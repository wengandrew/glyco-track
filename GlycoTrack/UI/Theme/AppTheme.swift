import SwiftUI

enum AppTheme: String {
    case organic

    // MARK: - Colors

    var glAccent: Color { Color(red: 0.55, green: 0.63, blue: 0.32) }
    var clAccent: Color { Color(red: 0.82, green: 0.50, blue: 0.25) }
    var primaryAccent: Color { Color(red: 0.55, green: 0.63, blue: 0.32) }
    var cardBackground: Color { Color(red: 0.98, green: 0.96, blue: 0.92) }
    var pageBackground: Color { Color(red: 0.96, green: 0.94, blue: 0.89) }
    var surfaceTint: Color { Color(red: 0.95, green: 0.90, blue: 0.80).opacity(0.15) }
    var beneficialColor: Color { Color(red: 0.40, green: 0.65, blue: 0.35) }
    var harmfulColor: Color { Color(red: 0.82, green: 0.40, blue: 0.30) }

    // MARK: - Typography

    var fontDesign: Font.Design { .default }
    var metricFontDesign: Font.Design { .rounded }

    // MARK: - Geometry

    var cardCornerRadius: CGFloat { 28 }
    var chipCornerRadius: CGFloat { 16 }

    // MARK: - Card Style

    var cardShadowRadius: CGFloat { 12 }
    var cardShadowOpacity: Double { 0.08 }

    // MARK: - Tab Bar

    var tabBarUsesLabels: Bool { true }
    var tabBarMaterial: Material { .ultraThinMaterial }
    var recordButtonColor: Color { Color(red: 0.55, green: 0.63, blue: 0.32) }

    // MARK: - Preferred color scheme

    var preferredColorScheme: ColorScheme? { .light }

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
