import Foundation

// MARK: - DecayConstants
// Single source of truth for all decay/rot/lighthouse constants.
// Never scatter these — always reference DecayConstants.
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §4

public enum DecayConstants {
    /// Base decay constant λ_base: ~2.8hr half-life at U=1.0
    public static let baseLambda: Double = 0.0001
    /// Utility decay rate μ: fades ~2x slower than saliency
    public static let utilityDecayMu: Double = 0.00005
    /// Rot amplifier on decay constant when RotScore > 0
    public static let rotLambdaAmplifier: Double = 1.5
    /// RotScore threshold at which cauterization is triggered
    public static let rotCauterizeThreshold: Double = 0.82
    /// Decay constant multiplier applied at cauterization
    public static let rotCauterizeMultiplier: Double = 2.5
    /// Rot formula α — rot's influence on final weight penalty
    public static let rotAlpha: Double = 0.6
    /// Lighthouse saliency floor — always findable, never drops below this
    public static let lighthouseFloor: Double = 0.4
    /// Rot drift threshold in seconds (default: 15 minutes)
    public static let rotThresholdSeconds: Double = 900.0
    /// Maximum interaction history records per synapse (cap to prevent unbounded growth)
    public static let maxInteractionHistory: Int = 200
    /// Weight range minimum (maps from prior probability 0.0)
    public static let weightRangeMin: Double = 0.1
    /// Weight range maximum (maps from prior probability 1.0)
    public static let weightRangeMax: Double = 3.0
}
