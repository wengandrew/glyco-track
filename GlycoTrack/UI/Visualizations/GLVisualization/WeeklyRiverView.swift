import SwiftUI

/// Weekly River — horizontal Mon–Sun timeline. Y-axis = time of day. Bubble size = GL.
struct WeeklyRiverView: View {
    let entries: [FoodLogEntry]
    /// Start of the week (Monday 00:00) being displayed.
    let weekStart: Date
    /// Fired when a food bubble is tapped — routes to detail sheet.
    var onTap: (FoodLogEntry) -> Void = { _ in }
    /// Fired when the user taps an empty area inside a day column — routes
    /// to the Today tab with that day selected.
    var onDayTap: (Date) -> Void = { _ in }

    init(entries: [FoodLogEntry],
         weekStart: Date,
         onTap: @escaping (FoodLogEntry) -> Void = { _ in },
         onDayTap: @escaping (Date) -> Void = { _ in }) {
        self.entries = entries
        self.weekStart = weekStart
        self.onTap = onTap
        self.onDayTap = onDayTap
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

    private func date(forColumn col: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: col, to: Calendar.current.startOfDay(for: weekStart)) ?? weekStart
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
                                    .foregroundColor(isToday ? Color(.systemBlue) : .secondary)
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
                        // Background
                        Color(.secondarySystemGroupedBackground)
                            .frame(width: geo.size.width, height: geo.size.height)

                        // Today column highlight
                        if let todayIdx = todayColumnIndex {
                            Color(.systemBlue).opacity(0.07)
                                .frame(width: colWidth, height: geo.size.height)
                                .offset(x: colWidth * Double(todayIdx))
                        }

                        // Vertical separators between days
                        ForEach(1..<7, id: \.self) { i in
                            Color(.separator)
                                .frame(width: 0.5, height: geo.size.height)
                                .offset(x: colWidth * Double(i))
                        }

                        // Time guidelines (6am, 12pm, 6pm)
                        ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                            Color(.systemGray4)
                                .frame(width: geo.size.width, height: 0.5)
                                .offset(y: geo.size.height * fraction)
                        }

                        // Column tap targets — below food graphics so food taps
                        // take priority in the ZStack. Tapping empty column area
                        // navigates to that day in the Today tab.
                        ForEach(0..<7, id: \.self) { i in
                            let colDate = date(forColumn: i)
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: colWidth, height: geo.size.height)
                                .offset(x: colWidth * Double(i))
                                .onTapGesture { onDayTap(colDate) }
                        }

                        // Food graphics — on top, capturing taps before column backgrounds
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
        .foregroundColor(.secondary)
        .padding(.trailing, 4)
    }
}
