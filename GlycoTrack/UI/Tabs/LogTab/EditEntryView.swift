import SwiftUI
import CoreData

struct EditEntryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: FoodLogEntry
    let onDelete: (() -> Void)?

    @State private var foodDescription: String
    @State private var quantity: String
    @State private var editedTimestamp: Date
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false

    init(entry: FoodLogEntry, onDelete: (() -> Void)? = nil) {
        self.entry = entry
        self.onDelete = onDelete
        _foodDescription = State(initialValue: entry.foodDescription)
        _quantity = State(initialValue: entry.quantity)
        _editedTimestamp = State(initialValue: entry.timestamp ?? Date())
    }

    private var matchLabel: String {
        let tier = MatchTier(rawValue: entry.parsingMethod)
        if tier == .unrecognized { return "Not recognized" }
        let pct = Int((entry.confidenceScore * 100).rounded())
        return "\(pct)% confidence"
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Food") {
                    TextField("Food description", text: $foodDescription)
                    TextField("Quantity (e.g. 1 cup)", text: $quantity)
                    DatePicker(
                        "Date & time",
                        selection: $editedTimestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.locale, .current)
                }

                Section("Calculated Values (read-only)") {
                    LabeledContent("GL", value: String(format: "%.2f", entry.computedGL))
                    LabeledContent("CL", value: String(format: "%+.3f", entry.computedCL))
                    LabeledContent("Match", value: matchLabel)
                }

                if let refFood = entry.referenceFood {
                    Section("Reference") {
                        LabeledContent("Matched to", value: refFood)
                    }
                }

                if !entry.rawTranscript.isEmpty {
                    Section("Original Transcript") {
                        Text(entry.rawTranscript)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete Entry")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    FoodLogRepository(context: context).softDelete(entry)
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("This entry will be removed from your log.")
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
        }
    }

    private func save() {
        guard !foodDescription.isEmpty, !isSaving else { return }
        isSaving = true
        Task { await performSave() }
    }

    @MainActor
    private func performSave() async {
        let newGrams = resolveGrams()

        // Route through the full cascade so composite dishes ("beef noodle
        // soup") recompute correctly on edit too. Decomposition may hit the
        // Claude API — the Save button remains enabled; the sheet dismisses
        // once the recompute is done.
        let client = ClaudeAPIClient(apiKey: APIKey.claude)
        let parser = TranscriptParser(client: client)
        let matcher = FoodMatcher(repo: NutritionalRepository(context: context), parser: parser)

        let parsed = ParsedFood(food: foodDescription, quantity: quantity, unit: "", grams: newGrams)
        let resolution = await matcher.resolve(food: parsed)

        // Round timestamp to nearest 30 minutes — SwiftUI's DatePicker in a
        // Form style doesn't expose minuteInterval, so enforce at Save.
        let rounded = Date(
            timeIntervalSince1970: (editedTimestamp.timeIntervalSince1970 / 1800).rounded() * 1800
        )
        entry.timestamp = rounded

        FoodLogRepository(context: context).update(
            entry,
            foodDescription: foodDescription,
            quantity: quantity,
            quantityGrams: newGrams,
            computedGL: resolution.totalGL,
            computedCL: resolution.totalCL,
            confidenceScore: resolution.confidence,
            parsingMethod: resolution.tier.rawValue,
            referenceFood: .some(resolution.matchSummary),
            nutritionalProfile: .some(resolution.primaryProfile)
        )
        isSaving = false
        dismiss()
    }

    private func resolveGrams() -> Double {
        struct Parsed { let number: Double; let unit: String }

        // Handles "300g", "300 g", "2 cups", "1.5  cups" — numeric prefix plus optional unit suffix.
        func parse(_ text: String) -> Parsed? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let scanner = Scanner(string: trimmed)
            guard let num = scanner.scanDouble() else { return nil }
            let remainder = String(trimmed[scanner.currentIndex...])
            let unit = remainder.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return Parsed(number: num, unit: unit)
        }

        // Loose plural comparison so "cup" and "cups" match.
        func normalize(_ unit: String) -> String {
            unit.hasSuffix("s") ? String(unit.dropLast()) : unit
        }

        guard let new = parse(quantity) else { return entry.quantityGrams }

        switch new.unit {
        case "g", "gram", "grams":
            return new.number
        case "kg", "kilogram", "kilograms":
            return new.number * 1000
        case "oz", "ounce", "ounces":
            return new.number * 28.349523125
        case "lb", "lbs", "pound", "pounds":
            return new.number * 453.59237
        default:
            // Non-mass unit (cup, slice, egg, mL, etc.). Only ratio-scale when the unit
            // is unchanged or the user omitted it — cross-unit scaling (e.g. g → cups)
            // produces nonsense. mL is volume and requires a per-food density to convert.
            guard let old = parse(entry.quantity), old.number > 0 else { return entry.quantityGrams }
            let sameUnit = new.unit.isEmpty || normalize(old.unit) == normalize(new.unit)
            guard sameUnit else { return entry.quantityGrams }
            return entry.quantityGrams * (new.number / old.number)
        }
    }
}
