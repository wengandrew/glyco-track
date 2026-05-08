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
        // No `loggedAt` in the response → caller uses the recording time.
        XCTAssertNil(foods[0].loggedAt)
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

    // MARK: - Time-context (`loggedAt`) decoding

    func testParseDecodesLoggedAtWhenPresent() async throws {
        // Claude includes `loggedAt` because the user said "two hours ago".
        let stub = StubClaudeClient(nextResponse: """
        [{"food":"oatmeal","quantity":"1","unit":"cup","grams":234,"loggedAt":"2026-05-02T12:30:00-07:00"}]
        """)
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "I had one cup of oatmeal two hours ago")

        XCTAssertEqual(foods.count, 1)
        XCTAssertNotNil(foods[0].loggedAt)
        // 2026-05-02T12:30:00-07:00 == 2026-05-02T19:30:00Z.
        let expected = ISO8601DateFormatter().date(from: "2026-05-02T19:30:00Z")
        XCTAssertEqual(foods[0].loggedAt, expected)
    }

    func testParseDecodesLoggedAtPerFoodWhenDifferentTimes() async throws {
        // Per-food anchoring: "toast at 8am and a banana at 10am" yields
        // distinct timestamps on each food.
        let stub = StubClaudeClient(nextResponse: """
        [
          {"food":"toast","quantity":"1","unit":"slice","grams":30,"loggedAt":"2026-05-02T08:00:00-07:00"},
          {"food":"banana","quantity":"1","unit":"piece","grams":118,"loggedAt":"2026-05-02T10:00:00-07:00"}
        ]
        """)
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "toast at 8am and a banana at 10am")

        XCTAssertEqual(foods.count, 2)
        XCTAssertNotNil(foods[0].loggedAt)
        XCTAssertNotNil(foods[1].loggedAt)
        XCTAssertNotEqual(foods[0].loggedAt, foods[1].loggedAt)
    }

    func testParseTreatsExplicitNullLoggedAtAsNil() async throws {
        // Tolerance: if Claude emits `"loggedAt": null` instead of omitting
        // the key, the parser should still treat it as absent.
        let stub = StubClaudeClient(nextResponse: """
        [{"food":"banana","quantity":"1","unit":"piece","grams":118,"loggedAt":null}]
        """)
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "banana")

        XCTAssertEqual(foods.count, 1)
        XCTAssertNil(foods[0].loggedAt)
    }

    func testParseIgnoresMalformedLoggedAtString() async throws {
        // If Claude returns garbage in `loggedAt`, fall back to nil rather
        // than throwing — better to use the recording time than to drop the
        // whole entry. This is the same robustness contract the parser
        // already has for surrounding-prose tolerance.
        let stub = StubClaudeClient(nextResponse: """
        [{"food":"banana","quantity":"1","unit":"piece","grams":118,"loggedAt":"yesterday"}]
        """)
        let parser = TranscriptParser(client: stub)

        let foods = try await parser.parse(transcript: "banana")

        XCTAssertEqual(foods.count, 1)
        XCTAssertNil(foods[0].loggedAt)
    }

    // MARK: - Time-context (prompt + user-message contract)

    func testParseUserMessageIncludesCurrentTimePrefix() async throws {
        // The parser must hand Claude the current time so relative phrases
        // can be resolved. Format: "Current time: <ISO8601>\nTranscript: ...".
        let stub = StubClaudeClient(nextResponse: "[]")
        let parser = TranscriptParser(client: stub)

        let fixedNow = ISO8601DateFormatter().date(from: "2026-05-02T14:30:00Z") ?? Date()
        _ = try await parser.parse(transcript: "I had oatmeal", currentTime: fixedNow)

        let userMessage = stub.lastUserMessage ?? ""
        XCTAssertTrue(userMessage.hasPrefix("Current time: "),
                      "user message must lead with 'Current time:' so Claude can anchor relative time phrases — got: \(userMessage)")

        // Extract the ISO-8601 timestamp, verify it carries a timezone offset,
        // and round-trip it back to a Date to confirm it encodes fixedNow.
        let tsPattern = #"Current time: (\S+)"#
        let tsMatch = userMessage.range(of: tsPattern, options: .regularExpression)
        XCTAssertNotNil(tsMatch, "could not find timestamp in: \(userMessage)")
        if let range = tsMatch {
            let token = String(userMessage[range]).replacingOccurrences(of: "Current time: ", with: "")
            // Must include a timezone designator (Z or ±HH:MM).
            let hasOffset = token.range(of: #"[+-]\d{2}:\d{2}$|Z$"#, options: .regularExpression) != nil
            XCTAssertTrue(hasOffset, "timestamp must include a timezone offset — got: \(token)")
            // Parsing the token back must recover fixedNow exactly.
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime]
            let recovered = parser.date(from: token)
            XCTAssertNotNil(recovered, "timestamp in user message could not be parsed: \(token)")
            XCTAssertEqual(recovered, fixedNow,
                           "timestamp in user message must equal the supplied currentTime — got: \(token)")
        }

        XCTAssertTrue(userMessage.contains("Transcript: I had oatmeal"),
                      "user message must include the trimmed transcript on its own line — got: \(userMessage)")
    }

    /// The system prompt must keep the time-context rules. Production behavior
    /// hinges on Claude emitting `loggedAt` only when the user said something
    /// time-anchored — drift here would either flood every entry with a
    /// (probably-wrong) timestamp or drop the feature entirely.
    func testSystemPromptIncludesTimeContextRules() async throws {
        let stub = StubClaudeClient(nextResponse: "[]")
        let parser = TranscriptParser(client: stub)

        _ = try await parser.parse(transcript: "anything")

        let system = stub.lastSystem ?? ""
        XCTAssertTrue(system.contains("loggedAt"),
                      "system prompt must define the loggedAt field")
        XCTAssertTrue(system.contains("OPTIONAL") || system.contains("optional"),
                      "system prompt must mark loggedAt as optional")
        XCTAssertTrue(system.contains("OMIT") || system.contains("omit"),
                      "system prompt must instruct Claude to omit loggedAt when no time is mentioned")
        XCTAssertTrue(system.contains("ago"),
                      "system prompt must explain relative-time resolution (e.g. 'X hours ago')")
        XCTAssertTrue(system.contains("yesterday"),
                      "system prompt must explain absolute relative dates ('yesterday at <time>')")
        XCTAssertTrue(system.contains("breakfast") && system.contains("lunch") && system.contains("dinner"),
                      "system prompt must define meal-name defaults (breakfast/lunch/dinner)")
        XCTAssertTrue(system.contains("NEVER set `loggedAt` to a time after"),
                      "system prompt must forbid future timestamps")
    }

    // MARK: - ParsedFood Codable round-trip

    func testParsedFoodRoundTripWithoutLoggedAt() throws {
        // Encoding and decoding a ParsedFood with no loggedAt must preserve all fields exactly.
        let original = ParsedFood(food: "oatmeal", quantity: "1", unit: "cup", grams: 234.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParsedFood.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.loggedAt, "loggedAt must be nil when not set")
    }

    func testParsedFoodRoundTripWithLoggedAt() throws {
        // loggedAt must survive encode → decode. The ISO-8601 round-trip may shift
        // the timezone offset in the string but must preserve the exact moment in time.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let date = f.date(from: "2026-05-02T14:30:00Z")!
        let original = ParsedFood(food: "banana", quantity: "1", unit: "piece", grams: 118.0, loggedAt: date)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParsedFood.self, from: data)
        XCTAssertNotNil(decoded.loggedAt)
        // ISO8601.string(from:) formats whole seconds; ISO8601.parse recovers the exact
        // same moment, so the round-trip is lossless and strict equality holds.
        XCTAssertEqual(decoded.loggedAt!, date, "loggedAt must round-trip exactly through encode/decode")
        XCTAssertEqual(decoded.food, original.food)
        XCTAssertEqual(decoded.grams, original.grams)
    }

    // MARK: - ISO8601 fractional-second parsing

    func testISO8601ParsesFractionalSeconds() {
        // Claude occasionally emits fractional-second timestamps. The parser must accept them.
        let raw = "2026-05-02T14:30:00.000-07:00"
        let parsed = ISO8601.parse(raw)
        XCTAssertNotNil(parsed, "ISO8601.parse must accept fractional-second strings from Claude")

        // Verify the parsed date equals the same moment without fractional seconds.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let expected = f.date(from: "2026-05-02T14:30:00-07:00")!
        XCTAssertEqual(parsed!, expected)
    }

    // MARK: - decomposeIngredients gram rounding

    func testDecomposeUserMessageRoundsGramsToInt() async {
        // totalGrams is passed as Int(rounded()) in the user message — verify the format.
        let stub = StubClaudeClient(nextResponse: "[]")
        let parser = TranscriptParser(client: stub)

        _ = await parser.decomposeIngredients(foodName: "pasta", totalGrams: 245.7)

        // 245.7 rounds to 246, so the message must be "pasta (246g)"
        XCTAssertEqual(stub.lastUserMessage, "pasta (246g)",
                       "decomposeIngredients must format totalGrams as Int(rounded()) in the user message")
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
