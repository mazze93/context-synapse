import Foundation
import SynapseCore

enum ShadowContextCommand {
    static func prepare(args: [String], core: SynapseCore) throws -> ShadowContextStore {
        let store = try ShadowContextStore(core: core)
        let commands = ["--fork-shadow", "--return-primary", "--promote-shadow"]
        let supplied = commands.filter { args.contains($0) }
        guard supplied.count <= 1 else { throw CommandError.usage }
        if let command = supplied.first {
            // Management commands accept only their value and an optional user.
            var remaining = Array(args.dropFirst())
            if let user = remaining.firstIndex(of: "--user"), user + 1 < remaining.count {
                remaining.removeSubrange(user...user + 1)
            }
            if command == "--fork-shadow" {
                guard remaining.count == 2, remaining[0] == command,
                      !remaining[1].hasPrefix("--") else { throw CommandError.usage }
                let id = try store.fork(goal: remaining[1])
                print("Shadow context: \(id). Primary retained; return with --return-primary.")
            } else {
                guard remaining == [command] else { throw CommandError.usage }
                if command == "--return-primary" {
                    try store.returnToPrimary(); print("Returned to primary; shadow history retained.")
                } else {
                    try store.promoteShadow(); print("Shadow promoted to primary; previous primary files retained.")
                }
            }
            exit(0)
        }
        return store
    }
    enum CommandError: LocalizedError {
        case usage
        var errorDescription: String? {
            "Use one of --fork-shadow <goal>, --return-primary, or --promote-shadow, optionally with --user <id>."
        }
    }
}
