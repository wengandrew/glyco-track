import SwiftUI

/// Prototype B: Weekly River
/// Horizontal Mon–Sun timeline. Y-axis = time of day. Bubble size = GL, color = food group.
struct WeeklyRiverView: View {
    let entries: [FoodLogEntry]

    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private func dayIndex(for date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        // weekday: 1=Sun, 2=Mon ... 7=Sat; convert to Mon=0, ..., Sun=6
        return (weekday + 5) % 7
    }

    private func timeOfDayFraction(for date: Date) -> Double {
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: date))
        let minute = Double(cal.component(.minute, from: date))
        return (hour + minute / 60.0) / 24.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly GL River")
                .font(.headline)
                .padding(.horizontal)

            GeometryReader { geo in
                let colWidth = geo.size.width / 7
                ZStack(alignment: .topLeading) {
                    // Grid
                    ForEach(0..<7, id: \.self) { i in
                        Rectangle()
                            .fill(i % 2 == 0 ? Color(.systemGray6) : Color(.systemBackground))
                            .frame(width: colWidth, height: geo.size.height)
                            .offset(x: colWidth * Double(i))
                    }

                    // Time guidelines (6am, 12pm, 6pm)
                    ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(width: geo.size.width, height: 0.5)
                            .offset(y: geo.size.height * fraction)
                    }

                    // Bubbles
                    ForEach(entries, id: \.id) { entry in
                        let col = dayIndex(for: entry.timestamp ?? Date())
                        let yFrac = timeOfDayFraction(for: entry.timestamp ?? Date())
                        let radius = CGFloat(max(8, sqrt(entry.computedGL) * 3.5))
                        let x = colWidth * Double(col) + colWidth / 2
                        let y = geo.size.height * yFrac

                        FoodBubble(
                            foodDescription: entry.foodDescription,
                            magnitude: entry.computedGL,
                            foodGroup: FoodGroup.from(string: entry.foodGroup),
                            scaleFactor: 3.5
                        )
                        .position(x: x, y: y)
                    }

                    // Day labels
                    ForEach(0..<7, id: \.self) { i in
                        Text(dayLabels[i])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: colWidth)
                            .offset(x: colWidth * Double(i), y: geo.size.height - 16)
                    }
                }
            }
            .frame(height: 300)
            .padding(.horizontal, 8)

            // Time axis labels
            HStack {
                Text("12am").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("6am").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("12pm").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("6pm").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("12am").font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
    }
}
