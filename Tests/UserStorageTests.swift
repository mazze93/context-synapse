import XCTest
import Foundation
@testable import SynapseCore

final class UserStorageTests: XCTestCase {
    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testDistinctIdentifiersDoNotShareState() throws {
        try withRoot { root in
            // Create the punctuated name first: it must never be silently stripped.
            let names = ["Ada.Name", "Ada Name", "AdaName"]
            var paths = Set<String>()
            for name in names {
                let core = try SynapseCore(user: name, baseOverride: root)
                paths.insert(core.configURL.path)
                XCTAssertTrue(core.saveLighthouse(SynapseContent(id: name, text: name)))
            }
            XCTAssertEqual(paths.count, 3)
            for name in names {
                let core = try SynapseCore(user: name, baseOverride: root)
                XCTAssertEqual(core.loadLighthouseRecord()?.text, name)
            }
        }
    }

    func testExistingSpaceNamedDirectoryIsPreserved() throws {
        try withRoot { root in
            let userDir = root.appendingPathComponent("ContextSynapse/users/Ada Name")
            try FileManager.default.createDirectory(at: userDir.appendingPathComponent("logs"), withIntermediateDirectories: true)
            let seed = SynapseCore(folderName: "Seed", baseOverride: root)
            var weights = seed.defaultWeights()
            weights.intents["Create"] = 2.75
            try JSONEncoder().encode(weights).write(to: userDir.appendingPathComponent("config.json"))
            let regions = [Region(name: "preserved", vector: [1, 0])]
            try JSONEncoder().encode(regions).write(to: userDir.appendingPathComponent("regions.json"))
            let marker = Data("preserved".utf8)
            for path in ["logs/old.json", "session.json", "referee.json"] {
                try marker.write(to: userDir.appendingPathComponent(path))
            }
            let core = try SynapseCore(user: "Ada Name", baseOverride: root)
            XCTAssertEqual(core.loadOrCreateDefaultWeights().intents["Create"], 2.75)
            XCTAssertEqual(core.loadOrSeedRegions().first?.name, "preserved")
            for path in ["logs/old.json", "session.json", "referee.json"] {
                XCTAssertEqual(try Data(contentsOf: userDir.appendingPathComponent(path)), marker)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ContextSynapse/users/AdaName").path))
        }
    }

    func testAmbiguousLegacyDirectoryIsNotClaimedOrModified() throws {
        try withRoot { root in
            let owner = try SynapseCore(user: "AdaName", baseOverride: root)
            let before = try Data(contentsOf: owner.configURL)
            XCTAssertThrowsError(try SynapseCore(user: "Ada.Name", baseOverride: root))
            XCTAssertEqual(try Data(contentsOf: owner.configURL), before)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ContextSynapse/users/Ada.Name").path))
        }
    }

    func testConflictingProfileIsNotOverwritten() throws {
        try withRoot { root in
            let directory = root.appendingPathComponent("ContextSynapse/users/Ada")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let profile = UserProfile(id: "ada", displayName: "owner", createdAt: "old", lastUsedAt: "old")
            let bytes = try JSONEncoder().encode(profile)
            let url = directory.appendingPathComponent("profile.json")
            try bytes.write(to: url)
            XCTAssertThrowsError(try SynapseCore(user: "Ada", baseOverride: root))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path))
        }
    }

    func testInvalidIdentifiersThrowBeforeCreatingState() throws {
        try withRoot { root in
            for name in ["", "🔥", "***", "..", "../Ada", "Ada/B", "Ada\\B", "Ada:B", "Ada\nB"] {
                XCTAssertThrowsError(try SynapseCore(user: name, baseOverride: root), name)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ContextSynapse").path))
        }
    }

    func testLegacyPunctuatedLighthouseMigratesAndClearDoesNotResurrectIt() throws {
        try withRoot { root in
            let legacy = root.appendingPathComponent("ContextSynapse/Ada.Name/lighthouse.json")
            try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
            let record = LighthouseRecord(id: "anchor", text: "preserved", setAt: "2026-09-01T00:00:00Z")
            try JSONEncoder().encode(record).write(to: legacy)
            let core = try SynapseCore(user: "Ada.Name", baseOverride: root)
            XCTAssertEqual(core.loadLighthouseRecord(), record)
            XCTAssertTrue(FileManager.default.fileExists(atPath: core.lighthouseURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
            core.clearLighthouse()
            XCTAssertNil(core.loadLighthouseRecord())
        }
    }

    func testFailedLighthouseMigrationKeepsLegacyRecord() throws {
        try withRoot { root in
            let core = try SynapseCore(user: "Ada.Name", baseOverride: root)
            let legacy = core.appSupport.appendingPathComponent("Ada.Name/lighthouse.json")
            try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
            let record = LighthouseRecord(id: "anchor", text: "preserved", setAt: "2026-09-01T00:00:00Z")
            try JSONEncoder().encode(record).write(to: legacy)
            // A directory at the destination makes an atomic file replacement fail.
            try FileManager.default.createDirectory(at: core.lighthouseURL, withIntermediateDirectories: false)
            XCTAssertEqual(core.loadLighthouseRecord(), record)
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        }
    }
}
