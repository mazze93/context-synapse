import XCTest
import Foundation
@testable import SynapseCore

// P1 backlog: RunLog decay snapshot + RefereeConfig persistence.

final class RunTelemetryTests: XCTestCase {

    private func makeCore(_ label: String) -> SynapseCore {
        SynapseCore(folderName: "ContextSynapseTests_\(label)_\(UUID().uuidString)")
    }

    // MARK: - DecaySnapshot

    func testDecaySnapshotContextRoundTrip() {
        let snapshot = SynapseCore.RunLog.DecaySnapshot(
            decayWeight: 0.734512,
            rotScore: 0.421337,
            lighthouseSaliency: 0.578663,
            refereeMode: "abrasive",
            interventionFired: true
        )
        var context = ["user": "default", "edgarState": "watching"]
        context.merge(snapshot.contextFields) { _, new in new }

        let run = SynapseCore.RunLog(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            input: "q", chosenIntent: "Create", chosenTone: "Concise",
            chosenDomain: "Work", assembledPrompt: "p", context: context
        )
        let decoded = run.decaySnapshot
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.decayWeight, snapshot.decayWeight, accuracy: 1e-6)
        XCTAssertEqual(decoded!.rotScore, snapshot.rotScore, accuracy: 1e-6)
        XCTAssertEqual(decoded!.lighthouseSaliency, snapshot.lighthouseSaliency, accuracy: 1e-6)
        XCTAssertEqual(decoded!.refereeMode, "abrasive")
        XCTAssertTrue(decoded!.interventionFired)
        // Pre-existing plain keys survive the merge
        XCTAssertEqual(run.context["edgarState"], "watching")
    }

    func testPreSnapshotRunLogYieldsNilSnapshot() {
        // Old on-disk logs carried only a raw rotScore string.
        let run = SynapseCore.RunLog(
            timestamp: "2026-01-01T00:00:00Z",
            input: "q", chosenIntent: "Create", chosenTone: "Concise",
            chosenDomain: "Work", assembledPrompt: "p",
            context: ["rotScore": "0.1234", "edgarState": "perched"]
        )
        XCTAssertNil(run.decaySnapshot)
    }

    func testDecaySnapshotSurvivesRunLogJSONRoundTrip() throws {
        let snapshot = SynapseCore.RunLog.DecaySnapshot(
            decayWeight: 1.0, rotScore: 0.0, lighthouseSaliency: 1.0,
            refereeMode: "functional", interventionFired: false
        )
        let run = SynapseCore.RunLog(
            timestamp: "2026-07-15T12:00:00Z",
            input: "q", chosenIntent: "i", chosenTone: "t",
            chosenDomain: "d", assembledPrompt: "p",
            context: snapshot.contextFields
        )
        let data = try JSONEncoder().encode(run)
        let decoded = try JSONDecoder().decode(SynapseCore.RunLog.self, from: data)
        XCTAssertEqual(decoded.decaySnapshot, snapshot)
    }

    // MARK: - RefereeConfig persistence

    func testRefereeConfigDefaultsToFunctionalWhenUnset() {
        let core = makeCore("RefereeDefault")
        XCTAssertEqual(core.loadRefereeConfig().mode, .functional)
    }

    func testRefereeConfigRoundTrip() {
        let core = makeCore("RefereeRoundTrip")
        var config = RefereeConfig()
        config.mode = .abrasive
        config.driftThresholdMinutes = 20.0
        XCTAssertTrue(core.saveRefereeConfig(config))
        XCTAssertEqual(core.loadRefereeConfig(), config)
    }

    func testRefereeConfigDoesNotDisturbWeightsFile() {
        // referee.json is a sibling of config.json precisely so that
        // saveWeights() can never clobber it — verify both survive.
        let core = makeCore("RefereeSibling")
        let weights = core.loadOrCreateDefaultWeights()
        core.saveRefereeConfig(RefereeConfig(mode: .abrasive))
        core.saveWeights(weights)
        XCTAssertEqual(core.loadRefereeConfig().mode, .abrasive)
        XCTAssertNotEqual(core.refereeConfigURL, core.configURL)
    }
}
