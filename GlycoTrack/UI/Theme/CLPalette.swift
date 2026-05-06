import SpriteKit

/// SpriteKit colors for the CL visualization (Balance scale).
///
/// Centralizes the red/green RGB literals that would otherwise be duplicated
/// inline with small per-site variations. One place to tune the palette,
/// one canonical "harmful red" / "beneficial green".
extension SKColor {
    /// Harmful CL (positive). Saturated warm red used for disc strokes,
    /// item tints, etc. Apply `withAlphaComponent` at call sites to vary
    /// opacity without redefining the hue.
    static let clHarmful = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1.0)

    /// Beneficial CL (negative). Cool green, used as the inverse of `clHarmful`.
    static let clBeneficial = SKColor(red: 0.25, green: 0.70, blue: 0.40, alpha: 1.0)
}
