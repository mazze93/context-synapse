import Foundation

/// CLI context selection. Weights/referee configuration remain shared; each
/// explicit anchor has a separate lighthouse and session history. A single
/// atomic index write switches selection; original primary files stay intact.
public final class ShadowContextStore {
    private struct Index: Codable {
        var primary = "primary"
        var shadow: String?
        var contexts: [String] = []
        var priorPrimaries: [String] = []
        var cleared: [String] = []
    }
    public enum ContextError: LocalizedError {
        case corruptIndex, missingAnchor, alreadyShadow, notShadow, invalidLabel, shadowAnchorRequired
        public var errorDescription: String? {
            switch self {
            case .corruptIndex: return "Context index is invalid; restore it from backup before continuing."
            case .missingAnchor: return "Set an explicit primary lighthouse before forking."
            case .alreadyShadow: return "Return to the primary before starting another shadow context."
            case .notShadow: return "No shadow context is active."
            case .shadowAnchorRequired: return "Return to the primary before clearing a shadow anchor."
            case .invalidLabel: return "A shadow goal must contain 1–500 non-control characters."
            }
        }
    }
    private let core: SynapseCore
    private let root: URL
    private let indexURL: URL
    private var index: Index
    public var activeID: String { index.shadow ?? index.primary }
    public var isShadow: Bool { index.shadow != nil }
    public var priorPrimaryIDs: [String] { index.priorPrimaries }

    public init(core: SynapseCore) throws {
        self.core = core
        root = core.configURL.deletingLastPathComponent()
        indexURL = root.appendingPathComponent("contexts.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
            } catch { throw ContextError.corruptIndex }
            func valid(_ id: String) -> Bool { id == "primary" || UUID(uuidString: id) != nil }
            guard valid(index.primary), index.shadow.map(valid) ?? true,
                  index.contexts.allSatisfy({ UUID(uuidString: $0) != nil }),
                  index.priorPrimaries.allSatisfy(valid),
                  index.cleared.allSatisfy({ index.contexts.contains($0) }),
                  index.primary == "primary" || index.contexts.contains(index.primary),
                  index.shadow.map({ index.contexts.contains($0) && $0 != index.primary }) ?? true else {
                throw ContextError.corruptIndex
            }
        } else { index = Index() }
        // Fail closed rather than quietly switching anchors when selected data
        // is missing or malformed. Original primary may legitimately have none.
        if activeID != "primary" {
            _ = try loadLighthouse()
            if FileManager.default.fileExists(atPath: sessionURL.path) {
                _ = try JSONDecoder().decode(SessionState.self, from: Data(contentsOf: sessionURL))
            }
        }
    }

    private func directory(_ id: String) -> URL {
        id == "primary" ? root : root.appendingPathComponent("contexts").appendingPathComponent(id)
    }
    public var sessionURL: URL { directory(activeID).appendingPathComponent("session.json") }

    public func loadLighthouse() throws -> LighthouseRecord? {
        if index.cleared.contains(activeID) { return nil }
        if activeID == "primary" { return core.loadLighthouseRecord() }
        let url = directory(activeID).appendingPathComponent("lighthouse.json")
        return try JSONDecoder().decode(LighthouseRecord.self, from: Data(contentsOf: url))
    }

    public func saveLighthouse(_ content: SynapseContent, at now: Date = Date()) throws {
        if activeID == "primary" {
            guard core.saveLighthouse(content, at: now) else { throw CocoaError(.fileWriteUnknown) }
        } else {
            let record = LighthouseRecord(id: content.id, text: content.text,
                fileReferences: content.fileReferences, functionNames: content.functionNames,
                setAt: ISO8601DateFormatter().string(from: now))
            try JSONEncoder().encode(record).write(to: directory(activeID).appendingPathComponent("lighthouse.json"), options: .atomic)
            if index.cleared.contains(activeID) {
                var next = index; next.cleared.removeAll { $0 == activeID }
                try commit(next)
            }
        }
    }

    public func clearLighthouse() throws {
        // An active shadow must retain a defined anchor. Returning first is an
        // explicit action, and the primary clear follows existing CLI behavior.
        guard !isShadow else { throw ContextError.shadowAnchorRequired }
        if activeID == "primary" { core.clearLighthouse() }
        else {
            var next = index
            if !next.cleared.contains(activeID) { next.cleared.append(activeID) }
            try commit(next) // retain the old anchor file as recovery evidence
        }
    }

    @discardableResult
    public func fork(goal: String, at now: Date = Date()) throws -> String {
        guard !isShadow else { throw ContextError.alreadyShadow }
        let label = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 500,
              label.rangeOfCharacter(from: .controlCharacters) == nil else { throw ContextError.invalidLabel }
        guard try loadLighthouse() != nil else { throw ContextError.missingAnchor }
        let id = UUID().uuidString
        let folder = directory(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let anchor = LighthouseRecord(id: UUID().uuidString, text: label,
            setAt: ISO8601DateFormatter().string(from: now))
        try JSONEncoder().encode(anchor).write(to: folder.appendingPathComponent("lighthouse.json"), options: .atomic)
        let session = SessionState(startedAt: now, lighthouseID: anchor.id)
        try JSONEncoder().encode(session).write(to: folder.appendingPathComponent("session.json"), options: .atomic)
        var next = index
        next.contexts.append(id)
        next.shadow = id
        try commit(next)
        return id
    }

    public func returnToPrimary() throws {
        guard isShadow else { throw ContextError.notShadow }
        // Verify the destination before selecting it.
        if index.primary != "primary" {
            _ = try JSONDecoder().decode(LighthouseRecord.self, from: Data(contentsOf:
                directory(index.primary).appendingPathComponent("lighthouse.json")))
        }
        var next = index; next.shadow = nil
        try commit(next)
    }

    public func promoteShadow() throws {
        guard let shadow = index.shadow else { throw ContextError.notShadow }
        _ = try loadLighthouse()
        var next = index
        next.priorPrimaries.append(index.primary)
        next.primary = shadow
        next.shadow = nil
        try commit(next)
    }

    private func commit(_ next: Index) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(next).write(to: indexURL, options: .atomic)
        index = next
    }
}
