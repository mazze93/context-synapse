import XCTest
@testable import SynapseCore

/// Known Issue: unbounded prior growth. `Prior.renormalizeIfSaturated` caps the
/// accumulated Beta evidence (alpha + beta) while preserving the mean, and
/// `applyFeedbackUpdate` applies it after every bump. These tests pin both the
/// pure math and the wiring. UUID-isolated folders per the test convention.
final class PriorGrowthTests: XCTestCase {

    // MARK: - Pure math

    func testRenormalizePreservesMeanWhenSaturated() {
        // alpha:beta = 3:1 → mean 0.75, total 400 (> cap 200).
        var prior = Prior(alpha: 300.0, beta: 100.0)
        let meanBefore = prior.probability()
        prior.renormalizeIfSaturated()

        XCTAssertEqual(prior.alpha + prior.beta, Prior.maxEvidence, accuracy: 1e-9,
                       "total evidence should be scaled down to the cap")
        XCTAssertEqual(prior.probability(), meanBefore, accuracy: 1e-12,
                       "renormalization must preserve the mean exactly")
    }

    func testRenormalizeIsNoOpBelowCap() {
        var prior = Prior(alpha: 40.0, beta: 10.0) // total 50 < cap
        prior.renormalizeIfSaturated()
        XCTAssertEqual(prior.alpha, 40.0, accuracy: 1e-12)
        XCTAssertEqual(prior.beta, 10.0, accuracy: 1e-12)
    }

    func testRenormalizeIsIdempotentAtCap() {
        var prior = Prior(alpha: 150.0, beta: 150.0) // total 300 > cap
        prior.renormalizeIfSaturated()
        let (a1, b1) = (prior.alpha, prior.beta)
        prior.renormalizeIfSaturated() // second pass: already at cap
        XCTAssertEqual(prior.alpha, a1, accuracy: 1e-12)
        XCTAssertEqual(prior.beta, b1, accuracy: 1e-12)
    }

    // MARK: - Wiring through applyFeedbackUpdate

    func testFeedbackHistoryStaysBounded() {
        let core = SynapseCore(folderName: "ContextSynapseTests_PriorGrowth_\(UUID().uuidString)")

        // Far more feedback events than the cap would admit if it accumulated 1:1.
        for _ in 0..<(Int(Prior.maxEvidence) + 500) {
            core.applyFeedbackUpdate(chosenIntent: "Create",
                                     chosenTone: "Concise",
                                     chosenDomain: "Work",
                                     positive: true)
        }

        let w = core.loadOrCreateDefaultWeights()
        guard let intent = w.priors.intents["Create"] else {
            return XCTFail("expected a persisted prior for the bumped intent")
        }
        // Bounded (small slack for the single +1 bump applied before renormalize).
        XCTAssertLessThanOrEqual(intent.alpha + intent.beta, Prior.maxEvidence + 1.0,
                                 "accumulated evidence must not grow without bound")
        // Still responsive to the direction of feedback (mostly-positive → high mean).
        XCTAssertGreaterThan(intent.probability(), 0.9,
                             "bounding evidence must not erase the learned signal")
    }
}
