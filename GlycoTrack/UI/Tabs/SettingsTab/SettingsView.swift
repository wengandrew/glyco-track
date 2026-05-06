import SwiftUI

/// Settings pane content. Hosted inside `MoreSheet`'s segmented control —
/// no `NavigationView` wrapper here, the sheet owns nav chrome.
struct SettingsPaneView: View {
    @AppStorage(AppSettings.dailyGLBudgetKey)
    private var glBudget: Double = AppSettings.defaultDailyGLBudget

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Form {
            // MARK: Theme Picker
            Section {
                ForEach(AppTheme.allCases) { t in
                    ThemeOptionRow(theme: t, isSelected: themeManager.current == t) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            themeManager.current = t
                        }
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Theme affects colors, typography, spacing, and layout. Changes apply immediately.")
                    .font(.footnote)
            }

            // MARK: GL Budget
            Section {
                HStack {
                    Text("Daily GL Budget")
                    Spacer()
                    Text("\(Int(glBudget))")
                        .font(.body.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Stepper(
                    value: $glBudget,
                    in: AppSettings.dailyGLBudgetRange,
                    step: AppSettings.dailyGLBudgetStep
                ) {
                    Text("Adjust")
                }
                .accessibilityLabel("Daily GL budget")
                .accessibilityValue("\(Int(glBudget)) glycemic load units")
            } header: {
                Text("Glycemic Load")
            } footer: {
                Text("""
The bucket on the Today tab fills at \(Int(glBudget)) GL — anything above spills over the rim. The Month tab heatmap and the Total GL chip on the Today tab also scale to this number. Public-health "moderate GL day" guidance is around 100; a physician may prescribe lower (60–80) for tighter glucose control or higher (120–150) for athletes.
""")
                    .font(.footnote)
            }

            if glBudget != AppSettings.defaultDailyGLBudget {
                Section {
                    Button(role: .destructive) {
                        glBudget = AppSettings.defaultDailyGLBudget
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Reset to default (\(Int(AppSettings.defaultDailyGLBudget)))")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Theme Option Row

private struct ThemeOptionRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Color preview swatch
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.glAccent)
                        .frame(width: 12, height: 28)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.clAccent)
                        .frame(width: 12, height: 28)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.cardBackground)
                        .frame(width: 12, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemGray6))
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(theme.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(theme.primaryAccent)
                        .font(.title3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
