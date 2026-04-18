import SwiftUI

enum FoodGroup: String, CaseIterable {
    case grains     = "grains"
    case fruits     = "fruits"
    case dairy      = "dairy"
    case proteins   = "proteins"
    case vegetables = "vegetables"
    case processed  = "processed"

    var color: Color {
        switch self {
        case .grains:     return Color(red: 0.29, green: 0.565, blue: 0.851) // Blue
        case .fruits:     return Color(red: 0.961, green: 0.651, blue: 0.137) // Orange
        case .dairy:      return Color(red: 0.608, green: 0.349, blue: 0.714) // Purple
        case .proteins:   return Color(red: 0.545, green: 0.271, blue: 0.075) // Brown
        case .vegetables: return Color(red: 0.153, green: 0.682, blue: 0.376) // Green
        case .processed:  return Color(red: 0.906, green: 0.298, blue: 0.235) // Red
        }
    }

    var displayName: String {
        switch self {
        case .grains:     return "Grains & Starches"
        case .fruits:     return "Fruits & Natural Sugars"
        case .dairy:      return "Dairy"
        case .proteins:   return "Proteins"
        case .vegetables: return "Vegetables"
        case .processed:  return "Processed & Sweets"
        }
    }

    static func from(string: String) -> FoodGroup {
        return FoodGroup(rawValue: string.lowercased()) ?? .proteins
    }

    /// Heuristic assignment based on food name keywords.
    static func classify(_ foodName: String) -> FoodGroup {
        let name = foodName.lowercased()
        if name.contains("bread") || name.contains("rice") || name.contains("pasta") ||
           name.contains("oat") || name.contains("cereal") || name.contains("flour") ||
           name.contains("tortilla") || name.contains("cracker") || name.contains("noodle") ||
           name.contains("couscous") || name.contains("quinoa") || name.contains("barley") {
            return .grains
        }
        if name.contains("apple") || name.contains("banana") || name.contains("orange") ||
           name.contains("berry") || name.contains("fruit") || name.contains("mango") ||
           name.contains("grape") || name.contains("melon") || name.contains("cherry") ||
           name.contains("juice") || name.contains("peach") || name.contains("pear") ||
           name.contains("plum") || name.contains("kiwi") || name.contains("pineapple") {
            return .fruits
        }
        if name.contains("milk") || name.contains("yogurt") || name.contains("yoghurt") ||
           name.contains("cheese") || name.contains("cream") || name.contains("butter") ||
           name.contains("dairy") || name.contains("ricotta") || name.contains("cottage") {
            return .dairy
        }
        if name.contains("broccoli") || name.contains("spinach") || name.contains("kale") ||
           name.contains("lettuce") || name.contains("tomato") || name.contains("carrot") ||
           name.contains("cucumber") || name.contains("pepper") || name.contains("onion") ||
           name.contains("mushroom") || name.contains("zucchini") || name.contains("vegetable") ||
           name.contains("celery") || name.contains("cabbage") || name.contains("asparagus") ||
           name.contains("bean") && !name.contains("coffee") || name.contains("pea") {
            return .vegetables
        }
        if name.contains("cake") || name.contains("cookie") || name.contains("donut") ||
           name.contains("candy") || name.contains("chocolate") && !name.contains("dark") ||
           name.contains("chips") || name.contains("sugar") || name.contains("soda") ||
           name.contains("cola") || name.contains("processed") || name.contains("waffle") ||
           name.contains("muffin") || name.contains("brownie") || name.contains("fries") {
            return .processed
        }
        // Default: proteins (eggs, meat, fish, nuts, legumes)
        return .proteins
    }
}
