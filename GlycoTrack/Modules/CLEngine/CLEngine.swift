import Foundation

// iOS app target wrapper — mirrors CLEngineCore SPM module.

struct NutritionInput {
    let saturatedFatPer100g: Double
    let transFatPer100g: Double
    let solubleFiberPer100g: Double
    let pufaPer100g: Double
    let mufaPer100g: Double
}

struct CLResult {
    let cl: Double
    let sfaContribution: Double
    let tfaContribution: Double
    let fiberBenefit: Double
    let pufaBenefit: Double
    let mufaBenefit: Double

    var isHarmful: Bool { cl > 0 }
    var isBeneficial: Bool { cl < 0 }
}

enum CLWeights {
    static let saturatedFat: Double = 1.0
    static let transFat: Double = 2.0
    static let solubleFiber: Double = 0.5
    static let pufa: Double = 0.7
    static let mufa: Double = 0.5
}

final class CLEngine {
    func computeCL(nutrition: NutritionInput, quantityGrams: Double) -> CLResult {
        let scale = quantityGrams / 100.0
        let sfa = nutrition.saturatedFatPer100g * scale
        let tfa = nutrition.transFatPer100g * scale
        let fiber = nutrition.solubleFiberPer100g * scale
        let pufa = nutrition.pufaPer100g * scale
        let mufa = nutrition.mufaPer100g * scale

        let sfaC = sfa * CLWeights.saturatedFat
        let tfaC = tfa * CLWeights.transFat
        let fibB = fiber * CLWeights.solubleFiber
        let pufB = pufa * CLWeights.pufa
        let mufB = mufa * CLWeights.mufa

        return CLResult(cl: sfaC + tfaC - fibB - pufB - mufB,
                        sfaContribution: sfaC, tfaContribution: tfaC,
                        fiberBenefit: fibB, pufaBenefit: pufB, mufaBenefit: mufB)
    }
}
