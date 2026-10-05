import XCTest
@testable import SynapseCore

final class PR40CircuitTests: XCTestCase {
    func testUpdatingEdgeWeightPreservesEdgeIdentity() async throws {
        let circuit = SynapticCircuit()
        let source = SynapticNode(synapseID: "source")
        let target = SynapticNode(synapseID: "target")
        let edge = CircuitEdge(source: source.id, target: target.id, weight: 0.2)
        await circuit.register(source)
        await circuit.register(target)
        await circuit.connect(edge)
        await circuit.updateEdgeWeight(id: edge.id, weight: 0.8)
        await circuit.updateEdgeWeight(id: edge.id, weight: 0.5)
        let snapshot = await circuit.snapshot()
        XCTAssertEqual(snapshot.edges.count, 1)
        XCTAssertEqual(snapshot.edges.first?.id, edge.id)
        XCTAssertEqual(snapshot.edges.first?.weight, 0.5)
    }

    func testFaultInjectionReportsIsolatedNodeAsTooIsolated() async throws {
        let circuit = SynapticCircuit()
        await circuit.register(SynapticNode(synapseID: "isolated"))
        _ = await circuit.forwardPass()
        let report = await circuit.injectFault(intoSynapse: "isolated", severity: 1.0)
        XCTAssertEqual(report.propagationDepth, 0)
        XCTAssertEqual(report.affectedNodeCount, 0)
        XCTAssertTrue(report.isTooIsolated)
        XCTAssertFalse(report.isHealthy)
    }
}
