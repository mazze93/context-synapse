import Foundation

// MARK: - RunLog decay telemetry (CLAUDE.md P1)
// Extends SynapseCore.RunLog with a typed decay snapshot without touching
// SynapseCore.swift. RunLog.context is [String:String] and already on disk,
// so the snapshot round-trips through namespaced context keys rather than
// changing the serialized shape — old run logs stay readable, new ones gain
// typed fields.

extension SynapseCore.RunLog {

    public struct DecaySnapshot: Codable, Equatable, Sendable {
        public let decayWeight: Double
        public let rotScore: Double
        /// 1 − rotScore, clamped to [0, 1] at construction sites.
        public let lighthouseSaliency: Double
        public let refereeMode: String
        public let interventionFired: Bool

        public init(decayWeight: Double, rotScore: Double,
                    lighthouseSaliency: Double, refereeMode: String,
                    interventionFired: Bool) {
            self.decayWeight = decayWeight
            self.rotScore = rotScore
            self.lighthouseSaliency = lighthouseSaliency
            self.refereeMode = refereeMode
            self.interventionFired = interventionFired
        }

        enum Key: String, CaseIterable {
            case decayWeight, rotScore, lighthouseSaliency, refereeMode, interventionFired
        }

        /// Context entries for embedding into RunLog.context.
        public var contextFields: [String: String] {
            [
                Key.decayWeight.rawValue:        String(format: "%.6f", decayWeight),
                Key.rotScore.rawValue:           String(format: "%.6f", rotScore),
                Key.lighthouseSaliency.rawValue: String(format: "%.6f", lighthouseSaliency),
                Key.refereeMode.rawValue:        refereeMode,
                Key.interventionFired.rawValue:  interventionFired ? "true" : "false"
            ]
        }

        /// Rebuild from a RunLog context dict. Returns nil for pre-snapshot
        /// logs (which carried only a raw "rotScore" string, or nothing).
        public init?(context: [String: String]) {
            guard let dw = context[Key.decayWeight.rawValue].flatMap(Double.init),
                  let rot = context[Key.rotScore.rawValue].flatMap(Double.init),
                  let sal = context[Key.lighthouseSaliency.rawValue].flatMap(Double.init),
                  let mode = context[Key.refereeMode.rawValue],
                  let fired = context[Key.interventionFired.rawValue]
            else { return nil }
            self.init(decayWeight: dw, rotScore: rot, lighthouseSaliency: sal,
                      refereeMode: mode, interventionFired: fired == "true")
        }
    }

    /// Typed view of this run's decay telemetry, if the log carries one.
    public var decaySnapshot: DecaySnapshot? {
        DecaySnapshot(context: context)
    }
}
