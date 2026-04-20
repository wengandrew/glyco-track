import SwiftUI

/// Prototype C: Monthly Heatmap
/// Calendar grid. Cell color = total daily GL (green → red gradient). Tap day → drill to DailyBucketView.
struct MonthlyHeatmapView: View {
    let month: Date
    let getDayEntries: (Date) -> [FoodLogEntry]

    @State private var selectedDate: Date?

    private var calendarDays: [Date?] {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: month)
        guard let firstDay = cal.date(from: components) else { return [] }
        let weekday = cal.component(.weekday, from: firstDay)
        let leadingBlanks = (weekday + 5) % 7 // Monday-first offset
        let range = cal.range(of: .day, in: .month, for: firstDay)!
        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            days.append(cal.date(byAdding: .day, value: day - 1, to: firstDay))
        }
        return days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            // Weekday labels
            HStack(spacing: 0) {
                ForEach(["M", "Tu", "W", "Th", "F", "Sa", "Su"], id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(date: day, entries: getDayEntries(day))
                            .onTapGesture { selectedDate = day }
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, 8)

            // Legend
            HStack(spacing: 12) {
                Text("GL:").font(.caption2).foregroundColor(.secondary)
                ForEach([(0.0, "0"), (0.3, "30"), (0.6, "60"), (1.0, "100+")], id: \.1) { (fraction, label) in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(glGradientColor(fraction: fraction))
                            .frame(width: 14, height: 14)
                        Text(label).font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .sheet(isPresented: Binding(
            get: { selectedDate != nil },
            set: { if !$0 { selectedDate = nil } }
        )) {
            if let date = selectedDate {
                NavigationView {
                    DailyBucketView(entries: getDayEntries(date))
                        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { selectedDate = nil }
                            }
                        }
                }
            }
        }
    }
}

struct DayCell: View {
    let date: Date
    let entries: [FoodLogEntry]

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var fraction: Double { min(totalGL / dailyGLBudgetUI, 1.0) }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(totalGL > 0 ? glGradientColor(fraction: fraction) : Color(.systemGray6))

            if isToday {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
            }

            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(totalGL > 0 ? .white : .primary)
                if totalGL > 0 {
                    Text("\(Int(totalGL))")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

