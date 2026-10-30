import XCTest
@testable import SynapseCore
final class PR40ReviewProbeTests: XCTestCase {
    func testDefaultConvenienceBypassesOwnershipValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = root.appendingPathComponent("ContextSynapse/users/Default")
        try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: true)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("ContextSynapse/users/default").path), "case-insensitive volume required")
        let profile = UserProfile(id: "Default", displayName: "existing owner", createdAt: "old", lastUsedAt: "old")
        try JSONEncoder().encode(profile).write(to: owner.appendingPathComponent("profile.json"))
        let seed = SynapseCore(folderName: "Seed", baseOverride: root)
        var weights = seed.defaultWeights()
        weights.intents["Create"] = 2.75
        try JSONEncoder().encode(weights).write(to: owner.appendingPathComponent("config.json"))
        XCTAssertThrowsError(try SynapseCore(user: "default", baseOverride: root))
        let bypass = SynapseCore(baseOverride: root)
        XCTAssertEqual(bypass.currentUser, "default")
        XCTAssertEqual(bypass.loadOrCreateDefaultWeights().intents["Create"], 2.75)
        weights.intents["Create"] = 0.25
        XCTAssertTrue(bypass.saveWeights(weights))
        let changed = try JSONDecoder().decode(Weights.self, from: Data(contentsOf: owner.appendingPathComponent("config.json")))
        XCTAssertEqual(changed.intents["Create"], 0.25)
    }
}
