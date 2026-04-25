import SwiftUI
import CoreData

struct HomeTabView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var voiceCapture = VoiceCapture()
    @StateObject private var logProcessor: FoodLogProcessor

    @FetchRequest private var entries: FetchedResults<FoodLogEntry>

    // Earliest logged entry ever — used to clamp backward date navigation.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == NO"),
        animation: .default
    )
    private var allEntriesAsc: FetchedResults<FoodLogEntry>

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var clPrototype: CLPrototype = .tugOfWar
    @State private var selectedEntry: FoodLogEntry?

    init() {
        _logProcessor = StateObject(wrappedValue: FoodLogProcessor())
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
                    recordingSection

                    let entryArray = Array(entries)
                    let totalGL = entryArray.reduce(0) { $0 + $1.computedGL }

                    // ── GL SECTION ───────────────────────────────
                    MetricSection(
                        title: "Glycemic Load",
                        subtitle: "Carbs · diabetes risk",
                        accent: .glAccent,
                        icon: "drop.fill",
                        trailing: { GLStatusLabel(total: totalGL, budget: dailyGLBudgetUI) }
                    ) {
                        dateNavigator
                        PhysicsBucketView(
                            entries: entryArray,
                            dateKey: selectedDate
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(horizontalSwipe)

                    // ── CL SECTION ───────────────────────────────
                    MetricSection(
                        title: "Cholesterol Load",
                        subtitle: "Fats & fiber · heart risk",
                        accent: .clAccent,
                        icon: "heart.fill"
                    ) {
                        Picker("CL view", selection: $clPrototype) {
                            ForEach(CLPrototype.allCases) { p in
                                Text(p.shortLabel).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch clPrototype {
                        case .tugOfWar:
                            TugOfWarBarView(entries: entryArray)
                        case .waterline:
                            WaterlineView(entries: entryArray, dateKey: selectedDate)
                        case .balance:
                            BalanceScaleView(entries: entryArray, dateKey: selectedDate)
                        }
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
            .sheet(item: $selectedEntry) { entry in
                FoodEntryDetailSheet(entry: entry)
            }
        }
        .onOpenURL { url in
            if url.scheme == "glycotrack" && url.host == "record" {
                // Logging a new item should snap the view back to today.
                changeDate(to: Calendar.current.startOfDay(for: Date()))
                Task { await toggleRecording() }
            }
        }
        .onChange(of: selectedDate) { newDate in
            entries.nsPredicate = Self.predicate(for: newDate)
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

    // MARK: - Recording

    private var recordingSection: some View {
        VStack(spacing: 8) {
            RecordButton(isRecording: voiceCapture.isRecording) {
                // Ensure we're back on today when logging a new entry.
                if !isToday {
                    changeDate(to: Calendar.current.startOfDay(for: Date()))
                }
                Task { await toggleRecording() }
            }

            if voiceCapture.isRecording {
                Text("Listening...")
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text("Tap to log food by voice")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if voiceCapture.isRecording || !voiceCapture.transcript.isEmpty {
                Text(voiceCapture.transcript)
                    .font(.caption)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            if logProcessor.isProcessing {
                HStack {
                    ProgressView()
                    Text("Processing your food log…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if logProcessor.lastError != nil {
                Text("Could not process: \(logProcessor.lastError!)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }

    private func toggleRecording() async {
        if voiceCapture.isRecording {
            voiceCapture.stopRecording()
        } else {
            voiceCapture.onTranscriptFinalized = { transcript in
                Task {
                    await logProcessor.process(transcript: transcript, context: context)
                    updateWidgetData()
                }
            }
            do {
                try await voiceCapture.startRecording()
            } catch {
                // Error shown via voiceCapture.error
            }
        }
    }

    private func updateWidgetData() {
        let defaults = UserDefaults(suiteName: "group.com.glycotrack.shared")
        let repo = FoodLogRepository(context: context)
        defaults?.set(repo.dailyGL(for: Date()), forKey: "todayGL")
        defaults?.set(repo.countToday(), forKey: "todayEntryCount")
    }

    // MARK: - Predicate

    static func predicate(for date: Date) -> NSPredicate {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return NSPredicate(format: "timestamp >= %@ AND timestamp < %@ AND isSoftDeleted == NO",
                           start as NSDate, end as NSDate)
    }
}

// MARK: - Prototype enums

enum CLPrototype: String, CaseIterable, Identifiable {
    case tugOfWar, waterline, balance
    var id: String { rawValue }
    var shortLabel: String {
        switch self {
        case .tugOfWar:  return "Tug of War"
        case .waterline: return "Waterline"
        case .balance:   return "Balance"
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal)

            content()
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accent.opacity(0.04))
                .padding(.horizontal, 8)
        )
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

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    var body: some View {
        HStack {
            StatChip(label: "Total GL", value: String(format: "%.1f", totalGL),
                     color: glGradientColor(fraction: totalGL / dailyGLBudgetUI))
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
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Date formatters

private extension DateFormatter {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
    static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}
