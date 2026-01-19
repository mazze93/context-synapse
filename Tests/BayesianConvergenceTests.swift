import XCTest
@testable import SynapseCore

final class BayesianConvergenceTests: XCTestCase {
    
    func testPriorProbabilityIncreasesWithPositiveFeedback() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_ProbUp_\(UUID().uuidString)")
        var w = core.loadOrCreateDefaultWeights()
        let key = "Create"
        let p0 = w.priors.intents[key]?.probability() ?? 0.5
        
        for _ in 0..<25 {
            core.applyFeedbackUpdate(chosenIntent: key, chosenTone: "Concise", chosenDomain: "Work", positive: true)
        }
        w = core.loadOrCreateDefaultWeights()
        let p1 = w.priors.intents[key]?.probability() ?? 0.5
        XCTAssertGreaterThan(p1, p0)
        XCTAssertGreaterThan(p1, 0.70)
        let wCreate = w.intents[key] ?? 1.0
        XCTAssertGreaterThan(wCreate, 1.8)
    }
    
    func testPriorProbabilityDecreasesWithNegativeFeedback() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_ProbDown_\(UUID().uuidString)")
        var w = core.loadOrCreateDefaultWeights()
        let key = "Analyze"
        let p0 = w.priors.intents[key]?.probability() ?? 0.5
        
        for _ in 0..<25 {
            core.applyFeedbackUpdate(chosenIntent: key, chosenTone: "Technical", chosenDomain: "Work", positive: false)
        }
        w = core.loadOrCreateDefaultWeights()
        let p1 = w.priors.intents[key]?.probability() ?? 0.5
        XCTAssertLessThan(p1, p0)
        XCTAssertLessThan(p1, 0.30)
        let wAnalyze = w.intents[key] ?? 1.0
        XCTAssertLessThan(wAnalyze, 1.2)
    }
    
    func testFaultInjectionDoesNotCrashAndReturnsMatrix() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_Faults_\(UUID().uuidString)")
        core.faultProbability = 0.6
        let regs = core.loadOrSeedRegions()
        let (matrix, nearest) = core.computeRegionSimilarities(regionsIn: regs)
        XCTAssertEqual(matrix.count, regs.count)
        XCTAssertEqual(matrix.first?.count, regs.count)
        XCTAssertEqual(nearest.keys.count, regs.count)
    }
    
    func testCosineSimilarityToleratesMismatchedVectorLengths() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_Cosine_\(UUID().uuidString)")
        let a = [1.0, 0.0, 0.0]
        let b = [1.0, 0.0]
        let s = core.cosineSimilarity(a, b)
        XCTAssertGreaterThan(s, 0.99)
    }
}
