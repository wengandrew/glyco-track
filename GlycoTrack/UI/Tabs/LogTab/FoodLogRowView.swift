import SwiftUI

struct FoodLogRowView: View {
    let entry: FoodLogEntry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Food group dot
            Circle()
                .fill(FoodGroup.from(string: entry.foodGroup).color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.foodDescription.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Text(entry.quantity)
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
}
