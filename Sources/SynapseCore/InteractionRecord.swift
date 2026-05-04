import Foundation

// MARK: - InteractionRecord
// Timestamped event classification for decay utility computation.
// Each observable interaction with the system produces one record.
// successWeight maps event types to utility signals used in U(s,t).
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
    /// Cached successWeight at time of recording — avoids recompute on history replay
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
