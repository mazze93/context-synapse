import Foundation
import SynapseCore

extension SynapseCore {
    // build canonical vector ordering: intents keys sorted, then tones sorted, then domains sorted
    public func canonicalVector(for weights: Weights, scale: Double = 1.0) -> [Double] {
        let intents = weights.intents.keys.sorted().map { weights.intents[$0] ?? 0.0 }
        let tones = weights.tones.keys.sorted().map { weights.tones[$0] ?? 0.0 }
        let domains = weights.domains.keys.sorted().map { weights.domains[$0] ?? 0.0 }
        return (intents + tones + domains).map { $0 * scale }
    }
}
