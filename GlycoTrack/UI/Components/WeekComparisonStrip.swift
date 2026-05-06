import SwiftUI

/// Compact comparison strip: this period vs the prior period of the same
/// length. Shows deltas for Avg Daily GL, Total GL, and Net CL. Renders
/// nothing when the prior period has no data (showing "↑ 100% from zero"
/// would be misleading after a fresh install or a long break).
///
/// Today only used by the Week tab, but kept here in `UI/Components/` so a
/// "Month vs prior Month" use case can reuse it without churn.
struct WeekComparisonStrip: View {
    let currentEntries: [FoodLogEntry]
    let priorEntries: [FoodLogEntry]
    /// Number of days in either period — same on both sides (a week is 7 days
    /// regardless of how many were logged). Drives the avg-daily denominator.
    let daysInPeriod: Int

    var body: some View {
        if priorEntries.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                deltaCell(label: "Avg GL",
                          delta: avgDailyGL(currentEntries) - avgDailyGL(priorEntries),
                          format: "%+.0f",
                          direction: .lowerIsBetter)
                deltaCell(label: "Total GL",
                          delta: totalGL(currentEntries) - totalGL(priorEntries),
                          format: "%+.0f",
                          direction: .lowerIsBetter)
                deltaCell(label: "Net CL",
                          delta: netCL(currentEntries) - netCL(priorEntries),
                          format: "%+.1f",
                          // More-negative CL is more beneficial, so a
                          // negative delta is an improvement.
                          direction: .lowerIsBetter)
            }
        }
    }

    // MARK: - Helpers

    private enum Direction {
        case lowerIsBetter
        case higherIsBetter
    }

    private func deltaCell(label: String, delta: Double, format: String, direction: Direction) -> some View {
        let isFlat = abs(delta) < 0.05
        let isImprovement: Bool = {
            guard !isFlat else { return false }
            switch direction {
            case .lowerIsBetter: return delta < 0
            case .higherIsBetter: return delta > 0
            }
        }()
        let color: Color = isFlat ? .secondary : (isImprovement ? .green : .red)
        let arrow: String = isFlat ? "minus" : (delta > 0 ? "arrow.up" : "arrow.down")

        return VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 3) {
                Image(systemName: arrow)
                    .font(.caption2.weight(.semibold))
                Text(String(format: format, delta))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(label: label, delta: delta, format: format, isFlat: isFlat, isImprovement: isImprovement))
    }

    private func accessibilityLabel(label: String, delta: Double, format: String, isFlat: Bool, isImprovement: Bool) -> String {
        let kind = isFlat ? "unchanged" : (isImprovement ? "improvement" : "regression")
        return "\(label) change vs previous week: \(String(format: format, delta)). \(kind)."
    }

    private func totalGL(_ entries: [FoodLogEntry]) -> Double {
        entries.reduce(0) { $0 + $1.computedGL }
    }

    private func netCL(_ entries: [FoodLogEntry]) -> Double {
        entries.reduce(0) { $0 + $1.computedCL }
    }

    private func avgDailyGL(_ entries: [FoodLogEntry]) -> Double {
        totalGL(entries) / Double(max(daysInPeriod, 1))
    }
}
