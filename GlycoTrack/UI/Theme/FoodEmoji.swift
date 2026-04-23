import Foundation

/// Resolves a food emoji for a given entry.
///
/// Precedence:
///   1. Low confidence / unrecognized → ❓
///   2. Exact match in `food_emoji_map.json` on the reference food name (if any)
///   3. Exact match in the map on the user's raw food description
///   4. Keyword fallback (substring classifier)
///   5. Final fallback: 🍽️
enum FoodEmoji {
    static let unknown = "❓"
    static let fallback = "🍽️"

    /// Treat entries below this confidence as unrecognized.
    /// FoodLogProcessor writes `confidenceScore` directly from the match result; a miss with
    /// no DB profile (USDA/GI both absent) yields a very low score.
    private static let unknownConfidenceThreshold: Double = 0.3

    static func resolve(
        foodDescription: String,
        referenceFood: String? = nil,
        confidence: Double = 1.0
    ) -> String {
        if confidence < unknownConfidenceThreshold {
            return unknown
        }
        let candidates: [String] = [referenceFood, foodDescription]
            .compactMap { $0?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let map = Self.loadMap()
        for c in candidates {
            if let hit = map[c] { return hit }
        }
        for c in candidates {
            if let hit = keyword(for: c) { return hit }
        }
        return fallback
    }

    // MARK: - Keyword classifier

    /// Ordered rules: the first substring that matches wins. Order from more-specific to less.
    private static let keywordRules: [(needle: String, emoji: String)] = [
        // Compound / specific first
        ("rice noodle", "🍜"), ("egg noodle", "🍜"), ("noodle", "🍜"),
        ("spaghetti", "🍝"), ("pasta", "🍝"), ("macaroni", "🧀"),
        ("sushi", "🍣"), ("sashimi", "🍣"),
        ("pizza", "🍕"),
        ("hamburger", "🍔"), ("burger", "🍔"),
        ("hot dog", "🌭"), ("sausage", "🌭"), ("frankfurt", "🌭"),
        ("taco", "🌮"), ("burrito", "🌯"), ("quesadilla", "🌮"), ("enchilada", "🌯"),
        ("tortilla chip", "🌮"), ("tortilla", "🫓"),
        ("dumpling", "🥟"), ("wonton", "🥟"), ("samosa", "🥟"), ("pierogi", "🥟"),
        ("spring roll", "🥟"), ("ravioli", "🥟"),
        // Breads
        ("bagel", "🥯"), ("croissant", "🥐"), ("pita", "🫓"), ("naan", "🫓"),
        ("flatbread", "🫓"), ("chapati", "🫓"), ("bread", "🍞"), ("toast", "🍞"),
        ("muffin", "🧁"), ("cupcake", "🧁"),
        ("pancake", "🥞"), ("waffle", "🧇"),
        // Sweets
        ("cake", "🍰"), ("cheesecake", "🍰"),
        ("cookie", "🍪"), ("biscuit", "🍪"),
        ("donut", "🍩"), ("doughnut", "🍩"),
        ("brownie", "🍫"), ("chocolate", "🍫"),
        ("ice cream", "🍦"), ("sorbet", "🍧"), ("gelato", "🍨"),
        ("candy", "🍬"), ("gummy", "🍬"), ("caramel", "🍬"), ("toffee", "🍬"),
        ("pudding", "🍮"), ("custard", "🍮"),
        // Fruits
        ("apple", "🍎"), ("banana", "🍌"), ("orange", "🍊"), ("grape", "🍇"),
        ("watermelon", "🍉"), ("pineapple", "🍍"), ("mango", "🥭"),
        ("strawberr", "🍓"), ("raspberr", "🍓"), ("blueberr", "🫐"), ("blackberr", "🫐"),
        ("cherr", "🍒"), ("peach", "🍑"), ("pear", "🍐"), ("plum", "🍑"),
        ("kiwi", "🥝"), ("lemon", "🍋"), ("lime", "🍋"), ("avocado", "🥑"),
        ("coconut", "🥥"), ("fruit", "🍇"), ("berr", "🍓"),
        // Veg
        ("broccoli", "🥦"), ("cauliflower", "🥦"),
        ("spinach", "🥬"), ("kale", "🥬"), ("lettuce", "🥬"), ("cabbage", "🥬"),
        ("arugula", "🥬"), ("chard", "🥬"), ("greens", "🥬"),
        ("carrot", "🥕"), ("cucumber", "🥒"), ("zucchini", "🥒"), ("pickle", "🥒"),
        ("pepper", "🫑"), ("chili", "🌶️"), ("jalapen", "🌶️"),
        ("onion", "🧅"), ("shallot", "🧅"), ("scallion", "🧅"), ("leek", "🧅"),
        ("garlic", "🧄"), ("mushroom", "🍄"), ("eggplant", "🍆"),
        ("pumpkin", "🎃"), ("squash", "🎃"), ("tomato", "🍅"),
        ("potato", "🥔"), ("yam", "🍠"),
        ("salad", "🥗"), ("vegetable", "🥦"), ("veggie", "🥦"),
        // Grains & legumes
        ("rice", "🍚"), ("oat", "🥣"), ("cereal", "🥣"), ("granola", "🥣"),
        ("quinoa", "🌾"), ("barley", "🌾"), ("millet", "🌾"), ("wheat", "🌾"),
        ("bulgur", "🌾"), ("couscous", "🌾"), ("polenta", "🌽"), ("grits", "🌽"),
        ("corn", "🌽"), ("popcorn", "🍿"),
        ("bean", "🫘"), ("lentil", "🫘"), ("chickpea", "🫘"), ("hummus", "🫘"),
        ("tofu", "🫘"), ("tempeh", "🫘"), ("edamame", "🫛"), ("pea", "🫛"),
        // Proteins
        ("chicken", "🍗"), ("turkey", "🦃"), ("duck", "🦆"),
        ("beef", "🥩"), ("steak", "🥩"), ("pork", "🥓"), ("bacon", "🥓"),
        ("ham", "🍖"), ("lamb", "🍖"), ("veal", "🍖"), ("meat", "🍖"),
        ("egg", "🥚"),
        ("salmon", "🐟"), ("tuna", "🐟"), ("cod", "🐟"), ("tilapia", "🐟"),
        ("trout", "🐟"), ("halibut", "🐟"), ("sardine", "🐟"), ("mackerel", "🐟"),
        ("anchov", "🐟"), ("herring", "🐟"), ("fish", "🐟"),
        ("shrimp", "🦐"), ("prawn", "🦐"), ("lobster", "🦞"), ("crab", "🦀"),
        ("scallop", "🦪"), ("clam", "🦪"), ("oyster", "🦪"), ("mussel", "🦪"),
        ("octopus", "🐙"), ("squid", "🦑"), ("calamari", "🦑"),
        // Dairy
        ("cheese", "🧀"), ("yogurt", "🥛"), ("yoghurt", "🥛"), ("milk", "🥛"),
        ("butter", "🧈"), ("cream", "🥛"),
        // Nuts
        ("peanut", "🥜"), ("almond", "🥜"), ("cashew", "🥜"), ("walnut", "🥜"),
        ("pecan", "🥜"), ("pistachio", "🥜"), ("hazelnut", "🥜"), ("nut", "🥜"),
        ("seed", "🌱"),
        // Sauces / condiments
        ("olive", "🫒"), ("oil", "🫗"),
        ("ketchup", "🍅"), ("mayo", "🥚"), ("mustard", "🌭"),
        ("salsa", "🍅"), ("pesto", "🌿"), ("guacamole", "🥑"),
        ("syrup", "🍯"), ("honey", "🍯"), ("jam", "🍯"), ("jelly", "🍯"),
        ("sugar", "🍚"), ("sweetener", "🍬"),
        // Drinks
        ("coffee", "☕"), ("espresso", "☕"), ("cappuccino", "☕"), ("latte", "☕"),
        ("tea", "🍵"), ("matcha", "🍵"), ("chai", "🍵"),
        ("water", "💧"),
        ("juice", "🧃"), ("smoothie", "🥤"), ("shake", "🥤"),
        ("soda", "🥤"), ("cola", "🥤"), ("pop", "🥤"),
        ("beer", "🍺"), ("ale", "🍺"), ("lager", "🍺"),
        ("wine", "🍷"), ("whiskey", "🥃"), ("vodka", "🍸"), ("cocktail", "🍸"),
        // Soups / stews
        ("soup", "🍲"), ("stew", "🍲"), ("chowder", "🍲"), ("chili", "🌶️"),
        ("curry", "🍛"), ("paella", "🥘"), ("risotto", "🍚"),
        // Misc
        ("fries", "🍟"), ("chip", "🍟")
    ]

    private static func keyword(for text: String) -> String? {
        for rule in keywordRules where text.contains(rule.needle) {
            return rule.emoji
        }
        return nil
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
            referenceFood: entry.referenceFood,
            confidence: Double(entry.confidenceScore)
        )
    }
}
