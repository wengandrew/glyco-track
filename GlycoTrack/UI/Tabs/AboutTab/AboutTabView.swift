import SwiftUI

struct AboutTabView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heroSection
                    whatItTracksSection
                    glMathSection
                    clMathSection
                    quadrantSection
                    tiersSection
                    howMatchingWorks
                    sourcesSection
                    footnote
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .navigationTitle("About")
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GlycoTrack")
                .font(.largeTitle.weight(.bold))
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
        sectionCard(title: "Match quality tiers", icon: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 12) {
                tierRow(
                    tier: .direct,
                    description: "Your food was found directly in the reference database by name (or a close typo). Most reliable."
                )
                tierRow(
                    tier: .componentB,
                    description: "Your food name contains multiple recognized ingredients (e.g. \"beef noodle soup\" → beef + noodles). The database entries are matched as components of the name and weighted by match length."
                )
                tierRow(
                    tier: .aiDecomposed,
                    description: "AI broke the dish into weighted ingredients (e.g. beef 60 g + rice noodles 90 g + broth 90 g + bok choy 15 g) and every ingredient was found in the database. Each contributes to GL and CL in proportion to its grams."
                )
                tierRow(
                    tier: .aiBlended,
                    description: "AI decomposition was used, but some ingredients fell back to partial component matches. Less precise than Tier 3; some of the dish's mass may go uncounted."
                )
                tierRow(
                    tier: .unrecognized,
                    description: "Nothing matched. GL and CL are set to 0 and the entry is flagged \"Not recognized\" so you know the values aren't trustworthy. Consider re-logging with a more specific name."
                )

                Text("The \"Refine\" badge appears when confidence is below 70%. Consider editing the entry to a more specific name.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var howMatchingWorks: some View {
        sectionCard(title: "How matching works", icon: "magnifyingglass") {
            Text("""
When you log a food, the matcher tries steps in order and stops at the first that's strong enough:

1.  **Direct lookup** — exact, substring, or tight typo-fuzzy match.
2.  **Component search** — scan the database for recognized food names contained in yours.
3.  **AI decomposition** — if the name is composite (e.g. \"chicken caesar salad\"), Claude breaks it into weighted ingredients and each is looked up.
4.  **Blend** — if AI names an ingredient the database doesn't have verbatim, the component search fills the gap.
5.  **Give up** — nothing matched; values are zeroed and flagged.

Daily totals are the sum of each entry's GL and CL. Flagged entries contribute 0, so unrecognized foods don't silently inflate or deflate your daily numbers.
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
                    .font(.headline)
            }
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
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

    private func tierRow(tier: MatchTier, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            tierPill(tier: tier)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.longLabel)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func tierPill(tier: MatchTier) -> some View {
        let color: Color
        switch tier {
        case .direct: color = .green
        case .componentB: color = .blue
        case .aiDecomposed: color = .teal
        case .aiBlended: color = .orange
        case .unrecognized: color = .red
        }
        return Text(tier.shortLabel)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .cornerRadius(5)
    }
}
