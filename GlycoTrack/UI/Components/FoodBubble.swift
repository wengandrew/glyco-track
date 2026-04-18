import SwiftUI

struct FoodBubble: View {
    let foodDescription: String
    let magnitude: Double
    let foodGroup: FoodGroup
    let scaleFactor: Double

    private var radius: Double {
        max(12, sqrt(magnitude) * scaleFactor)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(foodGroup.color.opacity(0.85))
                .frame(width: radius * 2, height: radius * 2)

            if radius > 20 {
                Text(foodDescription)
                    .font(.system(size: max(8, radius * 0.35)))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(4)
                    .frame(width: radius * 1.7)
            }
        }
    }
}

struct FoodBubble_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            FoodBubble(foodDescription: "Brown Rice", magnitude: 25, foodGroup: .grains, scaleFactor: 3)
            FoodBubble(foodDescription: "Broccoli", magnitude: 5, foodGroup: .vegetables, scaleFactor: 3)
            FoodBubble(foodDescription: "Cake", magnitude: 45, foodGroup: .processed, scaleFactor: 3)
        }
        .padding()
    }
}
