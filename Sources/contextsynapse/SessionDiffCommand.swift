import Foundation
import SynapseCore

/// Executes before SynapseCore initialization: reading logs creates no app state.
enum SessionDiffCommand {
    static func run(_ args: [String]) -> Int32 {
        guard args.count == 4, args[1] == "--session-diff",
              !args[2].hasPrefix("--"), !args[3].hasPrefix("--") else {
            fputs("Usage: contextsynapse --session-diff <before-run.json> <after-run.json>\n", stderr)
            return 2
        }
        do {
            let decoder = JSONDecoder()
            let before = try decoder.decode(SynapseCore.RunLog.self,
                from: Data(contentsOf: URL(fileURLWithPath: args[2])))
            let after = try decoder.decode(SynapseCore.RunLog.self,
                from: Data(contentsOf: URL(fileURLWithPath: args[3])))
            print(try SessionDiff(before: before, after: after).formatted)
            return 0
        } catch {
            fputs("Cannot compare run logs: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
