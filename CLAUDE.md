# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Branching & Workflow

**Branch model:**
- `main` — stable, tested builds only
- `develop` — integration branch; always what gets built and tested on device
- Feature branches — one per Claude session, branched off `develop`

**The root repo (`/Users/ampere/code/glyco-track`) is always checked out to `develop`.** This is the Xcode build target for device testing. Do not check out `main` or a feature branch at the root.

**Every session must:**
1. Branch off `develop` (not `main`) at the start
2. Do all work in the session's worktree on that feature branch
3. When work is complete and the build passes, open a PR targeting `develop` (not `main`)
4. Never merge directly to `develop` or `main` — always via PR

**Active feature branches (update this as PRs open/merge):**
<!-- Add a line per open PR: - [branch-name]: brief description -->

**Cross-session awareness:** Before starting work, run `git log develop --oneline -20` to see what's already landed. Check open PRs on GitHub for what's in flight but not yet merged.

## Behavior

- **Ask before assuming.** When a task has multiple reasonable approaches (e.g. a new visualization style, a data model change, a refactor), ask a clarifying question first. Don't assume the user knows the tradeoffs — explain the options briefly and ask which direction they prefer.
- **Always rebuild after code changes.** After any code edit, run `./scripts/deploy.sh` and report the result. Do not summarize a change as done until the build succeeds.

## Build & Test Commands

```bash
# Build and deploy to connected iPhone — the default workflow.
# Runs xcodegen automatically, so no separate regen step is needed.
./scripts/deploy.sh                       # auto-detects device, regens + builds + installs
./scripts/deploy.sh --no-launch           # install without launching
./scripts/deploy.sh --clean               # clean build first
./scripts/deploy.sh --no-regen            # skip xcodegen (faster, only when no files changed)

# Run unit tests (pure Swift, no device needed — covers GI/CL engine math)
swift test
swift test --filter GIEngineTests/testWhiteRiceGL

# Simulator-only build (no device required)
xcodebuild -project GlycoTrack.xcodeproj -scheme GlycoTrack \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

The `project.pbxproj` is committed and tracked. `deploy.sh` regenerates it automatically on every run, so after adding or removing Swift files just run `deploy.sh` as normal and commit the updated `project.pbxproj` if it changed. The `contents.xcworkspacedata` file is also tracked — do not delete it.

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

### Visualizations (prototyping phase)

All visualization views live under `GlycoTrack/UI/Visualizations/` and are explicitly experimental. The design intent is to test multiple renderings and keep winners:
- **GL views** (unsigned, budget-based): `PhysicsBucketView` (SpriteKit physics), `DailyBucketView` (static), `WeeklyRiverView`, `MonthlyHeatmapView`
- **CL views** (signed, ±): `TugOfWarBarView`, `WaterlineView`, `BalanceScaleView`
- **Combined**: `QuadrantPlotView` (GL on Y, CL on X — the app's most distinctive view)

`HomeTabView` separates GL and CL into two distinct labeled sections with different accent colors (blue for GL, crimson for CL). The picker labels "GL View" must only contain GL prototypes, and "CL View" must only contain CL prototypes — they were previously mixed, which was confusing.

Tappable bubbles open `FoodEntryDetailSheet` — pass a `FoodLogEntry` as `.sheet(item:)`.

### API key

`CLAUDE_API_KEY` is injected via `GlycoTrack/Config/GlycoTrack.xcconfig` (committed stub) which includes the gitignored `GlycoTrack.local.xcconfig`. The key reaches the app via `Info.plist` → `Bundle.main.infoDictionary?["CLAUDE_API_KEY"]`. Never hardcode it.

### Xcode 26 quirks

- `navigationTitle(_:displayedComponents:)` is removed — use `navigationTitle(someString)` or `navigationTitle(date.formatted(...))`.
- `.fill(...).stroke(...)` chain requires iOS 17 — use `.fill(...).overlay(stroke(...))` instead.
- No `.xcdatamodeld` file — Core Data model is fully programmatic (see above).
- `isSoftDeleted` (not `isDeleted`) — `NSManagedObject` already has `isDeleted`.
