import XCTest
@testable import SynapseCore

/// Provenance/benchmark records are generic and must compile & pass everywhere,
/// including the macos-15 CI runner (no FoundationModels). These tests pin the
/// summary-statistics math and Codable round-trips — the deterministic core the
/// on-device benchmark relies on.
final class AIProvenanceTests: XCTestCase {

    // MARK: - Benchmark statistics

    func testStatsOddSampleCount() {
        let r = AIBenchmarkReport(label: "t", prompt: "p",
                                  latenciesMs: [30, 10, 100, 20, 40],   // unsorted on purpose
                                  provenance: Self.stubProvenance())
        XCTAssertEqual(r.iterations, 5)
        XCTAssertEqual(r.meanMs, 40, accuracy: 1e-9)
        XCTAssertEqual(r.medianMs, 30, accuracy: 1e-9)   // middle of sorted [10,20,30,40,100]
        XCTAssertEqual(r.minMs, 10, accuracy: 1e-9)
        XCTAssertEqual(r.maxMs, 100, accuracy: 1e-9)
        XCTAssertEqual(r.p90Ms, 100, accuracy: 1e-9)     // nearest-rank: ceil(0.9*5)=5 -> idx4
    }

    func testStatsEvenSampleCount() {
        let r = AIBenchmarkReport(label: "t", prompt: "p",
                                  latenciesMs: [40, 10, 30, 20],
                                  provenance: Self.stubProvenance())
        XCTAssertEqual(r.meanMs, 25, accuracy: 1e-9)
        XCTAssertEqual(r.medianMs, 25, accuracy: 1e-9)   // (20+30)/2
        XCTAssertEqual(r.p90Ms, 40, accuracy: 1e-9)      // ceil(0.9*4)=4 -> idx3
    }

    func testEmptySamplesAreZeroedNotCrashing() {
        let r = AIBenchmarkReport(label: "t", prompt: "p",
                                  latenciesMs: [], provenance: Self.stubProvenance())
        XCTAssertEqual(r.iterations, 0)
        XCTAssertEqual(r.meanMs, 0)
        XCTAssertEqual(r.medianMs, 0)
        XCTAssertEqual(r.p90Ms, 0)
    }

    // MARK: - Codable round-trips (durable records)

    func testProvenanceRecordRoundTrips() throws {
        let original = Self.stubProvenance()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIProvenanceRecord.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testBenchmarkReportRoundTrips() throws {
        let original = AIBenchmarkReport(label: "latency", prompt: "p",
                                         latenciesMs: [12.5, 9.0, 15.25],
                                         provenance: Self.stubProvenance())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIBenchmarkReport.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertFalse(original.jsonString().isEmpty)
    }

    // MARK: - Environment capture

    func testCurrentEnvironmentIsPopulated() {
        let env = AIEnvironment.current()
        XCTAssertFalse(env.osVersion.isEmpty, "OS version must be captured")
        XCTAssertGreaterThan(env.physicalMemoryBytes, 0, "physical memory must be captured")
        // On macOS these sysctls are present; assert non-empty when non-nil.
        if let chip = env.chip { XCTAssertFalse(chip.isEmpty) }
    }

    func testLeavesDeviceMatchesExecution() {
        XCTAssertFalse(Self.stubProvenance(execution: .onDevice).leavesDevice)
        XCTAssertTrue(Self.stubProvenance(execution: .network).leavesDevice)
        XCTAssertFalse(Self.stubProvenance(execution: .privateCloud).leavesDevice)
    }

    // MARK: - On-device containment (leak prevention)

    /// Records carry a host fingerprint. They must persist under Application
    /// Support (on-device) and NEVER inside the repo tree — the sink that keeps
    /// them off GitHub/CI. Portable: runs everywhere, no model required.
    func testBenchmarkRecordsStayOnDeviceNotInRepo() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_AIRec_\(UUID().uuidString)")
        let report = AIBenchmarkReport(label: "t", prompt: "p",
                                       latenciesMs: [1, 2, 3],
                                       provenance: Self.stubProvenance())
        let url = try XCTUnwrap(core.recordAIBenchmark(report), "record must persist on-device")

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.path.contains("Application Support"),
                      "records must live under Application Support (on-device)")

        // Never written into the source repo (which would risk a commit/push).
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .path
        XCTAssertFalse(url.path.hasPrefix(repoRoot),
                       "AI records must never be written into the repo tree")
    }

    // MARK: - Helpers

    private static func stubProvenance(execution: AIExecutionLocus = .onDevice) -> AIProvenanceRecord {
        AIProvenanceRecord(
            framework: "Stub",
            modelIdentity: "stub-model",
            execution: execution,
            available: execution == .onDevice,
            unavailabilityReason: nil,
            supportedLanguages: ["en"],
            environment: AIEnvironment(osVersion: "test-os", chip: "test-chip",
                                       deviceModel: "test-model", physicalMemoryBytes: 1024),
            capturedAt: "2026-07-21T00:00:00Z"
        )
    }
}
