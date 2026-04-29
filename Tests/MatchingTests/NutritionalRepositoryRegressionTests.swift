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
}
