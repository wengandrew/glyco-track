# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Branching & Workflow

**Branch model:**
- `main` — stable, tested builds only
- `develop` — integration branch; always what gets built and tested on device
- Feature branches — one per Claude session, branched off `develop`

**The root repo (`/Users/ampere/code/glyco-track`) is always checked out to `develop`.** This is the Xcode build target for device testing. Do not check out `main` or a feature branch at the root.

**Every session must:**
1. Sync with remote before writing any code: `git fetch origin && git rebase origin/develop`
2. Branch off `develop` (not `main`) at the start
3. Do all work in the session's worktree on that feature branch
4. **Update `PLAN.md` (and `CLAUDE.md` if behaviour changed) before opening a PR.** A pre-tool-use hook blocks `gh pr create` if `PLAN.md` is unmodified on the branch — fix the docs, then open the PR.
5. When work is complete, open a PR targeting `develop` (not `main`) — **do not build or deploy locally**
6. Never merge directly to `develop` or `main` — always via PR

**Build to verify, but do not deploy.** Claude MAY run `xcodebuild` (or `xcodegen generate && xcodebuild`) with a `build` action for the iOS Simulator destination to verify compilation before opening a PR. Claude MUST NOT run `./scripts/deploy.sh` or any command that installs the app on device — deployment to the user's iPhone is the user's job, after reviewing the PR. Safe verification command:

```bash
xcodebuild -project GlycoTrack.xcodeproj -scheme GlycoTrack \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

If the build fails, fix the compile errors before opening (or updating) the PR. Never use `-allowProvisioningUpdates`, `install`, or any device destination.

**Active feature branches (update this as PRs open/merge):**
<!-- Add a line per open PR: - [branch-name]: brief description -->

**Cross-session awareness:** Before starting work, run `git log develop --oneline -20` to see what's already landed. Check open PRs on GitHub for what's in flight but not yet merged.

**Worktree sync rule — do this at the start of every session in a worktree:**
```bash
git fetch origin
git rebase origin/develop
```
Worktrees do not auto-track their base branch. If new PRs land on `develop` after the worktree was created, the worktree branch stays frozen at its creation point. Failing to rebase means you build and test against stale code for the entire session, and only discover the drift at PR time. Rebase early, not just before opening the PR.

## Design Philosophy

**This is an app for users, not engineers.**

- **Never surface algorithm internals.** Users should not see tier labels (T1, T2, etc.), match method names, or confidence scores in the main UI. These are implementation details. If an entry's confidence is low, that's the algorithm's problem to solve, not the user's — flag it quietly in a details view if at all.
- **Never make the user fix the algorithm's mistakes.** Do not add "Refine match," "Override," or similar escape hatches that ask the user to do what the matching engine should have done automatically. If the algorithm gets it wrong, improve the algorithm.
- **Reduce, don't expose.** When a feature exists to compensate for a technical limitation, remove the feature and fix the limitation instead.
- **Fewer options, more confidence.** A well-designed app makes the right choice obvious, not the user's responsibility. Prefer single clear actions over menus with multiple paths.

## Behavior

- **Ask before assuming.** When a task has multiple reasonable approaches (e.g. a new visualization style, a data model change, a refactor), ask a clarifying question first. Don't assume the user knows the tradeoffs — explain the options briefly and ask which direction they prefer.
- **Build to verify, never deploy.** You MAY run `xcodebuild … build` against the iOS Simulator destination to catch compile errors before PR. Do NOT run `deploy.sh` or any install/device command — that's the user's step.

## Build & Test Commands

These are for the user's reference, not for Claude to run autonomously.

```bash
# Deploy to connected iPhone (user runs this after merging a PR)
./scripts/deploy.sh                       # auto-detects device, regens + builds + installs
./scripts/deploy.sh --no-launch           # install without launching
./scripts/deploy.sh --clean               # clean build first
./scripts/deploy.sh --no-regen            # skip xcodegen (faster, only when no files changed)

# Run unit tests (pure Swift, no device needed — covers GI/CL engine math)
swift test
swift test --filter GIEngineTests/testWhiteRiceGL
```

The `project.pbxproj` is committed and tracked. After adding or removing Swift files, run `xcodegen generate` and commit the updated `project.pbxproj`. The `contents.xcworkspacedata` file is also tracked — do not delete it.

## TestFlight / Beta Distribution

### Prerequisites (one-time account setup)
1. Enroll in the **Apple Developer Program** at developer.apple.com ($99/year)
2. In **App Store Connect → My Apps → "+"**, create a new app with bundle ID `com.glycotrack.app`
3. Add your team ID to the gitignored local xcconfig:
   ```
   echo 'DEVELOPMENT_TEAM = XXXXXXXXXX' >> GlycoTrack/Config/GlycoTrack.local.xcconfig
   ```
   Find your 10-character team ID at developer.apple.com → Membership.

### Building a TestFlight build
```bash
# Produces build/GlycoTrack.ipa (Release config, App Store signing)
./scripts/archive.sh
```

### Uploading to TestFlight
After `archive.sh` succeeds, upload via either:
- **Xcode Organizer**: Window → Organizer → select the archive → Distribute App → App Store Connect → Upload
- **Transporter** (Mac App Store): drag in the `.ipa`
- **altool CLI**: `xcrun altool --upload-app -f build/GlycoTrack.ipa -t ios --apiKey <key> --apiIssuer <issuer>`

### Inviting testers
In App Store Connect → TestFlight → add tester emails. They receive an invite to install the TestFlight app and join the beta.

### Build number
Apple rejects uploads with a duplicate build number. Bump `CFBundleVersion` in `GlycoTrack/Info.plist` before each new upload (e.g. 1 → 2 → 3). `CFBundleShortVersionString` (the marketing version like "1.0") only needs to change for user-facing releases.

## Architecture

### Dual-axis health tracking

The app tracks two independent metrics per food entry:
- **GL (Glycemic Load)** — always unsigned (≥ 0). Daily budget = 100. Formula: `(GI × carbs_grams) / 100`.
- **CL (Cholesterol Load)** — signed. Positive = harmful (sat/trans fat), negative = beneficial (fiber, PUFA, MUFA). Formula: `(SFA×1.0) + (TFA×2.0) − (fiber×0.5) − (PUFA×0.7) − (MUFA×0.5)`.

Both values are stored directly on `FoodLogEntry` as `computedGL` and `computedCL`.

### Two parallel module systems

The engines exist twice — once for testability, once for iOS:

| SPM target (testable, Linux-compatible) | iOS app wrapper |
|---|---|
| `Sources/GIEngineCore/` | `GlycoTrack/Modules/GIEngine/GIEngine.swift` |
| `Sources/CLEngineCore/` | `GlycoTrack/Modules/CLEngine/CLEngine.swift` |
| `Sources/TranscriptParserCore/` | `GlycoTrack/Modules/TranscriptParser/TranscriptParser.swift` |

The iOS wrappers mirror the SPM API exactly. Tests run against the SPM targets via `swift test`. When changing engine logic, update **both** copies.

### Voice → Core Data pipeline

```
VoiceCapture (SFSpeechRecognizer, on-device)
  → transcript string
  → FoodLogProcessor.process(transcript:context:)         [HomeTab/FoodLogProcessor.swift]
    → TranscriptParser.parse(transcript:, currentTime:)
        → [ParsedFood] each carrying optional `loggedAt: Date?`
    → FoodMatcher.resolve(food:) → FoodResolution          [Modules/Matching/FoodMatcher.swift]
        T1  NutritionalRepository.findBestMatch()  — exact / contains / fuzzy whole-name
        T2  NutritionalRepository.findComponents() — reverse-substring decomposition
        T3  TranscriptParser.decomposeIngredients() → Claude API → per-ingredient DB lookup
        T4  T3 + T2 fallback for unresolved ingredients
        T5  unrecognized → GL = 0, CL = 0, red badge
    → FoodLogRepository.create(timestamp: food.loggedAt ?? recordedAt, …)
        → FoodLogEntry (computedGL, computedCL, tier, confidence)
```

`FoodLogProcessor` is `@MainActor ObservableObject`. `FoodMatcher`, `NutritionalRepository`, and `FoodLogRepository` are all `@MainActor` — see the Core Data threading rule below.

#### Time-context resolution (`ParsedFood.loggedAt`)

`TranscriptParser.parse(transcript:, currentTime:)` hands Claude a
`"Current time: <ISO-8601>\nTranscript: …"` user message. Claude is
prompted to populate `loggedAt` **only** when the transcript contains a
detectable time phrase ("two hours ago", "yesterday at 5pm", "for
breakfast", "this morning at 9am") and to **omit** the field otherwise.
`FoodLogProcessor` then stamps the entry with
`food.loggedAt ?? recordedAt`, where `recordedAt` is captured **once**
at the top of `process()` so every food in the same recording shares a
single "now" anchor.

Two invariants guard this path — don't regress them:

1. **Defensive future-time clamp.** Even though the prompt forbids
   `loggedAt > currentTime`, the processor applies
   `min(food.loggedAt, recordedAt)` as a belt-and-suspenders guard.
   Keep this — Claude's prompt-following on time arithmetic isn't
   bulletproof and a future-stamped entry would scramble the
   "navigating into the future" guards in `HomeTabView` /
   `WeekTabView`.

2. **Tolerant decoding never throws.** Omitted field, explicit `null`,
   or unparseable string all yield `nil` — never `throw`. Falling back
   to the recording time is always preferable to dropping the entry,
   and the parser tests
   (`testParseTreatsExplicitNullLoggedAtAsNil`,
   `testParseIgnoresMalformedLoggedAtString`) pin this behavior.

The `loggedAt` field is also Equatable+Codable so the SPM core's
`ParsedFood` can be shipped through any future serialization layer
without losing the time context.

### GL/CL computation accuracy — critical rules

Getting these numbers right is the core purpose of the app. Several failure modes have been found and fixed; do not reintroduce them.

**1. Never log an unrecognized food.**
If matching fails, `FoodLogProcessor` skips the entry entirely and sets `lastError` to name the unrecognized food(s) so the user can re-try with a more specific description. Logging a GL=0/CL=0 entry would silently corrupt daily totals. The `MatchTier.unrecognized` (T5) case is still returned by `FoodMatcher` as a sentinel; it is `FoodLogProcessor`'s responsibility to filter it out before calling `FoodLogRepository.create`.

**2. USDA-only entries with real carbs must use GI = 55, not GI = 0.**
`NutritionalProfile.glycemicIndex == 0` means "no Sydney GI entry", not "zero GI". If `carbsPer100g > 3` and `glycemicIndex == 0`, substitute GI = 55 (medium) before computing GL. Noodles and grains without a GI entry would otherwise report GL = 0.

**3. Composite dishes must be decomposed; GL/CL are summed across components.**
`GL_total = Σ (GI_i × carbs_i_in_serving) / 100` across resolved components. A single direct lookup on "beef noodle soup" will fail; the cascade is what makes composite dishes work.

**4. Claude's ingredient gram estimates must be normalized to the user's actual serving size.**
`decomposeIngredients` allows ±15% total mass error. Always scale: `scaledGrams = ing.grams × (totalGrams / sum(ingredients.grams))` before computing GL/CL, so the result tracks the actual portion.

**5. Word-boundary matching must be applied at every substring site.**
Short food names ("egg", "ale", "oat", "tea") appear as raw substrings inside unrelated words ("veggie", "kale", "bloated", "steak"). Both T1's contains-check (`fetchDBNameContainsQuery`) and T2's `findComponents` use `_wordBoundaryContains` — do not replace these with plain `String.contains`.

**6. T1 contains-match requires a word-count ratio gate (≥ 50%).**
Even after word-boundary checks pass, a short generic query can spuriously match a long DB entry whose first word happens to be that query ("sugar" → "sugar snap peas", "apple" → "apple cider vinegar"). `fetchDBNameContainsQuery` enforces that the query must cover at least 50% of the DB entry's word count. "white rice" / "steamed white rice" = 67% → accepted. "sugar" / "sugar snap peas" = 33% → rejected, falls through to T2/T3.

### Core Data threading — @MainActor required

`PersistenceController.shared.context` is a main-queue `NSManagedObjectContext`. Per SE-0338, non-isolated `async` functions run on the cooperative pool (not the caller's actor), so any Core Data fetch inside an unannotated async function is a threading violation that crashes intermittently.

**`NutritionalRepository`, `FoodLogRepository`, and `FoodMatcher` are all `@MainActor`.** Keep them that way. Adding a new class that touches the main context? Mark it `@MainActor` too. The network `await` inside `FoodMatcher.resolve` (Claude API call) still suspends cleanly — UI remains responsive.

### SwiftUI + Core Data observation

Use `@ObservedObject var entry: FoodLogEntry` (not `let`) in any view that displays a Core Data object's properties directly. `NSManagedObject` conforms to `ObservableObject` and fires `objectWillChange` on every property save. With `let`, SwiftUI never subscribes and the row won't update when the entry is edited.

### Core Data model

There is **no `.xcdatamodeld` file**. The schema is defined programmatically in `GlycoTrack/Models/GlycoTrackManagedObjectModel.swift` to work around an Xcode 26 CDMFoundation crash. To add or rename an attribute, edit `GlycoTrackManagedObjectModel.swift` and the corresponding `FoodLogEntry+CoreDataProperties.swift` or `NutritionalProfile+CoreDataProperties.swift`. Soft-delete is via `isSoftDeleted` (not `isDeleted`, which conflicts with `NSManagedObject`).

#### Schema-change policy: wipe-on-mismatch

The programmatic model means **schema changes are not auto-migratable**. There's no `.xcdatamodel` for Core Data to diff against the persistent store; `NSPersistentContainer.loadPersistentStores` will fail with an incompatibility error (or, worse, succeed and silently corrupt) if the in-code schema drifts from what's on disk.

**Current policy: any schema change wipes local data on the developer's device.** Acceptable today because (a) there's no paid Apple Developer Program account yet, so App Store distribution isn't possible; (b) the only "real" install is the user's sideloaded build, which already gets reinstalled weekly when the 7-day sideload cert expires; (c) the GI/USDA reference data re-seeds from JSON on a fresh store, and `FoodLogEntry` history is the only durable user data and is small enough to be re-loggable.

**When to revisit:** the moment any of these change, this policy needs a real migration plan:
- Paid Apple Developer Program account → TestFlight or App Store distribution
- Multiple users with retained logs they care about
- A schema change that's not purely additive (renames, deletes, type changes)

**Checklist when changing the schema today:**
1. Edit `GlycoTrackManagedObjectModel.swift` — add the `NSAttributeDescription` to the right entity, set `isOptional`, `attributeType`, `defaultValue`.
2. Edit the corresponding `+CoreDataProperties.swift` so the Swift API matches.
3. Bump nothing — there is no version number to bump, and there is no migration to write.
4. Tell the user (or document in the PR) that the next build wipes their local store on first launch. The next launch after that re-seeds the reference databases automatically.
5. If you're worried about losing logged entries, export them via the Debug tab first (or run a one-time migration script before the schema change lands).

**When we eventually need real migrations,** the most likely path is:
- Switch to a real `.xcdatamodeld` (assuming the Xcode 26 CDMFoundation bug is fixed by then)
- Add `NSPersistentContainer` migration options: `NSMigratePersistentStoresAutomaticallyOption: true`, `NSInferMappingModelAutomaticallyOption: true`
- Add a versioned model document with each schema change, or write `NSMappingModel`s for non-inferrable changes
- Add a migration test (boot a known-old store, verify it migrates and reads correctly)

Don't preemptively write any of that — adding it now without a forcing function would just be infrastructure to maintain. The wipe-on-change policy is the right default until real users with retained data exist.

### Reference databases

Two JSON files are bundled as app resources and seeded into Core Data at first launch by `PersistenceController.seedNutritionalProfiles()`:
- `gi_database.json` — 782 foods with GI values, aliases, and optional `carbs` field (Sydney GI Database)
- `usda_nutrition.json` — 516 foods with fat/fiber macros (USDA FoodData Central)

The seeding code merges these by exact name: `usda?.carbs ?? gi.carbs ?? 0`. The `carbs` field on GI entries serves as a fallback when no USDA entry matches by name, preventing GL=0 on carb-heavy foods that only exist in the GI database. Foods with no USDA match get CL = 0. Foods with no GI match fall back to GI = 55 (tier 3, confidence 0.35).

**7. Fuzzy matching uses normalized edit distance, not absolute threshold.**
`fetchFuzzy` in `NutritionalRepository` requires `levenshtein(a, b) / max(len(a), len(b)) <= 0.30` in addition to the absolute `d <= 3` cap. This prevents short food names from matching unrelated words at low absolute distance (e.g., "milk"→"elk" at d=2 is 50% normalized — rejected). The prep-method guard (no fuzzy bridging across grilled/fried/etc.) still applies.

### Visualizations

All visualization views live under `GlycoTrack/UI/Visualizations/`.

- **GL views** (unsigned, budget-based): `PhysicsBucketView` (SpriteKit physics — the only daily GL view), `WeeklyRiverView`, `MonthlyHeatmapView`.
- **CL views** (signed, ±): `BalanceScaleView` (SpriteKit physics — pinned beam). `TugOfWarBarView` was removed in PR #44.
- **Combined**: `QuadrantPlotSection` (CL on X, GL on Y) — embedded on Week and Month tabs only (not the Home/Today tab). Despite the legacy "Quadrant" name, this is a **two-region** plot: only CL is signed, so the chart splits left/right at CL = 0 (left = beneficial, right = harmful) and grows upward from a GL = 0 baseline. Do not re-introduce a four-quadrant grid — the lower half would be permanently empty and would mislead readers into thinking "negative GL" is meaningful.

`HomeTabView` shows a date navigator (chevrons + swipe left/right on the viz sections) that drives an `@FetchRequest` with a dynamic predicate for the selected day. Forward navigation is capped at today.

**Date-scoped physics scenes must use `.id(SceneKey)` on a child host view that constructs its scene at init.** `PhysicsBucketView` and `BalanceScaleView` each accept a `dateKey: Date?` init param and each contain a small private host view (`BucketSceneHost`, `BalanceSceneHost`). The host owns the SKScene as `@State`, initialized synchronously from `entries` in its `init`. The parent applies `.id(key)` to the host where the key struct includes all reactive inputs for that scene — e.g. `SceneKey(replay, dayKey, entryIDs, width, height, budget)` for the bucket (budget changes geometry) and `SceneKeyCL(replay, dayKey, entryIDs, width, height)` for the balance scale. SwiftUI tears down and re-inits the host whenever any key field changes, and the new init reads the latest `entries` passed in.

**Do not** use `.task(id:)` to write the scene to a parent's `@State`, and **do not** bump a UUID `sceneID` in `.onChange(of: entryIDs)` / `.onChange(of: dayKey)`. Both patterns failed in production:

  1. `.task(id:)` with a synchronous body has no cancellation checkpoints, so when two tasks (stale + fresh) are scheduled in quick succession their finish order is undefined — the stale task can land last and overwrite the fresh scene. User-visible bug: viz "always one day behind on swipe."
  2. The `.onChange` UUID-bump pattern has a SwiftUI render-order race: `@FetchRequest`'s predicate update happens in a sibling `.onChange(of: selectedDate)` whose ordering relative to the child's `.onChange(of: dayKey)` is not guaranteed, so the UUID could be bumped during a render that still held yesterday's entries.

The `.id`-on-child-host pattern dodges both: SwiftUI's view-identity-reset semantics force a fresh `init` call with the current `entries` parameter, all on the main thread inside body evaluation. No async, no race. Keep `replayNonce: UUID` only for cases where inputs don't change (Replay button, view re-appearance). If you add a new date-scoped SpriteKit scene, follow the same pattern.

**Area-proportional encoding.** Every visualization encodes GL (or |CL|) as the area of its food graphic. In `PhysicsBucketView`, the bucket's interior area is sized at scene-init so that `budget * areaPerUnit ≈ 78%` of bucket area — i.e. a full 100-GL day fills the bucket and items above that spill over the rim. CL views use a fixed `areaPerCLUnit` tuned per-view. For CL, sign is encoded by position (harmful = top/right, beneficial = bottom/left), never by area.

**Food emojis.** `FoodEmoji.resolve(entry:)` maps a `FoodLogEntry` to a single emoji via (1) exact match in `food_emoji_map.json` on `referenceFood` or `foodDescription`, then (2) a keyword classifier in `FoodEmoji.swift`. Low-confidence matches (`confidenceScore < 0.3`) always return ❓ — never fabricate a high-confidence emoji for an unknown food, same rule as GL/CL. Visualizations use `FoodGraphic` (SwiftUI) or an `SKLabelNode` with the emoji (SpriteKit); both size the glyph so its drawn area is proportional to the passed magnitude. The emoji is the sole visual identifier for a food — the `FoodGroup` classification (formerly colored circles / tinted tokens) was deleted entirely. `FoodEntryDetailSheet`'s header also uses `FoodEmoji.resolve(entry:)` — keep it that way; do not re-introduce food-group coloring anywhere. Tier/confidence coloring (e.g. `ConfidenceBadge` in `FoodLogRowView`) is unrelated and retained.

**Replay triggers.** Physics scenes in `PhysicsBucketView` and `BalanceScaleView` rebuild (replaying the drop animation) when (a) the view appears — `.onAppear { replayNonce = UUID() }`, (b) the entry list changes — automatic via `entryIDs` being part of the scene key, (c) the displayed day changes — automatic via `dayKey` being part of the scene key, (d) the user taps Replay — bumps `replayNonce`. The scene key is wired into `.id(key)` on a private host view; the host's `init` constructs the scene from the current `entries` synchronously. See "Date-scoped physics scenes" above for why this pattern is required (other approaches deadlock on async ordering or SwiftUI render-order races).

**Unified entry-interaction flow.** Every tap — visualization item, Log-tab row, river item, quadrant dot — opens `FoodEntryDetailSheet` first. The sheet shows an emoji header, prominent timestamp, GL/CL, and raw transcript. The toolbar has two direct buttons: a pencil (Edit) that presents `EditEntryView`, and a trash (Delete) that shows a confirmation dialog and soft-deletes. Never open `EditEntryView` directly from a tap — always go through the detail sheet. `FoodEntryDetailSheet` uses `@ObservedObject var entry` so it refreshes after an edit.

`EditEntryView` includes a timestamp `DatePicker` (rounded to 30-minute intervals on Save, constrained to `...Date()` so users can't log future entries).

### Build info (debug tab)

`GlycoTrack/Config/BuildInfo.generated.swift` is regenerated by `scripts/inject_build_info.sh` (git branch, short commit with `-dirty` marker, UTC timestamp). `AppInfo` (`GlycoTrack/Config/AppInfo.swift`) exposes this plus `CFBundleShortVersionString` / `CFBundleVersion`. `DebugTabView` surfaces it in the "Build Info" section along with the last-data-update timestamp. `scripts/deploy.sh` calls `inject_build_info.sh` before `xcodegen generate`, so every device install gets fresh values. The generated file is committed so clean checkouts still compile.

### Reusable period components

- `PeriodSummaryView(title:, entries:, daysInPeriod:)` — single summary card used by both Week and Month tabs. Shows Avg Daily GL, Total GL, Net CL. Days-logged and "N entries need review" warnings were removed deliberately — do not reintroduce them.
- `QuadrantPlotSection(entries:, onTap:)` — embeddable GL × CL two-region plot (left = beneficial CL, right = harmful CL, GL up); host owns the `selectedEntry` state and `.sheet(item:) { FoodEntryDetailSheet(entry:) }` wiring.

### App icon

Lives in `GlycoTrack/Resources/Assets.xcassets/AppIcon.appiconset/`. Modern Xcode asset catalog: a single 1024×1024 universal source PNG (`AppIcon-1024.png`); the asset catalog compiler synthesizes all device sizes at build time. The PNG is generated by `scripts/generate_app_icon.py` (Pillow) so the design is reproducible and edits are diff-friendly — re-run the script after tweaking colors or geometry. `project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` so the build picks it up automatically; do not also set `CFBundleIcons*` in `Info.plist` (would conflict).

### API key

`CLAUDE_API_KEY` is injected via `GlycoTrack/Config/GlycoTrack.xcconfig` (committed stub) which includes the gitignored `GlycoTrack.local.xcconfig`. The key reaches the app via `Info.plist` → `Bundle.main.infoDictionary?["CLAUDE_API_KEY"]`. Never hardcode it.

### Xcode 26 quirks

- `navigationTitle(_:displayedComponents:)` is removed — use `navigationTitle(someString)` or `navigationTitle(date.formatted(...))`.
- `.fill(...).stroke(...)` chain requires iOS 17 — use `.fill(...).overlay(stroke(...))` instead.
- No `.xcdatamodeld` file — Core Data model is fully programmatic (see above).
- `isSoftDeleted` (not `isDeleted`) — `NSManagedObject` already has `isDeleted`.
