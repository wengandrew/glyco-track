import Foundation
import CoreData

/// Orchestrates: transcript → parse → cascade match → Core Data save
@MainActor
final class FoodLogProcessor: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var lastError: String?

    private var apiKey: String {
        Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
    }

    func process(transcript: String, context: NSManagedObjectContext) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        let client = ClaudeAPIClient(apiKey: apiKey)
        let parser = TranscriptParser(client: client)

        let foods: [ParsedFood]
        do {
            foods = try await parser.parse(transcript: transcript)
        } catch {
            lastError = error.localizedDescription
            return
        }

        guard !foods.isEmpty else {
            lastError = "No foods identified in your recording."
            return
        }

        let nutritionalRepo = NutritionalRepository(context: context)
        let logRepo = FoodLogRepository(context: context)
        let matcher = FoodMatcher(repo: nutritionalRepo, parser: parser)

        for food in foods {
            let resolution = await matcher.resolve(food: food)
            let foodGroup = FoodGroup.classify(food.food).rawValue

            _ = logRepo.create(
                rawTranscript: transcript,
                foodDescription: food.food,
                quantity: [food.quantity, food.unit].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " "),
                quantityGrams: food.grams,
                timestamp: Date(),
                confidenceScore: resolution.confidence,
                parsingMethod: resolution.tier.rawValue,
                referenceFood: resolution.matchSummary,
                foodGroup: foodGroup,
                computedGL: resolution.totalGL,
                computedCL: resolution.totalCL,
                nutritionalProfile: resolution.primaryProfile
            )
        }

        NotificationManager.shared.cancelTodayIfSufficientlyLogged(
            entryCount: logRepo.countToday()
        )
    }
}
