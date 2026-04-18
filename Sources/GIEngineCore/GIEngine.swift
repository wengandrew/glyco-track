import Foundation

public struct GLResult {
    public let gl: Double
    public let gi: Int
    public let carbs: Double
    public let confidence: Float
    public let tier: Int
    public let matchedFoodName: String?

    public var threshold: GLThreshold {
        if gl <= 10 { return .low }
        if gl <= 19 { return .medium }
        return .high
    }
}

public enum GLThreshold {
    case low, medium, high
}

public let dailyGLBudget: Double = 100.0

public final class GIEngine {
    private let database: GIDatabase

    public init(database: GIDatabase) {
        self.database = database
    }

    /// Primary entry point: compute GL given a food name and quantity in grams.
    /// carbsPer100g must be provided from the USDA nutrition database.
    public func computeGL(
        foodName: String,
        quantityGrams: Double,
        carbsPer100g: Double
    ) -> GLResult {
        let carbsInServing = carbsPer100g * quantityGrams / 100.0

        guard let match = database.lookup(foodName) else {
            // Tier 3: no match — estimate using average GI of 55 (medium)
            let gl = (55.0 * carbsInServing) / 100.0
            return GLResult(gl: max(0, gl), gi: 55, carbs: carbsInServing,
                            confidence: 0.35, tier: 3, matchedFoodName: nil)
        }

        let gi = Double(match.record.gi)
        let gl = (gi * carbsInServing) / 100.0
        return GLResult(gl: max(0, gl), gi: match.record.gi, carbs: carbsInServing,
                        confidence: match.confidence, tier: match.tier,
                        matchedFoodName: match.record.name)
    }

    /// Convenience: compute GL when GI is already known (e.g. from prior match).
    public static func computeGL(gi: Int, carbsGrams: Double) -> Double {
        max(0, (Double(gi) * carbsGrams) / 100.0)
    }
}
