import SwiftUI

/// Tug of War (CL Visualization).
/// Horizontal bar centered at zero. Beneficial foods (−CL) push LEFT, harmful foods
/// (+CL) push RIGHT. Each food is an emoji token whose width is proportional to |CL|
/// (token height is fixed, so width∝area∝magnitude). The rope marker in the middle
/// is offset toward the winning side by the net CL.
struct TugOfWarBarView: View {
    let entries: [FoodLogEntry]

    @State private var selectedEntry: FoodLogEntry?

    private struct Token: Identifiable {
        let id: UUID
        let entry: FoodLogEntry
        let magnitude: Double
        let emoji: String
    }

    private var harmfulTokens: [Token] {
        entries.filter { $0.computedCL > 0 }
            .sorted { $0.computedCL > $1.computedCL }
            .map { Token(id: $0.id ?? UUID(), entry: $0, magnitude: $0.computedCL,
                         emoji: FoodEmoji.resolve(entry: $0)) }
    }

    private var beneficialTokens: [Token] {
        entries.filter { $0.computedCL < 0 }
            .sorted { $0.computedCL < $1.computedCL }
            .map { Token(id: $0.id ?? UUID(), entry: $0, magnitude: abs($0.computedCL),
                         emoji: FoodEmoji.resolve(entry: $0)) }
    }

    private var totalHarmful: Double { harmfulTokens.reduce(0) { $0 + $1.magnitude } }
    private var totalBeneficial: Double { beneficialTokens.reduce(0) { $0 + $1.magnitude } }
    private var maxTotal: Double { max(totalHarmful, totalBeneficial, 1.0) }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }
    private var ropeOffset: Double {
        // Offset of the center rope marker as fraction of half-width, clamped.
        let ratio = (totalHarmful - totalBeneficial) / max(totalHarmful + totalBeneficial, 1.0)
        return max(-0.95, min(ratio, 0.95))
    }

    private let tokenHeight: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tug of War")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                let halfWidth = geo.size.width / 2
                let totalMagnitude = totalHarmful + totalBeneficial
                // Points of bar width per unit |CL|. One unit of total magnitude spans
                // the whole bar; beyond that we scale down.
                let pointsPerUnit = totalMagnitude > 0 ? (geo.size.width / CGFloat(max(totalMagnitude, maxTotal * 2))) : 0

                ZStack(alignment: .center) {
                    // Background rail
                    RoundedRectangle(cornerRadius: tokenHeight / 2)
                        .fill(Color(.systemGray6))
                        .frame(height: tokenHeight + 8)

                    HStack(spacing: 0) {
                        // Beneficial (extends left from center)
                        HStack(spacing: 2) {
                            Spacer(minLength: 0)
                            ForEach(beneficialTokens.reversed()) { token in
                                tokenView(token, pointsPerUnit: pointsPerUnit, side: .beneficial)
                            }
                        }
                        .frame(width: halfWidth, alignment: .trailing)

                        // Harmful (extends right from center)
                        HStack(spacing: 2) {
                            ForEach(harmfulTokens) { token in
                                tokenView(token, pointsPerUnit: pointsPerUnit, side: .harmful)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: halfWidth, alignment: .leading)
                    }
                    .padding(.horizontal, 4)

                    // Rope marker (the tug position)
                    ropeMarker
                        .offset(x: CGFloat(ropeOffset) * (halfWidth - 12))
                }
            }
            .frame(height: tokenHeight + 24)

            // Zero / direction labels
            HStack {
                Text("← Beneficial").font(.caption2).foregroundColor(.green)
                Spacer()
                Text("0").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("Harmful →").font(.caption2).foregroundColor(.red)
            }

            if entries.isEmpty {
                Text("Log food to see the tug").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .sheet(item: $selectedEntry) { entry in
            FoodEntryDetailSheet(entry: entry)
        }
    }

    private enum Side { case harmful, beneficial }

    @ViewBuilder
    private func tokenView(_ token: Token, pointsPerUnit: CGFloat, side: Side) -> some View {
        // Minimum width keeps emojis readable even for tiny items.
        let w = max(28, CGFloat(token.magnitude) * pointsPerUnit)
        let tint: Color = side == .harmful ? .red : .green
        Button {
            selectedEntry = token.entry
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.5), lineWidth: 1))
                Text(token.emoji)
                    .font(.system(size: min(tokenHeight * 0.62, w * 0.62)))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(width: w, height: tokenHeight)
        }
        .buttonStyle(.plain)
    }

    private var ropeMarker: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundColor(netCL > 0 ? .red : (netCL < 0 ? .green : .gray))
            Rectangle()
                .fill(netCL > 0 ? Color.red : (netCL < 0 ? Color.green : Color.gray))
                .frame(width: 2, height: tokenHeight + 8)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 10))
                .foregroundColor(netCL > 0 ? .red : (netCL < 0 ? .green : .gray))
        }
    }
}
