import CoreData
import Foundation

/// Manual override path: the user picks a `NutritionalProfile` from
/// `FoodPickerView` and we re-link the existing `FoodLogEntry` to it,
/// recomputing GL and CL from the new profile while preserving the
/// original timestamp, transcript, and serving size.
@MainActor
enum EntryRefiner {
    /// Re-link `entry` to `profile`, recompute GL/CL from the entry's existing
    /// `quantityGrams` and the profile's macros, mark the entry as a
    /// high-confidence direct match, and save. Returns nothing — the entry's
    /// `objectWillChange` will fire so SwiftUI views observing it refresh.
    static func refine(entry: FoodLogEntry, to profile: NutritionalProfile, context: NSManagedObjectContext) {
        let grams = entry.quantityGrams
        let (gl, cl) = NutritionCalculator.compute(profile: profile, grams: grams)

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
