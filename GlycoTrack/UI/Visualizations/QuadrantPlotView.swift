import SwiftUI

/// GL × CL Two-Region Plot — embeddable section.
///
/// **Why two regions, not four quadrants?** GL is always ≥ 0 (it's a load, not a balance);
/// only CL is signed. A four-quadrant grid would always leave the bottom two quadrants
/// empty, wasting vertical space and confusing readers into thinking "negative GL"
/// means something. Splitting only by the CL = 0 axis gives:
///
///   • Left  half — Beneficial CL (negative): fiber, PUFA, MUFA dominant
///   • Right half — Harmful CL (positive): SFA, TFA dominant
///
/// The Y-axis is GL going UP from a baseline at the bottom (GL = 0). Within each half,
/// items higher in the chart contribute more glycemic load. The cluster ideal is
/// "low and to the left": low GL, beneficial CL.
///
/// Embeddable — no sheet, no navigation. Host views own tap routing via `onTap`.
struct QuadrantPlotSection: View {
    let entries: [FoodLogEntry]
    let onTap: (FoodLogEntry) -> Void

    init(entries: [FoodLogEntry], onTap: @escaping (FoodLogEntry) -> Void = { _ in }) {
        self.entries = entries
        self.onTap = onTap
    }

    private var maxGL: Double { max(entries.map(\.computedGL).max() ?? 30, 30) }
    private var maxAbsCL: Double { max(entries.map { abs($0.computedCL) }.max() ?? 10, 10) }

    private var centroid: CGPoint? {
        guard !entries.isEmpty else { return nil }
        let avgGL = entries.reduce(0) { $0 + $1.computedGL } / Double(entries.count)
        let avgCL = entries.reduce(0) { $0 + $1.computedCL } / Double(entries.count)
        return CGPoint(x: avgCL, y: avgGL)
    }

    /// Vertical insets so emojis aren't cropped by the section frame.
    private let topInsetFrac: CGFloat = 0.08
    private let bottomInsetFrac: CGFloat = 0.10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GL × CL")
                .font(.headline)
                .padding(.horizontal)

            Text("Goal: keep your foods low and to the left.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let plotHeight = h * (1 - topInsetFrac - bottomInsetFrac)
                let baselineY = h * (1 - bottomInsetFrac)

                ZStack {
                    // Two-region backgrounds — split by the vertical CL = 0 axis.
                    Group {
                        Rectangle().fill(Color.green.opacity(0.07))
                            .frame(width: w / 2, height: h)
                            .offset(x: -w / 4)
                        Rectangle().fill(Color.red.opacity(0.05))
                            .frame(width: w / 2, height: h)
                            .offset(x: w / 4)
                    }

                    // Vertical CL = 0 axis (full height of plot area)
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(width: 1, height: h)

                    // Horizontal GL = 0 baseline (at the bottom — GL is unsigned)
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(width: w, height: 1)
                        .position(x: w / 2, y: baselineY)

                    // Region labels — placed at the top since the chart grows upward.
                    Text("Beneficial")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green.opacity(0.7))
                        .position(x: w * 0.22, y: h * 0.06)
                    Text("Harmful")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red.opacity(0.65))
                        .position(x: w * 0.78, y: h * 0.06)

                    // Data points — Y axis grows upward from the baseline.
                    ForEach(entries, id: \.id) { entry in
                        let xFrac = entry.computedCL / (maxAbsCL * 2)             // -0.5 … +0.5
                        let yFrac = min(max(entry.computedGL / maxGL, 0), 1)      //   0  …  1
                        let x = w / 2 + xFrac * w * 0.9
                        let y = baselineY - yFrac * plotHeight

                        FoodGraphic(
                            emoji: FoodEmoji.resolve(entry: entry),
                            magnitude: max(entry.computedGL, abs(entry.computedCL)),
                            areaPerUnit: 60,
                            minSide: 24,
                            maxSide: 72
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(entry) }
                        .position(x: x, y: y)
                        .opacity(0.95)
                    }

                    // Centroid crosshair
                    if let c = centroid {
                        let cxFrac = c.x / (maxAbsCL * 2)
                        let cyFrac = min(max(c.y / maxGL, 0), 1)
                        let cx = w / 2 + cxFrac * w * 0.9
                        let cy = baselineY - cyFrac * plotHeight
                        ZStack {
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 16, height: 1.5)
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 1.5, height: 16)
                            Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1.5).frame(width: 10, height: 10)
                        }
                        .position(x: cx, y: cy)
                        .allowsHitTesting(false)
                    }

                    // Axis hints
                    Text("CL →")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .position(x: w * 0.92, y: baselineY + 10)
                    Text("GL ↑")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .position(x: 14, y: h * 0.04)
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 8)

            // Axis legend
            HStack {
                Text("← Beneficial CL").font(.caption2).foregroundColor(.green)
                Spacer()
                Text("Harmful CL →").font(.caption2).foregroundColor(.red)
            }
            .padding(.horizontal, 12)
        }
    }
}
