import Foundation

// MARK: - SynapseContent
// A lightweight value type representing a named unit of context —
// a file, a function, a task description, a lighthouse anchor.
// This is the atom that SynapseWeightState operates on.
// The text field is what SemanticDistanceStrategy measures against.

public struct SynapseContent: Equatable, Codable {
    /// Stable unique identifier for this content unit
    public let id: String
    /// Human-readable description or raw content text.
    /// This is what distance strategies operate on.
    public let text: String
    /// Optional file paths or resource references associated with this content
    public let fileReferences: [String]
    /// Optional function/symbol names when content is code-oriented
    public let functionNames: [String]

    public init(
        id: String = UUID().uuidString,
        text: String,
        fileReferences: [String] = [],
        functionNames: [String] = []
    ) {
        self.id = id
        self.text = text
        self.fileReferences = fileReferences
        self.functionNames = functionNames
    }
}

// MARK: - ContextIntervention
// The data packet Edgar hands to EdgarIntervention.render()
// when the CAUTERIZE threshold fires.
//
// This is the Fool's dog moment:
// "hey man i know you are vibing right now but you have lost the plot
//  and you're about to run right off the edge, check yourself"
//
// No judgment — just signal, numbers, and four choices.

public struct ContextIntervention {
    /// Description of the lighthouse (primary goal set at session start)
    public let lighthouseDescription: String
    /// Description of the current drifted synapse
    public let currentSynapseDescription: String
    /// Approximate minutes the user has been in drift
    public let minutesInDrift: Int
    /// Lighthouse saliency score right now [0.0, 1.0]
    public let lighthouseSaliencyNow: Double
    /// Lighthouse saliency at session start (baseline for delta display)
    public let lighthouseSaliencyAtSessionStart: Double

    public init(
        lighthouseDescription: String,
        currentSynapseDescription: String,
        minutesInDrift: Int,
        lighthouseSaliencyNow: Double,
        lighthouseSaliencyAtSessionStart: Double = 1.0
    ) {
        self.lighthouseDescription = lighthouseDescription
        self.currentSynapseDescription = currentSynapseDescription
        self.minutesInDrift = minutesInDrift
        self.lighthouseSaliencyNow = lighthouseSaliencyNow
        self.lighthouseSaliencyAtSessionStart = lighthouseSaliencyAtSessionStart
    }
}

// MARK: - DecayConstants
// Centralized decay/rot math constants.
// Referenced by SynapseWeightState. Collected here for single-point tuning.
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §4–§6

public enum DecayConstants {
    /// Base decay constant λ — controls how fast saliency fades without interaction
    /// Tuned so a synapse at rest for ~1 hour reaches ~37% of its base weight
    public static let baseLambda: Double = 0.0003

    /// Utility decay rate μ — utility fades ~2x slower than saliency
    public static let utilityDecayMu: Double = 0.00015

    /// Rot amplifies decay by this factor per unit of rot score
    public static let rotLambdaAmplifier: Double = 2.0

    /// Rot penalization coefficient α in: W_final = W_decay · (1 - α · RotScore)
    public static let rotAlpha: Double = 0.4

    /// Time threshold for rot drift (seconds) — default 20 minutes
    public static let rotThresholdSeconds: Double = 1200.0

    /// Rot score at which cauterization is required — the CAUTERIZE threshold
    public static let rotCauterizeThreshold: Double = 0.82

    /// Decay multiplier applied when cauterization fires
    public static let rotCauterizeMultiplier: Double = 5.0

    /// Lighthouse floor — minimum final weight for a lighthouse synapse
    /// Ensures the primary goal never decays below findable
    public static let lighthouseFloor: Double = 0.25

    /// Maximum interaction history stored per SynapseWeightState
    public static let maxInteractionHistory: Int = 100
}
