import SwiftUI
import CoreData

struct LogTabView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        predicate: NSPredicate(format: "isSoftDeleted == NO"),
        animation: .default
    )
    private var entries: FetchedResults<FoodLogEntry>

    @State private var selectedEntry: FoodLogEntry?
    @State private var showManualEntry = false

    var body: some View {
        NavigationView {
            List {
                ForEach(entries) { entry in
                    FoodLogRowView(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEntry = entry }
                }
                .onDelete(perform: softDelete)
            }
            .listStyle(.plain)
            .navigationTitle("Food Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                EditEntryView(entry: entry)
            }
            .sheet(isPresented: $showManualEntry) {
                ManualEntryView()
            }
        }
    }

    private func softDelete(at offsets: IndexSet) {
        let repo = FoodLogRepository(context: context)
        offsets.forEach { repo.softDelete(entries[$0]) }
    }
}

// MARK: - Edit Entry

struct EditEntryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: FoodLogEntry

    @State private var foodDescription: String
    @State private var quantity: String

    init(entry: FoodLogEntry) {
        self.entry = entry
        _foodDescription = State(initialValue: entry.foodDescription)
        _quantity = State(initialValue: entry.quantity)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Food") {
                    TextField("Food description", text: $foodDescription)
                    TextField("Quantity (e.g. 1 cup)", text: $quantity)
                }

                Section("Calculated Values (read-only)") {
                    LabeledContent("GL", value: String(format: "%.2f", entry.computedGL))
                    LabeledContent("CL", value: String(format: "%+.3f", entry.computedCL))
                    LabeledContent("Confidence", value: String(format: "%.0f%%", entry.confidenceScore * 100))
                    LabeledContent("Parsing Tier", value: "Tier \(entry.parsingMethod)")
                }

                if let refFood = entry.referenceFood {
                    Section("Reference") {
                        LabeledContent("Matched to", value: refFood)
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        guard !foodDescription.isEmpty else { return }

        let newGrams = resolveGrams()
        let match = NutritionalRepository(context: context).findBestMatch(for: foodDescription)
        let profile = match?.profile

        let glResult = GIEngine(database: GIDatabase(records: loadGIDatabase())).computeGL(
            foodName: foodDescription,
            quantityGrams: newGrams,
            carbsPer100g: profile?.carbsPer100g ?? 0
        )
        let clResult = CLEngine().computeCL(
            nutrition: NutritionInput(
                saturatedFatPer100g: profile?.saturatedFatPer100g ?? 0,
                transFatPer100g: profile?.transFatPer100g ?? 0,
                solubleFiberPer100g: profile?.solubleFiberPer100g ?? 0,
                pufaPer100g: profile?.pufaPer100g ?? 0,
                mufaPer100g: profile?.mufaPer100g ?? 0
            ),
            quantityGrams: newGrams
        )

        FoodLogRepository(context: context).update(
            entry,
            foodDescription: foodDescription,
            quantity: quantity,
            quantityGrams: newGrams,
            computedGL: glResult.gl,
            computedCL: clResult.cl
        )
        dismiss()
    }

    private func resolveGrams() -> Double {
        struct Parsed { let number: Double; let unit: String }

        func parse(_ text: String) -> Parsed? {
            let parts = text.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let first = parts.first, let num = Double(first) else { return nil }
            return Parsed(number: num, unit: parts.dropFirst().joined(separator: " ").lowercased())
        }

        guard let new = parse(quantity) else { return entry.quantityGrams }

        switch new.unit {
        case "g", "gram", "grams":
            return new.number
        case "kg", "kilogram", "kilograms":
            return new.number * 1000
        case "oz", "ounce", "ounces":
            return new.number * 28.35
        case "lb", "lbs", "pound", "pounds":
            return new.number * 453.6
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            return new.number
        default:
            // Non-metric unit (cup, slice, egg, etc.) — scale proportionally
            guard let old = parse(entry.quantity), old.number > 0 else { return entry.quantityGrams }
            return entry.quantityGrams * (new.number / old.number)
        }
    }

    private func loadGIDatabase() -> [GIRecord] {
        guard let url = Bundle.main.url(forResource: "gi_database", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([GIRecord].self, from: data)
        else { return [] }
        return records
    }
}

// MARK: - Manual Entry

struct ManualEntryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var processor = FoodLogProcessor()

    @State private var foodText: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("What did you eat?") {
                    TextEditor(text: $foodText)
                        .frame(height: 80)
                }

                if processor.isProcessing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Processing…")
                        }
                    }
                }

                if let err = processor.lastError {
                    Section {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await processor.process(transcript: foodText, context: context)
                            if processor.lastError == nil { dismiss() }
                        }
                    }
                    .disabled(foodText.isEmpty || processor.isProcessing)
                }
            }
        }
    }
}
