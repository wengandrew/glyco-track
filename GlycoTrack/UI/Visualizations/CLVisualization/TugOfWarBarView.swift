import SwiftUI

/// Prototype E: Tug of War Bar (CL Visualization)
/// Horizontal bar centered at zero. Harmful segments extend right (red), beneficial left (green).
/// Segment width = magnitude, color = food group.
struct TugOfWarBarView: View {
    let entries: [FoodLogEntry]

    private struct Segment: Identifiable {
        let id: UUID
        let foodDescription: String
        let magnitude: Double
        let foodGroup: FoodGroup
        let isHarmful: Bool
    }

    private var harmfulSegments: [Segment] {
        entries.filter { $0.computedCL > 0 }.map {
            Segment(id: $0.id ?? UUID(), foodDescription: $0.foodDescription,
                    magnitude: $0.computedCL, foodGroup: FoodGroup.from(string: $0.foodGroup ?? "proteins"), isHarmful: true)
        }.sorted { $0.magnitude > $1.magnitude }
    }

    private var beneficialSegments: [Segment] {
        entries.filter { $0.computedCL < 0 }.map {
            Segment(id: $0.id ?? UUID(), foodDescription: $0.foodDescription,
                    magnitude: abs($0.computedCL), foodGroup: FoodGroup.from(string: $0.foodGroup ?? "proteins"), isHarmful: false)
        }.sorted { $0.magnitude > $1.magnitude }
    }

    private var totalHarmful: Double { harmfulSegments.reduce(0) { $0 + $1.magnitude } }
    private var totalBeneficial: Double { beneficialSegments.reduce(0) { $0 + $1.magnitude } }
    private var maxMagnitude: Double { max(totalHarmful, totalBeneficial, 1.0) }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CL Tug of War")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                let halfWidth = geo.size.width / 2

                ZStack(alignment: .center) {
                    // Center line
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(width: 2, height: 48)

                    HStack(spacing: 0) {
                        // Beneficial (extends left from center)
                        HStack(spacing: 1) {
                            ForEach(beneficialSegments.reversed()) { seg in
                                let w = (seg.magnitude / maxMagnitude) * halfWidth
                                Rectangle()
                                    .fill(seg.foodGroup.color)
                                    .frame(width: max(w, 2), height: 32)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: halfWidth, alignment: .trailing)

                        // Harmful (extends right from center)
                        HStack(spacing: 1) {
                            ForEach(harmfulSegments) { seg in
                                let w = (seg.magnitude / maxMagnitude) * halfWidth
                                Rectangle()
                                    .fill(seg.foodGroup.color)
                                    .frame(width: max(w, 2), height: 32)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: halfWidth, alignment: .leading)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 48)

            // Labels
            HStack {
                Image(systemName: "arrow.left")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Beneficial").font(.caption).foregroundColor(.green)
                Spacer()
                Text("Harmful").font(.caption).foregroundColor(.red)
                Image(systemName: "arrow.right")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Net indicator
            if !entries.isEmpty {
                HStack {
                    Text("Net: \(netCL < 0 ? "✓ Beneficial" : "⚠ Harmful")")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(netCL < 0 ? .green : .red)
                    Spacer()
                    Text(String(format: "%.1f", netCL))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(netCL < 0 ? .green : .red)
                }
            }

            // Legend
            FoodGroupLegend()
        }
        .padding()
    }
}

struct FoodGroupLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 4) {
            ForEach(FoodGroup.allCases, id: \.self) { group in
                HStack(spacing: 4) {
                    Circle()
                        .fill(group.color)
                        .frame(width: 8, height: 8)
                    Text(group.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
