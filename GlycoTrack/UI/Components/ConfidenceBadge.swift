import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Float
    let tier: Int16

    private var isUnrecognized: Bool { tier == MatchTier.unrecognized.rawValue }

    var body: some View {
        if isUnrecognized {
            Label("Not recognized", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red)
                .cornerRadius(4)
        }
    }
}
