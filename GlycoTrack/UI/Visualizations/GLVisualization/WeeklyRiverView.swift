import SwiftUI

/// Weekly River — horizontal Mon–Sun timeline. Y-axis = time of day. Bubble size = GL.
struct WeeklyRiverView: View {
    let entries: [FoodLogEntry]
    /// Start of the week (Monday 00:00) being displayed.
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

    private var todayColumnIndex: Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: weekStart)) ?? weekStart
        guard today >= cal.startOfDay(for: weekStart), today < weekEnd else { return nil }
        return dayIndex(for: Date())
    }

    private let plotHeight: CGFloat = 300
    private let dayHeaderHeight: CGFloat = 36
    private let timeAxisWidth: CGFloat = 32

    private var dailyGLTotals: [Int: Double] {
        var totals: [Int: Double] = [:]
        for entry in entries {
            let col = dayIndex(for: entry.timestamp ?? Date())
            totals[col, default: 0] += entry.computedGL
        }
        return totals
    }

    // Warm neutral matching the app's card background palette.
    private let gridBackground = Color(red: 0.97, green: 0.95, blue: 0.91)
    private let todayTint = Color(red: 0.55, green: 0.63, blue: 0.32).opacity(0.10)
    private let separatorColor = Color(red: 0.85, green: 0.82, blue: 0.76)
    private let guidelineColor = Color(red: 0.80, green: 0.77, blue: 0.72)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Y-axis time labels
            timeAxis
                .frame(width: timeAxisWidth, height: plotHeight)
                .padding(.top, dayHeaderHeight)

            VStack(spacing: 0) {
                // Day headers
                GeometryReader { geo in
                    let colWidth = geo.size.width / 7
                    let glTotals = dailyGLTotals
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<7, id: \.self) { i in
                            let isToday = todayColumnIndex == i
                            VStack(spacing: 1) {
                                Text(dayLabels[i])
                                    .font(.system(size: 11, weight: isToday ? .bold : .medium))
                                    .foregroundColor(isToday ? Color(red: 0.55, green: 0.63, blue: 0.32) : .secondary)
                                if let gl = glTotals[i], gl > 0 {
                                    Text("\(Int(gl.rounded()))")
                                        .font(.system(size: 9, weight: .regular))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("")
                                        .font(.system(size: 9))
                                }
                            }
                            .frame(width: colWidth)
                            .offset(x: colWidth * Double(i))
                        }
                    }
                }
                .frame(height: dayHeaderHeight)

                GeometryReader { geo in
                    let colWidth = geo.size.width / 7
                    ZStack(alignment: .topLeading) {
                        // Unified warm background
                        Rectangle()
                            .fill(gridBackground)
                            .frame(width: geo.size.width, height: geo.size.height)

                        // Today column highlight
                        if let todayIdx = todayColumnIndex {
                            Rectangle()
                                .fill(todayTint)
                                .frame(width: colWidth, height: geo.size.height)
                                .offset(x: colWidth * Double(todayIdx))
                        }

                        // Vertical separators between days
                        ForEach(1..<7, id: \.self) { i in
                            Rectangle()
                                .fill(separatorColor)
                                .frame(width: 0.5, height: geo.size.height)
                                .offset(x: colWidth * Double(i))
                        }

                        // Time guidelines (6am, 12pm, 6pm)
                        ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                            Rectangle()
                                .fill(guidelineColor)
                                .frame(width: geo.size.width, height: 0.5)
                                .offset(y: geo.size.height * fraction)
                        }

                        // Food graphics
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
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 4)
    }

    private var timeAxis: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("12a")
            Spacer()
            Text("6a")
            Spacer()
            Text("12p")
            Spacer()
            Text("6p")
            Spacer()
            Text("12a")
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(Color(red: 0.60, green: 0.57, blue: 0.52))
        .padding(.trailing, 4)
    }
}
