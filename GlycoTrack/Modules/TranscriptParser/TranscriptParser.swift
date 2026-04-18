import Foundation

// iOS app target wrapper — mirrors TranscriptParserCore SPM module.

struct ParsedFood: Codable, Equatable {
    let food: String
    let quantity: String
    let unit: String
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
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
                .replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8),
              let foods = try? JSONDecoder().decode([ParsedFood].self, from: data)
        else { throw ParseError.noFoodsFound }
        return foods
    }
}
