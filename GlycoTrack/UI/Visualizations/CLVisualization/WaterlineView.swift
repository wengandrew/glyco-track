import SwiftUI

/// Prototype D: Waterline (CL Visualization)
/// Container with center line at zero. Harmful (positive CL) bubbles float above,
/// beneficial (negative CL) sink below. Water level shows net CL.
struct WaterlineView: View {
    let entries: [FoodLogEntry]

    private var harmfulEntries: [FoodLogEntry] {
        entries.filter { $0.computedCL > 0 }.sorted { $0.computedCL > $1.computedCL }
    }

    private var beneficialEntries: [FoodLogEntry] {
        entries.filter { $0.computedCL < 0 }.sorted { $0.computedCL < $1.computedCL }
    }

    private var netCL: Double {
        entries.reduce(0) { $0 + $1.computedCL }
    }

    private var waterLevel: Double {
        let maxMagnitude = 20.0
        let clamped = max(-maxMagnitude, min(netCL, maxMagnitude))
        return 0.5 - (clamped / (maxMagnitude * 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cholesterol Load")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                ZStack {
                    // Container
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)

                    // Water fill
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(netCL > 0
                                  ? Color.red.opacity(0.12)
                                  : Color.green.opacity(0.12))
                            .frame(height: geo.size.height * min(max(waterLevel, 0.05), 0.95))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Center zero line
                    Rectangle()
                        .fill(Color(.systemGray2))
                        .frame(height: 1)
                        .offset(y: 0)

                    // Zero label
                    HStack {
                        Text("0")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .offset(x: 4)
                        Spacer()
                    }

                    // Harmful bubbles (above center)
                    HarmfulBubbleLayout(entries: harmfulEntries, containerSize: CGSize(width: geo.size.width, height: geo.size.height / 2))
                        .frame(width: geo.size.width, height: geo.size.height / 2)
                        .offset(y: -geo.size.height / 4)

                    // Beneficial bubbles (below center)
                    BeneficialBubbleLayout(entries: beneficialEntries, containerSize: CGSize(width: geo.size.width, height: geo.size.height / 2))
                        .frame(width: geo.size.width, height: geo.size.height / 2)
                        .offset(y: geo.size.height / 4)

                    // Labels
                    VStack {
                        HStack {
                            Text("Harmful ↑").font(.system(size: 10)).foregroundColor(.red.opacity(0.7))
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Text("Beneficial ↓").font(.system(size: 10)).foregroundColor(.green.opacity(0.7))
                            Spacer()
                        }
                    }
                    .padding(8)
                }
            }
            .aspectRatio(0.75, contentMode: .fit)
        }
        .padding()
    }
}

struct HarmfulBubbleLayout: View {
    let entries: [FoodLogEntry]
    let containerSize: CGSize

    var body: some View {
        Canvas { context, size in
            var placed: [(CGPoint, CGFloat)] = []
            for entry in entries {
                let r = CGFloat(max(10, sqrt(abs(entry.computedCL)) * 5))
                let center = findSpot(r: r, placed: placed, size: size)
                placed.append((center, r))
                let group = FoodGroup.from(string: entry.foodGroup)
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)), with: .color(group.color.opacity(0.8)))
            }
        }
    }

    private func findSpot(r: CGFloat, placed: [(CGPoint, CGFloat)], size: CGSize) -> CGPoint {
        for _ in 0..<150 {
            let x = CGFloat.random(in: r...(size.width - r))
            let y = CGFloat.random(in: r...(size.height - r))
            let pt = CGPoint(x: x, y: y)
            if !placed.contains(where: { hypot($0.0.x - pt.x, $0.0.y - pt.y) < $0.1 + r + 3 }) {
                return pt
            }
        }
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }
}

struct BeneficialBubbleLayout: View {
    let entries: [FoodLogEntry]
    let containerSize: CGSize

    var body: some View {
        Canvas { context, size in
            var placed: [(CGPoint, CGFloat)] = []
            for entry in entries {
                let r = CGFloat(max(10, sqrt(abs(entry.computedCL)) * 5))
                let center = findSpot(r: r, placed: placed, size: size)
                placed.append((center, r))
                let group = FoodGroup.from(string: entry.foodGroup)
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)), with: .color(group.color.opacity(0.8)))
            }
        }
    }

    private func findSpot(r: CGFloat, placed: [(CGPoint, CGFloat)], size: CGSize) -> CGPoint {
        for _ in 0..<150 {
            let x = CGFloat.random(in: r...(size.width - r))
            let y = CGFloat.random(in: r...(size.height - r))
            let pt = CGPoint(x: x, y: y)
            if !placed.contains(where: { hypot($0.0.x - pt.x, $0.0.y - pt.y) < $0.1 + r + 3 }) {
                return pt
            }
        }
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }
}

struct CLNetLabel: View {
    let netCL: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: netCL > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(netCL > 0 ? .red : .green)
            Text(String(format: "CL %.1f", netCL))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(netCL > 0 ? .red : .green)
        }
    }
}
