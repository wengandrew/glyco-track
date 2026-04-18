// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlycoTrackCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "GIEngineCore", targets: ["GIEngineCore"]),
        .library(name: "CLEngineCore", targets: ["CLEngineCore"]),
        .library(name: "TranscriptParserCore", targets: ["TranscriptParserCore"]),
    ],
    targets: [
        .target(
            name: "GIEngineCore",
            path: "Sources/GIEngineCore"
        ),
        .target(
            name: "CLEngineCore",
            path: "Sources/CLEngineCore"
        ),
        .target(
            name: "TranscriptParserCore",
            path: "Sources/TranscriptParserCore"
        ),
        .testTarget(
            name: "GIEngineCoreTests",
            dependencies: ["GIEngineCore"],
            path: "Tests/GIEngineCoreTests"
        ),
        .testTarget(
            name: "CLEngineCoreTests",
            dependencies: ["CLEngineCore"],
            path: "Tests/CLEngineCoreTests"
        ),
    ]
)
