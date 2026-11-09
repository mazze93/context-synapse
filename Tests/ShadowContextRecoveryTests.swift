import XCTest
@testable import SynapseCore

/// Regression: a missing or malformed shadow must not block the explicit
/// return. Normal construction still fails closed on damaged shadow data.
final class ShadowContextRecoveryTests: XCTestCase {
    private func withShadow(_ body: (SynapseCore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = SynapseCore(baseOverride: root)
        XCTAssertTrue(core.saveLighthouse(SynapseContent(id: "primary", text: "primary")))
        let store = try ShadowContextStore(core: core)
        _ = try store.fork(goal: "shadow")
        try body(core, store.sessionURL.deletingLastPathComponent())
    }

    private func assertReturnRecovers(_ core: SynapseCore) throws {
        XCTAssertThrowsError(try ShadowContextStore(core: core))
        let recovery = try ShadowContextStore(core: core, verifyActiveContext: false)
        XCTAssertTrue(recovery.isShadow)
        try recovery.returnToPrimary()
        let resumed = try ShadowContextStore(core: core)
        XCTAssertEqual(resumed.activeID, "primary")
        XCTAssertEqual(try resumed.loadLighthouse()?.id, "primary")
    }

    func testReturnSucceedsWhenShadowAnchorIsMissing() throws {
        try withShadow { core, folder in
            try FileManager.default.removeItem(at: folder.appendingPathComponent("lighthouse.json"))
            try assertReturnRecovers(core)
        }
    }

    func testReturnSucceedsWhenShadowSessionIsMalformed() throws {
        try withShadow { core, folder in
            try Data("broken".utf8).write(to: folder.appendingPathComponent("session.json"))
            try assertReturnRecovers(core)
        }
    }

    func testRecoveryConstructionStillRejectsCorruptIndex() throws {
        try withShadow { core, _ in
            let index = core.configURL.deletingLastPathComponent().appendingPathComponent("contexts.json")
            try Data("broken".utf8).write(to: index)
            XCTAssertThrowsError(try ShadowContextStore(core: core, verifyActiveContext: false))
        }
    }
}
