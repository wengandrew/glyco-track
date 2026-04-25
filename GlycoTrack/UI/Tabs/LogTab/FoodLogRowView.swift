import SwiftUI

struct FoodLogRowView: View {
    @ObservedObject var entry: FoodLogEntry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Food emoji
            Text(FoodEmoji.resolve(entry: entry))
                .font(.system(size: 22))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.foodDescription.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    // Date + approximate hour (rounded down). Display-only — the
                    // underlying `entry.timestamp` is preserved at full precision so
                    // edits, sorts, and predicates work normally.
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.dateLabel(for: entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(Self.approximateHourLabel(for: entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(entry.quantity) (\(Int(entry.quantityGrams.rounded()))g)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("GL \(String(format: "%.1f", entry.computedGL))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(GLThresholdLevel.from(gl: entry.computedGL).color)

                    Text("CL \(String(format: "%+.2f", entry.computedCL))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(entry.computedCL < 0 ? .green : .red)

                    ConfidenceBadge(confidence: entry.confidenceScore, tier: entry.parsingMethod)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Display formatters

    /// "MM/dd/yyyy" for the entry's date. Display-only.
    private static func dateLabel(for timestamp: Date?) -> String {
        Self.dateFormatter.string(from: timestamp ?? Date())
    }

    /// Hour rounded DOWN to the nearest hour, formatted as "5pm" / "7am" / "12am".
    /// Display-only — does not mutate `entry.timestamp`.
    private static func approximateHourLabel(for timestamp: Date?) -> String {
        let date = timestamp ?? Date()
        let hour24 = Calendar.current.component(.hour, from: date) // 0…23
        let isAM = hour24 < 12
        let display12: Int = {
            if hour24 == 0 { return 12 }       // midnight
            if hour24 == 12 { return 12 }      // noon
            return hour24 > 12 ? hour24 - 12 : hour24
        }()
        return "\(display12)\(isAM ? "am" : "pm")"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f
    }()
}
