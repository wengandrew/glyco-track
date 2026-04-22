import SwiftUI

/// Detail sheet shown when a user taps a food bubble in any visualization.
struct FoodEntryDetailSheet: View {
    let entry: FoodLogEntry
    @Environment(\.dismiss) private var dismiss

    private var group: FoodGroup { FoodGroup.from(string: entry.foodGroup) }
    private var glLevel: GLThresholdLevel { GLThresholdLevel.from(gl: entry.computedGL) }
    private var clIsBeneficial: Bool { entry.computedCL < 0 }

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
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(group.color)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "fork.knife")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .semibold))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodDescription)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Circle().fill(group.color).frame(width: 7, height: 7)
                    Text(group.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
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
            if let ts = entry.timestamp {
                detailRow("Logged", ts.formatted(date: .abbreviated, time: .shortened))
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
