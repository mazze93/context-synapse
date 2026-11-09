import Foundation

/// Read-only comparison of two RunLog snapshots, in caller-specified order.
/// Missing legacy telemetry is unavailable, never interpreted as zero.
public struct SessionDiff: Codable, Equatable, Sendable {
    public struct Metric: Codable, Equatable, Sendable {
        public let before: Double?
        public let after: Double?
        public var delta: Double? {
            guard let before, let after else { return nil }
            return after - before
        }
    }

    public let beforeTimestamp: String
    public let afterTimestamp: String
    public let decayWeight: Metric
    public let rotScore: Metric
    public let lighthouseSaliency: Metric
    public let beforeRefereeMode: String?
    public let afterRefereeMode: String?
    public let beforeInterventionFired: Bool?
    public let afterInterventionFired: Bool?

    public init(before: SynapseCore.RunLog, after: SynapseCore.RunLog) throws {
        let first = before.decaySnapshot
        let second = after.decaySnapshot
        for snapshot in [first, second].compactMap({ $0 }) {
            guard snapshot.decayWeight.isFinite, snapshot.rotScore.isFinite,
                  snapshot.lighthouseSaliency.isFinite else {
                throw DiffError.nonFiniteTelemetry
            }
        }
        beforeTimestamp = before.timestamp
        afterTimestamp = after.timestamp
        decayWeight = Metric(before: first?.decayWeight, after: second?.decayWeight)
        rotScore = Metric(before: first?.rotScore, after: second?.rotScore)
        lighthouseSaliency = Metric(before: first?.lighthouseSaliency, after: second?.lighthouseSaliency)
        beforeRefereeMode = first?.refereeMode
        afterRefereeMode = second?.refereeMode
        beforeInterventionFired = first?.interventionFired
        afterInterventionFired = second?.interventionFired
    }

    public enum DiffError: Error { case nonFiniteTelemetry }

    public var formatted: String {
        func line(_ name: String, _ metric: Metric) -> String {
            let before = metric.before.map { String(format: "%.6f", $0) } ?? "unavailable"
            let after = metric.after.map { String(format: "%.6f", $0) } ?? "unavailable"
            let delta = metric.delta.map { String(format: "%+.6f", $0) } ?? "unavailable"
            return "\(name): \(before) → \(after) (delta \(delta))"
        }
        return (["Run snapshots: \(beforeTimestamp) → \(afterTimestamp)",
                 line("decay weight", decayWeight), line("rot score", rotScore),
                 line("lighthouse saliency", lighthouseSaliency),
                 "referee: \(beforeRefereeMode ?? "unavailable") → \(afterRefereeMode ?? "unavailable")",
                 "intervention: \(beforeInterventionFired.map(String.init) ?? "unavailable") → \(afterInterventionFired.map(String.init) ?? "unavailable")",
                 "Two endpoints only; no intermediate trajectory is inferred."])
            .joined(separator: "\n")
    }
}
