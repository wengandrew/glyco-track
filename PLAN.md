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

## UI Refresh — 2026-04-30 (PR #44, this branch)

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
- ~~Waterline rendered as scroll-down section below Balance~~ — **removed in PR #53**. The Today tab now shows only the GL bucket and the CL balance scale.

**Listening / transcript polish**
- "Listening…" feedback moves out of the page-flow card into a **floating pill above the tab bar** near the mic button. Page content no longer reflows on record.
- Lingering transcript bug: `VoiceCapture.transcript` was never cleared after `stopRecording()`, so the in-flow card stuck around. Fix: clear `transcript` (and `FoodLogProcessor.lastError`) once the entry is committed; pill auto-dismisses after a short fade.

**Accelerometer-driven gravity**
- `PhysicsBucketView` only (WaterlineView removed in PR #53). A shared `MotionGravityController` reads `CMMotionManager.deviceMotion.gravity` on the main run loop (~30 Hz) and maps it onto the bucket scene's `physicsWorld.gravity` so items roll/settle in the direction of real gravity as the user tilts the phone.

~~**Waterline settling — faster**~~ — WaterlineView removed in PR #53; tuning notes preserved for reference only.

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
| #25 | Matcher tightening + decomposition prompt + parser tests | T1 contains-match gate `> 0.5`; fuzzy refuses to bridge prep-method words; HEADLINE-CARB RULE in `decomposeIngredients`; 12 new parser tests. |
| #26 | GI-database alias wiring | Fixes a regression introduced by #25 — aliases (`pomegranate juice → pomegranate`) were being dropped at lookup. |
| #27 | Whole-grain matcher fidelity + emoji-resolver overhaul | "whole wheat bread" no longer collapses to "white bread"; `FoodEmoji.resolve` rewritten with priority cascade. |
| #28 | USDA expansion 377 → 501 + build script | `scripts/build_usda_nutrition.py` consumes FoodData Central CSVs; +124 curated entries. GI-DB coverage 367→488 / 776. |
| #29 | iOS-target matcher regression tests (`Tests/MatchingTests/`) | Real Core Data store; pins `bread →∅`, `chicken →∅`, `grilled chicken ↛ fried chicken`. (Plan A.5) |
| #30 | CI via GitHub Actions | `swift test` + `xcodebuild build` for iOS Simulator on every PR. (Plan A.3) |
| #31 | Core Data schema-change policy in CLAUDE.md | Documents the wipe-on-mismatch policy and when it must change (paid Apple Developer account / multi-user). (Plan A.4) |
| #32 | CI: iOS XCTest suite alongside the simulator build | `xcodebuild test` job added. |
| #33 | Haptic feedback in physics scenes | `UIImpactFeedbackGenerator(.light)` from SpriteKit contact callbacks in bucket / balance / waterline. (Plan B.7) |
| #34 | Settings sheet with editable daily GL budget | `AppSettings.dailyGLBudgetKey` + `@AppStorage`-driven UI; default 100, range 50–200, step 5. (Plan B.5) |
| #35 | Week-over-week comparison strip on Week tab | Second `@FetchRequest` for prior week, deltas surfaced via `WeekComparisonStrip`. (Plan B.10) |
| #36 | VoiceOver labels on emoji items in SpriteKit scenes | Each `SKLabelNode` now carries `accessibilityLabel`. (Plan B.8) |
| #37 | "Refine" affordance on low-confidence rows | Tap badge → search-style picker against `NutritionalProfile`; promote in two taps. (Plan B.9) |
| #38 | Lock-screen + StandBy widget variants | `accessoryRectangular`, `accessoryCircular`, `accessoryInline` added to `GlycoTrackWidget`. (Plan B.6) |
| #39 | Extract `ClaudeAPIClient` into `Modules/ClaudeAPI/` | No longer lives inside `TranscriptParser.swift`. (Plan C.12) |
| #40 | Unified logging via `os.Logger` | `Modules/Logging/Log.swift` exposes categorized loggers (`app`, `network`, `coreData`, `voice`, `notifications`); `print(...)` removed from production paths. (Plan C.11) |
| #41 | Encapsulate `Bundle.main.infoDictionary` lookups | `BuildInfo` / `AppInfo` follow the typed-accessor `APIKey` pattern. (Plan C.15) |
| #42 | Profile + batch first-launch seed | `PersistenceController.seedNutritionalProfiles()` runs on a background context with batched inserts. Also added `MotionGravityController` (accelerometer-driven gravity for Bucket + Waterline scenes). (Plan C.14) |
| #43 | SwiftLint integration with CI enforcement | `.swiftlint.yml` (force_unwrapping warning, line_length, function_body_length, large_tuple, cyclomatic_complexity); CI job blocks merges on errors. (Plan C.13) |
| #44 | UI refresh — simplify tabs, accelerometer gravity, restyled visuals | Detailed in the "UI Refresh — 2026-04-30" section above. Also routes deploy.sh build artifacts to the main repo root so worktree builds don't pollute the worktree. |
| #45 | Fix intermittent navigation title rendering on tab switches | Replaced `NavigationView` (deprecated in iOS 16+) with `NavigationStack` in all four primary tab roots. The bug was most visible on Week (3 `@FetchRequest`s + heaviest sub-tree) but the antipattern was in every tab. Sheet-level `NavigationView` instances inside Edit/Add flows are modal and not torn down on tab switch — left for a follow-up. |
| #46 | Voice transcripts: detect time context, backdate entries | `ParsedFood` gains optional `loggedAt: Date?`. Parser hands Claude a `Current time:` prefix so it can resolve "two hours ago", "yesterday at 5pm", "for breakfast", per-food ("toast at 8am and a banana at 10am"), etc. into absolute ISO-8601 timestamps. `FoodLogProcessor` stamps entries with `food.loggedAt ?? recordedAt` and clamps with `min(…, recordedAt)` against future-time drift. 6 new parser tests pin decoding, prompt rules, and the user-message contract. |
| #53 | Remove WaterlineView; remove GL×CL from Home tab; enlarge plot on Week/Month | `WaterlineView.swift` deleted entirely (buoyancy CL viz eliminated). `QuadrantPlotSection` removed from `HomeTabView` — Today tab now shows only GL bucket + CL balance scale. Plot height increased 200→320 on Week and Month tabs. Shared types (`SceneKeyCL`, `CLNetLabel`) migrated into `BalanceScaleView.swift`. Dead `selectedEntry` state and sheet wiring removed from `HomeTabView`. |

---

## Design vs Implementation Divergences (refreshed)

| DESIGN.md says | Implementation does | Rationale |
|---|---|---|
| GI + USDA DBs bundled as SQLite tables | JSON files seeded into Core Data at first launch | Simpler toolchain; no SQLite schema migration needed |
| Core Data `.xcdatamodeld` model file | Programmatic `NSManagedObjectModel` in Swift | Xcode 26 CDMFoundation bug crashes on any `.xcdatamodel` file |
| Tab 1 labelled "Home" | Tab labelled "Today" | More descriptive for a daily-logging app |
| Voice streams audio to Claude in real-time | Apple Speech → transcript → Claude parses text | `SFSpeechRecognizer` runs locally; Claude receives text only |
| Entry timestamp = `Date()` at log time (DESIGN §6.1: `loggedAt` separate from `timestamp`) | **Entry `timestamp` = `food.loggedAt ?? recordedAt`** — Claude resolves explicit/relative time phrases in the transcript ("two hours ago", "yesterday at 5pm", "for breakfast", per-food times) into absolute ISO-8601 stamps; transcripts with no time phrase still fall back to the recording time. PR #46. | Forced manual edits whenever a user logged retroactively; first-class time context turns "I had eggs two hours ago" into a usable entry without a follow-up tap. `loggedAt` is per-food so multi-food utterances with different times stay accurate. |
| Widget is strict mic button | Widget shows GL progress bar + mic deep-link | WidgetKit cannot access microphone |
| Color = food group; food groups have a 6-color palette (DESIGN §6.3, §8) | **Food groups removed entirely.** Each food renders as a single emoji via `FoodEmoji.resolve(entry:)`; tier/confidence tinting kept for the row badge only. | Color-coding by food group never communicated as much as the emoji identity itself; testing showed users read the emoji first. |
| GL × CL Quadrant is a 4-region plot in a modal sheet (DESIGN §8) | **Two-region plot embedded inline** on Week and Month tabs only (left/right, GL grows up from a 0 baseline); removed from Today tab in PR #53 | Lower half would be permanently empty (GL is unsigned); modal added a tap to no purpose; Today tab focuses on daily GL bucket + CL balance scale. |
| 5 tabs (Home/Week/Month/Log/Summary) inside the system `TabView` (DESIGN §9) | **4 tabs** (Today / Week / Month / Log) in a custom floating bar; record-button pill separated on the right; Settings / About / Debug consolidated into a `MoreSheet` reachable via a gear button on the Today tab. | Record action needed to be reachable from any tab; Summary tab + `SummaryGenerator` removed entirely (PR #44); Tug-of-War CL viz removed (PR #44). |
| Daily GL budget hardcoded to 100 (DESIGN §3.1) | **User-editable** via `AppSettings.dailyGLBudgetKey` (`UserDefaults`-backed `@AppStorage`, default 100, range 50–200, step 5) — surfaced in MoreSheet's Settings pane, observed across Today/Month/PeriodSummary chips. `GIEngineCore` keeps its own `dailyGLBudget` constant for unit-test stability. | PR #34 made the budget user-editable; the engine constant is intentionally separate so tests and UI evolve independently. |
| Tier 5 unrecognized foods (CLAUDE.md) | T5 returns GL=0/CL=0 with explicit "Not recognized" red badge | **Never** silently zero an unrecognized food into a high-confidence match; T5 is the load-bearing failure path. |

---

## Suggested Next Steps — superseded 2026-05-01

The "A. Reliability & data quality", "B. UX refinements", and "C. Engineering hygiene" sections from the previous revision have all shipped (PRs #25–#43; see Post-MVP Iterations table above). Status:

- ✅ A.1 USDA expansion (377 → 501) — #28
- ✅ A.2 TranscriptParserCoreTests — #25
- ✅ A.3 CI via GitHub Actions — #30, #32
- ✅ A.4 Core Data schema-change policy documented — #31 (full migration deferred until paid-team / multi-user, intentionally)
- ✅ A.5 iOS-side matcher regression tests — #29
- ✅ B.5 Editable daily GL budget — #34
- ✅ B.6 Lock-screen / StandBy widget — #38
- ✅ B.7 Haptics — #33
- ✅ B.8 VoiceOver — #36
- ✅ B.9 Refine affordance — #37
- ✅ B.10 Week-over-week strip — #35
- ✅ C.11 `os.Logger` — #40
- ✅ C.12 ClaudeAPIClient extraction — #39
- ✅ C.13 SwiftLint — #43
- ✅ C.14 Seed profiling/batching — #42
- ✅ C.15 `Bundle.main.infoDictionary` encapsulation — #41

D. and E. items below are preserved (deferred).

---

## Path to App Store — 2026-05-01 (active workstream)

Goal: **submit GlycoTrack 1.0 to the App Store**. The plan splits into (1) engineering work that lives in this repo and (2) deployment logistics that live in the user's Apple/business accounts. Both must converge before submission.

### 1. App-side engineering work (Claude / repo)

Ordered roughly by submission-blocker → polish.

#### 1A. Submission blockers

These will cause App Store Connect to reject upload or App Review to bounce the build.

1. ✅ **`PrivacyInfo.xcprivacy` added** (this PR). `GlycoTrack/PrivacyInfo.xcprivacy` and `GlycoTrackWidget/PrivacyInfo.xcprivacy` declare:
   - `NSPrivacyTracking = false`, no tracking domains.
   - `NSPrivacyCollectedDataTypes` — `OtherUserContent` (voice transcripts sent to Anthropic for parsing), not linked to user, not for tracking, purpose `AppFunctionality`. Widget collects nothing.
   - `NSPrivacyAccessedAPITypes` — `UserDefaults` (CA92.1) on both targets. No `FileTimestamp` / `SystemBootTime` usage in the codebase (verified).
   - Verified bundled into `.app` and `.appex` via `xcodebuild build -configuration Release`.

2. ✅ **`UILaunchScreen` replaced** (this PR). Now references `LaunchBackground` color asset (deep-blue brand color, sourced from `GL_BLUE` in `scripts/generate_app_icon.py`). Cold launch shows a solid brand color instead of a blank white frame. Logo image deferred — color-only is App-Store-acceptable for v1.0 and avoids needing a separate launch-logo asset.

3. ✅ **`UIRequiredDeviceCapabilities` fixed** (this PR). Key removed entirely (Apple infers from min iOS 16). Was previously `armv7`, which would fail binary-architecture validation.

4. ✅ **`ITSAppUsesNonExemptEncryption = false` added** (this PR). Standard exemption for HTTPS-only network use; avoids the per-build prompt in App Store Connect.

5. **Bump version + build numbers strategically.** `CFBundleShortVersionString = 1.0`, `CFBundleVersion = 1`. Move to a script-driven scheme (e.g. read from git tags) so each TestFlight upload increments `CFBundleVersion` automatically — App Store Connect rejects re-uploads with the same build number. **Deferred:** needs a design decision on the source-of-truth (git tags vs `agvtool` vs a bumped value in xcconfig).

6. **Decide on the widget.** Without App Groups (free team), the widget shows empty data. For App Store submission, either:
   - (a) Add `com.apple.security.application-groups` entitlement to both targets and bundle the suite name (paid program required) — and ship the widget as a real feature, OR
   - (b) Hide the widget extension from this 1.0 submission entirely (remove from `project.yml`'s app-extension target list), ship voice + visualizations only. Add it back in 1.1 once paid-team features are validated.

   Recommendation: **(b) for 1.0** — fewer review surfaces to defend, then add widget + lock-screen variants in a 1.1 follow-up once App Groups is enabled. **Deferred:** wait for paid-team enrollment decision before pulling the widget target out of the build.

7. ✅ **Release build validated** (this PR). `xcodebuild build -configuration Release -destination 'generic/platform=iOS Simulator'` builds clean against the new Info.plist + privacy manifests + asset-catalog color. Full archive against a device destination still pending paid-team enrollment (codesign needs a real Team ID).

#### 1B. App Review risk-reducers

These won't block upload but materially raise the chance of first-pass approval.

8. **Add a clear permissions-onboarding flow.** First launch should explain *why* we need mic + speech recognition before triggering the system permission alerts. Apple rejects apps that ask for sensitive permissions without context. A single "Welcome to GlycoTrack" sheet with a "Continue" button that then calls `requestAuthorization()` is enough.

9. **Add an in-app privacy policy + support contact.** App Store Connect requires a privacy policy URL, but the app should also link to it from the About pane (`MoreSheet`). Same for a support email. Without these, App Review treats the app as a dark pattern.

10. **Health-claim disclaimers.** GlycoTrack tracks "diabetes risk" / "heart disease risk" — language Apple's medical-app guideline (App Store Review Guideline 1.4) treats as a regulated claim. Either:
   - Soften copy across `AboutPaneView` and onboarding to describe GL/CL as *informational dietary metrics*, not medical-grade indicators, OR
   - Add a prominent "GlycoTrack is not a medical device. Consult your physician for diabetes / cardiovascular guidance." disclaimer at app launch and at the top of the About pane.

   Recommendation: do both. Soften DESIGN-doc-flavored copy in user-facing text + add a one-time disclaimer.

11. **Polish empty / error states.** Specifically:
    - Today tab on a freshly-installed phone with zero entries: currently shows an empty bucket with no explainer. Add a subtle "Tap the mic to log your first meal" hint.
    - Network failure during voice→Claude parse: currently surfaces only as a red `ListeningPill`. Add a gentle retry / fallback path.
    - First-launch seeding spinner: profiling landed in #42, but the user-visible state during the ~1–2s seed is ambiguous on cold install. Add a "Loading nutritional database…" overlay if the seed is in flight.

12. **Crash reporting.** Apple's Crashlytics surrogate (XCMetrics / xcrun crashes) is fine for v1.0 — no SDK needed. Make sure `UIApplicationMain` doesn't swallow exceptions silently. (Optional: add `os_log_fault` taps in known critical paths.)

13. **TestFlight metadata.** Beta App Description, Test Information notes ("To test voice logging, tap the mic and say 'two slices of toast'"), tester contact email. Lives in App Store Connect, but the prose lives in the repo as `docs/testflight_notes.md` for review-prep.

#### 1C. Optional polish (non-blocking, defer to 1.1 if time-pressed)

14. **HealthKit write integration** (existing PLAN D.16). Once paid team is set up, write daily GL / CL aggregates so they're consumable from the Watch / Health app. Requires `NSHealthUpdateUsageDescription`, entitlement, and an opt-in toggle in Settings.
15. **Background-refresh widget timeline** (existing D.18) — only relevant if 1A.6 chose path (a).
16. **Soft-delete cleanup job** (existing D.19) — pre-launch is the right time before users have ageing soft-deleted rows.
17. **Cohort export to CSV** (existing D.20) — also a useful App Review test path for reviewers who want to inspect the data structure.

### 2. User-side deployment logistics

These are things the user does in Apple/business accounts and a browser, not in code.

#### 2A. Apple Developer Program enrollment

- **Today's state:** the app is signed with a *free* Apple ID team — sufficient for sideload to your own iPhone (with 7-day cert expiry), but **cannot submit to TestFlight or the App Store**. This is the single biggest gating step.
- **Action:** enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) — $99/year.
  - **Individual** enrollment: simpler, faster (~24h), legal name appears on the App Store listing as the seller.
  - **Organization** enrollment: D-U-N-S Number required (free, ~1–2 week lead time via [dnb.com](https://www.dnb.com/duns-number/get-a-duns.html)), business legal name appears as seller. Choose this if you want a brand identity not tied to your personal name, or plan to add team members later.
  - **Recommendation:** if you have an LLC / sole proprietorship already, do Organization. Otherwise Individual is fine for v1.0; you can convert to Organization later (Apple supports it but the process is involved).
- Once enrolled, your Team ID (10-character alphanumeric) replaces the personal-team value in `GlycoTrack.local.xcconfig`. Re-add the speech-recognition + app-groups entitlements at that point.

#### 2B. App Store Connect setup

- **Reserve the bundle ID.** `com.glycotrack.app` is what the project uses. In App Store Connect → Certificates, IDs & Profiles → Identifiers, register this exact string. Reserve early — bundle IDs are first-come.
- **Reserve the app name.** App Store names are also first-come. "GlycoTrack" must be available on the App Store globally; check via [App Store search](https://apps.apple.com/us/app/) before locking in. Trademark is separate from App Store reservation; if you're serious about the brand, run a basic [USPTO TESS search](https://tmsearch.uspto.gov/) too.
- **Create the app record** in App Store Connect → Apps → "+" → New App. You'll need:
  - Platform: iOS
  - Bundle ID: the one you registered above
  - SKU: any unique string (e.g. `GLYCOTRACK_2026`)
  - Primary language: English (U.S.)

#### 2C. Required listing assets

- **App Icon** — already done (1024×1024 in `Assets.xcassets/AppIcon.appiconset/`).
- **Screenshots** — required at minimum for one device size:
  - **6.7" iPhone (15 Pro Max / 14 Pro Max)** — 1290×2796, up to 10 images.
  - **6.5" iPhone (11 Pro Max / XS Max)** — 1284×2778 or 1242×2688, up to 10 images. (Optional but improves coverage.)
  - **iPad** screenshots only required if your `TARGETED_DEVICE_FAMILY` includes iPad. Today it's `"1"` (iPhone-only) — keep it that way for v1.0.
- **App Preview video** — optional, but high-converting. 15–30 seconds, portrait, no system UI in shot.
- **Description** — up to 4,000 characters. Should explain GL vs CL in plain language, walk through voice logging, and end with a soft disclaimer.
- **Keywords** — 100 characters, comma-separated. Candidates: `glycemic,cholesterol,diabetes,heart,food,log,nutrition,GL,CL,diet`.
- **Promotional Text** — 170 characters; updateable without resubmitting. Use for "What's new in 1.0" / launch-week messaging.
- **Category** — primary: Health & Fitness. Secondary: Food & Drink.
- **Age rating** — fill out the questionnaire. Likely 4+ (no objectionable content) but the medical-information question may push it to 12+ ("infrequent/mild medical/treatment information").

#### 2D. Required URLs (host these somewhere)

- **Privacy policy URL** — *required*. Cannot ship without one. Minimum cover: what data the app collects (voice transcripts → Anthropic, nothing else server-side), what stays on-device, no third-party tracking, Anthropic's data-handling link. A static GitHub Pages page is sufficient. [Iubenda](https://www.iubenda.com/) generates compliant text for ~$30/yr if you don't want to write it yourself.
- **Support URL** — *required*. A simple GitHub Pages page or a `mailto:` redirect is sufficient.
- **Marketing URL** — optional. Skip for v1.0.

#### 2E. Export compliance + tax

- **Encryption export compliance.** GlycoTrack uses HTTPS (Anthropic API + Apple Speech). Standard Apple exemption applies. Set `ITSAppUsesNonExemptEncryption = false` in `Info.plist`. (Avoids the per-build prompt in App Store Connect.)
- **Tax + banking forms.** Required even for a free app you don't intend to monetize, because Apple wants you to be eligible to accept payment if you change your mind. Goes in App Store Connect → Agreements, Tax, and Banking. Free apps need only the Free Apps agreement signed.

#### 2F. App Review information

- **Demo account credentials** — n/a (no login).
- **Notes for reviewer** — write a short note explaining: "GlycoTrack is voice-first. To test, tap the mic on the Today tab and say 'I had a slice of toast and a glass of orange juice.' The app uses the Anthropic Claude API to parse the transcript; an API key is bundled with the build for review purposes."
- **Review API key** — Apple's review pipeline calls your network endpoints. Make sure your Anthropic API key has enough quota for review traffic (probably <100 calls).

### 3. Basic launch sequence (recommended order)

```
Week 0  →  Decide on Individual vs Organization Apple Developer enrollment.
            (If Organization, kick off D-U-N-S now — 1-2 week lead time.)
Week 1  →  Pay $99, complete Apple Developer enrollment.
            In parallel: ship engineering items 1A.1–1A.6 (privacy manifest,
            launch screen, armv7 fix, version scheme, widget decision,
            release-build validation).
Week 2  →  Ship engineering items 1B.7–1B.10 (onboarding, disclaimers,
            empty/error states). Set up TestFlight in App Store Connect.
            Recruit 5–10 beta testers (friends + family + r/diabetes Reddit).
Week 3-5 → TestFlight beta (Internal first, then External). Iterate on
            feedback. Fix any reviewer-blocking findings.
Week 6  →  Prepare metadata: screenshots, description, privacy policy URL,
            support URL. Submit for App Review.
            (Median review time as of 2026: 24-48 hours, occasionally up to
            a week.)
Week 6+ → If approved: schedule release for the date you want. If
            rejected: read the reviewer note carefully, iterate, resubmit
            (each round is 1-2 days).
```

### 4. Post-launch backlog (preserves D + E from previous revision)

| Item | Notes |
|---|---|
| **D.16 HealthKit write** | Daily GL/CL aggregate to HealthKit. Paid team gated. |
| **D.17 Apple Watch complication** | Tiny WatchKit target sharing the App Group. |
| **D.18 Background widget refresh** | Conditional on shipping the widget at all (1A.5). |
| **D.19 Soft-delete cleanup** | Hard-delete `isSoftDeleted == true` rows older than 30 days. |
| **D.20 CSV export** | Files-app integration. Useful for App Review too. |
| **E.21 Photo-based food logging** | Vision + Claude vision API. DESIGN §17. |
| **E.22 On-device food-name embedding** | Replace Levenshtein with semantic match in T1/T2. |

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
