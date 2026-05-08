import XCTest
@testable import GIEngineCore

final class GIEngineTests: XCTestCase {
    private var database: GIDatabase!
    private var engine: GIEngine!

    override func setUp() {
        super.setUp()
        // Minimal inline DB for unit testing
        let records: [GIRecord] = [
            GIRecord(name: "white rice", gi: 72, aliases: ["rice", "steamed rice"]),
            GIRecord(name: "oatmeal", gi: 55, aliases: ["oats", "porridge"]),
            GIRecord(name: "lentils", gi: 32, aliases: ["red lentils"]),
            GIRecord(name: "white bread", gi: 75, aliases: ["bread", "toast"]),
            GIRecord(name: "watermelon", gi: 72, aliases: []),
            GIRecord(name: "apple", gi: 36, aliases: ["apples"]),
            GIRecord(name: "chocolate cake", gi: 38, aliases: ["cake"]),
            GIRecord(name: "eggs", gi: 0, aliases: ["egg", "scrambled eggs"]),
            GIRecord(name: "butter", gi: 0, aliases: []),
            GIRecord(name: "brown rice", gi: 50, aliases: ["wholegrain rice"]),
            GIRecord(name: "glucose", gi: 100, aliases: ["dextrose"])
        ]
        database = GIDatabase(records: records)
        engine = GIEngine(database: database)
    }

    // MARK: - GL Formula Validation (GL = GI × carbs / 100)

    func testWhiteRiceGL() {
        // 45g serving, 28.6g carbs per 100g → 12.87g carbs in serving
        // GL = 72 × 12.87 / 100 = 9.27
        let result = engine.computeGL(foodName: "white rice", quantityGrams: 45, carbsPer100g: 28.6)
        XCTAssertEqual(result.gi, 72)
        XCTAssertEqual(result.gl, 9.27, accuracy: 0.05)
        XCTAssertEqual(result.tier, 1)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.85)
    }

    func testWhiteRiceLargeServing() {
        // 150g serving (restaurant rice) → GL = 72 × (28.6 × 1.5) / 100 = 30.89
        let result = engine.computeGL(foodName: "white rice", quantityGrams: 150, carbsPer100g: 28.6)
        XCTAssertEqual(result.gl, 30.89, accuracy: 0.1)
        XCTAssertEqual(result.threshold, .high)
    }

    func testOatmealGL() {
        // 250g cooked oatmeal, 12g carbs per 100g → 30g carbs
        // GL = 55 × 30 / 100 = 16.5 (medium)
        let result = engine.computeGL(foodName: "oatmeal", quantityGrams: 250, carbsPer100g: 12.0)
        XCTAssertEqual(result.gi, 55)
        XCTAssertEqual(result.gl, 16.5, accuracy: 0.05)
        XCTAssertEqual(result.threshold, .medium)
    }

    func testLentilsGL() {
        // 100g lentils, 20g carbs per 100g → GL = 32 × 20 / 100 = 6.4 (low)
        let result = engine.computeGL(foodName: "lentils", quantityGrams: 100, carbsPer100g: 20.0)
        XCTAssertEqual(result.gi, 32)
        XCTAssertEqual(result.gl, 6.4, accuracy: 0.05)
        XCTAssertEqual(result.threshold, .low)
    }

    func testWatermelonGL() {
        // 120g watermelon, 7.6g carbs per 100g → 9.12g carbs
        // GL = 72 × 9.12 / 100 = 6.57 (low despite high GI — small carbs)
        let result = engine.computeGL(foodName: "watermelon", quantityGrams: 120, carbsPer100g: 7.6)
        XCTAssertEqual(result.gi, 72)
        XCTAssertEqual(result.gl, 6.57, accuracy: 0.05)
        XCTAssertEqual(result.threshold, .low)
    }

    func testEggsGL() {
        // Eggs have GI 0 → GL = 0 regardless of quantity
        let result = engine.computeGL(foodName: "eggs", quantityGrams: 100, carbsPer100g: 1.1)
        XCTAssertEqual(result.gi, 0)
        XCTAssertEqual(result.gl, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.threshold, .low)
    }

    func testGLIsNeverNegative() {
        // GL must always be >= 0 (unsigned)
        let result = engine.computeGL(foodName: "butter", quantityGrams: 100, carbsPer100g: 0.0)
        XCTAssertGreaterThanOrEqual(result.gl, 0)
    }

    // MARK: - Alias Matching

    func testAliasMatch() {
        let result = engine.computeGL(foodName: "rice", quantityGrams: 100, carbsPer100g: 28.6)
        XCTAssertEqual(result.gi, 72)
        XCTAssertEqual(result.tier, 1)
    }

    func testAliasMatchToast() {
        let result = engine.computeGL(foodName: "toast", quantityGrams: 30, carbsPer100g: 49.0)
        XCTAssertEqual(result.gi, 75)
    }

    // MARK: - Tier 3 Fallback

    func testUnknownFoodFallsBackToTier3() {
        let result = engine.computeGL(foodName: "dragon fruit foam", quantityGrams: 100, carbsPer100g: 15.0)
        XCTAssertEqual(result.tier, 3)
        XCTAssertLessThan(result.confidence, 0.5)
        XCTAssertGreaterThanOrEqual(result.gl, 0)
    }

    // MARK: - Static helper

    func testStaticGLComputation() {
        // GL = GI × carbs / 100
        XCTAssertEqual(GIEngine.computeGL(gi: 100, carbsGrams: 50), 50.0)
        XCTAssertEqual(GIEngine.computeGL(gi: 72, carbsGrams: 45), 32.4)
        XCTAssertEqual(GIEngine.computeGL(gi: 0, carbsGrams: 100), 0.0)
    }

    // MARK: - Thresholds

    func testThresholds() {
        XCTAssertEqual(GLThreshold.low, .low)
        let lowResult = engine.computeGL(foodName: "apple", quantityGrams: 100, carbsPer100g: 13.8)
        XCTAssertEqual(lowResult.threshold, .low) // GL ≈ 4.97

        let highResult = engine.computeGL(foodName: "glucose", quantityGrams: 100, carbsPer100g: 100)
        XCTAssertEqual(highResult.threshold, .high) // GL = 100
    }

    // MARK: - Daily budget

    func testDailyBudget() {
        XCTAssertEqual(dailyGLBudget, 100.0)
    }

    // MARK: - Threshold exact boundaries (CLAUDE.md: Low ≤10, Medium 11–19, High ≥20)

    func testGLThresholdExactlyTenIsLow() {
        // GI=100 (glucose), carbs=100g/100g, qty=10g → GL = 100*(10)/100 = 10.0 → low
        let result = engine.computeGL(foodName: "glucose", quantityGrams: 10, carbsPer100g: 100.0)
        XCTAssertEqual(result.gl, 10.0, accuracy: 0.001)
        XCTAssertEqual(result.threshold, .low, "GL = 10 must be .low (boundary is ≤10)")
    }

    func testGLThresholdElevenIsMedium() {
        // GL = 11.0 → first value above the low threshold
        let result = engine.computeGL(foodName: "glucose", quantityGrams: 11, carbsPer100g: 100.0)
        XCTAssertEqual(result.gl, 11.0, accuracy: 0.001)
        XCTAssertEqual(result.threshold, .medium, "GL = 11 must be .medium")
    }

    func testGLThresholdNineteenIsMedium() {
        // GL = 19.0 → last value inside the medium band
        let result = engine.computeGL(foodName: "glucose", quantityGrams: 19, carbsPer100g: 100.0)
        XCTAssertEqual(result.gl, 19.0, accuracy: 0.001)
        XCTAssertEqual(result.threshold, .medium, "GL = 19 must be .medium")
    }

    func testGLThresholdTwentyIsHigh() {
        // GL = 20.0 → boundary of the high band (≥20)
        let result = engine.computeGL(foodName: "glucose", quantityGrams: 20, carbsPer100g: 100.0)
        XCTAssertEqual(result.gl, 20.0, accuracy: 0.001)
        XCTAssertEqual(result.threshold, .high, "GL = 20 must be .high (boundary is ≥20)")
    }

    // MARK: - Case insensitivity and whitespace tolerance

    func testLookupIsCaseInsensitive() {
        let upper = engine.computeGL(foodName: "WHITE RICE", quantityGrams: 100, carbsPer100g: 28.6)
        let lower = engine.computeGL(foodName: "white rice", quantityGrams: 100, carbsPer100g: 28.6)
        XCTAssertEqual(upper.gi, lower.gi, "GI lookup must be case-insensitive")
        XCTAssertEqual(upper.tier, 1, "Upper-case canonical name must still resolve to tier 1")
    }

    func testLookupTrimsLeadingTrailingWhitespace() {
        let padded = engine.computeGL(foodName: "  oatmeal  ", quantityGrams: 100, carbsPer100g: 12.0)
        XCTAssertEqual(padded.gi, 55, "Lookup must trim leading/trailing whitespace before matching")
        XCTAssertEqual(padded.tier, 1)
    }

    // MARK: - GIDatabase fuzzy confidence tiers (d=1 → 0.80, d=2 → 0.70, d=3 → 0.55)

    func testFuzzyMatchD1GivesHighConfidence() {
        // "oatmeel" is Levenshtein d=1 from "oatmeal" (a→e). Resolves to tier 2, confidence 0.80.
        let result = engine.computeGL(foodName: "oatmeel", quantityGrams: 100, carbsPer100g: 12.0)
        XCTAssertEqual(result.tier, 2, "1-char typo must fall to tier 2")
        XCTAssertEqual(result.confidence, 0.80, accuracy: 0.01, "d=1 must give 0.80 confidence")
        XCTAssertEqual(result.gi, 55, "Fuzzy must resolve to oatmeal (GI 55)")
    }

    func testFuzzyMatchD2GivesMediumConfidence() {
        // "lentilles" is d=2 from "lentils" (insert 'l', insert 'e' before 's'). Confidence 0.70.
        let result = engine.computeGL(foodName: "lentilles", quantityGrams: 100, carbsPer100g: 20.0)
        XCTAssertEqual(result.tier, 2, "2-char typo must fall to tier 2")
        XCTAssertEqual(result.confidence, 0.70, accuracy: 0.01, "d=2 must give 0.70 confidence")
        XCTAssertEqual(result.gi, 32, "Fuzzy must resolve to lentils (GI 32)")
    }

    func testFuzzyMatchD3GivesLowConfidence() {
        // "wwwatermeloon" needs 3 insertions to become "watermelon" (two extra 'w's + one extra 'o')
        // and is d>3 from every other entry in the test DB. Must resolve at confidence 0.55.
        let result = engine.computeGL(foodName: "wwwatermeloon", quantityGrams: 120, carbsPer100g: 7.6)
        XCTAssertEqual(result.tier, 2, "d=3 from nearest entry must still be tier 2 (within the ≤3 cap)")
        XCTAssertEqual(result.confidence, 0.55, accuracy: 0.01, "d=3 must give 0.55 confidence")
        XCTAssertEqual(result.gi, 72, "Fuzzy must resolve to watermelon (GI 72)")
    }

    func testFuzzyMatchBeyondD3FallsToTier3() {
        // "dragonberry" is more than d=3 from every DB entry → tier 3 fallback.
        let result = engine.computeGL(foodName: "dragonberry", quantityGrams: 100, carbsPer100g: 15.0)
        XCTAssertEqual(result.tier, 3, "d>3 from all DB entries must fall to tier 3")
        XCTAssertLessThan(result.confidence, 0.5)
    }
}
