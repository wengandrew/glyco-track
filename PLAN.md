# GlycoTrack MVP — Implementation Plan

## Context

GlycoTrack is a voice-first iOS food-logging app that tracks two independent health metrics simultaneously: Glycemic Load (GL) and Cholesterol Load (CL). The user has provided a complete design document. This plan covers storing that design doc in the repo and building the full MVP from scratch in a Linux environment targeting iOS 16+ / iPhone 13+.

Since the build environment is Linux (no Xcode GUI, no simulator), the strategy is:
- Write all Swift source files in a valid Xcode-compatible project structure
- Use **XcodeGen** (`project.yml`) so the user can run `xcodegen generate` on their Mac to produce the `.xcodeproj`
- Use **Swift Package Manager** for the pure-logic layer (engines, storage, API clients) so unit tests can run on Linux via `swift test`
- Use **Core Data** (not SwiftData) for iOS 16 compatibility
- Bundle reference databases as seeded SQLite files populated at first launch from embedded JSON

> **Note (2026-04-18):** Development continues locally on macOS (not Linux). The XcodeGen + SPM structure still applies; `swift test` can run natively. The `.xcodeproj` is regenerated via `xcodegen generate` after any `project.yml` changes.

---

## Repository Structure

```
glyco-track/
├── DESIGN.md                        # Full design document (stored first)
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
│   │   ├── GlycoTrack.xcdatamodeld  # Core Data schema (FoodLogEntry + NutritionalProfile)
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
│   │   ├── gi_database.json         # Target: ~750 foods {name, gi, aliases}
│   │   └── usda_nutrition.json      # Target: ~7793 foods {name, carbs, sfa, tfa, fiber, pufa, mufa}
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
1. `DESIGN.md` ✅
2. `Package.swift` ✅
3. `project.yml` ✅
4. `README.md` ✅

### Phase 1: Data Layer ⚠️ PARTIAL
5. Core Data model (`.xcdatamodeld`) ✅
6. `PersistenceController.swift` ✅
7. `FoodLogRepository.swift` ✅
8. `NutritionalRepository.swift` ✅
9. `gi_database.json` — **359 entries** (target: ~750) ⚠️ needs expansion
10. `usda_nutrition.json` — **377 entries** (expanded from 177; covers all 359 GI foods) ⚠️ stretch target ~7793

**Known Phase 1 gaps:**
- gi_database.json covers common foods but missing ~400 less common ones
- usda_nutrition.json covers all current GI foods; further expansion is stretch goal

### Phase 2: Engines ✅ COMPLETE
11. `GIEngine.swift` + unit tests ✅
12. `CLEngine.swift` + `CLWeights.swift` + unit tests ✅

### Phase 3: Claude API Integration ✅ COMPLETE
13. `ClaudeAPIClient.swift` — real SSE streaming via `URLSession.bytes(for:)` + `AsyncThrowingStream` ✅
14. `TranscriptParser.swift` — food extraction (non-streaming, atomic JSON) ✅
15. `SummaryGenerator.swift` — trend analysis with progressive token streaming into `@Published summary` ✅

### Phase 4: Voice + Widget ✅ COMPLETE
16. `VoiceCapture.swift` ✅
17. `GlycoTrackWidget.swift` + entry view ✅

### Phase 5: UI Shell ✅ COMPLETE
18. `RootTabView.swift` ✅
19. `FoodGroupColor.swift`, `GLThreshold.swift` ✅
20. `FoodBubble.swift` ✅

### Phase 6: Visualizations ✅ COMPLETE (scaffold)
21–27. All 7 visualization prototypes scaffolded ✅

**Known visualization issues:** none — all fixed ✅

### Phase 7: Tab UIs ✅ COMPLETE (scaffold)
28–32. All 5 tabs scaffolded ✅

**Known tab issues:** none — all fixed ✅

### Phase 8: Notifications + Polish ✅ COMPLETE (scaffold)
33–35. `NotificationManager`, `AppDelegate`, `GlycoTrackApp` ✅

---

## Current Work Queue (2026-04-18)

All phases complete. Remaining stretch goals only.

**Phase 1 — Database expansion (stretch):**
- [ ] Expand `gi_database.json` from 359 → ~750 entries

**No open bugs.** All previously noted issues fixed:
- ✅ `EditEntryView`: GL/CL now recalculated on save via GIEngine + CLEngine
- ✅ `NotificationManager.cancelTodayIfSufficientlyLogged`: now actually cancels when ≥3 entries
- ✅ `FoodLogProcessor`: wired to call `cancelTodayIfSufficientlyLogged` after each batch save
- ✅ `DailyBucketView`: dead `resolvedColor` variable removed
- ✅ `MonthlyHeatmapView`: weekday labels changed to `["M","Tu","W","Th","F","Sa","Su"]`

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
| API key security | From `Info.plist` env var injection, never hardcoded |
| App Group | `group.com.glycotrack.shared` for widget ↔ app |

---

## Verification Plan

### Logic (runnable via `swift test`):
- `GIEngineTests`: white rice GL=72×45g/100=32.4, lentils GL=32×40g/100=12.8
- `CLEngineTests`: butter 100g → CL ≈ 45.3 (positive, harmful)
- `CLEngineTests`: Mediterranean meal CL < 0
- `CLEngineTests`: American fast food meal CL > 0

### App (requires Xcode on Mac):
1. `xcodegen generate` → opens in Xcode
2. Build for iPhone 13 simulator (iOS 16+)
3. Tap widget mic → speak "I had oatmeal and orange juice"
4. Verify 2 FoodLogEntry records created with correct GL/CL
5. Check Log tab shows both entries with confidence scores
6. Check Home tab DailyBucketView updates
7. Check QuadrantPlot positions (oatmeal: top-left quadrant)
8. Force summary generation → verify Claude response streams in progressively
9. Verify notification scheduled via `UNUserNotificationCenter.pending()`
