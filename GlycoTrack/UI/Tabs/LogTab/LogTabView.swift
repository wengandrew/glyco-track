import SwiftUI
import CoreData

struct LogTabView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        predicate: NSPredicate(format: "isDeleted == NO"),
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
        let repo = FoodLogRepository(context: context)
        repo.update(
            entry,
            foodDescription: foodDescription,
            quantity: quantity,
            quantityGrams: entry.quantityGrams,
            computedGL: entry.computedGL,
            computedCL: entry.computedCL
        )
        dismiss()
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
