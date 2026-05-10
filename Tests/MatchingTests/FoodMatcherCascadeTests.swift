import CoreData
import XCTest
@testable import GlycoTrack

/// Tests for the FoodMatcher cascade (T1/T2/T5 dispatch) and EntryRefiner
/// re-linking logic.
///
/// Tier 3/4 (Claude API) is stubbed out by `NoNetworkProtocol`, which intercepts
/// all URLSession.shared requests and fails them immediately — no sockets opened,
/// no auth tokens needed. `decomposeIngredients` catches the error and returns `[]`,
/// keeping the suite fully offline and deterministic. This file focuses on T1,
/// T2 (when T2 is strong enough to avoid the API), and T5.

// MARK: - Test support

/// URLProtocol that immediately fails every request without opening a socket.
/// Registered on URLSession.shared for the duration of each test.
private final class NoNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@MainActor
final class FoodMatcherCascadeTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: NutritionalRepository!
    private var matcher: FoodMatcher!

    override func setUp() async throws {
        try await super.setUp()
        URLProtocol.registerClass(NoNetworkProtocol.self)
        pc = PersistenceController(inMemory: true)
        await pc.seedNutritionalProfiles()
        AliasIndex.shared.reload()
        repo = NutritionalRepository(context: pc.context, aliasIndex: .shared)
        let client = ClaudeAPIClient(apiKey: "unused-in-tests")
        let parser = TranscriptParser(client: client)
        matcher = FoodMatcher(repo: repo, parser: parser)
    }

    override func tearDown() async throws {
        URLProtocol.unregisterClass(NoNetworkProtocol.self)
        matcher = nil
        repo = nil
        pc = nil
        try await super.tearDown()
    }

    // MARK: - Tier 1: direct whole-name match

    func testExactNameResolvesAtTier1() async {
        let food = ParsedFood(food: "white rice", quantity: "1 cup", unit: "cup", grams: 186)
        let result = await matcher.resolve(food: food)
        XCTAssertEqual(result.tier, .direct)
        XCTAssertTrue(result.isRecognized)
    }

    func testAliasResolvesAtTier1() async {
        // "rice" is a declared alias of "white rice". T1 alias path must fire.
        let food = ParsedFood(food: "rice", quantity: "1 cup", unit: "cup", grams: 186)
        let result = await matcher.resolve(food: food)
        XCTAssertEqual(result.tier, .direct)
    }

    func testTier1ConfidenceIsHighForExactMatch() async {
        let food = ParsedFood(food: "apple", quantity: "1 medium", unit: "", grams: 182)
        let result = await matcher.resolve(food: food)
        XCTAssertEqual(result.tier, .direct)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.85,
            "Exact and alias matches should carry ≥ 85% confidence")
    }

    func testTier1YieldsPrimaryProfile() async {
        let food = ParsedFood(food: "white rice", quantity: "1 cup", unit: "cup", grams: 186)
        let result = await matcher.resolve(food: food)
        XCTAssertNotNil(result.primaryProfile)
        XCTAssertEqual(result.primaryProfile?.foodName.lowercased(), "white rice")
    }

    func testTier1MatchSummaryIsPopulated() async {
        let food = ParsedFood(food: "apple", quantity: "1", unit: "", grams: 182)
        let result = await matcher.resolve(food: food)
        XCTAssertNotNil(result.matchSummary)
        XCTAssertFalse(result.matchSummary?.isEmpty ?? true)
    }

    // MARK: - Tier 1: GL accuracy

    func testCarbFoodHasPositiveGL() async {
        let food = ParsedFood(food: "white rice", quantity: "1 cup", unit: "cup", grams: 186)
        let result = await matcher.resolve(food: food)
        XCTAssertGreaterThan(result.totalGL, 0,
            "White rice is a high-carb food and must produce GL > 0")
    }

    func testFatOnlyFoodHasNearZeroGL() async {
        // Butter has no carbs — GL should be negligible regardless of serving size.
        let food = ParsedFood(food: "butter", quantity: "1 tbsp", unit: "tbsp", grams: 14)
        let result = await matcher.resolve(food: food)
        XCTAssertTrue(result.isRecognized, "butter must be recognized in seed data")
        XCTAssertLessThan(result.totalGL, 1.0,
            "Butter has no significant carbs; GL must be near 0")
    }

    func testGLScalesWithServingSize() async {
        // GL should be proportional to grams served.
        let small = ParsedFood(food: "white rice", quantity: "half cup", unit: "", grams: 93)
        let large = ParsedFood(food: "white rice", quantity: "2 cups", unit: "", grams: 372)
        let smallResult = await matcher.resolve(food: small)
        let largeResult = await matcher.resolve(food: large)
        XCTAssertTrue(smallResult.isRecognized, "white rice (small) must be recognized")
        XCTAssertTrue(largeResult.isRecognized, "white rice (large) must be recognized")
        XCTAssertGreaterThan(largeResult.totalGL, smallResult.totalGL,
            "Larger serving must yield higher GL")
    }

    // MARK: - Tier 2: component decomposition (strong coverage)

    func testStrongComponentMatchIsRecognized() async {
        // "chicken and broccoli" — both "chicken" and "broccoli" exist in the DB.
        // T2 coverage should be strong enough to skip the API and return a result.
        let food = ParsedFood(food: "chicken and broccoli", quantity: "1 bowl", unit: "", grams: 300)
        let result = await matcher.resolve(food: food)
        XCTAssertTrue(result.isRecognized,
            "Two well-known components should produce a recognized result")
    }

    func testComponentMatchHasMultipleContributors() async {
        let food = ParsedFood(food: "chicken and broccoli", quantity: "1 bowl", unit: "", grams: 300)
        let result = await matcher.resolve(food: food)
        XCTAssertTrue(result.isRecognized, "chicken and broccoli must be recognized")
        XCTAssertGreaterThanOrEqual(result.contributingComponents.count, 2,
            "both chicken and broccoli should be present as distinct components")
    }

    // MARK: - Tier 5: unrecognized

    func testGibberishIsUnrecognized() async {
        let food = ParsedFood(food: "xyzqwerty99999nonsense", quantity: "100g", unit: "g", grams: 100)
        let result = await matcher.resolve(food: food)
        XCTAssertEqual(result.tier, .unrecognized)
        XCTAssertFalse(result.isRecognized)
    }

    func testUnrecognizedYieldsZeroGLAndCL() async {
        let food = ParsedFood(food: "blorptastic99", quantity: "50g", unit: "g", grams: 50)
        let result = await matcher.resolve(food: food)
        XCTAssertEqual(result.tier, .unrecognized)
        XCTAssertEqual(result.totalGL, 0)
        XCTAssertEqual(result.totalCL, 0)
    }

    func testUnrecognizedHasZeroConfidence() async {
        let food = ParsedFood(food: "completelymadeupfood12345", quantity: "100g", unit: "g", grams: 100)
        let result = await matcher.resolve(food: food)
        XCTAssertEqual(result.tier, .unrecognized)
        XCTAssertEqual(result.confidence, 0.0)
        XCTAssertNil(result.primaryProfile)
        XCTAssertNil(result.matchSummary)
    }

    func testUnrecognizedHasNoContributingComponents() async {
        let food = ParsedFood(food: "qqq999zzz", quantity: "100g", unit: "g", grams: 100)
        let result = await matcher.resolve(food: food)
        XCTAssertEqual(result.tier, .unrecognized)
        XCTAssertTrue(result.contributingComponents.isEmpty)
    }
}

// MARK: -

/// Tests for EntryRefiner — the manual-override path that re-links a
/// FoodLogEntry to a new NutritionalProfile and recomputes GL/CL.
@MainActor
final class EntryRefinerTests: XCTestCase {
    private var pc: PersistenceController!

    override func setUp() async throws {
        try await super.setUp()
        pc = PersistenceController(inMemory: true)
        await pc.seedNutritionalProfiles()
        AliasIndex.shared.reload()
    }

    override func tearDown() async throws {
        pc = nil
        try await super.tearDown()
    }

    private func profile(named name: String) -> NutritionalProfile? {
        NutritionalRepository(context: pc.context, aliasIndex: .shared)
            .findBestMatch(for: name)?.profile
    }

    private func makeEntry(gl: Double = 50, cl: Double = 1.0, grams: Double = 100) -> FoodLogEntry {
        let e = FoodLogEntry(context: pc.context)
        e.id = UUID()
        e.timestamp = Date()
        e.foodDescription = "original food"
        e.quantity = "100g"
        e.quantityGrams = grams
        e.rawTranscript = "test transcript"
        e.computedGL = gl
        e.computedCL = cl
        e.parsingMethod = MatchTier.aiBlended.rawValue
        e.confidenceScore = 0.40
        e.isEdited = false
        return e
    }

    // MARK: - Metadata updates

    func testRefineLinksNewProfile() {
        guard let profile = profile(named: "white rice") else {
            XCTFail("white rice must be in DB"); return
        }
        let entry = makeEntry()
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertEqual(entry.nutritionalProfile, profile)
    }

    func testRefineSetsTierToDirect() {
        guard let profile = profile(named: "apple") else { XCTFail("apple not found in seed DB"); return }
        let entry = makeEntry()
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertEqual(entry.parsingMethod, MatchTier.direct.rawValue)
    }

    func testRefineSetsPerfectConfidence() {
        guard let profile = profile(named: "apple") else { XCTFail("apple not found in seed DB"); return }
        let entry = makeEntry()
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertEqual(entry.confidenceScore, 1.0, accuracy: 0.001)
    }

    func testRefineMarksEntryAsEdited() {
        guard let profile = profile(named: "apple") else { XCTFail("apple not found in seed DB"); return }
        let entry = makeEntry()
        XCTAssertFalse(entry.isEdited)
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertTrue(entry.isEdited)
    }

    func testRefineUpdatesReferenceFood() {
        guard let profile = profile(named: "white rice") else { XCTFail("white rice not found in seed DB"); return }
        let entry = makeEntry()
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertEqual(entry.referenceFood, profile.foodName)
    }

    func testRefinePreservesTimestamp() {
        guard let profile = profile(named: "apple") else { XCTFail("apple not found in seed DB"); return }
        let original = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let entry = makeEntry()
        entry.timestamp = original
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertEqual(entry.timestamp, original,
            "refine() must not touch the entry's timestamp")
    }

    func testRefinePreservesRawTranscript() {
        guard let profile = profile(named: "apple") else { XCTFail("apple not found in seed DB"); return }
        let entry = makeEntry()
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertEqual(entry.rawTranscript, "test transcript",
            "refine() must not touch the raw transcript")
    }

    // MARK: - GL recomputation

    func testRefineComputesPositiveGLForCarbFood() {
        guard let profile = profile(named: "white rice") else { XCTFail("white rice not found in seed DB"); return }
        let entry = makeEntry(gl: 0, grams: 150)
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertGreaterThan(entry.computedGL, 0,
            "White rice at 150g must produce GL > 0")
    }

    func testRefineGLIsNearZeroForFatOnlyFood() {
        guard let profile = profile(named: "butter") else { XCTFail("butter not found in seed DB"); return }
        let entry = makeEntry(gl: 99, grams: 14)
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertLessThan(entry.computedGL, 1.0,
            "Butter has no meaningful carbs; GL must be near 0")
    }

    func testRefineGLUsesActualGramsNotDefault() {
        guard let profile = profile(named: "white rice") else { XCTFail("white rice not found in seed DB"); return }
        let entry50  = makeEntry(gl: 0, grams: 50)
        let entry200 = makeEntry(gl: 0, grams: 200)
        EntryRefiner.refine(entry: entry50,  to: profile, context: pc.context)
        EntryRefiner.refine(entry: entry200, to: profile, context: pc.context)
        XCTAssertGreaterThan(entry200.computedGL, entry50.computedGL,
            "Larger serving must yield higher GL")
    }

    // MARK: - CL recomputation

    func testRefineCLIsPositiveForSatFatFood() {
        // Bacon has significant saturated fat → positive CL (harmful direction).
        guard let profile = profile(named: "bacon") else { XCTFail("bacon not found in seed DB"); return }
        let entry = makeEntry(cl: 0, grams: 100)
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertGreaterThan(entry.computedCL, 0,
            "Bacon's saturated fat should push CL positive")
    }

    func testRefineCLIsNegativeForHighFiberFood() {
        // Avocado has significant fiber and MUFA → net CL should be negative (beneficial).
        guard let profile = profile(named: "avocado") else { XCTFail("avocado not found in seed DB"); return }
        let entry = makeEntry(cl: 0, grams: 100)
        EntryRefiner.refine(entry: entry, to: profile, context: pc.context)
        XCTAssertLessThan(entry.computedCL, 0,
            "Avocado's fiber and MUFA should push CL negative (beneficial)")
    }
}
