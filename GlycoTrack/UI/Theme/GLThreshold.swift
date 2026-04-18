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

let dailyGLBudgetUI: Double = 100.0

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
