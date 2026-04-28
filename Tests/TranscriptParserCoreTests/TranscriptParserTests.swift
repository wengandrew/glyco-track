import XCTest
@testable import TranscriptParserCore

/// Stub `ClaudeAPISending` that returns a canned response string and records
/// the system / user message it was handed. Lets us exercise the parser
/// surface without touching the network.
final class StubClaudeClient: ClaudeAPISending {
    var nextResponse: String
    var nextError: Error?
    private(set) var lastSystem: String?
    private(set) var lastUserMessage: String?
    private(set) var callCount: Int = 0

    init(nextResponse: String = "[]") {
        self.nextResponse = nextResponse
    }

    func send(system: String, userMessage: String, maxTokens: Int) async throws -> String {
        callCount += 1
        lastSystem = system
        lastUserMessage = userMessage
        if let nextError { throw nextError }
        return nextResponse
    }
}

final class TranscriptParserTests: XCTestCase {

    // MARK: - parse(transcript:)

    func testParseEmptyTranscriptThrows() async {
        let parser = TranscriptParser(client: StubClaudeClient())
        do {
            _ = try await parser.parse(transcript: "   ")
            XCTFail("expected emptyTranscript error")
        } catch let error as ParseError {
            switch error {
            case .emptyTranscript: break
            default: XCTFail("expected .emptyTranscript, got \(error)")
            }
        } catch {
            XCTFail("expected ParseError, got \(error)")
        }
    }

    func testParseHappyPathSingleFood() async throws {
        let stub = StubClaudeClient(nextResponse: """
        [{"food":"oatmeal","quantity":"1","unit":"cup","grams":234}]
        """)
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "I had oatmeal")

        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(foods[0].food, "oatmeal")
        XCTAssertEqual(foods[0].quantity, "1")
        XCTAssertEqual(foods[0].unit, "cup")
        XCTAssertEqual(foods[0].grams, 234)
    }

    func testParseMultipleFoods() async throws {
        let stub = StubClaudeClient(nextResponse: """
        [
          {"food":"scrambled eggs","quantity":"2","unit":"eggs","grams":100},
          {"food":"whole wheat toast","quantity":"1","unit":"slice","grams":30},
          {"food":"orange juice","quantity":"1","unit":"cup","grams":248}
        ]
        """)
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "eggs, toast, OJ")

        XCTAssertEqual(foods.count, 3)
        XCTAssertEqual(foods[0].food, "scrambled eggs")
        XCTAssertEqual(foods[2].food, "orange juice")
    }

    func testParseTolereatesPreambleAndCodeFences() async throws {
        // Claude sometimes wraps the JSON in prose or fences despite the
        // "Return ONLY the JSON array" rule. The extractor finds the first
        // '[' and last ']' and decodes between them — this guards that.
        let stub = StubClaudeClient(nextResponse: """
        Sure, here is the JSON:
        ```json
        [{"food":"banana","quantity":"1","unit":"piece","grams":118}]
        ```
        """)
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "banana")

        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(foods[0].food, "banana")
    }

    func testParseMalformedJSONThrows() async {
        let stub = StubClaudeClient(nextResponse: """
        [{"food":"oatmeal", BROKEN
        """)
        let parser = TranscriptParser(client: stub)

        do {
            _ = try await parser.parse(transcript: "oatmeal")
            XCTFail("expected noFoodsFound error")
        } catch let error as ParseError {
            switch error {
            case .noFoodsFound: break
            default: XCTFail("expected .noFoodsFound, got \(error)")
            }
        } catch {
            XCTFail("expected ParseError, got \(error)")
        }
    }

    func testParseNoBracketsThrows() async {
        let stub = StubClaudeClient(nextResponse: "I cannot parse that.")
        let parser = TranscriptParser(client: stub)

        do {
            _ = try await parser.parse(transcript: "gibberish")
            XCTFail("expected noFoodsFound error")
        } catch let error as ParseError {
            switch error {
            case .noFoodsFound: break
            default: XCTFail("expected .noFoodsFound, got \(error)")
            }
        } catch {
            XCTFail("expected ParseError, got \(error)")
        }
    }

    func testParseEmptyArrayReturnsEmpty() async throws {
        let stub = StubClaudeClient(nextResponse: "[]")
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "no food mentioned")

        XCTAssertEqual(foods, [])
    }

    func testParseAPIErrorWrapsAsParseError() async {
        let stub = StubClaudeClient()
        stub.nextError = ClaudeAPIError.invalidResponse(429)
        let parser = TranscriptParser(client: stub)

        do {
            _ = try await parser.parse(transcript: "anything")
            XCTFail("expected apiError")
        } catch let error as ParseError {
            switch error {
            case .apiError: break
            default: XCTFail("expected .apiError, got \(error)")
            }
        } catch {
            XCTFail("expected ParseError, got \(error)")
        }
    }

    // MARK: - decomposeIngredients

    func testDecomposeHappyPath() async {
        let stub = StubClaudeClient(nextResponse: """
        [{"name":"beef","grams":60},{"name":"rice noodles","grams":90},{"name":"chicken broth","grams":90}]
        """)
        let parser = TranscriptParser(client: stub)

        let ingredients = await parser.decomposeIngredients(foodName: "beef noodle soup", totalGrams: 240)

        XCTAssertEqual(ingredients.count, 3)
        XCTAssertEqual(ingredients[0].name, "beef")
        XCTAssertEqual(ingredients[1].name, "rice noodles")
        XCTAssertEqual(stub.lastUserMessage, "beef noodle soup (240g)")
    }

    func testDecomposeReturnsEmptyOnAPIError() async {
        let stub = StubClaudeClient()
        stub.nextError = ClaudeAPIError.invalidResponse(500)
        let parser = TranscriptParser(client: stub)

        let ingredients = await parser.decomposeIngredients(foodName: "anything", totalGrams: 100)

        XCTAssertEqual(ingredients, [])
    }

    func testDecomposeReturnsEmptyOnMalformedJSON() async {
        let stub = StubClaudeClient(nextResponse: "not even an array")
        let parser = TranscriptParser(client: stub)

        let ingredients = await parser.decomposeIngredients(foodName: "x", totalGrams: 100)

        XCTAssertEqual(ingredients, [])
    }

    // MARK: - Headline-carb prompt rule

    /// The decomposition system prompt must explicitly require that the
    /// staple-carb word in the dish name (noodles, rice, bread, …) appears
    /// in the ingredient list. This prevents the silent-GL=0 regression
    /// observed in production logs (e.g. "hand pulled lamb noodle" decomposed
    /// into lamb + broth + scallion only). Keeping the rule wording in a
    /// test guards against future prompt edits accidentally dropping it.
    func testDecompositionPromptIncludesHeadlineCarbRule() async {
        let stub = StubClaudeClient(nextResponse: "[]")
        let parser = TranscriptParser(client: stub)

        _ = await parser.decomposeIngredients(foodName: "lamb noodle soup", totalGrams: 300)

        let system = stub.lastSystem ?? ""
        XCTAssertTrue(system.contains("HEADLINE-CARB RULE"),
                      "decomposition prompt must keep the HEADLINE-CARB RULE that forces named carbs into the ingredient list")
        XCTAssertTrue(system.contains("noodle"),
                      "headline-carb rule must list 'noodle' among staple carb words")
        XCTAssertTrue(system.contains("rice"),
                      "headline-carb rule must list 'rice' among staple carb words")
    }
}
