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

## UI Refresh — 2026-04-30 (in progress)

A focused pass to simplify the surface area, remove half-finished prototypes, and apply a more distinctive visual identity. Single-PR scope.

**Removals**
- **Summary tab + `SummaryGenerator` module** — narrative AI summaries weren't carrying their weight against the visualizations. The tab is gone; the module is deleted (no other call sites).
- **Tug-of-War CL viz** — three CL prototypes was one too many; Tug of War lost the prototype bake-off. `TugOfWarBarView.swift` deleted; references removed from Today + Week tabs.
- **Debug tab + About tab from the tab bar** — neither is for end-users on the daily path. Both move into a single consolidated sheet (see below). The tab bar now shows only Today / Week / Month / Log.

**Consolidation: Settings / About / Debug**
- One gear button on the Today nav bar opens a single sheet.
- Sheet uses a top-level segmented control (`Settings · About · Debug`) so a tap toggles between the three. Each pane re-uses its prior content largely as-is.
- About content (educational copy on GL/CL math, tiers, sources) stays the same.

**Today CL layout**
- CL section default = **Balance**. Picker is gone.
- **Waterline** is rendered as its own scroll-down section below Balance — the user scrolls to see the second view. Two lenses on the same data, no extra tab.

**Listening / transcript polish**
- "Listening…" feedback moves out of the page-flow card into a **floating pill above the tab bar** near the mic button. Page content no longer reflows on record.
- Lingering transcript bug: `VoiceCapture.transcript` was never cleared after `stopRecording()`, so the in-flow card stuck around. Fix: clear `transcript` (and `FoodLogProcessor.lastError`) once the entry is committed; pill auto-dismisses after a short fade.

**Accelerometer-driven gravity**
- `PhysicsBucketView` and `WaterlineView` only. A shared `MotionGravityController` reads `CMMotionManager.deviceMotion.gravity` on the main run loop (~30 Hz) and maps it onto each scene's `physicsWorld.gravity` so items roll/settle in the direction of real gravity as the user tilts the phone.
- Waterline water surface stays at the midline regardless of tilt — only items respond. (Tilting the surface convincingly is much harder; not worth the complexity.)

**Waterline settling — faster**
- Floater spring-toward-waterline currently uses `springConstant = 6.0` with `linearDamping = 0.6`. That's underdamped → long visible oscillation. Bump spring (≈12) and damping (≈0.85) to land closer to critical damping for the typical floater mass; result is a faster decisive rise + settle.

**Visual styling — direction (a)**
- Bold rounded SF typography for headers and big numbers (`.system(.title2, design: .rounded, weight: .bold)`).
- GL accent (deep blue) and CL accent (crimson) used as **section identity**: gradient header bands, tinted backgrounds, accent-on-white chips.
- More generous whitespace between sections; cards get a subtle shadow + larger corner radius.
- Replace flat `Color(.systemGray6)` chips with gradient-filled accent chips for headline numbers.
- Tab bar styling refined to match (slightly larger pill, accent halo behind selected icon).

---

## Post-MVP Iterations (since 2026-04-20 device launch)

Tracks merged PRs that materially shape the product after the initial MVP deployment.

| PR | Title | What changed |
|---|---|---|
| #18 | Visualization overhaul | Emojis replaced food-group color tokens entirely; SpriteKit physics for daily GL bucket; date navigation across visualizations. |
| #19 | Worktree sync rule | Added the rebase-on-start rule to CLAUDE.md so feature branches don't drift behind develop. |
| #20 | Today tab polish + CL viz fixes | Tightened the Today tab; first round of physics tuning on Waterline / Balance scenes. |
| #21 | Unified entry flow + waterline fix + build info | Every entry-tap routes through `FoodEntryDetailSheet` (no more direct edit-jump); `DebugTabView` surfaces git branch / commit / build timestamp via `BuildInfo.generated.swift`. |
| #22 | Week tab + floating tab bar + CL physics | Replaced system `TabView` with two-pill custom bar (record button on right, iOS Weather app pattern); fixed Week tab axis labels and Mon-start week predicate; Waterline floaters now use spring-toward-waterline; Balance scale now locked horizontal until drops settle. |
| #23 | Widget containerBackground | Adopted iOS 17 `.containerBackground(for: .widget)` so the widget renders instead of showing the "adopt containerBackground API" black-rectangle warning. |
| #24 | Codebase cleanup | Removed force-unwraps in date math; deleted dead code in iOS-target `GIEngine.swift`; consolidated `DateFormatter`s into `UI/Theme/DateFormatters.swift`; introduced `APIKey` typed accessor; hoisted CL palette `SKColor`s to `UI/Theme/CLPalette.swift`. |
| (this PR) | Matcher tightening + decomposition prompt + parser tests | Findings from a prod log export (90 active entries) drove three matcher fixes: (a) T1 contains-match gate is now strict `> 0.5` so 1-word generics fall through to T3 instead of latching onto a specific variant (kills `bread→rye bread`, `juice→pomegranate juice`, `chicken→chicken drumstick`); (b) fuzzy match refuses to bridge across prep-method words (`grilled` vs `fried`, `baked` vs `steamed`, etc.) — same Levenshtein distance no longer disguises a different cooking technique with a different CL profile; (c) `decomposeIngredients` system prompt has a new HEADLINE-CARB RULE forcing the named carb (noodles/rice/pasta/bread/…) into the ingredient list, fixing the `hand pulled lamb noodle → lamb + broth` class of silent-GL=0 misses. New `Tests/TranscriptParserCoreTests/` covers parser happy path, malformed responses, prompt-rule regression, and decomposition contract (12 tests). |

---

## Design vs Implementation Divergences (refreshed)

| DESIGN.md says | Implementation does | Rationale |
|---|---|---|
| GI + USDA DBs bundled as SQLite tables | JSON files seeded into Core Data at first launch | Simpler toolchain; no SQLite schema migration needed |
| Core Data `.xcdatamodeld` model file | Programmatic `NSManagedObjectModel` in Swift | Xcode 26 CDMFoundation bug crashes on any `.xcdatamodel` file |
| Tab 1 labelled "Home" | Tab labelled "Today" | More descriptive for a daily-logging app |
| Voice streams audio to Claude in real-time | Apple Speech → transcript → Claude parses text | `SFSpeechRecognizer` runs locally; Claude receives text only |
| Widget is strict mic button | Widget shows GL progress bar + mic deep-link | WidgetKit cannot access microphone |
| Color = food group; food groups have a 6-color palette (DESIGN §6.3, §8) | **Food groups removed entirely.** Each food renders as a single emoji via `FoodEmoji.resolve(entry:)`; tier/confidence tinting kept for the row badge only. | Color-coding by food group never communicated as much as the emoji identity itself; testing showed users read the emoji first. |
| GL × CL Quadrant is a 4-region plot in a modal sheet (DESIGN §8) | **Two-region plot embedded inline** on Today/Week/Month tabs (left/right, GL grows up from a 0 baseline) | Lower half would be permanently empty (GL is unsigned); modal added a tap to no purpose. |
| 5 tabs (Home/Week/Month/Log/Summary) inside the system `TabView` (DESIGN §9) | 7 tabs (Today/Week/Month/Log/Summary/About/Debug) in a custom floating bar with a separated record-button pill on the right | Record action needed to be reachable from any tab; About + Debug are dev-facing. |
| Daily GL budget hardcoded to 100 (DESIGN §3.1) | Constant `dailyGLBudgetUI` in `GLThreshold.swift`; `GIEngineCore` exposes its own `dailyGLBudget` for tests | Two homes is intentional — UI and engine want to evolve independently. iOS-target `GIEngine.swift` no longer redefines it. |
| Tier 5 unrecognized foods (CLAUDE.md) | T5 returns GL=0/CL=0 with explicit "Not recognized" red badge | **Never** silently zero an unrecognized food into a high-confidence match; T5 is the load-bearing failure path. |

---

## Suggested Next Steps (prioritized)

Concrete, mobile-app-developer-flavored proposals. Roughly grouped by impact ÷ effort. Pick top items per session; not a contract.

### A. Reliability & data quality (do these first)

1. ⚙️ **Expand `usda_nutrition.json`.** First pass landed: 377 → 501 entries (124 curated additions covering all named prod-log gaps — `pine nuts`, `chana masala`, `corn on the cob`, `gooseberries`, `cantaloupe`, etc. — plus common proteins, cheeses, vegetables, and composite dishes). GI-database coverage rose from 367/776 to 488/776, cutting silent CL=0 cases by ~33%. New `scripts/build_usda_nutrition.py` consumes USDA FoodData Central SR Legacy CSVs (`--fdc-dir` flag) and merges them with `scripts/usda_supplement.json`; running with the FDC bundle locally is the path to push past 1,500 entries. Missing GI entries also added: `whole wheat spaghetti` (GI 37), `tomato sauce` (GI 38), `honey wheat bread` (GI 72).
2. ✅ **Add `Tests/TranscriptParserCoreTests/`** — landed in this-PR. 12 tests cover `parse(transcript:)` happy/malformed/preamble/empty paths, `decomposeIngredients` shape, and a regression test pinning the `HEADLINE-CARB RULE` in the system prompt.
3. **CI via GitHub Actions** running `swift test` + `xcodebuild build … iOS Simulator` on every PR. Currently relies on local builds; one rebase-without-rebuild can land a broken `develop`.
4. **Core Data migration plan.** The model is programmatic, so any new attribute is a manual `NSMappingModel` away from a wipe. Either document the "blow away local store on schema change" policy in CLAUDE.md, or wire up a lightweight migration test.
5. **iOS-side matcher regression tests.** This-PR's matcher tightening (gate, prep-method block) is currently only verified by hand against the prod log export. A `Tests/MatchingTests/` target with an in-memory Core Data store would let us pin `bread →∅`, `chicken →∅`, `grilled chicken ↛ fried chicken`, and `white rice → steamed white rice` as named regressions. Needs `PersistenceController.init(inMemory:)` to be `internal`.

### B. UX refinements (visible value to the user)

5. **Settings screen with editable daily GL budget.** Some users have physician-prescribed budgets that differ from the default 100. Today the budget is constant. Stored in `UserDefaults`, default 100, surfaced on Today + Month + summary chips.
6. **Lock-screen / StandBy widget** (`accessoryRectangular`, `accessoryCircular`). Widget extension already exists; iOS 17 lock-screen widget is one extra `WidgetFamily` case + a slimmer view.
7. **Haptic feedback** when an item lands in the bucket / on a balance plate (`UIImpactFeedbackGenerator(style: .light)` from a SpriteKit contact callback). Free polish.
8. **VoiceOver labels** on emoji items in the SpriteKit scenes. Currently every food in the bucket is a generic SKNode with no accessibility label — VoiceOver users can't read the visualizations.
9. **"Refine" affordance on low-confidence rows.** Today the user sees a red badge but has to open the edit sheet and retype. Tap the badge → present a search-style picker against `NutritionalProfile` so the user can promote the entry to a known food in two taps.
10. **Week-over-week comparison strip on the Week tab** ("This week vs last week: GL avg ↓7"). Reuses `PeriodSummaryView`; one extra `@FetchRequest` for the prior week.

### C. Engineering hygiene

11. **Unified logging via `os.Logger`** instead of `print(...)`. Categorized (`network`, `coreData`, `voice`), respects Release builds.
12. **Extract `ClaudeAPIClient`** from `Modules/TranscriptParser/TranscriptParser.swift` into `Modules/ClaudeAPI/`. It's used independently by `SummaryGenerator` and the Edit-recompute path; living inside `TranscriptParser.swift` is a layering smell.
13. **SwiftLint** with rules for `force_unwrapping` (warning), `line_length`, `function_body_length`, `large_tuple`. Catches the kind of issue this PR found by hand.
14. **Profile first-launch seeding.** `PersistenceController.seedNutritionalProfiles()` parses two JSONs and inserts ~1,150 rows on first launch. Visible delay on weak hardware? Move to a background context with a progress hint.
15. **Replace `Bundle.main.infoDictionary` lookups for non-API-key config.** `BuildInfo`, `AppInfo`, and any future runtime flag should follow the `APIKey` enum pattern (typed accessor, single home).

### D. Strategic (multi-PR work, surface area changes)

16. **HealthKit write integration.** Daily GL / CL aggregate writes to HealthKit so other apps (and the watch) can consume. Requires entitlement; gated to paid Apple Developer Program.
17. **Apple Watch complication** showing today's GL ratio. Requires sharing the App Group + a tiny WatchKit target.
18. **Background-refresh widget timeline** so the widget GL number updates without opening the app. Today the widget reads `UserDefaults` and that's only refreshed on log; combine with `WidgetCenter.shared.reloadTimelines(ofKind:)` after every log.
19. **Soft-delete cleanup job** that hard-deletes entries with `isSoftDeleted == true` older than 30 days. Right now soft-deleted rows accumulate forever.
20. **Cohort export** (CSV / Files-app integration). Personal-team users can't use CloudKit; an "Export logs" button writes a CSV they can email to themselves as a primitive backup.

### E. Speculative / research-mode

21. **Photo-based food logging via Vision + Claude vision API.** Already in DESIGN §17 but worth scoping a small spike.
22. **On-device food-name embedding** (e.g. `NaturalLanguage` framework or a tiny CoreML model) to replace Levenshtein in T1/T2 with semantic match. "linguine" → "spaghetti" should resolve without falling all the way to Claude.

---

## Critical Design Constraints

| Constraint | Implementation |
|---|---|
| GL unsigned | `computedGL` always `max(0, raw)`, Double |
| CL signed | `computedCL` can be negative, Double |
| Daily GL budget 100 | `dailyGLBudgetUI` in `UI/Theme/GLThreshold.swift`; SPM core has its own `dailyGLBudget` |
| Midnight local TZ | `Calendar.current.startOfDay(for: Date())` |
| No raw audio storage | `VoiceCapture` only keeps transcript string |
| iOS 16+ | Core Data (not SwiftData), no `@Observable` macro |
| API key security | From `Info.plist` env var injection via xcconfig, never hardcoded |
