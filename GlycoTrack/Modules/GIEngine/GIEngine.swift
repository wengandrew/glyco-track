import Foundation

// iOS app target wrapper — mirrors GIEngineCore SPM module.
// The full database/lookup/Levenshtein machinery from the SPM core is no longer
// needed here: FoodMatcher reads GI directly from NutritionalProfile and only
// needs the per-ingredient GL formula. Keep the SPM core complete for tests;
// keep this file minimal so the iOS surface area is what's actually called.
//
// `dailyGLBudget` lives in `GLThreshold.swift` as `dailyGLBudgetUI` for the UI;
// don't redefine it here.

enum GIEngine {
    /// GL = (GI × carbs_in_serving_g) / 100. Clamped to ≥ 0 so a stray
    /// negative carb value can't pull a daily total below zero.
    static func computeGL(gi: Int, carbsGrams: Double) -> Double {
        max(0, (Double(gi) * carbsGrams) / 100.0)
    }
}
