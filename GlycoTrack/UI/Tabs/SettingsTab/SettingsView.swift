import SwiftUI

/// Settings pane content. Hosted inside `MoreSheet`'s segmented control —
/// no `NavigationView` wrapper here, the sheet owns nav chrome.
struct SettingsPaneView: View {
    @AppStorage(AppSettings.dailyGLBudgetKey)
    private var glBudget: Double = AppSettings.defaultDailyGLBudget
    @AppStorage(AppSettings.physicsGravityKey)
    private var physicsGravity: Double = AppSettings.defaultPhysicsGravity
    @AppStorage(AppSettings.physicsHapticsKey)
    private var physicsHaptics: Double = AppSettings.defaultPhysicsHaptics

    var body: some View {
        Form {
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

            // MARK: Physics Sandbox
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Gravity")
                        Spacer()
                        Text(String(format: "%.1f", physicsGravity))
                            .font(.body.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $physicsGravity,
                        in: AppSettings.physicsGravityRange,
                        step: 0.5
                    )
                    .accessibilityLabel("Gravity strength")
                    .accessibilityValue(String(format: "%.1f", physicsGravity))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Vibration")
                        Spacer()
                        Text(physicsHaptics == 0 ? "Off" : String(format: "%.0f%%", physicsHaptics * 100))
                            .font(.body.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $physicsHaptics,
                        in: AppSettings.physicsHapticsRange,
                        step: 0.1
                    )
                    .accessibilityLabel("Vibration intensity")
                    .accessibilityValue(physicsHaptics == 0 ? "Off" : String(format: "%.0f%%", physicsHaptics * 100))
                }
            } header: {
                Text("Physics Sandbox")
            } footer: {
                Text("Controls how the food items behave in the bucket and balance scale. Higher gravity makes objects fall and roll faster. Vibration triggers a haptic tap when items land.")
                    .font(.footnote)
            }
        }
    }
}
