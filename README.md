# GlycoTrack

Voice-first food logging app for iOS. Tracks Glycemic Load (GL) and Cholesterol Load (CL) simultaneously to help manage diabetes and heart disease risk.

## Setup

### Requirements
- Xcode 15+ (on macOS)
- iOS 16+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Claude API key from [console.anthropic.com](https://console.anthropic.com)
- Apple Developer account (free or paid) for device testing

### 1. Create your credentials file

```bash
cp GlycoTrack/Config/GlycoTrack.xcconfig.example GlycoTrack/Config/GlycoTrack.xcconfig
```

Edit `GlycoTrack/Config/GlycoTrack.xcconfig` and fill in:

```
CLAUDE_API_KEY = sk-ant-...        # your Anthropic API key
DEVELOPMENT_TEAM = XXXXXXXXXX      # your 10-character Apple Team ID
```

Your Team ID is in [developer.apple.com](https://developer.apple.com) → Account → Membership, or visible in Xcode → Settings → Accounts after signing in.

This file is gitignored and never committed.

### 2. Generate and open the Xcode project

```bash
brew install xcodegen   # first time only
xcodegen generate
open GlycoTrack.xcodeproj
```

### 3. Build and run on device

In Xcode:
1. Connect your iPhone via USB (trust the computer if prompted)
2. Select your device in the toolbar (not a simulator)
3. Press **⌘R** to build and run

Xcode's Automatic signing will provision the app and create the App Group (`group.com.glycotrack.shared`) on first build. If Xcode asks to register a device or capability, click **Register**.

> **Note:** The App Group is required for the widget to share data with the main app. With a free Apple ID it works for personal device testing (7-day certificate). A paid developer account removes that limit.

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
| NotificationManager | `GlycoTrack/Modules/NotificationManager/` | End-of-day push |

## Data Flow

1. Widget mic button → `VoiceCapture` → transcript
2. `TranscriptParser` (Claude API) → JSON food array
3. `GIEngine` + `CLEngine` → GL + CL values
4. Core Data → persisted `FoodLogEntry` records
5. SwiftUI views → render from Core Data queries

## Running Tests

```bash
swift test   # 26 tests, all pass
```

Tests cover GL/CL calculations against published nutritional tables and dietary pattern validation (Mediterranean vs. American fast food).
