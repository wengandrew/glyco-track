import SwiftUI
import CoreData

struct WeekTabView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: weekPredicate(),
        animation: .default
    )
    private var weekEntries: FetchedResults<FoodLogEntry>

    @State private var selectedEntry: FoodLogEntry?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Weekly GL river — items tappable via onTap
                    WeeklyRiverView(entries: Array(weekEntries), onTap: { selectedEntry = $0 })
                        .padding(.horizontal, 4)

                    Divider().padding(.horizontal)

                    // CL bar (always shown — toggle removed)
                    TugOfWarBarView(entries: Array(weekEntries))
                        .padding(.horizontal)

                    // Week summary (unified card)
                    PeriodSummaryView(
                        title: "Week Summary",
                        entries: Array(weekEntries),
                        daysInPeriod: 7
                    )
                    .padding(.horizontal)

                    // GL × CL Quadrant — embedded
                    QuadrantPlotSection(
                        entries: Array(weekEntries),
                        onTap: { selectedEntry = $0 }
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .navigationTitle("This Week")
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailSheet(entry: entry)
            }
        }
    }
}

private func weekPredicate() -> NSPredicate {
    let cal = Calendar.current
    let now = Date()
    let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
    let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
    return NSPredicate(format: "timestamp >= %@ AND timestamp < %@ AND isSoftDeleted == NO",
                       start as NSDate, end as NSDate)
}
