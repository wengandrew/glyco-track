import CoreData
import Foundation

/// Result of a direct (whole-name) match. Tier 1 territory.
struct DirectMatch {
    let profile: NutritionalProfile
    let confidence: Float
}

/// Result of a reverse-substring component match (Option B).
/// The DB entry's foodName (or alias) appears inside the user's query string.
struct ComponentMatch {
    let profile: NutritionalProfile
    /// The substring of the user's query that matched this DB entry.
    let matchedToken: String
    /// Character-length coverage contribution (used for confidence scoring).
    let coverage: Int
}

final class NutritionalRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.context) {
        self.context = context
    }

    /// Tier 1: strict direct-match lookup on the full food name.
    /// Only returns a hit when the query matches a DB entry as a whole — not when
    /// a random DB token happens to appear inside a composite name. Use
    /// `findComponents(for:)` for that case.
    func findBestMatch(for foodName: String) -> DirectMatch? {
        let normalized = foodName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }

        if let exact = fetchExact(normalized) {
            return DirectMatch(profile: exact, confidence: 0.95)
        }

        // DB entry whose name CONTAINS the query — e.g. user says "white rice",
        // DB has "steamed white rice". The query is a substring of the DB entry.
        if let contains = fetchDBNameContainsQuery(normalized) {
            return DirectMatch(profile: contains, confidence: 0.85)
        }

        // Fuzzy match via Levenshtein — only useful for typos/minor variation,
        // NOT for composite dishes (distance to "beef noodle soup" is huge).
        if let (fuzzy, distance) = fetchFuzzy(normalized) {
            let confidence: Float = distance <= 1 ? 0.80 : distance <= 2 ? 0.70 : 0.55
            return DirectMatch(profile: fuzzy, confidence: confidence)
        }

        return nil
    }

    /// Tier 2: reverse-substring decomposition (Option B).
    /// Returns DB entries whose foodName appears inside the user's query.
    /// For "beef noodle soup" this surfaces "beef", "noodles", etc.
    /// Excludes single-letter matches and tokens shorter than 3 chars.
    func findComponents(for foodName: String) -> [ComponentMatch] {
        let normalized = foodName.lowercased().trimmingCharacters(in: .whitespaces)
        guard normalized.count >= 3 else { return [] }

        let request = NutritionalProfile.fetchRequest()
        let all = (try? context.fetch(request)) ?? []

        var hits: [String: ComponentMatch] = [:]  // keyed by matched token (dedup)

        for profile in all {
            let dbName = profile.foodName.lowercased().trimmingCharacters(in: .whitespaces)
            guard dbName.count >= 3 else { continue }

            // Match DB entry name inside the query, bounded by word boundaries so
            // "ice" doesn't match inside "rice".
            if wordBoundaryContains(haystack: normalized, needle: dbName) {
                // Prefer longest coverage when the same token matches multiple profiles.
                let existing = hits[dbName]
                if existing == nil || existing!.coverage < dbName.count {
                    hits[dbName] = ComponentMatch(profile: profile, matchedToken: dbName, coverage: dbName.count)
                }
            }
        }

        // Prefer longer matches first (more specific). "chicken noodle" over "chicken".
        var results = Array(hits.values).sorted { $0.coverage > $1.coverage }

        // Drop redundant shorter matches fully contained inside a longer accepted one.
        // e.g. if "chicken noodle" matched, drop "chicken" and "noodle" from results.
        var accepted: [ComponentMatch] = []
        for match in results {
            let isCovered = accepted.contains { longer in
                wordBoundaryContains(haystack: longer.matchedToken, needle: match.matchedToken)
            }
            if !isCovered {
                accepted.append(match)
            }
        }
        results = accepted
        return results
    }

    /// Fraction of the query's characters (excluding whitespace) that are covered
    /// by the union of component matches. Used to gate Tier 2 confidence.
    func coverageFraction(query: String, components: [ComponentMatch]) -> Double {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespaces)
        let nonSpaceChars = normalized.filter { !$0.isWhitespace }.count
        guard nonSpaceChars > 0 else { return 0 }
        let covered = components.reduce(0) { acc, match in
            acc + match.matchedToken.filter { !$0.isWhitespace }.count
        }
        return min(1.0, Double(covered) / Double(nonSpaceChars))
    }

    // MARK: - Private helpers

    private func fetchExact(_ name: String) -> NutritionalProfile? {
        let request = NutritionalProfile.fetchRequest()
        request.predicate = NSPredicate(format: "foodName ==[cd] %@", name)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchDBNameContainsQuery(_ query: String) -> NutritionalProfile? {
        let request = NutritionalProfile.fetchRequest()
        request.predicate = NSPredicate(format: "foodName CONTAINS[cd] %@", query)
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

    /// Word-boundary-aware contains. Ensures "ice" doesn't match inside "rice"
    /// while still allowing "beef" to match inside "beef noodle soup". Plural
    /// "s"/"es" suffixes on the needle are tolerated on the right edge so
    /// "egg" matches "scrambled eggs" but NOT "eggplant".
    private func wordBoundaryContains(haystack: String, needle: String) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        let h = Array(haystack)
        let n = Array(needle)
        let hLen = h.count, nLen = n.count
        var i = 0
        while i <= hLen - nLen {
            var match = true
            for j in 0..<nLen {
                if h[i + j] != n[j] { match = false; break }
            }
            if match {
                let leftOk = (i == 0) || !h[i - 1].isLetter
                let rightIdx = i + nLen
                let rightOk: Bool
                if rightIdx == hLen {
                    rightOk = true
                } else if !h[rightIdx].isLetter {
                    rightOk = true
                } else if h[rightIdx] == "s" &&
                          (rightIdx + 1 == hLen || !h[rightIdx + 1].isLetter) {
                    rightOk = true    // "eggs"
                } else if rightIdx + 1 < hLen && h[rightIdx] == "e" && h[rightIdx + 1] == "s" &&
                          (rightIdx + 2 == hLen || !h[rightIdx + 2].isLetter) {
                    rightOk = true    // "potatoes"
                } else {
                    rightOk = false
                }
                if leftOk && rightOk { return true }
            }
            i += 1
        }
        return false
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aArr = Array(a)
        let bArr = Array(b)
        let m = aArr.count, n = bArr.count
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = aArr[i-1] == bArr[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}
