import Foundation

// MARK: - SemanticDistanceStrategy Protocol
// Injected into SynapseWeightState for rot distance computation.
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §5.4
//
// Three implementations in order of complexity:
//   Option A — StructuralHeuristicDistance   (ship now, this file)
//   Option B — TFIDFCosineDistance           (v1.0)
//   Option C — LocalEmbeddingDistance        (future, CoreML MiniLM)
//
// The protocol boundary means swapping strategies requires
// ZERO changes to the rot formula in SynapseWeightState.

public protocol SemanticDistanceStrategy {
    /// Returns distance in [0.0, 1.0] where 0.0 = identical, 1.0 = fully diverged.
    func distance(from content: SynapseContent, to lighthouse: SynapseContent) -> Double
}

// MARK: - Option A: StructuralHeuristicDistance
// Computes overlap between fileReferences and functionNames.
// Fast, zero dependencies, works for code-centric sessions.
// Limitation: blind to conceptual drift not manifest in file/function names.

public struct StructuralHeuristicDistance: SemanticDistanceStrategy {
    public init() {}

    public func distance(from content: SynapseContent, to lighthouse: SynapseContent) -> Double {
        let synapseRefs = Set(content.fileReferences + content.functionNames)
        let lighthouseRefs = Set(lighthouse.fileReferences + lighthouse.functionNames)

        let totalRefs = synapseRefs.union(lighthouseRefs)
        guard !totalRefs.isEmpty else {
            // No structural references — fall back to text overlap heuristic
            return textOverlapDistance(content.text, lighthouse.text)
        }

        let sharedRefs = synapseRefs.intersection(lighthouseRefs)
        let overlap = Double(sharedRefs.count) / Double(totalRefs.count)
        return max(0.0, min(1.0, 1.0 - overlap))
    }

    // Simple word-overlap heuristic for text-only synapses.
    // Not semantic — treats each whitespace-separated token as a feature.
    private func textOverlapDistance(_ a: String, _ b: String) -> Double {
        let tokensA = Set(a.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let tokensB = Set(b.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let union = tokensA.union(tokensB)
        guard !union.isEmpty else { return 0.0 }
        let intersection = tokensA.intersection(tokensB)
        return max(0.0, min(1.0, 1.0 - Double(intersection.count) / Double(union.count)))
    }
}

// MARK: - Option B: TFIDFCosineDistance (stub — v1.0)
// Build keyword bag from synapse + lighthouse content.
// Reuses SynapseCore.cosineSimilarity over the TF-IDF vectors.
// Uncomment and implement in v1.0 sprint.

// public struct TFIDFCosineDistance: SemanticDistanceStrategy {
//     public func distance(from content: SynapseContent, to lighthouse: SynapseContent) -> Double {
//         // TODO: compute TF-IDF vectors, call cosineSimilarity, return 1.0 - score
//         fatalError("Not yet implemented — target v1.0")
//     }
// }
