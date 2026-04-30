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

    enum Tab: Int, CaseIterable, Identifiable {
        case today, week, month, log, summary, about, debug
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .today:   return "Today"
            case .week:    return "Week"
            case .month:   return "Month"
            case .log:     return "Log"
            case .summary: return "Summary"
            case .about:   return "About"
            case .debug:   return "Debug"
            }
        }

        var systemImage: String {
            switch self {
            case .today:   return "house.fill"
            case .week:    return "calendar.badge.clock"
            case .month:   return "calendar"
            case .log:     return "list.bullet"
            case .summary: return "text.magnifyingglass"
            case .about:   return "info.circle"
            case .debug:   return "wrench.and.screwdriver"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    // Reserve space so tab content (e.g. ScrollView contents)
                    // isn't hidden behind the floating tab bar.
                    Color.clear.frame(height: 76)
                }

            customTabBar
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
            HomeTabView(voiceCapture: voiceCapture, logProcessor: logProcessor)
        case .week:
            WeekTabView()
        case .month:
            MonthTabView()
        case .log:
            LogTabView()
        case .summary:
            SummaryTabView()
        case .about:
            AboutTabView()
        case .debug:
            DebugTabView()
        }
    }

    // MARK: - Custom tab bar

    private var customTabBar: some View {
        HStack(spacing: 10) {
            // Left pill: tab buttons
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            // Right pill: record button
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))

                CompactRecordButton(isRecording: voiceCapture.isRecording) {
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
            Image(systemName: tab.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .accessibilityLabel(tab.title)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recording

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

/// Smaller variant of `RecordButton` sized for the floating tab bar.
private struct CompactRecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 60, height: 60)
                        .scaleEffect(pulse ? 1.25 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                }

                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 48, height: 48)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { recording in
            pulse = recording
        }
    }
}
