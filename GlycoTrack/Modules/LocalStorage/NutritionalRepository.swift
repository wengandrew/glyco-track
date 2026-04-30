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

/// All operations use a main-queue NSManagedObjectContext, so the type is
/// @MainActor-isolated to prevent cross-thread Core Data access.
@MainActor
final class NutritionalRepository {
    private let context: NSManagedObjectContext
    private let aliasIndex: AliasIndex

    init(context: NSManagedObjectContext = PersistenceController.shared.context,
         aliasIndex: AliasIndex = .shared) {
        self.context = context
        self.aliasIndex = aliasIndex
    }

    /// Tier 1: strict direct-match lookup on the full food name.
    /// Only returns a hit when the query matches a DB entry as a whole — not when
    /// a random DB token happens to appear inside a composite name. Use
    /// `findComponents(for:)` for that case.
    func findBestMatch(for foodName: String) -> DirectMatch? {
        let normalized = foodName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }

        if let direct = matchDirect(normalized) {
            return direct
        }

        // No direct hit on the full query — but the query might carry a
        // "whole grain" / "brown" qualifier that the DB doesn't index by
        // shape. "whole wheat spaghetti" doesn't exist as an entry, but
        // stripping the qualifier resolves "spaghetti" to `white pasta`,
        // and the promotion table swaps that for `whole wheat pasta`. Same
        // for "brown jasmine rice" → falls back to brown rice when the
        // exact shape isn't in the DB. Confidence is inherited from the
        // inner match — the qualifier didn't weaken the signal.
        let qualifier = Self.detectGrainQualifier(in: normalized)
        if qualifier.hasAny, let inner = matchDirect(qualifier.stripped) {
            let promoted = promote(profile: inner.profile, qualifier: qualifier) ?? inner.profile
            return DirectMatch(profile: promoted, confidence: inner.confidence)
        }

        return nil
    }

    /// Standard T1 cascade on a single normalized query string. Does not
    /// strip qualifiers — `findBestMatch` handles that as a fallback.
    private func matchDirect(_ normalized: String) -> DirectMatch? {
        if let exact = fetchExact(normalized) {
            return DirectMatch(profile: exact, confidence: 0.95)
        }

        // Alias hit: the query is exactly a declared alias of some canonical
        // entry. "grilled chicken" → "chicken breast", "bread" → "white
        // bread", "sugar" → "white sugar", "rice" → "white rice", "egg" →
        // "eggs". Treated as a strong T1 signal — slightly below an exact
        // canonical hit (0.95) but stronger than contains/fuzzy. Without this
        // path the strict contains-gate (`> 0.5`) leaves single-word generic
        // queries with no T1 home and they fall to T3 or T5 unnecessarily.
        if let canonical = aliasIndex.canonical(forAlias: normalized),
           let aliasMatch = fetchExact(canonical.lowercased()) {
            return DirectMatch(profile: aliasMatch, confidence: 0.93)
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

    // MARK: - Whole-grain / brown qualifier promotion

    /// Qualifier prefixes that indicate the user wants the whole-grain
    /// version of a refined-grain canonical entry. Order matters only for
    /// the longest-match-first strip below; the set itself is unordered.
    private static let wholeGrainQualifierPrefixes: [String] = [
        "whole wheat ", "whole-wheat ",
        "whole grain ", "whole-grain ",
        "wholegrain ", "wholemeal "
    ]

    /// Promotion table: stripped canonical → whole-grain or brown sibling.
    /// Both keys and values are foodName as stored in NutritionalProfile
    /// (lowercased for the lookup). New entries should be added when a new
    /// refined↔whole-grain pair appears in the DB.
    private static let wholeGrainPromotion: [String: String] = [
        "white rice": "brown rice",
        "white bread": "whole wheat bread",
        "white pasta": "whole wheat pasta",
        "white flour": "whole wheat flour",
        "tortilla": "whole wheat tortilla",
        "flour tortilla": "whole wheat tortilla"
    ]

    struct GrainQualifier {
        let stripped: String
        let hasWholeGrain: Bool
        let hasBrown: Bool
        var hasAny: Bool { hasWholeGrain || hasBrown }
    }

    /// Detects and strips a leading whole-grain or brown qualifier on the
    /// query. "whole wheat spaghetti" → ("spaghetti", wholeGrain), "brown
    /// rice" → ("rice", brown). Both qualifiers can stack ("brown whole
    /// wheat …" — unusual but tolerated). Returns the original string when
    /// no qualifier is present.
    static func detectGrainQualifier(in normalized: String) -> GrainQualifier {
        var s = normalized
        var wg = false
        var brown = false

        // Strip whole-grain prefixes first (multi-word) so "whole grain
        // brown rice" doesn't misfire on "brown".
        for prefix in wholeGrainQualifierPrefixes where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            wg = true
            break
        }
        if s.hasPrefix("brown ") {
            s = String(s.dropFirst("brown ".count)).trimmingCharacters(in: .whitespaces)
            brown = true
        }
        return GrainQualifier(stripped: s, hasWholeGrain: wg, hasBrown: brown)
    }

    /// Returns the promoted profile when the inner match's canonical name
    /// has a whole-grain / brown sibling in the DB. nil when no promotion
    /// applies (qualifier was on a food without a sibling entry, e.g.
    /// "brown jasmine rice" — fall back to the inner match unchanged).
    private func promote(profile: NutritionalProfile, qualifier: GrainQualifier) -> NutritionalProfile? {
        guard qualifier.hasAny else { return nil }
        let key = profile.foodName.lowercased()
        guard let promotedName = Self.wholeGrainPromotion[key] else { return nil }
        return fetchExact(promotedName)
    }

    /// Tier 2: reverse-substring decomposition (Option B).
    /// Returns DB entries whose foodName (or any declared alias) appears
    /// inside the user's query. For "beef noodle soup" this surfaces "beef",
    /// "noodles", etc. For "grilled chicken caesar salad" this surfaces the
    /// "grilled chicken" alias of `chicken breast` plus "caesar salad" if
    /// present. Excludes tokens shorter than 3 chars.
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

            // Aliases of this profile are also legitimate substring tokens.
            // Without this, "grilled chicken caesar salad" would never see
            // `chicken breast` as a component because the canonical name
            // doesn't appear in the query — only its alias does.
            for alias in aliasIndex.aliases(forCanonical: dbName) where alias.count >= 3 {
                guard wordBoundaryContains(haystack: normalized, needle: alias) else { continue }
                let existing = hits[alias]
                if existing == nil || existing!.coverage < alias.count {
                    hits[alias] = ComponentMatch(profile: profile, matchedToken: alias, coverage: alias.count)
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
    /// by the union of component matches. Tracks actual character positions to
    /// avoid double-counting overlapping tokens.
    func coverageFraction(query: String, components: [ComponentMatch]) -> Double {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespaces)
        let queryChars = Array(normalized)
        let nonSpaceChars = queryChars.filter { !$0.isWhitespace }.count
        guard nonSpaceChars > 0 else { return 0 }

        var covered = Array(repeating: false, count: queryChars.count)
        for match in components {
            let tokenChars = Array(match.matchedToken)
            guard !tokenChars.isEmpty, tokenChars.count <= queryChars.count else { continue }
            for start in 0...(queryChars.count - tokenChars.count) {
                var matches = true
                for offset in 0..<tokenChars.count where queryChars[start + offset] != tokenChars[offset] {
                    matches = false
                    break
                }
                if matches {
                    for offset in 0..<tokenChars.count { covered[start + offset] = true }
                }
            }
        }

        let coveredNonSpace = zip(queryChars, covered).reduce(0) { count, pair in
            count + ((pair.1 && !pair.0.isWhitespace) ? 1 : 0)
        }
        return Double(coveredNonSpace) / Double(nonSpaceChars)
    }

    // MARK: - Private helpers

    func wordBoundaryContains(haystack: String, needle: String) -> Bool {
        _wordBoundaryContains(haystack: haystack, needle: needle)
    }

    private func fetchExact(_ name: String) -> NutritionalProfile? {
        let request = NutritionalProfile.fetchRequest()
        request.predicate = NSPredicate(format: "foodName ==[cd] %@", name)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func fetchDBNameContainsQuery(_ query: String) -> NutritionalProfile? {
        let request = NutritionalProfile.fetchRequest()
        request.predicate = NSPredicate(format: "foodName CONTAINS[cd] %@", query)
        let candidates = (try? context.fetch(request)) ?? []
        let queryWords = query.split(separator: " ").count
        // Two guards before accepting a contains-match:
        // 1. Word-boundary: "egg" must not match inside "veggie".
        // 2. Word-count ratio: the query must cover MORE than half of the DB
        //    entry's words. Strict `>` (not `>=`) is load-bearing — a 1-word
        //    generic query against a 2-word specific entry hits exactly 0.5
        //    and would otherwise match: "bread" → "rye bread", "juice" →
        //    "pomegranate juice", "chicken" → "chicken drumstick" all observed
        //    in production logs. Letting these fall through to T2/T3 is more
        //    honest than silently picking a specific variant. "white rice" /
        //    "steamed white rice" (ratio = 0.67) still passes.
        // Prefer the shortest surviving match (fewest extra qualifier words).
        return candidates
            .filter { profile in
                let dbWords = profile.foodName.split(separator: " ").count
                return Double(queryWords) / Double(dbWords) > 0.5
                    && _wordBoundaryContains(haystack: profile.foodName.lowercased(), needle: query)
            }
            .min(by: { $0.foodName.count < $1.foodName.count })
    }

    private func fetchFuzzy(_ name: String) -> (NutritionalProfile, Int)? {
        let request = NutritionalProfile.fetchRequest()
        let all = (try? context.fetch(request)) ?? []
        let queryPrep = Self.prepMethodTokens(in: name)
        var best: (NutritionalProfile, Int)?
        for profile in all {
            let dbName = profile.foodName.lowercased()
            // Refuse fuzzy bridges across different prep methods. "grilled
            // chicken" → "fried chicken" has Lev = 4-ish but the CL profile
            // is meaningfully different — silent fuzzing here is exactly the
            // class of mislabel CLAUDE.md rule #1 forbids. If both names
            // mention prep methods and they disagree, skip.
            let dbPrep = Self.prepMethodTokens(in: dbName)
            if !queryPrep.isEmpty && !dbPrep.isEmpty && queryPrep.isDisjoint(with: dbPrep) {
                continue
            }
            let d = levenshtein(name, dbName)
            if d <= 3 {
                if best == nil || d < best!.1 {
                    best = (profile, d)
                }
            }
        }
        return best
    }

    /// Prep-method words that change a food's nutritional profile enough that
    /// fuzzing across them is wrong. Kept conservative — words that don't
    /// shift fat/cholesterol meaningfully (e.g. "chopped", "sliced") aren't
    /// here.
    private static let prepMethodWords: Set<String> = [
        "grilled", "fried", "deep-fried", "baked", "steamed", "boiled",
        "raw", "roasted", "smoked", "sauteed", "sautéed", "poached",
        "broiled", "stewed", "braised", "pan-fried", "stir-fried"
    ]

    private static func prepMethodTokens(in name: String) -> Set<String> {
        let tokens = name.lowercased().split { !$0.isLetter && $0 != "-" }.map(String.init)
        return Set(tokens).intersection(prepMethodWords)
    }

    /// Word-boundary-aware contains. Ensures "ice" doesn't match inside "rice"
    /// while still allowing "beef" to match inside "beef noodle soup". Plural
    /// "s"/"es" suffixes on the needle are tolerated on the right edge so
    /// "egg" matches "scrambled eggs" but NOT "eggplant".
    private func _wordBoundaryContains(haystack: String, needle: String) -> Bool {
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
