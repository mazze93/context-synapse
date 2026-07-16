import Foundation

// MARK: - RefereeConfig persistence (CLAUDE.md P1)
// RefereeConfig was defined in SynapseReferee.swift but never saved or loaded.
//
// Deliberate deviation from the backlog note ("alongside Weights in
// config.json"): saveWeights() rewrites config.json wholesale from the Weights
// codable, so any sibling key stored there would be silently clobbered on the
// next feedback update. The config lives in its own referee.json in the same
// user dir instead — same interpretability guarantee, no write collision.

extension SynapseCore {

    /// `…/ContextSynapse/users/<user>/referee.json`
    public var refereeConfigURL: URL {
        configURL.deletingLastPathComponent().appendingPathComponent("referee.json")
    }

    /// Load the persisted referee config, falling back to defaults
    /// (.functional, per ADR-002: abrasive mode is strictly opt-in).
    public func loadRefereeConfig() -> RefereeConfig {
        guard let data = try? Data(contentsOf: refereeConfigURL),
              let config = try? JSONDecoder().decode(RefereeConfig.self, from: data)
        else { return RefereeConfig() }
        return config
    }

    @discardableResult
    public func saveRefereeConfig(_ config: RefereeConfig) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: refereeConfigURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
