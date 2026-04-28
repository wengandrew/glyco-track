import SpriteKit

/// SpriteKit colors for the CL visualizations (Waterline, Balance).
///
/// Both views had been writing the same red/green RGB literals inline several
/// times, with tiny per-site variations (0.85 vs 0.9 vs 0.95 red) that read as
/// noise rather than intent. Centralizing here gives one place to tune the
/// palette and one canonical "harmful red" / "beneficial green".
extension SKColor {
    /// Harmful CL (positive). Saturated warm red used for disc strokes,
    /// waterline tint, etc. Apply `withAlphaComponent` at call sites to vary
    /// opacity without redefining the hue.
    static let clHarmful = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1.0)

    /// Beneficial CL (negative). Cool green, used as the inverse of `clHarmful`.
    static let clBeneficial = SKColor(red: 0.25, green: 0.70, blue: 0.40, alpha: 1.0)
}
