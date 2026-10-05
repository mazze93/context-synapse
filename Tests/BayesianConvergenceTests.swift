import XCTest
@testable import SynapseCore

final class BayesianConvergenceTests: XCTestCase {
    private static var cliExecutableURL: URL?

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @discardableResult
    private func runProcess(executable: String, arguments: [String], in directory: URL) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.currentDirectoryURL = directory
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private func ensureCLIExecutable() throws -> URL {
        if let cached = Self.cliExecutableURL, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let repoRoot = repositoryRootURL()
        let execURL = repoRoot.appendingPathComponent(".build/debug/contextsynapse")
        if !FileManager.default.fileExists(atPath: execURL.path) {
            throw XCTSkip("CLI executable not found at \(execURL.path). Run swift build before swift test.")
        }
        Self.cliExecutableURL = execURL
        return execURL
    }
    
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
    
    // MARK: - Export/Import Tests
    
    func testExportStateCreatesValidFile() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_Export_\(UUID().uuidString)")
        let tempDir = FileManager.default.temporaryDirectory
        let exportFile = tempDir.appendingPathComponent("test_export_\(UUID().uuidString).json")
        
        // Export state
        let success = core.exportState(to: exportFile, metadata: ["test": "value"])
        XCTAssertTrue(success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportFile.path))
        
        // Verify file contains valid JSON
        let data = try Data(contentsOf: exportFile)
        let bundle = try JSONDecoder().decode(ExportBundle.self, from: data)
        XCTAssertEqual(bundle.version, "1.0")
        XCTAssertEqual(bundle.metadata["test"], "value")
        XCTAssertFalse(bundle.weights.intents.isEmpty)
        XCTAssertFalse(bundle.regions.isEmpty)
        
        // Cleanup
        try? FileManager.default.removeItem(at: exportFile)
    }
    
    func testImportStateRestoresData() throws {
        let core1 = SynapseCore(folderName: "ContextSynapseTests_Import1_\(UUID().uuidString)")
        let core2 = SynapseCore(folderName: "ContextSynapseTests_Import2_\(UUID().uuidString)")
        
        // Modify core1 with feedback
        for _ in 0..<10 {
            core1.applyFeedbackUpdate(chosenIntent: "Create", chosenTone: "Technical", chosenDomain: "Work", positive: true)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let exportFile = tempDir.appendingPathComponent("test_import_\(UUID().uuidString).json")
        
        // Export from core1
        XCTAssertTrue(core1.exportState(to: exportFile))
        
        // Import to core2
        XCTAssertTrue(core2.importState(from: exportFile, merge: false))
        
        // Verify core2 has same weights
        let w1 = core1.loadOrCreateDefaultWeights()
        let w2 = core2.loadOrCreateDefaultWeights()
        XCTAssertEqual(w1.priors.intents["Create"]?.alpha, w2.priors.intents["Create"]?.alpha)
        XCTAssertEqual(w1.priors.intents["Create"]?.beta, w2.priors.intents["Create"]?.beta)
        
        // Cleanup
        try? FileManager.default.removeItem(at: exportFile)
    }
    
    func testImportStateMergesDataCorrectly() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_Merge_\(UUID().uuidString)")
        
        // Set initial state
        for _ in 0..<5 {
            core.applyFeedbackUpdate(chosenIntent: "Create", chosenTone: "Technical", chosenDomain: "Work", positive: true)
        }
        let w1 = core.loadOrCreateDefaultWeights()
        let alpha1 = w1.priors.intents["Create"]?.alpha ?? 0
        
        // Create export with different feedback
        let core2 = SynapseCore(folderName: "ContextSynapseTests_Merge2_\(UUID().uuidString)")
        for _ in 0..<10 {
            core2.applyFeedbackUpdate(chosenIntent: "Create", chosenTone: "Technical", chosenDomain: "Work", positive: true)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let exportFile = tempDir.appendingPathComponent("test_merge_\(UUID().uuidString).json")
        XCTAssertTrue(core2.exportState(to: exportFile))
        
        // Import with merge
        XCTAssertTrue(core.importState(from: exportFile, merge: true))
        
        // Verify merged values
        let w2 = core.loadOrCreateDefaultWeights()
        let alpha2 = w2.priors.intents["Create"]?.alpha ?? 0
        
        // After merge, alpha should be between the two original values
        XCTAssertGreaterThan(alpha2, alpha1)
        
        // Cleanup
        try? FileManager.default.removeItem(at: exportFile)
    }

    func testAssemblePromptUsesCanonicalFormat() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_Assemble_\(UUID().uuidString)")
        let prompt = core.assemblePrompt(tone: "Concise", intent: "Analyze", domain: "Work", query: "Check this crash")
        XCTAssertEqual(prompt, "[Concise] [Analyze] [Work]: Check this crash")
    }

    func testResetToFactoryDefaultsOverwritesPersistedState() throws {
        let core = SynapseCore(folderName: "ContextSynapseTests_Reset_\(UUID().uuidString)")

        var mutatedWeights = core.loadOrCreateDefaultWeights()
        mutatedWeights.intents["Create"] = 2.75
        core.saveWeights(mutatedWeights)
        core.saveRegions([Region(name: "CustomRegion", vector: [9.0, 1.0, 2.0])])

        let reset = core.resetToFactoryDefaults()
        XCTAssertEqual(reset.weights.intents["Create"], 1.0)
        XCTAssertEqual(reset.regions.map { $0.name }, ["NorthAmerica", "EMEA", "APAC"])

        let reloadedWeights = core.loadOrCreateDefaultWeights()
        let reloadedRegions = core.loadOrSeedRegions()
        XCTAssertEqual(reloadedWeights.intents["Create"], 1.0)
        XCTAssertEqual(reloadedRegions.map { $0.name }, ["NorthAmerica", "EMEA", "APAC"])
    }

    func testExportAndImportAcceptUserFlagBeforeCommandFlag() throws {
        let executable = try ensureCLIExecutable()
        let tempDir = FileManager.default.temporaryDirectory
        let exportFile = tempDir.appendingPathComponent("test_cli_order_\(UUID().uuidString).json")
        let user = "cli_order_user"

        let exportResult = try runProcess(
            executable: executable.path,
            arguments: ["--user", user, "--export", exportFile.path, "--metadata", "suite=cli_flag_order"],
            in: repositoryRootURL()
        )
        XCTAssertEqual(exportResult.status, 0, "Export command failed.\nstdout:\n\(exportResult.stdout)\nstderr:\n\(exportResult.stderr)")
        XCTAssertTrue(exportResult.stdout.contains("Successfully exported state"), "Unexpected export output: \(exportResult.stdout)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportFile.path), "Export file was not created")

        let importResult = try runProcess(
            executable: executable.path,
            arguments: ["--user", user, "--import", exportFile.path, "--merge"],
            in: repositoryRootURL()
        )
        XCTAssertEqual(importResult.status, 0, "Import command failed.\nstdout:\n\(importResult.stdout)\nstderr:\n\(importResult.stderr)")
        XCTAssertTrue(importResult.stdout.contains("Successfully imported state"), "Unexpected import output: \(importResult.stdout)")

        try? FileManager.default.removeItem(at: exportFile)
    }
}
