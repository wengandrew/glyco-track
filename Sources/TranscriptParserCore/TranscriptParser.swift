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

/// One atomic ingredient inside a composite dish, as inferred by the
/// ingredient-decomposition pass (Option A). Grams are the portion of the
/// dish's total weight attributed to this ingredient.
public struct ParsedIngredient: Codable, Equatable {
    public let name: String
    public let grams: Double

    public init(name: String, grams: Double) {
        self.name = name
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

    /// Decompose a composite dish name into its atomic ingredients with gram
    /// estimates. Returns an empty array if Claude cannot decompose the dish.
    /// Never throws — the caller treats a failed decomposition as "no Option A
    /// contribution" and falls through to the next cascade step.
    public func decomposeIngredients(foodName: String, totalGrams: Double) async -> [ParsedIngredient] {
        let userMessage = "\(foodName) (\(Int(totalGrams.rounded()))g)"
        do {
            let text = try await client.send(
                system: decompositionPrompt,
                userMessage: userMessage,
                maxTokens: 384
            )
            return extractIngredients(from: text)
        } catch {
            return []
        }
    }

    private func extractFoods(from text: String) throws -> [ParsedFood] {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else {
            throw ParseError.noFoodsFound
        }
        let jsonSlice = String(text[start...end])
        guard let data = jsonSlice.data(using: .utf8) else {
            throw ParseError.noFoodsFound
        }
        do {
            return try JSONDecoder().decode([ParsedFood].self, from: data)
        } catch {
            throw ParseError.noFoodsFound
        }
    }

    private func extractIngredients(from text: String) -> [ParsedIngredient] {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return [] }
        let jsonSlice = String(text[start...end])
        guard let data = jsonSlice.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ParsedIngredient].self, from: data)) ?? []
    }
}
