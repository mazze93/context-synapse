import Foundation

// MARK: - SynapseWeightState
// Per-synapse mutable weight state. Owns decay math, rot scoring,
// lighthouse floor protection, and cauterization logic.
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §4, §5, §6
//
// ADR-001: Affect vector updates are ASYNC — affect vector surfaces
// as available context only. Lighthouse anchors set on confirmed
// user choice, never via automatic inference. See session artifact.

public struct SynapseWeightState {
    // MARK: - Identity
    public let synapseId: String
    public let isLighthouse: Bool

    // MARK: - Mutable state
    /// Interaction history, capped at DecayConstants.maxInteractionHistory
    public private(set) var interactions: [InteractionRecord]
    /// Number of child synapses depending on this one (connectivity factor)
    public var childCount: Int
    /// Current rot score [0.0, 1.0] — recomputed by SynapseManager
    public private(set) var rotScore: Double
    /// Whether cauterization has been flagged this session
    public private(set) var requiresCauterization: Bool
    /// Timestamp of last interaction
    public private(set) var lastInteractionAt: Date
    /// Session start time (for rot drift calculation)
    public let sessionStart: Date
    /// Semantic distance strategy — injected, swappable
    private let distanceStrategy: SemanticDistanceStrategy

    // MARK: - Init
    public init(
        synapseId: String,
        isLighthouse: Bool = false,
        childCount: Int = 0,
        sessionStart: Date = Date(),
        distanceStrategy: SemanticDistanceStrategy = StructuralHeuristicDistance()
    ) {
        self.synapseId = synapseId
        self.isLighthouse = isLighthouse
        self.childCount = childCount
        self.rotScore = 0.0
        self.requiresCauterization = false
        self.interactions = []
        self.lastInteractionAt = sessionStart
        self.sessionStart = sessionStart
        self.distanceStrategy = distanceStrategy
    }

    // MARK: - Interaction recording
    public mutating func record(_ event: InteractionEventType) {
        let record = InteractionRecord(eventType: event, synapseId: synapseId)
        interactions.append(record)
        // Cap history to avoid unbounded growth
        if interactions.count > DecayConstants.maxInteractionHistory {
            interactions.removeFirst(interactions.count - DecayConstants.maxInteractionHistory)
        }
        if event != .windowSwitchAway {
            lastInteractionAt = record.timestamp
        }
    }

    // MARK: - Utility Score U(s, t)
    // Recency-weighted moving average over interaction history.
    // U(s,t) = Σ successᵢ · e^(-μ(t - tᵢ)) / Σ e^(-μ(t - tᵢ))
    // μ = DecayConstants.utilityDecayMu — utility fades ~2x slower than saliency
    public func utilityScore(at now: Date = Date()) -> Double {
        guard !interactions.isEmpty else { return 0.5 } // neutral prior
        var numerator = 0.0
        var denominator = 0.0
        let mu = DecayConstants.utilityDecayMu
        for record in interactions {
            let dt = now.timeIntervalSince(record.timestamp)
            let weight = exp(-mu * dt)
            numerator += record.successWeight * weight
            denominator += weight
        }
        guard denominator > 0 else { return 0.5 }
        return max(0.0, min(1.0, numerator / denominator))
    }

    // MARK: - Dynamic Decay Constant λ(s)
    // λ(s) = λ_base · (1 - connectivityFactor(s)) · rotMultiplier(s)
    // A highly connected synapse decays slower.
    // A rotting synapse decays faster.
    public func dynamicDecayConstant(maxConnections: Int = 50) -> Double {
        let connectivityFactor = maxConnections > 0
            ? min(1.0, Double(childCount) / Double(maxConnections))
            : 0.0
        let rotMultiplier = 1.0 + rotScore * DecayConstants.rotLambdaAmplifier
        return DecayConstants.baseLambda * (1.0 - connectivityFactor) * rotMultiplier
    }

    // MARK: - Decay Weight W_decay(s, t)
    // W_decay(s,t) = W_base · e^(-λ(s) · t) · U(s,t)
    public func decayWeight(
        baseWeight: Double = 1.0,
        maxConnections: Int = 50,
        at now: Date = Date()
    ) -> Double {
        let t = now.timeIntervalSince(lastInteractionAt)
        let lambda = dynamicDecayConstant(maxConnections: maxConnections)
        let U = utilityScore(at: now)
        return baseWeight * exp(-lambda * t) * U
    }

    // MARK: - Rot Score computation
    // RotScore(s) = D(s, lighthouse) · tanh(T_drift / T_threshold) · VelocityAmplifier
    // Lighthouse synapses cannot rot (RotScore always 0.0).
    // Design ref: Ops Manual §5.2
    public mutating func recomputeRotScore(
        content: SynapseContent,
        lighthouse: SynapseContent,
        at now: Date = Date()
    ) {
        guard !isLighthouse else {
            rotScore = 0.0
            requiresCauterization = false
            return
        }

        let distance = distanceStrategy.distance(from: content, to: lighthouse)
        let tDrift = now.timeIntervalSince(lastInteractionAt)
        let tRatio = tDrift / DecayConstants.rotThresholdSeconds
        let tanhFactor = tanh(tRatio)

        // VelocityAmplifier: amplifies rot when actively engaged with drifting synapse
        let interactionRate = recentInteractionRate(windowSeconds: 300, at: now)
        let maxRate = 10.0 // interactions per 5-min window considered "high velocity"
        let velocityAmplifier = 1.0 + min(interactionRate / maxRate, 1.0)

        rotScore = max(0.0, min(1.0, distance * tanhFactor * velocityAmplifier))
        requiresCauterization = rotScore >= DecayConstants.rotCauterizeThreshold
    }

    // MARK: - Final Weight W_final(s, t)
    // W_final(s,t) = max(floor(s), W_decay(s,t) · (1 - α · RotScore(s)))
    // Lighthouse floor ensures the primary goal is always findable.
    // Design ref: Ops Manual §6.2
    public func finalWeight(
        baseWeight: Double = 1.0,
        maxConnections: Int = 50,
        at now: Date = Date()
    ) -> Double {
        let floor = isLighthouse ? DecayConstants.lighthouseFloor : 0.0
        let Wdecay = decayWeight(baseWeight: baseWeight, maxConnections: maxConnections, at: now)
        let rotPenalty = 1.0 - DecayConstants.rotAlpha * rotScore
        let computed = Wdecay * max(0.0, rotPenalty)
        return max(floor, computed)
    }

    // MARK: - Cauterization application
    // When flagged, spike the effective decay constant by CAUTERIZE_MULTIPLIER.
    // The SynapseManager detects requiresCauterization and calls this.
    // Does NOT delete the synapse — spikes decay cost to force re-evaluation.
    public func cauterizedDecayConstant(maxConnections: Int = 50) -> Double {
        guard requiresCauterization else { return dynamicDecayConstant(maxConnections: maxConnections) }
        return dynamicDecayConstant(maxConnections: maxConnections) * DecayConstants.rotCauterizeMultiplier
    }

    // MARK: - Lighthouse degradation detection
    // Returns true when lighthouse saliency is degrading but above floor.
    // Triggers the "Where was I?" re-sync prompt at W_final < 0.6.
    public func lighthouseNeedsResync(maxConnections: Int = 50, at now: Date = Date()) -> Bool {
        guard isLighthouse else { return false }
        let w = finalWeight(maxConnections: maxConnections, at: now)
        return w < 0.6 && w >= DecayConstants.lighthouseFloor
    }

    // MARK: - Helper: recent interaction rate
    private func recentInteractionRate(windowSeconds: Double, at now: Date) -> Double {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        let recent = interactions.filter { $0.timestamp >= cutoff }
        return Double(recent.count)
    }
}

// MARK: - SessionContext
// Passed to Referee.evaluateSaliency — session-level shared state.

public struct SessionContext {
    public let lighthouse: SynapseContent
    public let maxConnections: Int
    public let decayConstant: Double
    public let sessionStart: Date
    /// Time since last interaction with the lighthouse synapse
    public let timeSinceLastLighthouseInteraction: TimeInterval

    public init(
        lighthouse: SynapseContent,
        maxConnections: Int = 50,
        decayConstant: Double = DecayConstants.baseLambda,
        sessionStart: Date = Date(),
        timeSinceLastLighthouseInteraction: TimeInterval = 0
    ) {
        self.lighthouse = lighthouse
        self.maxConnections = maxConnections
        self.decayConstant = decayConstant
        self.sessionStart = sessionStart
        self.timeSinceLastLighthouseInteraction = timeSinceLastLighthouseInteraction
    }
}
