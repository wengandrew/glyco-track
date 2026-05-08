import SwiftUI
import CoreData

@main
struct GlycoTrackApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage(AppSettings.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false

    /// True only on first launch while the DB seed is running. Set synchronously
    /// from `persistenceController.isSeedingOnFirstLaunch` in `.onAppear` (by
    /// which point the `.onReceive` subscription is live), cleared by the
    /// `glycoTrackSeedingDidComplete` notification from PersistenceController.
    @State private var isSeedingDatabase = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environment(\.managedObjectContext, persistenceController.context)

                if isSeedingDatabase {
                    seedingOverlay
                }
            }
            .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
                OnboardingView()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .glycoTrackSeedingDidComplete)
            ) { _ in
                withAnimation { isSeedingDatabase = false }
            }
            .onAppear {
                // Read synchronously — isSeedingOnFirstLaunch is set before the
                // background task is spawned, so no race with the notification.
                isSeedingDatabase = persistenceController.isSeedingOnFirstLaunch
            }
            .task {
                // Delay notification permission until after onboarding so the
                // system dialog doesn't interrupt the welcome screen.
                guard hasCompletedOnboarding else { return }
                await requestNotificationPermission()
            }
            .onChange(of: hasCompletedOnboarding) { completed in
                guard completed else { return }
                Task { await requestNotificationPermission() }
            }
        }
    }

    // MARK: - Seeding overlay

    private var seedingOverlay: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                Text("Loading nutritional database\u{2026}")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Permissions

    private func requestNotificationPermission() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        if granted {
            NotificationManager.shared.scheduleDailyCheck()
        }
    }
}
