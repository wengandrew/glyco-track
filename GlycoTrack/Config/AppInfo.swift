import Foundation

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
    static var gitBranch: String { BuildInfo.gitBranch }
    static var gitCommit: String { BuildInfo.gitCommit }
    static var buildTimestamp: String { BuildInfo.buildTimestamp }
}
