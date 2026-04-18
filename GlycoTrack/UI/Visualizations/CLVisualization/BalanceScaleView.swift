import SwiftUI

/// Prototype F: Balance Scale (CL Visualization)
/// Two plates with bubbles. Scale tips toward heavier side (net CL direction).
struct BalanceScaleView: View {
    let entries: [FoodLogEntry]

    private var harmfulEntries: [FoodLogEntry] { entries.filter { $0.computedCL > 0 } }
    private var beneficialEntries: [FoodLogEntry] { entries.filter { $0.computedCL < 0 } }

    private var totalHarmful: Double { harmfulEntries.reduce(0) { $0 + $1.computedCL } }
    private var totalBeneficial: Double { beneficialEntries.reduce(0) { $0 + abs($1.computedCL) } }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    // Tip angle: positive = tips right (harmful heavier), negative = tips left (beneficial heavier)
    private var tipAngle: Double {
        let maxAngle = 25.0
        let ratio = (totalHarmful - totalBeneficial) / max(totalHarmful + totalBeneficial, 1.0)
        return ratio * maxAngle
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("CL Balance")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                ZStack {
                    // Fulcrum
                    VStack(spacing: 0) {
                        Spacer()
                        Triangle()
                            .fill(Color(.systemGray3))
                            .frame(width: 24, height: 20)
                    }

                    // Beam
                    ZStack {
                        Rectangle()
                            .fill(Color(.systemGray2))
                            .frame(width: geo.size.width * 0.85, height: 4)
                            .cornerRadius(2)

                        // Left plate (beneficial)
                        VStack {
                            ScalePlate(entries: beneficialEntries, label: "Beneficial", color: .green, isLeft: true)
                                .offset(x: -geo.size.width * 0.3, y: tipAngle > 0 ? abs(tipAngle) * 1.5 : 0)
                        }

                        // Right plate (harmful)
                        VStack {
                            ScalePlate(entries: harmfulEntries, label: "Harmful", color: .red, isLeft: false)
                                .offset(x: geo.size.width * 0.3, y: tipAngle < 0 ? abs(tipAngle) * 1.5 : 0)
                        }
                    }
                    .rotationEffect(.degrees(tipAngle * 0.4))
                    .offset(y: -20)
                }
            }
            .aspectRatio(1.4, contentMode: .fit)

            // Net result label
            Text(netCL < -0.5 ? "Your choices are net beneficial for heart health." :
                 netCL > 0.5 ? "Your choices are net harmful for heart health." :
                 "Your cholesterol impact is roughly neutral.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct ScalePlate: View {
    let entries: [FoodLogEntry]
    let label: String
    let color: Color
    let isLeft: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Plate
            ZStack {
                Ellipse()
                    .fill(color.opacity(0.1))
                    .stroke(color.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 90, height: 36)

                // Mini bubbles
                HStack(spacing: 3) {
                    ForEach(entries.prefix(4), id: \.id) { entry in
                        let size = CGFloat(max(8, sqrt(abs(entry.computedCL)) * 4))
                        Circle()
                            .fill(FoodGroup.from(string: entry.foodGroup).color.opacity(0.8))
                            .frame(width: min(size, 22), height: min(size, 22))
                    }
                }
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
