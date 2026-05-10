# GlycoTrack — Implementation Plan

## What this app is

GlycoTrack is a voice-first iOS food-logging app that tracks two independent health metrics per meal:

- **GL (Glycemic Load)** — unsigned, daily budget of 100. Formula: `(GI × carbs_g) / 100`.
- **CL (Cholesterol Load)** — signed. Positive = harmful (sat/trans fat), negative = beneficial (fiber, PUFA, MUFA).

The user speaks a meal ("I had a bowl of ramen and green tea") and the app resolves each food through a matching cascade, computes GL and CL, and surfaces the results through physics-based visualizations.

---

## Repository Structure (current)

```
glyco-track/
├── CLAUDE.md                        # Session instructions for Claude Code
├── DESIGN.md                        # Original product design document
├── PLAN.md                          # This file
├── project.yml                      # XcodeGen project definition
├── Package.swift                    # SPM for testable logic modules
│
├── GlycoTrack/                      # iOS app target
│   ├── App/
│   │   ├── GlycoTrackApp.swift
│   │   └── AppDelegate.swift
│   ├── Models/
│   │   ├── GlycoTrackManagedObjectModel.swift  # Programmatic NSManagedObjectModel (no .xcdatamodeld)
│   │   ├── FoodLogEntry+CoreDataClass.swift
│   │   ├── FoodLogEntry+CoreDataProperties.swift
│   │   ├── NutritionalProfile+CoreDataClass.swift
│   │   ├── NutritionalProfile+CoreDataProperties.swift
│   │   └── CoreDataIdentifiable.swift
│   ├── Modules/
│   │   ├── GIEngine/GIEngine.swift
│   │   ├── CLEngine/CLEngine.swift              # CLWeights.swift lives in Sources/CLEngineCore/
│   │   ├── TranscriptParser/TranscriptParser.swift
│   │   ├── ClaudeAPI/ClaudeAPIClient.swift      # extracted from TranscriptParser in #39
│   │   ├── Matching/
│   │   │   ├── FoodMatcher.swift
│   │   │   ├── AliasIndex.swift
│   │   │   └── EntryRefiner.swift
│   │   ├── VoiceCapture/VoiceCapture.swift
│   │   ├── LocalStorage/
│   │   │   ├── PersistenceController.swift
│   │   │   ├── FoodLogRepository.swift
│   │   │   └── NutritionalRepository.swift
│   │   ├── Logging/Log.swift                   # os.Logger wrappers (#40)
│   │   └── NotificationManager/NotificationManager.swift
│   ├── Resources/
│   │   ├── gi_database.json         # 1081 foods {name, gi, aliases, carbs}
│   │   ├── usda_nutrition.json      # 813 foods {name, carbs, sfa, tfa, fiber, pufa, mufa}
│   │   └── food_emoji_map.json
│   ├── Config/
│   │   ├── GlycoTrack.xcconfig      # committed stub; includes .local.xcconfig
│   │   ├── AppInfo.swift
│   │   └── BuildInfo.generated.swift
│   └── UI/  (tabs, visualizations, components, theme)
│       ├── Tabs/  (HomeTabView, WeekTabView, MonthTabView, LogTabView)
│       └── Visualizations/  (PhysicsBucketView, BalanceScaleView, WeeklyRiverView, …)
│
├── GlycoTrackWidget/
│   ├── GlycoTrackWidget.swift
│   └── GlycoTrackWidgetEntryView.swift
│
├── Sources/                         # SPM targets (run via `swift test`, Linux-compatible)
│   ├── GIEngineCore/
│   ├── CLEngineCore/
│   └── TranscriptParserCore/
│
├── Tests/
│   ├── GIEngineCoreTests/
│   ├── CLEngineCoreTests/
│   ├── TranscriptParserCoreTests/
│   └── MatchingTests/               # iOS-target XCTests against real Core Data store
│       ├── NutritionalRepositoryRegressionTests.swift
│       └── EthnicFoodCoverageTests.swift
│
└── .claude/
    ├── settings.json                # Claude Code hook registration
    └── hooks/
        └── check-plan-updated.sh   # Blocks `gh pr create` if PLAN.md is unmodified (#59)
```

---

## Implementation Phases

All phases are complete as of the MVP device launch (2026-04-20).

| Phase | Description | Status |
|---|---|---|
| 0 | Foundation: repo, XcodeGen, SPM, CI skeleton | ✅ |
| 1 | Data layer: GI + USDA JSON databases, Core Data seeding | ✅ |
| 2 | Engines: GIEngine, CLEngine (SPM + iOS wrappers) | ✅ |
| 3 | Claude API integration: TranscriptParser, FoodMatcher cascade | ✅ |
| 4 | Voice capture + widget | ✅ |
| 5 | UI shell: tab bar, navigation, theme | ✅ |
| 6 | Visualizations: physics bucket, balance scale, river, heatmap, quadrant | ✅ |
| 7 | Tab UIs: Today, Week, Month, Log | ✅ |
| 8 | Notifications + polish | ✅ |

**Current database sizes:** `gi_database.json` — 1081 entries · `usda_nutrition.json` — 813 entries

---

## Milestone: MVP Deployed to Device (2026-04-20)

Built and deployed to an iPhone running iOS 26 / Xcode 26.1.1. (`project.yml` declares `xcodeVersion: "15.0"` as the XcodeGen minimum constraint; the actual build toolchain is Xcode 26.)

### Xcode 26 compatibility fixes

| Issue | Fix |
|---|---|
| `CDMEntity initWithXMLElement` crash in CDMFoundation | Replaced `.xcdatamodeld` with programmatic `NSManagedObjectModel` |
| `isDeleted` conflicts with `NSManagedObject` built-in | Renamed to `isSoftDeleted` throughout |
| Optional `Date?`/`UUID?` passed to non-optional APIs | Added `?? Date()` / `?? UUID()` fallbacks |
| `navigationTitle(_:displayedComponents:)` removed | Replaced with `navigationTitle(date.formatted(...))` |
| `.fill().stroke()` chain requires iOS 17 | Replaced with `.fill().overlay(stroke(...))` |

### Free Apple ID limitations (resolved by paid-team enrollment)

- **Widget data** — App Groups entitlement removed; widget shows empty data
- **Certificate expiry** — 7-day sideload; reinstall required weekly

---

## Post-MVP PR History

All PRs target `develop`. Listed in merge order.

| PR | Title | Summary |
|---|---|---|
| #14 | Fix duplicate food log entries from voice | Deduplication guard in `FoodLogProcessor` — same food logged twice from one utterance. |
| #15 | Fix composite-dish GL/CL + About tab | Matching cascade correctly sums GL/CL across components; added About tab with GL/CL educational copy. |
| #16 | Fix T1 contains-match substring false positives (round 1) | Short food names ("egg", "oat") were matching inside longer unrelated words via plain `String.contains`. Introduced `_wordBoundaryContains`. |
| #17 | Fix T1 contains-match spurious short-name matches (round 2) | Word-count ratio gate: query must cover ≥ 50% of DB entry word count to match. "sugar" → "sugar snap peas" (33%) now rejected. |
| #18 | Visualization overhaul | Emojis replace food-group color tokens; SpriteKit physics for GL bucket; date navigation across all viz sections. |
| #19 | Worktree sync rule | Added rebase-on-start rule to CLAUDE.md so feature branches don't drift behind develop. |
| #20 | Today tab polish + CL viz physics fixes | Tightened Today tab layout; first round of physics tuning on Waterline / Balance scenes. |
| #21 | Unified entry flow + build info | Every entry-tap routes through `FoodEntryDetailSheet`; `DebugTabView` surfaces git branch/commit/timestamp via `BuildInfo.generated.swift`. |
| #22 | Week tab + floating tab bar + CL physics | Replaced system `TabView` with custom two-pill bar (record button right, iOS Weather pattern); Week tab axis labels and Mon-start predicate fixed; Balance scale locked horizontal until drops settle. |
| #23 | Widget containerBackground | Adopted iOS 17 `.containerBackground(for: .widget)` — widget renders correctly instead of black rectangle. |
| #24 | Codebase cleanup | Removed force-unwraps; deleted dead code; consolidated `DateFormatter`s; introduced `APIKey` typed accessor; hoisted CL palette to `CLPalette.swift`. |
| #25 | Matcher tightening + decomposition prompt + parser tests | T1 contains-match word-count gate (≥ 50%); fuzzy refuses to bridge prep-method words (grilled ↛ fried); `HEADLINE-CARB RULE` in `decomposeIngredients`; 12 new parser tests. |
| #26 | Wire GI-database aliases into matcher | Fixed regression from #25 — aliases (e.g. `pomegranate juice → pomegranate`) were dropped at lookup. `AliasIndex` singleton introduced. |
| #27 | Whole-grain fidelity + emoji-resolver overhaul | "whole wheat bread" no longer collapses to "white bread"; `FoodEmoji.resolve` rewritten with priority cascade. |
| #28 | USDA expansion 377→501 + build script | `scripts/build_usda_nutrition.py` consumes FoodData Central CSVs; +124 curated entries. |
| #29 | Matcher regression tests (iOS target) | `Tests/MatchingTests/` created; real Core Data store in tests; pins `bread→∅`, `chicken→∅`, `grilled chicken↛fried chicken`. |
| #30 | CI: `swift test` + iOS Simulator build | GitHub Actions job on every PR. |
| #31 | Core Data schema-change policy | Wipe-on-mismatch policy documented in CLAUDE.md; when to revisit (paid team, multi-user). |
| #32 | CI: iOS XCTest suite | `xcodebuild test` job added alongside simulator build. |
| #33 | Haptic feedback in physics scenes | `UIImpactFeedbackGenerator(.light)` from SpriteKit contact callbacks. |
| #34 | Editable daily GL budget | `AppSettings.dailyGLBudgetKey` + `@AppStorage` UI; default 100, range 50–200, step 5. |
| #35 | Week-over-week comparison strip | Second `@FetchRequest` for prior week; deltas via `WeekComparisonStrip`. |
| #36 | VoiceOver labels in SpriteKit | Each `SKLabelNode` carries `accessibilityLabel`. |
| #37 | "Refine" affordance for low-confidence rows | Tap badge → search-style `NutritionalProfile` picker. (Later removed in #56 — algorithm should handle accuracy, not the user.) |
| #38 | Lock-screen + StandBy widget variants | `accessoryRectangular`, `accessoryCircular`, `accessoryInline` added to `GlycoTrackWidget`. |
| #39 | Extract `ClaudeAPIClient` | Moved out of `TranscriptParser.swift` into `Modules/ClaudeAPI/`. |
| #40 | Unified logging via `os.Logger` | `Modules/Logging/Log.swift`; categorized loggers (`app`, `network`, `coreData`, `voice`, `notifications`); `print(...)` removed from production paths. |
| #41 | Encapsulate `Bundle.main.infoDictionary` | `BuildInfo` / `AppInfo` follow the typed-accessor `APIKey` pattern. |
| #42 | Profile + batch first-launch seed | `seedNutritionalProfiles()` runs on background context with batched inserts; `MotionGravityController` for accelerometer gravity. |
| #43 | SwiftLint + CI enforcement | `.swiftlint.yml`; CI blocks on errors. |
| #44 | UI refresh | Removed Summary tab + `SummaryGenerator`, Tug-of-War CL viz, Debug/About from tab bar. Floating listening pill; accelerometer gravity on bucket; Organic-style typography. |
| #45 | Fix navigation title flicker | `NavigationView` → `NavigationStack` in all four primary tab roots. |
| #46 | Time context in voice transcripts | `ParsedFood` gains `loggedAt: Date?`; Claude resolves time phrases ("two hours ago", "yesterday at 5pm") into ISO-8601 stamps; `FoodLogProcessor` stamps with `food.loggedAt ?? recordedAt` and clamps against future drift. 6 new parser tests. |
| #47 | App Store submission blockers | `PrivacyInfo.xcprivacy` for both targets; `UILaunchScreen` brand-color launch; `armv7` capability key removed; `ITSAppUsesNonExemptEncryption = false`; release build validated on Simulator. |
| #48 | Fix voice timestamp timezone bug | Timestamps were being computed in UTC instead of device local time; fixed in `FoodLogProcessor`. |
| #49 | TestFlight distribution workflow | `scripts/archive.sh` for Release archive; `CLAUDE.md` + `PLAN.md` TestFlight section documenting upload + tester invite flow. |
| #50 | Delete button on Edit Entry screen | Direct trash button in `EditEntryView` toolbar alongside Save; confirmation alert before soft-delete. |
| #51 | Auto-dismiss "Couldn't log" error pill | `ListeningPill` error state auto-clears after 4 s so it doesn't block the mic button indefinitely. |
| #52 | `-allowProvisioningUpdates` in deploy.sh | Lets `xcodebuild` auto-register the device without a manual Xcode step on first install to a new phone. |
| #53 | Remove WaterlineView + GL×CL from Home tab | `WaterlineView.swift` deleted; `QuadrantPlotSection` removed from Today tab — Today now shows only GL bucket + CL balance scale. Plot height 200→320 on Week/Month. |
| #54 | Three-theme UI system | Clinical, Organic, Midnight themes; `ThemeManager` + `UserDefaults`. Collapsed to Organic-only in #56. |
| #55 | Fix GL/CL accuracy: fuzzy matching + DB gaps | (1) Normalized fuzzy threshold `d/max_len ≤ 0.30`; (2) `carbs` fallback field added to `gi_database.json` and seeding chain `usda?.carbs ?? gi.carbs ?? 0`; (3) 15 new USDA + 3 new GI entries. 16 regression tests. |
| #56 | UI polish: Organic-only theme, inline search, direct delete | Inline search above log list; Clinical/Midnight themes removed; `FoodEntryDetailSheet` toolbar gets direct Edit + Delete; "Refine match" removed; T5 unrecognized entries dropped (not logged as GL=0). |
| #57 | Remove stats panels; add pickle | Stats panels removed from Week/Month. Pickle added to `usda_nutrition.json`. |
| #58 | Expand test suite | 32 new tests: GL threshold boundaries, fuzzy confidence tiers, CL neutral-band edges, `ParsedFood` Codable round-trips, `wordBoundaryContains` edge cases, `detectGrainQualifier`, `coverageFraction`, `findComponents`. |
| #59 | Expand food databases: global ethnic cuisine + regression suite | `gi_database.json` 782→1081; `usda_nutrition.json` 516→813. ~15 cuisine categories (Chinese/Dim Sum, Japanese, Korean, Thai, Indian, Middle Eastern, Mexican, Filipino, Malaysian, Indonesian, Vietnamese, South American, African, global beverages). 65 existing entries enriched with aliases. `EthnicFoodCoverageTests.swift` (247 tests). Pre-PR hook blocks `gh pr create` if PLAN.md is unmodified. |
| #62 | UI/UX cleanup | Removed: daily insight banner ("Great balance today!"), progress bar + Replay buttons from bucket/balance views, "100 GL" label inside bucket, redundant Settings sheet title. Font changed from serif → system default (SF) throughout; `metricFontDesign` stays `.rounded`. Week timeline redesigned: unified warm background, thin vertical separators, today-column highlight, rounded grid corners. Done/Export buttons moved to bottom of Settings sheet. |
| #64 | Nav chevrons, CL panel cleanup, Impact Map rename | Day/Week/Month chevrons now hide (not grey-out) at boundary dates. CL panel: removed "No CL logged yet" empty state and summary text. Quadrant plot renamed "Food Impact Map" with plain-language subtitle. Month tab gains earliest-month guard so back-chevron hides at first logged month. |
| #65 | Swipe nav, native color scheme, week-day tap to Today | Week and Month tabs now swipe left/right to navigate (matching Day tab). Color scheme switched to native iOS system colors (systemBlue/Orange/Green/Red accents, systemGroupedBackground cards, dark-mode support, no more warm organic palette). `selectedDate` hoisted from HomeTabView to RootTabView as a Binding. Tapping an empty day column in the Week river view jumps to the Today tab with that day selected. |
| #66 | Week GL totals, physics sandbox settings, manual entry text | Week river view shows per-day GL totals under each day label. Settings gains a Physics Sandbox section with gravity (1–20) and vibration (0–100%) sliders. `SceneHaptics` now accepts intensity, `BucketScene` and `BalanceScene` both read AppStorage for gravity and haptics — changes rebuild scenes via SceneKey. Manual entry section header updated to "Type what you ate (manual entry)". |

---

## Current State of the App (2026-05-08)

**What's working well:**
- Voice → GL/CL pipeline reliable for common Western, Asian, and Middle Eastern foods
- Physics visualizations (bucket, balance scale) are the core UX differentiator
- Test suite: 292 Xcode tests + 63 SPM tests, all green on CI
- DB: 1081 GI entries, 813 USDA entries — broadest ethnic coverage to date

**Known limitations:**
- `usda_nutrition.json` is 813 entries vs DESIGN target of 7,793. Foods without a USDA record get CL = 0.
- Widget shows empty GL data without App Groups (free team limitation).
- `NotificationManager.cancelTodayIfSufficientlyLogged` removes the repeating trigger; users who don't open the app the next day miss one notification.

---

## Path to App Store

Goal: submit GlycoTrack 1.0. Splits into engineering work (repo) and deployment logistics (user's Apple accounts).

### Engineering work

#### Submission blockers (1A) — all complete as of PR #47

| Item | PR | Status |
|---|---|---|
| `PrivacyInfo.xcprivacy` for both targets | #47 | ✅ |
| Brand-color launch screen (no blank white flash) | #47 | ✅ |
| `armv7` capability key removed | #47 | ✅ |
| `ITSAppUsesNonExemptEncryption = false` | #47 | ✅ |
| Release build validated on Simulator | #47 | ✅ |
| Version/build number strategy | — | ✅ Option A: manual bump. `CFBundleShortVersionString` (marketing, e.g. `1.0`) and `CFBundleVersion` (build integer, e.g. `1`) stay in `Info.plist`. Bump `CFBundleVersion` before every TestFlight upload; bump `CFBundleShortVersionString` only for user-facing releases. |
| Widget decision: ship or hide for 1.0 | — | ✅ Widget dependency removed from `project.yml` for 1.0. App Groups entitlement requires paid team. Re-enable in 1.1 by adding `- target: GlycoTrackWidget` back to main target dependencies. |

#### App Review risk-reducers (1B)

| Item | Status |
|---|---|
| Permissions onboarding flow (mic + speech recognition) before first alert | ⏳ |
| In-app privacy policy link + support contact in About pane | ⏳ |
| Health-claim disclaimers ("informational only, not medical advice") | ⏳ |
| Empty-state hint on Today tab ("Tap the mic to log your first meal") | ⏳ |
| Graceful network-failure path (retry or fallback beyond red pill) | ⏳ |
| First-launch seeding overlay ("Loading nutritional database…") | ⏳ |
| TestFlight metadata written to `docs/testflight_notes.md` | ⏳ |

#### Optional / 1.1 polish (1C)

- HealthKit daily GL/CL write (paid team gated)
- Background widget timeline refresh
- Soft-delete cleanup job (hard-delete rows older than 30 days)
- CSV export via Files app

### Deployment logistics (user-side)

#### Apple Developer Program

The app is currently signed with a free Apple ID — cannot submit to TestFlight or the App Store.

**Action:** enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) ($99/year).
- **Individual** — simpler (~24 h approval), personal name appears as seller.
- **Organization** — D-U-N-S Number required (~1–2 week lead time); business name as seller. Preferred if you have an LLC or want brand separation.

Once enrolled: add Team ID to `GlycoTrack.local.xcconfig`; re-add speech recognition + App Groups entitlements.

#### App Store Connect

1. Register bundle ID `com.glycotrack.app` (Certificates, IDs & Profiles → Identifiers).
2. Reserve app name "GlycoTrack" — first-come. Run a [USPTO TESS](https://tmsearch.uspto.gov/) check if you care about trademark.
3. Create app record: iOS, bundle ID above, SKU `GLYCOTRACK_2026`, language English (U.S.).

#### Required listing assets

| Asset | Notes |
|---|---|
| App Icon | ✅ 1024×1024 in `Assets.xcassets/AppIcon.appiconset/` |
| Screenshots | Required for 6.7" (1290×2796). 6.5" optional. |
| App Preview video | Optional but high-converting. 15–30 s portrait. |
| Description | ≤ 4,000 chars. GL/CL plain-language explanation + soft disclaimer. |
| Keywords | 100 chars: `glycemic,cholesterol,diabetes,heart,food,log,nutrition,GL,CL,diet` |
| Category | Primary: Health & Fitness · Secondary: Food & Drink |
| Privacy policy URL | Required. GitHub Pages or Iubenda (~$30/yr). |
| Support URL | Required. GitHub Pages or `mailto:` redirect. |

#### Launch sequence

```
Week 0   → Choose Individual vs Organization enrollment.
           If Organization: start D-U-N-S now (1–2 week lead time).
Week 1   → Complete Apple Developer enrollment ($99).
           Ship 1B engineering items (onboarding, disclaimers, empty states).
Week 2   → Set up TestFlight in App Store Connect.
           Recruit 5–10 beta testers.
Week 3–5 → TestFlight beta (Internal → External). Iterate on feedback.
Week 6   → Finalize metadata (screenshots, description, URLs).
           Submit for App Review (median 24–48 h in 2026).
Week 6+  → If approved: schedule release.
           If rejected: read reviewer note, fix, resubmit (1–2 days per round).
```

---

## Post-launch Backlog

| Item | Notes |
|---|---|
| HealthKit write | Daily GL/CL aggregates → Health app. Paid team gated. |
| Apple Watch complication | WatchKit target sharing the App Group. |
| Background widget refresh | Only relevant if widget ships (see 1A widget decision). |
| Soft-delete cleanup job | Hard-delete `isSoftDeleted == true` rows > 30 days old. |
| CSV export | Files-app integration; also useful for App Review test path. |
| Photo-based food logging | Vision + Claude vision API. DESIGN §17. |
| On-device food-name embedding | Replace Levenshtein with semantic match in T1/T2. |
| USDA database expansion | Current: 813 entries. DESIGN target: 7,793. |

---

## Design vs Implementation Divergences

| DESIGN.md says | Implementation does | Rationale |
|---|---|---|
| GI + USDA DBs bundled as SQLite tables | JSON seeded into Core Data at first launch | Simpler toolchain; no SQLite migration needed |
| `.xcdatamodeld` model file | Programmatic `NSManagedObjectModel` in Swift | Xcode 26 CDMFoundation crash on any `.xcdatamodel` file |
| Tab 1 labelled "Home" | Tab labelled "Today" | More descriptive for a daily-logging app |
| Voice streams audio to Claude in real-time | `SFSpeechRecognizer` → transcript string → Claude parses text | On-device ASR; Claude receives text only |
| Entry timestamp = `Date()` at log time | `food.loggedAt ?? recordedAt` — Claude resolves time phrases into ISO-8601 stamps per food | "I had eggs two hours ago" creates a correctly backdated entry without a manual tap |
| Widget is strict mic button | Widget shows GL progress bar + mic deep-link | WidgetKit cannot access microphone |
| Food groups with 6-color palette (§6.3, §8) | Food groups removed entirely; single emoji per food via `FoodEmoji.resolve` | Emoji communicates food identity more directly than color tokens |
| GL × CL as a 4-region quadrant plot (§8) | Two-region plot (left = beneficial CL, right = harmful CL; GL grows up from zero baseline); Today tab shows only bucket + balance scale | Lower half permanently empty; GL is unsigned |
| 5 tabs including Summary | 4 tabs (Today / Week / Month / Log); Summary tab + `SummaryGenerator` removed | AI narrative summaries didn't add over the visualizations |
| Daily GL budget hardcoded to 100 | User-editable 50–200 in Settings (PR #34); SPM engine keeps its own constant for test stability | Accommodates different dietary needs |
| T5 unrecognized foods logged as GL=0/CL=0 | T5 entries are **not logged**; `FoodLogProcessor` sets `lastError` instead | Logging GL=0/CL=0 silently corrupts daily totals |
| "Refine match" affordance (PR #37) | **Removed in PR #56** | Asking the user to fix the algorithm's mistakes violates the design philosophy |

---

## Critical Design Constraints

| Constraint | Implementation |
|---|---|
| GL ≥ 0 (unsigned) | `computedGL = max(0, raw)` |
| CL signed (±) | `computedCL` can be negative |
| Daily GL budget default 100 | `dailyGLBudgetUI` in `UI/Theme/GLThreshold.swift`; SPM core has its own constant |
| Midnight local TZ boundary | `Calendar.current.startOfDay(for: Date())` |
| No raw audio storage | `VoiceCapture` retains transcript string only |
| iOS 16+ | Core Data (not SwiftData); no `@Observable` macro |
| API key security | `Info.plist` ← xcconfig injection; never hardcoded |
| PLAN.md updated with every PR | Enforced for Claude Code `gh pr create` calls by `.claude/hooks/check-plan-updated.sh`; PRs opened via GitHub UI bypass the hook |
