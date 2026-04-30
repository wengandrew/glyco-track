import Foundation

/// Single typed accessor for `Info.plist` values.
///
/// `Bundle.main.infoDictionary?["…"] as? String ?? "…"` was repeated in
/// `APIKey` (CLAUDE_API_KEY) and `AppInfo` (CFBundleShortVersionString,
/// CFBundleVersion) — three sites, three slightly different fallback
/// strings, each free to drift. Read everything through here so the cast,
/// the fallback, and the optional trimming live in one place.
///
/// Adding a new key? Add a static accessor below; don't reach into
/// `Bundle.main.infoDictionary` from anywhere else. The PLAN notes (C.15)
/// that any new runtime flag should follow this pattern.
enum BundleConfig {
    /// Reads a String value from the main bundle's `Info.plist`. Returns the
    /// supplied `default` when the key is missing or not a string.
    /// Whitespace is *not* trimmed by default — see `string(_:trimmed:default:)`
    /// for keys whose pipeline preserves trailing whitespace (e.g. xcconfig).
    static func string(_ key: String, default fallback: String = "") -> String {
        Bundle.main.infoDictionary?[key] as? String ?? fallback
    }

    /// Same as `string(_:default:)` but trims leading/trailing whitespace and
    /// newlines. Use this for values injected via xcconfig — the build pipeline
    /// can preserve a trailing newline that a runtime comparison won't.
    static func string(_ key: String, trimmed: Bool, default fallback: String = "") -> String {
        let raw = string(key, default: fallback)
        return trimmed ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : raw
    }
}
