// Tests for the on-device FoundationModelsClient.
//
// Guarded by #if canImport(FoundationModels): on SDKs without the framework
// (e.g. the macos-15 CI runner) this file compiles out entirely, so CI stays
// green. Where the framework exists but the model is not enabled (Apple
// Intelligence off / assets downloading), the round-trip test skips with the
// reason rather than failing.

#if canImport(FoundationModels)

import XCTest
@testable import SynapseCore

final class FoundationModelsClientTests: XCTestCase {

    /// `isAvailable` and `unavailabilityReason` must never disagree: available
    /// iff there is no reason. Pure logic — runs regardless of model state.
    func testAvailabilityFlagsAreConsistent() {
        XCTAssertEqual(FoundationModelsClient.isAvailable,
                       FoundationModelsClient.unavailabilityReason == nil,
                       "isAvailable must be true exactly when there is no unavailability reason")
    }

    /// End-to-end: drive the on-device model and assert non-empty content.
    /// Skips (does not fail) when the model isn't available on this machine.
    func testOnDeviceRoundTrip() async throws {
        try XCTSkipUnless(
            FoundationModelsClient.isAvailable,
            "on-device model unavailable — \(FoundationModelsClient.unavailabilityReason ?? "unknown reason")"
        )

        let client = FoundationModelsClient(instructions: "Answer in one short word.")
        let result: Result<String, Error> = await withCheckedContinuation { continuation in
            client.sendPrompt("Reply with a single friendly word.") { outcome in
                continuation.resume(returning: outcome)
            }
        }

        switch result {
        case .success(let text):
            XCTAssertFalse(
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "on-device model returned empty content"
            )
        case .failure(let error):
            XCTFail("on-device round-trip failed: \(error.localizedDescription)")
        }
    }

    /// Provenance must be honest: available iff no reason, on-device, and it
    /// never claims to leave the device. Runs regardless of model state (no
    /// inference performed).
    func testProvenanceRecordIsHonest() {
        let record = FoundationModelsClient().provenance()
        XCTAssertEqual(record.framework, "FoundationModels")
        XCTAssertEqual(record.execution, .onDevice)
        XCTAssertFalse(record.leavesDevice, "on-device model must never report leaving the device")
        XCTAssertEqual(record.available, record.unavailabilityReason == nil)
        XCTAssertEqual(record.available, FoundationModelsClient.isAvailable)
        XCTAssertFalse(record.environment.osVersion.isEmpty)
    }

    /// Repeatable benchmark: N timed on-device inferences, sane summary stats,
    /// and a durable JSON record. Skips when the model is unavailable. Prints
    /// the report so a run leaves observable evidence of identity + timing.
    func testBenchmarkIsRepeatableAndRecorded() async throws {
        try XCTSkipUnless(
            FoundationModelsClient.isAvailable,
            "on-device model unavailable — \(FoundationModelsClient.unavailabilityReason ?? "unknown reason")"
        )
        guard #available(macOS 26.0, *) else { throw XCTSkip("requires macOS 26") }

        let client = FoundationModelsClient(instructions: "Answer in one sentence.")
        let report = try await client.benchmark(iterations: 3)

        XCTAssertEqual(report.iterations, 3)
        XCTAssertEqual(report.latenciesMs.count, 3)
        XCTAssertTrue(report.latenciesMs.allSatisfy { $0 > 0 }, "each run must take measurable time")
        XCTAssertLessThanOrEqual(report.minMs, report.medianMs)
        XCTAssertLessThanOrEqual(report.medianMs, report.maxMs)
        XCTAssertEqual(report.provenance.framework, "FoundationModels")
        XCTAssertTrue(report.provenance.available)

        // Persist the full record ON-DEVICE only (Application Support, outside
        // the repo, never CI). We do NOT print it: the record carries a host
        // fingerprint and stdout is a CI-log leak channel.
        let core = SynapseCore(folderName: "ContextSynapseTests_AIBench_\(UUID().uuidString)")
        let url = try XCTUnwrap(core.recordAIBenchmark(report), "benchmark record must persist on-device")
        XCTAssertTrue(url.path.contains("Application Support"),
                      "records must live on-device under Application Support")

        // Non-identifying breadcrumb only (latency, no host/model fingerprint).
        print("benchmark ok: \(report.iterations) runs, median \(Int(report.medianMs)) ms")
    }
}

#endif
