# GlycoTrack

Voice-first food logging app for iOS. Tracks Glycemic Load (GL) and Cholesterol Load (CL) simultaneously to help manage diabetes and heart disease risk.

## Setup

### Requirements
- Xcode 15+ (on macOS)
- iOS 16+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Claude API key

### Generate Xcode Project

```bash
brew install xcodegen
xcodegen generate
open GlycoTrack.xcodeproj
```

### Configure API Key

Set your Claude API key in `GlycoTrack/Info.plist` under `CLAUDE_API_KEY`, or inject via an `.xcconfig`:

```
CLAUDE_API_KEY = your-key-here
```

### App Group

The app and widget share data via App Group `group.com.glycotrack.shared`. Configure this in your Apple Developer account and set `DEVELOPMENT_TEAM` in `project.yml`.

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
swift test
```

Tests cover GL/CL calculations against published nutritional tables and dietary pattern validation.
