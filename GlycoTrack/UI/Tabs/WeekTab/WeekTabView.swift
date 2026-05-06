import SwiftUI
import CoreData

struct WeekTabView: View {
    @Environment(\.appTheme) private var theme
    @State private var selectedWeekStart: Date = WeekTabView.mondayWeekStart(for: Date())
    @State private var selectedEntry: FoodLogEntry?

    @FetchRequest private var weekEntries: FetchedResults<FoodLogEntry>
    /// Same shape as `weekEntries` but for the seven days *before* the
    /// selected week. Drives `WeekComparisonStrip`'s deltas. Predicate is
    /// updated alongside `weekEntries` whenever `selectedWeekStart` changes.
    @FetchRequest private var priorWeekEntries: FetchedResults<FoodLogEntry>

    /// Earliest logged entry — used to clamp backward week navigation.
    /// `timestamp != nil` so a stray nil-timestamp row can't become `.first`
    /// and silently disable the back-chevron.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO AND timestamp != nil"),
        animation: .default
    )
    private var allEntriesAsc: FetchedResults<FoodLogEntry>

    init() {
        let weekStart = Self.mondayWeekStart(for: Date())
        _weekEntries = FetchRequest<FoodLogEntry>(
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
            predicate: Self.predicate(for: weekStart),
            animation: .default
        )
        _priorWeekEntries = FetchRequest<FoodLogEntry>(
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
            predicate: Self.predicate(for: Self.priorWeekStart(for: weekStart)),
            animation: .default
        )
    }

    var body: some View {
        // `NavigationStack` (iOS 16+) replaces the deprecated `NavigationView`.
        // The old container intermittently dropped the large title on tab
        // switch — most visibly on this tab because of its three @FetchRequest
        // instances + heavy sub-tree (river + period + comparison + quadrant).
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    weekNavigator
                        .padding(.horizontal)

                    WeeklyRiverView(
                        entries: Array(weekEntries),
                        weekStart: selectedWeekStart,
                        onTap: { selectedEntry = $0 }
                    )
                    .padding(.horizontal, 4)

                    Divider().padding(.horizontal)

                    PeriodSummaryView(
                        title: "Week Summary",
                        entries: Array(weekEntries),
                        daysInPeriod: 7
                    )
                    .padding(.horizontal)

                    WeekComparisonStrip(
                        currentEntries: Array(weekEntries),
                        priorEntries: Array(priorWeekEntries),
                        daysInPeriod: 7
                    )
                    .padding(.horizontal)

                    QuadrantPlotSection(
                        entries: Array(weekEntries),
                        onTap: { selectedEntry = $0 }
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .navigationTitle("Your Week")
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailSheet(entry: entry)
            }
            .onChange(of: selectedWeekStart) { newValue in
                weekEntries.nsPredicate = Self.predicate(for: newValue)
                priorWeekEntries.nsPredicate = Self.predicate(for: Self.priorWeekStart(for: newValue))
            }
        }
    }

    // MARK: - Week navigation

    private var weekNavigator: some View {
        HStack(spacing: 16) {
            Button {
                changeWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isEarliestWeek ? .secondary : theme.primaryAccent)
                    .frame(width: 32, height: 32)
                    .background(theme == .midnight ? Color.white.opacity(0.08) : Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(isEarliestWeek)

            VStack(spacing: 0) {
                Text(weekHeading)
                    .font(.system(.subheadline, design: theme.fontDesign, weight: .semibold))
                Text(weekSubheading)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                changeWeek(to: Self.mondayWeekStart(for: Date()))
            }

            Button {
                changeWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isCurrentWeek ? .secondary : theme.primaryAccent)
                    .frame(width: 32, height: 32)
                    .background(theme == .midnight ? Color.white.opacity(0.08) : Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(isCurrentWeek)
        }
    }

    private var isCurrentWeek: Bool {
        Calendar.current.isDate(selectedWeekStart, inSameDayAs: Self.mondayWeekStart(for: Date()))
    }

    private var earliestLoggedWeekStart: Date? {
        guard let first = allEntriesAsc.first, let ts = first.timestamp else { return nil }
        return Self.mondayWeekStart(for: ts)
    }

    private var isEarliestWeek: Bool {
        guard let earliest = earliestLoggedWeekStart else { return true }
        return Calendar.current.isDate(selectedWeekStart, inSameDayAs: earliest)
    }

    private var weekHeading: String {
        isCurrentWeek ? "This Week" : weekRangeString
    }

    private var weekSubheading: String {
        isCurrentWeek ? weekRangeString : "Tap to return to this week"
    }

    private var weekRangeString: String {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
        let f = DateFormatter.monthDay
        return "\(f.string(from: selectedWeekStart)) – \(f.string(from: end))"
    }

    private func changeWeek(by delta: Int) {
        guard let target = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: selectedWeekStart) else { return }
        changeWeek(to: target)
    }

    private func changeWeek(to date: Date) {
        let target = Self.mondayWeekStart(for: date)
        let currentWeekStart = Self.mondayWeekStart(for: Date())
        var clamped = target > currentWeekStart ? currentWeekStart : target
        if let earliest = earliestLoggedWeekStart, clamped < earliest {
            clamped = earliest
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedWeekStart = clamped
        }
    }

    // MARK: - Calendar helpers

    /// Start of week (Monday 00:00) for a given date — independent of the user's
    /// locale-default first weekday. Always Monday so the column layout
    /// (Mon..Sun) and the predicate window stay in sync.
    static func mondayWeekStart(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? Calendar.current.startOfDay(for: date)
    }

    /// Monday of the week immediately before `weekStart` — used by the
    /// week-over-week comparison strip.
    static func priorWeekStart(for weekStart: Date) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
    }

    static func predicate(for weekStart: Date) -> NSPredicate {
        let weekEnd = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
        return NSPredicate(format: "timestamp >= %@ AND timestamp < %@ AND isSoftDeleted == NO",
                           weekStart as NSDate, weekEnd as NSDate)
    }
}
