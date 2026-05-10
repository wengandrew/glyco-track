# GlycoTrack TestFlight Notes

## What is GlycoTrack?

GlycoTrack is a voice-first food-logging app that tracks two independent health metrics for every meal:

- **GL (Glycemic Load)** — measures how much a food is likely to spike blood sugar. Relevant to diabetes and metabolic risk. Always ≥ 0. Daily budget defaults to 100.
- **CL (Cholesterol Load)** — measures how much a food is likely to raise or lower LDL cholesterol. Positive = harmful (saturated/trans fat), negative = beneficial (fiber, healthy fats).

You speak a meal ("I had a bowl of ramen and green tea"), and the app resolves each food through its ingredient database, computes GL and CL, and displays the results in physics-based visualizations.

---

## How to Test

### First Launch

1. Accept the onboarding screen (microphone + speech recognition permissions).
2. The nutritional database seeds on first launch — a brief loading overlay appears (typically 1–3 seconds). This only happens once.

### Logging a Meal (Core Flow)

1. Tap the **mic button** (bottom-right, floating tab bar).
2. Speak a meal — examples:
   - "I had scrambled eggs with whole wheat toast and orange juice"
   - "Large bowl of chicken tikka masala with basmati rice"
   - "Two slices of pepperoni pizza"
   - "I had a glass of red wine two hours ago"
3. Pause briefly — the app auto-stops after 2 seconds of silence.
4. Watch the GL bucket fill with physics-based drops and the CL balance scale tip.

### Time Phrases

The app recognises natural time phrases and backdates entries accordingly:
- "I had eggs **this morning at 8am**"
- "For breakfast" / "For lunch" / "For dinner"
- "**Two hours ago** I had a banana"
- "**Yesterday at 6pm** I had sushi"

### Navigation

- Swipe left/right on the Today tab to navigate between days.
- Tap the date label to jump back to today.
- Tap any food drop (GL bucket) or arm weight (CL scale) to see its details.
- Week and Month tabs swipe left/right to navigate weeks/months.
- Tapping a day column in the Week river view jumps to that day on the Today tab.

### Editing & Deleting

- Tap any entry → Detail sheet → pencil icon to edit timestamp or description.
- Tap trash icon (in detail sheet or via Edit Entry) to soft-delete.

### Manual Entry

- On the Today tab → scroll down to the text field below the physics views.
- Type a food description and submit — same matching pipeline as voice.

### Settings

- Gear icon (top-right of Today tab) → Settings pane:
  - Adjust daily GL budget (50–200, default 100).
  - Physics sandbox: gravity and haptic intensity sliders.

---

## Known Limitations

| Issue | Notes |
|---|---|
| Widget shows empty data | App Groups entitlement requires a paid Apple Developer team. Planned for v1.1. |
| CL = 0 for some foods | Foods without a USDA macronutrient record default to CL = 0. Database expansion is ongoing. |
| Daily notification may miss a day | `cancelTodayIfSufficientlyLogged` removes the repeating trigger; users who don't open the app the next day miss one notification. |
| Privacy policy URL placeholder | The in-app privacy policy link points to a GitHub Pages URL that must be published before App Store submission. |

---

## Test Scenarios to Focus On

Please pay particular attention to:

1. **First launch experience** — Does the onboarding appear? Does the database finish seeding quickly?
2. **Voice recognition accuracy** — Try unusual foods: ethnic dishes, composite meals ("pho with brisket and noodles"), drinks ("matcha latte with oat milk").
3. **Unrecognized food handling** — Try something obscure. The app should show "Couldn't recognize X" rather than logging a silent 0.
4. **Network failure** — Disable Wi-Fi/cellular, try to log. The error pill should show "Network unavailable" with a **Retry** button.
5. **Time phrase back-dating** — Say "I had cereal this morning" at noon — check the timestamp on the entry.
6. **Day navigation / swipe** — Navigate to a past day, swipe back to today, verify chevrons hide at boundaries.

---

## Feedback

Please report bugs and feedback via GitHub Issues: https://github.com/wengandrew/glyco-track/issues

Or email directly — see the support link in the app's **About** pane (gear icon → About → Support & Feedback).
