import SwiftUI

/// GL × CL Quadrant Plot
/// GL on Y-axis (unsigned, 0+), CL on X-axis (signed, negative=beneficial).
/// Quadrant labels:
///   Top-right:    High GL + Harmful CL = Worst (cake, donuts)
///   Top-left:     High GL + Beneficial CL = Complex (oatmeal, brown rice)
///   Bottom-right: Low GL + Harmful CL = Watch out (butter, cream)
///   Bottom-left:  Low GL + Beneficial CL = Best (vegetables, olive oil)
struct QuadrantPlotView: View {
    let entries: [FoodLogEntry]

    private var maxGL: Double { max(entries.map(\.computedGL).max() ?? 30, 30) }
    private var maxAbsCL: Double { max(entries.map { abs($0.computedCL) }.max() ?? 10, 10) }

    private var centroid: CGPoint? {
        guard !entries.isEmpty else { return nil }
        let avgGL = entries.reduce(0) { $0 + $1.computedGL } / Double(entries.count)
        let avgCL = entries.reduce(0) { $0 + $1.computedCL } / Double(entries.count)
        return CGPoint(x: avgCL, y: avgGL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GL × CL Quadrant")
                .font(.headline)
                .padding(.horizontal)

            Text("Best: bottom-left. Goal: keep your cluster there.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Quadrant backgrounds
                    Group {
                        Rectangle().fill(Color.red.opacity(0.05))
                            .frame(width: w/2, height: h/2)
                            .offset(x: w/4, y: -h/4) // top-right
                        Rectangle().fill(Color.orange.opacity(0.05))
                            .frame(width: w/2, height: h/2)
                            .offset(x: -w/4, y: -h/4) // top-left
                        Rectangle().fill(Color.yellow.opacity(0.05))
                            .frame(width: w/2, height: h/2)
                            .offset(x: w/4, y: h/4) // bottom-right
                        Rectangle().fill(Color.green.opacity(0.07))
                            .frame(width: w/2, height: h/2)
                            .offset(x: -w/4, y: h/4) // bottom-left
                    }

                    // Axes
                    Rectangle().fill(Color(.systemGray3)).frame(width: 1, height: h) // Y-axis
                    Rectangle().fill(Color(.systemGray3)).frame(width: w, height: 1) // X-axis

                    // Quadrant labels
                    Text("Worst").font(.system(size: 9)).foregroundColor(.red.opacity(0.6))
                        .offset(x: w * 0.3, y: -h * 0.35)
                    Text("Complex").font(.system(size: 9)).foregroundColor(.orange.opacity(0.6))
                        .offset(x: -w * 0.3, y: -h * 0.35)
                    Text("Watch Out").font(.system(size: 9)).foregroundColor(.yellow.opacity(0.8))
                        .offset(x: w * 0.3, y: h * 0.35)
                    Text("Best").font(.system(size: 9)).foregroundColor(.green.opacity(0.7))
                        .offset(x: -w * 0.3, y: h * 0.35)

                    // Data points
                    ForEach(entries, id: \.id) { entry in
                        let xFrac = entry.computedCL / (maxAbsCL * 2)
                        let yFrac = entry.computedGL / (maxGL * 2)
                        let x = w/2 + xFrac * w * 0.9
                        let y = h/2 - yFrac * h * 0.9

                        FoodBubble(
                            foodDescription: entry.foodDescription,
                            magnitude: max(entry.computedGL, abs(entry.computedCL)),
                            foodGroup: FoodGroup.from(string: entry.foodGroup),
                            scaleFactor: 2.5
                        )
                        .position(x: x, y: y)
                        .opacity(0.85)
                    }

                    // Centroid crosshair
                    if let c = centroid {
                        let cx = w/2 + (c.x / (maxAbsCL * 2)) * w * 0.9
                        let cy = h/2 - (c.y / (maxGL * 2)) * h * 0.9
                        ZStack {
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 16, height: 1.5)
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 1.5, height: 16)
                            Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1.5).frame(width: 10, height: 10)
                        }
                        .position(x: cx, y: cy)
                    }

                    // Axis labels
                    Text("CL →").font(.system(size: 9)).foregroundColor(.secondary)
                        .offset(x: w * 0.42, y: 2)
                    Text("GL ↑").font(.system(size: 9)).foregroundColor(.secondary)
                        .offset(x: -w * 0.44, y: -h * 0.42)
                }
            }
            .frame(height: 280)
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
