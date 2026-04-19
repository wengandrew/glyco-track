import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let dailyCheckIdentifier = "com.glycotrack.daily-check"

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleDailyCheck() {
        center.removePendingNotificationRequests(withIdentifiers: [dailyCheckIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "How's your eating going today?"
        content.body = "Don't forget to log your meals. Tap to record what you've had."
        content.sound = .default

        var components = DateComponents()
        components.hour = 20
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyCheckIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    /// Cancel today's 8 PM notification once the user has logged ≥3 meals.
    func cancelTodayIfSufficientlyLogged(entryCount: Int) {
        guard entryCount >= 3 else { return }
        center.removePendingNotificationRequests(withIdentifiers: [dailyCheckIdentifier])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Deep link to recording screen via URL scheme
        if let url = URL(string: "glycotrack://record") {
            UIApplication.shared.open(url)
        }
        completionHandler()
    }
}
