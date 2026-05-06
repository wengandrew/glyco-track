import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case clinical
    case organic
    case midnight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clinical: return "Clinical"
        case .organic:  return "Organic"
        case .midnight: return "Midnight"
        }
    }

    var description: String {
        switch self {
        case .clinical: return "Clean, data-forward, medical precision"
        case .organic:  return "Warm, inviting, wellness-focused"
        case .midnight: return "Dark, vibrant, modern dashboard"
        }
    }

    // MARK: - Colors

    var glAccent: Color {
        switch self {
        case .clinical: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .organic:  return Color(red: 0.55, green: 0.63, blue: 0.32)
        case .midnight: return Color(red: 0.0, green: 0.85, blue: 0.95)
        }
    }

    var clAccent: Color {
        switch self {
        case .clinical: return Color(red: 0.90, green: 0.26, blue: 0.32)
        case .organic:  return Color(red: 0.82, green: 0.50, blue: 0.25)
        case .midnight: return Color(red: 0.95, green: 0.25, blue: 0.60)
        }
    }

    var primaryAccent: Color {
        switch self {
        case .clinical: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .organic:  return Color(red: 0.55, green: 0.63, blue: 0.32)
        case .midnight: return Color(red: 0.35, green: 0.45, blue: 1.0)
        }
    }

    var cardBackground: Color {
        switch self {
        case .clinical: return Color(.secondarySystemBackground)
        case .organic:  return Color(red: 0.98, green: 0.96, blue: 0.92)
        case .midnight: return Color(white: 0.11)
        }
    }

    var cardBackgroundAdaptive: Color {
        switch self {
        case .clinical: return Color(.secondarySystemBackground)
        case .organic:  return Color(.secondarySystemBackground)
        case .midnight: return Color(white: 0.11)
        }
    }

    var pageBackground: Color {
        switch self {
        case .clinical: return Color(.systemBackground)
        case .organic:  return Color(red: 0.96, green: 0.94, blue: 0.89)
        case .midnight: return Color(red: 0.06, green: 0.06, blue: 0.08)
        }
    }

    var surfaceTint: Color {
        switch self {
        case .clinical: return .clear
        case .organic:  return Color(red: 0.95, green: 0.90, blue: 0.80).opacity(0.15)
        case .midnight: return Color.white.opacity(0.04)
        }
    }

    var beneficialColor: Color {
        switch self {
        case .clinical: return Color(red: 0.20, green: 0.72, blue: 0.45)
        case .organic:  return Color(red: 0.40, green: 0.65, blue: 0.35)
        case .midnight: return Color(red: 0.20, green: 0.90, blue: 0.50)
        }
    }

    var harmfulColor: Color {
        switch self {
        case .clinical: return Color(red: 0.90, green: 0.26, blue: 0.32)
        case .organic:  return Color(red: 0.82, green: 0.40, blue: 0.30)
        case .midnight: return Color(red: 1.0, green: 0.30, blue: 0.40)
        }
    }

    // MARK: - Typography

    var fontDesign: Font.Design {
        switch self {
        case .clinical: return .default
        case .organic:  return .rounded
        case .midnight: return .default
        }
    }

    var metricFontDesign: Font.Design {
        switch self {
        case .clinical: return .monospaced
        case .organic:  return .rounded
        case .midnight: return .monospaced
        }
    }

    // MARK: - Geometry

    var cardCornerRadius: CGFloat {
        switch self {
        case .clinical: return 16
        case .organic:  return 28
        case .midnight: return 20
        }
    }

    var chipCornerRadius: CGFloat {
        switch self {
        case .clinical: return 10
        case .organic:  return 16
        case .midnight: return 12
        }
    }

    // MARK: - Card Style

    var cardBorderWidth: CGFloat {
        switch self {
        case .clinical: return 0
        case .organic:  return 0
        case .midnight: return 0.5
        }
    }

    var cardBorderColor: Color {
        switch self {
        case .clinical: return .clear
        case .organic:  return .clear
        case .midnight: return Color.white.opacity(0.08)
        }
    }

    var cardShadowRadius: CGFloat {
        switch self {
        case .clinical: return 2
        case .organic:  return 12
        case .midnight: return 0
        }
    }

    var cardShadowOpacity: Double {
        switch self {
        case .clinical: return 0.06
        case .organic:  return 0.08
        case .midnight: return 0
        }
    }

    var showsLeftAccent: Bool {
        self == .clinical
    }

    // MARK: - Tab Bar

    var tabBarUsesLabels: Bool {
        switch self {
        case .clinical: return false
        case .organic:  return true
        case .midnight: return false
        }
    }

    var tabBarMaterial: Material {
        switch self {
        case .clinical: return .regularMaterial
        case .organic:  return .ultraThinMaterial
        case .midnight: return .ultraThinMaterial
        }
    }

    var recordButtonColor: Color {
        switch self {
        case .clinical: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .organic:  return Color(red: 0.55, green: 0.63, blue: 0.32)
        case .midnight: return Color(red: 0.35, green: 0.45, blue: 1.0)
        }
    }

    // MARK: - Preferred color scheme

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .clinical: return nil
        case .organic:  return .light
        case .midnight: return .dark
        }
    }

    // MARK: - Greeting

    func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch self {
        case .clinical:
            return "Dashboard"
        case .organic:
            if hour < 12 { return "Good morning" }
            if hour < 17 { return "Good afternoon" }
            return "Good evening"
        case .midnight:
            return "Today"
        }
    }

    // MARK: - Daily insight

    func dailyInsight(totalGL: Double, budget: Double, netCL: Double, entryCount: Int) -> String? {
        guard entryCount > 0 else { return nil }
        let fraction = totalGL / budget
        switch self {
        case .clinical:
            if fraction > 1.0 {
                return "GL budget exceeded by \(Int((fraction - 1.0) * 100))%"
            } else if fraction > 0.8 {
                return "Approaching GL budget (\(Int(fraction * 100))% used)"
            }
            return nil
        case .organic:
            if fraction < 0.5 && netCL < 0 {
                return "Great balance today! Keep it up."
            } else if fraction > 1.0 {
                return "You've gone over your GL target. Consider lighter options."
            } else if netCL > 2 {
                return "CL is running high. Try adding some fiber."
            }
            return "You're doing well. \(Int((1.0 - fraction) * 100))% GL budget remaining."
        case .midnight:
            return "\(Int(fraction * 100))% GL \u{2022} \(entryCount) logged"
        }
    }
}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = {
        let raw = UserDefaults.standard.string(forKey: "appTheme") ?? ""
        return AppTheme(rawValue: raw) ?? .clinical
    }()
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    @Published var current: AppTheme {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "appTheme") }
    }

    static let shared = ThemeManager()

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appTheme") ?? ""
        self.current = AppTheme(rawValue: raw) ?? .clinical
    }
}
