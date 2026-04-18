import CoreData
import Foundation

final class NutritionalRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.context) {
        self.context = context
    }

    func findBestMatch(for foodName: String) -> (profile: NutritionalProfile, tier: Int16, confidence: Float)? {
        let normalized = foodName.lowercased().trimmingCharacters(in: .whitespaces)

        // Tier 1: exact match
        if let exact = fetchExact(normalized) {
            return (exact, 1, 0.95)
        }

        // Tier 1: contains match (e.g. "white rice" matches "steamed white rice")
        if let contains = fetchContains(normalized) {
            return (contains, 1, 0.87)
        }

        // Tier 2: fuzzy match via Levenshtein
        if let (fuzzy, distance) = fetchFuzzy(normalized) {
            let confidence: Float = distance <= 1 ? 0.80 : distance <= 2 ? 0.70 : 0.55
            return (fuzzy, 2, confidence)
        }

        return nil
    }

    private func fetchExact(_ name: String) -> NutritionalProfile? {
        let request = NutritionalProfile.fetchRequest()
        request.predicate = NSPredicate(format: "foodName ==[cd] %@", name)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchContains(_ name: String) -> NutritionalProfile? {
        let request = NutritionalProfile.fetchRequest()
        request.predicate = NSPredicate(format: "foodName CONTAINS[cd] %@", name)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchFuzzy(_ name: String) -> (NutritionalProfile, Int)? {
        let request = NutritionalProfile.fetchRequest()
        let all = (try? context.fetch(request)) ?? []
        var best: (NutritionalProfile, Int)?
        for profile in all {
            let d = levenshtein(name, profile.foodName.lowercased())
            if d <= 3 {
                if best == nil || d < best!.1 {
                    best = (profile, d)
                }
            }
        }
        return best
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aArr = Array(a)
        let bArr = Array(b)
        let m = aArr.count, n = bArr.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                if aArr[i-1] == bArr[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                }
            }
        }
        return dp[m][n]
    }
}
