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
4. When work is complete, open a PR targeting `develop` (not `main`) — **do not build or deploy locally**
5. Never merge directly to `develop` or `main` — always via PR

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
    → TranscriptParser.parse() → [ParsedFood]
    → FoodMatcher.resolve(food:) → FoodResolution          [Modules/Matching/FoodMatcher.swift]
        T1  NutritionalRepository.findBestMatch()  — exact / contains / fuzzy whole-name
        T2  NutritionalRepository.findComponents() — reverse-substring decomposition
        T3  TranscriptParser.decomposeIngredients() → Claude API → per-ingredient DB lookup
        T4  T3 + T2 fallback for unresolved ingredients
        T5  unrecognized → GL = 0, CL = 0, red badge
    → FoodLogRepository.create() → FoodLogEntry (computedGL, computedCL, tier, confidence)
```

`FoodLogProcessor` is `@MainActor ObservableObject`. `FoodMatcher`, `NutritionalRepository`, and `FoodLogRepository` are all `@MainActor` — see the Core Data threading rule below.

### GL/CL computation accuracy — critical rules

Getting these numbers right is the core purpose of the app. Several failure modes have been found and fixed; do not reintroduce them.

**1. Never silently return GL = 0 / CL = 0 for an unrecognized food.**
If matching fails, return `MatchTier.unrecognized` (T5) with explicit zeros and a red "Not recognized" badge. A false high-confidence match with zeroed values is worse than admitting failure — it silently corrupts daily totals.

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

### Reference databases

Two JSON files are bundled as app resources and seeded into Core Data at first launch by `PersistenceController.seedNutritionalProfiles()`:
- `gi_database.json` — 776 foods with GI values and aliases (Sydney GI Database)
- `usda_nutrition.json` — 377 foods with fat/fiber macros (USDA FoodData Central)

Foods with no USDA match get CL = 0. Foods with no GI match fall back to GI = 55 (tier 3, confidence 0.35). The USDA set is intentionally small (design target was 7,793) — expansion is a known post-MVP gap.

### Visualizations

All visualization views live under `GlycoTrack/UI/Visualizations/`.

- **GL views** (unsigned, budget-based): `PhysicsBucketView` (SpriteKit physics — the only daily GL view), `WeeklyRiverView`, `MonthlyHeatmapView`.
- **CL views** (signed, ±): `TugOfWarBarView` (SwiftUI stacked bar), `WaterlineView` (SpriteKit physics — buoyancy), `BalanceScaleView` (SpriteKit physics — pinned beam).
- **Combined**: `QuadrantPlotSection` (CL on X, GL on Y) — embedded directly on Today, Week, and Month tabs (no modal sheet wrapper). Despite the legacy "Quadrant" name, this is a **two-region** plot: only CL is signed, so the chart splits left/right at CL = 0 (left = beneficial, right = harmful) and grows upward from a GL = 0 baseline. Do not re-introduce a four-quadrant grid — the lower half would be permanently empty and would mislead readers into thinking "negative GL" is meaningful.

`HomeTabView` shows a date navigator (chevrons + swipe left/right on the viz sections) that drives an `@FetchRequest` with a dynamic predicate for the selected day. Forward navigation is capped at today.

**Date-scoped physics scenes must take a `dateKey` AND derive their scene key purely from inputs.** `PhysicsBucketView`, `BalanceScaleView`, and `WaterlineView` each accept a `dateKey: Date?` init param. The `.task(id:)` and SpriteView `.id(...)` are both keyed off a `SceneKey` struct that contains `(replayNonce, dayKey, entryIDs, width, height)`. **Do not** revert to a UUID-based `sceneID` bumped by `.onChange(of: entryIDs)` / `.onChange(of: dayKey)` — that pattern has a SwiftUI render-order race: the UUID can be bumped during a render that still captured stale `entries` (because `@FetchRequest`'s predicate update happens in a sibling `.onChange` whose ordering is not guaranteed), producing a scene built from the previous day's items that then sticks because the id never changes again. Deriving the key from `dayKey + entryIDs` directly means the `.task` re-runs whenever entries change, regardless of `.onChange` ordering, and the closure always captures the freshest `self`. Keep `replayNonce: UUID` only for the cases where inputs don't change (Replay button, view re-appearance). If you add a new date-scoped SpriteKit scene, follow the same pattern.

**Area-proportional encoding.** Every visualization encodes GL (or |CL|) as the area of its food graphic. In `PhysicsBucketView`, the bucket's interior area is sized at scene-init so that `budget * areaPerUnit ≈ 78%` of bucket area — i.e. a full 100-GL day fills the bucket and items above that spill over the rim. CL views use a fixed `areaPerCLUnit` tuned per-view. For CL, sign is encoded by position (harmful = top/right, beneficial = bottom/left), never by area.

**Food emojis.** `FoodEmoji.resolve(entry:)` maps a `FoodLogEntry` to a single emoji via (1) exact match in `food_emoji_map.json` on `referenceFood` or `foodDescription`, then (2) a keyword classifier in `FoodEmoji.swift`. Low-confidence matches (`confidenceScore < 0.3`) always return ❓ — never fabricate a high-confidence emoji for an unknown food, same rule as GL/CL. Visualizations use `FoodGraphic` (SwiftUI) or an `SKLabelNode` with the emoji (SpriteKit); both size the glyph so its drawn area is proportional to the passed magnitude. The emoji is the sole visual identifier for a food — the `FoodGroup` classification (formerly colored circles / tinted tokens) was deleted entirely. `FoodEntryDetailSheet`'s header also uses `FoodEmoji.resolve(entry:)` — keep it that way; do not re-introduce food-group coloring anywhere. Tier/confidence coloring (e.g. `ConfidenceBadge` in `FoodLogRowView`) is unrelated and retained.

**Waterline buoyancy contract.** `WaterlineView` uses explicit `floatCategory` and `sinkCategory` physics-category bitmasks — set on BOTH branches when creating each item's body. Do not rely on the default mask (`0xFFFFFFFF`), which matches every category and leaks lift onto items that should sink. **Beneficial CL (negative) → `floatCategory`**, low effective density, gets upward Archimedean force scaled by submerged depth → rises to the surface. **Harmful CL (positive) → `sinkCategory`**, higher density, gets a mild extra downward nudge → settles on the bottom. Items of each kind spawn in the half they need to cross so the motion reads. Direction is deliberately opposite of the bucket (harmful fills the bucket; harmful sinks in the tank) so the two views aren't visually redundant.

**Replay triggers.** Physics scenes in `PhysicsBucketView`, `WaterlineView`, and `BalanceScaleView` rebuild (replaying the drop animation) when (a) the view appears — `.onAppear { replayNonce = UUID() }`, (b) the entry list changes — automatic via `entryIDs` being part of the scene key, (c) the displayed day changes — automatic via `dayKey` being part of the scene key, (d) the user taps Replay — bumps `replayNonce`. The scene key is wired into both `.id(key)` on `SpriteView` and `.task(id: key)`, so the view rebuilds AND the scene gets re-instantiated with the latest entries. See "Date-scoped physics scenes" above for why deriving the key from inputs (rather than bumping a UUID via `.onChange`) is required.

**Unified entry-interaction flow.** Every tap — visualization item, Log-tab row, river item, quadrant dot — opens `FoodEntryDetailSheet` first. The sheet shows an emoji header, prominent timestamp, GL/CL, tier/confidence, and raw transcript. It has an Edit button in the toolbar that presents `EditEntryView` (defined in `LogTab/LogTabView.swift`). Never open `EditEntryView` directly from a tap — always go through the detail sheet. `FoodEntryDetailSheet` uses `@ObservedObject var entry` so it refreshes after an edit.

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
