import Foundation
import os

/// Single home for `os.Logger` instances, one per subsystem-relevant category.
///
/// Use the categorized loggers (`Log.network`, `Log.voice`, etc.) instead of
/// raw `print` calls — `os.Logger` writes through the unified logging system,
/// so messages show up in Console.app with the right subsystem/category and
/// can be filtered, persisted, and stripped from Release builds via the
/// `.debug` privacy level when needed.
///
/// Adding a category? Add it here, not via ad-hoc `Logger(...)` calls — the
/// subsystem string and the convention of "one logger per concern" both
/// benefit from a single home.
enum Log {
    /// Subsystem matches the app's bundle identifier so Console.app's
    /// "Subsystem" filter zeroes in on this app's logs without picking up
    /// noise from frameworks the app links against.
    private static let subsystem = "com.glycotrack.app"

    /// App-wide events with no sharper category — startup, lifecycle.
    static let app = Logger(subsystem: subsystem, category: "app")
    /// HTTP requests to Anthropic + their failures.
    static let network = Logger(subsystem: subsystem, category: "network")
    /// Core Data setup, seeding, save errors.
    static let coreData = Logger(subsystem: subsystem, category: "coreData")
    /// Microphone session, SFSpeechRecognizer, transcript hand-off.
    static let voice = Logger(subsystem: subsystem, category: "voice")
    /// UNUserNotificationCenter authorization + scheduling.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    /// Summary generation pipeline (streaming Claude responses).
    static let summary = Logger(subsystem: subsystem, category: "summary")
}
