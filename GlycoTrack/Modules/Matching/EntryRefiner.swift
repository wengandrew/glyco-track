import CoreData
import Foundation

/// Manual override path: the user picks a `NutritionalProfile` from
/// `FoodPickerView` and we re-link the existing `FoodLogEntry` to it,
/// recomputing GL and CL from the new profile while preserving the
/// original timestamp, transcript, and serving size.
///
/// Mirrors `FoodMatcher.compute(components:)` for a single component (the
/// new profile, all of `entry.quantityGrams`). Kept separate so a future
/// refactor of the matcher's internals doesn't accidentally change the
/// refinement contract — manual overrides should always produce the same
/// numbers a fresh T1 match against the same profile would.
@MainActor
enum EntryRefiner {
    /// Re-link `entry` to `profile`, recompute GL/CL from the entry's existing
    /// `quantityGrams` and the profile's macros, mark the entry as a
    /// high-confidence direct match, and save. Returns nothing — the entry's
    /// `objectWillChange` will fire so SwiftUI views observing it refresh.
    static func refine(entry: FoodLogEntry, to profile: NutritionalProfile, context: NSManagedObjectContext) {
        let grams = entry.quantityGrams

        // GL — same logic as FoodMatcher.compute.
        let carbsInServing = profile.carbsPer100g * grams / 100.0
        let effectiveGI: Int = (profile.glycemicIndex == 0 && profile.carbsPer100g > 3)
            ? 55
            : Int(profile.glycemicIndex)
        let gl = GIEngine.computeGL(gi: effectiveGI, carbsGrams: carbsInServing)

        // CL — same nutrition input shape as the matcher uses.
        let nutrition = NutritionInput(
            saturatedFatPer100g: profile.saturatedFatPer100g,
            transFatPer100g: profile.transFatPer100g,
            solubleFiberPer100g: profile.solubleFiberPer100g,
            pufaPer100g: profile.pufaPer100g,
            mufaPer100g: profile.mufaPer100g
        )
        let cl = CLEngine().computeCL(nutrition: nutrition, quantityGrams: grams).cl

        entry.nutritionalProfile = profile
        entry.referenceFood = profile.foodName
        entry.computedGL = gl
        entry.computedCL = cl
        // Manual override is by definition a direct, certain match.
        entry.parsingMethod = MatchTier.direct.rawValue
        entry.confidenceScore = 1.0
        entry.isEdited = true

        try? context.save()
    }
}
