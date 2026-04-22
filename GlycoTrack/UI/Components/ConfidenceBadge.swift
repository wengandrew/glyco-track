import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Float
    let tier: Int16

    private var isUnrecognized: Bool { tier == MatchTier.unrecognized.rawValue }
    private var needsRefine: Bool {
        !isUnrecognized && confidence < 0.70
    }

    private var tierLabel: String {
        MatchTier(rawValue: tier)?.shortLabel ?? "T?"
    }

    private var tierColor: Color {
        switch MatchTier(rawValue: tier) {
        case .direct:        return .green
        case .componentB:    return .blue
        case .aiDecomposed:  return .teal
        case .aiBlended:     return .orange
        case .unrecognized:  return .red
        case .none:          return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if isUnrecognized {
                Label("Not recognized", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)
            } else {
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
}
