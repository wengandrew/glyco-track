import Foundation

/// HTTP client for Anthropic's Messages API. Used by:
///
/// - `TranscriptParser.parse()` for voice-transcript → ParsedFood JSON
/// - `TranscriptParser.decomposeIngredients()` for composite-dish → ingredient JSON
/// - `LogTabView`'s edit-recompute path (which goes through TranscriptParser)
///
/// Mirrors the SPM-target version at
/// `Sources/TranscriptParserCore/ClaudeAPIClient.swift` — keep them in
/// sync when changing the API surface.
final class ClaudeAPIClient {
    static let model = "claude-sonnet-4-6"
    private static let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Send a message to Claude and receive the full text response (non-streaming).
    /// Used by transcript parsing and ingredient decomposition where partial
    /// streaming would be wasted — those callers need the full JSON before
    /// they can act on it.
    func send(system: String, userMessage: String, maxTokens: Int = 1024) async throws -> String {
        struct Msg: Encodable { let role: String; let content: String }
        struct Req: Encodable {
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Msg]
            let stream: Bool
        }
        struct Block: Decodable { let type: String; let text: String? }
        struct Resp: Decodable { let content: [Block] }

        let req = Req(
            model: Self.model,
            max_tokens: maxTokens,
            system: system,
            messages: [Msg(role: "user", content: userMessage)],
            stream: false
        )

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
