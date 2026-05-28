// MARK: - SynapticCircuit.swift
// Context Synapse v0.3 — Bedrock Layer: Circuit Actor
//
// The SynapticCircuit is the belief-revision substrate that replaces
// the static W_base(s) constant in the decay formula with a mutable
// Beta-distributed prior updated by observed interaction outcomes.
//
// Thread model: Swift 6.0 strict concurrency.
//   - All mutable state is actor-isolated.
//   - Outputs are Sendable value types (snapshots, reports).
//   - External callers always await. No ordering is assumed by callers.
//   - Ordering is ENFORCED INTERNALLY: backwardPass validates against
//     lastForwardPassNumber before computing errors.
//
// Signal flow:
//   forwardPass()  → ForwardPassResult (predictions + connectivity factors)
//                  → consumed by SynapseWeightState to compute W_decay
//   backwardPass() → BackwardPassResult (errors + unstable nodes)
//                  → consumed by Referee/Edgar for intervention decisions
//
// Ethical invariant (ADR-001 / ADR-002):
//   Fault injection is ALWAYS caller-initiated.
//   The circuit never self-injects.
//   Affect vector is NOT an input to this layer.
//   Operational context inference is permanently out of scope.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SynapticCircuit
// ─────────────────────────────────────────────────────────────────────────────

public actor SynapticCircuit {

    // ── State ─────────────────────────────────────────────────────────────────

    private var nodes:     [UUID: SynapticNode] = [:]
    private var edges:     [CircuitEdge]        = []
    private var passCount: Int                  = 0

    /// Tracks the pass number of the most recent forwardPass.
    /// backwardPass validates against this before computing errors.
    private var lastForwardPassNumber: Int = 0

    /// Connectivity factor cache. Rebuilt on edge mutation.
    /// Key: node UUID, Value: average incident edge weight.
    private var connectivityCache:      [UUID: Double] = [:]
    private var connectivityCacheDirty: Bool           = true

    // ── Computed Properties ───────────────────────────────────────────────────

    /// Current learning rate. Decays with pass count.
    /// η(τ) = etaBase / (1 + τ · etaDecayFactor)
    public var currentLearningRate: Double {
        CircuitConstants.etaBase / (1.0 + Double(passCount) * CircuitConstants.etaDecayFactor)
    }

    public init() {}

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Node / Edge Registration
    // ─────────────────────────────────────────────────────────────────────────

    /// Register a synapse node. Idempotent on same UUID; replaces on re-registration.
    public func register(_ node: SynapticNode) {
        nodes[node.id] = node
        connectivityCacheDirty = true
    }

    /// Add a directional edge between two registered nodes.
    /// For bidirectional coupling, add paired edges (A→B and B→A).
    public func connect(_ edge: CircuitEdge) {
        edges.append(edge)
        connectivityCacheDirty = true
    }

    /// Update the weight of an existing edge.
    public func updateEdgeWeight(id: UUID, weight: Double) {
        guard let idx = edges.firstIndex(where: { $0.id == id }) else { return }
        edges[idx] = edges[idx].withWeight(weight)
        connectivityCacheDirty = true
    }

    /// Remove all edges incident to a node (called before de-registering).
    public func disconnectNode(id: UUID) {
        edges.removeAll { $0.sourceID == id || $0.targetID == id }
        nodes.removeValue(forKey: id)
        connectivityCacheDirty = true
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Forward Pass
    // Generate predictions from current priors. Increment pass counter.
    //
    // Output: ForwardPassResult
    //   predictions[synapseID]         → W_base(s) substitute in decay formula
    //   connectivityFactors[synapseID] → connectivity_factor(s) in λ(s) formula
    //
    // Side effect: updates lastPrediction on each node (actor-isolated).
    // ─────────────────────────────────────────────────────────────────────────

    public func forwardPass() -> ForwardPassResult {
        passCount += 1
        lastForwardPassNumber = passCount
        rebuildConnectivityCacheIfNeeded()

        var predictions:          [String: Double] = [:]
        var connectivityFactors:  [String: Double] = [:]

        for (id, var node) in nodes {
            let connectivity    = connectivityCache[id] ?? 0.0
            let incomingBias    = computeIncomingInfluence(for: id)

            // Prediction: prior mean modulated by topological embedding.
            // The +15% bonus for highly-connected nodes encodes the principle
            // that context with stronger relational anchors is more reliable.
            let rawPrediction = node.prior.mean * (1.0 + incomingBias * 0.15)
            node.lastPrediction = min(1.0, max(0.0, rawPrediction))
            nodes[id] = node

            predictions[node.synapseID]         = node.lastPrediction
            connectivityFactors[node.synapseID] = connectivity
        }

        return ForwardPassResult(
            predictions:         predictions,
            connectivityFactors: connectivityFactors,
            learningRate:        currentLearningRate,
            passNumber:          passCount
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Backward Pass
    // Record observations. Compute prediction errors. Update priors.
    // Propagate errors through edges (uncertainty only, not mean shift).
    //
    // Ordering guard: rejects calls where passNumber doesn't follow a forwardPass.
    // Callers should check BackwardPassResult.passNumber for confirmation.
    //
    // observations: [synapseID: successᵢ value]
    //   Use the interaction weight table (git commit = 1.0, etc.)
    // ─────────────────────────────────────────────────────────────────────────

    public func backwardPass(observations: [String: Double]) async -> BackwardPassResult {
        // Ordering guard: meaningful errors require a prior prediction.
        // If called before any forwardPass, lastForwardPassNumber == 0.
        guard lastForwardPassNumber > 0 else {
            return BackwardPassResult(
                predictionErrors: [:],
                epistemicallyUnstableNodes: [],
                passNumber: passCount
            )
        }

        let eta = currentLearningRate
        var errors:         [String: Double] = [:]
        var unstableNodes:  [String]         = []

        // ── Step 1: Record observations and update local priors ───────────────

        for (synapseID, observation) in observations {
            guard
                let nodeID = nodeID(for: synapseID),
                var node = nodes[nodeID]
            else { continue }

            let prevMean = node.prior.mean
            node.lastObservation = observation
            node.prior.update(observation: observation, eta: eta)
            nodes[nodeID] = node

            errors[synapseID] = node.predictionError

            if node.isEpistemicallyUnstable {
                unstableNodes.append(synapseID)
            }

            // High-drift signal: prior moved significantly in one pass.
            // Intentional fragility — surface this, don't suppress it.
            let drift = abs(node.prior.mean - prevMean)
            if drift > 0.1 {
                emitDriftEvent(synapseID: synapseID, drift: drift, newMean: node.prior.mean)
            }
        }

        // ── Step 2: Propagate uncertainty through edges ───────────────────────
        propagateUncertainty(eta: eta)

        return BackwardPassResult(
            predictionErrors:             errors,
            epistemicallyUnstableNodes:   unstableNodes,
            passNumber:                   passCount
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Lighthouse Floor (ADR-003)
    // floor(s) = prior.mean(s) · LIGHTHOUSE_FLOOR_CEILING
    //
    // The floor is earned, not granted. A lighthouse synapse with an eroding
    // prior loses its floor. Lighthouse misdesignation is self-correcting.
    //
    // Used by SynapseWeightState.W_final:
    //   W_final(s,t) = max(lighthouseFloor(s,isLighthouse), W_decay · (1 − α · rot))
    // ─────────────────────────────────────────────────────────────────────────

    public func lighthouseFloor(for synapseID: String, isLighthouse: Bool) -> Double {
        guard isLighthouse,
              let id = nodeID(for: synapseID),
              let node = nodes[id]
        else { return 0.0 }
        return node.prior.mean * CircuitConstants.lighthouseFloorCeiling
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Fault Injection (ADR-002 / MAESTRO calibration)
    // Deliberately introduce controlled adversity into a node.
    // Measures propagation depth and interprets circuit health.
    //
    // IMPORTANT: By default, this operates on a SNAPSHOT of the circuit,
    // not the live state. Set liveMutation = true only for deliberate
    // adversarial hardening sessions (not calibration runs).
    //
    // Consent invariant: fault injection is ALWAYS caller-initiated.
    // This method is never called internally. (ADR-001 principle.)
    // ─────────────────────────────────────────────────────────────────────────

    public func injectFault(
        intoSynapse synapseID: String,
        severity: Double,
        liveMutation: Bool = false
    ) -> FaultInjectionReport {
        guard var node = nodes.values.first(where: { $0.synapseID == synapseID }) else {
            return .notFound(synapseID: synapseID, severity: severity, passNumber: passCount)
        }

        let preState       = node.prior
        let amplifiedEta   = currentLearningRate * CircuitConstants.faultInjectionEtaMultiplier

        // Artificial observation that maximally contradicts the current prediction.
        let artificialObservation = max(0.0, node.lastPrediction - severity)
        node.lastObservation = artificialObservation
        node.prior.update(observation: artificialObservation, eta: amplifiedEta)

        // Write back only if live mutation is explicitly requested
        if liveMutation {
            nodes[node.id] = node
        }

        let (depth, affectedIDs) = measurePropagationDepth(from: node.id, severity: severity)

        return FaultInjectionReport(
            synapseID:                  synapseID,
            severity:                   severity,
            propagationDepth:           depth,
            affectedNodeCount:          affectedIDs.count,
            preInjectionPriorMean:      preState.mean,
            postInjectionPriorMean:     node.prior.mean,
            preInjectionUncertainty:    preState.uncertainty,
            postInjectionUncertainty:   node.prior.uncertainty,
            passNumber:                 passCount
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - State Access
    // All reads return Sendable value types. No references escape the actor.
    // ─────────────────────────────────────────────────────────────────────────

    public func snapshot() -> CircuitSnapshot {
        CircuitSnapshot(
            nodes:             Array(nodes.values),
            edges:             edges,
            passCount:         passCount,
            learningRate:      currentLearningRate,
            schemaVersionHash: computeSchemaHash()
        )
    }

    public func priorMean(for synapseID: String) -> Double? {
        nodes.values.first { $0.synapseID == synapseID }?.prior.mean
    }

    public func connectivityFactor(for synapseID: String) -> Double {
        rebuildConnectivityCacheIfNeeded()
        guard let id = nodeID(for: synapseID) else { return 0.0 }
        return connectivityCache[id] ?? 0.0
    }

    public func predictionError(for synapseID: String) -> Double {
        nodes.values.first { $0.synapseID == synapseID }?.predictionError ?? 0.0
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Private: Error Propagation
    // ─────────────────────────────────────────────────────────────────────────

    /// Bleed prediction error from source nodes to target nodes via edges.
    /// Only widens target uncertainty (beta), never shifts target mean.
    /// This preserves the principle: adjacent nodes become less confident,
    /// not less useful. They are invited to collect more evidence.
    private func propagateUncertainty(eta: Double) {
        for edge in edges {
            guard
                let source = nodes[edge.sourceID],
                var target = nodes[edge.targetID],
                source.predictionError > CircuitConstants.minimumMeaningfulBleed
            else { continue }

            let errorBleed = source.predictionError * edge.propagationCoefficient
            target.prior.widenUncertainty(by: eta * errorBleed)
            nodes[edge.targetID] = target
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Private: Propagation Depth Measurement
    // ─────────────────────────────────────────────────────────────────────────

    /// BFS from a source node. Measures how many hops a fault of `severity`
    /// would meaningfully reach. Used to classify circuit coupling.
    private func measurePropagationDepth(
        from startID: UUID,
        severity: Double
    ) -> (depth: Int, nodeIDs: [UUID]) {
        var visited:     Set<UUID> = [startID]
        var frontier:    [UUID]    = [startID]
        var depth:        Int      = 0
        var affectedIDs: [UUID]    = []

        while !frontier.isEmpty, depth < CircuitConstants.maxFaultPropagationDepth {
            var next: [UUID] = []
            for currentID in frontier {
                for edge in edges where edge.sourceID == currentID {
                    guard !visited.contains(edge.targetID) else { continue }
                    let impact = severity * edge.propagationCoefficient
                    if impact > CircuitConstants.minimumMeaningfulBleed {
                        visited.insert(edge.targetID)
                        next.append(edge.targetID)
                        affectedIDs.append(edge.targetID)
                    }
                }
            }
            frontier = next
            depth += 1
        }

        return (depth, affectedIDs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Private: Connectivity Cache
    // ─────────────────────────────────────────────────────────────────────────

    private func rebuildConnectivityCacheIfNeeded() {
        guard connectivityCacheDirty else { return }
        connectivityCache.removeAll()

        for node in nodes.values {
            let incomingWeights = edges
                .filter { $0.targetID == node.id }
                .map(\.weight)
            let outgoingWeights = edges
                .filter { $0.sourceID == node.id }
                .map(\.weight)
            let allWeights = incomingWeights + outgoingWeights

            let avgWeight = allWeights.isEmpty
                ? 0.0
                : allWeights.reduce(0.0, +) / Double(allWeights.count)

            connectivityCache[node.id] = avgWeight
        }

        connectivityCacheDirty = false
    }

    /// Weighted sum of upstream priors, normalized by incoming edge count.
    /// Provides the topological bias used in forwardPass prediction.
    private func computeIncomingInfluence(for nodeID: UUID) -> Double {
        let incoming = edges.filter { $0.targetID == nodeID }
        guard !incoming.isEmpty else { return 0.0 }

        let total = incoming.compactMap { edge -> Double? in
            nodes[edge.sourceID].map { $0.prior.mean * edge.weight }
        }.reduce(0.0, +)

        return total / Double(incoming.count)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Private: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func nodeID(for synapseID: String) -> UUID? {
        nodes.values.first { $0.synapseID == synapseID }?.id
    }

    /// Stable hash of the current node/edge schema.
    /// Stored in CircuitSnapshot. Mismatch on load = stale priors (MAESTRO T5).
    private func computeSchemaHash() -> String {
        let nodeKeys = nodes.values.map(\.synapseID).sorted().joined()
        let edgeKeys = edges.map { "\($0.sourceID)-\($0.targetID)" }.sorted().joined()
        return String((nodeKeys + edgeKeys).hashValue)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Side Effect: Drift Event
    // Explicit documentation: this emits a structured log line to stdout.
    // In production, replace with RunLog writer injected at construction.
    // Intentional fragility: large prior updates are signals, not noise.
    // ─────────────────────────────────────────────────────────────────────────

    private func emitDriftEvent(synapseID: String, drift: Double, newMean: Double) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[CIRCUIT-DRIFT] \(ts) synapse=\(synapseID) drift=\(String(format: "%.3f", drift)) newMean=\(String(format: "%.3f", newMean))")
    }
}
