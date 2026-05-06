import SwiftUI

struct FoodLogRowView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var entry: FoodLogEntry

    private var glColor: Color {
        let level = GLThresholdLevel.from(gl: entry.computedGL)
        switch level {
        case .low:    return theme.beneficialColor
        case .medium: return .orange
        case .high:   return theme.harmfulColor
        }
    }

    private var emojiBackgroundColor: Color {
        switch theme {
        case .organic:  return Color(.systemGray6)
        case .midnight: return Color.white.opacity(0.06)
        case .clinical: return .clear
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Food emoji — slightly larger with background for organic/midnight
            Text(FoodEmoji.resolve(entry: entry))
                .font(.system(size: theme == .clinical ? 22 : 24))
                .frame(width: theme == .clinical ? 28 : 36, height: theme == .clinical ? 28 : 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(emojiBackgroundColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.foodDescription.capitalized)
                        .font(.system(.subheadline, design: theme.fontDesign, weight: .medium))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.dateLabel(for: entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(Self.timeLabel(for: entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(entry.quantity) (\(Int(entry.quantityGrams.rounded()))g)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("GL \(String(format: "%.1f", entry.computedGL))")
                        .font(.system(size: 11, weight: .medium, design: theme.metricFontDesign))
                        .foregroundColor(glColor)

                    Text("CL \(String(format: "%+.2f", entry.computedCL))")
                        .font(.system(size: 11, weight: .medium, design: theme.metricFontDesign))
                        .foregroundColor(entry.computedCL < 0 ? theme.beneficialColor : theme.harmfulColor)

                    ConfidenceBadge(confidence: entry.confidenceScore, tier: entry.parsingMethod)
                }
            }
        }
        .padding(.vertical, theme == .organic ? 6 : 4)
    }

    // MARK: - Display formatters

    /// "MM/dd/yyyy" for the entry's date. Display-only.
    private static func dateLabel(for timestamp: Date?) -> String {
        DateFormatter.numericMonthDayYear.string(from: timestamp ?? Date())
    }

    /// Minute-precision time, formatted as "7:34pm" / "12:05am". Display-only.
    private static func timeLabel(for timestamp: Date?) -> String {
        DateFormatter.hourMinute.string(from: timestamp ?? Date())
    }

}
