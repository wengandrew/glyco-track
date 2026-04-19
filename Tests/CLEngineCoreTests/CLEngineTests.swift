import XCTest
@testable import CLEngineCore

final class CLEngineTests: XCTestCase {
    private var engine: CLEngine!

    override func setUp() {
        super.setUp()
        engine = CLEngine()
    }

    // MARK: - Harmful foods (positive CL)

    func testButter100g() {
        // butter: SFA=51.37, TFA=3.28, fiber=0, PUFA=3.01, MUFA=21.02
        // CL = (51.37×1.0) + (3.28×2.0) - 0 - (3.01×0.7) - (21.02×0.5)
        //    = 51.37 + 6.56 - 2.107 - 10.51
        //    = 45.31
        let nutrition = NutritionInput(
            saturatedFatPer100g: 51.37, transFatPer100g: 3.28,
            solubleFiberPer100g: 0.0, pufaPer100g: 3.01, mufaPer100g: 21.02
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 100)
        XCTAssertTrue(result.isHarmful, "Butter should be harmful")
        XCTAssertEqual(result.cl, 45.31, accuracy: 0.1)
        XCTAssertEqual(result.classification, .harmful)
    }

    func testTransFatFood() {
        // Partially hydrogenated shortening (old-style): TFA=25.0, SFA=25.0, PUFA=10.0, MUFA=40.0
        // CL = (25×1.0) + (25×2.0) − (10×0.7) − (40×0.5) = 25+50−7−20 = 48.0 → harmful
        let nutrition = NutritionInput(
            saturatedFatPer100g: 25.0, transFatPer100g: 25.0,
            solubleFiberPer100g: 0.0, pufaPer100g: 10.0, mufaPer100g: 40.0
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 100)
        XCTAssertTrue(result.isHarmful, "Hydrogenated shortening with high trans fat should be harmful")
        XCTAssertGreaterThan(result.tfaContribution, result.sfaContribution * 0.5,
                             "Trans fat contribution should be significant")
    }

    func testBeef100g() {
        // beef: SFA=8.22, TFA=1.15, fiber=0, PUFA=0.52, MUFA=7.61
        let nutrition = NutritionInput(
            saturatedFatPer100g: 8.22, transFatPer100g: 1.15,
            solubleFiberPer100g: 0.0, pufaPer100g: 0.52, mufaPer100g: 7.61
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 100)
        XCTAssertTrue(result.isHarmful, "Beef should have net harmful CL")
    }

    // MARK: - Beneficial foods (negative CL)

    func testOliveOil15g() {
        // olive oil: SFA=13.81, TFA=0, fiber=0, PUFA=10.52, MUFA=72.96
        // 15g serving (typical drizzle)
        // CL = (13.81×1.0×0.15) - (10.52×0.7×0.15) - (72.96×0.5×0.15)
        //    = 2.07 - 1.10 - 5.47 = -4.50
        let nutrition = NutritionInput(
            saturatedFatPer100g: 13.81, transFatPer100g: 0.0,
            solubleFiberPer100g: 0.0, pufaPer100g: 10.52, mufaPer100g: 72.96
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 15)
        XCTAssertTrue(result.isBeneficial, "Olive oil should be net beneficial")
        XCTAssertLessThan(result.cl, 0)
    }

    func testOats100g() {
        // oats: SFA=0.37, TFA=0, soluble fiber=1.0, PUFA=0.76, MUFA=0.54
        let nutrition = NutritionInput(
            saturatedFatPer100g: 0.37, transFatPer100g: 0.0,
            solubleFiberPer100g: 1.0, pufaPer100g: 0.76, mufaPer100g: 0.54
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 100)
        XCTAssertTrue(result.isBeneficial, "Oatmeal should be net beneficial due to soluble fiber")
    }

    func testWalnuts30g() {
        // walnuts: SFA=6.13, TFA=0, fiber=2.0, PUFA=47.17, MUFA=8.93
        // High PUFA should dominate and produce negative CL
        let nutrition = NutritionInput(
            saturatedFatPer100g: 6.13, transFatPer100g: 0.0,
            solubleFiberPer100g: 2.0, pufaPer100g: 47.17, mufaPer100g: 8.93
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 30)
        XCTAssertTrue(result.isBeneficial, "Walnuts should be net beneficial due to high PUFA")
    }

    func testChiaSeeds15g() {
        // chia seeds: SFA=3.33, fiber=34.4, PUFA=23.67, MUFA=2.31
        let nutrition = NutritionInput(
            saturatedFatPer100g: 3.33, transFatPer100g: 0.0,
            solubleFiberPer100g: 34.4, pufaPer100g: 23.67, mufaPer100g: 2.31
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 15)
        XCTAssertTrue(result.isBeneficial, "Chia seeds should be beneficial due to high fiber + PUFA")
    }

    // MARK: - Mediterranean vs Standard American Diet Validation

    func testMediterraneanMealIsNegativeCL() {
        // Mediterranean meal: olive oil + salmon + spinach
        // Olive oil 20g
        let oliveOil = engine.computeCL(nutrition: NutritionInput(
            saturatedFatPer100g: 13.81, transFatPer100g: 0.0,
            solubleFiberPer100g: 0.0, pufaPer100g: 10.52, mufaPer100g: 72.96
        ), quantityGrams: 20)

        // Salmon 150g
        let salmon = engine.computeCL(nutrition: NutritionInput(
            saturatedFatPer100g: 3.15, transFatPer100g: 0.09,
            solubleFiberPer100g: 0.0, pufaPer100g: 3.72, mufaPer100g: 3.73
        ), quantityGrams: 150)

        // Spinach 100g
        let spinach = engine.computeCL(nutrition: NutritionInput(
            saturatedFatPer100g: 0.06, transFatPer100g: 0.0,
            solubleFiberPer100g: 0.8, pufaPer100g: 0.16, mufaPer100g: 0.01
        ), quantityGrams: 100)

        let totalMedCL = oliveOil.cl + salmon.cl + spinach.cl
        XCTAssertLessThan(totalMedCL, 0,
            "Mediterranean meal (olive oil + salmon + spinach) should have negative CL. Got: \(totalMedCL)")
    }

    func testAmericanFastFoodMealIsPositiveCL() {
        // American fast food: burger + french fries + cola
        // Burger patty 150g (beef-like)
        let burger = engine.computeCL(nutrition: NutritionInput(
            saturatedFatPer100g: 8.22, transFatPer100g: 1.15,
            solubleFiberPer100g: 0.0, pufaPer100g: 0.52, mufaPer100g: 7.61
        ), quantityGrams: 150)

        // Bun 60g (white bread-like)
        let bun = engine.computeCL(nutrition: NutritionInput(
            saturatedFatPer100g: 0.58, transFatPer100g: 0.18,
            solubleFiberPer100g: 0.5, pufaPer100g: 1.26, mufaPer100g: 0.61
        ), quantityGrams: 60)

        // French fries 150g
        let fries = engine.computeCL(nutrition: NutritionInput(
            saturatedFatPer100g: 2.32, transFatPer100g: 0.13,
            solubleFiberPer100g: 0.5, pufaPer100g: 4.62, mufaPer100g: 4.58
        ), quantityGrams: 150)

        let totalAmericanCL = burger.cl + bun.cl + fries.cl
        XCTAssertGreaterThan(totalAmericanCL, 0,
            "American fast food meal should have positive CL. Got: \(totalAmericanCL)")
    }

    // MARK: - Edge Cases

    func testZeroPortionCL() {
        let nutrition = NutritionInput(
            saturatedFatPer100g: 51.37, transFatPer100g: 3.28,
            solubleFiberPer100g: 0.0, pufaPer100g: 3.01, mufaPer100g: 21.02
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 0)
        XCTAssertEqual(result.cl, 0.0, accuracy: 0.001)
    }

    func testPureProteinFoodApproachesZero() {
        // Chicken breast: very low SFA, no TFA, no fiber, low PUFA, low MUFA
        let nutrition = NutritionInput(
            saturatedFatPer100g: 0.66, transFatPer100g: 0.01,
            solubleFiberPer100g: 0.0, pufaPer100g: 0.55, mufaPer100g: 0.66
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 100)
        XCTAssertLessThan(abs(result.cl), 2.0, "Chicken breast CL should be near zero")
    }

    func testCLScalesWithPortion() {
        let nutrition = NutritionInput(
            saturatedFatPer100g: 10.0, transFatPer100g: 0.0,
            solubleFiberPer100g: 0.0, pufaPer100g: 0.0, mufaPer100g: 0.0
        )
        let result50g = engine.computeCL(nutrition: nutrition, quantityGrams: 50)
        let result100g = engine.computeCL(nutrition: nutrition, quantityGrams: 100)
        XCTAssertEqual(result100g.cl, result50g.cl * 2, accuracy: 0.001)
    }

    // MARK: - Component breakdown validation

    func testComponentBreakdown() {
        let nutrition = NutritionInput(
            saturatedFatPer100g: 10.0, transFatPer100g: 2.0,
            solubleFiberPer100g: 5.0, pufaPer100g: 4.0, mufaPer100g: 6.0
        )
        let result = engine.computeCL(nutrition: nutrition, quantityGrams: 100)
        // SFA: 10 × 1.0 = 10
        XCTAssertEqual(result.sfaContribution, 10.0, accuracy: 0.01)
        // TFA: 2 × 2.0 = 4
        XCTAssertEqual(result.tfaContribution, 4.0, accuracy: 0.01)
        // Fiber: 5 × 0.5 = 2.5
        XCTAssertEqual(result.fiberBenefit, 2.5, accuracy: 0.01)
        // PUFA: 4 × 0.7 = 2.8
        XCTAssertEqual(result.pufaBenefit, 2.8, accuracy: 0.01)
        // MUFA: 6 × 0.5 = 3.0
        XCTAssertEqual(result.mufaBenefit, 3.0, accuracy: 0.01)
        // CL = 10 + 4 - 2.5 - 2.8 - 3.0 = 5.7
        XCTAssertEqual(result.cl, 5.7, accuracy: 0.01)
    }
}
