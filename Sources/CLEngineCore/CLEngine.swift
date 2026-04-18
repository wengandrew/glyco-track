import Foundation

public struct CLResult {
    /// Signed value: positive = net harmful, negative = net beneficial.
    public let cl: Double
    public let sfaContribution: Double
    public let tfaContribution: Double
    public let fiberBenefit: Double
    public let pufaBenefit: Double
    public let mufaBenefit: Double

    public var isHarmful: Bool { cl > 0 }
    public var isBeneficial: Bool { cl < 0 }
    public var isNeutral: Bool { cl == 0 }

    public var classification: CLClassification {
        if cl < -1.0 { return .beneficial }
        if cl > 1.0 { return .harmful }
        return .neutral
    }
}

public enum CLClassification {
    case beneficial, neutral, harmful
}

public struct NutritionInput {
    public let saturatedFatPer100g: Double
    public let transFatPer100g: Double
    public let solubleFiberPer100g: Double
    public let pufaPer100g: Double
    public let mufaPer100g: Double

    public init(
        saturatedFatPer100g: Double,
        transFatPer100g: Double,
        solubleFiberPer100g: Double,
        pufaPer100g: Double,
        mufaPer100g: Double
    ) {
        self.saturatedFatPer100g = saturatedFatPer100g
        self.transFatPer100g = transFatPer100g
        self.solubleFiberPer100g = solubleFiberPer100g
        self.pufaPer100g = pufaPer100g
        self.mufaPer100g = mufaPer100g
    }
}

public final class CLEngine {
    private let weights: CLWeights.Type

    public init(weights: CLWeights.Type = CLWeights.self) {
        self.weights = weights
    }

    /// Compute signed Cholesterol Load for a food given its nutritional profile and serving size.
    ///
    /// CL = (SFA × W_sfa) + (TFA × W_tfa) − (Fiber × W_fiber) − (PUFA × W_pufa) − (MUFA × W_mufa)
    ///
    /// All inputs are per-100g values; quantityGrams scales the result to the actual serving.
    public func computeCL(nutrition: NutritionInput, quantityGrams: Double) -> CLResult {
        let scale = quantityGrams / 100.0

        let sfa = nutrition.saturatedFatPer100g * scale
        let tfa = nutrition.transFatPer100g * scale
        let fiber = nutrition.solubleFiberPer100g * scale
        let pufa = nutrition.pufaPer100g * scale
        let mufa = nutrition.mufaPer100g * scale

        let sfaContrib = sfa * weights.saturatedFat
        let tfaContrib = tfa * weights.transFat
        let fiberBenefit = fiber * weights.solubleFiber
        let pufaBenefit = pufa * weights.pufa
        let mufaBenefit = mufa * weights.mufa

        let cl = sfaContrib + tfaContrib - fiberBenefit - pufaBenefit - mufaBenefit

        return CLResult(
            cl: cl,
            sfaContribution: sfaContrib,
            tfaContribution: tfaContrib,
            fiberBenefit: fiberBenefit,
            pufaBenefit: pufaBenefit,
            mufaBenefit: mufaBenefit
        )
    }
}
