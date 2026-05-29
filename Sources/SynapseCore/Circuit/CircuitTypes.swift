// MARK: - CircuitTypes.swift
// Context Synapse v0.3 — Bedrock Layer: Value Types
//
// All types in this file are pure value types (structs/enums).
// No actor state. No side effects. Safe to copy across concurrency domains.
//
// Dependency graph (reads downward, no cycles):
//   CircuitConstants
//       └── SynapticPrior
//           └── SynapticNode
//               └── CircuitEdge
//                   └── [Output types: ForwardPassResult, BackwardPassResult,
//                                      CircuitSnapshot, FaultInjectionReport,
//                                      CalibrationReport]
//
// Integration note: SynapseWeightState (v0.3 target) consumes ForwardPassResult.
//   Replace W_base(s) with ForwardPassResult.predictions[synapseID].
//   Replace connectivity_factor(s) with ForwardPassResult.connectivityFactors[synapseID].

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CircuitConstants
// All tunable parameters in one place. Every constant is documented.
// When calibrating: run FaultInjectionSuite.runFullSuite() and let
// CalibrationReport.recommendedRotLambdaAmplifier override these defaults.
// ─────────────────────────────────────────────────────────────────────────────

public enum CircuitConstants {
    // ── Learning rate ─────────────────────────────────────────────────────────
    /// Starting learning rate. High = fast early adaptation.
    /// Decays per-pass: η(τ) = etaBase / (1 + τ · etaDecayFactor)
    public static let etaBase: Double = 0.1

    /// Controls how quickly the learning rate drops off.
    /// At τ=50 passes: η ≈ 0.067. At τ=200: η ≈ 0.033.
    public static let etaDecayFactor: Double = 0.008

    // ── Error propagation ─────────────────────────────────────────────────────
    /// Maximum fraction of a source node's prediction error that bleeds
    /// to a target node across one edge, scaled by edge weight.
    /// 0.3 = strong relational coupling. 0.1 = near-isolated nodes.
    public static let maxErrorPropagationFraction: Double = 0.3

    /// Minimum error magnitude required for propagation to register.
    /// Prevents noise from creating spurious uncertainty increases.
    public static let minimumMeaningfulBleed: Double = 0.05

    // ── Fault injection ───────────────────────────────────────────────────────
    /// Learning rate multiplier applied during fault injection runs.
    /// Injected faults are high-signal events; priors should feel them.
    public static let faultInjectionEtaMultiplier: Double = 2.5

    /// Maximum edge hops measured during fault propagation depth test.
    /// Faults that cascade beyond this are flagged as pathological.
    public static let maxFaultPropagationDepth: Int = 5

    // ── Epistemic instability ─────────────────────────────────────────────────
    /// Prediction error above this threshold triggers instability flag.
    /// Feeds into BackwardPassResult.epistemicallyUnstableNodes.
    public static let instabilityErrorThreshold: Double = 0.4

    /// Prior uncertainty (variance proxy) above this threshold triggers
    /// instability flag. High uncertainty = weakly calibrated prior.
    public static let instabilityUncertaintyThreshold: Double = 0.15

    // ── Decay formula ─────────────────────────────────────────────────────────
    /// Coefficient applied to prediction error in the decay amplifier.
    /// λ(s,t) += predictionError(s) · errorDecayAmplifier
    /// Replaces static ROT_LAMBDA_AMPLIFIER with a dynamic signal.
    /// Calibration target: run FaultInjectionSuite and use
    /// CalibrationReport.recommendedRotLambdaAmplifier instead.
    public static let errorDecayAmplifier: Double = 1.2

    /// Lighthouse floor ceiling. floor(s) = prior.mean(s) · this value.
    /// Result: lighthouse synapses earn their floor; it is not a grant.
    /// ADR-003: replaces the static 0.4 constant.
    public static let lighthouseFloorCeiling: Double = 0.4

    // ── Prior integrity ───────────────────────────────────────────────────────
    /// Maximum evidence weight a prior can accumulate (α + β cap).
    /// Prevents lighthouse ossification: priors locked by sheer volume.
    /// Above cap, updates are blocked until user-initiated prior reset (ADR-003).
    public static let evidenceWeightCap: Double = 100.0

    /// Minimum alpha value. Prior can never go below uninformed baseline.
    /// Prevents error flooding from collapsing all priors to uselessness.
    public static let minimumAlpha: Double = 1.0
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SynapticPrior
// Mutable Beta-distributed belief about a synapse's utility.
//
// This is what W_base(s) has always needed to be.
//
// Renamed from Prior to SynapticPrior to avoid module-level conflict
// with SynapseCore.Prior (the simpler Beta wrapper used for dimension weights).
//
// Beta(α, β):
//   mean     = α / (α + β)       — expected utility
//   variance = αβ / (α+β)²(α+β+1) — calibration confidence
//
// Conjugate prior for Bernoulli observations: successᵢ values from the
// interaction weight table map directly to update inputs.
// ─────────────────────────────────────────────────────────────────────────────

public struct SynapticPrior: Sendable, Codable, Equatable {
    /// Pseudo-count of successful interactions.
    public private(set) var alpha: Double

    /// Pseudo-count of unsuccessful interactions.
    public private(set) var beta: Double

    /// Expected utility: E[SynapticPrior] = α / (α + β). Range: (0, 1).
    public var mean: Double { alpha / (alpha + beta) }

    /// Uncertainty proxy. Approaches 0 as evidence accumulates.
    /// High uncertainty = prior is weakly calibrated, easily revised.
    public var uncertainty: Double {
        let n = alpha + beta
        return (alpha * beta) / (n * n * (n + 1.0))
    }

    /// Total evidence accumulated. Small n = weak prior, easily overwritten.
    /// Intentional fragility: early priors should be cheap to correct.
    public var evidenceWeight: Double { alpha + beta }

    /// Whether this prior has hit the evidence weight cap.
    /// See CircuitConstants.evidenceWeightCap. ADR-003.
    public var isOssified: Bool { evidenceWeight >= CircuitConstants.evidenceWeightCap }

    // ── Update ────────────────────────────────────────────────────────────────

    /// Update prior given an observed utility in [0, 1].
    /// Blocked if ossified — surface to user for explicit reset.
    ///
    /// - Parameters:
    ///   - observation: successᵢ value from interaction weight table [0.0–1.0]
    ///   - eta: caller-supplied learning rate (use SynapticCircuit.currentLearningRate)
    public mutating func update(observation: Double, eta: Double) {
        guard !isOssified else { return }
        let clamped = max(0.0, min(1.0, observation))
        let newAlpha = alpha + eta * clamped
        let newBeta  = beta  + eta * (1.0 - clamped)
        // Enforce minimum alpha floor — prevents error flooding collapse
        alpha = max(CircuitConstants.minimumAlpha, newAlpha)
        beta  = newBeta
    }

    /// Increase uncertainty only (no mean shift). Used during error propagation:
    /// adjacent nodes become less confident without being penalized for other nodes' errors.
    public mutating func widenUncertainty(by amount: Double) {
        guard !isOssified else { return }
        beta += amount
    }

    // ── Factories ─────────────────────────────────────────────────────────────

    /// Uniform prior. No commitment. α=β=1 → mean=0.5.
    /// Use for new synapses with no interaction history.
    public static let uninformed = SynapticPrior(alpha: 1.0, beta: 1.0)

    /// High-confidence lighthouse prior. High mean, high evidence weight.
    /// Still mutable. Still correctable. NOT a permanent floor grant (ADR-003).
    ///
    /// - Parameter confidence: pseudo-count base. 10 = strong but revisable.
    public static func lighthouse(confidence: Double = 10.0) -> SynapticPrior {
        SynapticPrior(alpha: confidence * 0.8, beta: confidence * 0.2)
    }

    public init(alpha: Double, beta: Double) {
        self.alpha = max(CircuitConstants.minimumAlpha, alpha)
        self.beta  = max(0.01, beta)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SynapticNode
// Atomic unit of the circuit. Holds generative model state.
// Maps 1:1 to a Synapse in SynapseCore via synapseID (foreign key).
// ─────────────────────────────────────────────────────────────────────────────

public struct SynapticNode: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    /// Foreign key into SynapseCore. Must match the synapse's identifier exactly.
    public let synapseID: String

    public var prior: SynapticPrior

    /// Prediction generated by the most recent forward pass.
    /// Default: 0.5 (uninformed). Calling backwardPass before forwardPass
    /// produces meaningless errors — circuit enforces ordering via passNumber.
    public internal(set) var lastPrediction: Double = 0.5

    /// Observation recorded by the most recent backward pass. nil = pending.
    public internal(set) var lastObservation: Double?

    // ── Prediction Error ──────────────────────────────────────────────────────

    /// Unsigned error magnitude: |predicted − observed|.
    /// 0.0 if no observation has been recorded yet.
    public var predictionError: Double {
        guard let obs = lastObservation else { return 0.0 }
        return abs(lastPrediction - obs)
    }

    /// Signed error: positive = overestimated utility, negative = underestimated.
    /// Positive error → decay accelerated (ADR-004). Negative → learning opportunity.
    public var predictionErrorSigned: Double {
        guard let obs = lastObservation else { return 0.0 }
        return lastPrediction - obs
    }

    /// True when this node warrants Referee attention.
    /// Signal surfaces in BackwardPassResult.epistemicallyUnstableNodes.
    /// Feeds into ContextIntervention (EdgarIntervention consumer).
    public var isEpistemicallyUnstable: Bool {
        prior.uncertainty > CircuitConstants.instabilityUncertaintyThreshold
        || predictionError > CircuitConstants.instabilityErrorThreshold
    }

    public init(id: UUID = UUID(), synapseID: String, prior: SynapticPrior = .uninformed) {
        self.id        = id
        self.synapseID = synapseID
        self.prior     = prior
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CircuitEdge
// Encodes the relational structure between nodes.
//
// Bidirectionality note: edges are directional (source → target).
// True bidirectional propagation requires paired edges (A→B and B→A).
// Callers must explicitly add both directions when bidirectional coupling
// is intended. This is a deliberate design choice: not all relationships
// are symmetric. (See ADR-002, Watch-out §2.)
// ─────────────────────────────────────────────────────────────────────────────

public struct CircuitEdge: Sendable, Codable, Equatable {
    public let id: UUID
    public let sourceID: UUID
    public let targetID: UUID

    /// Relationship strength [0, 1]. Higher weight = more error propagation
    /// and stronger connectivity_factor contribution.
    public private(set) var weight: Double

    /// Fraction of source error that bleeds to target on propagation pass.
    /// Hard cap via CircuitConstants.maxErrorPropagationFraction.
    public var propagationCoefficient: Double {
        weight * CircuitConstants.maxErrorPropagationFraction
    }

    public init(source: UUID, target: UUID, weight: Double) {
        self.id       = UUID()
        self.sourceID = source
        self.targetID = target
        self.weight   = max(0.0, min(1.0, weight))
    }

    /// Returns a copy with updated weight (edges are immutable from outside the circuit).
    public func withWeight(_ newWeight: Double) -> CircuitEdge {
        CircuitEdge(source: sourceID, target: targetID, weight: newWeight)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Output Value Types
// All Sendable. Safe to cross actor boundaries. Carry snapshots, not references.
// ─────────────────────────────────────────────────────────────────────────────

/// Result of a forward pass. Feeds directly into SynapseWeightState.
///
/// Integration points:
///   predictions[synapseID]         → replaces W_base(s) in decay formula
///   connectivityFactors[synapseID] → replaces connectivity_factor(s) in λ(s)
public struct ForwardPassResult: Sendable {
    /// synapseID → predicted utility [0, 1]. Modulated by prior mean and topology.
    public let predictions: [String: Double]
    /// synapseID → connectivity factor [0, 1]. Derived from incident edge weights.
    public let connectivityFactors: [String: Double]
    public let learningRate: Double
    public let passNumber: Int
}

/// Result of a backward pass. Feeds into Referee/Edgar instability detection.
public struct BackwardPassResult: Sendable {
    /// synapseID → |predicted - observed|. Feeds errorDecayAmplifier in λ(s).
    public let predictionErrors: [String: Double]
    /// Synapses currently in an epistemically unstable state.
    /// Consumer: ContextIntervention in EdgarIntervention.
    public let epistemicallyUnstableNodes: [String]
    public let passNumber: Int
}

/// Complete point-in-time snapshot of the circuit.
/// Used for persistence, diffing, and FaultInjectionSuite.
public struct CircuitSnapshot: Sendable, Codable {
    public let nodes: [SynapticNode]
    public let edges: [CircuitEdge]
    public let passCount: Int
    public let learningRate: Double
    /// Schema version hash. On mismatch at load time: mark all priors stale.
    /// See MAESTRO threat T5 (schema drift).
    public let schemaVersionHash: String
}

/// Report from a single fault injection run against one synapse.
public struct FaultInjectionReport: Sendable {
    public let synapseID: String
    public let severity: Double
    /// Number of hops fault propagated. -1 = synapse not found.
    public let propagationDepth: Int
    public let affectedNodeCount: Int
    public let preInjectionPriorMean: Double
    public let postInjectionPriorMean: Double
    public let preInjectionUncertainty: Double
    public let postInjectionUncertainty: Double
    public let passNumber: Int

    /// Circuit is pathologically coupled if faults cascade too deeply
    /// or if a high-confidence prior collapses in one pass.
    public var isPathological: Bool {
        propagationDepth >= CircuitConstants.maxFaultPropagationDepth
        || (preInjectionPriorMean > 0.6 && postInjectionPriorMean < 0.2)
    }

    /// Circuit is too isolated if faults produce no relational signal.
    public var isTooIsolated: Bool { propagationDepth == 0 && affectedNodeCount == 0 }

    /// Healthy range: propagation reaches 1–3 hops with graceful attenuation.
    public var isHealthy: Bool { !isPathological && !isTooIsolated }

    /// Sentinel value when the target synapse doesn't exist in the circuit.
    public static func notFound(synapseID: String, severity: Double, passNumber: Int) -> FaultInjectionReport {
        FaultInjectionReport(
            synapseID: synapseID, severity: severity,
            propagationDepth: -1, affectedNodeCount: 0,
            preInjectionPriorMean: 0, postInjectionPriorMean: 0,
            preInjectionUncertainty: 0, postInjectionUncertainty: 0,
            passNumber: passNumber
        )
    }
}

/// Calibration recommendations produced by FaultInjectionSuite.runFullSuite().
/// Replace CircuitConstants values with these after a suite run.
public struct CalibrationReport: Sendable {
    /// Fraction of fault runs that produced pathological cascades.
    /// > 0.20 = circuit is over-coupled; reduce maxErrorPropagationFraction.
    public let couplingIndex: Double

    /// Fraction of fault runs with zero propagation.
    /// > 0.30 = circuit is over-isolated; add relational edges.
    public let isolationIndex: Double

    /// Mean absolute prior drift across all fault runs.
    public let meanPredictionErrorMagnitude: Double

    /// Recommended value for ROT_LAMBDA_AMPLIFIER (was static 1.5).
    public let recommendedRotLambdaAmplifier: Double

    /// Recommended value for ROT_CAUTERIZE_THRESHOLD (was static 0.82).
    public let recommendedCauterizeThreshold: Double

    public let totalFaultRuns: Int

    public var circuitHealth: CircuitHealthStatus {
        if couplingIndex > 0.20 { return .overCoupled }
        if isolationIndex > 0.30 { return .overIsolated }
        return .healthy
    }

    public enum CircuitHealthStatus: String, Sendable {
        case healthy      = "HEALTHY — propagation 1–3 hops, graceful attenuation"
        case overCoupled  = "OVER-COUPLED — tighten propagation coefficients or isolate nodes"
        case overIsolated = "OVER-ISOLATED — add relational edges between semantic clusters"
    }
}
