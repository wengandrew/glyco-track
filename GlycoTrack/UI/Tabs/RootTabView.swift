import SwiftUI
import CoreData

struct RootTabView: View {
    @Environment(\.managedObjectContext) private var context

    // Hoisted from HomeTabView so the floating tab-bar Record button can drive
    // recording from any tab. HomeTabView still observes both objects for its
    // transcript / progress / error UI.
    @StateObject private var voiceCapture = VoiceCapture()
    @StateObject private var logProcessor = FoodLogProcessor()

    @State private var selectedTab: Tab = .today
    @State private var homeSelectedDate: Date = Calendar.current.startOfDay(for: Date())

    enum Tab: Int, CaseIterable, Identifiable {
        case today, week, month, log
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .today: return "Today"
            case .week:  return "Week"
            case .month: return "Month"
            case .log:   return "Log"
            }
        }

        var systemImage: String {
            switch self {
            case .today: return "house.fill"
            case .week:  return "calendar.badge.clock"
            case .month: return "calendar"
            case .log:   return "list.bullet"
            }
        }
    }

    private let theme: AppTheme = .organic

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    // Reserve space so tab content (e.g. ScrollView contents)
                    // isn't hidden behind the floating tab bar.
                    Color.clear.frame(height: theme.tabBarUsesLabels ? 88 : 76)
                }

            VStack(spacing: 8) {
                ListeningPill(voiceCapture: voiceCapture, logProcessor: logProcessor) {
                    await logProcessor.retry()
                }
                customTabBar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.appTheme, theme)
        .preferredColorScheme(theme.preferredColorScheme)
        .onOpenURL { url in
            if url.scheme == "glycotrack" && url.host == "record" {
                selectedTab = .today
                Task { await toggleRecording() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .today:
            HomeTabView(voiceCapture: voiceCapture, logProcessor: logProcessor, selectedDate: $homeSelectedDate)
        case .week:
            WeekTabView(onDayTapped: { date in
                homeSelectedDate = Calendar.current.startOfDay(for: date)
                withAnimation { selectedTab = .today }
            })
        case .month:
            MonthTabView()
        case .log:
            LogTabView()
        }
    }

    // MARK: - Custom tab bar

    private var customTabBar: some View {
        HStack(spacing: 12) {
            // Left pill: tab buttons
            HStack(spacing: theme.tabBarUsesLabels ? 0 : 4) {
                ForEach(Tab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, theme.tabBarUsesLabels ? 10 : 8)
            .background(theme.tabBarMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)

            // Right pill: record button
            ZStack {
                Circle()
                    .fill(theme.tabBarMaterial)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)

                CompactRecordButton(isRecording: voiceCapture.isRecording, theme: theme) {
                    selectedTab = .today
                    Task { await toggleRecording() }
                }
            }
            .frame(width: 64, height: 64)
        }
    }

    private func tabButton(for tab: Tab) -> some View {
        let isSelected = (tab == selectedTab)
        return Button {
            if selectedTab != tab {
                selectedTab = tab
            }
        } label: {
            if theme.tabBarUsesLabels {
                VStack(spacing: 3) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                    Text(tab.title)
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                }
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 56, height: 44)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(theme.primaryAccent)
                                .shadow(color: theme.primaryAccent.opacity(0.30), radius: 4, x: 0, y: 2)
                        } else {
                            Capsule().fill(Color.clear)
                        }
                    }
                )
                .accessibilityLabel(tab.title)
            } else {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        Group {
                            if isSelected {
                                Circle()
                                    .fill(theme.primaryAccent)
                                    .shadow(color: theme.primaryAccent.opacity(0.30), radius: 3, x: 0, y: 2)
                            } else {
                                Circle().fill(Color.clear)
                            }
                        }
                    )
                    .accessibilityLabel(tab.title)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSelected)
    }

    // MARK: - Recording

    private func toggleRecording() async {
        if voiceCapture.isRecording {
            voiceCapture.stopRecording()
        } else {
            // Reset stale transcript from a prior recording so the listening
            // pill doesn't flash yesterday's text. Also wipe any prior error
            // so the pill doesn't keep displaying it across sessions.
            voiceCapture.transcript = ""
            logProcessor.lastError = nil

            voiceCapture.onTranscriptFinalized = { transcript in
                Task { @MainActor in
                    await logProcessor.process(transcript: transcript, context: context)
                    updateWidgetData()
                    // Once the entry has been committed (or processing
                    // failed and the error is surfaced), clear the
                    // transcript so the pill collapses back to nothing
                    // for the next recording.
                    voiceCapture.transcript = ""
                }
            }
            do {
                try await voiceCapture.startRecording()
            } catch {
                // The user-facing message surfaces via voiceCapture.error
                // (driven by VoiceCapture's own state); diagnostic detail
                // goes to Console.app for the developer.
                Log.voice.error("startRecording failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func updateWidgetData() {
        let defaults = UserDefaults(suiteName: "group.com.glycotrack.shared")
        let repo = FoodLogRepository(context: context)
        defaults?.set(repo.dailyGL(for: Date()), forKey: "todayGL")
        defaults?.set(repo.countToday(), forKey: "todayEntryCount")
    }
}

// ListeningPill lives in UI/Components/ListeningPill.swift.
// CompactRecordButton lives in UI/Components/CompactRecordButton.swift.
