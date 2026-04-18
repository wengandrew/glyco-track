# GlycoTrack — Complete Design Document (MVP)

## 1. Product Vision

GlycoTrack is a voice-first food logging app for iOS that tracks dietary glycemic load (GL) and cholesterol load (CL) to help users manage diabetes and heart disease risk. Users speak what they ate via a home screen widget; the app handles all parsing, nutritional lookup, and analysis automatically.

## 2. Core Value Proposition

Two independent health risk dimensions tracked simultaneously:

- **Glycemic Load (GL):** Tracks carbohydrate quality and quantity for diabetes risk. GL is strictly unsigned — every food with carbs adds to the total. You cannot negate a high-GL food.
- **Cholesterol Load (CL):** Tracks saturated fat, trans fat, soluble fiber, and unsaturated fat for heart disease risk. CL is signed — beneficial foods (fiber, unsaturated fats) actively counteract harmful foods (saturated fat, trans fat).

This dual-axis tracking surfaces conflicts invisible to the user (e.g., brown rice is great for CL but contributes GL; nuts are low GL but beneficial for CL).

## 3. Scientific Basis

### 3.1 GL Formula

```
GL = (Glycemic Index × grams of carbohydrate) / 100
```

Daily GL budget: ~100 (evidence-based, not user-configurable). Thresholds per serving: Low ≤10, Medium 11–19, High ≥20.

### 3.2 CL Formula

```
CL = (SFA_grams × W_sfa) + (TFA_grams × W_tfa) - (SolubleFiber_grams × W_fiber) - (PUFA_grams × W_pufa) - (MUFA_grams × W_mufa)
```

Positive CL = net harmful. Negative CL = net beneficial. Zero = neutral. Weights derived from clinical dose-response data; validated against Mediterranean diet (should produce negative CL) and standard American diet (should produce positive CL).

**LDL-raising:** Saturated fat (butter, cheese, beef, palm/coconut oil), trans fat, dietary cholesterol (modest effect), free sugars (small effect).

**LDL-lowering:** Soluble fiber (oats, barley, psyllium, legumes; each 5g/day reduces LDL ~5.6 mg/dL), PUFA (soybean, corn, sunflower oil, nuts), MUFA (olive oil, avocado, almonds), plant sterols/stanols.

## 4. Technical Stack

- **Language:** Swift
- **UI:** SwiftUI
- **Database:** SQLite (SwiftData or Core Data)
- **Widget:** WidgetKit
- **Voice:** Apple Speech Recognition framework
- **AI:** Claude API with streaming
- **Target:** iOS 16+, iPhone 13+
- **GI DB:** University of Sydney GI Database (bundled)
- **Nutrition DB:** USDA FoodData Central (bundled, separate)

## 5. Module Structure

| Module              | Responsibility                                                                 |
|---------------------|--------------------------------------------------------------------------------|
| VoiceCapture        | Widget, speech recognition, real-time audio streaming to Claude                |
| TranscriptParser    | Claude API, multi-food extraction, confidence scoring, parsing method tracking |
| GIEngine            | GI lookup from Sydney DB, GL calculation, unit tests                           |
| CLEngine            | Fat/fiber lookup from USDA DB, CL calculation (signed), unit tests             |
| LocalStorage        | SQLite schema, CRUD, two-table architecture                                    |
| VisualizationEngine | Multiple prototype views for GL and CL, clustering logic                       |
| SummaryGenerator    | Claude API for trends, context-aware, covers both GL and CL                    |
| NotificationManager | End-of-day logging check, push notifications                                   |
| UITabs              | Home, Week, Month, Log, Summary                                                |

## 6. Data Model

### 6.1 FoodLogEntry Table

| Field                | Type     | Description                                   |
|----------------------|----------|-----------------------------------------------|
| id                   | UUID     | Primary key                                   |
| rawTranscript        | String   | Original voice-to-text from Claude            |
| foodDescription      | String   | Extracted food description                    |
| quantity             | String   | Extracted quantity                            |
| quantityGrams        | Double   | Normalized grams                              |
| timestamp            | DateTime | When consumed (midnight-to-midnight local TZ) |
| loggedAt             | DateTime | When entry created                            |
| confidenceScore      | Float    | 0.0–1.0                                       |
| parsingMethod        | Int      | Tier 1–4                                      |
| referenceFood        | String?  | Proxy DB entry if Tier 2                      |
| nutritionalProfileId | FK       | Links to NutritionalProfile                   |
| foodGroup            | String   | Food group classification                     |
| computedGL           | Double   | Calculated glycemic load                      |
| computedCL           | Double   | Calculated cholesterol load (signed)          |
| isEdited             | Bool     | User manually corrected                       |
| isDeleted            | Bool     | Soft delete flag                              |

### 6.2 NutritionalProfile Table

| Field               | Type   | Description                          |
|---------------------|--------|--------------------------------------|
| id                  | UUID   | Primary key                          |
| foodName            | String | Canonical food name                  |
| glycemicIndex       | Int    | GI value (0–100), source: Sydney DB  |
| carbsPer100g        | Double | Carbs per 100g, source: USDA         |
| saturatedFatPer100g | Double | SFA per 100g, source: USDA           |
| transFatPer100g     | Double | TFA per 100g, source: USDA           |
| solubleFiberPer100g | Double | Soluble fiber per 100g, source: USDA |
| pufaPer100g         | Double | PUFA per 100g, source: USDA          |
| mufaPer100g         | Double | MUFA per 100g, source: USDA          |
| giSource            | String | Source dataset for GI                |
| nutritionSource     | String | Source dataset for fat/fiber         |

### 6.3 Food Group Color Coding

| Color  | Group                      | Examples             |
|--------|----------------------------|----------------------|
| Blue   | Grains & starches          | Rice, bread, pasta   |
| Orange | Fruits & natural sugars    | Apples, bananas      |
| Purple | Dairy                      | Milk, cheese, yogurt |
| Brown  | Proteins                   | Meat, legumes, nuts  |
| Green  | Vegetables                 | Broccoli, spinach    |
| Red    | Processed/refined & sweets | Cake, cookies, chips |

### 6.4 Parsing Method Tiers

| Tier | Method                  | Confidence | Description                                |
|------|-------------------------|------------|--------------------------------------------|
| 1    | Direct DB match         | 0.85–1.0   | Exact/near-exact database match            |
| 2    | Claude-estimated lookup | 0.5–0.84   | Mapped to closest proxy food               |
| 3    | Claude full estimation  | 0.2–0.49   | Novel/composite food; all values estimated |
| 4    | Insufficient data       | < 0.2      | Cannot estimate; flagged strongly          |

## 7. Core Features

### 7.1 Voice Logging (Widget)

Widget is strictly a mic button. Tap → recording starts immediately. User speaks naturally, can list multiple foods in one recording ("I had eggs, toast with butter, and OJ"). Claude parses multi-food input and creates separate FoodLogEntry per item. No raw audio stored. Assumes internet connectivity.

### 7.2 GIEngine

Bundled Sydney GI DB (~750 foods). Fuzzy string matching for lookup. GL = (GI × carbs) / 100. Daily budget ~100 (hardcoded). Unit tests against known foods.

### 7.3 CLEngine

Bundled USDA FoodData Central (~7,793 foods). Separate from GI DB. CL = weighted formula (signed). Positive = harmful, negative = beneficial. Weight calibration from clinical data. Validated against dietary patterns.

## 8. Visualizations (Prototyping Phase)

### GL Visualizations (Unsigned)

**Prototype A — Daily Bucket:** Fixed container = daily GL budget. Bubbles sorted GL ascending (low pours first, high spills over). Size = GL, color = food group. Resets midnight local TZ.

**Prototype B — Weekly River:** Horizontal Mon–Sun timeline, all 7 days visible. Y = time of day. Size = GL, color = food group.

**Prototype C — Monthly Heatmap:** Calendar grid. Cell color = total daily GL (green → red gradient). Tap day → drill to bucket.

### CL Visualizations (Signed)

**Prototype D — Waterline:** Container with midline at zero. Harmful bubbles float above, beneficial sink below. Water level = net CL.

**Prototype E — Tug of War Bar:** Horizontal bar centered at zero. Harmful extends right, beneficial extends left. Segment width = magnitude, color = food group.

**Prototype F — Balance Scale:** Two sides with bubbles. Scale tips to show net CL.

### Combined View

**GL × CL Quadrant Plot:** GL on Y-axis, CL on X-axis. Four quadrants: top-right = worst (cake), top-left = complex (oatmeal), bottom-right = watch out (butter), bottom-left = best (vegetables). Goal: keep cluster center near bottom-left. Secondary/insights view.

### Prototyping Plan

Build all prototypes A–F plus quadrant. Determine primary views through testing. Determine toggle vs. side-by-side through testing. Clustering logic consistent across time intervals.

## 9. Tab Structure

| Tab     | Purpose                                               |
|---------|-------------------------------------------------------|
| Home    | Daily GL + CL visualizations                          |
| Week    | Weekly river + CL view                                |
| Month   | Heatmap calendar, tap to drill down                   |
| Log     | Editable list, confidence flagging, manual text entry |
| Summary | Unified Claude-generated analysis (GL + CL)           |

## 10. Log Tab

Chronological list (newest first). Each row: food, quantity, time, GL, CL, food group dot. Confidence < 0.7 flagged with "Refine" badge. Parsing tier displayed. Tap to edit (text fields). GL/CL recalculate live. Soft delete. "Add manual entry" button (text-based, no voice). No sorting/filtering in MVP.

## 11. Summary Tab

Unified written summary. Auto-regenerates every 3 days or via "Update me" button. Context-aware: sparse data → "log more"; moderate → highlights top foods; rich → full trends + actionable recommendation. Calls out GL/CL conflicts explicitly.

## 12. Notifications

End-of-day push (~8 PM local). Fires if < 2–3 entries logged. Friendly message. Tap opens app to recording screen.

## 13. Data Flow

1. Tap widget → recording starts
2. Audio streams to Claude API
3. Claude returns JSON array of food items
4. One FoodLogEntry created per item with raw transcript + extracted description
5. GIEngine computes GL from Sydney DB
6. CLEngine computes CL from USDA DB
7. Entries stored locally with GL, CL, confidence, parsing method
8. Visualizations render from date-range queries
9. Every 3 days: SummaryGenerator runs Claude against all entries
10. User edits in Log tab → GL/CL recalculate
11. End-of-day notification if insufficient logging

## 14. Reference Databases

**Sydney GI DB:** ~750 foods with tested GI values. Bundled as SQLite table.

**USDA FoodData Central:** 7,793 foods, up to 150 components. Public domain (CC0). CSV/JSON available. Bundled as separate SQLite table.

**Reconciliation:** Build-time script cross-references both DBs via fuzzy matching. Foods in both are linked. Partial data retained for single-source foods. Manual review for ambiguous matches.

## 15. Design Decisions

| Decision                             | Rationale                            |
|--------------------------------------|--------------------------------------|
| Voice-first UI                       | Minimize friction                    |
| Multi-food parsing                   | Natural speech patterns              |
| Real-time streaming                  | No audio file management             |
| Two-table data model                 | Separate user data from science data |
| Separate reference DBs               | Cleanliness, independent updates     |
| Local only (MVP)                     | Simplicity; cloud deferred           |
| GL unsigned, CL signed               | Scientifically accurate              |
| Color = food group, size = magnitude | No visual channel overload           |
| Parsing tiers                        | Transparent confidence tracking      |
| Multiple viz prototypes              | Empirical testing determines best    |
| Midnight local TZ                    | Standard practice                    |
| Single unified summary               | Simpler UX                           |

## 16. Success Metrics

- Logging: 2–3 entries/day average
- < 20% low-confidence entries after 1 week
- Daily app engagement
- Measurable GL/CL trend shifts over 2–4 weeks
- GL calculations match published tables
- CL validated against dietary patterns
- Multi-food parsing > 90% accuracy

## 17. Future Features (Post-MVP)

- CloudKit/Google Drive backup
- Offline recording with deferred parsing
- Real-time clarifying questions
- Retroactive manual logging
- Apple Health integration
- Web dashboard
- Photo-based food logging
- Customizable targets (with medical guidance)
