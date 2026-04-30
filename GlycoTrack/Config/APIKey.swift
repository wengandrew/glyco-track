import Foundation

/// Single typed accessor for the Claude API key.
///
/// The key is injected via `GlycoTrack.xcconfig` (which `#include`s the
/// gitignored `GlycoTrack.local.xcconfig`) and reaches the running app via
/// `Info.plist` -> `Bundle.main.infoDictionary["CLAUDE_API_KEY"]`. Looking it
/// up in three different views (FoodLogProcessor, LogTabView, SummaryTabView)
/// duplicated the cast and made it easy for one site to drift (different
/// fallback, missing trim, etc.). Read it through here instead.
enum APIKey {
    /// Raw key as configured. Whitespace is trimmed because the xcconfig
    /// pipeline preserves any trailing newline. Empty string means missing.
    static var claude: String {
        BundleConfig.string("CLAUDE_API_KEY", trimmed: true)
    }

    /// True when a non-empty key is configured. Use this to gate Claude-backed
    /// features so we don't ship requests with an empty `x-api-key` header.
    static var hasClaude: Bool { !claude.isEmpty }
}
