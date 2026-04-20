import Foundation

enum SummaryContext {
    case sparse   // < 5 entries
    case moderate // 5–20 entries
    case rich     // > 20 entries
}

@MainActor
final class SummaryGenerator: ObservableObject {
    @Published var summary: String = ""
    @Published var isLoading: Bool = false
    @Published var lastGeneratedAt: Date? {
        didSet {
            if let date = lastGeneratedAt {
                UserDefaults.standard.set(date, forKey: "summaryLastGeneratedAt")
            }
        }
    }

    private let apiKey: String
    private let logRepository: FoodLogRepository

    private static let systemPrompt = """
    You are a nutrition coach for GlycoTrack, an app that tracks Glycemic Load (GL) and Cholesterol Load (CL).

    GL is unsigned (always positive) and measures carbohydrate quality/quantity impact on blood sugar.
    Daily GL budget: 100. Low ≤ 10, Medium 11–19, High ≥ 20 per serving.

    CL is signed: positive = net harmful to cholesterol levels, negative = net beneficial.
    CL formula: (SFA × 1.0) + (TFA × 2.0) − (soluble fiber × 0.5) − (PUFA × 0.7) − (MUFA × 0.5)

    When analyzing the user's log:
    1. Note top GL contributors (foods that most strain the daily budget)
    2. Note CL patterns (overall trend harmful or beneficial)
    3. Call out GL/CL conflicts explicitly (e.g., "oatmeal is great for CL but adds to your GL budget")
    4. Give 1–2 specific, actionable recommendations
    5. Be warm, practical, and non-judgmental
    6. Write in plain conversational prose, no headers or bullet points
    """

    init(apiKey: String, logRepository: FoodLogRepository) {
        self.apiKey = apiKey
        self.logRepository = logRepository
        self.lastGeneratedAt = UserDefaults.standard.object(forKey: "summaryLastGeneratedAt") as? Date
    }

    var needsRegeneration: Bool {
        guard let last = lastGeneratedAt else { return true }
        return Date().timeIntervalSince(last) > 3 * 24 * 60 * 60 // 3 days
    }

    func generateIfNeeded() async {
        guard needsRegeneration else { return }
        await generate()
    }

    func generate() async {
        let entries = logRepository.fetchAll()
        let context = summaryContext(for: entries)
        let prompt = buildPrompt(entries: entries, context: context)

        isLoading = true
        summary = ""
        defer { isLoading = false }

        let client = ClaudeAPIClient(apiKey: apiKey)
        do {
            for try await chunk in client.stream(
                system: Self.systemPrompt,
                userMessage: prompt,
                maxTokens: 600
            ) {
                summary += chunk
            }
            lastGeneratedAt = Date()
        } catch {
            summary = "Unable to generate summary right now. Please try again later."
        }
    }

    private func summaryContext(for entries: [FoodLogEntry]) -> SummaryContext {
        switch entries.count {
        case 0..<5: return .sparse
        case 5...20: return .moderate
        default: return .rich
        }
    }

    private func buildPrompt(entries: [FoodLogEntry], context: SummaryContext) -> String {
        switch context {
        case .sparse:
            return """
            The user has only logged \(entries.count) food item(s) so far. Encourage them to log more meals \
            for better insights, and briefly explain what GlycoTrack tracks.
            """
        case .moderate, .rich:
            let foodSummaries = entries.prefix(50).map { entry in
                let date = DateFormatter.localizedString(from: entry.timestamp ?? Date(), dateStyle: .short, timeStyle: .short)
                return "- \(entry.foodDescription) (\(entry.quantity)) | GL: \(String(format: "%.1f", entry.computedGL)) | CL: \(String(format: "%.2f", entry.computedCL)) | \(date)"
            }.joined(separator: "\n")

            let totalGL = entries.reduce(0.0) { $0 + $1.computedGL }
            let totalCL = entries.reduce(0.0) { $0 + $1.computedCL }
            let avgDailyGL = entries.isEmpty ? 0 : totalGL / Double(Set(entries.map { Calendar.current.startOfDay(for: $0.timestamp ?? Date()) }).count)

            return """
            Here is the user's recent food log (\(entries.count) entries):

            \(foodSummaries)

            Summary stats:
            - Total GL across all entries: \(String(format: "%.1f", totalGL)) (daily budget: 100)
            - Average daily GL: \(String(format: "%.1f", avgDailyGL))
            - Total CL: \(String(format: "%.2f", totalCL)) (positive = net harmful, negative = net beneficial)

            Provide a \(context == .rich ? "full trend analysis with specific actionable recommendations" : "brief analysis highlighting top foods and patterns"). \
            Explicitly call out any GL/CL conflicts.
            """
        }
    }
}
