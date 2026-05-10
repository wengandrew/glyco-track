import SwiftUI

enum AppTheme: String {
    case organic

    // MARK: - Colors

    var glAccent: Color { Color(.systemBlue) }
    var clAccent: Color { Color(.systemOrange) }
    var primaryAccent: Color { Color(.systemBlue) }
    var cardBackground: Color { Color(.secondarySystemGroupedBackground) }
    var pageBackground: Color { Color(.systemGroupedBackground) }
    var surfaceTint: Color { .clear }
    var beneficialColor: Color { Color(.systemGreen) }
    var harmfulColor: Color { Color(.systemRed) }

    // MARK: - Typography

    var fontDesign: Font.Design { .default }
    var metricFontDesign: Font.Design { .rounded }

    // MARK: - Geometry

    var cardCornerRadius: CGFloat { 16 }
    var chipCornerRadius: CGFloat { 10 }

    // MARK: - Card Style

    var cardShadowRadius: CGFloat { 6 }
    var cardShadowOpacity: Double { 0.06 }

    // MARK: - Tab Bar

    var tabBarUsesLabels: Bool { true }
    var tabBarMaterial: Material { .ultraThinMaterial }
    var recordButtonColor: Color { Color(.systemBlue) }

    // MARK: - Preferred color scheme

    var preferredColorScheme: ColorScheme? { nil }

    // MARK: - Greeting

    func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .organic
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
