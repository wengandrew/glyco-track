import SwiftUI

enum GLThresholdLevel {
    case low    // ≤ 10
    case medium // 11–19
    case high   // ≥ 20

    static func from(gl: Double) -> GLThresholdLevel {
        if gl <= 10 { return .low }
        if gl <= 19 { return .medium }
        return .high
    }

    var label: String {
        switch self {
        case .low:    return "Low GL"
        case .medium: return "Medium GL"
        case .high:   return "High GL"
        }
    }

    var color: Color {
        switch self {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

/// Convenience accessor for non-view code (used as a `Double` rather than a
/// view-bound `@AppStorage`). For SwiftUI views that need to re-render when
/// the user changes their budget, declare
/// `@AppStorage(AppSettings.dailyGLBudgetKey) private var glBudget: Double = AppSettings.defaultDailyGLBudget`
/// instead — this global is a snapshot at access time, not a reactive binding.
var dailyGLBudgetUI: Double { AppSettings.dailyGLBudget }

/// Maps a GL fraction (0–1+) to a gradient color.
func glGradientColor(fraction: Double) -> Color {
    let clamped = max(0, min(fraction, 1.0))
    if clamped < 0.5 {
        return Color(red: 0.15 + clamped * 0.9, green: 0.68 - clamped * 0.2, blue: 0.2)
    } else {
        let t = (clamped - 0.5) * 2
        return Color(red: 0.6 + t * 0.3, green: 0.58 - t * 0.38, blue: 0.0)
    }
}
