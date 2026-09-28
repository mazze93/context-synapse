// MARK: - EventLedger.swift
// Context Synapse — Instrument Layer: append-only interaction event ledger.
//
// WHY A LEDGER AND NOT A DIRECT CIRCUIT CALL
// ------------------------------------------
// The producer (git hook, editor watcher, manual CLI) must never block on,
// or be coupled to, the evolving SynapseManager/SynapticCircuit API. It
// appends an immutable record and exits. Circuit state is then a FOLD over
// this log — never a mutable field written from three directions.
//
// This also means: a producer bug can never corrupt circuit state, and the
// raw observation history survives any change to the decay math. If the
// decay constants are recalibrated, the ledger can be re-folded from zero.
//
// PRIVACY CONTRACT (see docs/DATA-CLASSIFICATION.md)
// -------------------------------------------------
// This type accepts ONLY pre-hashed or non-identifying fields. It performs
// no hashing itself: hashing happens in the producer (the git hook) so raw
// paths and commit messages never cross the process boundary. Any caller
// passing a raw path or message into `repoToken` is violating the contract.
//
// Design ref: CONTEXT-SYNAPSE-OPS-MANUAL §4.4, §10.2
// Decision ref: docs/adr/ADR-006-ledger-separation.md

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LedgerEvent
// One immutable observation. Serialized as a single JSON line.
// ─────────────────────────────────────────────────────────────────────────────

public struct LedgerEvent: Codable, Equatable, Sendable {
    /// Schema version. Bump on any field change; readers must tolerate older rows.
    public let schema: Int
    public let id: String
    /// ISO-8601 UTC timestamp of the observed event (not of the write).
    public let timestamp: String
    /// Raw value of InteractionEventType (e.g. "git.commit").
    public let event: String
    /// Cached successWeight, so the ledger stays readable if the table is retuned.
    /// The fold re-derives from `event` when reprocessing; this is for audit only.
    public let successWeight: Double
    /// Synapse this observation is attributed to. User-chosen label or repo token.
    public let synapseId: String
    /// Opaque, salted repo identifier. NEVER a path, URL, or name.
    public let repoToken: String?
    /// Count only — never the file names themselves.
    public let changedFileCount: Int?
    /// Which producer emitted this: "cli", "git-hook", "manual".
    public let source: String

    public static let currentSchema = 1

    public init(
        id: String = UUID().uuidString,
        timestamp: String,
        event: String,
        successWeight: Double,
        synapseId: String,
        repoToken: String? = nil,
        changedFileCount: Int? = nil,
        source: String
    ) {
        self.schema = LedgerEvent.currentSchema
        self.id = id
        self.timestamp = timestamp
        self.event = event
        self.successWeight = successWeight
        self.synapseId = synapseId
        self.repoToken = repoToken
        self.changedFileCount = changedFileCount
        self.source = source
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EventLedger
// Append-only JSONL file. One event per line.
//
// CONCURRENCY: appends seek to end and write a single line. POSIX guarantees
// atomicity for writes under PIPE_BUF (512 bytes minimum; 4096 on macOS). A
// LedgerEvent line is ~200 bytes, so concurrent git hooks across repos will
// not interleave. This sidesteps the known single-writer limitation for THIS
// file specifically; it does not change the config.json single-writer
// assumption documented in the Ops Manual.
// ─────────────────────────────────────────────────────────────────────────────

public final class EventLedger {
    public enum LedgerError: Error, CustomStringConvertible {
        case cannotCreateDirectory(String)
        case cannotOpenForAppend(String)
        case encodingFailed
        case lineTooLong(Int)

        public var description: String {
            switch self {
            case .cannotCreateDirectory(let p): return "Cannot create ledger directory: \(p)"
            case .cannotOpenForAppend(let p):   return "Cannot open ledger for append: \(p)"
            case .encodingFailed:               return "Failed to encode ledger event"
            case .lineTooLong(let n):
                return "Refusing to append \(n)-byte line; atomicity guarantee holds only under 4096 bytes"
            }
        }
    }

    /// Maximum line size for which the append atomicity guarantee holds.
    private static let maxAtomicLineBytes = 4096

    public let fileURL: URL

    /// - Parameter directory: normally SynapseCore's per-user directory
    ///   (i.e. `core.logDir.deletingLastPathComponent()`).
    public init(directory: URL, filename: String = "events.jsonl") throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            } catch {
                throw LedgerError.cannotCreateDirectory(directory.path)
            }
        }
        self.fileURL = directory.appendingPathComponent(filename)
    }

    // ── Append ───────────────────────────────────────────────────────────────

    /// Append one event. Atomic under the size guarantee documented above.
    public func append(_ event: LedgerEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(event) else {
            throw LedgerError.encodingFailed
        }
        data.append(0x0A)  // newline

        guard data.count <= EventLedger.maxAtomicLineBytes else {
            throw LedgerError.lineTooLong(data.count)
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil,
                          attributes: [.posixPermissions: 0o600])
        }

        guard let handle = FileHandle(forWritingAtPath: fileURL.path) else {
            throw LedgerError.cannotOpenForAppend(fileURL.path)
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    // ── Read ─────────────────────────────────────────────────────────────────

    /// Read every well-formed event. Malformed lines are skipped, not fatal:
    /// a corrupt line must never make the whole history unreadable.
    /// Returns events plus the count of skipped lines for honest reporting.
    public func readAll() -> (events: [LedgerEvent], skipped: Int) {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ([], 0)
        }
        let decoder = JSONDecoder()
        var events: [LedgerEvent] = []
        var skipped = 0

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(LedgerEvent.self, from: data)
            else {
                skipped += 1
                continue
            }
            events.append(event)
        }
        return (events, skipped)
    }

    public var eventCount: Int { readAll().events.count }

    // ── CSV Export ───────────────────────────────────────────────────────────

    /// Emit the ledger as CSV for analysis. This is the plot-ready artifact.
    @discardableResult
    public func exportCSV(to url: URL) -> Bool {
        let (events, _) = readAll()
        var lines = ["timestamp,event,success_weight,synapse_id,repo_token,changed_file_count,source"]

        for e in events {
            let fields = [
                e.timestamp,
                e.event,
                String(e.successWeight),
                e.synapseId,
                e.repoToken ?? "",
                e.changedFileCount.map(String.init) ?? "",
                e.source
            ].map(EventLedger.csvEscape)
            lines.append(fields.joined(separator: ","))
        }

        let payload = lines.joined(separator: "\n") + "\n"
        do {
            try payload.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Quote fields containing comma, quote, or newline; double any inner quotes.
    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
