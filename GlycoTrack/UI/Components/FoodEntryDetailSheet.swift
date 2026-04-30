import SwiftUI

/// Detail sheet shown when a user taps a food bubble in any visualization,
/// or a row in the Log tab. Presents a read-only summary and an Edit button
/// that opens `EditEntryView`.
struct FoodEntryDetailSheet: View {
    @ObservedObject var entry: FoodLogEntry
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit: Bool = false
    @State private var showPicker: Bool = false

    private var glLevel: GLThresholdLevel { GLThresholdLevel.from(gl: entry.computedGL) }
    private var clIsBeneficial: Bool { entry.computedCL < 0 }

    /// True for any entry whose match the matcher itself flagged as imperfect:
    /// unrecognized (T5) or any tier with confidence below 0.70. Drives the
    /// "Refine" toolbar button so high-confidence direct hits don't clutter
    /// the toolbar with an option that almost no user would reach for.
    private var canRefine: Bool {
        entry.parsingMethod == MatchTier.unrecognized.rawValue
            || entry.confidenceScore < 0.70
    }

    private var timestampText: String {
        guard let ts = entry.timestamp else { return "" }
        return ts.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    HStack(spacing: 12) {
                        metricCard(
                            title: "Glycemic Load",
                            value: String(format: "%.1f", entry.computedGL),
                            subtitle: glLevel.label,
                            color: glLevel.color,
                            icon: "drop.fill"
                        )
                        metricCard(
                            title: "Cholesterol Load",
                            value: String(format: "%+.2f", entry.computedCL),
                            subtitle: clIsBeneficial ? "Beneficial" : (entry.computedCL > 0 ? "Harmful" : "Neutral"),
                            color: clIsBeneficial ? .green : (entry.computedCL > 0 ? .red : .gray),
                            icon: "heart.fill"
                        )
                    }

                    detailsSection

                    if !entry.rawTranscript.isEmpty {
                        transcriptSection
                    }
                }
                .padding()
            }
            .navigationTitle("Food Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEdit = true
                        } label: {
                            Label("Edit details", systemImage: "pencil")
                        }
                        if canRefine {
                            Button {
                                showPicker = true
                            } label: {
                                Label("Refine match", systemImage: "wand.and.stars")
                            }
                        }
                    } label: {
                        // Single trailing button collapses Edit + Refine when
                        // both are available, so the toolbar stays calm on a
                        // narrow detail sheet. Falls back to a plain Edit
                        // glyph + tap-to-menu for high-confidence rows.
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More actions")
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                NavigationStack {
                    EditEntryView(entry: entry)
                }
            }
            .sheet(isPresented: $showPicker) {
                FoodPickerView { profile in
                    EntryRefiner.refine(entry: entry, to: profile, context: context)
                }
                .environment(\.managedObjectContext, context)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(width: 84, height: 84)
                    Text(FoodEmoji.resolve(entry: entry))
                        .font(.system(size: 56))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.foodDescription)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                    if !timestampText.isEmpty {
                        Text(timestampText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details").font(.subheadline.weight(.semibold))
            detailRow("Quantity", entry.quantity.isEmpty ? "—" : entry.quantity)
            if entry.quantityGrams > 0 {
                detailRow("Grams", String(format: "%.0f g", entry.quantityGrams))
            }
            detailRow("Confidence", confidenceLabel)
            if let ref = entry.referenceFood, !ref.isEmpty {
                detailRow("Matched food", ref)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var confidenceLabel: String {
        let tier = MatchTier(rawValue: entry.parsingMethod)
        if tier == .unrecognized {
            return "Not recognized — GL and CL set to 0"
        }
        let pct = Int((entry.confidenceScore * 100).rounded())
        let tierName = tier?.longLabel ?? "Unknown"
        return "\(pct)% · \(tierName) (T\(entry.parsingMethod))"
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You said").font(.subheadline.weight(.semibold))
            Text("\u{201C}\(entry.rawTranscript)\u{201D}")
                .font(.callout)
                .italic()
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}
