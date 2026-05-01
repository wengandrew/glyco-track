import SwiftUI
import CoreData

/// Debug pane content. Hosted inside `MoreSheet`'s segmented control — no
/// `NavigationStack` wrapper here. The pane exposes its export action via
/// the binding `exportRequested` so `MoreSheet`'s toolbar button can trigger it.
struct DebugPaneView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodLogEntry.timestamp, ascending: false)],
        predicate: nil
    ) private var foodLogs: FetchedResults<FoodLogEntry>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NutritionalProfile.foodName, ascending: true)]
    ) private var profiles: FetchedResults<NutritionalProfile>

    @State private var exportPayload: String?
    @State private var showShareSheet = false

    /// Bindable trigger for the export action — MoreSheet's toolbar Export
    /// button bumps the bool, which we observe and act on. Cleaner than
    /// hoisting a closure through the NavigationView.
    @Binding var exportRequested: Bool

    init(exportRequested: Binding<Bool> = .constant(false)) {
        self._exportRequested = exportRequested
    }

    var body: some View {
        List {
            buildInfoSection
            statsSection
            foodLogSection
            nutritionalProfileSection
        }
        .sheet(isPresented: $showShareSheet) {
            if let payload = exportPayload {
                ShareSheet(items: [payload])
            }
        }
        .onChange(of: exportRequested) { newValue in
            guard newValue else { return }
            buildExport()
            exportRequested = false
        }
    }

    // MARK: - Sections

    private var buildInfoSection: some View {
        Section("Build Info") {
            LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
            LabeledContent("Branch", value: AppInfo.gitBranch)
            LabeledContent("Commit", value: AppInfo.gitCommit)
            LabeledContent("Built", value: AppInfo.buildTimestamp)
            LabeledContent("Last data update", value: lastDataUpdateDisplay)
        }
    }

    private var lastDataUpdateDisplay: String {
        let latest = foodLogs
            .lazy
            .filter { !$0.isSoftDeleted }
            .compactMap { $0.timestamp }
            .max()
        guard let latest else { return "never" }
        return latest.formatted(date: .abbreviated, time: .shortened)
    }

    private var statsSection: some View {
        Section("Summary") {
            LabeledContent("Food Log Entries", value: "\(foodLogs.count)")
            LabeledContent("  — soft deleted", value: "\(foodLogs.filter { $0.isSoftDeleted }.count)")
            LabeledContent("Nutritional Profiles", value: "\(profiles.count)")
        }
    }

    private var foodLogSection: some View {
        Section("Food Log (most recent first)") {
            if foodLogs.isEmpty {
                Text("No entries").foregroundStyle(.secondary)
            } else {
                ForEach(foodLogs.prefix(50), id: \.objectID) { entry in
                    DebugFoodLogRow(entry: entry)
                }
                if foodLogs.count > 50 {
                    Text("… \(foodLogs.count - 50) more (export for full list)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    private var nutritionalProfileSection: some View {
        Section("Nutritional Profiles (first 20)") {
            if profiles.isEmpty {
                Text("No profiles").foregroundStyle(.secondary)
            } else {
                ForEach(profiles.prefix(20), id: \.objectID) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.foodName).font(.caption.bold())
                        Text("GI: \(profile.glycemicIndex)  carbs: \(profile.carbsPer100g, specifier: "%.1f")g/100g")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                if profiles.count > 20 {
                    Text("… \(profiles.count - 20) more (export for full list)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Export

    private func buildExport() {
        var root: [String: Any] = [:]
        root["exportedAt"] = ISO8601DateFormatter().string(from: Date())

        let fmt = ISO8601DateFormatter()
        root["foodLogEntries"] = foodLogs.map { e -> [String: Any] in
            [
                "id":                 e.id?.uuidString ?? "nil",
                "timestamp":          e.timestamp.map { fmt.string(from: $0) } ?? "nil",
                "loggedAt":           e.loggedAt.map { fmt.string(from: $0) } ?? "nil",
                "foodDescription":    e.foodDescription,
                "quantity":           e.quantity,
                "quantityGrams":      e.quantityGrams,
                "rawTranscript":      e.rawTranscript,
                "parsingMethod":      e.parsingMethod,
                "confidenceScore":    e.confidenceScore,
                "referenceFood":      e.referenceFood ?? "nil",
                "computedGL":         e.computedGL,
                "computedCL":         e.computedCL,
                "isEdited":           e.isEdited,
                "isSoftDeleted":      e.isSoftDeleted,
                "nutritionalProfile": e.nutritionalProfile?.foodName ?? "nil"
            ]
        }

        root["nutritionalProfiles"] = profiles.map { p -> [String: Any] in
            [
                "id":                  p.id?.uuidString ?? "nil",
                "foodName":            p.foodName,
                "glycemicIndex":       p.glycemicIndex,
                "carbsPer100g":        p.carbsPer100g,
                "solubleFiberPer100g": p.solubleFiberPer100g,
                "saturatedFatPer100g": p.saturatedFatPer100g,
                "transFatPer100g":     p.transFatPer100g,
                "pufaPer100g":         p.pufaPer100g,
                "mufaPer100g":         p.mufaPer100g,
                "giSource":            p.giSource,
                "nutritionSource":     p.nutritionSource
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            exportPayload = json
            showShareSheet = true
        }
    }
}

// MARK: - Sub-views

private struct DebugFoodLogRow: View {
    let entry: FoodLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.foodDescription)
                    .font(.caption.bold())
                    .strikethrough(entry.isSoftDeleted)
                Spacer()
                Text(entry.timestamp.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("qty: \(entry.quantity)")
                Text("GL: \(entry.computedGL, specifier: "%.1f")")
                Text("CL: \(entry.computedCL, specifier: "%.1f")")
                Text("conf: \(entry.confidenceScore, specifier: "%.2f")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let profile = entry.nutritionalProfile?.foodName {
                Text("↳ \(profile)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
