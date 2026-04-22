import Foundation

// iOS app target wrapper — mirrors TranscriptParserCore SPM module.

struct ParsedFood: Codable, Equatable {
    let food: String
    let quantity: String
    let unit: String
    let grams: Double
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
You are a food parsing assistant for a health tracking app. The user will give you a voice transcript of what they ate.

Extract each distinct food item from the transcript. Return a JSON array of objects with these exact fields:
- food: canonical food name (lowercase)
- quantity: numeric quantity as a string (e.g. "2", "1.5", "1")
- unit: unit of measurement (e.g. "eggs", "slice", "cup", "oz", "g", "piece", "tbsp", "serving")
- grams: estimated weight in grams as a number

Rules:
- Create one object per distinct food item
- If the user mentions a combo, separate them
- If quantity is unclear, assume 1 standard serving
- Always estimate grams based on the quantity and unit
- If no specific food is mentioned, return []
- Return ONLY the JSON array, no other text, no markdown code fences

Examples:
Input: "I had two scrambled eggs, a slice of whole wheat toast with butter, and orange juice"
Output: [{"food":"scrambled eggs","quantity":"2","unit":"eggs","grams":100},{"food":"whole wheat toast","quantity":"1","unit":"slice","grams":30},{"food":"butter","quantity":"1","unit":"tsp","grams":5},{"food":"orange juice","quantity":"1","unit":"cup","grams":248}]
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
- Return ONLY the JSON array. No prose, no markdown, no code fences.

Examples:
Input: "beef noodle soup" (250g)
Output: [{"name":"beef","grams":60},{"name":"rice noodles","grams":90},{"name":"chicken broth","grams":90},{"name":"bok choy","grams":15}]

Input: "chicken caesar salad" (300g)
Output: [{"name":"grilled chicken","grams":120},{"name":"romaine lettuce","grams":130},{"name":"caesar dressing","grams":30},{"name":"parmesan cheese","grams":15}]

Input: "cheeseburger" (220g)
Output: [{"name":"beef patty","grams":110},{"name":"cheddar cheese","grams":25},{"name":"hamburger bun","grams":70},{"name":"lettuce","grams":10}]
"""

final class ClaudeAPIClient {
    static let model = "claude-sonnet-4-6"
    private static let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func send(system: String, userMessage: String, maxTokens: Int = 1024) async throws -> String {
        struct Msg: Encodable { let role: String; let content: String }
        struct Req: Encodable { let model: String; let max_tokens: Int; let system: String; let messages: [Msg]; let stream: Bool }
        struct Block: Decodable { let type: String; let text: String? }
        struct Resp: Decodable { let content: [Block] }

        let req = Req(model: Self.model, max_tokens: maxTokens, system: system,
                      messages: [Msg(role: "user", content: userMessage)], stream: false)

        var urlReq = URLRequest(url: Self.baseURL)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlReq.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlReq.httpBody = try JSONEncoder().encode(req)

        let (data, response) = try await URLSession.shared.data(for: urlReq)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.content.compactMap(\.text).joined()
    }

    /// Stream text tokens via SSE. Yields deltas as they arrive from the API.
    func stream(system: String, userMessage: String, maxTokens: Int = 1024) -> AsyncThrowingStream<String, Error> {
        struct Msg: Encodable { let role: String; let content: String }
        struct Req: Encodable { let model: String; let max_tokens: Int; let system: String; let messages: [Msg]; let stream: Bool }
        struct Event: Decodable { let type: String; let delta: Delta? }
        struct Delta: Decodable { let type: String?; let text: String? }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let req = Req(model: Self.model, max_tokens: maxTokens, system: system,
                                  messages: [Msg(role: "user", content: userMessage)], stream: true)
                    var urlReq = URLRequest(url: Self.baseURL)
                    urlReq.httpMethod = "POST"
                    urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlReq.setValue(self.apiKey, forHTTPHeaderField: "x-api-key")
                    urlReq.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
                    urlReq.httpBody = try JSONEncoder().encode(req)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlReq)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]",
                              let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(Event.self, from: data),
                              event.type == "content_block_delta",
                              event.delta?.type == "text_delta",
                              let text = event.delta?.text
                        else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

final class TranscriptParser {
    private let client: ClaudeAPIClient

    init(client: ClaudeAPIClient) {
        self.client = client
    }

    func parse(transcript: String) async throws -> [ParsedFood] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.emptyTranscript }

        let text = try await client.send(system: systemPrompt, userMessage: trimmed, maxTokens: 512)
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
