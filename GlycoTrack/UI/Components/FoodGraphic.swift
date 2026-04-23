import SwiftUI

/// Renders a food as an emoji sized so that its **area** is proportional to `magnitude`.
///
/// Use in SwiftUI visualizations that previously used colored circles. The emoji is
/// centered in a transparent square; there is no background fill or stroke by default
/// (food-group colors were removed — the emoji itself is the identifier).
struct FoodGraphic: View {
    let emoji: String
    /// A unitless magnitude — e.g. GL or |CL| for a single entry.
    let magnitude: Double
    /// Conversion factor: `area = magnitude * areaPerUnit`. Tune per-context so
    /// totals at the relevant budget fill the available container.
    let areaPerUnit: Double
    /// Minimum rendered side length so a tiny item is still tappable/visible.
    var minSide: Double = 22
    /// Optional cap to keep one huge item from dominating the frame.
    var maxSide: Double = 160

    /// Side length in points — emoji draws in a square of this size.
    var side: Double {
        let area = max(magnitude, 0) * areaPerUnit
        let raw = sqrt(max(area, 0))
        return min(max(raw, minSide), maxSide)
    }

    var body: some View {
        Text(emoji)
            .font(.system(size: side * 0.82))
            .frame(width: side, height: side)
            .minimumScaleFactor(0.5)
    }
}

#Preview {
    HStack(spacing: 8) {
        FoodGraphic(emoji: "🍚", magnitude: 25, areaPerUnit: 160)
        FoodGraphic(emoji: "🥦", magnitude: 5, areaPerUnit: 160)
        FoodGraphic(emoji: "🍰", magnitude: 45, areaPerUnit: 160)
        FoodGraphic(emoji: "❓", magnitude: 10, areaPerUnit: 160)
    }
    .padding()
}
