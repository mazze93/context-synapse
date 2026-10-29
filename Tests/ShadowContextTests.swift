import XCTest
@testable import SynapseCore

final class ShadowContextTests: XCTestCase {
    private func withCore(_ body: (SynapseCore) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = SynapseCore(baseOverride: root)
        try await body(core)
    }

    func testForkReturnAndPromotionPreserveIndependentHistories() async throws {
        try await withCore { core in
            XCTAssertTrue(core.saveLighthouse(SynapseContent(id: "primary-anchor", text: "primary goal")))
            let primary = core.makeSynapseManager()
            await primary.observe(SynapseContent(id: "primary-work", text: "primary work"), event: .gitCommit)
            let original = try Data(contentsOf: core.sessionURL)
            let store = try ShadowContextStore(core: core)
            let shadow = try store.fork(goal: "side quest")
            XCTAssertNotEqual(store.sessionURL, core.sessionURL)
            XCTAssertEqual(try store.loadLighthouse()?.text, "side quest")
            let manager = SynapseManager(sessionURL: store.sessionURL, lighthouse: try store.loadLighthouse())
            await manager.observe(SynapseContent(id: "shadow-work", text: "shadow work"), event: .buildFailure)
            let shadowURL = store.sessionURL
            let shadowBytes = try Data(contentsOf: shadowURL)
            XCTAssertEqual(try Data(contentsOf: core.sessionURL), original)
            XCTAssertThrowsError(try store.fork(goal: "nested"))
            let resumed = try ShadowContextStore(core: core)
            XCTAssertEqual(resumed.activeID, shadow)
            try resumed.promoteShadow()
            XCTAssertFalse(resumed.isShadow)
            XCTAssertEqual(resumed.activeID, shadow)
            XCTAssertEqual(resumed.priorPrimaryIDs, ["primary"])
            XCTAssertEqual(try Data(contentsOf: resumed.sessionURL), shadowBytes)
            XCTAssertEqual(try Data(contentsOf: core.sessionURL), original)
            // Forking from a promoted primary must return to that context.
            _ = try resumed.fork(goal: "second side quest")
            try resumed.returnToPrimary()
            XCTAssertEqual(resumed.activeID, shadow)
            XCTAssertEqual(try Data(contentsOf: resumed.sessionURL), shadowBytes)
        }
    }

    func testPromotedPrimaryCanBeClearedAndExplicitlyReanchored() async throws {
        try await withCore { core in
            XCTAssertTrue(core.saveLighthouse(SynapseContent(id: "p", text: "original")))
            let store = try ShadowContextStore(core: core)
            _ = try store.fork(goal: "promoted")
            XCTAssertThrowsError(try store.clearLighthouse())
            try store.promoteShadow()
            try store.clearLighthouse()
            XCTAssertNil(try ShadowContextStore(core: core).loadLighthouse())
            XCTAssertEqual(core.loadLighthouseRecord()?.text, "original")
            try store.saveLighthouse(SynapseContent(id: "replacement", text: "explicit replacement"))
            XCTAssertEqual(try ShadowContextStore(core: core).loadLighthouse()?.id, "replacement")
        }
    }

    func testReturnRestoresOriginalPrimaryAndRetainsShadow() async throws {
        try await withCore { core in
            XCTAssertTrue(core.saveLighthouse(SynapseContent(id: "primary", text: "primary")))
            let store = try ShadowContextStore(core: core)
            _ = try store.fork(goal: "shadow")
            let shadowURL = store.sessionURL
            try store.returnToPrimary()
            XCTAssertEqual(store.activeID, "primary")
            XCTAssertEqual(try store.loadLighthouse()?.id, "primary")
            XCTAssertTrue(FileManager.default.fileExists(atPath: shadowURL.path))
            XCTAssertThrowsError(try store.returnToPrimary())
            XCTAssertThrowsError(try store.promoteShadow())
        }
    }

    func testInvalidForkAndCorruptIndexFailBeforeSelectionChanges() async throws {
        try await withCore { core in
            let store = try ShadowContextStore(core: core)
            XCTAssertThrowsError(try store.fork(goal: "no anchor"))
            XCTAssertTrue(core.saveLighthouse(SynapseContent(id: "p", text: "primary")))
            XCTAssertThrowsError(try store.fork(goal: " \n "))
            let index = core.configURL.deletingLastPathComponent().appendingPathComponent("contexts.json")
            try Data("broken".utf8).write(to: index)
            XCTAssertThrowsError(try ShadowContextStore(core: core))
            try FileManager.default.removeItem(at: index)
            // A directory at the index destination makes pointer persistence fail.
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            XCTAssertThrowsError(try store.fork(goal: "unselected orphan"))
            XCTAssertEqual(store.activeID, "primary")
            XCTAssertEqual(core.loadLighthouseRecord()?.id, "p")
        }
    }

    func testCLIExplicitForkQueryReturnAndPromotion() throws {
        let user = "shadow-cli-" + UUID().uuidString
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ContextSynapse/users/" + user)
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/contextsynapse")
        func invoke(_ arguments: [String]) throws -> Int32 {
            let task = Process(); task.executableURL = cli
            task.arguments = arguments + ["--user", user]
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            try task.run(); task.waitUntilExit(); return task.terminationStatus
        }
        XCTAssertEqual(try invoke(["--lighthouse", "primary goal"]), 0)
        XCTAssertEqual(try invoke(["primary work"]), 0)
        let session = root.appendingPathComponent("session.json")
        let original = try Data(contentsOf: session)
        XCTAssertEqual(try invoke(["--fork-shadow", "explicit side goal"]), 0)
        XCTAssertEqual(try invoke(["side work"]), 0)
        XCTAssertEqual(try Data(contentsOf: session), original)
        XCTAssertEqual(try invoke(["--return-primary"]), 0)
        XCTAssertEqual(try invoke(["--rsa"]), 0)
        XCTAssertEqual(try invoke(["--fork-shadow", "second goal"]), 0)
        XCTAssertEqual(try invoke(["--promote-shadow"]), 0)
        XCTAssertEqual(try invoke(["--rsa"]), 0)
        XCTAssertEqual(try Data(contentsOf: session), original)
        XCTAssertEqual(try invoke(["--return-primary", "--promote-shadow"]), 2)
    }
}
