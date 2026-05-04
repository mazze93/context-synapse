import Foundation

// MARK: - InteractionRecord
// Timestamped event classification for decay utility computation.
// Each interaction with the system produces one of these records.
// successWeight maps observable system events to utility signals.
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §4.4

public enum InteractionEventType: String, Codable, CaseIterable {
    case gitCommit         = "git.commit"
    case fileSave          = "file.save"
    case buildSuccess      = "build.success"
    case buildFailure      = "build.failure"
    case keystrokeBurst    = "keystroke.burst"
    case windowSwitchAway  = "window.switch.away"
    case manualFeedback    = "manual.feedback"

    /// Observable success weight for utility score computation.
    /// Source: Ops Manual §4.4 Interaction Success Weights
    public var successWeight: Double {
        switch self {
        case .gitCommit:        return 1.0
        case .fileSave:         return 0.9
        case .buildSuccess:     return 0.85
        case .buildFailure:     return 0.2
        case .keystrokeBurst:   return 0.1
        case .windowSwitchAway: return 0.0
        case .manualFeedback:   return 0.75
        }
    }
}

public struct InteractionRecord: Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let eventType: InteractionEventType
    /// successWeight at time of recording (cached to avoid recompute)
    public let successWeight: Double
    /// Optional synapse ID this interaction is attributed to
    public let synapseId: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: InteractionEventType,
        synapseId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.successWeight = eventType.successWeight
        self.synapseId = synapseId
    }
}

// MARK: - SynapseContent
// Immutable content descriptor for a synapse.
// Used by SemanticDistanceStrategy for structural heuristic distance.

public struct SynapseContent: Codable, Equatable {
    public let id: String
    public let text: String
    public let fileReferences: [String]
    public let functionNames: [String]
    public let createdAt: Date

    public init(
        id: String,
        text: String,
        fileReferences: [String] = [],
        functionNames: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.fileReferences = fileReferences
        self.functionNames = functionNames
        self.createdAt = createdAt
    }
}

// MARK: - DecayConstants
// Single source of truth for all decay/rot constants.
// Never scatter these — always reference DecayConstants.

public enum DecayConstants {
    /// Base decay constant: ~2.8hr half-life at U=1.0
    public static let baseLambda: Double = 0.0001
    /// Utility decay rate: fades ~2x slower than saliency
    public static let utilityDecayMu: Double = 0.00005
    /// Rot amplifier on decay constant
    public static let rotLambdaAmplifier: Double = 1.5
    /// RotScore threshold at which cauterization is triggered
    public static let rotCauterizeThreshold: Double = 0.82
    /// Decay constant multiplier applied at cauterization
    public static let rotCauterizeMultiplier: Double = 2.5
    /// Rot formula alpha — rot's influence on final weight
    public static let rotAlpha: Double = 0.6
    /// Lighthouse saliency floor — always findable
    public static let lighthouseFloor: Double = 0.4
    /// Rot drift threshold in seconds (default: 15 minutes)
    public static let rotThresholdSeconds: Double = 900.0
    /// Maximum interaction history records per synapse
    public static let maxInteractionHistory: Int = 200
    /// Weight range minimum (maps from prior probability 0.0)
    public static let weightRangeMin: Double = 0.1
    /// Weight range maximum (maps from prior probability 1.0)
    public static let weightRangeMax: Double = 3.0
}
