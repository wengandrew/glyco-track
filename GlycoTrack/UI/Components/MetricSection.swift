import SwiftUI

/// Themed card wrapping a GL or CL visualization section. Used on HomeTabView
/// for both the Glycemic Load and Cholesterol Load panels.
struct MetricSection<Content: View, Trailing: View>: View {
    @Environment(\.appTheme) private var theme

    let title: String
    let subtitle: String
    let accent: Color
    let icon: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 36, height: 36)
                        .shadow(color: accent.opacity(0.25), radius: 4, x: 0, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.title2, design: theme.fontDesign, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subtitle.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .tracking(0.6)
                        .foregroundColor(.secondary)
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            content()
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .fill(theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                            .fill(theme.surfaceTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                            .stroke(accent.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(
                        color: Color.black.opacity(theme.cardShadowOpacity),
                        radius: theme.cardShadowRadius,
                        x: 0,
                        y: 6
                    )
            }
        )
        .padding(.horizontal, 12)
    }
}

extension MetricSection where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String,
        accent: Color,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.icon = icon
        self.trailing = { EmptyView() }
        self.content = content
    }
}
