import Foundation

/// Weights calibrated from clinical dose-response studies.
/// Each unit of fat/fiber per 100g of food contributes to CL.
///
/// References:
/// - Saturated fat: Clarke et al. (1997), Mensink et al. (2003)
/// - Trans fat: Mozaffarian et al. (2006) — strongest LDL-raising per gram
/// - Soluble fiber: Brown et al. (1999) — 5g/day → -5.6 mg/dL LDL
/// - PUFA/MUFA: Mensink & Katan (1992), Mensink et al. (2003)
public struct CLWeights {
    /// Saturated fat raises LDL
    public static let saturatedFat: Double = 1.0
    /// Trans fat raises LDL ~2× more than SFA per gram
    public static let transFat: Double = 2.0
    /// Soluble fiber lowers LDL
    public static let solubleFiber: Double = 0.5
    /// PUFA lowers LDL (replaces SFA in cell membranes)
    public static let pufa: Double = 0.7
    /// MUFA lowers LDL modestly
    public static let mufa: Double = 0.5
}
