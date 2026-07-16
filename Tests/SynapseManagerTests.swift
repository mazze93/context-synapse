import XCTest
import Foundation
@testable import SynapseCore

// v0.4 SynapseManager: session persistence, circuit wiring, RSA epochs.

final class SynapseManagerTests: XCTestCase {

    private func tempSessionURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cs-mgr-\(UUID().uuidString)")
            .appendingPathComponent("session.json")
    }

    private func makeLighthouse(text: String = "ship the v0.4 release",
                                minutesAgo: Double = 20) -> LighthouseRecord {
        LighthouseRecord(
            id: UUID().uuidString, text: text,
            setAt: ISO8601DateFormatter().string(
                from: Date().addingTimeInterval(-minutesAgo * 60))
        )
    }

    private func makeManager(lighthouse: LighthouseRecord?,
                             sessionURL: URL? = nil) -> SynapseManager {
        let url = sessionURL ?? tempSessionURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return SynapseManager(sessionURL: url, lighthouse: lighthouse)
    }

    private func content(_ text: String) -> SynapseContent {
        SynapseContent(id: UUID().uuidString, text: text)
    }

    // MARK: - Epochs

    func testObserveWithoutLighthouseProducesNoEpoch() async {
        let manager = makeManager(lighthouse: nil)
        let epoch = await manager.observe(content("anything"), event: .fileSave)
        XCTAssertNil(epoch, "epochs are only meaningful relative to an anchor")
    }

    func testObserveAppendsEpochsWithMonotonicIndices() async {
        let manager = makeManager(lighthouse: makeLighthouse())
        for i in 0..<3 {
            let epoch = await manager.observe(content("thread \(i)"), event: .fileSave)
            XCTAssertEqual(epoch?.index, i)
        }
        let epochs = await manager.epochs
        XCTAssertEqual(epochs.count, 3)
    }

    // MARK: - RSA matrix properties

    func testRSAMatrixIsSymmetricWithUnitDiagonalAndLighthouseRowZero() async throws {
        let manager = makeManager(lighthouse: makeLighthouse(text: "anchor goal"))
        _ = await manager.observe(content("first thread"), event: .fileSave)
        let maybeEpoch = await manager.observe(content("second thread"), event: .gitCommit)
        let epoch = try XCTUnwrap(maybeEpoch)

        XCTAssertTrue(epoch.labels[0].hasPrefix("⚓"), "row 0 must be the lighthouse")
        XCTAssertEqual(epoch.labels.count, epoch.matrix.count)
        for (i, row) in epoch.matrix.enumerated() {
            XCTAssertEqual(row.count, epoch.matrix.count)
            XCTAssertEqual(row[i], 1.0, accuracy: 1e-9, "diagonal must be 1.0")
            for j in row.indices {
                XCTAssertEqual(epoch.matrix[i][j], epoch.matrix[j][i], accuracy: 1e-9,
                               "matrix must be symmetric")
                XCTAssertGreaterThanOrEqual(epoch.matrix[i][j], 0.0)
                XCTAssertLessThanOrEqual(epoch.matrix[i][j], 1.0)
            }
        }
    }

    // MARK: - Session persistence

    func testSessionSurvivesManagerRestart() async {
        let url = tempSessionURL()
        let lighthouse = makeLighthouse()

        let first = makeManager(lighthouse: lighthouse, sessionURL: url)
        _ = await first.observe(content("persistent thread"), event: .fileSave)
        let countBefore = await first.epochs.count

        let second = makeManager(lighthouse: lighthouse, sessionURL: url)
        let epochsAfter = await second.epochs
        let synapses = await second.trackedSynapses
        XCTAssertEqual(epochsAfter.count, countBefore, "epochs must survive restart")
        XCTAssertTrue(synapses.contains { $0.text == "persistent thread" },
                      "synapse clocks must survive restart")
    }

    func testRevisitedThreadReusesSynapseInsteadOfSpawningTwin() async {
        let manager = makeManager(lighthouse: makeLighthouse())
        _ = await manager.observe(content("same thread"), event: .fileSave)
        _ = await manager.observe(content("same thread"), event: .gitCommit)
        let synapses = await manager.trackedSynapses
        XCTAssertEqual(synapses.filter { $0.text == "same thread" }.count, 1)
        XCTAssertEqual(synapses.first { $0.text == "same thread" }?.interactions.count, 2)
    }

    func testTrackedSynapsesAreCapped() async {
        let manager = makeManager(lighthouse: makeLighthouse())
        for i in 0..<(SynapseManager.maxTrackedSynapses + 5) {
            _ = await manager.observe(content("thread \(i)"), event: .keystrokeBurst)
        }
        let count = await manager.trackedSynapses.filter { !$0.isLighthouse }.count
        XCTAssertLessThanOrEqual(count, SynapseManager.maxTrackedSynapses)
    }

    // MARK: - Drift is visible across epochs

    func testDriftingQueriesDegradeAnchorSaliency() async throws {
        // Lighthouse set 30 minutes ago; a fresh drifting thread must show
        // materially degraded saliency (this is the CLI regression, now at
        // the manager layer).
        let manager = makeManager(lighthouse: makeLighthouse(
            text: "wire the SynapseManager backward pass", minutesAgo: 30))
        let maybeEpoch = await manager.observe(content("vintage synthesizer prices"), event: .fileSave)
        let epoch = try XCTUnwrap(maybeEpoch)
        XCTAssertLessThan(epoch.lighthouseSaliency, 0.5,
            "a 30-min-old anchor + unrelated thread must read as drifted")
    }

    // MARK: - Circuit wiring

    func testBackwardPassProducesPredictionErrorForObservedSynapse() async throws {
        let manager = makeManager(lighthouse: makeLighthouse())
        let c = content("circuit thread")
        _ = await manager.observe(c, event: .buildFailure)
        let maybeEpoch = await manager.observe(c, event: .buildFailure)
        let epoch = try XCTUnwrap(maybeEpoch)
        XCTAssertFalse(epoch.predictionErrors.isEmpty,
            "backward pass must record prediction errors for observed synapses")
    }

    // MARK: - Rendering

    func testHeatmapRendersEveryRowAndSaliencyStripMatchesEpochCount() async throws {
        let manager = makeManager(lighthouse: makeLighthouse())
        _ = await manager.observe(content("alpha"), event: .fileSave)
        let maybeEpoch = await manager.observe(content("beta"), event: .fileSave)
        let epoch = try XCTUnwrap(maybeEpoch)

        let heatmap = RSARenderer.heatmap(epoch)
        XCTAssertEqual(heatmap.split(separator: "\n").count, epoch.labels.count + 2,
            "header + one line per row + column footer")
        XCTAssertTrue(heatmap.contains("⚓"))

        let epochs = await manager.epochs
        let strip = RSARenderer.saliencyStrip(epochs)
        let sparkLine = strip.split(separator: "\n")[1]
        XCTAssertEqual(sparkLine.prefix(while: { "▁▂▃▄▅▆▇█".contains($0) }).count,
                       epochs.count)
    }
}
