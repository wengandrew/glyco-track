import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Float
    let tier: Int16

    private var needsRefine: Bool { confidence < 0.7 }

    private var tierLabel: String {
        switch tier {
        case 1: return "T1"
        case 2: return "T2"
        case 3: return "T3"
        case 4: return "T4"
        default: return "T?"
        }
    }

    private var tierColor: Color {
        switch tier {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(tierLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(tierColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tierColor.opacity(0.12))
                .cornerRadius(4)

            if needsRefine {
                Text("Refine")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(4)
            }
        }
    }
}
