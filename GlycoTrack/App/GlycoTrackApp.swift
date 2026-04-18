import SwiftUI

@main
struct GlycoTrackApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, persistenceController.context)
                .onAppear {
                    Task {
                        await requestNotificationPermission()
                    }
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
