# GlycoTrack — TestFlight Metadata

## What to Test

### Golden path
1. Launch app fresh (or after deleting and reinstalling).
2. Complete onboarding — confirm mic and speech recognition permission dialogs appear after tapping "Get Started".
3. On the Today tab, confirm the "Tap the mic to log your first meal" hint appears.
4. Tap the record button (bottom-right pill). Speak a simple meal: "I had oatmeal with milk and a black coffee."
5. Confirm entries appear with GL and CL values in the bucket and balance scale.
6. Tap an entry row in the Log tab — confirm the detail sheet opens, then try Edit and Delete.
7. Navigate to the Week and Month tabs — confirm the GL river, heatmap, and quadrant plot populate.

### Edge cases to exercise
- **Composite dish:** "I had pad thai with tofu" — should decompose and sum GL/CL across ingredients.
- **Unrecognized food:** "I had blorgfood" — confirm an error message appears (red pill, not a zero-GL entry).
- **Time phrase:** "I had eggs two hours ago" — confirm the log entry's timestamp is backdated, not the current time.
- **No network:** Enable Airplane Mode, then try recording — confirm "No internet connection" error appears.
- **Date navigation:** Swipe left/right on the Today tab to navigate days; tap the date header to return to today.
- **GL budget:** Change the daily GL budget in Settings (gear icon → Settings) — confirm the bucket fill level adjusts.

## Known Limitations

- Widget shows no data — App Groups entitlement requires a paid Apple Developer team (planned for v1.1).
- Database covers ~1,081 GI foods and ~813 USDA foods. Obscure ingredients may not match and will surface as errors.
- First launch only: a "Loading nutritional database…" screen appears for a few seconds while ~1,900 entries seed into Core Data.

## App Store Listing

**App name:** GlycoTrack

**Subtitle:** GL & CL food tracker

**Description (≤ 4,000 chars):**
```
GlycoTrack is a voice-first food logging app that tracks two independent health metrics for every meal: Glycemic Load (GL) and Cholesterol Load (CL).

Speak your meal — "I had a bowl of ramen and green tea" — and the app identifies each food, computes its GL and CL from clinically grounded formulas, and adds it to your daily picture.

WHY TWO NUMBERS?
Most nutrition apps collapse everything into a single score. GL and CL measure different risks that don't always agree:
• GL tracks blood sugar impact — relevant to metabolic health and diabetes risk.
• CL tracks LDL cholesterol impact — relevant to heart disease risk.
White rice is high-GL but nearly-zero-CL. Olive oil is zero-GL but strongly negative-CL (beneficial). Tracking both keeps trade-offs visible.

HOW IT WORKS
• Speak naturally. The app uses on-device speech recognition to transcribe your meal, then identifies ingredients and computes GL and CL using the Sydney University GI Database and USDA FoodData Central.
• Composite dishes (pad thai, beef noodle soup) are automatically decomposed into ingredients and summed.
• Time-aware logging: say "I had eggs two hours ago" and the entry is backdated correctly.
• Physics-based visualizations show GL as a filling bucket and CL as a balance scale — so you feel the day's load, not just read a number.

FORMULAS
GL = (GI × carbs in serving) / 100. Daily budget defaults to 100 — adjustable in Settings.
CL = (SFA × 1.0) + (TFA × 2.0) − (fiber × 0.5) − (PUFA × 0.7) − (MUFA × 0.5). Positive = net harmful. Negative = net beneficial.

FOR INFORMATIONAL USE ONLY
GlycoTrack is a tracking tool, not medical advice. Consult your physician before making dietary changes.
```

**Keywords (100 chars):**
```
glycemic,cholesterol,food log,nutrition,GL,CL,diabetes,heart,diet,metabolic,blood sugar
```

**Category:** Health & Fitness (primary) · Food & Drink (secondary)

**Privacy policy URL:** https://github.com/wengandrew/glyco-track/blob/main/PRIVACY.md
*(Create this page before App Store submission.)*

**Support URL:** https://github.com/wengandrew/glyco-track/issues

## Pre-Submission Checklist

- [ ] Privacy policy page live at the URL above
- [ ] Screenshots captured on 6.7" device (1290 × 2796 px) — required
- [ ] Screenshots captured on 6.5" device (1242 × 2688 px) — optional but recommended
- [ ] `CFBundleVersion` in `GlycoTrack/Info.plist` bumped before archive (Apple rejects duplicate build numbers)
- [ ] `CFBundleShortVersionString` set to `1.0` for the first submission
- [ ] Archive built with `./scripts/archive.sh` and validated
- [ ] TestFlight internal testing complete (at least one round with yourself)
- [ ] Encryption question answered: `ITSAppUsesNonExemptEncryption = false` (already in Info.plist)

## Build Number Policy

`CFBundleShortVersionString` (e.g. `1.0`) — change only for user-visible releases (1.0 → 1.1 → 2.0).
`CFBundleVersion` (e.g. `1`) — increment before every TestFlight or App Store upload (1 → 2 → 3…). Apple rejects duplicate build numbers within the same marketing version.
