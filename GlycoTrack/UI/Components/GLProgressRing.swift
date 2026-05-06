import SwiftUI

/// Circular progress ring showing GL total vs budget.
/// Used by the Clinical theme as the trailing element in the GL MetricSection.
struct GLProgressRing: View {
    @Environment(\.appTheme) private var theme
    let total: Double
    let budget: Double

    private var safeBudget: Double { max(budget, 1) }
    private var fraction: Double { min(total / safeBudget, 1.0) }
    private var isOver: Bool { total > safeBudget }

    private var ringColor: Color {
        if isOver { return theme.harmfulColor }
        if fraction > 0.8 { return .orange }
        return theme.glAccent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
                .frame(width: 40, height: 40)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: fraction)

            Text(isOver ? "!" : "\(Int(fraction * 100))%")
                .font(.system(size: isOver ? 14 : 9, weight: .bold, design: theme.metricFontDesign))
                .foregroundColor(ringColor)
        }
    }
}
