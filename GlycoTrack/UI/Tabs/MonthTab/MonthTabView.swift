import SwiftUI
import CoreData

struct MonthTabView: View {
    @Environment(\.managedObjectContext) private var context

    @State private var displayedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    )!

    @State private var selectedEntry: FoodLogEntry?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO"),
        animation: .default
    )
    private var allEntries: FetchedResults<FoodLogEntry>

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Month navigation
                    HStack {
                        Button {
                            displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth)!
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(displayedMonth, format: .dateTime.month(.wide).year())
                            .font(.headline)
                        Spacer()
                        Button {
                            displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth)!
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(isCurrentMonth)
                    }
                    .padding(.horizontal)

                    MonthlyHeatmapView(month: displayedMonth) { date in
                        entries(for: date)
                    }
                    .padding(.horizontal, 4)

                    // Month summary (unified card)
                    PeriodSummaryView(
                        title: "Month Summary",
                        entries: monthEntries,
                        daysInPeriod: daysInDisplayedMonth
                    )
                    .padding(.horizontal)

                    // GL × CL Quadrant — embedded
                    QuadrantPlotSection(
                        entries: monthEntries,
                        onTap: { selectedEntry = $0 }
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("Month")
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailSheet(entry: entry)
            }
        }
    }

    private var isCurrentMonth: Bool {
        let cal = Calendar.current
        return cal.component(.month, from: displayedMonth) == cal.component(.month, from: Date())
            && cal.component(.year, from: displayedMonth) == cal.component(.year, from: Date())
    }

    /// Number of days in the displayed month (28–31). Used as the divisor
    /// for the Month Summary's Avg Daily GL stat.
    private var daysInDisplayedMonth: Int {
        let cal = Calendar.current
        return cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    private var monthEntries: [FoodLogEntry] {
        let cal = Calendar.current
        return allEntries.filter {
            cal.component(.month, from: $0.timestamp ?? Date()) == cal.component(.month, from: displayedMonth)
            && cal.component(.year, from: $0.timestamp ?? Date()) == cal.component(.year, from: displayedMonth)
        }
    }

    private func entries(for date: Date) -> [FoodLogEntry] {
        let cal = Calendar.current
        return allEntries.filter { cal.isDate($0.timestamp ?? Date(), inSameDayAs: date) }
    }
}
