// MARK: - FaultInjectionSuite.swift
// Context Synapse v0.3 — Bedrock Layer: Fault Injection Calibration Suite
//
// The system eats its own cooking.
//
// This suite runs controlled adversity against the SynapticCircuit to produce
// empirically grounded calibration recommendations for:
//   - ROT_LAMBDA_AMPLIFIER    (currently static 1.5 in spec)
//   - ROT_CAUTERIZE_THRESHOLD (currently static 0.82 in spec)
//   - maxErrorPropagationFraction (currently static 0.3 in CircuitConstants)
//
// Run schedule: once per 50 passes OR on Referee-triggered instability event.
//
// Consent invariant: this suite is never self-scheduled.
// The circuit does not call this. The user initiates it.
//
// IMPORTANT: The suite operates on a snapshot fork by default.
// Live mutations are explicitly opted into, not the default.
// Pass liveMutation: true to injectFault only for deliberate stress sessions.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FaultInjectionSuite
// ─────────────────────────────────────────────────────────────────────────────

public struct FaultInjectionSuite: Sendable {
    public let circuit: SynapticCircuit

    public init(circuit: SynapticCircuit) {
        self.circuit = circuit
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Full Suite Run
    // Runs two fault levels (mild 0.3, severe 0.7) against every registered
    // synapse. Returns calibration recommendations.
    //
    // Snapshot-first: fetches node list from snapshot, runs faults in read-only
    // mode (liveMutation: false). Live circuit state is unchanged.
    // ─────────────────────────────────────────────────────────────────────────

    public func runFullSuite() async -> CalibrationReport {
        let snapshot = await circuit.snapshot()
        var reports: [FaultInjectionReport] = []

        for node in snapshot.nodes {
            let mild = await circuit.injectFault(
                intoSynapse:  node.synapseID,
                severity:     0.3,
                liveMutation: false
            )
            let severe = await circuit.injectFault(
                intoSynapse:  node.synapseID,
                severity:     0.7,
                liveMutation: false
            )
            reports.append(contentsOf: [mild, severe])
        }

        return buildCalibrationReport(from: reports)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Targeted Run
    // Run the suite against a specific list of synapses.
    // Used when Referee flags specific nodes as epistemically unstable.
    // ─────────────────────────────────────────────────────────────────────────

    public func runTargetedSuite(synapseIDs: [String]) async -> CalibrationReport {
        var reports: [FaultInjectionReport] = []

        for synapseID in synapseIDs {
            let mild = await circuit.injectFault(
                intoSynapse:  synapseID,
                severity:     0.3,
                liveMutation: false
            )
            let severe = await circuit.injectFault(
                intoSynapse:  synapseID,
                severity:     0.7,
                liveMutation: false
            )
            reports.append(contentsOf: [mild, severe])
        }

        return buildCalibrationReport(from: reports)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Lighthouse Audit
    // Run fault injection against all lighthouse-designated synapses.
    // A lighthouse that fails the healthy-range test should be surfaced
    // to the Referee. (MAESTRO T3 — lighthouse ossification detection.)
    //
    // lighthouseIDs: caller provides the set of lighthouse-designated synapseIDs.
    // ─────────────────────────────────────────────────────────────────────────

    public func auditLighthouses(lighthouseIDs: [String]) async -> [String: FaultInjectionReport] {
        var audit: [String: FaultInjectionReport] = [:]

        for synapseID in lighthouseIDs {
            // Use severe fault only: lighthouses should be stress-tested hard.
            let report = await circuit.injectFault(
                intoSynapse:  synapseID,
                severity:     0.7,
                liveMutation: false
            )
            audit[synapseID] = report
        }

        return audit
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Calibration Report Construction
    // ─────────────────────────────────────────────────────────────────────────

    private func buildCalibrationReport(from reports: [FaultInjectionReport]) -> CalibrationReport {
        let validReports    = reports.filter { $0.propagationDepth >= 0 }
        let totalFaults     = validReports.count
        guard totalFaults > 0 else {
            return CalibrationReport(
                couplingIndex:                    0,
                isolationIndex:                   0,
                meanPredictionErrorMagnitude:     0,
                recommendedRotLambdaAmplifier:    1.5,
                recommendedCauterizeThreshold:    0.82,
                totalFaultRuns:                   0
            )
        }

        let pathologicalCount = validReports.filter(\.isPathological).count
        let isolatedCount     = validReports.filter(\.isTooIsolated).count
        let couplingIndex     = Double(pathologicalCount) / Double(totalFaults)
        let isolationIndex    = Double(isolatedCount)     / Double(totalFaults)

        // Mean absolute prior drift: how much do priors actually move under fault?
        // High = priors are responsive; calibration is meaningful.
        // Low = priors are too rigid; learning rate may need increase.
        let meanDrift = validReports
            .map { abs($0.preInjectionPriorMean - $0.postInjectionPriorMean) }
            .reduce(0.0, +) / Double(totalFaults)

        return CalibrationReport(
            couplingIndex:                    couplingIndex,
            isolationIndex:                   isolationIndex,
            meanPredictionErrorMagnitude:     meanDrift,
            recommendedRotLambdaAmplifier:    recommendedAmplifier(meanDrift),
            recommendedCauterizeThreshold:    recommendedCauterizeThreshold(couplingIndex),
            totalFaultRuns:                   totalFaults
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Recommendation Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// ROT_LAMBDA_AMPLIFIER recommendation.
    /// Current spec: 1.5 (static).
    /// If mean error > 0.3: amplifier justified or should increase.
    /// If mean error < 0.1: amplifier is over-penalizing normal variance.
    /// Output range: [1.0, 1.67].
    private func recommendedAmplifier(_ meanError: Double) -> Double {
        let base = 1.0
        let sensitivity = 0.5
        let normalized  = min(1.0, meanError / 0.3)
        return base + normalized * sensitivity
    }

    /// ROT_CAUTERIZE_THRESHOLD recommendation.
    /// Current spec: 0.82 (static).
    /// High coupling → lower threshold (cut earlier, prevent cascade).
    /// Minimum floor: 0.65 (preserve AbrasiveReferee headroom).
    private func recommendedCauterizeThreshold(_ couplingIndex: Double) -> Double {
        let base       = 0.82
        let adjustment = couplingIndex * 0.2
        return max(0.65, base - adjustment)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CalibrationReport: Formatted Output
// Convenience extension for CLI / RunLog display.
// ─────────────────────────────────────────────────────────────────────────────

extension CalibrationReport {
    /// Human-readable summary for RunLog or CLI display.
    public var formattedSummary: String {
        """
        ── FAULT INJECTION CALIBRATION REPORT ──────────────────────────
        Status:              \(circuitHealth.rawValue)
        Total fault runs:    \(totalFaultRuns)
        Coupling index:      \(String(format: "%.2f", couplingIndex)) (>0.20 = over-coupled)
        Isolation index:     \(String(format: "%.2f", isolationIndex)) (>0.30 = over-isolated)
        Mean prior drift:    \(String(format: "%.3f", meanPredictionErrorMagnitude))

        ── RECOMMENDATIONS (replace CircuitConstants values) ────────────
        ROT_LAMBDA_AMPLIFIER:    \(String(format: "%.2f", recommendedRotLambdaAmplifier)) (current: 1.5)
        ROT_CAUTERIZE_THRESHOLD: \(String(format: "%.2f", recommendedCauterizeThreshold)) (current: 0.82)
        ─────────────────────────────────────────────────────────────────
        """
    }
}
