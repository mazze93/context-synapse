import Foundation

// MARK: - SynapseContent
// Immutable content descriptor for a synapse.
// Used by SemanticDistanceStrategy for structural heuristic distance computation.
// Passed to SynapseWeightState.recomputeRotScore — describes what a synapse IS about,
// not its weight or decay state.
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §5

public struct SynapseContent: Codable, Equatable {
    /// Stable unique identifier — never changes after creation
    public let id: String
    /// Human-readable description of this synapse's primary concern
    public let text: String
    /// Source file paths referenced by this synapse (used for structural distance)
    public let fileReferences: [String]
    /// Function/method/type names referenced by this synapse (used for structural distance)
    public let functionNames: [String]
    /// ISO8601 creation timestamp
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
