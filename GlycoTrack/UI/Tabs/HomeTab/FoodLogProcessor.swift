import Foundation
import CoreData

/// Orchestrates: transcript → parse → cascade match → Core Data save
@MainActor
final class FoodLogProcessor: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var lastError: String?

    func process(transcript: String, context: NSManagedObjectContext) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        let client = ClaudeAPIClient(apiKey: APIKey.claude)
        let parser = TranscriptParser(client: client)

        // Anchor the parser's time-context resolution to the moment the user
        // finished speaking. Captured once so every food in this transcript
        // resolves "now" against the same instant — and so the fallback
        // (omitted `loggedAt` → recording time) is consistent across foods.
        let recordedAt = Date()

        let foods: [ParsedFood]
        do {
            foods = try await parser.parse(transcript: transcript, currentTime: recordedAt)
        } catch {
            Log.network.error("TranscriptParser.parse failed: \(error.localizedDescription, privacy: .public)")
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

        var unrecognizedNames: [String] = []

        for food in foods {
            let resolution = await matcher.resolve(food: food)

            // Don't log entries we couldn't match — GL=0/CL=0 would silently
            // corrupt daily totals. Collect names and surface them as an error
            // so the user can re-try with a more specific description.
            if resolution.tier == .unrecognized {
                unrecognizedNames.append(food.food)
                continue
            }

            // `food.loggedAt` is set when Claude detected a time phrase in the
            // transcript ("two hours ago", "yesterday at 5pm", …). Otherwise
            // we fall back to the recording time. Defensive clamp to
            // `recordedAt` in case Claude returns a future timestamp despite
            // the prompt rule against it.
            let resolved = food.loggedAt.map { min($0, recordedAt) } ?? recordedAt

            _ = logRepo.create(
                rawTranscript: transcript,
                foodDescription: food.food,
                quantity: [food.quantity, food.unit].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " "),
                quantityGrams: food.grams,
                timestamp: resolved,
                confidenceScore: resolution.confidence,
                parsingMethod: resolution.tier.rawValue,
                referenceFood: resolution.matchSummary,
                computedGL: resolution.totalGL,
                computedCL: resolution.totalCL,
                nutritionalProfile: resolution.primaryProfile
            )
        }

        if !unrecognizedNames.isEmpty {
            let names = unrecognizedNames.map { "\"\($0)\"" }.joined(separator: ", ")
            lastError = "Couldn't recognize \(names) — try a more specific name."
        }

        NotificationManager.shared.cancelTodayIfSufficientlyLogged(
            entryCount: logRepo.countToday()
        )
    }
}
