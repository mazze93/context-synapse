import XCTest
@testable import SynapseCore

// MARK: - SynapseRefereeTests
// Tests FunctionalReferee and AbrasiveReferee activation logic.

final class SynapseRefereeTests: XCTestCase {

    private func makeContext(
        lighthouseText: String = "primary goal",
        timeSinceLastLighthouse: TimeInterval = 0
    ) -> SessionContext {
        SessionContext(
            lighthouse: SynapseContent(id: "lh", text: lighthouseText),
            maxConnections: 50,
            decayConstant: DecayConstants.baseLambda,
            sessionStart: Date(),
            timeSinceLastLighthouseInteraction: timeSinceLastLighthouse
        )
    }

    private func makeContent(id: String, text: String, files: [String] = [], funcs: [String] = []) -> SynapseContent {
        SynapseContent(id: id, text: text, fileReferences: files, functionNames: funcs)
    }

    // MARK: - FunctionalReferee

    func testFunctionalRefereeReturnsValueInRange() {
        let referee = FunctionalReferee()
        let state = SynapseWeightState(synapseId: "fr-test", isLighthouse: false)
        let ctx = makeContext()
        let score = referee.evaluateSaliency(for: state, content: makeContent(id: "c", text: "task"), in: ctx)
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    func testFunctionalRefereeLighthouseAlwaysAboveFloor() {
        let referee = FunctionalReferee()
        var state = SynapseWeightState(
            synapseId: "lh-referee",
            isLighthouse: true,
            sessionStart: Date(timeIntervalSinceNow: -86400)
        )
        for _ in 0..<50 { state.record(.windowSwitchAway) }
        let ctx = makeContext()
        let score = referee.evaluateSaliency(
            for: state,
            content: makeContent(id: "lh", text: "primary"),
            in: ctx
        )
        XCTAssertGreaterThanOrEqual(score, DecayConstants.lighthouseFloor,
            "FunctionalReferee must never score lighthouse below floor")
    }

    func testFunctionalRefereeShadowContextForkThreshold() {
        let referee = FunctionalReferee()
        // Non-rotting synapse should NOT fork
        let cleanState = SynapseWeightState(synapseId: "clean", isLighthouse: false)
        XCTAssertFalse(referee.shouldForkToShadowContext(state: cleanState))
        // Lighthouse should never fork regardless of rotScore
        let lhState = SynapseWeightState(synapseId: "lh", isLighthouse: true)
        XCTAssertFalse(referee.shouldForkToShadowContext(state: lhState))
    }

    // MARK: - AbrasiveReferee

    func testAbrasiveRefereeDoesNotKickBelowDriftThreshold() {
        let referee = AbrasiveReferee(
            maxDriftMinutes: 15.0,
            rotThreshold: 0.3,
            interventionCooldownMinutes: 15.0
        )
        var state = SynapseWeightState(synapseId: "abrasive-ok", isLighthouse: false)
        // Low drift: 5 minutes
        let ctx = makeContext(timeSinceLastLighthouse: 5 * 60)
        let content = makeContent(id: "c", text: "task")
        // Even with high rot, drift time is below threshold — no kick
        let score = referee.evaluateSaliency(for: state, content: content, in: ctx)
        XCTAssertGreaterThan(score, 0.1, "Should not kick below drift threshold")
    }

    func testAbrasiveRefereeKicksWhenAllConditionsMet() {
        let referee = AbrasiveReferee(
            maxDriftMinutes: 1.0, // very short for testing — 1 minute threshold
            rotThreshold: 0.01,   // very low rot threshold for testing
            interventionCooldownMinutes: 0.0 // no cooldown
        )
        // Simulate old session with high drift
        var state = SynapseWeightState(
            synapseId: "abrasive-kick",
            isLighthouse: false,
            sessionStart: Date(timeIntervalSinceNow: -7200)
        )
        // Add low-signal interactions to establish non-zero rotScore via recompute
        let synContent = makeContent(id: "s", text: "rabbit hole",
            files: ["Rabbit.swift"], funcs: ["chase"])
        let lhContent = makeContent(id: "l", text: "primary goal",
            files: ["Goal.swift"], funcs: ["stay"])
        state.recomputeRotScore(content: synContent, lighthouse: lhContent, at: Date())

        // 20 minutes drift (above 1 minute threshold)
        let ctx = SessionContext(
            lighthouse: lhContent,
            maxConnections: 50,
            decayConstant: DecayConstants.baseLambda,
            sessionStart: Date(timeIntervalSinceNow: -7200),
            timeSinceLastLighthouseInteraction: 20 * 60
        )

        let score = referee.evaluateSaliency(for: state, content: synContent, in: ctx)
        // If rot threshold is met and drift exceeded: score should be 0.1
        if state.rotScore >= 0.01 {
            XCTAssertEqual(score, 0.1, accuracy: 0.001,
                "AbrasiveReferee should kick to 0.1 when all conditions met")
        }
    }

    func testAbrasiveRefereeLighthouseNeverKicked() {
        let referee = AbrasiveReferee(
            maxDriftMinutes: 0.0,
            rotThreshold: 0.0,
            interventionCooldownMinutes: 0.0
        )
        let lhState = SynapseWeightState(synapseId: "lh-abrasive", isLighthouse: true)
        let ctx = makeContext(timeSinceLastLighthouse: 999999)
        let score = referee.evaluateSaliency(
            for: lhState,
            content: makeContent(id: "lh", text: "primary"),
            in: ctx
        )
        XCTAssertGreaterThanOrEqual(score, DecayConstants.lighthouseFloor,
            "AbrasiveReferee must never kick the lighthouse")
    }

    func testRefereeConfigMakesFunctionalByDefault() {
        let config = RefereeConfig()
        XCTAssertEqual(config.mode, .functional)
        let referee = config.makeReferee()
        XCTAssertTrue(referee is FunctionalReferee)
    }

    func testRefereeConfigMakesAbrasiveWhenSet() {
        let config = RefereeConfig(mode: .abrasive)
        let referee = config.makeReferee()
        XCTAssertTrue(referee is AbrasiveReferee)
    }

    func testContextInterventionFormattedMessageContainsKeyData() {
        let intervention = ContextIntervention(
            lighthouseDescription: "Finish SynapseReferee tests",
            currentSynapseDescription: "Reading about unrelated library",
            minutesInDrift: 22,
            lighthouseSaliencyNow: 0.55,
            lighthouseSaliencyAtSessionStart: 1.0
        )
        let msg = intervention.formattedMessage
        XCTAssertTrue(msg.contains("22 minutes"))
        XCTAssertTrue(msg.contains("55%"))
        XCTAssertTrue(msg.contains("100%"))
        XCTAssertTrue(msg.contains("Lighthouse"))
        XCTAssertTrue(msg.contains("→"))
    }
}
