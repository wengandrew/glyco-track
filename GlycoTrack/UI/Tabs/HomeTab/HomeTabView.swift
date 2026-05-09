import SwiftUI
import CoreData

struct HomeTabView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.appTheme) private var theme

    // Owned by RootTabView so the floating tab-bar Record button can drive
    // recording. We observe both here for transcript / progress / error UI.
    @ObservedObject var voiceCapture: VoiceCapture
    @ObservedObject var logProcessor: FoodLogProcessor

    @FetchRequest private var entries: FetchedResults<FoodLogEntry>

    // Earliest logged entry ever — used to clamp backward date navigation.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO"),
        animation: .default
    )
    private var allEntriesAsc: FetchedResults<FoodLogEntry>

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showMore: Bool = false

    /// Reactive binding to the user's GL budget so the bucket / status chip
    /// re-render when the value changes in Settings.
    @AppStorage(AppSettings.dailyGLBudgetKey) private var glBudget: Double = AppSettings.defaultDailyGLBudget

    init(voiceCapture: VoiceCapture, logProcessor: FoodLogProcessor) {
        self.voiceCapture = voiceCapture
        self.logProcessor = logProcessor
        _entries = FetchRequest<FoodLogEntry>(
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
            predicate: Self.predicate(for: Date()),
            animation: .default
        )
    }

    var body: some View {
        let entryArray = Array(entries)
        let totalGL = entryArray.reduce(0) { $0 + $1.computedGL }

        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    // ── GL SECTION ───────────────────────────────
                    MetricSection(
                        title: "Glycemic Load",
                        subtitle: "Carbs \u{00B7} diabetes risk",
                        accent: theme.glAccent,
                        icon: "drop.fill",
                        trailing: {
                            GLStatusLabel(total: totalGL, budget: glBudget)
                        }
                    ) {
                        dateNavigator
                        PhysicsBucketView(
                            entries: entryArray,
                            dateKey: selectedDate
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(horizontalSwipe)

                    // ── CL SECTION (Balance — primary lens) ─────
                    MetricSection(
                        title: "Cholesterol Load",
                        subtitle: "Fats & fiber \u{00B7} heart risk",
                        accent: theme.clAccent,
                        icon: "heart.fill"
                    ) {
                        BalanceScaleView(entries: entryArray, dateKey: selectedDate)
                    }
                    .contentShape(Rectangle())
                    .gesture(horizontalSwipe)

                }
                .padding(.bottom, 24)
            }
            .background(theme.pageBackground.ignoresSafeArea())
            .navigationTitle(theme.greeting(for: Date()))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showMore = true
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings, About, Debug")
                    }
                }
            }
            .sheet(isPresented: $showMore) {
                MoreSheet()
            }
        }
        .onChange(of: selectedDate) { newDate in
            entries.nsPredicate = Self.predicate(for: newDate)
        }
        .onChange(of: voiceCapture.isRecording) { recording in
            // When the floating tab-bar Record button starts a new recording,
            // snap the visualizations back to today.
            if recording && !isToday {
                changeDate(to: Calendar.current.startOfDay(for: Date()))
            }
        }
    }

    // MARK: - Date navigation

    private var dateNavigator: some View {
        HStack(spacing: 16) {
            if !isEarliest {
                Button {
                    changeDate(byDays: -1)
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

            VStack(spacing: 0) {
                Text(dateHeading)
                    .font(.system(.subheadline, design: theme.fontDesign, weight: .semibold))
                Text(dateSubheading)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                changeDate(to: Calendar.current.startOfDay(for: Date()))
            }

            if !isToday {
                Button {
                    changeDate(byDays: 1)
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
    }

    private var horizontalSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Only trigger on decisive horizontal motion.
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                if dx < 0 {
                    // Left swipe → next day (forward in time).
                    changeDate(byDays: 1)
                } else {
                    // Right swipe → previous day.
                    changeDate(byDays: -1)
                }
            }
    }

    private var isToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: Date())
    }

    /// Earliest day that has any logged entry — nil until the first log.
    private var earliestLoggedDay: Date? {
        guard let first = allEntriesAsc.first, let ts = first.timestamp else { return nil }
        return Calendar.current.startOfDay(for: ts)
    }

    private var isEarliest: Bool {
        guard let earliest = earliestLoggedDay else { return true }
        return Calendar.current.isDate(selectedDate, inSameDayAs: earliest)
    }

    private var dateHeading: String {
        isToday ? "Today" : DateFormatter.weekdayMonthDay.string(from: selectedDate)
    }

    private var dateSubheading: String {
        isToday ? DateFormatter.weekdayMonthDay.string(from: selectedDate) : "Tap to return to today"
    }

    private func changeDate(byDays delta: Int) {
        guard let target = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        changeDate(to: target)
    }

    private func changeDate(to date: Date) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let today = Calendar.current.startOfDay(for: Date())
        // Don't allow navigating into the future.
        var clamped = startOfDay > today ? today : startOfDay
        // Don't allow navigating before the first-ever logged day — there's
        // nothing to show and the empty-day display is misleading.
        if let earliest = earliestLoggedDay, clamped < earliest {
            clamped = earliest
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = clamped
        }
    }

    // MARK: - Predicate

    static func predicate(for date: Date) -> NSPredicate {
        let start = Calendar.current.startOfDay(for: date)
        // `Calendar.date(byAdding:.day, value: 1, to:)` returns nil only for
        // pathological calendars; fall back to a 24-hour offset so the predicate
        // is always well-formed.
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return NSPredicate(format: "timestamp >= %@ AND timestamp < %@ AND isSoftDeleted == NO",
                           start as NSDate, end as NSDate)
    }
}

// MARK: - Section chrome

struct MetricSection<Content: View, Trailing: View>: View {
    @Environment(\.appTheme) private var theme

    let title: String
    let subtitle: String
    let accent: Color
    let icon: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 36, height: 36)
                        .shadow(color: accent.opacity(0.25), radius: 4, x: 0, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.title2, design: theme.fontDesign, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subtitle.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .tracking(0.6)
                        .foregroundColor(.secondary)
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            content()
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .fill(theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                            .fill(theme.surfaceTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                            .stroke(accent.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(
                        color: Color.black.opacity(theme.cardShadowOpacity),
                        radius: theme.cardShadowRadius,
                        x: 0,
                        y: 6
                    )
            }
        )
        .padding(.horizontal, 12)
    }
}

extension MetricSection where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String,
        accent: Color,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.icon = icon
        self.trailing = { EmptyView() }
        self.content = content
    }
}


// Shared `DateFormatter.short` / `.weekdayMonthDay` live in
// `UI/Theme/DateFormatters.swift`.
