import Foundation

enum AppInfo {
    static var version: String {
        BundleConfig.string("CFBundleShortVersionString", default: "unknown")
    }
    static var build: String {
        BundleConfig.string("CFBundleVersion", default: "unknown")
    }
    static var gitBranch: String { BuildInfo.gitBranch }
    static var gitCommit: String { BuildInfo.gitCommit }
    static var buildTimestamp: String { BuildInfo.buildTimestamp }
}
