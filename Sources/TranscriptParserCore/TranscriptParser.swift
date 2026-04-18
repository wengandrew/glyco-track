import Foundation

public struct ParsedFood: Codable, Equatable {
    public let food: String
    public let quantity: String
    public let unit: String
    public let grams: Double

    public init(food: String, quantity: String, unit: String, grams: Double) {
        self.food = food
        self.quantity = quantity
        self.unit = unit
        self.grams = grams
    }
}

public enum ParseError: Error, LocalizedError {
    case emptyTranscript
    case noFoodsFound
    case apiError(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript: return "Transcript is empty"
        case .noFoodsFound: return "No foods could be identified in the transcript"
        case .apiError(let err): return "API error: \(err.localizedDescription)"
        }
    }
}

private let systemPrompt = """
You are a food parsing assistant for a health tracking app. The user will give you a voice transcript of what they ate.

Extract each distinct food item from the transcript. Return a JSON array of objects with these exact fields:
- food: canonical food name (lowercase, e.g. "scrambled eggs", "whole wheat toast")
- quantity: numeric quantity as a string (e.g. "2", "1.5", "1")
- unit: unit of measurement (e.g. "eggs", "slice", "cup", "oz", "g", "piece", "tbsp", "serving")
- grams: estimated weight in grams as a number

Rules:
- Create one object per distinct food item
- If the user mentions a combo (e.g. "eggs and toast"), separate them
- If quantity is unclear, assume 1 standard serving
- Always estimate grams based on the quantity and unit
- If no specific food is mentioned, return an empty array []
- Return ONLY the JSON array, no other text, no markdown code fences

Examples:
Input: "I had two scrambled eggs, a slice of whole wheat toast with butter, and a glass of orange juice"
Output: [{"food":"scrambled eggs","quantity":"2","unit":"eggs","grams":100},{"food":"whole wheat toast","quantity":"1","unit":"slice","grams":30},{"food":"butter","quantity":"1","unit":"tsp","grams":5},{"food":"orange juice","quantity":"1","unit":"cup","grams":248}]

Input: "Bowl of oatmeal with blueberries"
Output: [{"food":"oatmeal","quantity":"1","unit":"bowl","grams":250},{"food":"blueberries","quantity":"0.5","unit":"cup","grams":74}]
"""

public final class TranscriptParser {
    private let client: ClaudeAPIClient

    public init(client: ClaudeAPIClient) {
        self.client = client
    }

    public func parse(transcript: String) async throws -> [ParsedFood] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.emptyTranscript }

        let responseText: String
        do {
            responseText = try await client.send(
                system: systemPrompt,
                userMessage: trimmed,
                maxTokens: 512
            )
        } catch {
            throw ParseError.apiError(error)
        }

        return try extractFoods(from: responseText)
    }

    private func extractFoods(from text: String) throws -> [ParsedFood] {
        // Strip any accidental markdown fences
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .components(separatedBy: "\n")
                .dropFirst()
                .joined(separator: "\n")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw ParseError.noFoodsFound
        }

        let foods: [ParsedFood]
        do {
            foods = try JSONDecoder().decode([ParsedFood].self, from: data)
        } catch {
            throw ParseError.noFoodsFound
        }

        return foods
    }
}
