import XCTest
@testable import SynapseCore

// MARK: - SemanticDistanceTests
// Tests StructuralHeuristicDistance contract:
//   1. Identical content returns 0.0
//   2. Fully disjoint content returns 1.0
//   3. Partial overlap returns value in (0.0, 1.0)
//   4. Text fallback works when no structural refs exist
//   5. Output is always in [0.0, 1.0]

final class SemanticDistanceTests: XCTestCase {

    private let strategy = StructuralHeuristicDistance()

    private func content(
        _ id: String, text: String,
        files: [String] = [], funcs: [String] = []
    ) -> SynapseContent {
        SynapseContent(id: id, text: text, fileReferences: files, functionNames: funcs)
    }

    func testIdenticalStructuralRefsReturnZeroDistance() {
        let a = content("a", text: "task", files: ["Foo.swift"], funcs: ["bar"])
        let b = content("b", text: "task", files: ["Foo.swift"], funcs: ["bar"])
        XCTAssertEqual(strategy.distance(from: a, to: b), 0.0, accuracy: 0.001)
    }

    func testFullyDisjointStructuralRefsReturnOneDistance() {
        let a = content("a", text: "unrelated", files: ["Alpha.swift"], funcs: ["doAlpha"])
        let b = content("b", text: "other", files: ["Beta.swift"], funcs: ["doBeta"])
        XCTAssertEqual(strategy.distance(from: a, to: b), 1.0, accuracy: 0.001)
    }

    func testPartialOverlapReturnsIntermediateDistance() {
        let a = content("a", text: "task", files: ["Shared.swift", "Unique.swift"], funcs: ["foo"])
        let b = content("b", text: "task", files: ["Shared.swift", "Other.swift"], funcs: ["bar"])
        let d = strategy.distance(from: a, to: b)
        XCTAssertGreaterThan(d, 0.0)
        XCTAssertLessThan(d, 1.0)
    }

    func testOutputAlwaysInZeroToOneRange() {
        let pairs: [(SynapseContent, SynapseContent)] = [
            (content("x", text: ""), content("y", text: "")),
            (content("x", text: "hello world"), content("y", text: "hello")),
            (content("x", text: "abc", files: ["A.swift"]), content("y", text: "xyz", files: ["B.swift"])),
        ]
        for (a, b) in pairs {
            let d = strategy.distance(from: a, to: b)
            XCTAssertGreaterThanOrEqual(d, 0.0, "Distance must be >= 0.0")
            XCTAssertLessThanOrEqual(d, 1.0, "Distance must be <= 1.0")
        }
    }

    func testTextFallbackWhenNoStructuralRefs() {
        // Identical text, no refs — should return 0.0 (identical)
        let a = content("a", text: "implement context decay algorithm")
        let b = content("b", text: "implement context decay algorithm")
        XCTAssertEqual(strategy.distance(from: a, to: b), 0.0, accuracy: 0.001)
    }

    func testTextFallbackDisjointText() {
        let a = content("a", text: "lighthouse primary goal")
        let b = content("b", text: "rabbit hole distraction")
        let d = strategy.distance(from: a, to: b)
        XCTAssertGreaterThan(d, 0.0)
        XCTAssertLessThanOrEqual(d, 1.0)
    }

    func testEmptyContentBothSidesReturnsZero() {
        let a = content("a", text: "")
        let b = content("b", text: "")
        // Both empty: no tokens, no refs — Jaccard of empty sets = 0.0
        XCTAssertEqual(strategy.distance(from: a, to: b), 0.0, accuracy: 0.001)
    }

    func testSymmetryProperty() {
        // Distance should be symmetric: d(a,b) == d(b,a)
        let a = content("a", text: "decay algorithm", files: ["Decay.swift"], funcs: ["compute"])
        let b = content("b", text: "referee logic", files: ["Referee.swift"], funcs: ["evaluate"])
        let dAB = strategy.distance(from: a, to: b)
        let dBA = strategy.distance(from: b, to: a)
        XCTAssertEqual(dAB, dBA, accuracy: 0.001, "Distance must be symmetric")
    }
}
