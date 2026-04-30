import SwiftUI
import CoreData

/// Search-style picker over `NutritionalProfile`. Used by the Refine flow on
/// FoodEntryDetailSheet to let the user promote a low-confidence entry to a
/// known reference food in two taps.
///
/// Returns the chosen profile via `onSelect` and dismisses itself. The caller
/// is responsible for re-linking the entry and recomputing GL/CL — see
/// `EntryRefiner.refine(entry:to:context:)`.
struct FoodPickerView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let onSelect: (NutritionalProfile) -> Void

    @State private var query: String = ""
    @State private var results: [NutritionalProfile] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
                resultsList
            }
            .navigationTitle("Pick a food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { reload() }
            .onChange(of: query) { _ in reload() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search foods", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var resultsList: some View {
        List(results, id: \.objectID) { profile in
            Button {
                onSelect(profile)
                dismiss()
            } label: {
                row(for: profile)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func row(for profile: NutritionalProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.foodName)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                Text(metaLine(for: profile))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private func metaLine(for profile: NutritionalProfile) -> String {
        var parts: [String] = []
        if profile.glycemicIndex > 0 {
            parts.append("GI \(profile.glycemicIndex)")
        }
        if profile.carbsPer100g > 0 {
            parts.append("\(Int(profile.carbsPer100g.rounded()))g carbs / 100g")
        }
        return parts.isEmpty ? "Reference food" : parts.joined(separator: " · ")
    }

    private func reload() {
        let request = NutritionalProfile.fetchRequest()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // Case-insensitive contains. CONTAINS[cd] handles both case and
            // diacritic insensitivity so 'jalapeño' matches 'jalapeno'.
            request.predicate = NSPredicate(format: "foodName CONTAINS[cd] %@", trimmed)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "foodName", ascending: true)]
        // Cap unfiltered results so the list doesn't render all ~780 rows when
        // the user just opened the sheet — type-to-narrow is the expected flow.
        request.fetchLimit = trimmed.isEmpty ? 80 : 200
        results = (try? context.fetch(request)) ?? []
    }
}
