import XCTest
import Foundation
@testable import SynapseCore

final class LighthouseStoreTests: XCTestCase {

    private func makeCore(_ label: String) -> SynapseCore {
        SynapseCore(folderName: "ContextSynapseTests_\(label)_\(UUID().uuidString)")
    }

    func testSaveLoadRoundTrip() {
        let core = makeCore("LighthouseRoundTrip")
        let content = SynapseContent(
            id: UUID().uuidString,
            text: "Finish the decay integration",
            fileReferences: ["SynapseWeightState.swift"],
            functionNames: ["recomputeRotScore"]
        )
        let setAt = Date()
        XCTAssertTrue(core.saveLighthouse(content, at: setAt))

        let record = core.loadLighthouseRecord()
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.id, content.id)
        XCTAssertEqual(record?.text, content.text)
        XCTAssertEqual(record?.fileReferences, content.fileReferences)
        XCTAssertEqual(record?.functionNames, content.functionNames)
        // ISO-8601 round-trip has second precision
        if let roundTripped = record?.setAtDate {
            XCTAssertEqual(roundTripped.timeIntervalSince1970,
                           setAt.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("setAtDate failed to parse")
        }
    }

    func testClearLighthouse() {
        let core = makeCore("LighthouseClear")
        core.saveLighthouse(SynapseContent(id: UUID().uuidString, text: "temp"))
        XCTAssertNotNil(core.loadLighthouseRecord())
        core.clearLighthouse()
        XCTAssertNil(core.loadLighthouseRecord())
    }

    func testLegacyPathMigration() throws {
        let core = makeCore("LighthouseLegacy")
        // Write a record at the pre-0.4 CLI location: <appSupport>/<user>/lighthouse.json
        let legacyDir = core.appSupport.appendingPathComponent(core.currentUser)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let record = LighthouseRecord(
            id: UUID().uuidString,
            text: "legacy anchor",
            setAt: ISO8601DateFormatter().string(from: Date())
        )
        let legacyURL = legacyDir.appendingPathComponent("lighthouse.json")
        try JSONEncoder().encode(record).write(to: legacyURL)

        // Load migrates to the canonical users/<user>/ path and removes the legacy copy
        let loaded = core.loadLighthouseRecord()
        XCTAssertEqual(loaded, record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: core.lighthouseURL.path))

        // Subsequent loads read the canonical copy
        XCTAssertEqual(core.loadLighthouseRecord(), record)
    }

    func testCanonicalPathWinsOverLegacy() throws {
        let core = makeCore("LighthouseCanonicalWins")
        let canonical = SynapseContent(id: UUID().uuidString, text: "canonical")
        core.saveLighthouse(canonical)

        let legacyDir = core.appSupport.appendingPathComponent(core.currentUser)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyRecord = LighthouseRecord(
            id: UUID().uuidString, text: "legacy",
            setAt: ISO8601DateFormatter().string(from: Date())
        )
        try JSONEncoder().encode(legacyRecord)
            .write(to: legacyDir.appendingPathComponent("lighthouse.json"))

        XCTAssertEqual(core.loadLighthouseRecord()?.text, "canonical")
    }

    func testBreadcrumbLineFormat() {
        let now = Date()
        let record = LighthouseRecord(
            id: UUID().uuidString,
            text: "ship v0.3",
            setAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-20 * 60))
        )
        let line = BreadcrumbWriter.breadcrumbLine(for: record, rotScore: 0.25, at: now)
        XCTAssertEqual(line, "⚓ Lighthouse: ship v0.3 — saliency 75% — last touched 20min ago")
    }

    func testBreadcrumbSaliencyClamped() {
        let record = LighthouseRecord(
            id: UUID().uuidString, text: "x",
            setAt: ISO8601DateFormatter().string(from: Date())
        )
        XCTAssertTrue(BreadcrumbWriter.breadcrumbLine(for: record, rotScore: 1.7)
            .contains("saliency 0%"))
        XCTAssertTrue(BreadcrumbWriter.breadcrumbLine(for: record, rotScore: -0.5)
            .contains("saliency 100%"))
    }
}
