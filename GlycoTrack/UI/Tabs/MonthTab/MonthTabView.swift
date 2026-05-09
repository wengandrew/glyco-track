import SwiftUI
import CoreData

struct MonthTabView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme

    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: Date())

    @State private var selectedEntry: FoodLogEntry?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO"),
        animation: .default
    )
    private var allEntries: FetchedResults<FoodLogEntry>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO AND timestamp != nil"),
        animation: .default
    )
    private var allEntriesAsc: FetchedResults<FoodLogEntry>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Month navigation
                    HStack(spacing: 16) {
                        if !isEarliestMonth {
                            Button {
                                shiftMonth(by: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(theme.primaryAccent)
                                    .frame(width: 32, height: 32)
                                    .background(Color(.systemGray6))
                                    .clipShape(Circle())
                            }
                        } else {
                            Color.clear.frame(width: 32, height: 32)
                        }
                        Spacer()
                        Text(displayedMonth, format: .dateTime.month(.wide).year())
                            .font(.system(.headline, design: theme.fontDesign))
                        Spacer()
                        if !isCurrentMonth {
                            Button {
                                shiftMonth(by: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(theme.primaryAccent)
                                    .frame(width: 32, height: 32)
                                    .background(Color(.systemGray6))
                                    .clipShape(Circle())
                            }
                        } else {
                            Color.clear.frame(width: 32, height: 32)
                        }
                    }
                    .padding(.horizontal)

                    MonthlyHeatmapView(month: displayedMonth) { date in
                        entries(for: date)
                    }
                    .padding(.horizontal, 4)

                    // Food Impact Map — embedded
                    QuadrantPlotSection(
                        entries: monthEntries,
                        onTap: { selectedEntry = $0 }
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Your Month")
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailSheet(entry: entry)
            }
        }
    }

    private var earliestLoggedMonth: Date? {
        guard let first = allEntriesAsc.first, let ts = first.timestamp else { return nil }
        return Calendar.current.startOfMonth(for: ts)
    }

    private var isEarliestMonth: Bool {
        guard let earliest = earliestLoggedMonth else { return true }
        let cal = Calendar.current
        return cal.component(.year, from: displayedMonth) == cal.component(.year, from: earliest)
            && cal.component(.month, from: displayedMonth) == cal.component(.month, from: earliest)
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

    private func shiftMonth(by delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }
}

extension Calendar {
    /// Start of the month containing `date` (day-1 at 00:00). Falls back to the
    /// start of the day if the year/month components can't be reassembled, so
    /// no caller has to force-unwrap.
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
