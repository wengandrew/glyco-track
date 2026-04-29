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
        if !desc.isEmpty, let hit = keyword(for: desc) { return hit }
        return fallback
    }

    // MARK: - Keyword classifier

    /// Earlier rules win, so the order encodes "what's the primary identity
    /// of a compound food name?". Rough hierarchy:
    ///   1. Specific compound dish forms (fruit snack, casserole, noodle…)
    ///   2. Drinks by form (soda/cola/coffee…) — "X soda" should land on
    ///      🥤 rather than the fruit X
    ///   3. Sweets (cake/cookie/candy…), bread/wrap forms
    ///   4. Proteins (chicken, beef, salami, fish/shellfish, eggs)
    ///   5. Grains / legumes / dairy
    ///   6. Fruits (after drinks)
    ///   7. Non-aromatic vegetables
    ///   8. Aromatics (garlic, onion, scallion…) — usually a modifier in
    ///      compound names like "garlic chicken", so they go LAST among
    ///      whole-food categories
    ///   9. Nuts/seeds, condiments, soups, miscellaneous
    private static let keywordRules: [(needle: String, emoji: String)] = [
        // 1. Compound dish forms — most specific first
        ("fruit snack", "🍬"),
        ("rice noodle", "🍜"), ("egg noodle", "🍜"), ("ramen", "🍜"), ("noodle", "🍜"),
        ("spaghetti", "🍝"), ("pasta", "🍝"), ("macaroni", "🧀"),
        ("sushi", "🍣"), ("sashimi", "🍣"),
        ("pizza", "🍕"),
        ("hamburger", "🍔"), ("burger", "🍔"),
        ("hot dog", "🌭"), ("frankfurt", "🌭"),
        ("taco", "🌮"), ("burrito", "🌯"), ("quesadilla", "🌮"), ("enchilada", "🌯"),
        ("tortilla chip", "🌮"), ("tortilla", "🫓"),
        ("dumpling", "🥟"), ("wonton", "🥟"), ("samosa", "🥟"), ("pierogi", "🥟"),
        ("spring roll", "🥟"), ("ravioli", "🥟"),
        ("casserole", "🥘"), ("skillet", "🥘"), ("paella", "🥘"),
        ("caesar salad", "🥗"), ("salad", "🥗"),

        // 2. Drinks by form — placed before fruits so "orange soda" → 🥤
        ("soda", "🥤"), ("cola", "🥤"), ("pop", "🥤"),
        ("coffee", "☕"), ("espresso", "☕"), ("cappuccino", "☕"), ("latte", "☕"),
        ("matcha", "🍵"), ("chai", "🍵"), ("tea", "🍵"),
        ("smoothie", "🥤"), ("shake", "🥤"),
        ("juice", "🧃"),
        ("beer", "🍺"), ("ale", "🍺"), ("lager", "🍺"),
        ("wine", "🍷"), ("whiskey", "🥃"), ("vodka", "🍸"), ("cocktail", "🍸"),
        ("water", "💧"),

        // 3. Sweets and breads
        ("muffin", "🧁"), ("cupcake", "🧁"),
        ("pancake", "🥞"), ("waffle", "🧇"),
        ("cheesecake", "🍰"), ("cake", "🍰"),
        ("cookie", "🍪"), ("biscuit", "🍪"),
        ("donut", "🍩"), ("doughnut", "🍩"),
        ("brownie", "🍫"), ("chocolate", "🍫"),
        ("ice cream", "🍦"), ("sorbet", "🍧"), ("gelato", "🍨"),
        ("candy", "🍬"), ("gummy", "🍬"), ("caramel", "🍬"), ("toffee", "🍬"),
        ("pudding", "🍮"), ("custard", "🍮"),
        ("bagel", "🥯"), ("croissant", "🥐"),
        ("pita", "🫓"), ("naan", "🫓"), ("flatbread", "🫓"), ("chapati", "🫓"),
        ("bread", "🍞"), ("toast", "🍞"),

        // 4. Proteins — before aromatics so "garlic chicken" → 🍗
        ("salami", "🥩"), ("prosciutto", "🥩"), ("pepperoni", "🥩"), ("pastrami", "🥩"),
        ("sausage", "🌭"),
        ("chicken", "🍗"), ("turkey", "🦃"), ("duck", "🦆"),
        ("beef", "🥩"), ("steak", "🥩"),
        ("pork", "🥓"), ("bacon", "🥓"),
        ("ham", "🍖"), ("lamb", "🍖"), ("veal", "🍖"), ("meat", "🍖"),
        ("egg", "🥚"),
        ("salmon", "🐟"), ("tuna", "🐟"), ("cod", "🐟"), ("tilapia", "🐟"),
        ("trout", "🐟"), ("halibut", "🐟"), ("sardine", "🐟"), ("mackerel", "🐟"),
        ("anchov", "🐟"), ("herring", "🐟"), ("fish", "🐟"),
        ("shrimp", "🦐"), ("prawn", "🦐"), ("lobster", "🦞"), ("crab", "🦀"),
        ("scallop", "🦪"), ("clam", "🦪"), ("oyster", "🦪"), ("mussel", "🦪"),
        ("octopus", "🐙"), ("squid", "🦑"), ("calamari", "🦑"),

        // 5. Grains, legumes, dairy
        ("chana", "🫘"), ("channa", "🫘"),
        ("rice", "🍚"), ("risotto", "🍚"),
        ("oat", "🥣"), ("cereal", "🥣"), ("granola", "🥣"),
        ("quinoa", "🌾"), ("barley", "🌾"), ("millet", "🌾"), ("wheat", "🌾"),
        ("bulgur", "🌾"), ("couscous", "🌾"),
        ("polenta", "🌽"), ("grits", "🌽"),
        ("corn", "🌽"), ("popcorn", "🍿"),
        ("bean", "🫘"), ("lentil", "🫘"), ("chickpea", "🫘"), ("hummus", "🫘"),
        ("tofu", "🫘"), ("tempeh", "🫘"),
        ("edamame", "🫛"), ("pea", "🫛"),
        ("cheese", "🧀"), ("yogurt", "🥛"), ("yoghurt", "🥛"), ("milk", "🥛"),
        ("butter", "🧈"), ("cream", "🥛"),

        // 6. Fruits
        ("apple", "🍎"), ("banana", "🍌"), ("orange", "🍊"), ("grape", "🍇"),
        ("watermelon", "🍉"), ("pineapple", "🍍"), ("mango", "🥭"),
        ("strawberr", "🍓"), ("raspberr", "🍓"), ("blueberr", "🫐"), ("blackberr", "🫐"),
        ("cherr", "🍒"), ("peach", "🍑"), ("pear", "🍐"), ("plum", "🍑"),
        ("kiwi", "🥝"), ("lemon", "🍋"), ("lime", "🍋"),
        ("avocado", "🥑"), ("coconut", "🥥"),
        ("fruit", "🍇"), ("berr", "🍓"),

        // 7. Vegetables (non-aromatic)
        ("broccoli", "🥦"), ("cauliflower", "🥦"),
        ("spinach", "🥬"), ("kale", "🥬"), ("lettuce", "🥬"), ("cabbage", "🥬"),
        ("arugula", "🥬"), ("chard", "🥬"), ("greens", "🥬"),
        ("carrot", "🥕"),
        ("cucumber", "🥒"), ("zucchini", "🥒"), ("pickle", "🥒"),
        ("pepper", "🫑"), ("chili", "🌶️"), ("jalapeno", "🌶️"),
        ("mushroom", "🍄"), ("eggplant", "🍆"),
        ("pumpkin", "🎃"), ("squash", "🎃"), ("tomato", "🍅"),
        ("potato", "🥔"), ("yam", "🍠"),
        ("vegetable", "🥦"), ("veggie", "🥦"),

        // 8. Aromatics — placed AFTER proteins so "garlic chicken" → 🍗,
        //    not 🧄. They're rarely the primary identity in compound names.
        ("garlic", "🧄"),
        ("onion", "🧅"), ("shallot", "🧅"), ("scallion", "🧅"), ("leek", "🧅"),

        // 9. Nuts, seeds, condiments
        ("peanut", "🥜"), ("almond", "🥜"), ("cashew", "🥜"), ("walnut", "🥜"),
        ("pecan", "🥜"), ("pistachio", "🥜"), ("hazelnut", "🥜"), ("nut", "🥜"),
        ("seed", "🌱"),
        ("olive", "🫒"), ("oil", "🫗"),
        ("ketchup", "🍅"), ("mayo", "🥚"), ("mustard", "🌭"),
        ("salsa", "🍅"), ("pesto", "🌿"), ("guacamole", "🥑"),
        ("syrup", "🍯"), ("honey", "🍯"), ("jam", "🍯"), ("jelly", "🍯"),
        ("sugar", "🍚"), ("sweetener", "🍬"),

        // 10. Soups / stews — generic forms; specific items above already won
        ("soup", "🍲"), ("stew", "🍲"), ("chowder", "🍲"),
        ("curry", "🍛"),

        // 11. Misc
        ("fries", "🍟"), ("chip", "🍟"),
    ]

    private static func keyword(for text: String) -> String? {
        for rule in keywordRules where wordBoundaryContains(haystack: text, needle: rule.needle) {
            return rule.emoji
        }
        return nil
    }

    /// Word-boundary-aware contains. Without this, the substring approach
    /// produces ugly collisions once rule order matters: `kale.contains("ale")`
    /// would route kale to 🍺, `peach.contains("pea")` to 🫛, and
    /// `veggie.contains("egg")` to 🥚.
    ///
    /// Tolerated trailing morphology on the needle's right boundary:
    ///   - `s`  → "egg" matches "eggs"
    ///   - `es` → "potato" matches "potatoes"
    ///   - `y`  → "strawberr" matches "strawberry", "anchov" matches "anchovy"
    ///   - `ies` → "cherr" matches "cherries", "berr" matches "berries"
    /// These let stem-style needles ("strawberr", "cherr", "anchov") match
    /// the common English singular and plural forms without bloating the
    /// rule list.
    private static func wordBoundaryContains(haystack: String, needle: String) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        let h = Array(haystack)
        let n = Array(needle)
        let hLen = h.count, nLen = n.count
        var i = 0
        while i <= hLen - nLen {
            var match = true
            for j in 0..<nLen where h[i + j] != n[j] {
                match = false
                break
            }
            if match {
                let leftOk = (i == 0) || !h[i - 1].isLetter
                let rightIdx = i + nLen
                if leftOk && rightOkAtBoundary(h: h, hLen: hLen, rightIdx: rightIdx) {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    private static func rightOkAtBoundary(h: [Character], hLen: Int, rightIdx: Int) -> Bool {
        if rightIdx == hLen { return true }
        if !h[rightIdx].isLetter { return true }
        // Allowed letter suffixes on the needle: s, es, y, ies. Each must
        // itself end at a non-letter or string end so we don't bleed into
        // an unrelated word.
        let suffixes: [[Character]] = [["s"], ["e", "s"], ["y"], ["i", "e", "s"]]
        for suffix in suffixes {
            let endIdx = rightIdx + suffix.count
            guard endIdx <= hLen else { continue }
            var matches = true
            for k in 0..<suffix.count where h[rightIdx + k] != suffix[k] {
                matches = false
                break
            }
            guard matches else { continue }
            if endIdx == hLen || !h[endIdx].isLetter { return true }
        }
        return false
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
