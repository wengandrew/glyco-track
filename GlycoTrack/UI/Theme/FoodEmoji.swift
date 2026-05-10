import Foundation

/// Resolves a food emoji for a given entry.
///
/// Resolution order — earlier sources win:
///   1. Low confidence / unrecognized → ❓
///   2. `food_emoji_map.json` keyed by the user's typed `foodDescription`
///   3. `food_emoji_map.json` keyed by the matcher's canonical answer
///      (`entry.nutritionalProfile?.foodName`) — covers alias paths so the
///      JSON only needs canonical entries
///   4. `food_emoji_map.json` keyed by the alias-resolved canonical of the
///      typed description (via `AliasIndex`) — handles cases where the entry
///      didn't carry a profile but the typed name is a known alias
///   5. Keyword classifier on the typed `foodDescription`
///   6. Final fallback: 🍽️
///
/// What this deliberately does NOT do: scan `referenceFood`. That field is
/// the matcher's `matchSummary`, which for composite dishes is a joined
/// ingredient string like "brown sugar (7g) + corn syrup (5g) + gelatin
/// (3g)". Substring keyword scanning on that produces arbitrary results
/// (Welch's fruit snacks resolved to 🌽 because "corn" appeared in the
/// summary string). The user-typed description is the primary identity of
/// a food and should drive the emoji.
enum FoodEmoji {
    static let unknown = "❓"
    static let fallback = "🍽️"

    /// Treat entries below this confidence as unrecognized.
    /// FoodLogProcessor writes `confidenceScore` directly from the match result; a miss with
    /// no DB profile (USDA/GI both absent) yields a very low score.
    private static let unknownConfidenceThreshold: Double = 0.3

    static func resolve(
        foodDescription: String,
        canonicalName: String? = nil,
        confidence: Double = 1.0
    ) -> String {
        if confidence < unknownConfidenceThreshold {
            return unknown
        }

        let map = Self.loadMap()
        let desc = foodDescription
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = canonicalName?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !desc.isEmpty, let hit = map[desc] { return hit }
        if let canonical, !canonical.isEmpty, canonical != desc, let hit = map[canonical] { return hit }
        if !desc.isEmpty,
           let aliasCanonical = AliasIndex.shared.canonical(forAlias: desc)?.lowercased(),
           aliasCanonical != desc,
           aliasCanonical != canonical,
           let hit = map[aliasCanonical] {
            return hit
        }
        if !desc.isEmpty, let hit = FoodEmojiKeywordClassifier.classify(desc) { return hit }
        return fallback
    }

    // MARK: - Map loading

    private static let mapLock = NSLock()
    private static var cachedMap: [String: String]?

    private static func loadMap() -> [String: String] {
        mapLock.lock()
        defer { mapLock.unlock() }
        if let cached = cachedMap { return cached }

        guard
            let url = Bundle.main.url(forResource: "food_emoji_map", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            cachedMap = [:]
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in raw {
            if key.hasPrefix("_") { continue }
            if let str = value as? String {
                result[key.lowercased()] = str
            }
        }
        cachedMap = result
        return result
    }
}

extension FoodEmoji {
    /// Convenience for Core Data entries.
    static func resolve(entry: FoodLogEntry) -> String {
        resolve(
            foodDescription: entry.foodDescription,
            canonicalName: entry.nutritionalProfile?.foodName,
            confidence: Double(entry.confidenceScore)
        )
    }
}
