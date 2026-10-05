import XCTest
@testable import SynapseCore

/// Link 1 of the GUI-write-failure verification (ADR-005): prove that a genuine
/// disk-I/O failure is reported as `false` by the persistence methods. This is
/// the only link in the chain that carries real branching logic; the ViewModel
/// reflection and the SwiftUI banner rendering are covered in ADR-005 as
/// deferred / inherent-perimeter.
///
/// Mechanism: the `baseOverride` init seam points storage at a temp directory
/// made read-only (chmod 0555), so atomic writes fail with EACCES.
final class PersistenceFailureTests: XCTestCase {

    private func makeReadOnlyRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSFail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        return root
    }

    /// Restore write permission so the temp dir can be torn down by the OS.
    private func makeWritableAgain(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func testSaveWeightsReportsFailureOnUnwritableStorage() throws {
        // root privileges bypass POSIX permission bits — the write would
        // succeed and this test would silently pass without proving anything.
        try XCTSkipIf(geteuid() == 0, "root bypasses file permissions; cannot induce EACCES")

        let root = try makeReadOnlyRoot()
        defer { makeWritableAgain(root) }

        let core = SynapseCore(folderName: "CS_\(UUID().uuidString)",
                               user: "u",
                               baseOverride: root)

        XCTAssertFalse(core.saveWeights(core.defaultWeights()),
                       "atomic write beneath a read-only root must report failure, not swallow it")
    }

    func testSaveRegionsAndLogRunAlsoReportFailure() throws {
        try XCTSkipIf(geteuid() == 0, "root bypasses file permissions; cannot induce EACCES")

        let root = try makeReadOnlyRoot()
        defer { makeWritableAgain(root) }

        let core = SynapseCore(folderName: "CS_\(UUID().uuidString)",
                               user: "u",
                               baseOverride: root)

        XCTAssertFalse(core.saveRegions(core.defaultRegions(for: core.defaultWeights())),
                       "saveRegions must report failure on unwritable storage")

        let run = SynapseCore.RunLog(
            timestamp: "t", input: "q",
            chosenIntent: "Create", chosenTone: "Concise", chosenDomain: "Work",
            assembledPrompt: "p", context: [:]
        )
        XCTAssertFalse(core.logRun(run),
                       "logRun must report failure on unwritable storage")
    }

    /// Control: the same seam pointed at a writable temp root succeeds — proves
    /// the failure above is caused by permissions, not by the override itself.
    func testWritableOverrideSucceeds() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CSOK_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let core = SynapseCore(folderName: "CS_\(UUID().uuidString)",
                               user: "u",
                               baseOverride: root)

        XCTAssertTrue(core.saveWeights(core.defaultWeights()),
                      "a writable override must persist successfully")
    }
}
