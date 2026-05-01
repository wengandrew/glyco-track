import SwiftUI

/// Settings pane content. Hosted inside `MoreSheet`'s segmented control —
/// no `NavigationView` wrapper here, the sheet owns nav chrome.
///
/// The only knob today is the daily GL budget — physician-prescribed targets
/// vary, so the bucket size needs to adapt. Stored in UserDefaults under
/// `AppSettings.dailyGLBudgetKey` and observed via `@AppStorage` everywhere
/// the bucket / heatmap / status chip render.
struct SettingsPaneView: View {
    @AppStorage(AppSettings.dailyGLBudgetKey)
    private var glBudget: Double = AppSettings.defaultDailyGLBudget

    var body: some View {
        Form {
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
