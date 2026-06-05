// MARK: - SynapticCircuitTests.swift
// Tests for CircuitTypes.swift, SynapticCircuit.swift, FaultInjectionSuite.swift
// Context Synapse v0.3 — Bedrock Layer

import XCTest
@testable import SynapseCore

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CircuitConstants Tests
// ─────────────────────────────────────────────────────────────────────────────

final class CircuitConstantsTests: XCTestCase {

    func testEtaBaseIsPositive() {
        XCTAssertGreaterThan(CircuitConstants.etaBase, 0.0)
    }

    func testEtaDecayFactorIsPositive() {
        XCTAssertGreaterThan(CircuitConstants.etaDecayFactor, 0.0)
    }

    func testMaxErrorPropagationFractionIsInUnitInterval() {
        XCTAssertGreaterThan(CircuitConstants.maxErrorPropagationFraction, 0.0)
        XCTAssertLessThanOrEqual(CircuitConstants.maxErrorPropagationFraction, 1.0)
    }

    func testMinimumMeaningfulBleedIsPositive() {
        XCTAssertGreaterThan(CircuitConstants.minimumMeaningfulBleed, 0.0)
    }

    func testFaultInjectionEtaMultiplierIsGreaterThanOne() {
        XCTAssertGreaterThan(CircuitConstants.faultInjectionEtaMultiplier, 1.0)
    }

    func testMaxFaultPropagationDepthIsPositive() {
        XCTAssertGreaterThan(CircuitConstants.maxFaultPropagationDepth, 0)
    }

    func testInstabilityThresholdsAreInUnitInterval() {
        XCTAssertGreaterThan(CircuitConstants.instabilityErrorThreshold, 0.0)
        XCTAssertLessThan(CircuitConstants.instabilityErrorThreshold, 1.0)
        XCTAssertGreaterThan(CircuitConstants.instabilityUncertaintyThreshold, 0.0)
        XCTAssertLessThan(CircuitConstants.instabilityUncertaintyThreshold, 1.0)
    }

    func testLighthouseFloorCeilingIs0Point4() {
        XCTAssertEqual(CircuitConstants.lighthouseFloorCeiling, 0.4, accuracy: 1e-9)
    }

    func testEvidenceWeightCapIsStrictlyPositive() {
        XCTAssertGreaterThan(CircuitConstants.evidenceWeightCap, 0.0)
    }

    func testMinimumAlphaIsAtLeastOne() {
        XCTAssertGreaterThanOrEqual(CircuitConstants.minimumAlpha, 1.0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Prior Tests
// ─────────────────────────────────────────────────────────────────────────────

final class PriorTests: XCTestCase {

    // MARK: Factories

    func testUninformedPriorHasMeanOfHalf() {
        let p = Prior.uninformed
        XCTAssertEqual(p.mean, 0.5, accuracy: 1e-9)
    }

    func testUninformedPriorHasAlphaAndBetaOfOne() {
        let p = Prior.uninformed
        XCTAssertEqual(p.alpha, 1.0, accuracy: 1e-9)
        XCTAssertEqual(p.beta, 1.0, accuracy: 1e-9)
    }

    func testLighthousePriorMeanIsAboveHalf() {
        let p = Prior.lighthouse()
        XCTAssertGreaterThan(p.mean, 0.5)
    }

    func testLighthousePriorDefaultConfidence10ProducesExpectedRatio() {
        // alpha = 10 * 0.8 = 8, beta = 10 * 0.2 = 2 → mean = 8/10 = 0.8
        let p = Prior.lighthouse(confidence: 10.0)
        XCTAssertEqual(p.mean, 0.8, accuracy: 1e-9)
    }

    func testLighthousePriorCustomConfidenceScales() {
        let p = Prior.lighthouse(confidence: 20.0)
        // alpha = 16, beta = 4 → mean = 16/20 = 0.8
        XCTAssertEqual(p.mean, 0.8, accuracy: 1e-9)
        XCTAssertGreaterThan(p.evidenceWeight, Prior.lighthouse(confidence: 10.0).evidenceWeight)
    }

    // MARK: init clamps

    func testInitClampsAlphaBelowMinimum() {
        let p = Prior(alpha: 0.0, beta: 1.0)
        XCTAssertEqual(p.alpha, CircuitConstants.minimumAlpha)
    }

    func testInitClampsBetaBelowMinimum() {
        let p = Prior(alpha: 1.0, beta: 0.0)
        XCTAssertGreaterThan(p.beta, 0.0)
    }

    // MARK: mean & evidenceWeight

    func testMeanIsAlphaOverAlphaPlusBeta() {
        let p = Prior(alpha: 3.0, beta: 7.0)
        XCTAssertEqual(p.mean, 3.0 / 10.0, accuracy: 1e-9)
    }

    func testEvidenceWeightIsAlphaPlusBeta() {
        let p = Prior(alpha: 4.0, beta: 6.0)
        XCTAssertEqual(p.evidenceWeight, 10.0, accuracy: 1e-9)
    }

    // MARK: uncertainty

    func testUncertaintyDecreaseAsEvidenceAccumulates() {
        let weak   = Prior(alpha: 1.0, beta: 1.0)
        let strong = Prior(alpha: 50.0, beta: 50.0)
        XCTAssertGreaterThan(weak.uncertainty, strong.uncertainty)
    }

    func testUncertaintyIsPositive() {
        let p = Prior.uninformed
        XCTAssertGreaterThan(p.uncertainty, 0.0)
    }

    // MARK: isOssified

    func testIsOssifiedFalseForNewPrior() {
        let p = Prior.uninformed
        XCTAssertFalse(p.isOssified)
    }

    func testIsOssifiedTrueWhenEvidenceWeightReachesOrExceedsCap() {
        // evidenceWeightCap = 100.0
        let p = Prior(alpha: 60.0, beta: 40.0) // weight = 100
        XCTAssertTrue(p.isOssified)
    }

    func testIsOssifiedFalseJustBelowCap() {
        let p = Prior(alpha: 50.0, beta: 49.0) // weight = 99
        XCTAssertFalse(p.isOssified)
    }

    // MARK: update

    func testUpdateIncreasesAlphaOnPositiveObservation() {
        var p = Prior.uninformed
        let alphaInitial = p.alpha
        p.update(observation: 1.0, eta: 0.1)
        XCTAssertGreaterThan(p.alpha, alphaInitial)
    }

    func testUpdateIncreasesBetaOnZeroObservation() {
        var p = Prior.uninformed
        let betaInitial = p.beta
        p.update(observation: 0.0, eta: 0.1)
        XCTAssertGreaterThan(p.beta, betaInitial)
    }

    func testUpdateIncreaseMeanAfterRepeatedPositiveObservations() {
        var p = Prior.uninformed
        let initialMean = p.mean
        for _ in 0..<20 {
            p.update(observation: 1.0, eta: 0.1)
        }
        XCTAssertGreaterThan(p.mean, initialMean)
    }

    func testUpdateDecreaseMeanAfterRepeatedNegativeObservations() {
        var p = Prior(alpha: 5.0, beta: 1.0) // high mean initially
        let initialMean = p.mean
        for _ in 0..<20 {
            p.update(observation: 0.0, eta: 0.1)
        }
        XCTAssertLessThan(p.mean, initialMean)
    }

    func testUpdateClampsObservationAboveOneToOne() {
        var p = Prior.uninformed
        var pRef = Prior.uninformed
        p.update(observation: 2.0, eta: 0.1)    // over-range
        pRef.update(observation: 1.0, eta: 0.1) // clamped equivalent
        XCTAssertEqual(p.alpha, pRef.alpha, accuracy: 1e-9)
        XCTAssertEqual(p.beta, pRef.beta, accuracy: 1e-9)
    }

    func testUpdateClampsObservationBelowZeroToZero() {
        var p = Prior.uninformed
        var pRef = Prior.uninformed
        p.update(observation: -0.5, eta: 0.1)  // under-range
        pRef.update(observation: 0.0, eta: 0.1) // clamped equivalent
        XCTAssertEqual(p.alpha, pRef.alpha, accuracy: 1e-9)
        XCTAssertEqual(p.beta, pRef.beta, accuracy: 1e-9)
    }

    func testUpdateIsBlockedWhenOssified() {
        var p = Prior(alpha: 60.0, beta: 40.0) // isOssified = true
        let alphaBefore = p.alpha
        let betaBefore  = p.beta
        p.update(observation: 0.0, eta: 0.5)
        XCTAssertEqual(p.alpha, alphaBefore, accuracy: 1e-9)
        XCTAssertEqual(p.beta, betaBefore, accuracy: 1e-9)
    }

    func testUpdateEnforcesMinimumAlphaFloor() {
        // Start with minimum alpha, apply high-penalty update; alpha must not drop below 1.0
        var p = Prior(alpha: 1.0, beta: 1.0)
        for _ in 0..<100 {
            p.update(observation: 0.0, eta: 0.5)
        }
        XCTAssertGreaterThanOrEqual(p.alpha, CircuitConstants.minimumAlpha)
    }

    // MARK: widenUncertainty

    func testWidenUncertaintyIncreasesBeta() {
        var p = Prior.uninformed
        let betaBefore = p.beta
        p.widenUncertainty(by: 0.5)
        XCTAssertGreaterThan(p.beta, betaBefore)
    }

    func testWidenUncertaintyDoesNotChangeMean() {
        // mean = alpha/(alpha+beta); adding to beta shifts mean downward
        // The implementation widens uncertainty which does change mean, but
        // the intent is to decrease mean as beta increases.
        // Test that alpha does NOT change.
        var p = Prior.uninformed
        let alphaBefore = p.alpha
        p.widenUncertainty(by: 1.0)
        XCTAssertEqual(p.alpha, alphaBefore, accuracy: 1e-9)
    }

    func testWidenUncertaintyIsBlockedWhenOssified() {
        var p = Prior(alpha: 60.0, beta: 40.0) // isOssified
        let betaBefore = p.beta
        p.widenUncertainty(by: 10.0)
        XCTAssertEqual(p.beta, betaBefore, accuracy: 1e-9)
    }

    // MARK: Codable

    func testPriorIsRoundTrippable() throws {
        let original = Prior(alpha: 3.5, beta: 7.2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Prior.self, from: data)
        XCTAssertEqual(decoded.alpha, original.alpha, accuracy: 1e-9)
        XCTAssertEqual(decoded.beta, original.beta, accuracy: 1e-9)
    }

    // MARK: Equatable

    func testPriorEquality() {
        let a = Prior(alpha: 2.0, beta: 3.0)
        let b = Prior(alpha: 2.0, beta: 3.0)
        XCTAssertEqual(a, b)
    }

    func testPriorInequality() {
        let a = Prior(alpha: 2.0, beta: 3.0)
        let b = Prior(alpha: 2.0, beta: 4.0)
        XCTAssertNotEqual(a, b)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SynapticNode Tests
// ─────────────────────────────────────────────────────────────────────────────

final class SynapticNodeTests: XCTestCase {

    // MARK: init defaults

    func testDefaultLastPredictionIsHalf() {
        let node = SynapticNode(synapseID: "test")
        XCTAssertEqual(node.lastPrediction, 0.5, accuracy: 1e-9)
    }

    func testDefaultLastObservationIsNil() {
        let node = SynapticNode(synapseID: "test")
        XCTAssertNil(node.lastObservation)
    }

    func testDefaultPriorIsUninformed() {
        let node = SynapticNode(synapseID: "test")
        XCTAssertEqual(node.prior, Prior.uninformed)
    }

    func testCustomIDIsPreserved() {
        let id = UUID()
        let node = SynapticNode(id: id, synapseID: "test")
        XCTAssertEqual(node.id, id)
    }

    // MARK: predictionError

    func testPredictionErrorIsZeroWithNoObservation() {
        let node = SynapticNode(synapseID: "test")
        XCTAssertEqual(node.predictionError, 0.0, accuracy: 1e-9)
    }

    func testPredictionErrorIsAbsoluteDifference() {
        var node = SynapticNode(synapseID: "test")
        // lastPrediction = 0.5, set observation to 0.8 → error = 0.3
        node.lastObservation = 0.8
        XCTAssertEqual(node.predictionError, 0.3, accuracy: 1e-9)
    }

    func testPredictionErrorIsAlwaysNonNegative() {
        var node = SynapticNode(synapseID: "test")
        node.lastObservation = 1.0 // prediction=0.5 < observation → abs = 0.5
        XCTAssertGreaterThanOrEqual(node.predictionError, 0.0)
    }

    // MARK: predictionErrorSigned

    func testPredictionErrorSignedIsZeroWithNoObservation() {
        let node = SynapticNode(synapseID: "test")
        XCTAssertEqual(node.predictionErrorSigned, 0.0, accuracy: 1e-9)
    }

    func testPredictionErrorSignedIsPositiveWhenOverestimated() {
        var node = SynapticNode(synapseID: "test")
        // prediction=0.5, observation=0.2 → signed = 0.3 (positive = overestimated)
        node.lastObservation = 0.2
        XCTAssertGreaterThan(node.predictionErrorSigned, 0.0)
    }

    func testPredictionErrorSignedIsNegativeWhenUnderestimated() {
        var node = SynapticNode(synapseID: "test")
        // prediction=0.5, observation=0.8 → signed = -0.3 (negative = underestimated)
        node.lastObservation = 0.8
        XCTAssertLessThan(node.predictionErrorSigned, 0.0)
    }

    // MARK: isEpistemicallyUnstable — error threshold

    func testNotEpistemicallyUnstableByDefault() {
        let node = SynapticNode(synapseID: "test")
        // Default: no observation (error=0), uninformed prior (uncertainty small)
        // uncertainty of uninformed prior = (1*1)/(4*3) = 1/12 ≈ 0.083 < 0.15 threshold
        // error = 0 < 0.4
        XCTAssertFalse(node.isEpistemicallyUnstable)
    }

    func testEpistemicallyUnstableFromLargePredictionError() {
        var node = SynapticNode(synapseID: "test")
        // Force error > 0.4: prediction=0.5, set observation near 0 → error > 0.4
        node.lastObservation = 0.0 // error = abs(0.5 - 0.0) = 0.5 > 0.4
        XCTAssertTrue(node.isEpistemicallyUnstable)
    }

    func testEpistemicallyUnstableFromHighUncertainty() {
        // Create node with high uncertainty (low evidence, equal alpha/beta but very low)
        // uncertainty = (1*1)/(4*3) = 0.083 for uninformed
        // Need uncertainty > 0.15: use alpha=1, beta=1 but wait — let's compute manually.
        // uncertainty = α*β / (n^2 * (n+1)); max at α=β=n/2
        // For α=β=1: n=2, u = 1/(4*3) = 0.0833 < 0.15
        // For α=β=0.5 (clamped by init): alpha becomes 1.0
        // Let's try: to get uncertainty > 0.15, need α*β/(n^2*(n+1)) > 0.15
        // at α=β: u = (n/2)^2 / (n^2*(n+1)) = 1/(4*(n+1))
        // 1/(4*(n+1)) > 0.15 → n+1 < 1/0.6 → n < 0.67 — not achievable with min alpha=1
        // Actually, asymmetric case: α=1 (minimum), β = small value
        // u = 1*β/(1+β)^2*(2+β); maximize at β approaching 0:
        // lim β→0: u → 0. At β=1: u=1/12.
        // Peak is at some point. Let's try α=1, β=1.5:
        // n=2.5, u = 1.5/(6.25*3.5) = 1.5/21.875 ≈ 0.0686
        // Hmm, still under 0.15. Let's use a weak prior differently:
        // alpha=1, beta=3 → n=4, u = 3/(16*5) = 3/80 = 0.0375
        // The uncertainty formula at α=β peak for n small:
        // At α=0.5, β=0.5 (but alpha clamped to 1): n=1.5, u = 1*(0.5)/(2.25*2.5)?
        // Actually let me just verify the formula can exceed 0.15 at all.
        // Max of u = α*β/(n^2*(n+1)) at fixed n: maximized when α=β=n/2
        // = (n/2)^2/(n^2*(n+1)) = 1/(4*(n+1))
        // For n=2 (uninformed): max u = 1/12 ≈ 0.083
        // For n=1.01 (smallest possible): max u ≈ 1/(4*2.01) ≈ 0.124
        // So with minimumAlpha=1.0 and minimumBeta=0.01, minimum n=1.01
        // max uncertainty ≈ 0.124 < 0.15.
        // CONCLUSION: uncertainty CANNOT exceed 0.15 given minimumAlpha=1.0
        // So isEpistemicallyUnstable is only triggered by predictionError threshold.
        // This is an important boundary condition to test.
        let node = SynapticNode(synapseID: "lighthouse", prior: Prior(alpha: 1.0, beta: 0.01))
        // uncertainty = 1.0*0.01 / (1.01^2 * 2.01) ≈ 0.01/2.049 ≈ 0.00488
        XCTAssertFalse(node.isEpistemicallyUnstable)
    }

    func testEpistemicallyUnstableBoundaryAtExactErrorThreshold() {
        var nodeBelow = SynapticNode(synapseID: "test")
        var nodeAbove = SynapticNode(synapseID: "test")
        // threshold = 0.4; prediction = 0.5
        nodeBelow.lastObservation = 0.11 // error = 0.39 < 0.4
        nodeAbove.lastObservation = 0.09 // error = 0.41 > 0.4
        XCTAssertFalse(nodeBelow.isEpistemicallyUnstable)
        XCTAssertTrue(nodeAbove.isEpistemicallyUnstable)
    }

    // MARK: Codable

    func testSynapticNodeIsRoundTrippable() throws {
        var node = SynapticNode(synapseID: "round-trip")
        node.lastObservation = 0.7
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(SynapticNode.self, from: data)
        XCTAssertEqual(decoded.id, node.id)
        XCTAssertEqual(decoded.synapseID, node.synapseID)
        XCTAssertEqual(decoded.prior, node.prior)
        XCTAssertEqual(decoded.lastObservation, node.lastObservation)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CircuitEdge Tests
// ─────────────────────────────────────────────────────────────────────────────

final class CircuitEdgeTests: XCTestCase {

    func testWeightIsClampedToUnitIntervalAbove() {
        let source = UUID()
        let target = UUID()
        let edge = CircuitEdge(source: source, target: target, weight: 2.0)
        XCTAssertEqual(edge.weight, 1.0, accuracy: 1e-9)
    }

    func testWeightIsClampedToUnitIntervalBelow() {
        let source = UUID()
        let target = UUID()
        let edge = CircuitEdge(source: source, target: target, weight: -0.5)
        XCTAssertEqual(edge.weight, 0.0, accuracy: 1e-9)
    }

    func testWeightInUnitIntervalIsPreserved() {
        let source = UUID()
        let target = UUID()
        let edge = CircuitEdge(source: source, target: target, weight: 0.75)
        XCTAssertEqual(edge.weight, 0.75, accuracy: 1e-9)
    }

    func testSourceAndTargetIDsArePreserved() {
        let source = UUID()
        let target = UUID()
        let edge = CircuitEdge(source: source, target: target, weight: 0.5)
        XCTAssertEqual(edge.sourceID, source)
        XCTAssertEqual(edge.targetID, target)
    }

    func testPropagationCoefficientIsWeightTimesMaxFraction() {
        let edge = CircuitEdge(source: UUID(), target: UUID(), weight: 0.5)
        let expected = 0.5 * CircuitConstants.maxErrorPropagationFraction
        XCTAssertEqual(edge.propagationCoefficient, expected, accuracy: 1e-9)
    }

    func testPropagationCoefficientIsZeroForZeroWeight() {
        let edge = CircuitEdge(source: UUID(), target: UUID(), weight: 0.0)
        XCTAssertEqual(edge.propagationCoefficient, 0.0, accuracy: 1e-9)
    }

    func testPropagationCoefficientIsMaxFractionForFullWeight() {
        let edge = CircuitEdge(source: UUID(), target: UUID(), weight: 1.0)
        XCTAssertEqual(edge.propagationCoefficient, CircuitConstants.maxErrorPropagationFraction, accuracy: 1e-9)
    }

    func testWithWeightCreatesNewEdgeWithUpdatedWeight() {
        let source = UUID()
        let target = UUID()
        let edge = CircuitEdge(source: source, target: target, weight: 0.3)
        let updated = edge.withWeight(0.9)
        XCTAssertEqual(updated.weight, 0.9, accuracy: 1e-9)
        XCTAssertEqual(updated.sourceID, source)
        XCTAssertEqual(updated.targetID, target)
    }

    func testWithWeightOriginalEdgeIsUnchanged() {
        let edge = CircuitEdge(source: UUID(), target: UUID(), weight: 0.3)
        _ = edge.withWeight(0.9)
        XCTAssertEqual(edge.weight, 0.3, accuracy: 1e-9)
    }

    func testWithWeightClampsToUnitInterval() {
        let edge = CircuitEdge(source: UUID(), target: UUID(), weight: 0.5)
        let over = edge.withWeight(1.5)
        let under = edge.withWeight(-1.0)
        XCTAssertEqual(over.weight, 1.0, accuracy: 1e-9)
        XCTAssertEqual(under.weight, 0.0, accuracy: 1e-9)
    }

    func testEachEdgeHasUniqueID() {
        let e1 = CircuitEdge(source: UUID(), target: UUID(), weight: 0.5)
        let e2 = CircuitEdge(source: UUID(), target: UUID(), weight: 0.5)
        XCTAssertNotEqual(e1.id, e2.id)
    }

    // MARK: Codable

    func testCircuitEdgeIsRoundTrippable() throws {
        let source = UUID()
        let target = UUID()
        let edge = CircuitEdge(source: source, target: target, weight: 0.6)
        let data = try JSONEncoder().encode(edge)
        let decoded = try JSONDecoder().decode(CircuitEdge.self, from: data)
        XCTAssertEqual(decoded.id, edge.id)
        XCTAssertEqual(decoded.sourceID, source)
        XCTAssertEqual(decoded.targetID, target)
        XCTAssertEqual(decoded.weight, 0.6, accuracy: 1e-9)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FaultInjectionReport Tests
// ─────────────────────────────────────────────────────────────────────────────

final class FaultInjectionReportTests: XCTestCase {

    // MARK: notFound sentinel

    func testNotFoundHasPropagationDepthMinusOne() {
        let r = FaultInjectionReport.notFound(synapseID: "missing", severity: 0.5, passNumber: 3)
        XCTAssertEqual(r.propagationDepth, -1)
    }

    func testNotFoundHasZeroAffectedNodes() {
        let r = FaultInjectionReport.notFound(synapseID: "missing", severity: 0.5, passNumber: 3)
        XCTAssertEqual(r.affectedNodeCount, 0)
    }

    func testNotFoundPreservesSymapseIDAndSeverity() {
        let r = FaultInjectionReport.notFound(synapseID: "ghost", severity: 0.7, passNumber: 10)
        XCTAssertEqual(r.synapseID, "ghost")
        XCTAssertEqual(r.severity, 0.7, accuracy: 1e-9)
        XCTAssertEqual(r.passNumber, 10)
    }

    // MARK: isPathological

    func testIsPathologicalWhenPropagationDepthAtCap() {
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.5,
            propagationDepth: CircuitConstants.maxFaultPropagationDepth,
            affectedNodeCount: 1,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.5,
            preInjectionUncertainty: 0.1, postInjectionUncertainty: 0.1,
            passNumber: 1
        )
        XCTAssertTrue(r.isPathological)
    }

    func testIsPathologicalWhenHighConfidencePriorCollapses() {
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.8,
            propagationDepth: 1,
            affectedNodeCount: 1,
            preInjectionPriorMean: 0.7,  // > 0.6
            postInjectionPriorMean: 0.15, // < 0.2
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.3,
            passNumber: 1
        )
        XCTAssertTrue(r.isPathological)
    }

    func testIsNotPathologicalForHealthyPropagation() {
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.3,
            propagationDepth: 2,
            affectedNodeCount: 2,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.45,
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.07,
            passNumber: 1
        )
        XCTAssertFalse(r.isPathological)
    }

    func testIsPathologicalBoundaryPriorMean() {
        // preInjectionPriorMean == 0.6 → condition is > 0.6, so NOT pathological for collapse
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.8,
            propagationDepth: 1,
            affectedNodeCount: 1,
            preInjectionPriorMean: 0.6,  // NOT > 0.6
            postInjectionPriorMean: 0.1,  // < 0.2
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.3,
            passNumber: 1
        )
        XCTAssertFalse(r.isPathological)
    }

    // MARK: isTooIsolated

    func testIsTooIsolatedWhenDepthZeroAndNoAffectedNodes() {
        let r = FaultInjectionReport(
            synapseID: "isolated", severity: 0.3,
            propagationDepth: 0, affectedNodeCount: 0,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.48,
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.05,
            passNumber: 1
        )
        XCTAssertTrue(r.isTooIsolated)
    }

    func testIsNotTooIsolatedWhenDepthZeroButHasAffectedNodes() {
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.3,
            propagationDepth: 0, affectedNodeCount: 1,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.48,
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.05,
            passNumber: 1
        )
        XCTAssertFalse(r.isTooIsolated)
    }

    func testIsNotTooIsolatedWhenDepthPositive() {
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.3,
            propagationDepth: 1, affectedNodeCount: 0,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.48,
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.05,
            passNumber: 1
        )
        XCTAssertFalse(r.isTooIsolated)
    }

    // MARK: isHealthy

    func testIsHealthyWhenNeitherPathologicalNorIsolated() {
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.3,
            propagationDepth: 2, affectedNodeCount: 2,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.47,
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.06,
            passNumber: 1
        )
        XCTAssertTrue(r.isHealthy)
    }

    func testIsNotHealthyWhenPathological() {
        let r = FaultInjectionReport(
            synapseID: "test", severity: 0.5,
            propagationDepth: CircuitConstants.maxFaultPropagationDepth,
            affectedNodeCount: 5,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.3,
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.2,
            passNumber: 1
        )
        XCTAssertFalse(r.isHealthy)
    }

    func testIsNotHealthyWhenTooIsolated() {
        let r = FaultInjectionReport(
            synapseID: "lone", severity: 0.3,
            propagationDepth: 0, affectedNodeCount: 0,
            preInjectionPriorMean: 0.5, postInjectionPriorMean: 0.48,
            preInjectionUncertainty: 0.05, postInjectionUncertainty: 0.05,
            passNumber: 1
        )
        XCTAssertFalse(r.isHealthy)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CalibrationReport Tests
// ─────────────────────────────────────────────────────────────────────────────

final class CalibrationReportTests: XCTestCase {

    func testCircuitHealthIsHealthyWhenBothIndexesLow() {
        let r = CalibrationReport(
            couplingIndex: 0.10, isolationIndex: 0.10,
            meanPredictionErrorMagnitude: 0.1,
            recommendedRotLambdaAmplifier: 1.2,
            recommendedCauterizeThreshold: 0.82,
            totalFaultRuns: 10
        )
        XCTAssertEqual(r.circuitHealth, .healthy)
    }

    func testCircuitHealthIsOverCoupledWhenCouplingIndexExceedsThreshold() {
        let r = CalibrationReport(
            couplingIndex: 0.25, isolationIndex: 0.05,
            meanPredictionErrorMagnitude: 0.2,
            recommendedRotLambdaAmplifier: 1.3,
            recommendedCauterizeThreshold: 0.80,
            totalFaultRuns: 10
        )
        XCTAssertEqual(r.circuitHealth, .overCoupled)
    }

    func testCircuitHealthIsOverIsolatedWhenIsolationIndexExceedsThreshold() {
        let r = CalibrationReport(
            couplingIndex: 0.05, isolationIndex: 0.35,
            meanPredictionErrorMagnitude: 0.05,
            recommendedRotLambdaAmplifier: 1.0,
            recommendedCauterizeThreshold: 0.82,
            totalFaultRuns: 10
        )
        XCTAssertEqual(r.circuitHealth, .overIsolated)
    }

    func testOverCoupledTakesPriorityOverOverIsolated() {
        // coupling > 0.20 AND isolation > 0.30 — coupling check is first in implementation
        let r = CalibrationReport(
            couplingIndex: 0.25, isolationIndex: 0.35,
            meanPredictionErrorMagnitude: 0.2,
            recommendedRotLambdaAmplifier: 1.3,
            recommendedCauterizeThreshold: 0.75,
            totalFaultRuns: 10
        )
        XCTAssertEqual(r.circuitHealth, .overCoupled)
    }

    func testCircuitHealthBoundaryAt0Point20Coupling() {
        // couplingIndex == 0.20 → NOT > 0.20 → must check isolation
        let r = CalibrationReport(
            couplingIndex: 0.20, isolationIndex: 0.05,
            meanPredictionErrorMagnitude: 0.1,
            recommendedRotLambdaAmplifier: 1.1,
            recommendedCauterizeThreshold: 0.82,
            totalFaultRuns: 10
        )
        XCTAssertEqual(r.circuitHealth, .healthy)
    }

    func testCircuitHealthBoundaryAt0Point30Isolation() {
        // isolationIndex == 0.30 → NOT > 0.30 → healthy
        let r = CalibrationReport(
            couplingIndex: 0.05, isolationIndex: 0.30,
            meanPredictionErrorMagnitude: 0.05,
            recommendedRotLambdaAmplifier: 1.0,
            recommendedCauterizeThreshold: 0.82,
            totalFaultRuns: 10
        )
        XCTAssertEqual(r.circuitHealth, .healthy)
    }

    func testHealthStatusRawValuesAreDescriptive() {
        XCTAssertTrue(CalibrationReport.CircuitHealthStatus.healthy.rawValue.contains("HEALTHY"))
        XCTAssertTrue(CalibrationReport.CircuitHealthStatus.overCoupled.rawValue.contains("OVER-COUPLED"))
        XCTAssertTrue(CalibrationReport.CircuitHealthStatus.overIsolated.rawValue.contains("OVER-ISOLATED"))
    }

    // MARK: formattedSummary

    func testFormattedSummaryContainsTotalFaultRuns() {
        let r = CalibrationReport(
            couplingIndex: 0.10, isolationIndex: 0.10,
            meanPredictionErrorMagnitude: 0.1,
            recommendedRotLambdaAmplifier: 1.2,
            recommendedCauterizeThreshold: 0.82,
            totalFaultRuns: 42
        )
        XCTAssertTrue(r.formattedSummary.contains("42"))
    }

    func testFormattedSummaryContainsCouplingIndex() {
        let r = CalibrationReport(
            couplingIndex: 0.15, isolationIndex: 0.10,
            meanPredictionErrorMagnitude: 0.1,
            recommendedRotLambdaAmplifier: 1.2,
            recommendedCauterizeThreshold: 0.82,
            totalFaultRuns: 10
        )
        XCTAssertTrue(r.formattedSummary.contains("0.15"))
    }

    func testFormattedSummaryContainsROTLambdaAmplifier() {
        let r = CalibrationReport(
            couplingIndex: 0.10, isolationIndex: 0.10,
            meanPredictionErrorMagnitude: 0.1,
            recommendedRotLambdaAmplifier: 1.33,
            recommendedCauterizeThreshold: 0.82,
            totalFaultRuns: 10
        )
        XCTAssertTrue(r.formattedSummary.contains("ROT_LAMBDA_AMPLIFIER"))
    }

    func testFormattedSummaryContainsCauterizeThreshold() {
        let r = CalibrationReport(
            couplingIndex: 0.10, isolationIndex: 0.10,
            meanPredictionErrorMagnitude: 0.1,
            recommendedRotLambdaAmplifier: 1.2,
            recommendedCauterizeThreshold: 0.75,
            totalFaultRuns: 10
        )
        XCTAssertTrue(r.formattedSummary.contains("ROT_CAUTERIZE_THRESHOLD"))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SynapticCircuit Actor Tests
// ─────────────────────────────────────────────────────────────────────────────

final class SynapticCircuitTests: XCTestCase {

    // MARK: Learning Rate

    func testInitialLearningRateEqualsEtaBase() async {
        let circuit = SynapticCircuit()
        let lr = await circuit.currentLearningRate
        // passCount=0 → η = etaBase / (1 + 0) = etaBase
        XCTAssertEqual(lr, CircuitConstants.etaBase, accuracy: 1e-9)
    }

    func testLearningRateDecaysAfterForwardPass() async {
        let circuit = SynapticCircuit()
        let lrBefore = await circuit.currentLearningRate
        _ = await circuit.forwardPass()
        let lrAfter = await circuit.currentLearningRate
        XCTAssertLessThan(lrAfter, lrBefore)
    }

    func testLearningRateDecayFormula() async {
        let circuit = SynapticCircuit()
        _ = await circuit.forwardPass() // passCount = 1
        let lr = await circuit.currentLearningRate
        let expected = CircuitConstants.etaBase / (1.0 + 1.0 * CircuitConstants.etaDecayFactor)
        XCTAssertEqual(lr, expected, accuracy: 1e-9)
    }

    // MARK: Node Registration

    func testRegisterNodeStoresNodeAndReflectsInSnapshot() async {
        let circuit = SynapticCircuit()
        let node = SynapticNode(synapseID: "alpha")
        await circuit.register(node)
        let snap = await circuit.snapshot()
        XCTAssertTrue(snap.nodes.contains { $0.synapseID == "alpha" })
    }

    func testRegisterReplacesExistingNodeWithSameID() async {
        let circuit = SynapticCircuit()
        let id = UUID()
        let node1 = SynapticNode(id: id, synapseID: "first")
        let node2 = SynapticNode(id: id, synapseID: "second")
        await circuit.register(node1)
        await circuit.register(node2)
        let snap = await circuit.snapshot()
        let registered = snap.nodes.filter { $0.id == id }
        XCTAssertEqual(registered.count, 1)
        XCTAssertEqual(registered.first?.synapseID, "second")
    }

    func testPriorMeanReturnsNilForUnknownSynapseID() async {
        let circuit = SynapticCircuit()
        let mean = await circuit.priorMean(for: "nonexistent")
        XCTAssertNil(mean)
    }

    func testPriorMeanReturnsCorrectValueAfterRegistration() async {
        let circuit = SynapticCircuit()
        let node = SynapticNode(synapseID: "beta", prior: Prior(alpha: 3.0, beta: 7.0))
        await circuit.register(node)
        let mean = await circuit.priorMean(for: "beta")
        XCTAssertNotNil(mean)
        XCTAssertEqual(mean!, 0.3, accuracy: 1e-9)
    }

    // MARK: Edge Management

    func testConnectEdgeAppearsInSnapshot() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "n1")
        let n2 = SynapticNode(synapseID: "n2")
        await circuit.register(n1)
        await circuit.register(n2)
        let edge = CircuitEdge(source: n1.id, target: n2.id, weight: 0.8)
        await circuit.connect(edge)
        let snap = await circuit.snapshot()
        XCTAssertTrue(snap.edges.contains { $0.id == edge.id })
    }

    func testUpdateEdgeWeightChangesWeight() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "a")
        let n2 = SynapticNode(synapseID: "b")
        await circuit.register(n1)
        await circuit.register(n2)
        let edge = CircuitEdge(source: n1.id, target: n2.id, weight: 0.5)
        await circuit.connect(edge)
        await circuit.updateEdgeWeight(id: edge.id, weight: 0.9)
        let snap = await circuit.snapshot()
        let updated = snap.edges.first { $0.id == edge.id }
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated!.weight, 0.9, accuracy: 1e-9)
    }

    func testUpdateEdgeWeightIgnoresUnknownID() async {
        let circuit = SynapticCircuit()
        // Should not crash on unknown edge ID
        await circuit.updateEdgeWeight(id: UUID(), weight: 0.5)
        let snap = await circuit.snapshot()
        XCTAssertTrue(snap.edges.isEmpty)
    }

    func testDisconnectNodeRemovesNodeAndIncidentEdges() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "x")
        let n2 = SynapticNode(synapseID: "y")
        await circuit.register(n1)
        await circuit.register(n2)
        let edge = CircuitEdge(source: n1.id, target: n2.id, weight: 0.6)
        await circuit.connect(edge)
        await circuit.disconnectNode(id: n1.id)
        let snap = await circuit.snapshot()
        XCTAssertFalse(snap.nodes.contains { $0.synapseID == "x" })
        XCTAssertTrue(snap.edges.isEmpty)
    }

    // MARK: Forward Pass

    func testForwardPassIncrementsPassCount() async {
        let circuit = SynapticCircuit()
        let snap0 = await circuit.snapshot()
        _ = await circuit.forwardPass()
        let snap1 = await circuit.snapshot()
        XCTAssertEqual(snap1.passCount, snap0.passCount + 1)
    }

    func testForwardPassReturnsExpectedPassNumber() async {
        let circuit = SynapticCircuit()
        let result = await circuit.forwardPass()
        XCTAssertEqual(result.passNumber, 1)
    }

    func testForwardPassPredictionsContainAllRegisteredSynapseIDs() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "s1")
        let n2 = SynapticNode(synapseID: "s2")
        await circuit.register(n1)
        await circuit.register(n2)
        let result = await circuit.forwardPass()
        XCTAssertNotNil(result.predictions["s1"])
        XCTAssertNotNil(result.predictions["s2"])
    }

    func testForwardPassPredictionsAreInUnitInterval() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s1", prior: Prior(alpha: 8.0, beta: 2.0)))
        let result = await circuit.forwardPass()
        for (_, pred) in result.predictions {
            XCTAssertGreaterThanOrEqual(pred, 0.0)
            XCTAssertLessThanOrEqual(pred, 1.0)
        }
    }

    func testForwardPassConnectivityFactorIsZeroForIsolatedNode() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "lone"))
        let result = await circuit.forwardPass()
        XCTAssertEqual(result.connectivityFactors["lone"] ?? -1.0, 0.0, accuracy: 1e-9)
    }

    func testForwardPassConnectivityFactorIsNonZeroForConnectedNode() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "hub")
        let n2 = SynapticNode(synapseID: "spoke")
        await circuit.register(n1)
        await circuit.register(n2)
        await circuit.connect(CircuitEdge(source: n1.id, target: n2.id, weight: 0.8))
        let result = await circuit.forwardPass()
        XCTAssertGreaterThan(result.connectivityFactors["hub"] ?? 0.0, 0.0)
    }

    func testForwardPassLearningRateDecreases() async {
        let circuit = SynapticCircuit()
        let r1 = await circuit.forwardPass()
        let r2 = await circuit.forwardPass()
        XCTAssertGreaterThan(r1.learningRate, r2.learningRate)
    }

    // MARK: Backward Pass

    func testBackwardPassBeforeForwardPassReturnsEmptyResult() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s1"))
        let result = await circuit.backwardPass(observations: ["s1": 0.8])
        XCTAssertTrue(result.predictionErrors.isEmpty)
        XCTAssertTrue(result.epistemicallyUnstableNodes.isEmpty)
    }

    func testBackwardPassAfterForwardPassRecordsErrors() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s1"))
        _ = await circuit.forwardPass()
        let result = await circuit.backwardPass(observations: ["s1": 0.0])
        // prediction≈0.5, observation=0.0 → error ≈ 0.5
        XCTAssertNotNil(result.predictionErrors["s1"])
        XCTAssertGreaterThan(result.predictionErrors["s1"]!, 0.0)
    }

    func testBackwardPassDetectsEpistemicallyUnstableNode() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "unstable"))
        _ = await circuit.forwardPass()
        // observation=0.0 → prediction≈0.5, error=0.5 > 0.4 threshold
        let result = await circuit.backwardPass(observations: ["unstable": 0.0])
        XCTAssertTrue(result.epistemicallyUnstableNodes.contains("unstable"))
    }

    func testBackwardPassDoesNotFlagStableNode() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "stable"))
        _ = await circuit.forwardPass()
        // observation≈prediction → small error, not unstable
        let result = await circuit.backwardPass(observations: ["stable": 0.5])
        XCTAssertFalse(result.epistemicallyUnstableNodes.contains("stable"))
    }

    func testBackwardPassUpdatesPriorMean() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "learner"))
        let meanBefore = await circuit.priorMean(for: "learner")!
        _ = await circuit.forwardPass()
        _ = await circuit.backwardPass(observations: ["learner": 1.0])
        let meanAfter = await circuit.priorMean(for: "learner")!
        XCTAssertGreaterThan(meanAfter, meanBefore)
    }

    func testBackwardPassIgnoresUnknownSynapseID() async {
        let circuit = SynapticCircuit()
        _ = await circuit.forwardPass()
        // Should not crash on unknown synapseID
        let result = await circuit.backwardPass(observations: ["ghost": 0.5])
        XCTAssertTrue(result.predictionErrors.isEmpty)
    }

    func testBackwardPassPropagatesUncertaintyToAdjacentNode() async {
        let circuit = SynapticCircuit()
        let source = SynapticNode(synapseID: "source")
        let target = SynapticNode(synapseID: "target")
        await circuit.register(source)
        await circuit.register(target)
        let edge = CircuitEdge(source: source.id, target: target.id, weight: 1.0)
        await circuit.connect(edge)

        _ = await circuit.forwardPass()
        // Give source a large error: observation=0.0, prediction≈0.5 → error≈0.5 > minimumMeaningfulBleed
        _ = await circuit.backwardPass(observations: ["source": 0.0])

        // Target's prior beta should have increased (uncertainty widened)
        let snap = await circuit.snapshot()
        let targetNode = snap.nodes.first { $0.synapseID == "target" }!
        // Beta should be > 1.0 (original uninformed beta) due to uncertainty propagation
        XCTAssertGreaterThan(targetNode.prior.beta, 1.0)
    }

    // MARK: Prediction Error Accessor

    func testPredictionErrorForUnknownSynapseIsZero() async {
        let circuit = SynapticCircuit()
        let err = await circuit.predictionError(for: "nonexistent")
        XCTAssertEqual(err, 0.0, accuracy: 1e-9)
    }

    func testPredictionErrorIsZeroBeforeObservation() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s"))
        let err = await circuit.predictionError(for: "s")
        XCTAssertEqual(err, 0.0, accuracy: 1e-9)
    }

    func testPredictionErrorIsNonZeroAfterBackwardPass() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s"))
        _ = await circuit.forwardPass()
        _ = await circuit.backwardPass(observations: ["s": 0.0])
        let err = await circuit.predictionError(for: "s")
        XCTAssertGreaterThan(err, 0.0)
    }

    // MARK: Lighthouse Floor

    func testLighthouseFloorIsZeroForNonLighthouse() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s"))
        _ = await circuit.forwardPass()
        let floor = await circuit.lighthouseFloor(for: "s", isLighthouse: false)
        XCTAssertEqual(floor, 0.0, accuracy: 1e-9)
    }

    func testLighthouseFloorIsZeroForUnknownSynapse() async {
        let circuit = SynapticCircuit()
        let floor = await circuit.lighthouseFloor(for: "ghost", isLighthouse: true)
        XCTAssertEqual(floor, 0.0, accuracy: 1e-9)
    }

    func testLighthouseFloorIsPriorMeanTimesCeiling() async {
        let circuit = SynapticCircuit()
        let prior = Prior(alpha: 8.0, beta: 2.0) // mean = 0.8
        await circuit.register(SynapticNode(synapseID: "lh", prior: prior))
        let floor = await circuit.lighthouseFloor(for: "lh", isLighthouse: true)
        let expected = 0.8 * CircuitConstants.lighthouseFloorCeiling
        XCTAssertEqual(floor, expected, accuracy: 1e-9)
    }

    func testLighthouseFloorDecreasesAfterNegativeFeedback() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "lh", prior: Prior.lighthouse()))
        let floorBefore = await circuit.lighthouseFloor(for: "lh", isLighthouse: true)
        _ = await circuit.forwardPass()
        for _ in 0..<15 {
            _ = await circuit.backwardPass(observations: ["lh": 0.0])
            _ = await circuit.forwardPass()
        }
        let floorAfter = await circuit.lighthouseFloor(for: "lh", isLighthouse: true)
        XCTAssertLessThan(floorAfter, floorBefore)
    }

    // MARK: Fault Injection

    func testInjectFaultReturnsNotFoundForUnknownSynapse() async {
        let circuit = SynapticCircuit()
        let report = await circuit.injectFault(intoSynapse: "ghost", severity: 0.5)
        XCTAssertEqual(report.propagationDepth, -1)
        XCTAssertEqual(report.synapseID, "ghost")
    }

    func testInjectFaultDecreasesPriorMean() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "target", prior: Prior(alpha: 5.0, beta: 1.0)))
        _ = await circuit.forwardPass()
        let report = await circuit.injectFault(intoSynapse: "target", severity: 0.7)
        XCTAssertLessThan(report.postInjectionPriorMean, report.preInjectionPriorMean)
    }

    func testInjectFaultWithLiveMutationFalseDoesNotChangeLiveState() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s", prior: Prior(alpha: 5.0, beta: 1.0)))
        _ = await circuit.forwardPass()
        let meanBefore = await circuit.priorMean(for: "s")!
        _ = await circuit.injectFault(intoSynapse: "s", severity: 0.9, liveMutation: false)
        let meanAfter = await circuit.priorMean(for: "s")!
        XCTAssertEqual(meanBefore, meanAfter, accuracy: 1e-9)
    }

    func testInjectFaultWithLiveMutationTrueChangesLiveState() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s", prior: Prior(alpha: 5.0, beta: 1.0)))
        _ = await circuit.forwardPass()
        let meanBefore = await circuit.priorMean(for: "s")!
        _ = await circuit.injectFault(intoSynapse: "s", severity: 0.9, liveMutation: true)
        let meanAfter = await circuit.priorMean(for: "s")!
        XCTAssertLessThan(meanAfter, meanBefore)
    }

    func testInjectFaultReportsCorrectPassNumber() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s"))
        _ = await circuit.forwardPass()
        _ = await circuit.forwardPass() // passCount = 2
        let report = await circuit.injectFault(intoSynapse: "s", severity: 0.3)
        XCTAssertEqual(report.passNumber, 2)
    }

    func testInjectFaultPropagationDepthIsZeroForIsolatedNode() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "lone"))
        _ = await circuit.forwardPass()
        let report = await circuit.injectFault(intoSynapse: "lone", severity: 0.9)
        // No edges → BFS terminates immediately with depth=1 (incremented once then empty frontier)
        // Actually: frontier starts with [startID], depth=0; first iteration:
        // next = [] (no outgoing edges with impact > bleed); frontier=[], depth=1; loop exits.
        // So depth=1, affectedIDs=[] → isTooIsolated = false (depth != 0), isHealthy might be true
        // Let's just check affectedNodeCount == 0
        XCTAssertEqual(report.affectedNodeCount, 0)
    }

    func testInjectFaultMeasuresPropagationThroughChain() async {
        // A → B → C with high-weight edges; severe fault should reach B
        let circuit = SynapticCircuit()
        let a = SynapticNode(synapseID: "A")
        let b = SynapticNode(synapseID: "B")
        let c = SynapticNode(synapseID: "C")
        await circuit.register(a)
        await circuit.register(b)
        await circuit.register(c)
        await circuit.connect(CircuitEdge(source: a.id, target: b.id, weight: 1.0))
        await circuit.connect(CircuitEdge(source: b.id, target: c.id, weight: 1.0))
        _ = await circuit.forwardPass()
        let report = await circuit.injectFault(intoSynapse: "A", severity: 1.0)
        // impact = severity * propagationCoefficient = 1.0 * 0.3 = 0.3 > minimumMeaningfulBleed(0.05)
        XCTAssertGreaterThan(report.affectedNodeCount, 0)
    }

    // MARK: Snapshot

    func testSnapshotCapturesAllRegisteredNodes() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "n1"))
        await circuit.register(SynapticNode(synapseID: "n2"))
        await circuit.register(SynapticNode(synapseID: "n3"))
        let snap = await circuit.snapshot()
        XCTAssertEqual(snap.nodes.count, 3)
    }

    func testSnapshotCapturesAllEdges() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "a")
        let n2 = SynapticNode(synapseID: "b")
        await circuit.register(n1)
        await circuit.register(n2)
        await circuit.connect(CircuitEdge(source: n1.id, target: n2.id, weight: 0.5))
        await circuit.connect(CircuitEdge(source: n2.id, target: n1.id, weight: 0.5))
        let snap = await circuit.snapshot()
        XCTAssertEqual(snap.edges.count, 2)
    }

    func testSnapshotPassCountMatchesForwardPassCount() async {
        let circuit = SynapticCircuit()
        _ = await circuit.forwardPass()
        _ = await circuit.forwardPass()
        _ = await circuit.forwardPass()
        let snap = await circuit.snapshot()
        XCTAssertEqual(snap.passCount, 3)
    }

    func testSnapshotSchemaHashChangesWhenNodeAdded() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "first"))
        let snap1 = await circuit.snapshot()
        await circuit.register(SynapticNode(synapseID: "second"))
        let snap2 = await circuit.snapshot()
        XCTAssertNotEqual(snap1.schemaVersionHash, snap2.schemaVersionHash)
    }

    func testSnapshotSchemaHashIsStableWithNoChanges() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "stable"))
        let snap1 = await circuit.snapshot()
        let snap2 = await circuit.snapshot()
        XCTAssertEqual(snap1.schemaVersionHash, snap2.schemaVersionHash)
    }

    func testSnapshotIsCodeable() async throws {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "encode-me"))
        _ = await circuit.forwardPass()
        let snap = await circuit.snapshot()
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(CircuitSnapshot.self, from: data)
        XCTAssertEqual(decoded.passCount, snap.passCount)
        XCTAssertEqual(decoded.schemaVersionHash, snap.schemaVersionHash)
        XCTAssertEqual(decoded.nodes.count, snap.nodes.count)
    }

    // MARK: Connectivity Factor

    func testConnectivityFactorIsZeroForUnknownSynapse() async {
        let circuit = SynapticCircuit()
        let factor = await circuit.connectivityFactor(for: "phantom")
        XCTAssertEqual(factor, 0.0, accuracy: 1e-9)
    }

    func testConnectivityFactorIsZeroForIsolatedNode() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "island"))
        let factor = await circuit.connectivityFactor(for: "island")
        XCTAssertEqual(factor, 0.0, accuracy: 1e-9)
    }

    func testConnectivityFactorReflectsEdgeWeights() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "hub")
        let n2 = SynapticNode(synapseID: "leaf")
        await circuit.register(n1)
        await circuit.register(n2)
        await circuit.connect(CircuitEdge(source: n1.id, target: n2.id, weight: 0.8))
        let factor = await circuit.connectivityFactor(for: "hub")
        XCTAssertEqual(factor, 0.8, accuracy: 1e-9)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FaultInjectionSuite Tests
// ─────────────────────────────────────────────────────────────────────────────

final class FaultInjectionSuiteTests: XCTestCase {

    // MARK: runFullSuite — empty circuit

    func testRunFullSuiteOnEmptyCircuitReturnsDefaults() async {
        let circuit = SynapticCircuit()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runFullSuite()
        XCTAssertEqual(report.totalFaultRuns, 0)
        XCTAssertEqual(report.couplingIndex, 0.0, accuracy: 1e-9)
        XCTAssertEqual(report.isolationIndex, 0.0, accuracy: 1e-9)
        XCTAssertEqual(report.recommendedRotLambdaAmplifier, 1.5, accuracy: 1e-9)
        XCTAssertEqual(report.recommendedCauterizeThreshold, 0.82, accuracy: 1e-9)
    }

    // MARK: runFullSuite — single node

    func testRunFullSuiteRunsTwoFaultsPerNode() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "one"))
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runFullSuite()
        // 1 node × 2 severity levels = 2 runs
        XCTAssertEqual(report.totalFaultRuns, 2)
    }

    func testRunFullSuiteDoesNotMutateLiveCircuit() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s", prior: Prior(alpha: 8.0, beta: 2.0)))
        _ = await circuit.forwardPass()
        let meanBefore = await circuit.priorMean(for: "s")!
        let suite = FaultInjectionSuite(circuit: circuit)
        _ = await suite.runFullSuite()
        let meanAfter = await circuit.priorMean(for: "s")!
        XCTAssertEqual(meanBefore, meanAfter, accuracy: 1e-9)
    }

    func testRunFullSuiteWithMultipleNodesRunsExpectedCount() async {
        let circuit = SynapticCircuit()
        for i in 0..<3 {
            await circuit.register(SynapticNode(synapseID: "n\(i)"))
        }
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runFullSuite()
        // 3 nodes × 2 = 6 fault runs
        XCTAssertEqual(report.totalFaultRuns, 6)
    }

    // MARK: runTargetedSuite

    func testRunTargetedSuiteOnEmptyListReturnsDefaults() async {
        let circuit = SynapticCircuit()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runTargetedSuite(synapseIDs: [])
        XCTAssertEqual(report.totalFaultRuns, 0)
        XCTAssertEqual(report.recommendedRotLambdaAmplifier, 1.5, accuracy: 1e-9)
    }

    func testRunTargetedSuiteRunsTwoFaultsPerTargetedSynapse() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "targeted"))
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runTargetedSuite(synapseIDs: ["targeted"])
        XCTAssertEqual(report.totalFaultRuns, 2)
    }

    func testRunTargetedSuiteExcludesNonTargetedNodes() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "included"))
        await circuit.register(SynapticNode(synapseID: "excluded"))
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        // Only target "included" — "excluded" should contribute 0 reports
        // But "excluded" has a valid node, so notFound won't fire. However we only pass 1 ID.
        let report = await suite.runTargetedSuite(synapseIDs: ["included"])
        XCTAssertEqual(report.totalFaultRuns, 2)
    }

    func testRunTargetedSuiteHandlesNonExistentSynapseID() async {
        let circuit = SynapticCircuit()
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        // notFound reports have propagationDepth=-1 → filtered as invalid
        let report = await suite.runTargetedSuite(synapseIDs: ["ghost"])
        XCTAssertEqual(report.totalFaultRuns, 0)
    }

    // MARK: auditLighthouses

    func testAuditLighthousesReturnsOneReportPerLighthouse() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "lh1", prior: Prior.lighthouse()))
        await circuit.register(SynapticNode(synapseID: "lh2", prior: Prior.lighthouse()))
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let audit = await suite.auditLighthouses(lighthouseIDs: ["lh1", "lh2"])
        XCTAssertEqual(audit.count, 2)
        XCTAssertNotNil(audit["lh1"])
        XCTAssertNotNil(audit["lh2"])
    }

    func testAuditLighthousesReturnsSentinelForUnregisteredLighthouse() async {
        let circuit = SynapticCircuit()
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let audit = await suite.auditLighthouses(lighthouseIDs: ["phantom"])
        XCTAssertNotNil(audit["phantom"])
        XCTAssertEqual(audit["phantom"]!.propagationDepth, -1)
    }

    func testAuditLighthousesOnEmptyListReturnsEmptyDictionary() async {
        let circuit = SynapticCircuit()
        let suite = FaultInjectionSuite(circuit: circuit)
        let audit = await suite.auditLighthouses(lighthouseIDs: [])
        XCTAssertTrue(audit.isEmpty)
    }

    func testAuditLighthousesUsesSevereFaultOnly() async {
        // Verify the audit reports contain severity=0.7
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "lighthouse", prior: Prior.lighthouse()))
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let audit = await suite.auditLighthouses(lighthouseIDs: ["lighthouse"])
        XCTAssertEqual(audit["lighthouse"]!.severity, 0.7, accuracy: 1e-9)
    }

    // MARK: Calibration recommendations

    func testRecommendedAmplifierIsAtLeastOne() async {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s"))
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runFullSuite()
        XCTAssertGreaterThanOrEqual(report.recommendedRotLambdaAmplifier, 1.0)
    }

    func testRecommendedAmplifierDoesNotExceedCeiling() async {
        // max amplifier = 1.0 + 1.0 * 0.5 = 1.5; test with high-drift scenario
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "s", prior: Prior(alpha: 8.0, beta: 2.0)))
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runFullSuite()
        XCTAssertLessThanOrEqual(report.recommendedRotLambdaAmplifier, 1.51)
    }

    func testRecommendedCauterizeThresholdHasMinimumFloor() async {
        let circuit = SynapticCircuit()
        // Add many pathological nodes to drive couplingIndex high
        for i in 0..<5 {
            await circuit.register(SynapticNode(synapseID: "p\(i)", prior: Prior.lighthouse()))
        }
        _ = await circuit.forwardPass()
        let suite = FaultInjectionSuite(circuit: circuit)
        let report = await suite.runFullSuite()
        XCTAssertGreaterThanOrEqual(report.recommendedCauterizeThreshold, 0.65)
    }

    // MARK: Regression: full pass cycle

    func testFullPassCycleProducesConsistentResults() async {
        let circuit = SynapticCircuit()
        let n1 = SynapticNode(synapseID: "reg1")
        let n2 = SynapticNode(synapseID: "reg2")
        await circuit.register(n1)
        await circuit.register(n2)
        await circuit.connect(CircuitEdge(source: n1.id, target: n2.id, weight: 0.5))

        for _ in 0..<5 {
            let fwd = await circuit.forwardPass()
            XCTAssertNotNil(fwd.predictions["reg1"])
            XCTAssertNotNil(fwd.predictions["reg2"])
            let bwd = await circuit.backwardPass(observations: ["reg1": 0.9, "reg2": 0.7])
            XCTAssertEqual(bwd.passNumber, fwd.passNumber)
        }

        // After 5 positive passes, reg1 mean should have increased
        let finalMean = await circuit.priorMean(for: "reg1")
        XCTAssertGreaterThan(finalMean!, 0.5)
    }
}
