import Foundation
import CoreData

/// Orchestrates: transcript → parse → GI lookup → CL lookup → Core Data save
@MainActor
final class FoodLogProcessor: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var lastError: String?

    private var apiKey: String {
        Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
    }

    func process(transcript: String, context: NSManagedObjectContext) async {
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
        let giEngine = GIEngine(database: GIDatabase(records: loadGIDatabase()))
        let clEngine = CLEngine()

        for food in foods {
            let match = nutritionalRepo.findBestMatch(for: food.food)
            let profile = match?.profile

            let carbsPer100g = profile?.carbsPer100g ?? 0

            let glResult = giEngine.computeGL(
                foodName: food.food,
                quantityGrams: food.grams,
                carbsPer100g: carbsPer100g
            )

            let nutrition = NutritionInput(
                saturatedFatPer100g: profile?.saturatedFatPer100g ?? 0,
                transFatPer100g: profile?.transFatPer100g ?? 0,
                solubleFiberPer100g: profile?.solubleFiberPer100g ?? 0,
                pufaPer100g: profile?.pufaPer100g ?? 0,
                mufaPer100g: profile?.mufaPer100g ?? 0
            )
            let clResult = clEngine.computeCL(nutrition: nutrition, quantityGrams: food.grams)

            let tier = match.map { Int16($0.tier) } ?? Int16(glResult.tier)
            let confidence = match.map { $0.confidence } ?? glResult.confidence
            let foodGroup = FoodGroup.classify(food.food).rawValue

            _ = logRepo.create(
                rawTranscript: transcript,
                foodDescription: food.food,
                quantity: food.quantity,
                quantityGrams: food.grams,
                timestamp: Date(),
                confidenceScore: confidence,
                parsingMethod: tier,
                referenceFood: match?.profile.foodName,
                foodGroup: foodGroup,
                computedGL: glResult.gl,
                computedCL: clResult.cl,
                nutritionalProfile: profile
            )
        }

        NotificationManager.shared.cancelTodayIfSufficientlyLogged(
            entryCount: logRepo.countToday()
        )
    }

    private func loadGIDatabase() -> [GIRecord] {
        guard
            let url = Bundle.main.url(forResource: "gi_database", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let records = try? JSONDecoder().decode([GIRecord].self, from: data)
        else { return [] }
        return records
    }
}
