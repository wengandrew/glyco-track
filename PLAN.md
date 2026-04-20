# GlycoTrack MVP — Implementation Plan

## Context

GlycoTrack is a voice-first iOS food-logging app that tracks two independent health metrics simultaneously: Glycemic Load (GL) and Cholesterol Load (CL). The user has provided a complete design document. This plan covers storing that design doc in the repo and building the full MVP from scratch.

---

## Repository Structure

```
glyco-track/
├── DESIGN.md                        # Full design document
├── PLAN.md                          # This file
├── project.yml                      # XcodeGen project definition
├── Package.swift                    # SPM for testable logic modules
├── README.md
│
├── GlycoTrack/                      # iOS App target
│   ├── App/
│   │   ├── GlycoTrackApp.swift      # @main entry point, Core Data stack init
│   │   └── AppDelegate.swift        # UNUserNotificationCenter delegate
│   ├── Models/
│   │   ├── GlycoTrackManagedObjectModel.swift  # Programmatic NSManagedObjectModel
│   │   ├── FoodLogEntry+CoreDataClass.swift
│   │   ├── FoodLogEntry+CoreDataProperties.swift
│   │   ├── NutritionalProfile+CoreDataClass.swift
│   │   ├── NutritionalProfile+CoreDataProperties.swift
│   │   └── CoreDataIdentifiable.swift
│   ├── Modules/
│   │   ├── GIEngine/GIEngine.swift
│   │   ├── CLEngine/CLEngine.swift + CLWeights.swift
│   │   ├── TranscriptParser/TranscriptParser.swift  (includes ClaudeAPIClient)
│   │   ├── SummaryGenerator/SummaryGenerator.swift
│   │   ├── VoiceCapture/VoiceCapture.swift
│   │   ├── LocalStorage/
│   │   │   ├── PersistenceController.swift
│   │   │   ├── FoodLogRepository.swift
│   │   │   └── NutritionalRepository.swift
│   │   └── NotificationManager/NotificationManager.swift
│   ├── Resources/
│   │   ├── gi_database.json         # 776 foods {name, gi, aliases}
│   │   └── usda_nutrition.json      # 377 foods {name, carbs, sfa, tfa, fiber, pufa, mufa}
│   └── UI/  (tabs, visualizations, components, theme)
│
├── GlycoTrackWidget/
│   ├── GlycoTrackWidget.swift
│   └── GlycoTrackWidgetEntryView.swift
│
├── Sources/                         # SPM targets (testable)
│   ├── GIEngineCore/
│   ├── CLEngineCore/
│   └── TranscriptParserCore/
│
└── Tests/
    ├── GIEngineCoreTests/
    └── CLEngineCoreTests/
```

---

## Implementation Phases & Status

### Phase 0: Foundation ✅ COMPLETE
### Phase 1: Data Layer ✅ COMPLETE
- `gi_database.json` — **776 entries**
- `usda_nutrition.json` — **377 entries** ⚠️ stretch target ~7793
### Phase 2: Engines ✅ COMPLETE
### Phase 3: Claude API Integration ✅ COMPLETE
### Phase 4: Voice + Widget ✅ COMPLETE
### Phase 5: UI Shell ✅ COMPLETE
### Phase 6: Visualizations ✅ COMPLETE
### Phase 7: Tab UIs ✅ COMPLETE
### Phase 8: Notifications + Polish ✅ COMPLETE

---

## 🎉 Milestone: MVP Deployed to Physical Device (2026-04-20)

The app has been built and deployed to an iPhone running iOS 26 (macOS 26 / Xcode 26.1.1).

### Xcode 26 Compatibility Fixes Applied

Several Xcode 26 / iOS 26 breaking changes required fixes before deployment:

| Issue | Fix |
|---|---|
| `CDMEntity initWithXMLElement` crash in Xcode 26's CDMFoundation indexer | Replaced `.xcdatamodeld` file entirely with a programmatic `NSManagedObjectModel` in `GlycoTrackManagedObjectModel.swift` |
| `codeGenerationType="manual"` caused indexer assertion | Removed by switching to programmatic model (no model file) |
| `isDeleted` conflicts with `NSManagedObject` built-in | Renamed attribute to `isSoftDeleted` throughout |
| `timestamp`, `loggedAt`, `id` optional `Date?`/`UUID?` values passed to non-optional APIs | Added `?? Date()` / `?? UUID()` fallbacks at all call sites |
| `navigationTitle(_:displayedComponents:)` removed from SwiftUI in Xcode 26 | Replaced with `navigationTitle(date.formatted(...))` |
| `fill(_:style:)` + `stroke(_:lineWidth:)` chain requires iOS 17 | Replaced with `.fill(...).overlay(stroke(...))` |
| `UIApplication` not in scope in `NotificationManager` | Added `import UIKit` |
| `com.apple.developer.usernotifications.time-sensitive` unsupported on personal team | Removed entitlement |
| `com.apple.developer.speech-recognition` + `com.apple.security.application-groups` unsupported on personal team | Removed entitlements (add back with paid account) |

### Personal Team Limitations (free Apple ID)

These features are degraded when sideloaded with a free developer account and can be restored with a paid Apple Developer Program membership:

- **Widget data** — App Groups entitlement removed; widget shows empty data
- **Voice logging** — Speech recognition entitlement removed; on-device `SFSpeechRecognizer` still works for iOS 26, server-side recognition unavailable
- **Certificate expiry** — 7-day sideload certificate; reinstall required weekly

---

## Known Limitations (post-MVP)

- `NotificationManager.cancelTodayIfSufficientlyLogged` removes the repeating trigger; future-day notifications only resume when the user opens the app. Users who don't open the app the day after cancelling will miss one notification.
- `usda_nutrition.json` has 377 entries vs DESIGN target of 7,793. Foods without USDA data fall back to GI-only GL calculation with CL=0. Expansion is a post-MVP stretch goal.
- Widget shows empty GL data without App Groups (personal team limitation).

---

## Design vs Implementation Divergences

| DESIGN.md says | Implementation does | Rationale |
|---|---|---|
| GI + USDA DBs bundled as SQLite tables | JSON files seeded into Core Data at first launch | Simpler toolchain; no SQLite schema migration needed |
| Core Data `.xcdatamodeld` model file | Programmatic `NSManagedObjectModel` in Swift | Xcode 26 CDMFoundation bug crashes on any `.xcdatamodel` file |
| Tab 1 labelled "Home" | Tab labelled "Today" | More descriptive for a daily-logging app |
| Voice streams audio to Claude in real-time | Apple Speech → transcript → Claude parses text | `SFSpeechRecognizer` runs locally; Claude receives text only |
| Widget is strict mic button | Widget shows GL progress bar + mic deep-link | WidgetKit cannot access microphone |

---

## Critical Design Constraints

| Constraint | Implementation |
|---|---|
| GL unsigned | `computedGL` always `max(0, raw)`, Double |
| CL signed | `computedCL` can be negative, Double |
| Daily GL budget 100 | Hardcoded constant `dailyGLBudget = 100.0` |
| Midnight local TZ | `Calendar.current.startOfDay(for: Date())` |
| No raw audio storage | `VoiceCapture` only keeps transcript string |
| iOS 16+ | Core Data (not SwiftData), no `@Observable` macro |
| API key security | From `Info.plist` env var injection via xcconfig, never hardcoded |
