import SwiftUI
import CoreData

struct ManualEntryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var processor = FoodLogProcessor()

    @State private var foodText: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Type what you ate (manual entry)") {
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
