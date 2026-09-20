// MARK: - RecordCommand.swift
// Context Synapse CLI — the event producer verbs.
//
// DECLARATIONS ONLY. main.swift owns all top-level statements; a second file
// in an executable target must contain no top-level code or the build breaks.
//
// Verbs:
//   --record <event-type>   append one observation to the ledger
//   --export-events <file>  write the ledger to CSV
//   --events-summary        print counts by event type
//
// The record verb is deliberately dumb: validate, append, exit. It performs
// no circuit work, holds no locks, and cannot fail in a way that corrupts
// state. A git hook calls it on every commit; it must never be the reason a
// commit feels slow or a session breaks.
//
// Decision ref: docs/adr/ADR-006-ledger-separation.md

import Foundation
import SynapseCore

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RecordCommand
// ─────────────────────────────────────────────────────────────────────────────

public enum RecordCommand {

    /// Exit codes are contractual — the git hook branches on them.
    public enum ExitCode: Int32 {
        case ok             = 0
        case usage          = 2
        case unknownEvent   = 3
        case ledgerFailure  = 4
    }

    // ── Argument extraction ──────────────────────────────────────────────────

    /// Return the value following `flag`, or nil if absent/valueless.
    /// Matches main.swift's existing positional-scan convention.
    public static func value(for flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        let candidate = args[idx + 1]
        // A value beginning with "--" means the flag was supplied without an argument.
        return candidate.hasPrefix("--") ? nil : candidate
    }

    // ── Validation ───────────────────────────────────────────────────────────

    /// Reject synapse IDs that could traverse directories or break CSV/JSONL.
    /// The ID is user-supplied and ends up in a file, so it is untrusted input.
    public static func sanitizeSynapseID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        // Defense in depth: no path traversal even though the ID never becomes a path.
        guard !trimmed.contains("..") else { return nil }
        return trimmed
    }

    /// Accept an explicit ISO-8601 timestamp, else stamp now.
    /// The hook passes the commit time so a replayed or delayed hook stays truthful.
    public static func resolveTimestamp(_ raw: String?) -> String {
        let formatter = ISO8601DateFormatter()
        if let raw, formatter.date(from: raw) != nil { return raw }
        return formatter.string(from: Date())
    }

    // ── Verb: --record ───────────────────────────────────────────────────────

    /// Handle `--record <event>`. Returns the process exit code.
    public static func handleRecord(args: [String], ledgerDirectory: URL) -> ExitCode {
        guard let eventRaw = value(for: "--record", in: args) else {
            printRecordUsage()
            return .usage
        }
        guard let eventType = InteractionEventType(rawValue: eventRaw) else {
            let valid = InteractionEventType.allCases.map(\.rawValue).joined(separator: ", ")
            FileHandle.standardError.write(
                Data("Error: unknown event '\(eventRaw)'. Valid: \(valid)\n".utf8))
            return .unknownEvent
        }

        let synapseRaw = value(for: "--synapse", in: args) ?? "default"
        guard let synapseId = sanitizeSynapseID(synapseRaw) else {
            FileHandle.standardError.write(
                Data("Error: --synapse must be 1-128 chars of [A-Za-z0-9-_.:]\n".utf8))
            return .usage
        }

        // repoToken is expected pre-hashed by the producer. Enforce the shape so a
        // raw path can never be silently accepted: hex only, bounded length.
        var repoToken = value(for: "--repo-token", in: args)
        if let token = repoToken {
            let isHex = !token.isEmpty && token.count <= 64
                && token.allSatisfy { $0.isHexDigit }
            if !isHex {
                FileHandle.standardError.write(
                    Data("Error: --repo-token must be hex (pre-hashed). Refusing raw identifier.\n".utf8))
                return .usage
            }
            repoToken = token.lowercased()
        }

        let changedFileCount = value(for: "--changed-files", in: args).flatMap(Int.init)
        let source = value(for: "--source", in: args) ?? "cli"
        let timestamp = resolveTimestamp(value(for: "--at", in: args))

        let event = LedgerEvent(
            timestamp: timestamp,
            event: eventType.rawValue,
            successWeight: eventType.successWeight,
            synapseId: synapseId,
            repoToken: repoToken,
            changedFileCount: changedFileCount,
            source: source
        )

        do {
            let ledger = try EventLedger(directory: ledgerDirectory)
            try ledger.append(event)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            return .ledgerFailure
        }

        // Quiet by default: a git hook should not spam the terminal on every commit.
        if args.contains("--verbose") {
            print("recorded \(eventType.rawValue) (w=\(eventType.successWeight)) → \(synapseId)")
        }
        return .ok
    }

    // ── Verb: --export-events ────────────────────────────────────────────────

    public static func handleExportEvents(args: [String], ledgerDirectory: URL) -> ExitCode {
        guard let outPath = value(for: "--export-events", in: args) else {
            FileHandle.standardError.write(
                Data("Usage: contextsynapse --export-events <output.csv> [--user <id>]\n".utf8))
            return .usage
        }
        do {
            let ledger = try EventLedger(directory: ledgerDirectory)
            let (events, skipped) = ledger.readAll()
            guard ledger.exportCSV(to: URL(fileURLWithPath: outPath)) else {
                FileHandle.standardError.write(Data("Error: failed to write \(outPath)\n".utf8))
                return .ledgerFailure
            }
            print("Exported \(events.count) events to: \(outPath)")
            if skipped > 0 {
                print("Warning: skipped \(skipped) malformed ledger line(s)")
            }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            return .ledgerFailure
        }
        return .ok
    }

    // ── Verb: --events-summary ───────────────────────────────────────────────

    public static func handleEventsSummary(ledgerDirectory: URL) -> ExitCode {
        do {
            let ledger = try EventLedger(directory: ledgerDirectory)
            let (events, skipped) = ledger.readAll()
            guard !events.isEmpty else {
                print("Ledger is empty. Nothing has been observed yet.")
                print("Path: \(ledger.fileURL.path)")
                return .ok
            }

            var counts: [String: Int] = [:]
            for e in events { counts[e.event, default: 0] += 1 }

            print("Ledger: \(ledger.fileURL.path)")
            print("Events: \(events.count)   First: \(events.first?.timestamp ?? "-")   Last: \(events.last?.timestamp ?? "-")")
            print("")
            for key in counts.keys.sorted() {
                let weight = InteractionEventType(rawValue: key)?.successWeight ?? 0
                let count = counts[key] ?? 0
                let padded = key.padding(toLength: max(key.count, 22), withPad: " ", startingAt: 0)
                print("  \(padded) \(count)   w=\(String(format: "%.2f", weight))")
            }
            let distinct = Set(events.map(\.synapseId)).count
            print("")
            print("Distinct synapses: \(distinct)")
            if skipped > 0 { print("Malformed lines skipped: \(skipped)") }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            return .ledgerFailure
        }
        return .ok
    }

    // ── Usage ────────────────────────────────────────────────────────────────

    public static func printRecordUsage() {
        let valid = InteractionEventType.allCases.map(\.rawValue).joined(separator: "\n    ")
        FileHandle.standardError.write(Data("""
        Usage: contextsynapse --record <event-type> [options]

        Options:
          --synapse <id>        attribution target (default: "default")
          --repo-token <hex>    pre-hashed repo identifier (hex only)
          --changed-files <n>   count of changed files (never names)
          --at <iso8601>        event time (default: now)
          --source <name>       producer name (default: "cli")
          --verbose             print confirmation

        Event types:
            \(valid)

        """.utf8))
    }
}
