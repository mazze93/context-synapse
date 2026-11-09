import XCTest
@testable import SynapseCore

final class SessionDiffTests: XCTestCase {
    private func run(_ context: [String: String], at timestamp: String = "synthetic") -> SynapseCore.RunLog {
        .init(timestamp: timestamp, input: "fixture", chosenIntent: "Create", chosenTone: "Concise",
              chosenDomain: "Work", assembledPrompt: "fixture", context: context)
    }

    func testKnownDifferencesAndLegacyUnknowns() throws {
        let before = SynapseCore.RunLog.DecaySnapshot(decayWeight: 0.8, rotScore: 0.1,
            lighthouseSaliency: 0.9, refereeMode: "functional", interventionFired: false)
        let after = SynapseCore.RunLog.DecaySnapshot(decayWeight: 0.3, rotScore: 0.7,
            lighthouseSaliency: 0.3, refereeMode: "abrasive", interventionFired: true)
        let diff = try SessionDiff(before: run(before.contextFields), after: run(after.contextFields))
        XCTAssertEqual(diff.decayWeight.delta!, -0.5, accuracy: 0.000001)
        XCTAssertEqual(diff.rotScore.delta!, 0.6, accuracy: 0.000001)
        XCTAssertEqual(diff.lighthouseSaliency.delta!, -0.6, accuracy: 0.000001)
        XCTAssertEqual(diff.afterInterventionFired, true)
        let legacy = try SessionDiff(before: run([:]), after: run(after.contextFields))
        XCTAssertNil(legacy.decayWeight.before)
        XCTAssertNil(legacy.decayWeight.delta)
        XCTAssertTrue(legacy.formatted.contains("unavailable"))
    }

    func testNonFiniteTelemetryRejected() throws {
        let context = ["decayWeight": "nan", "rotScore": "0.1", "lighthouseSaliency": "0.9",
                       "refereeMode": "functional", "interventionFired": "false"]
        XCTAssertThrowsError(try SessionDiff(before: run(context), after: run([:])))
    }

    func testCLIReadsFixturesWithoutChangingThemAndRejectsMalformedInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = root.appendingPathComponent("before.json")
        let after = root.appendingPathComponent("after.json")
        let bytes = try JSONEncoder().encode(run([:]))
        try bytes.write(to: before); try bytes.write(to: after)
        let cli = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/contextsynapse")
        func invoke(_ arguments: [String]) throws -> (Int32, String) {
            let task = Process(); task.executableURL = cli; task.arguments = arguments
            let out = Pipe(); task.standardOutput = out; task.standardError = Pipe()
            try task.run()
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit(); return (task.terminationStatus, text)
        }
        let good = try invoke(["--session-diff", before.path, after.path])
        XCTAssertEqual(good.0, 0); XCTAssertTrue(good.1.contains("unavailable"))
        XCTAssertEqual(try Data(contentsOf: before), bytes)
        XCTAssertEqual(try Data(contentsOf: after), bytes)
        XCTAssertEqual(try invoke(["--session-diff", before.path]).0, 2)
        try Data("not JSON".utf8).write(to: after)
        XCTAssertEqual(try invoke(["--session-diff", before.path, after.path]).0, 1)
        XCTAssertEqual(try invoke(["--session-diff", before.path, "missing.json"]).0, 1)
    }
}
