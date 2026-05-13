import Foundation

/// Single home for user-tunable settings keys + defaults.
///
/// Storage is `UserDefaults.standard` so SwiftUI views can use
/// `@AppStorage(AppSettings.<key>)` for automatic reactivity. Non-view code
/// reads through the static accessors below, which clamp out-of-range or
/// missing values back to the default.
enum AppSettings {
    /// Daily GL budget — the bucket size, summary chip threshold, and heatmap
    /// scale. Default 100 matches public-health "moderate GL day" guidance;
    /// physicians sometimes prescribe lower (60–80) or higher (120–150)
    /// targets, hence editable.
    static let dailyGLBudgetKey = "dailyGLBudget"
    static let defaultDailyGLBudget: Double = 100
    /// Reasonable bounds for the editor and clamp. Outside this range the
    /// app's visual scaling stops conveying meaningful information (the
    /// bucket fills/spills off-screen, the heatmap saturates instantly).
    static let dailyGLBudgetRange: ClosedRange<Double> = 50...200
    static let dailyGLBudgetStep: Double = 5

    /// Reads the persisted GL budget, clamped to `dailyGLBudgetRange`.
    /// Falls back to the default when no value is stored or the stored
    /// value is corrupt (zero / NaN).
    static var dailyGLBudget: Double {
        let stored = UserDefaults.standard.double(forKey: dailyGLBudgetKey)
        guard stored.isFinite, stored > 0 else { return defaultDailyGLBudget }
        return min(max(stored, dailyGLBudgetRange.lowerBound), dailyGLBudgetRange.upperBound)
    }

    // MARK: - Physics sandbox

    /// Gravity magnitude applied to both the GL bucket and CL balance scenes.
    /// Higher = objects accelerate faster and roll more aggressively when you
    /// tilt the phone. Lower = slow, floaty movement.
    static let physicsGravityKey = "physicsGravity"
    static let defaultPhysicsGravity: Double = 9.0
    static let physicsGravityRange: ClosedRange<Double> = 1...20

    /// Haptic intensity on item collisions (0 = silent, 1 = full impact).
    static let physicsHapticsKey = "physicsHaptics"
    static let defaultPhysicsHaptics: Double = 0.8
    static let physicsHapticsRange: ClosedRange<Double> = 0...1

    /// Duration (seconds) of each haptic pulse on collision.
    /// Only used when CoreHaptics is available; UIImpactFeedbackGenerator
    /// ignores this and fires a single fixed-length pulse.
    static let physicsHapticDurationKey = "physicsHapticDuration"
    static let defaultPhysicsHapticDuration: Double = 0.1
    static let physicsHapticDurationRange: ClosedRange<Double> = 0.02...0.5
}
