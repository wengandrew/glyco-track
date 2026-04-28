import SwiftUI

/// Prototype B: Weekly River
/// Horizontal Mon–Sun timeline. Y-axis = time of day. Bubble size = GL.
///
/// Emoji items are tappable — host views provide an `onTap` handler to route
/// taps to a detail sheet. Default is a no-op so existing call sites still
/// compile.
struct WeeklyRiverView: View {
    let entries: [FoodLogEntry]
    /// Start of the week (Monday 00:00) being displayed. Each entry's column is
    /// computed as days-since-weekStart so columns and entries always agree.
    let weekStart: Date
    var onTap: (FoodLogEntry) -> Void = { _ in }

    init(entries: [FoodLogEntry],
         weekStart: Date,
         onTap: @escaping (FoodLogEntry) -> Void = { _ in }) {
        self.entries = entries
        self.weekStart = weekStart
        self.onTap = onTap
    }

    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private func dayIndex(for date: Date) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: weekStart),
            to: cal.startOfDay(for: date)
        ).day ?? 0
        return min(max(days, 0), 6)
    }

    private func timeOfDayFraction(for date: Date) -> Double {
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: date))
        let minute = Double(cal.component(.minute, from: date))
        return (hour + minute / 60.0) / 24.0
    }

    private let plotHeight: CGFloat = 300
    private let dayHeaderHeight: CGFloat = 16
    private let timeAxisWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Y-axis time labels — top=12am, bottom=12am next day.
            timeAxis
                .frame(width: timeAxisWidth, height: plotHeight)
                .padding(.top, dayHeaderHeight)

            VStack(spacing: 0) {
                // X-axis day headers (Mon..Sun) along the top of the grid.
                GeometryReader { geo in
                    let colWidth = geo.size.width / 7
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(dayLabels[i])
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: colWidth)
                                .offset(x: colWidth * Double(i))
                        }
                    }
                }
                .frame(height: dayHeaderHeight)

                GeometryReader { geo in
                    let colWidth = geo.size.width / 7
                    ZStack(alignment: .topLeading) {
                        // Alternating column backgrounds.
                        ForEach(0..<7, id: \.self) { i in
                            Rectangle()
                                .fill(i % 2 == 0 ? Color(.systemGray6) : Color(.systemBackground))
                                .frame(width: colWidth, height: geo.size.height)
                                .offset(x: colWidth * Double(i))
                        }

                        // Time guidelines (6am, 12pm, 6pm).
                        ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: geo.size.width, height: 0.5)
                                .offset(y: geo.size.height * fraction)
                        }

                        // Food graphics.
                        ForEach(entries, id: \.id) { entry in
                            let col = dayIndex(for: entry.timestamp ?? Date())
                            let yFrac = timeOfDayFraction(for: entry.timestamp ?? Date())
                            let x = colWidth * Double(col) + colWidth / 2
                            let y = geo.size.height * yFrac

                            FoodGraphic(
                                emoji: FoodEmoji.resolve(entry: entry),
                                magnitude: entry.computedGL,
                                areaPerUnit: 40,
                                minSide: 20,
                                maxSide: 64
                            )
                            .contentShape(Circle())
                            .onTapGesture { onTap(entry) }
                            .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: plotHeight)
            }
        }
        .padding(.horizontal, 8)
    }

    private var timeAxis: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("12am")
            Spacer()
            Text("6am")
            Spacer()
            Text("12pm")
            Spacer()
            Text("6pm")
            Spacer()
            Text("12am")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }
}
