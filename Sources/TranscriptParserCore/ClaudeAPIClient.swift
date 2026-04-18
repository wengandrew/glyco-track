import Foundation

public struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

public struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let stream: Bool
}

public struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
}

public struct ClaudeResponse: Decodable {
    let content: [ClaudeContentBlock]
}

public enum ClaudeAPIError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse(Int)
    case decodingFailed(String)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Claude API key not configured in Info.plist"
        case .invalidResponse(let code): return "API returned HTTP \(code)"
        case .decodingFailed(let msg): return "Failed to decode response: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

public final class ClaudeAPIClient {
    public static let model = "claude-sonnet-4-6"
    private static let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Send a message to Claude and receive the full text response (non-streaming).
    public func send(system: String, userMessage: String, maxTokens: Int = 1024) async throws -> String {
        let request = ClaudeRequest(
            model: Self.model,
            max_tokens: maxTokens,
            system: system,
            messages: [ClaudeMessage(role: "user", content: userMessage)],
            stream: false
        )

        var urlRequest = URLRequest(url: Self.baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ClaudeAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse(0)
        }
        guard httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.invalidResponse(httpResponse.statusCode)
        }

        let decoded: ClaudeResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            throw ClaudeAPIError.decodingFailed(error.localizedDescription)
        }

        let text = decoded.content.compactMap { $0.text }.joined()
        return text
    }

    /// Convenience: send and stream text deltas via AsyncThrowingStream.
    public func stream(system: String, userMessage: String, maxTokens: Int = 1024) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await self.send(system: system, userMessage: userMessage, maxTokens: maxTokens)
                    // Simulate streaming by yielding in chunks
                    for word in text.components(separatedBy: " ") {
                        continuation.yield(word + " ")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
