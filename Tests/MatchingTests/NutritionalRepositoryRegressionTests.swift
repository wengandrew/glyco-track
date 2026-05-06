import CoreData
import XCTest
@testable import GlycoTrack

/// Regression tests for the matching cascade against the real bundled
/// gi_database.json + usda_nutrition.json. Pins the prod-log-driven fixes
/// shipped in #25 (T1 word-count gate, prep-method fuzzy block,
/// HEADLINE-CARB decomposition rule), #26 (alias wiring), and #27
/// (whole-grain promotion).
///
/// These tests hit `NutritionalRepository` directly — the full FoodMatcher
/// cascade involves a Claude-API call on T3, which we don't want to make
/// in unit tests. T1 and T2 logic — where the named regressions live —
/// are entirely repo-level.
@MainActor
final class NutritionalRepositoryRegressionTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: NutritionalRepository!

    override func setUp() async throws {
        try await super.setUp()
        pc = PersistenceController(inMemory: true)
        await pc.seedNutritionalProfiles()
        // AliasIndex.shared loaded its tables on first use from Bundle.main
        // (the test bundle, which carries the same JSON). Force a reload to
        // be deterministic across tests.
        AliasIndex.shared.reload()
        repo = NutritionalRepository(context: pc.context, aliasIndex: .shared)
    }

    override func tearDown() async throws {
        repo = nil
        pc = nil
        try await super.tearDown()
    }

    // MARK: - Sanity: seeding actually worked

    func testSeedPopulatesProfiles() throws {
        let request = NutritionalProfile.fetchRequest()
        let count = try pc.context.count(for: request)
        XCTAssertGreaterThan(count, 700, "Expected the GI database (~776 entries) to seed")
    }

    // MARK: - T1 word-count gate (PR #25)

    /// "bread" alone is a single-word generic that historically latched onto a
    /// specific bread variant via T1 contains. The word-count ratio gate
    /// (≥ 50%) plus the alias path should now route it to the canonical alias
    /// target ("white bread") rather than to a contains-match like "rye bread".
    func testGenericBreadResolvesViaAliasNotContains() {
        let result = repo.findBestMatch(for: "bread")
        XCTAssertNotNil(result, "'bread' should resolve via its alias entry")
        XCTAssertEqual(result?.profile.foodName.lowercased(), "white bread",
                       "'bread' must resolve to the canonical aliased entry, not a specific variant")
    }

    /// "sugar" appears as a substring inside "sugar snap peas" (33% word
    /// coverage). The gate must reject this contains-match. The alias path
    /// then resolves "sugar" → "white sugar".
    func testSugarDoesNotMatchSugarSnapPeas() {
        let result = repo.findBestMatch(for: "sugar")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "sugar snap peas",
                          "T1 contains must reject a query covering only one of three DB-entry words")
    }

    /// "apple" is in the DB itself. The contains-gate must not promote it
    /// to "apple cider vinegar" or "apple juice" when an exact match exists.
    func testAppleResolvesToApple() {
        let result = repo.findBestMatch(for: "apple")
        XCTAssertEqual(result?.profile.foodName.lowercased(), "apple",
                       "Exact match must beat any contains/alias path")
    }

    /// "white rice" exists as a canonical entry — must resolve directly,
    /// not via T2 component decomposition.
    func testWhiteRiceResolvesDirectly() {
        let result = repo.findBestMatch(for: "white rice")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.profile.foodName.lowercased(), "white rice")
    }

    // MARK: - Prep-method fuzzy block (PR #25)

    /// "grilled chicken" must NOT bridge to "fried chicken" via Levenshtein
    /// distance. The two have different CL profiles — fuzzy bridging would
    /// silently swap saturated/trans fat values.
    func testGrilledChickenDoesNotFuzzyBridgeToFriedChicken() {
        let result = repo.findBestMatch(for: "grilled chicken")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "fried chicken",
                          "Fuzzy match must refuse to bridge across prep methods")
    }

    // MARK: - Alias wiring (PR #26)

    /// "rice" is a declared alias of "white rice". Without the alias path,
    /// T1 contains is now too strict to land here (one word vs. two).
    func testRiceAliasResolvesToWhiteRice() {
        let result = repo.findBestMatch(for: "rice")
        XCTAssertEqual(result?.profile.foodName.lowercased(), "white rice",
                       "'rice' must resolve via the alias path on white rice")
    }

    /// "egg" / "eggs" alias mapping — eggs is the canonical entry, "egg" is
    /// a declared alias.
    func testEggSingularAliasResolvesToEggs() {
        let result = repo.findBestMatch(for: "egg")
        XCTAssertEqual(result?.profile.foodName.lowercased(), "eggs",
                       "'egg' must resolve via alias to canonical 'eggs'")
    }

    // MARK: - Word-boundary safety (PR #25)

    /// Short food-name substrings must not surface inside unrelated longer
    /// words via T2 component decomposition. "egg" must not appear as a
    /// component of "veggie burger".
    func testEggDoesNotMatchInsideVeggie() {
        let components = repo.findComponents(for: "veggie burger")
        let names = components.map { $0.profile.foodName.lowercased() }
        XCTAssertFalse(names.contains("eggs"),
                       "Word-boundary gate must reject 'egg' inside 'veggie'")
    }

    /// Same shape, "ale" inside "kale".
    func testAleDoesNotMatchInsideKale() {
        let components = repo.findComponents(for: "kale salad")
        let names = components.map { $0.profile.foodName.lowercased() }
        XCTAssertFalse(names.contains("ale"),
                       "Word-boundary gate must reject 'ale' inside 'kale'")
    }

    // MARK: - Whole-grain promotion (PR #27)

    /// "whole wheat spaghetti" exists as a canonical entry post-#28; before
    /// that the matcher had to strip the whole-wheat qualifier and promote
    /// "spaghetti" → "white pasta" → "whole wheat pasta". Either path must
    /// land on a whole-grain variant, never the refined-grain entry.
    func testWholeWheatSpaghettiResolvesToWholeGrain() {
        let result = repo.findBestMatch(for: "whole wheat spaghetti")
        XCTAssertNotNil(result, "whole-grain qualifier should resolve via direct match or promotion")
        let name = result?.profile.foodName.lowercased() ?? ""
        XCTAssertTrue(name.contains("whole wheat") || name.contains("wholemeal"),
                      "Promotion must land on a whole-grain variant, got '\(name)'")
    }

    /// "brown rice" exists directly — sanity check that the brown qualifier
    /// path resolves.
    func testBrownRiceResolvesDirectly() {
        let result = repo.findBestMatch(for: "brown rice")
        XCTAssertEqual(result?.profile.foodName.lowercased(), "brown rice")
    }

    // MARK: - Fuzzy match guardrails (log audit 2026-05-06)

    /// "bialy" (Polish bread roll) was fuzzy-matching to "kale" at Levenshtein
    /// distance 3. Completely different food categories — bread vs leafy green.
    func testBialyDoesNotFuzzyMatchKale() {
        let result = repo.findBestMatch(for: "bialy")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "kale",
                          "Fuzzy match must not bridge 'bialy' (bread) to 'kale' (vegetable)")
    }

    /// "arepa" (cornmeal cake) was fuzzy-matching to "tea" at distance 3.
    func testArepaDoesNotFuzzyMatchTea() {
        let result = repo.findBestMatch(for: "arepa")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "tea",
                          "Fuzzy match must not bridge 'arepa' (corn cake) to 'tea' (beverage)")
    }

    /// "milk" was fuzzy-matching to "elk" at distance 2. Dairy vs game meat.
    func testMilkDoesNotFuzzyMatchElk() {
        let result = repo.findBestMatch(for: "milk")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "elk",
                          "Fuzzy match must not bridge 'milk' (dairy) to 'elk' (game meat)")
    }

    /// "sugar" was fuzzy-matching to "satay" at distance 3. Must resolve via
    /// alias to "white sugar" instead.
    func testSugarDoesNotFuzzyMatchSatay() {
        let result = repo.findBestMatch(for: "sugar")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "satay",
                          "Fuzzy match must not bridge 'sugar' to 'satay'")
    }

    /// "bread bun" was fuzzy-matching to "breadnut" at distance 1.
    /// A bread roll and a tropical tree nut are different foods.
    func testBreadBunDoesNotFuzzyMatchBreadnut() {
        let result = repo.findBestMatch(for: "bread bun")
        XCTAssertNotEqual(result?.profile.foodName.lowercased(), "breadnut",
                          "Fuzzy match must not bridge 'bread bun' to 'breadnut'")
    }

    // MARK: - DB data completeness (log audit 2026-05-06)

    /// Soba noodles exist in the GI database (GI=56) but had carbsPer100g=0
    /// because no USDA entry existed. GL was silently zero for every soba log.
    func testSobaNoodlesHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "soba noodles")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Soba noodles must have carbs data so GL is non-zero")
    }

    /// Gummy candy (GI=80) had no USDA match — pure sugar food reporting GL=0.
    func testGummyCandyHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "gummy candy")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Gummy candy must have carbs data so GL is non-zero")
    }

    /// Wonton (GI=55) had no USDA match — dumplings reporting GL=0.
    func testWontonHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "wonton")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Wonton must have carbs data so GL is non-zero")
    }

    /// Corn on the cob (GI=52, USDA carbs=21g) — verify data survives seeding.
    func testCornOnTheCobHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "corn on the cob")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Corn on the cob must have carbs data")
    }

    /// Cantaloupe (GI=65, USDA carbs=8.16g) — verify data survives seeding.
    func testCantaloupeHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "cantaloupe")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Cantaloupe must have carbs data")
    }

    /// Naan (GI=71, USDA carbs=50g) — verify data survives seeding.
    func testNaanHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "naan")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Naan must have carbs data")
    }

    /// Bread sticks (GI=70) had no USDA match — reporting GL=0.
    func testBreadSticksHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "bread sticks")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Bread sticks must have carbs data so GL is non-zero")
    }

    /// Pine nuts (GI=15) had CL=0 despite significant fat content.
    func testPineNutsHasNonZeroCLData() {
        let result = repo.findBestMatch(for: "pine nuts")
        XCTAssertNotNil(result)
        let p = result!.profile
        let hasFatData = p.saturatedFatPer100g > 0 || p.pufaPer100g > 0 || p.mufaPer100g > 0
        XCTAssertTrue(hasFatData,
                      "Pine nuts must have fat macro data for CL computation")
    }

    /// Sesame oil had CL=0 despite being pure fat.
    func testSesameOilHasNonZeroCLData() {
        let result = repo.findBestMatch(for: "sesame oil")
        XCTAssertNotNil(result)
        let p = result!.profile
        let hasFatData = p.saturatedFatPer100g > 0 || p.pufaPer100g > 0 || p.mufaPer100g > 0
        XCTAssertTrue(hasFatData,
                      "Sesame oil must have fat macro data for CL computation")
    }

    /// Laksa (GI=46) had no USDA match — noodle soup reporting GL=0.
    func testLaksaHasNonZeroCarbs() {
        let result = repo.findBestMatch(for: "laksa")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.profile.carbsPer100g, 0,
                             "Laksa must have carbs data so GL is non-zero")
    }
}
