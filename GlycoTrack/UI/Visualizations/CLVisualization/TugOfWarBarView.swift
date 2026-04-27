import SwiftUI

/// Tug of War (CL Visualization).
/// Horizontal bar centered at zero. Beneficial foods (−CL) push LEFT, harmful
/// foods (+CL) push RIGHT. Each food is an emoji token whose width is
/// proportional to |CL| (token height is fixed, so width∝area∝magnitude).
///
/// The bar is horizontally scrollable: the content keeps a fixed
/// `pointsPerCLUnit` scale so token sizes stay comparable across days. On
/// short days content fills `availableWidth`; on heavy days it extends past
/// the visible edge and can be scrolled. The zero line sits at the horizontal
/// center of the content, and the scroll position defaults to centered so
/// the rope marker is initially visible.
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
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    // Visual constants
    private let tokenHeight: CGFloat = 38
    private let tokenSpacing: CGFloat = 2
    private let sideInset: CGFloat = 12
    /// Points of bar width per unit |CL|. Fixed so token sizes are comparable
    /// across days rather than rescaling to fit the screen.
    private let pointsPerCLUnit: CGFloat = 14
    /// Minimum visible width a token occupies regardless of magnitude, so
    /// tiny tokens stay readable.
    private let minTokenWidth: CGFloat = 28

    /// Visual width one side of the bar occupies given its total magnitude,
    /// accounting for the min-width-per-token floor.
    private func sideVisualWidth(tokens: [Token]) -> CGFloat {
        guard !tokens.isEmpty else { return 0 }
        let spacing = CGFloat(max(0, tokens.count - 1)) * tokenSpacing
        let tokenWidths = tokens.reduce(CGFloat(0)) { acc, t in
            acc + max(minTokenWidth, CGFloat(t.magnitude) * pointsPerCLUnit)
        }
        return tokenWidths + spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tug of War")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                let availableWidth = geo.size.width
                let beneficialSide = sideVisualWidth(tokens: beneficialTokens)
                let harmfulSide = sideVisualWidth(tokens: harmfulTokens)
                // Keep symmetric so the rope sits at the content midpoint.
                let halfSide = max(beneficialSide, harmfulSide) + sideInset
                // Full content width; never shrinks below the available width
                // so short days still visually fill the space.
                let contentWidth = max(availableWidth, halfSide * 2)
                let centerAnchorID = "tugofwar.center"

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .center) {
                            // Background rail — spans full content width
                            RoundedRectangle(cornerRadius: tokenHeight / 2)
                                .fill(Color(.systemGray6))
                                .frame(width: contentWidth, height: tokenHeight + 8)

                            HStack(spacing: 0) {
                                // Beneficial (extends left from center)
                                HStack(spacing: tokenSpacing) {
                                    Spacer(minLength: 0)
                                    ForEach(beneficialTokens.reversed()) { token in
                                        tokenView(token, side: .beneficial)
                                    }
                                }
                                .frame(width: contentWidth / 2, alignment: .trailing)

                                // Harmful (extends right from center)
                                HStack(spacing: tokenSpacing) {
                                    ForEach(harmfulTokens) { token in
                                        tokenView(token, side: .harmful)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(width: contentWidth / 2, alignment: .leading)
                            }
                            .frame(width: contentWidth)

                            // Rope marker at the zero line (content midpoint)
                            ropeMarker
                                // Invisible anchor used to center the scroll view on load.
                                .background(
                                    Color.clear
                                        .frame(width: 1, height: 1)
                                        .id(centerAnchorID)
                                )
                        }
                        .frame(width: contentWidth, height: tokenHeight + 24)
                    }
                    .onAppear {
                        // Center the rope in the visible viewport on first appearance.
                        DispatchQueue.main.async {
                            proxy.scrollTo(centerAnchorID, anchor: .center)
                        }
                    }
                    .onChange(of: entries.count) { _ in
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(centerAnchorID, anchor: .center)
                            }
                        }
                    }
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
    private func tokenView(_ token: Token, side: Side) -> some View {
        let w = max(minTokenWidth, CGFloat(token.magnitude) * pointsPerCLUnit)
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
        .allowsHitTesting(false)
    }
}
