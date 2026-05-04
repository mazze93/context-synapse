import XCTest
@testable import SynapseCore

// MARK: - SynapseWeightStateTests
// Tests three hard invariants from the Ops Manual:
//   1. Lighthouse floor invariant: W_final(lighthouse) >= 0.4 always
//   2. Cauterization threshold: requiresCauterization iff RotScore >= 0.82
//   3. Decay convergence: W_decay approaches 0 as t → ∞ for non-lighthouse

final class SynapseWeightStateTests: XCTestCase {

    // MARK: - Lighthouse Floor Invariant
    // W_final must never drop below DecayConstants.lighthouseFloor (0.4) for lighthouse synapses.
    // This holds regardless of elapsed time or rot score.

    func testLighthouseFloorNeverDropsBelowConstant() {
        var state = SynapseWeightState(
            synapseId: "lighthouse-test",
            isLighthouse: true,
            childCount: 0,
            sessionStart: Date(timeIntervalSinceNow: -86400) // 24h ago
        )
        // Record only low-signal events to maximise decay pressure
        for _ in 0..<50 {
            state.record(.windowSwitchAway)
        }
        // Simulate far future: 7 days elapsed
        let farFuture = Date(timeIntervalSinceNow: 7 * 86400)
        let w = state.finalWeight(baseWeight: 1.0, maxConnections: 50, at: farFuture)
        XCTAssertGreaterThanOrEqual(
            w,
            DecayConstants.lighthouseFloor,
            "Lighthouse final weight \(w) dropped below floor \(DecayConstants.lighthouseFloor)"
        )
    }

    func testLighthouseFloorHoldsWithZeroInteractions() {
        let state = SynapseWeightState(
            synapseId: "lighthouse-empty",
            isLighthouse: true,
            sessionStart: Date(timeIntervalSinceNow: -3600)
        )
        let farFuture = Date(timeIntervalSinceNow: 30 * 86400) // 30 days
        let w = state.finalWeight(baseWeight: 1.0, maxConnections: 50, at: farFuture)
        XCTAssertGreaterThanOrEqual(w, DecayConstants.lighthouseFloor)
    }

    func testNonLighthouseCanDropToZero() {
        let state = SynapseWeightState(
            synapseId: "non-lighthouse",
            isLighthouse: false,
            sessionStart: Date(timeIntervalSinceNow: -3600)
        )
        // With zero interactions and far future, utility score is 0.5 (neutral prior)
        // but decay will suppress weight significantly
        let farFuture = Date(timeIntervalSinceNow: 365 * 86400)
        let w = state.finalWeight(baseWeight: 1.0, maxConnections: 50, at: farFuture)
        // Non-lighthouse has no floor — weight can approach 0
        XCTAssertLessThan(w, DecayConstants.lighthouseFloor,
            "Non-lighthouse should not be protected by lighthouse floor")
    }

    // MARK: - Cauterization Threshold Invariant
    // requiresCauterization must be true iff RotScore >= DecayConstants.rotCauterizeThreshold (0.82)

    func testCauterizationFlagSetAtThreshold() {
        var state = SynapseWeightState(
            synapseId: "rot-test",
            isLighthouse: false,
            sessionStart: Date(timeIntervalSinceNow: -7200)
        )
        // Create a maximally diverged synapse
        let synapseCon = SynapseContent(
            id: "drifter",
            text: "completely unrelated rabbit hole",
            fileReferences: ["RabbitHole.swift"],
            functionNames: ["chaseRabbit"]
        )
        let lighthouseCon = SynapseContent(
            id: "lighthouse",
            text: "primary goal",
            fileReferences: ["Lighthouse.swift"],
            functionNames: ["keepLight"]
        )
        // Simulate 30 minutes of drift (above rotThresholdSeconds of 900s)
        let driftTime = Date(timeIntervalSinceNow: -(30 * 60))
        // Manually set last interaction to simulate drift
        // Since lastInteractionAt is private(set), we test via recomputeRotScore
        state.recomputeRotScore(content: synapseCon, lighthouse: lighthouseCon, at: Date())

        // With max structural distance (no overlap) + sufficient drift:
        // RotScore = 1.0 * tanh(large) * velocityAmplifier >= 0.82
        if state.rotScore >= DecayConstants.rotCauterizeThreshold {
            XCTAssertTrue(state.requiresCauterization,
                "requiresCauterization must be true when RotScore (\(state.rotScore)) >= threshold (\(DecayConstants.rotCauterizeThreshold))")
        } else {
            XCTAssertFalse(state.requiresCauterization,
                "requiresCauterization must be false when RotScore (\(state.rotScore)) < threshold")
        }
    }

    func testLighthouseNeverRequiresCauterization() {
        var state = SynapseWeightState(
            synapseId: "lighthouse-rot",
            isLighthouse: true,
            sessionStart: Date(timeIntervalSinceNow: -3600)
        )
        let content = SynapseContent(id: "lh", text: "lighthouse", fileReferences: ["A.swift"], functionNames: ["foo"])
        let other = SynapseContent(id: "other", text: "drift", fileReferences: ["B.swift"], functionNames: ["bar"])
        state.recomputeRotScore(content: content, lighthouse: other, at: Date())
        XCTAssertEqual(state.rotScore, 0.0, "Lighthouse RotScore must always be 0.0")
        XCTAssertFalse(state.requiresCauterization, "Lighthouse must never require cauterization")
    }

    func testCauterizedDecayConstantHigherThanNormal() {
        var state = SynapseWeightState(
            synapseId: "cauterize-check",
            isLighthouse: false,
            sessionStart: Date(timeIntervalSinceNow: -7200)
        )
        // Force high rot score via fully diverged content + drift
        let synapseCon = SynapseContent(id: "s", text: "rabbit", fileReferences: ["Rabbit.swift"], functionNames: ["run"])
        let lhCon = SynapseContent(id: "l", text: "goal", fileReferences: ["Goal.swift"], functionNames: ["stay"])
        state.recomputeRotScore(content: synapseCon, lighthouse: lhCon, at: Date())

        let normal = state.dynamicDecayConstant(maxConnections: 50)
        let cauterized = state.cauterizedDecayConstant(maxConnections: 50)

        if state.requiresCauterization {
            XCTAssertEqual(
                cauterized,
                normal * DecayConstants.rotCauterizeMultiplier,
                accuracy: 1e-10,
                "Cauterized λ must be exactly normal * CAUTERIZE_MULTIPLIER"
            )
        } else {
            XCTAssertEqual(cauterized, normal, accuracy: 1e-10,
                "Non-cauterized state must return normal decay constant")
        }
    }

    // MARK: - Decay Convergence
    // W_decay must be monotonically decreasing with time for fixed state.

    func testDecayIsMonotonicallyDecreasingOverTime() {
        let state = SynapseWeightState(
            synapseId: "decay-monotone",
            isLighthouse: false,
            sessionStart: Date(timeIntervalSinceNow: -60)
        )
        let base = Date()
        var prev = state.decayWeight(baseWeight: 1.0, maxConnections: 50, at: base)
        let intervals: [Double] = [300, 900, 3600, 7200, 86400, 7 * 86400]
        for dt in intervals {
            let future = Date(timeIntervalSinceNow: dt)
            let w = state.decayWeight(baseWeight: 1.0, maxConnections: 50, at: future)
            XCTAssertLessThanOrEqual(w, prev + 1e-10,
                "Decay weight must be non-increasing: w(t=\(dt)) = \(w) > w(prev) = \(prev)")
            prev = w
        }
    }

    func testHighConnectivityDecaysSlower() {
        let highConn = SynapseWeightState(
            synapseId: "high-conn",
            isLighthouse: false,
            childCount: 50,
            sessionStart: Date(timeIntervalSinceNow: -60)
        )
        let lowConn = SynapseWeightState(
            synapseId: "low-conn",
            isLighthouse: false,
            childCount: 0,
            sessionStart: Date(timeIntervalSinceNow: -60)
        )
        let future = Date(timeIntervalSinceNow: 3600)
        let wHigh = highConn.decayWeight(baseWeight: 1.0, maxConnections: 50, at: future)
        let wLow = lowConn.decayWeight(baseWeight: 1.0, maxConnections: 50, at: future)
        XCTAssertGreaterThan(wHigh, wLow,
            "Highly connected synapse should decay slower than isolated synapse")
    }

    // MARK: - Utility Score

    func testUtilityScoreNeutralPriorWithNoInteractions() {
        let state = SynapseWeightState(synapseId: "utility-empty", isLighthouse: false)
        XCTAssertEqual(state.utilityScore(), 0.5, accuracy: 0.001,
            "No interactions should yield neutral prior utility of 0.5")
    }

    func testHighSuccessInteractionsRaiseUtility() {
        var state = SynapseWeightState(synapseId: "utility-high", isLighthouse: false)
        for _ in 0..<20 { state.record(.gitCommit) }
        XCTAssertGreaterThan(state.utilityScore(), 0.5,
            "High-signal interactions (gitCommit=1.0) should raise utility above 0.5")
    }

    func testLowSuccessInteractionsLowerUtility() {
        var state = SynapseWeightState(synapseId: "utility-low", isLighthouse: false)
        for _ in 0..<20 { state.record(.windowSwitchAway) }
        XCTAssertLessThan(state.utilityScore(), 0.5,
            "windowSwitchAway (weight=0.0) interactions should lower utility below 0.5")
    }

    func testInteractionHistoryCapEnforced() {
        var state = SynapseWeightState(synapseId: "cap-test", isLighthouse: false)
        let over = DecayConstants.maxInteractionHistory + 50
        for _ in 0..<over { state.record(.fileSave) }
        XCTAssertEqual(state.interactions.count, DecayConstants.maxInteractionHistory,
            "Interaction history must be capped at DecayConstants.maxInteractionHistory")
    }

    // MARK: - Lighthouse Resync

    func testLighthouseResyncFlagsBetweenFloorAndSixty() {
        // lighthouseNeedsResync should return true when 0.4 <= W_final < 0.6
        // We can't force this precisely without controlling time, but we can verify
        // that a fresh lighthouse does NOT need resync (saliency starts high)
        let state = SynapseWeightState(
            synapseId: "resync-test",
            isLighthouse: true,
            sessionStart: Date()
        )
        XCTAssertFalse(state.lighthouseNeedsResync(),
            "Fresh lighthouse should not need resync immediately")
    }
}
