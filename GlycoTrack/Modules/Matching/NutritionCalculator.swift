import Foundation

/// Single-profile GL + CL computation, shared by FoodMatcher and EntryRefiner.
/// The two callers were previously duplicating this logic; centralising it
/// ensures that a correction to the GI=0 fallback or CL formula applies in
/// both places automatically.
enum NutritionCalculator {
    /// Returns (gl, cl) for a single nutritional profile at a given serving size.
    ///
    /// GL rule: `glycemicIndex == 0` means "no Sydney GI entry", not zero GI.
    /// When carbs are present (> 3 g/100g) we substitute medium GI (55) so
    /// carb-heavy foods without a Sydney entry don't silently report GL = 0.
    static func compute(profile: NutritionalProfile, grams: Double) -> (gl: Double, cl: Double) {
        let carbsInServing = profile.carbsPer100g * grams / 100.0
        let effectiveGI: Int = (profile.glycemicIndex == 0 && profile.carbsPer100g > 3)
            ? 55
            : Int(profile.glycemicIndex)
        let gl = GIEngine.computeGL(gi: effectiveGI, carbsGrams: carbsInServing)

        let nutrition = NutritionInput(
            saturatedFatPer100g: profile.saturatedFatPer100g,
            transFatPer100g: profile.transFatPer100g,
            solubleFiberPer100g: profile.solubleFiberPer100g,
            pufaPer100g: profile.pufaPer100g,
            mufaPer100g: profile.mufaPer100g
        )
        let cl = CLEngine().computeCL(nutrition: nutrition, quantityGrams: grams).cl
        return (gl, cl)
    }
}
