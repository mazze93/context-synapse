import Foundation

// MARK: - LighthouseStore
// Lighthouse persistence, promoted from the CLI into SynapseCore so the GUI
// and tests can reach it (CLAUDE.md P3). The record keeps `setAt` because the
// drift clock shown to the user (minutes since the lighthouse was set) belongs
// to the LIGHTHOUSE, not to the ephemeral per-query synapse.
//
// ADR-001 still governs: lighthouses are set on confirmed user choice only.

public struct LighthouseRecord: Codable, Equatable {
    public let id: String
    public let text: String
    public let fileReferences: [String]
    public let functionNames: [String]
    /// ISO-8601 timestamp of when the lighthouse was set (kept as String for
    /// on-disk compatibility with records written by the pre-0.4 CLI).
    public let setAt: String

    public init(id: String, text: String, fileReferences: [String] = [],
                functionNames: [String] = [], setAt: String) {
        self.id = id
        self.text = text
        self.fileReferences = fileReferences
        self.functionNames = functionNames
        self.setAt = setAt
    }

    public var setAtDate: Date? {
        ISO8601DateFormatter().date(from: setAt)
    }

    public var content: SynapseContent {
        SynapseContent(id: id, text: text, fileReferences: fileReferences,
                       functionNames: functionNames,
                       createdAt: setAtDate ?? Date())
    }
}

extension SynapseCore {

    /// Canonical location: alongside config.json in the user dir
    /// (`…/ContextSynapse/users/<user>/lighthouse.json`).
    public var lighthouseURL: URL {
        configURL.deletingLastPathComponent().appendingPathComponent("lighthouse.json")
    }

    /// Legacy location written by the pre-0.4 CLI
    /// (`…/ContextSynapse/<user>/lighthouse.json` — note: outside users/).
    /// Read-only fallback; saves always go to the canonical path.
    var legacyLighthouseURL: URL {
        appSupport.appendingPathComponent(currentUser).appendingPathComponent("lighthouse.json")
    }

    @discardableResult
    public func saveLighthouse(_ content: SynapseContent, at date: Date = Date()) -> Bool {
        let record = LighthouseRecord(
            id: content.id,
            text: content.text,
            fileReferences: content.fileReferences,
            functionNames: content.functionNames,
            setAt: ISO8601DateFormatter().string(from: date)
        )
        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: lighthouseURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Load the active lighthouse record, migrating transparently from the
    /// legacy CLI path when only that copy exists.
    public func loadLighthouseRecord() -> LighthouseRecord? {
        for url in [lighthouseURL, legacyLighthouseURL] {
            if let data = try? Data(contentsOf: url),
               let record = try? JSONDecoder().decode(LighthouseRecord.self, from: data) {
                if url == legacyLighthouseURL {
                    // one-time migration to the canonical path; legacy copy removed
                    try? data.write(to: lighthouseURL, options: .atomic)
                    try? fm.removeItem(at: url)
                }
                return record
            }
        }
        return nil
    }

    public func clearLighthouse() {
        try? fm.removeItem(at: lighthouseURL)
        try? fm.removeItem(at: legacyLighthouseURL)
    }
}

// MARK: - BreadcrumbWriter
// On lighthouse load, emit a re-sync line before the prompt (CLAUDE.md P1):
//   ⚓ Lighthouse: [text] — saliency [X]% — last touched [N]min ago
// Also appended to logs/breadcrumb-<iso>.txt for later archaeology.

public enum BreadcrumbWriter {

    public static func breadcrumbLine(for record: LighthouseRecord,
                                      rotScore: Double,
                                      at now: Date = Date()) -> String {
        let saliencyPct = Int((max(0.0, min(1.0, 1.0 - rotScore)) * 100).rounded())
        let minutes = record.setAtDate.map { Int(now.timeIntervalSince($0) / 60) } ?? 0
        return "⚓ Lighthouse: \(record.text) — saliency \(saliencyPct)% — last touched \(minutes)min ago"
    }

    /// Print the breadcrumb to stdout and append it to the core's log dir.
    public static func emit(for record: LighthouseRecord,
                            rotScore: Double,
                            core: SynapseCore,
                            at now: Date = Date()) {
        let line = breadcrumbLine(for: record, rotScore: rotScore, at: now)
        print(line)
        let iso = ISO8601DateFormatter().string(from: now)
        let file = core.logDir.appendingPathComponent("breadcrumb-\(iso).txt")
        try? (line + "\n").data(using: .utf8)?.write(to: file, options: .atomic)
    }
}
