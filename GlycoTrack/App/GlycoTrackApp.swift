import SwiftUI

@main
struct GlycoTrackApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // Separate @State drives the sheet so SwiftUI has a writable Binding and
    // can manage presentation lifecycle. Synced from hasCompletedOnboarding via
    // onAppear and onChange below.
    @State private var showOnboarding = false
    @State private var showSeedingOverlay = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environment(\.managedObjectContext, persistenceController.context)
                    .onAppear {
                        Task { await requestNotificationPermission() }
                    }

                if showSeedingOverlay {
                    SeedingOverlayView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.4), value: showSeedingOverlay)
            .onAppear {
                showOnboarding = !hasCompletedOnboarding
                // Guard against the notification arriving before subscription —
                // re-read the flag synchronously on appear.
                showSeedingOverlay = persistenceController.isSeeding
            }
            .onReceive(NotificationCenter.default.publisher(for: .didFinishSeeding)) { _ in
                showSeedingOverlay = false
            }
            .onChange(of: hasCompletedOnboarding) { completed in
                if completed { showOnboarding = false }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView()
                    .interactiveDismissDisabled()
            }
        }
    }

    private func requestNotificationPermission() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        if granted {
            NotificationManager.shared.scheduleDailyCheck()
        }
    }
}

private struct SeedingOverlayView: View {
    @State private var dotCount = 1
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.accentColor)

                VStack(spacing: 6) {
                    Text("Loading nutritional database\(String(repeating: ".", count: dotCount))")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .animation(nil, value: dotCount)

                    Text("This only happens once.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onReceive(timer) { _ in
            dotCount = dotCount % 3 + 1
        }
    }
}

extension Notification.Name {
    static let didFinishSeeding = Notification.Name("GlycoTrackDidFinishSeeding")
}
