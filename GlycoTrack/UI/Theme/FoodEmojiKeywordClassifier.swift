import Foundation

/// Keyword-based emoji classifier for food descriptions.
///
/// Used as the last-resort step in `FoodEmoji.resolve` when neither the
/// explicit JSON map nor the alias index produced a hit. Rules are ordered
/// from most-specific to least-specific; earlier rules win.
///
/// Rule ordering rationale:
///   1. Specific compound dish forms (spring roll, casserole, noodle…)
///   2. Drinks by form — placed before fruits so "orange soda" → 🥤
///   3. Sweets and bread forms
///   4. Proteins — before aromatics so "garlic chicken" → 🍗, not 🧄
///   5. Grains, legumes, dairy
///   6. Fruits (after drinks to avoid "orange soda" → 🍊)
///   7. Non-aromatic vegetables
///   8. Aromatics last among whole-food categories (usually modifiers)
///   9. Nuts, seeds, condiments, soups, misc
enum FoodEmojiKeywordClassifier {
    /// Returns the emoji for the first matching rule, or `nil` if nothing matched.
    static func classify(_ text: String) -> String? {
        for rule in rules where wordBoundaryContains(haystack: text, needle: rule.needle) {
            return rule.emoji
        }
        return nil
    }

    // MARK: - Rules

    static let rules: [(needle: String, emoji: String)] = [
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

        // 2. Drinks by form
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

        // 4. Proteins
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

        // 8. Aromatics — after proteins so "garlic chicken" → 🍗
        ("garlic", "🧄"),
        ("onion", "🧅"), ("shallot", "🧅"), ("scallion", "🧅"), ("leek", "🧅"),

        // 9. Nuts, seeds, condiments, soups, misc
        ("peanut", "🥜"), ("almond", "🥜"), ("cashew", "🥜"), ("walnut", "🥜"),
        ("pecan", "🥜"), ("pistachio", "🥜"), ("hazelnut", "🥜"), ("nut", "🥜"),
        ("seed", "🌱"),
        ("olive", "🫒"), ("oil", "🫗"),
        ("ketchup", "🍅"), ("mayo", "🥚"), ("mustard", "🌭"),
        ("salsa", "🍅"), ("pesto", "🌿"), ("guacamole", "🥑"),
        ("syrup", "🍯"), ("honey", "🍯"), ("jam", "🍯"), ("jelly", "🍯"),
        ("sugar", "🍚"), ("sweetener", "🍬"),
        ("soup", "🍲"), ("stew", "🍲"), ("chowder", "🍲"),
        ("curry", "🍛"),
        ("fries", "🍟"), ("chip", "🍟")
    ]

    // MARK: - Word-boundary matching

    /// Word-boundary-aware contains. Without this, substring matching produces
    /// false positives: `kale.contains("ale")` → 🍺, `peach.contains("pea")` → 🫛,
    /// `veggie.contains("egg")` → 🥚.
    ///
    /// Tolerated trailing morphology on the right boundary:
    ///   - `s`   → "egg" matches "eggs"
    ///   - `es`  → "potato" matches "potatoes"
    ///   - `y`   → "anchov" matches "anchovy"
    ///   - `ies` → "cherr" matches "cherries", "berr" matches "berries"
    static func wordBoundaryContains(haystack: String, needle: String) -> Bool {
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
                if leftOk && rightOkAtBoundary(h: h, hLen: hLen, rightIdx: i + nLen) {
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
}
