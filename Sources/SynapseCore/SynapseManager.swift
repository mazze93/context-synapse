import Foundation

// MARK: - SynapseManager (v0.4)
// Session coordinator. Owns what the per-query CLI could not:
//   - a session-persistent map of synapse states (the CLI's ephemeral
//     SynapseWeightState was the root cause of the inert-rot bug — a
//     coordinator that persists clocks eliminates the class)
//   - lighthouse designation for the session
//   - SynapticCircuit lifecycle + backward-pass wiring after each
//     interaction (INTEGRATION.md recipe)
//   - the RSA epoch layer: every observation snapshots an NxN
//     representational-similarity matrix over [lighthouse + live synapses],
//     so claims about drift and deviation from the anchor are backed by
//     recorded state across epochs, not vibes. This is the "region matrix"
//     machinery repointed at real project data.
//
// Persistence: session.json next to config.json (atomic writes).
// ADR-001/-002 hold: no affect inference, no operational-context inference.

// MARK: - Codable session model

public struct SynapseSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var fileReferences: [String]
    public var functionNames: [String]
    public var isLighthouse: Bool
    public var childCount: Int
    public var interactions: [InteractionRecord]
    public var lastInteractionAt: Date
    public var rotScore: Double

    public var content: SynapseContent {
        SynapseContent(id: id, text: text, fileReferences: fileReferences,
                       functionNames: functionNames, createdAt: lastInteractionAt)
    }
}

/// One epoch = one observed interaction. The matrix is RSA-style similarity
/// (1 − distance) over rows/cols `labels`; row 0 is always the lighthouse (⚓).
public struct EpochSnapshot: Codable, Equatable, Sendable {
    public let index: Int
    public let timestamp: Date
    public let labels: [String]
    public let matrix: [[Double]]
    public let lighthouseSaliency: Double
    /// W_final of the synapse observed this epoch (decay telemetry).
    public let observedDecayWeight: Double
    public let rotScores: [String: Double]
    public let predictionErrors: [String: Double]
    public let epistemicallyUnstable: [String]
}

public struct SessionState: Codable, Sendable {
    public var sessionId: String
    public var startedAt: Date
    /// The lighthouse this session's epochs were recorded against. Epochs
    /// from different anchors must never mix — a session is one anchor's
    /// evidence. Changing the lighthouse starts a fresh session.
    public var lighthouseID: String?
    public var synapses: [SynapseSnapshot]
    public var epochs: [EpochSnapshot]

    public init(sessionId: String = UUID().uuidString,
                startedAt: Date = Date(),
                lighthouseID: String? = nil,
                synapses: [SynapseSnapshot] = [],
                epochs: [EpochSnapshot] = []) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.lighthouseID = lighthouseID
        self.synapses = synapses
        self.epochs = epochs
    }
}

// MARK: - Manager

public actor SynapseManager {

    /// Non-lighthouse synapses tracked in the RSA matrix. Oldest (by
    /// lastInteractionAt) are evicted past this — the matrix must stay
    /// readable in a terminal.
    public static let maxTrackedSynapses = 10
    /// Epoch history cap — session.json must not grow unbounded.
    public static let maxEpochHistory = 200

    private let sessionURL: URL
    private let lighthouse: LighthouseRecord?
    private let distanceStrategy: any SemanticDistanceStrategy & Sendable
    private let circuit = SynapticCircuit()
    private var state: SessionState
    private var circuitSeeded = false
    /// Cached at seed time — avoids copying the whole circuit snapshot
    /// across the actor boundary just to look up one UUID.
    private var lighthouseNodeID: UUID?

    // MARK: Init

    public init(sessionURL: URL,
                lighthouse: LighthouseRecord?,
                distanceStrategy: any SemanticDistanceStrategy & Sendable = StructuralHeuristicDistance()) {
        self.sessionURL = sessionURL
        self.lighthouse = lighthouse
        self.distanceStrategy = distanceStrategy
        if let data = try? Data(contentsOf: sessionURL),
           let loaded = try? JSONDecoder().decode(SessionState.self, from: data),
           loaded.lighthouseID == lighthouse?.id {
            self.state = loaded
        } else {
            // No prior session, or the anchor changed (--resync / new
            // --lighthouse): epochs recorded against a different anchor are
            // not evidence for this one. Start fresh.
            self.state = SessionState(lighthouseID: lighthouse?.id)
        }
    }

    public var epochs: [EpochSnapshot] { state.epochs }
    public var trackedSynapses: [SynapseSnapshot] { state.synapses }

    // MARK: - Observe (the epoch tick)

    /// Record one interaction: update the synapse's persistent state, run the
    /// circuit forward/backward passes, snapshot the RSA matrix, persist.
    /// Returns nil when no lighthouse is set — epochs are only meaningful
    /// relative to an anchor.
    @discardableResult
    public func observe(_ content: SynapseContent,
                        event: InteractionEventType,
                        at now: Date = Date()) async -> EpochSnapshot? {
        guard let lighthouse else { return nil }
        let lighthouseContent = lighthouse.content
        await seedCircuitIfNeeded()

        // 1. Find-or-create the synapse. Reuse by exact text match so a
        //    revisited thread strengthens one synapse instead of spawning
        //    a twin; otherwise it is a new thread of attention.
        let existingIdx = state.synapses.firstIndex { !$0.isLighthouse && $0.text == content.text }
        var snapshot: SynapseSnapshot
        let isNew = existingIdx == nil
        if let idx = existingIdx {
            snapshot = state.synapses[idx]
        } else {
            snapshot = SynapseSnapshot(
                id: content.id, text: content.text,
                fileReferences: content.fileReferences,
                functionNames: content.functionNames,
                isLighthouse: false, childCount: 0,
                interactions: [], lastInteractionAt: now, rotScore: 0.0
            )
        }

        // 2. Circuit registration + bidirectional coupling to the lighthouse.
        if isNew {
            let node = SynapticNode(synapseID: snapshot.id, prior: .uninformed)
            await circuit.register(node)
            if let lhID = lighthouseNodeID {
                // Bidirectional coupling to the anchor; edge weight = initial
                // similarity (propagationCoefficient derives from weight).
                let similarity = 1.0 - distanceStrategy.distance(from: snapshot.content, to: lighthouseContent)
                await circuit.connect(CircuitEdge(source: lhID, target: node.id, weight: similarity))
                await circuit.connect(CircuitEdge(source: node.id, target: lhID, weight: similarity))
            }
        }

        // 3. Forward pass before the observation (ordering contract).
        _ = await circuit.forwardPass()

        // 4. Rot: the drift clock anchors to the LIGHTHOUSE (setAt), for new
        //    AND revisited synapses alike. Drift is time-away-from-anchor —
        //    NOT time since you last touched the drifting thread. Anchoring
        //    to the synapse's own lastInteractionAt lets a user hammering a
        //    rabbit hole reset their own rot to ~0 on every repeat (probe-
        //    confirmed regression: saliency read 1% then 100%/100% on
        //    repeats). When lighthouse *interactions* are tracked (v0.5),
        //    this becomes time-since-last-lighthouse-interaction.
        var weightState = SynapseWeightState(
            restoring: snapshot,
            sessionStart: state.startedAt,
            distanceStrategy: distanceStrategy
        )
        weightState.recomputeRotScore(content: snapshot.content,
                                      lighthouse: lighthouseContent,
                                      driftReference: lighthouse.setAtDate ?? now,
                                      at: now)
        weightState.record(event)
        let observedDecayWeight = weightState.finalWeight(at: now)

        snapshot.interactions = weightState.interactions
        snapshot.lastInteractionAt = weightState.lastInteractionAt
        snapshot.rotScore = weightState.rotScore

        if let idx = existingIdx { state.synapses[idx] = snapshot }
        else { state.synapses.append(snapshot) }
        evictStaleSynapses()

        // 5. Backward pass: the interaction outcome is the observation.
        let backward = await circuit.backwardPass(observations: [snapshot.id: event.successWeight])

        // 6. RSA matrix across [lighthouse + tracked synapses].
        let (labels, matrix) = rsaMatrix(lighthouse: lighthouseContent)
        let epoch = EpochSnapshot(
            index: (state.epochs.last?.index ?? -1) + 1,
            timestamp: now,
            labels: labels,
            matrix: matrix,
            lighthouseSaliency: max(0.0, min(1.0, 1.0 - snapshot.rotScore)),
            observedDecayWeight: observedDecayWeight,
            // Keyed by synapse id (unique by construction) — keying by text
            // would trap in Dictionary(uniqueKeysWithValues:) on collision.
            rotScores: Dictionary(uniqueKeysWithValues: state.synapses.map { ($0.id, $0.rotScore) }),
            predictionErrors: backward.predictionErrors,
            epistemicallyUnstable: backward.epistemicallyUnstableNodes
        )
        state.epochs.append(epoch)
        if state.epochs.count > Self.maxEpochHistory {
            state.epochs.removeFirst(state.epochs.count - Self.maxEpochHistory)
        }

        persist()
        return epoch
    }

    // MARK: - RSA

    static let lighthouseSynapseID = "⚓lighthouse"

    private func rsaMatrix(lighthouse: SynapseContent) -> (labels: [String], matrix: [[Double]]) {
        var rows: [(label: String, content: SynapseContent)] = [("⚓ " + lighthouse.text, lighthouse)]
        rows += state.synapses
            .filter { !$0.isLighthouse }
            .sorted { $0.lastInteractionAt > $1.lastInteractionAt }
            .map { ($0.text, $0.content) }
        let n = rows.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in i..<n {
                let sim = i == j ? 1.0
                    : max(0.0, min(1.0, 1.0 - distanceStrategy.distance(from: rows[i].content, to: rows[j].content)))
                matrix[i][j] = sim
                matrix[j][i] = sim
            }
        }
        return (rows.map(\.label), matrix)
    }

    // MARK: - Private

    private func seedCircuitIfNeeded() async {
        guard !circuitSeeded else { return }
        circuitSeeded = true
        // Lighthouse node: earned confidence (ADR-003), plus nodes for any
        // synapses restored from a previous invocation of this session.
        if lighthouse != nil {
            let node = SynapticNode(synapseID: Self.lighthouseSynapseID, prior: .lighthouse())
            lighthouseNodeID = node.id
            await circuit.register(node)
        }
        for snapshot in state.synapses where !snapshot.isLighthouse {
            await circuit.register(SynapticNode(synapseID: snapshot.id, prior: .uninformed))
        }
    }

    private func evictStaleSynapses() {
        let live = state.synapses.filter { !$0.isLighthouse }
        guard live.count > Self.maxTrackedSynapses else { return }
        let keep = Set(live.sorted { $0.lastInteractionAt > $1.lastInteractionAt }
            .prefix(Self.maxTrackedSynapses).map(\.id))
        state.synapses.removeAll { !$0.isLighthouse && !keep.contains($0.id) }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: sessionURL, options: .atomic)
    }
}

// MARK: - RSA rendering (pure, testable, terminal-first)

public enum RSARenderer {

    static let shades: [Character] = [" ", "░", "▒", "▓", "█"]
    static let sparks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    static func shade(_ v: Double) -> Character {
        let clamped = max(0.0, min(1.0, v))
        return shades[min(shades.count - 1, Int(clamped * Double(shades.count)))]
    }

    /// NxN heatmap. Row 0 is the lighthouse; every cell is similarity in
    /// [0,1] rendered as a shade block (doubled for square-ish aspect).
    public static func heatmap(_ epoch: EpochSnapshot, labelWidth: Int = 18) -> String {
        var out = "RSA · epoch \(epoch.index) · \(epoch.labels.count)×\(epoch.labels.count) · similarity 1−D(a,b)\n"
        for (i, label) in epoch.labels.enumerated() {
            let clipped = label.count > labelWidth
                ? String(label.prefix(labelWidth - 1)) + "…"
                : label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            let cells = epoch.matrix[i].map { c -> String in String(repeating: String(shade(c)), count: 2) }
            out += clipped + " │" + cells.joined() + "│\n"
        }
        out += String(repeating: " ", count: labelWidth) + "  " +
            epoch.labels.indices.map { String($0 % 10) + " " }.joined() + "\n"
        return out
    }

    /// Lighthouse saliency across epochs as a sparkline — the one-glance
    /// answer to "how anchored has this session been over time?"
    public static func saliencyStrip(_ epochs: [EpochSnapshot]) -> String {
        guard !epochs.isEmpty else { return "(no epochs yet — run some queries with a lighthouse set)" }
        let line = epochs.map { e -> String in
            let idx = min(sparks.count - 1, Int(max(0.0, min(1.0, e.lighthouseSaliency)) * Double(sparks.count)))
            return String(sparks[idx])
        }.joined()
        let last = epochs.last!
        return "anchor saliency · \(epochs.count) epochs\n" + line +
            "  now \(Int((last.lighthouseSaliency * 100).rounded()))%\n"
    }
}
