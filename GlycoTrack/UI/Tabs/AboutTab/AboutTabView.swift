// swiftlint:disable line_length
//
// AboutPaneView is mostly multi-paragraph educational copy inside `Text("""…""")`
// blocks. Reflowing those at 160 chars would just insert mid-sentence line
// breaks the reader doesn't see anyway — the visible width is whatever
// SwiftUI's layout engine decides at runtime. Disable file-wide.

import SwiftUI

/// About pane content. Hosted inside `MoreSheet`'s segmented control — no
/// `NavigationView` wrapper here.
struct AboutPaneView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroSection
                whatItTracksSection
                glMathSection
                clMathSection
                quadrantSection
                tiersSection
                sourcesSection
                legalSection
                footnote
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GlycoTrack")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Two numbers. Two kinds of risk. One honest picture of what you ate.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var whatItTracksSection: some View {
        sectionCard(title: "What this app tracks", icon: "square.split.2x1.fill") {
            Text("""
GlycoTrack tracks two independent metrics for every food you log:

•  **Glycemic Load (GL)** — how much a food is likely to spike your blood sugar. Relevant to diabetes and metabolic risk. Always ≥ 0.

•  **Cholesterol Load (CL)** — how much a food is likely to push LDL cholesterol up (harmful) or down (beneficial). Relevant to heart disease. Signed: positive means net harmful, negative means net beneficial.

The two don't always agree. White rice is high-GL but nearly-zero-CL. Olive oil is zero-GL but strongly-negative-CL. Tracking both keeps you honest about trade-offs a single score would hide.
""")
        }
    }

    private var glMathSection: some View {
        sectionCard(title: "The GL formula", icon: "drop.fill", accent: .glAccent) {
            VStack(alignment: .leading, spacing: 10) {
                formula("GL = (GI × carbs_in_serving) / 100")

                Text("""
**GI** is the *Glycemic Index* of the food (0–100). It measures how fast the carbs in that food raise blood glucose compared to pure glucose.

**carbs_in_serving** is the grams of carbs in the actual portion you ate, derived from the food's carbs-per-100g value and your serving weight.

Daily GL budget defaults to **100**. A single food over 20 GL is considered *high*; 10–19 is *medium*; under 10 is *low*.
""")
                    .font(.callout)

                Text("Example: 150 g of white rice at GI 72 with 28.6 g carbs/100 g → 30.9 GL — one serving, almost a third of the daily budget.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var clMathSection: some View {
        sectionCard(title: "The CL formula", icon: "heart.fill", accent: .clAccent) {
            VStack(alignment: .leading, spacing: 10) {
                formula("""
CL = (SFA × 1.0) + (TFA × 2.0)
     − (fiber × 0.5)
     − (PUFA × 0.7)
     − (MUFA × 0.5)
""")

                Text("""
CL sums each macronutrient's impact on LDL cholesterol, weighted by clinical dose-response evidence:

•  **SFA** (saturated fat) raises LDL — weight 1.0
•  **TFA** (trans fat) raises LDL ~2× as fast as SFA per gram — weight 2.0
•  **Soluble fiber** lowers LDL — weight 0.5
•  **PUFA** (polyunsaturated fat) lowers LDL when it replaces SFA — weight 0.7
•  **MUFA** (monounsaturated fat) lowers LDL modestly — weight 0.5

Inputs are per-100 g, then scaled to your actual serving weight.
""")
                    .font(.callout)

                Text("Example: 100 g butter → +45.3 CL (very harmful). 20 g olive oil → −4.5 CL (beneficial).")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var quadrantSection: some View {
        sectionCard(title: "Why both numbers matter", icon: "chart.scatter") {
            Text("""
Plotted together (GL on Y, CL on X), every food lands in one of four quadrants:

•  **Low GL / Low CL** — the zone you want to live in (leafy greens, salmon, olive oil).
•  **High GL / Low CL** — carbs without cholesterol cost (rice, potatoes, fruit).
•  **Low GL / High CL** — cholesterol cost without carbs (butter, fatty meats, cheese).
•  **High GL / High CL** — the worst of both (pastries, deep-fried carbs, most fast food).

Most single-score tools collapse this into one number and hide the trade-off. GlycoTrack keeps them separate.
""")
        }
    }

    private var tiersSection: some View {
        sectionCard(title: "How GL and CL are calculated", icon: "checkmark.seal.fill") {
            Text("""
GlycoTrack looks up every food you log in its reference database and computes GL and CL from the actual macronutrient values.

For simple foods ("white rice", "olive oil"), the database usually has a direct match. For composite dishes ("beef noodle soup", "pad thai"), the app breaks the dish into its ingredients and sums each ingredient's GL and CL contribution proportionally.

If a food can't be identified, the entry is not logged at all — a zero-GL/CL placeholder would silently corrupt your daily totals. You'll see an error message so you can try a more specific name.

The confidence percentage shown in each entry's detail view reflects how closely the logged description matched the database. Entries below 70% confidence may be less accurate.
""")
        }
    }

    private var sourcesSection: some View {
        sectionCard(title: "Data sources & weights", icon: "book.fill") {
            Text("""
•  **GI values** — Sydney University Glycemic Index Database (776 foods).
•  **Macros** — USDA FoodData Central (fat, fiber, carbs).
•  **CL coefficients** — calibrated from: Clarke et al. (1997) and Mensink et al. (2003) for SFA; Mozaffarian et al. (2006) for TFA (the ~2× multiplier); Brown et al. (1999) for soluble fiber; Mensink & Katan (1992) for PUFA/MUFA.

**Future work:** the ingredient database will be expanded from the current ~776 foods as the AI-decomposition cascade surfaces common composites (pho, pad thai, shakshuka, etc.). For now, the cascade handles unknown composites at runtime.
""")
        }
    }

    private var legalSection: some View {
        sectionCard(title: "Legal & Support", icon: "link") {
            VStack(alignment: .leading, spacing: 12) {
                // swiftlint:disable:next force_unwrapping
                Link("Privacy Policy", destination: URL(string: "https://github.com/wengandrew/glyco-track/blob/main/PRIVACY.md")!)
                    .font(.callout)
                // swiftlint:disable:next force_unwrapping
                Link("Get Help / Report an Issue", destination: URL(string: "https://github.com/wengandrew/glyco-track/issues")!)
                    .font(.callout)
                Text("GlycoTrack is for informational purposes only and is not a substitute for professional medical advice, diagnosis, or treatment. Always seek the advice of your physician or other qualified health provider with any questions you may have.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: some View {
        Text("GlycoTrack is a tracking tool, not medical advice. Talk to your doctor about specific targets for you.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }

    // MARK: - Reusable pieces

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        accent: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func formula(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
    }

}
