import XCTest
import Foundation
@testable import SynapseCore

// P1 backlog: decay/rot invariants for SynapseWeightState.
// Design refs: Ops Manual §4–§6, DecayConstants in InteractionRecord.swift.

final class DecayWeightTests: XCTestCase {

    // MARK: - 1. Lighthouse floor invariant

    func testLighthouseFloorHoldsRegardlessOfElapsedTime() {
        let start = Date()
        var state = SynapseWeightState(
            synapseId: "lh-\(UUID().uuidString)",
            isLighthouse: true,
            sessionStart: start
        )
        state.record(.manualFeedback)

        // Sweep from minutes to a year of neglect
        for hours in [0.1, 1.0, 24.0, 24.0 * 30, 24.0 * 365] {
            let later = start.addingTimeInterval(hours * 3600)
            let w = state.finalWeight(baseWeight: 1.0, maxConnections: 50, at: later)
            XCTAssertGreaterThanOrEqual(
                w, DecayConstants.lighthouseFloor,
                "lighthouse floor violated after \(hours)h"
            )
        }
    }

    func testNonLighthouseHasNoFloor() {
        let start = Date()
        var state = SynapseWeightState(synapseId: "s-\(UUID().uuidString)", sessionStart: start)
        state.record(.keystrokeBurst)
        let aYearLater = start.addingTimeInterval(365 * 24 * 3600)
        let w = state.finalWeight(at: aYearLater)
        XCTAssertLessThan(w, DecayConstants.lighthouseFloor)
    }

    // MARK: - 2. Cauterization threshold

    func testRotAtOrAboveThresholdFlagsCauterization() {
        let start = Date()
        var state = SynapseWeightState(
            synapseId: "drift-\(UUID().uuidString)",
            sessionStart: start,
            distanceStrategy: MaxDistanceStrategy()
        )
        // High-velocity engagement with maximally distant content, long past
        // the drift threshold: rot = 1.0 · tanh(large) · ~2.0, clamped to 1.0.
        for _ in 0..<10 { state.record(.keystrokeBurst) }
        let content = SynapseContent(id: "c", text: "alpha")
        let lighthouse = SynapseContent(id: "l", text: "omega")
        let farFuture = state.lastInteractionAt
            .addingTimeInterval(DecayConstants.rotThresholdSeconds * 100)

        // recomputeRotScore measures drift from lastInteractionAt; pin `now`
        // far enough out that tanh saturates.
        state.recomputeRotScore(content: content, lighthouse: lighthouse, at: farFuture)

        XCTAssertGreaterThanOrEqual(state.rotScore, DecayConstants.rotCauterizeThreshold)
        XCTAssertTrue(state.requiresCauterization)
    }

    func testLighthouseNeverRots() {
        var state = SynapseWeightState(
            synapseId: "lh-\(UUID().uuidString)",
            isLighthouse: true,
            distanceStrategy: MaxDistanceStrategy()
        )
        state.recomputeRotScore(
            content: SynapseContent(id: "c", text: "anything"),
            lighthouse: SynapseContent(id: "l", text: "else"),
            at: Date().addingTimeInterval(1e6)
        )
        XCTAssertEqual(state.rotScore, 0.0)
        XCTAssertFalse(state.requiresCauterization)
    }

    // MARK: - 3. Decay monotonicity

    func testDecayWeightDecreasesMonotonicallyWithTime() {
        let start = Date()
        var state = SynapseWeightState(synapseId: "mono-\(UUID().uuidString)", sessionStart: start)
        state.record(.gitCommit)

        var previous = Double.infinity
        for minutes in stride(from: 0.0, through: 600.0, by: 60.0) {
            let t = state.lastInteractionAt.addingTimeInterval(minutes * 60)
            let w = state.decayWeight(baseWeight: 1.0, maxConnections: 50, at: t)
            XCTAssertLessThanOrEqual(w, previous,
                "decayWeight increased at +\(minutes)min")
            previous = w
        }
    }

    func testConnectivitySlowsDecay() {
        let start = Date()
        var isolated = SynapseWeightState(synapseId: "iso-\(UUID().uuidString)",
                                          childCount: 0, sessionStart: start)
        var hub = SynapseWeightState(synapseId: "hub-\(UUID().uuidString)",
                                     childCount: 40, sessionStart: start)
        isolated.record(.gitCommit)
        hub.record(.gitCommit)
        XCTAssertGreaterThan(isolated.dynamicDecayConstant(maxConnections: 50),
                             hub.dynamicDecayConstant(maxConnections: 50))
    }
}

// Deterministic strategy: everything is maximally distant. Keeps the
// cauterization test independent of StructuralHeuristicDistance tuning.
private struct MaxDistanceStrategy: SemanticDistanceStrategy {
    func distance(from: SynapseContent, to: SynapseContent) -> Double { 1.0 }
}
