# GlycoTrack

Voice-first food logging app for iOS. Tracks Glycemic Load (GL) and Cholesterol Load (CL) simultaneously to help manage diabetes and heart disease risk.

## Setup

### Requirements
- Xcode 26+ (on macOS 26+) — earlier Xcode versions are not supported (see [Xcode 26 notes](#xcode-26-notes))
- iOS 16+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Claude API key from [console.anthropic.com](https://console.anthropic.com)
- Apple Developer account (free or paid) for device testing

### 1. Create your credentials file

`GlycoTrack/Config/GlycoTrack.xcconfig` is a committed stub — xcodegen always finds it. Put your real values in a local override file (gitignored):

```bash
cp GlycoTrack/Config/GlycoTrack.xcconfig.example GlycoTrack/Config/GlycoTrack.local.xcconfig
```

Edit `GlycoTrack/Config/GlycoTrack.local.xcconfig` and fill in:

```
CLAUDE_API_KEY = sk-ant-...        # your Anthropic API key
DEVELOPMENT_TEAM = XXXXXXXXXX      # your 10-character Apple Team ID
```

Your Team ID is in [developer.apple.com](https://developer.apple.com) → Account → Membership, or visible in Xcode → Settings → Accounts after signing in.

`GlycoTrack.local.xcconfig` is gitignored and never committed.

### 2. Generate and open the Xcode project

```bash
brew install xcodegen   # first time only
xcodegen generate
open GlycoTrack.xcodeproj
```

### 3. Build and run on device

In Xcode:
1. Connect your iPhone via USB (trust the computer if prompted)
2. Go to **Settings → General → VPN & Device Management** on iPhone and trust the developer certificate
3. Select your device in the toolbar (not a simulator)
4. Press **⌘R** to build and run

### Personal team limitations (free Apple ID)

A free Apple ID account can sideload the app but with these restrictions:

| Feature | Status |
|---------|--------|
| Widget GL data | Empty — App Groups entitlement removed (requires paid account) |
| Voice logging | Works — on-device `SFSpeechRecognizer` doesn't need entitlement on iOS 26 |
| Certificate | Expires after 7 days; reinstall weekly |

To restore full functionality (widget data, server-side speech), enroll in the Apple Developer Program and re-add the `com.apple.security.application-groups` entitlement.

## Xcode 26 notes

Xcode 26 / macOS 26 has a CDMFoundation bug that crashes on any `.xcdatamodel` file. GlycoTrack works around this by defining the Core Data schema programmatically in [`GlycoTrack/Models/GlycoTrackManagedObjectModel.swift`](GlycoTrack/Models/GlycoTrackManagedObjectModel.swift) — there is no `.xcdatamodeld` file in the repo.

Several SwiftUI APIs also changed in Xcode 26:
- `navigationTitle(_:displayedComponents:)` was removed — replaced with `navigationTitle(date.formatted(...))`
- `.fill().stroke()` chain requires iOS 17 — replaced with `.fill().overlay(stroke)`

## Architecture

See [DESIGN.md](DESIGN.md) for the full product design document.

### Core Modules (testable on Linux via `swift test`)

| Module | Path | Purpose |
|--------|------|---------|
| GIEngineCore | `Sources/GIEngineCore/` | GL calculation + GI database lookup |
| CLEngineCore | `Sources/CLEngineCore/` | CL calculation (signed) |
| TranscriptParserCore | `Sources/TranscriptParserCore/` | Claude API food extraction |

### iOS App Modules

| Module | Path | Purpose |
|--------|------|---------|
| LocalStorage | `GlycoTrack/Modules/LocalStorage/` | Core Data CRUD |
| VoiceCapture | `GlycoTrack/Modules/VoiceCapture/` | Speech recognition |
| ClaudeAPI | `GlycoTrack/Modules/ClaudeAPI/` | Anthropic API wrapper (extracted in PR #39) |
| Logging | `GlycoTrack/Modules/Logging/` | Categorized `os.Logger` instances |
| Settings | `GlycoTrack/Modules/Settings/` | `AppSettings` keys + defaults (e.g. user-editable daily GL budget) |
| Motion | `GlycoTrack/Modules/Motion/` | `MotionGravityController` — accelerometer-driven gravity for SpriteKit scenes |
| NotificationManager | `GlycoTrack/Modules/NotificationManager/` | End-of-day push |

## Data Flow

1. Widget mic button → `VoiceCapture` → transcript
2. `TranscriptParser` (Claude API) → JSON food array
3. `GIEngine` + `CLEngine` → GL + CL values
4. Core Data → persisted `FoodLogEntry` records
5. SwiftUI views → render from Core Data queries

## Running Tests

```bash
swift test                                          # SPM core targets (engines + parser)
xcodebuild test -project GlycoTrack.xcodeproj \
  -scheme GlycoTrack \
  -destination 'platform=iOS Simulator,name=iPhone 15'   # iOS-only suites (matcher regression tests)
```

Test coverage:
- `Tests/GIEngineCoreTests/` — GL calculations against published nutritional tables.
- `Tests/CLEngineCoreTests/` — CL calculations + Mediterranean-vs-American-fast-food dietary-pattern validation.
- `Tests/TranscriptParserCoreTests/` — Claude API parser happy / malformed / preamble paths + decomposition contract + HEADLINE-CARB RULE regression.
- `Tests/MatchingTests/` — iOS XCTest bundle running against a real in-memory Core Data store. Pins matcher regressions (e.g. `bread →∅`, `chicken →∅`, `grilled chicken ↛ fried chicken`).

CI runs all of the above on every PR via `.github/workflows/ci.yml`, plus SwiftLint.
