import SwiftUI

/// Prototype A: Daily GL Bucket
/// Fixed container representing daily GL budget (100). Bubbles fill from bottom,
/// sorted ascending (low GL first). Bubbles overflow the container when budget exceeded.
struct DailyBucketView: View {
    let entries: [FoodLogEntry]
    let budget: Double = dailyGLBudgetUI

    private var sortedEntries: [FoodLogEntry] {
        entries.sorted { $0.computedGL < $1.computedGL }
    }

    private var totalGL: Double {
        entries.reduce(0) { $0 + $1.computedGL }
    }

    private var fillFraction: Double {
        min(totalGL / budget, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily GL")
                    .font(.headline)
                Spacer()
                GLStatusLabel(total: totalGL, budget: budget)
            }

            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Bucket container
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray3), lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )

                    // Fill level
                    RoundedRectangle(cornerRadius: 12)
                        .fill(glGradientColor(fraction: fillFraction).opacity(0.15))
                        .frame(height: geo.size.height * fillFraction)

                    // Overflow indicator
                    if totalGL > budget {
                        OverflowBanner()
                    }

                    // Bubbles
                    BubbleLayout(entries: sortedEntries, containerSize: geo.size)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .aspectRatio(0.75, contentMode: .fit)

            // Budget bar
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 8)
                        Capsule()
                            .fill(glGradientColor(fraction: fillFraction))
                            .frame(width: geo.size.width * fillFraction, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("0").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("100 GL budget").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

struct GLStatusLabel: View {
    let total: Double
    let budget: Double

    var body: some View {
        let level = GLThresholdLevel.from(gl: total)
        Text("\(Int(total)) / \(Int(budget)) GL")
            .font(.subheadline).fontWeight(.semibold)
            .foregroundColor(total > budget ? .red : .primary)
    }
}

struct OverflowBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text("Over budget!")
                .font(.caption).fontWeight(.bold).foregroundColor(.red)
        }
        .padding(6)
        .background(.regularMaterial)
        .cornerRadius(8)
    }
}

struct BubbleLayout: View {
    let entries: [FoodLogEntry]
    let containerSize: CGSize

    var body: some View {
        Canvas { context, size in
            var placedCircles: [(CGPoint, CGFloat)] = []

            for entry in entries {
                let radius = CGFloat(max(12, sqrt(entry.computedGL) * 4.5))
                let center = findPosition(radius: radius, placed: placedCircles, containerSize: size)
                placedCircles.append((center, radius))

                let group = FoodGroup.from(string: entry.foodGroup)
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                var resolvedColor = context.resolve(group.color.opacity(0.85))
                context.fill(Path(ellipseIn: rect), with: .color(group.color.opacity(0.85)))

                if radius > 20 {
                    let text = entry.foodDescription.prefix(12)
                    context.draw(
                        Text(text).font(.system(size: min(11, radius * 0.35))).foregroundColor(.white),
                        at: center
                    )
                }
                let _ = resolvedColor
            }
        }
    }

    private func findPosition(radius: CGFloat, placed: [(CGPoint, CGFloat)], containerSize: CGSize) -> CGPoint {
        let padding: CGFloat = 4
        var attempts = 0
        while attempts < 200 {
            let x = CGFloat.random(in: radius + padding...(containerSize.width - radius - padding))
            let y = CGFloat.random(in: radius + padding...(containerSize.height - radius - padding))
            let point = CGPoint(x: x, y: y)
            if !placed.contains(where: { distance($0.0, point) < $0.1 + radius + padding }) {
                return point
            }
            attempts += 1
        }
        return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }
}
