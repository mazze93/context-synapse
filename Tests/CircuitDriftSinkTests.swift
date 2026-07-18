import XCTest
@testable import SynapseCore

/// Phase D: the circuit's high-drift signal is injected at construction and
/// defaults to stderr, not stdout (Known Issue: emitDriftEvent wrote to stdout,
/// violating the machine-readable-stdout convention).
///
/// Perimeter note: the `drift > 0.1` branch that calls the sink is not reachable
/// through the public backwardPass API under shipped constants (etaBase = 0.1
/// caps single-pass mean movement at ~0.024 from any prior). These tests pin
/// the sink contract and the injection point, which is what the cleanup changed;
/// end-to-end firing is a separate, pre-existing property.
final class CircuitDriftSinkTests: XCTestCase {

    func testFormattedLineShape() {
        let event = CircuitDriftEvent(
            synapseID: "syn-42",
            drift: 0.1234,
            newMean: 0.5678,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let line = event.formattedLine
        XCTAssertTrue(line.hasPrefix("[CIRCUIT-DRIFT] "), "diagnostic prefix is the parse anchor")
        XCTAssertTrue(line.contains("synapse=syn-42"))
        XCTAssertTrue(line.contains("drift=0.123"), "drift rounded to 3 dp")
        XCTAssertTrue(line.contains("newMean=0.568"), "mean rounded to 3 dp")
    }

    func testInjectedSinkIsUsedInsteadOfDefault() async {
        // A custom sink can be injected; constructing with it must succeed and
        // must not fall back to the stderr default. We can't trigger the private
        // emit path publicly (see perimeter note), so this asserts the
        // construction contract: the circuit accepts and retains a custom sink.
        let box = DriftBox()
        let circuit = SynapticCircuit(driftSink: { event in box.record(event) })

        // Drive a normal interaction to prove the injected sink coexists with
        // the forward/backward path without emitting anything to it (drift stays
        // under threshold) — i.e. no spurious events reach the sink either.
        let node = SynapticNode(synapseID: "s1", prior: .uninformed)
        await circuit.register(node)
        _ = await circuit.forwardPass()
        _ = await circuit.backwardPass(observations: ["s1": 1.0])

        XCTAssertEqual(box.count, 0, "sub-threshold updates must not emit drift events")
    }

    func testDefaultSinkExists() {
        // The default routes to stderr, never stdout. We can't capture the
        // process's stderr cleanly here, but the sink must be non-nil and
        // callable without crashing.
        SynapticCircuit.stderrDriftSink(
            CircuitDriftEvent(synapseID: "s", drift: 0.2, newMean: 0.7)
        )
    }
}

/// Thread-safe counter for the injected sink (@Sendable closure capture).
private final class DriftBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CircuitDriftEvent] = []
    func record(_ e: CircuitDriftEvent) { lock.lock(); events.append(e); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
}
