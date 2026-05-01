import SwiftUI
import CoreData

struct HomeTabView: View {
    @Environment(\.managedObjectContext) private var context

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
    @State private var selectedEntry: FoodLogEntry?
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
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    let entryArray = Array(entries)
                    let totalGL = entryArray.reduce(0) { $0 + $1.computedGL }

                    // ── GL SECTION ───────────────────────────────
                    MetricSection(
                        title: "Glycemic Load",
                        subtitle: "Carbs · diabetes risk",
                        accent: .glAccent,
                        icon: "drop.fill",
                        trailing: { GLStatusLabel(total: totalGL, budget: glBudget) }
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
                        subtitle: "Fats & fiber · heart risk",
                        accent: .clAccent,
                        icon: "heart.fill"
                    ) {
                        BalanceScaleView(entries: entryArray, dateKey: selectedDate)
                    }
                    .contentShape(Rectangle())
                    .gesture(horizontalSwipe)

                    // ── CL SECTION (Waterline — second lens) ────
                    // Same data, different reading: floats vs sinks. Scrolled
                    // to deliberately so the primary Balance view is the
                    // headline; users who want the alternate view scroll for it.
                    MetricSection(
                        title: "Waterline",
                        subtitle: "Same data, different reading",
                        accent: .clAccent,
                        icon: "drop.fill"
                    ) {
                        WaterlineView(entries: entryArray, dateKey: selectedDate)
                    }
                    .contentShape(Rectangle())
                    .gesture(horizontalSwipe)

                    // ── COMBINED: GL × CL Quadrant (embedded) ────
                    QuadrantPlotSection(
                        entries: entryArray,
                        onTap: { selectedEntry = $0 }
                    )

                    if !entryArray.isEmpty {
                        TodayEntrySummary(entries: entryArray)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle(titleForNav)
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
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailSheet(entry: entry)
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
            Button {
                changeDate(byDays: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isEarliest ? .secondary : .accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(isEarliest)

            VStack(spacing: 0) {
                Text(dateHeading)
                    .font(.subheadline.weight(.semibold))
                Text(dateSubheading)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                changeDate(to: Calendar.current.startOfDay(for: Date()))
            }

            Button {
                changeDate(byDays: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isToday ? .secondary : .accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(isToday)
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

    private var titleForNav: String {
        isToday ? "Today" : DateFormatter.short.string(from: selectedDate)
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
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: accent.opacity(0.35), radius: 6, x: 0, y: 3)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, accent.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text(subtitle.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
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
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(accent.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
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

extension Color {
    /// Shared GL accent: deep blue (carbs / water drop).
    static let glAccent = Color(red: 0.16, green: 0.42, blue: 0.82)
    /// Shared CL accent: crimson (heart).
    static let clAccent = Color(red: 0.83, green: 0.22, blue: 0.35)
}

// MARK: - Today summary

struct TodayEntrySummary: View {
    let entries: [FoodLogEntry]

    @AppStorage(AppSettings.dailyGLBudgetKey) private var glBudget: Double = AppSettings.defaultDailyGLBudget

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    var body: some View {
        HStack {
            StatChip(label: "Total GL", value: String(format: "%.1f", totalGL),
                     color: glGradientColor(fraction: totalGL / glBudget))
            StatChip(label: "Net CL", value: String(format: "%+.2f", netCL),
                     color: netCL < 0 ? .green : .red)
            StatChip(label: "Foods", value: "\(entries.count)", color: .accentColor)
        }
    }
}

struct StatChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(color.opacity(0.18), lineWidth: 0.8)
                )
        )
    }
}

// Shared `DateFormatter.short` / `.weekdayMonthDay` live in
// `UI/Theme/DateFormatters.swift`.
