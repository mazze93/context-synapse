import Foundation

// MARK: - SynapseReferee Protocol
// The Referee is the objective executive function layer.
// It does not judge content — it judges mechanical necessity.
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §7
//
// Two implementations:
//   FunctionalReferee  — default, silent adjustments, no interrupts
//   AbrasiveReferee    — user-initiated opt-in, active friction, "kick in the pants"
//
// User stated preference: AbrasiveReferee.
// AbrasiveReferee is NOT the default. It requires explicit config opt-in.
// See config.json: referee.mode = "abrasive"
//
// ADR-002 boundary: The Referee has no model for collapse.
// It manages distraction. It does not assess operational state.
// The operational context layer is permanently out of scope.

public protocol SynapseReferee {
    func evaluateSaliency(
        for state: SynapseWeightState,
        content: SynapseContent,
        in context: SessionContext
    ) -> Double
}

// MARK: - ContextIntervention
// Emitted by AbrasiveReferee when rot + drift threshold is exceeded.
// Surfaces to UI — never a lecture, always a data report + choices.

public struct ContextIntervention {
    public let lighthouseDescription: String
    public let currentSynapseDescription: String
    public let minutesInDrift: Int
    public let lighthouseSaliencyNow: Double
    public let lighthouseSaliencyAtSessionStart: Double

    public var formattedMessage: String {
        """
        ⚠️  Context Rot detected.

        Primary goal (Lighthouse): \(lighthouseDescription)
        Current drift:             \(currentSynapseDescription)
        Time in drift:             \(minutesInDrift) minutes
        Lighthouse saliency:       \(Int(lighthouseSaliencyNow * 100))% (was \(Int(lighthouseSaliencyAtSessionStart * 100))% at session start)

        → Continue on current task
        → Return to Lighthouse
        → Promote current task to Lighthouse
        → Dismiss for 15 minutes
        """
    }

    public init(
        lighthouseDescription: String,
        currentSynapseDescription: String,
        minutesInDrift: Int,
        lighthouseSaliencyNow: Double,
        lighthouseSaliencyAtSessionStart: Double = 1.0
    ) {
        self.lighthouseDescription = lighthouseDescription
        self.currentSynapseDescription = currentSynapseDescription
        self.minutesInDrift = minutesInDrift
        self.lighthouseSaliencyNow = lighthouseSaliencyNow
        self.lighthouseSaliencyAtSessionStart = lighthouseSaliencyAtSessionStart
    }
}

// MARK: - FunctionalReferee (default)
// Silent saliency management. No interrupts. Appropriate for most sessions.
//
// Saliency weight distribution:
//   Interaction Velocity  50% — did the user actually do something with this?
//   Structural Connectivity 30% — how many synapses depend on this one?
//   Temporal Decay         20% — standard Bayesian fading
//
// Lighthouse: always elevated, never below floor.
// Side quests elevated to Shadow Context when RotScore > 0.5.

public struct FunctionalReferee: SynapseReferee {
    // Saliency weights — sum to 1.0
    private let velocityWeight: Double = 0.50
    private let connectivityWeight: Double = 0.30
    private let decayWeight: Double = 0.20

    public init() {}

    public func evaluateSaliency(
        for state: SynapseWeightState,
        content: SynapseContent,
        in context: SessionContext
    ) -> Double {
        let now = Date()

        // 1. Interaction Velocity — time-discounted interaction signal
        let timeSinceAction = now.timeIntervalSince(state.lastInteractionAt)
        let velocity = 1.0 / (1.0 + log1p(max(0, timeSinceAction / 300.0)))

        // 2. Structural Connectivity — dependency graph weight
        let connectivity = context.maxConnections > 0
            ? min(1.0, Double(state.childCount) / Double(context.maxConnections))
            : 0.0

        // 3. Temporal Decay — standard Bayesian fading
        let decay = state.finalWeight(
            baseWeight: 1.0,
            maxConnections: context.maxConnections,
            at: now
        )

        let raw = (velocity * velocityWeight)
            + (connectivity * connectivityWeight)
            + (decay * decayWeight)

        // Lighthouse protection: always at or above floor, boosted to top of stack
        if state.isLighthouse {
            return max(DecayConstants.lighthouseFloor, min(1.0, raw * 1.25))
        }

        return max(0.0, min(1.0, raw))
    }

    /// Shadow Context check — should this side quest be forked?
    /// Returns true when RotScore exceeds 0.5 and synapse is not the lighthouse.
    public func shouldForkToShadowContext(state: SynapseWeightState) -> Bool {
        return !state.isLighthouse && state.rotScore > 0.5
    }
}

// MARK: - AbrasiveReferee (user-initiated opt-in)
// Active friction. Designed to break hyperfocus loops.
// NOT the default. Requires config: referee.mode = "abrasive"
//
// Activation: RotScore > rotThreshold sustained for > maxDriftMinutes
// On trigger:
//   - Force-decays drifting synapse to 0.1
//   - Promotes Lighthouse to 1.0
//   - Emits ContextIntervention to UI
//
// AbrasiveReferee is abrasive, not cruel.
// It presents data. It offers choices. It does not lecture.
// It does NOT activate on collapse — only on distraction.
// See ADR-002: operational context layer is permanently out of scope.

public struct AbrasiveReferee: SynapseReferee {
    public let maxDriftMinutes: Double
    public let rotThreshold: Double
    public let interventionCooldownMinutes: Double

    /// Track last intervention time to enforce cooldown
    private var lastInterventionAt: Date?
    /// Track session-start lighthouse saliency for intervention message
    private let lighthouseSaliencyAtStart: Double

    public init(
        maxDriftMinutes: Double = 15.0,
        rotThreshold: Double = 0.3,
        interventionCooldownMinutes: Double = 15.0,
        lighthouseSaliencyAtStart: Double = 1.0
    ) {
        self.maxDriftMinutes = maxDriftMinutes
        self.rotThreshold = rotThreshold
        self.interventionCooldownMinutes = interventionCooldownMinutes
        self.lighthouseSaliencyAtStart = lighthouseSaliencyAtStart
    }

    public func evaluateSaliency(
        for state: SynapseWeightState,
        content: SynapseContent,
        in context: SessionContext
    ) -> Double {
        let now = Date()
        let timeSinceLastLighthouse = context.timeSinceLastLighthouseInteraction
        let driftMinutes = timeSinceLastLighthouse / 60.0

        // Check if AbrasiveReferee kick should trigger
        let shouldKick = !state.isLighthouse
            && state.rotScore >= rotThreshold
            && driftMinutes >= maxDriftMinutes
            && !isInCooldown(at: now)

        if shouldKick {
            // Force saliency to floor — Referee stops helping with the distraction
            return 0.1
        }

        // Below threshold: behave like FunctionalReferee
        let timeSinceAction = now.timeIntervalSince(state.lastInteractionAt)
        let velocity = 1.0 / (1.0 + log1p(max(0, timeSinceAction / 300.0)))
        let connectivity = context.maxConnections > 0
            ? min(1.0, Double(state.childCount) / Double(context.maxConnections))
            : 0.0
        let decay = state.finalWeight(
            baseWeight: 1.0,
            maxConnections: context.maxConnections,
            at: now
        )

        let raw = (velocity * 0.50) + (connectivity * 0.30) + (decay * 0.20)

        if state.isLighthouse {
            return max(DecayConstants.lighthouseFloor, min(1.0, raw * 1.25))
        }

        return max(0.0, min(1.0, raw))
    }

    /// Build a ContextIntervention for UI emission.
    /// Call this when evaluateSaliency would return 0.1 (the kick condition).
    public func buildIntervention(
        lighthouseContent: SynapseContent,
        driftingContent: SynapseContent,
        driftMinutes: Int,
        lighthouseSaliencyNow: Double
    ) -> ContextIntervention {
        ContextIntervention(
            lighthouseDescription: lighthouseContent.text,
            currentSynapseDescription: driftingContent.text,
            minutesInDrift: driftMinutes,
            lighthouseSaliencyNow: lighthouseSaliencyNow,
            lighthouseSaliencyAtSessionStart: lighthouseSaliencyAtStart
        )
    }

    /// Whether the cooldown period is still active.
    private func isInCooldown(at now: Date) -> Bool {
        guard let last = lastInterventionAt else { return false }
        return now.timeIntervalSince(last) < interventionCooldownMinutes * 60.0
    }
}

// MARK: - RefereeMode
// Serializable referee config. Stored in default_config.json.

public enum RefereeMode: String, Codable, CaseIterable {
    case functional         // default — silent adjustments
    case abrasive           // user-initiated — active friction
}

// MARK: - RefereeConfig
// Persisted user preference for referee behavior.

public struct RefereeConfig: Codable, Equatable {
    public var mode: RefereeMode
    public var driftThresholdMinutes: Double
    public var rotThreshold: Double
    public var interventionCooldownMinutes: Double

    public init(
        mode: RefereeMode = .functional,
        driftThresholdMinutes: Double = 15.0,
        rotThreshold: Double = 0.3,
        interventionCooldownMinutes: Double = 15.0
    ) {
        self.mode = mode
        self.driftThresholdMinutes = driftThresholdMinutes
        self.rotThreshold = rotThreshold
        self.interventionCooldownMinutes = interventionCooldownMinutes
    }

    /// Build the appropriate Referee instance from config.
    public func makeReferee(lighthouseSaliencyAtStart: Double = 1.0) -> SynapseReferee {
        switch mode {
        case .functional:
            return FunctionalReferee()
        case .abrasive:
            return AbrasiveReferee(
                maxDriftMinutes: driftThresholdMinutes,
                rotThreshold: rotThreshold,
                interventionCooldownMinutes: interventionCooldownMinutes,
                lighthouseSaliencyAtStart: lighthouseSaliencyAtStart
            )
        }
    }
}
