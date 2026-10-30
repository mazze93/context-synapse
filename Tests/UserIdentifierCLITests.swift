import XCTest
import Foundation

final class UserIdentifierCLITests: XCTestCase {
    func testInvalidUserExitsNormallyWithoutCreatingState() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let executable = repository.appendingPathComponent(".build/debug/contextsynapse")
        // Fail rather than skip: build the CLI before running integration tests.
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        for arguments in [["--user", "🔥"], ["--user", "***"], ["--user", "../Ada"], ["--user", ""], ["--user"], ["--user", "--export"]] {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = repository
            var environment = ProcessInfo.processInfo.environment
            environment["HOME"] = home.path
            environment["CFFIXED_USER_HOME"] = home.path
            process.environment = environment
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationReason, .exit, arguments.description)
            XCTAssertEqual(process.terminationStatus, 2, arguments.description)
            XCTAssertTrue(error.contains("--user"), error)
            XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/ContextSynapse").path))
        }
    }
}
