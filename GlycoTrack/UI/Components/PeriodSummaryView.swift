import SwiftUI

/// Unified summary card used by WeekTab and MonthTab.
/// Shows three stats side-by-side: Avg Daily GL, Total GL, Net CL.
/// Deliberately omits days-logged, high-GL warnings, and low-confidence
/// warnings — those belonged to period-specific stat views and were
/// collapsed into this shared card for visual consistency.
struct PeriodSummaryView: View {
    @Environment(\.appTheme) private var theme

    let title: String
    let entries: [FoodLogEntry]
    /// Number of days spanned by the period (e.g. 7 for a week, 28–31 for a
    /// month). If nil, inferred from the date range of `entries` — minimum 1
    /// to avoid division by zero.
    let daysInPeriod: Int?

    @AppStorage(AppSettings.dailyGLBudgetKey) private var glBudget: Double = AppSettings.defaultDailyGLBudget

    init(title: String, entries: [FoodLogEntry], daysInPeriod: Int? = nil) {
        self.title = title
        self.entries = entries
        self.daysInPeriod = daysInPeriod
    }

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    private var resolvedDayCount: Int {
        if let d = daysInPeriod, d > 0 { return d }
        let cal = Calendar.current
        let dayStarts = Set(entries.compactMap { entry -> Date? in
            guard let ts = entry.timestamp else { return nil }
            return cal.startOfDay(for: ts)
        })
        return max(dayStarts.count, 1)
    }

    private var avgDailyGL: Double { totalGL / Double(resolvedDayCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.subheadline, design: theme.fontDesign, weight: .semibold))

            HStack(spacing: theme == .organic ? 12 : 8) {
                StatChip(
                    label: "Avg Daily GL",
                    value: String(format: "%.0f", avgDailyGL),
                    color: glGradientColor(fraction: avgDailyGL / glBudget)
                )
                StatChip(
                    label: "Total GL",
                    value: String(format: "%.0f", totalGL),
                    color: .primary
                )
                StatChip(
                    label: "Net CL",
                    value: String(format: "%+.1f", netCL),
                    color: netCL < 0 ? theme.beneficialColor : theme.harmfulColor
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .fill(theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                        .stroke(theme.cardBorderColor, lineWidth: theme.cardBorderWidth)
                )
        )
    }
}
