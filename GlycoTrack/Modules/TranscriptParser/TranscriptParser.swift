// swiftlint:disable line_length
//
// The system prompts in this file are intentional walls of text — both
// the rules block and the few-shot examples are calibrated together as a
// unit, and reflowing them would break the JSON layout of the examples.
// Wrapping them at 220 chars would obscure the contract more than it'd
// help any reader. Disable line_length file-wide here, not in
// .swiftlint.yml, so the choice is visible at the call site.

import Foundation

// iOS app target wrapper — mirrors TranscriptParserCore SPM module.

struct ParsedFood: Codable, Equatable {
    let food: String
    let quantity: String
    let unit: String
    let grams: Double
    /// Resolved consumption time when the user said something time-anchored
    /// in the transcript ("two hours ago", "yesterday at 5pm", …). `nil`
    /// means the user said nothing about timing — caller falls back to "now".
    let loggedAt: Date?

    init(food: String, quantity: String, unit: String, grams: Double, loggedAt: Date? = nil) {
        self.food = food
        self.quantity = quantity
        self.unit = unit
        self.grams = grams
        self.loggedAt = loggedAt
    }

    private enum CodingKeys: String, CodingKey {
        case food, quantity, unit, grams, loggedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        food = try c.decode(String.self, forKey: .food)
        quantity = try c.decode(String.self, forKey: .quantity)
        unit = try c.decode(String.self, forKey: .unit)
        grams = try c.decode(Double.self, forKey: .grams)
        if let raw = try c.decodeIfPresent(String.self, forKey: .loggedAt) {
            loggedAt = ISO8601Helper.parse(raw)
        } else {
            loggedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(food, forKey: .food)
        try c.encode(quantity, forKey: .quantity)
        try c.encode(unit, forKey: .unit)
        try c.encode(grams, forKey: .grams)
        if let loggedAt {
            try c.encode(ISO8601Helper.string(from: loggedAt), forKey: .loggedAt)
        }
    }
}

/// File-scoped helpers — kept private to avoid clashing with any other
/// ISO8601 utility a sibling module might want to introduce.
private enum ISO8601Helper {
    // Parsing: timezone-agnostic — ISO8601DateFormatter honours the offset
    // embedded in the string, so `timeZone` on the formatter only matters when
    // the input has no offset (which Claude never produces here).
    private static let basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Formatting: use the device's local timezone so Claude receives the
    // correct wall-clock offset (e.g. "-05:00") and resolves "for breakfast"
    // or "last night" against the right calendar day. Without this the
    // formatter defaults to UTC, which produces timestamps like 03:00Z for
    // a user in UTC-5 — Claude would then map "for breakfast" to 08:00Z
    // (03:00 local), making every time-anchored entry hours off.
    // autoupdatingCurrent (not current) ensures a mid-session DST or manual
    // timezone change is reflected immediately.
    private static let localFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone.autoupdatingCurrent
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        basic.date(from: raw) ?? fractional.date(from: raw)
    }

    static func string(from date: Date) -> String {
        localFormatter.string(from: date)
    }
}

struct ParsedIngredient: Codable, Equatable {
    let name: String
    let grams: Double
}

enum ParseError: Error, LocalizedError {
    case emptyTranscript
    case noFoodsFound
    case apiError(Error)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript: return "Transcript is empty"
        case .noFoodsFound: return "No foods identified in the recording"
        case .apiError(let e): return e.localizedDescription
        }
    }
}

private let systemPrompt = """
You are a food parsing assistant for a health tracking app. The user message has two lines:
  Current time: <ISO-8601 timestamp with timezone offset>
  Transcript: <what the user said about what they ate>

Extract each distinct food item from the transcript. Return a JSON array of objects with these exact fields:
- food: canonical food name (lowercase)
- quantity: numeric quantity as a string (e.g. "2", "1.5", "1")
- unit: unit of measurement (e.g. "eggs", "slice", "cup", "oz", "g", "piece", "tbsp", "serving")
- grams: estimated weight in grams as a number
- loggedAt (OPTIONAL): ISO-8601 timestamp in the SAME timezone offset as the supplied current time. Include ONLY when the user mentioned when they ate; OMIT the field entirely otherwise.

Time-context rules:
- DEFAULT: omit `loggedAt`. Most transcripts ("I had a banana") have no time context — leave the field out so the app uses the recording time.
- INCLUDE `loggedAt` when the transcript contains a clear absolute or relative time phrase. Resolve it against the supplied current time:
  - "X hours/minutes ago", "X days ago" → subtract from current time.
  - Specific clock time ("at 9am", "at 5:30 pm") → today at that time. If that would be in the future, use yesterday at that time instead.
  - "this morning" (no clock time) → 8:00 AM today. "this afternoon" → 1:00 PM. "this evening" → 7:00 PM.
  - "for breakfast" → 8:00 AM today (or yesterday if current time is before 8 AM). "for lunch" → 12:30 PM. "for dinner" → 7:00 PM.
  - "yesterday" / "yesterday at <time>" / "last night" → previous calendar day at the named time (or the appropriate meal default if no clock time).
  - "just now", "a moment ago" → current time minus 1 minute.
- Per-food: if the transcript anchors different foods to different times, give each its own `loggedAt`. If a single time covers all foods, use the same `loggedAt` on each.
- NEVER set `loggedAt` to a time after the supplied current time. Clamp to current time if your computation would put it in the future.
- Use the SAME timezone offset as the supplied current time. Do not convert to UTC.

Other rules:
- Create one object per distinct food item.
- If the user mentions a combo, separate them.
- If quantity is unclear, assume 1 standard serving.
- Always estimate grams based on the quantity and unit.
- If no specific food is mentioned, return [].
- Return ONLY the JSON array, no other text, no markdown code fences.

Examples:

Current time: 2026-05-02T14:30:00-07:00
Transcript: "I had two scrambled eggs, a slice of whole wheat toast with butter, and orange juice"
Output: [{"food":"scrambled eggs","quantity":"2","unit":"eggs","grams":100},{"food":"whole wheat toast","quantity":"1","unit":"slice","grams":30},{"food":"butter","quantity":"1","unit":"tsp","grams":5},{"food":"orange juice","quantity":"1","unit":"cup","grams":248}]

Current time: 2026-05-02T14:30:00-07:00
Transcript: "I had one cup of oatmeal two hours ago"
Output: [{"food":"oatmeal","quantity":"1","unit":"cup","grams":234,"loggedAt":"2026-05-02T12:30:00-07:00"}]

Current time: 2026-05-02T14:30:00-07:00
Transcript: "Yesterday at 5pm I had a slice of pizza"
Output: [{"food":"pizza","quantity":"1","unit":"slice","grams":107,"loggedAt":"2026-05-01T17:00:00-07:00"}]

Current time: 2026-05-02T14:30:00-07:00
Transcript: "I had toast at 8am and a banana at 10am"
Output: [{"food":"toast","quantity":"1","unit":"slice","grams":30,"loggedAt":"2026-05-02T08:00:00-07:00"},{"food":"banana","quantity":"1","unit":"piece","grams":118,"loggedAt":"2026-05-02T10:00:00-07:00"}]
"""

private let decompositionPrompt = """
You are a culinary ingredient decomposer for a nutrition-tracking app. The user will give you the name of a composite dish and its total weight in grams. Break the dish into its atomic ingredients with realistic gram estimates that sum to (approximately) the total weight.

Return a JSON array of objects with these exact fields:
- name: the ingredient as a common, lowercased single food (e.g. "beef", "rice noodles", "chicken broth", "bok choy", "soy sauce")
- grams: estimated portion in grams as a number

Rules:
- Use common singular food names that would appear in a standard nutrition database. Prefer simple forms ("beef" not "thin-sliced beef brisket"; "rice noodles" not "fresh flat rice noodles").
- The ingredient grams should sum to roughly the total dish weight (±15%). Broth/water-heavy dishes can include "broth" as an ingredient.
- Omit negligible ingredients (<3g) like salt, pepper, small garnishes. Keep the list to 2–6 key ingredients.
- HEADLINE-CARB RULE: if the dish name contains a staple carb word — "noodle(s)", "pasta", "spaghetti", "rice", "bread", "bun", "tortilla", "flour", "dumpling", "pancake", "wrap", "roll" — the ingredient list MUST include that carb (or a more specific variant of it: "rice noodles", "wheat noodles", "white rice", "whole wheat flour"). Never omit the carb that's literally named in the dish; doing so silently zeroes the GL.
- Return ONLY the JSON array. No prose, no markdown, no code fences.

Examples:
Input: "beef noodle soup" (250g)
Output: [{"name":"beef","grams":60},{"name":"rice noodles","grams":90},{"name":"chicken broth","grams":90},{"name":"bok choy","grams":15}]

Input: "hand pulled lamb noodle" (300g)
Output: [{"name":"lamb","grams":100},{"name":"wheat noodles","grams":140},{"name":"bone broth","grams":50},{"name":"scallion","grams":10}]

Input: "mixed rice with vegetables" (250g)
Output: [{"name":"white rice","grams":150},{"name":"carrot","grams":40},{"name":"peas","grams":35},{"name":"corn","grams":25}]

Input: "chicken caesar salad" (300g)
Output: [{"name":"grilled chicken","grams":120},{"name":"romaine lettuce","grams":130},{"name":"caesar dressing","grams":30},{"name":"parmesan cheese","grams":15}]

Input: "cheeseburger" (220g)
Output: [{"name":"beef patty","grams":110},{"name":"cheddar cheese","grams":25},{"name":"hamburger bun","grams":70},{"name":"lettuce","grams":10}]
"""

// `ClaudeAPIClient` lives in `Modules/ClaudeAPI/ClaudeAPIClient.swift` —
// it's used by the Edit-recompute path independently of TranscriptParser,
// so it doesn't belong nested inside this file.

final class TranscriptParser {
    private let client: ClaudeAPIClient

    init(client: ClaudeAPIClient) {
        self.client = client
    }

    func parse(transcript: String, currentTime: Date = Date()) async throws -> [ParsedFood] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.emptyTranscript }

        // Hand Claude the wall-clock time so it can resolve relative phrases
        // ("two hours ago", "yesterday at 5pm", "for breakfast") into absolute
        // ISO-8601 timestamps in `loggedAt`.
        let userMessage = "Current time: \(ISO8601Helper.string(from: currentTime))\nTranscript: \(trimmed)"

        let text = try await client.send(system: systemPrompt, userMessage: userMessage, maxTokens: 512)
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else {
            throw ParseError.noFoodsFound
        }
        let jsonSlice = String(text[start...end])
        guard let data = jsonSlice.data(using: .utf8),
              let foods = try? JSONDecoder().decode([ParsedFood].self, from: data)
        else { throw ParseError.noFoodsFound }
        return foods
    }

    /// Decompose a composite dish name into atomic ingredients with gram estimates.
    /// Returns an empty array on any failure so the caller can fall through.
    func decomposeIngredients(foodName: String, totalGrams: Double) async -> [ParsedIngredient] {
        let userMessage = "\(foodName) (\(Int(totalGrams.rounded()))g)"
        do {
            let text = try await client.send(system: decompositionPrompt, userMessage: userMessage, maxTokens: 384)
            guard let start = text.firstIndex(of: "["),
                  let end = text.lastIndex(of: "]") else { return [] }
            let jsonSlice = String(text[start...end])
            guard let data = jsonSlice.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ParsedIngredient].self, from: data)) ?? []
        } catch {
            return []
        }
    }
}
