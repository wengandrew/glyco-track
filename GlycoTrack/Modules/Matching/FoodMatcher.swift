import CoreData
import Foundation

/// Final per-food resolution after the cascade completes. Carries enough data
/// for the caller to create a FoodLogEntry and render a confidence badge.
struct FoodResolution {
    let totalGL: Double
    let totalCL: Double
    let tier: MatchTier
    let confidence: Float
    /// The primary NutritionalProfile to link to the Core Data entry. For
    /// tier 1 this is the direct match; for tier 2–4 it's the highest-weight
    /// resolved component (or nil at tier 5).
    let primaryProfile: NutritionalProfile?
    /// Human-readable description of what matched (for the detail sheet).
    let matchSummary: String?
    /// The components that contributed nutrition. Used for the detail view.
    let contributingComponents: [ResolvedComponent]

    var isRecognized: Bool { tier != .unrecognized }
}

struct ResolvedComponent {
    let profile: NutritionalProfile
    let grams: Double
    /// Which matcher step resolved this component.
    let via: ResolutionPath
}

enum ResolutionPath {
    case direct          // whole-name DB hit
    case componentSearch // Option B: DB name appeared inside the query
    case aiDecomposed    // Option A: Claude named this ingredient, DB matched it directly
    case aiPlusComponent // Option A gave the ingredient, Option B resolved it to DB
}

/// Tiers reflect HOW a food was matched. Lower tier = more direct = more trusted.
/// Confidence within a tier varies with coverage/quality of the match.
enum MatchTier: Int16, CaseIterable {
    case direct         = 1   // whole-name DB match (exact, contains, or tight fuzzy)
    case componentB     = 2   // reverse-substring decomposition; DB tokens found inside the query
    case aiDecomposed   = 3   // Claude-decomposed ingredients, all resolved against the DB
    case aiBlended      = 4   // Claude decomposition + B fallback for some ingredients (partial)
    case unrecognized   = 5   // nothing matched; GL and CL are zero

    var shortLabel: String {
        switch self {
        case .direct: return "T1"
        case .componentB: return "T2"
        case .aiDecomposed: return "T3"
        case .aiBlended: return "T4"
        case .unrecognized: return "T5"
        }
    }

    var longLabel: String {
        switch self {
        case .direct: return "Direct match"
        case .componentB: return "Component match"
        case .aiDecomposed: return "AI-decomposed"
        case .aiBlended: return "AI + fallback"
        case .unrecognized: return "Not recognized"
        }
    }
}

/// Orchestrates the matching cascade:
///   1. Tier 1 — direct whole-name lookup
///   2. Tier 2 — reverse-substring component decomposition (Option B)
///   3. Tier 3 — Claude ingredient decomposition (Option A)
///   4. Tier 4 — Tier 3 with Tier 2 filling in unresolved ingredients
///   5. Tier 5 — give up; emit zeros + "not recognized"
final class FoodMatcher {
    private let repo: NutritionalRepository
    private let parser: TranscriptParser
    private let clEngine: CLEngine

    init(repo: NutritionalRepository, parser: TranscriptParser, clEngine: CLEngine = CLEngine()) {
        self.repo = repo
        self.parser = parser
        self.clEngine = clEngine
    }

    /// Resolve a single ParsedFood into a fully-computed FoodResolution.
    /// May call Claude's decomposition endpoint if earlier cascade steps miss.
    func resolve(food: ParsedFood) async -> FoodResolution {
        let query = food.food
        let grams = food.grams

        // ── Tier 1 · direct whole-name match ────────────────────────────────
        if let direct = repo.findBestMatch(for: query) {
            let comp = ResolvedComponent(profile: direct.profile, grams: grams, via: .direct)
            let (gl, cl) = compute(components: [comp])
            return FoodResolution(
                totalGL: gl,
                totalCL: cl,
                tier: .direct,
                confidence: direct.confidence,
                primaryProfile: direct.profile,
                matchSummary: direct.profile.foodName,
                contributingComponents: [comp]
            )
        }

        // ── Tier 2 · reverse-substring (Option B) ───────────────────────────
        let components = repo.findComponents(for: query)
        let coverage = repo.coverageFraction(query: query, components: components)
        let tier2IsStrong = (components.count >= 2 && coverage >= 0.6)
            || (components.count >= 1 && coverage >= 0.75)

        // ── Tier 3/4 · AI decomposition (Option A) ──────────────────────────
        // Invoked whenever Tier 1 missed AND Tier 2 is weak or empty. If Tier 2
        // is strong we still prefer it (faster, no extra API call).
        if !tier2IsStrong {
            let ingredients = await parser.decomposeIngredients(foodName: query, totalGrams: grams)
            if !ingredients.isEmpty {
                if let aiResolution = resolveAI(
                    ingredients: ingredients,
                    totalGrams: grams,
                    componentPool: components,
                    query: query
                ) {
                    return aiResolution
                }
            }
        }

        // ── Tier 2 · use Option B result if we have anything ────────────────
        if !components.isEmpty {
            let resolved = distributeWeight(across: components, totalGrams: grams)
            let (gl, cl) = compute(components: resolved)
            let confidence = Float(0.50 + 0.25 * coverage)
            let summary = resolved.map { $0.profile.foodName }.joined(separator: " + ")
            return FoodResolution(
                totalGL: gl,
                totalCL: cl,
                tier: .componentB,
                confidence: confidence,
                primaryProfile: resolved.max(by: { $0.grams < $1.grams })?.profile,
                matchSummary: summary,
                contributingComponents: resolved
            )
        }

        // ── Tier 5 · nothing matched ────────────────────────────────────────
        return FoodResolution(
            totalGL: 0,
            totalCL: 0,
            tier: .unrecognized,
            confidence: 0.0,
            primaryProfile: nil,
            matchSummary: nil,
            contributingComponents: []
        )
    }

    // MARK: - Option A resolution with B fallback (blend)

    private func resolveAI(
        ingredients: [ParsedIngredient],
        totalGrams: Double,
        componentPool: [ComponentMatch],
        query: String
    ) -> FoodResolution? {
        var resolved: [ResolvedComponent] = []
        var anyBlended = false
        var matchedMass: Double = 0
        let totalMass = max(1, ingredients.reduce(0) { $0 + $1.grams })

        for ing in ingredients {
            // Direct lookup on the ingredient name.
            if let direct = repo.findBestMatch(for: ing.name) {
                resolved.append(ResolvedComponent(profile: direct.profile, grams: ing.grams, via: .aiDecomposed))
                matchedMass += ing.grams
                continue
            }
            // Fall back to Option B for this ingredient name.
            let subComponents = repo.findComponents(for: ing.name)
            if let best = subComponents.max(by: { $0.coverage < $1.coverage }) {
                resolved.append(ResolvedComponent(profile: best.profile, grams: ing.grams, via: .aiPlusComponent))
                matchedMass += ing.grams
                anyBlended = true
                continue
            }
            // If the pool found during the outer query covers this ingredient
            // name, we can still use it. This handles cases where the AI names
            // an ingredient the DB doesn't have, but the overall query string
            // matched something that overlaps.
            if let pooled = componentPool.first(where: {
                ing.name.lowercased().contains($0.matchedToken)
            }) {
                resolved.append(ResolvedComponent(profile: pooled.profile, grams: ing.grams, via: .aiPlusComponent))
                matchedMass += ing.grams
                anyBlended = true
            }
            // else: ingredient unresolved, skipped
        }

        guard !resolved.isEmpty else { return nil }

        let matchFraction = matchedMass / totalMass
        let allMatched = resolved.count == ingredients.count
        let tier: MatchTier = (allMatched && !anyBlended) ? .aiDecomposed : .aiBlended

        let confidence: Float
        switch tier {
        case .aiDecomposed:
            confidence = Float(0.65 + 0.20 * matchFraction)
        case .aiBlended:
            confidence = Float(0.30 + 0.30 * matchFraction)
        default:
            confidence = 0.5
        }

        let (gl, cl) = compute(components: resolved)
        let summary = resolved
            .map { "\($0.profile.foodName) (\(Int($0.grams.rounded()))g)" }
            .joined(separator: " + ")

        return FoodResolution(
            totalGL: gl,
            totalCL: cl,
            tier: tier,
            confidence: confidence,
            primaryProfile: resolved.max(by: { $0.grams < $1.grams })?.profile,
            matchSummary: summary,
            contributingComponents: resolved
        )
    }

    // MARK: - Math

    /// Per-ingredient GL and CL, summed. GL uses each ingredient's own GI and
    /// carbs; CL uses each ingredient's own fat/fiber macros. This is the
    /// correct way to handle composite dishes: sum the parts.
    private func compute(components: [ResolvedComponent]) -> (gl: Double, cl: Double) {
        var totalGL: Double = 0
        var totalCL: Double = 0
        for comp in components {
            let p = comp.profile
            let carbsInServing = p.carbsPer100g * comp.grams / 100.0

            // USDA-only entries (no Sydney GI match) store glycemicIndex = 0.
            // For actually-carby ingredients that lands at GL = 0 spuriously
            // — e.g. a noodle variant without a Sydney entry would contribute
            // no GL despite being all carbs. Fall back to medium GI (55) when
            // carbs are present but GI is missing; leave fat/meat/oil alone.
            let effectiveGI: Int = (p.glycemicIndex == 0 && p.carbsPer100g > 3)
                ? 55
                : Int(p.glycemicIndex)
            totalGL += GIEngine.computeGL(gi: effectiveGI, carbsGrams: carbsInServing)

            let nutrition = NutritionInput(
                saturatedFatPer100g: p.saturatedFatPer100g,
                transFatPer100g: p.transFatPer100g,
                solubleFiberPer100g: p.solubleFiberPer100g,
                pufaPer100g: p.pufaPer100g,
                mufaPer100g: p.mufaPer100g
            )
            let clResult = clEngine.computeCL(nutrition: nutrition, quantityGrams: comp.grams)
            totalCL += clResult.cl
        }
        return (totalGL, totalCL)
    }

    /// For Tier 2 (no AI weights) — split the query's total grams across the
    /// found components, weighted by coverage (longer matches get more mass).
    private func distributeWeight(across components: [ComponentMatch], totalGrams: Double) -> [ResolvedComponent] {
        let totalCoverage = max(1, components.reduce(0) { $0 + $1.coverage })
        return components.map { match in
            let share = Double(match.coverage) / Double(totalCoverage)
            return ResolvedComponent(profile: match.profile, grams: totalGrams * share, via: .componentSearch)
        }
    }
}
