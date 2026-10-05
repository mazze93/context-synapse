// MARK: - AIProvenance.swift
// ContextSynapse — identity, provenance, and benchmark records for AI work.
//
// Interpretability-first (a core ContextSynapse design rule): every piece of AI
// inference the system does should leave a plain-JSON record of *what* ran,
// *where* it derived inference, and *how it performed* — nothing hidden. These
// types are deliberately generic (on-device or network) and dependency-free, so
// any AIClient can attach them. FoundationModelsClient is the first adopter.
//
// This file is NOT gated on canImport(FoundationModels): the records must exist
// on every platform, including the macos-15 CI runner.
//
// PRIVACY / CONTAINMENT: these records carry a host fingerprint (chip, device
// model, memory, OS build). They are on-device artifacts. The only sanctioned
// sink is SynapseCore.recordAIBenchmark, which writes under Application Support
// (outside the repo, never CI/remote). Do NOT print full records to stdout —
// CI captures stdout into public logs. AIProvenanceTests pins this invariant.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Where inference physically runs relative to the device.
public enum AIExecutionLocus: String, Codable, Sendable {
    case onDevice        // Neural Engine / GPU, no egress
    case privateCloud    // Apple Private Cloud Compute (opt-in, extends on-device guarantees)
    case network         // third-party API over the network
}

/// The host machine an inference ran on. Captured, not assumed.
public struct AIEnvironment: Codable, Sendable, Equatable {
    public let osVersion: String
    public let chip: String?
    public let deviceModel: String?
    public let physicalMemoryBytes: UInt64

    public init(osVersion: String, chip: String?, deviceModel: String?, physicalMemoryBytes: UInt64) {
        self.osVersion = osVersion
        self.chip = chip
        self.deviceModel = deviceModel
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    /// Snapshot the current host. `chip`/`deviceModel` come from sysctl and are
    /// `nil` if the query fails rather than being faked.
    public static func current() -> AIEnvironment {
        AIEnvironment(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            chip: sysctlString("machdep.cpu.brand_string"),
            deviceModel: sysctlString("hw.model"),
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    /// Read a sysctl string by name; `nil` on any failure.
    static func sysctlString(_ name: String) -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }
}

/// Identity + provenance of a model at a point in time. Answers: what is
/// running, where does it derive inference, is it available, on what host.
public struct AIProvenanceRecord: Codable, Sendable, Equatable {
    /// Framework serving the model, e.g. "FoundationModels", "OpenAI".
    public let framework: String
    /// Best available identity of the model. Apple's on-device model exposes no
    /// version string, so this names the kind, not a fabricated version.
    public let modelIdentity: String
    /// Where inference runs.
    public let execution: AIExecutionLocus
    /// Convenience: true iff inference leaves the device.
    public var leavesDevice: Bool { execution == .network }
    /// Whether the model can serve a request right now.
    public let available: Bool
    /// Why it can't, if `available == false`.
    public let unavailabilityReason: String?
    /// BCP-47 language tags the model supports, sorted; empty if unknown.
    public let supportedLanguages: [String]
    /// Host machine.
    public let environment: AIEnvironment
    /// ISO-8601 capture time.
    public let capturedAt: String

    public init(framework: String,
                modelIdentity: String,
                execution: AIExecutionLocus,
                available: Bool,
                unavailabilityReason: String?,
                supportedLanguages: [String],
                environment: AIEnvironment = .current(),
                capturedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.framework = framework
        self.modelIdentity = modelIdentity
        self.execution = execution
        self.available = available
        self.unavailabilityReason = unavailabilityReason
        self.supportedLanguages = supportedLanguages
        self.environment = environment
        self.capturedAt = capturedAt
    }
}

/// Repeatable latency benchmark for an AI model. Carries the provenance of what
/// was measured so results are comparable across runs and machines.
public struct AIBenchmarkReport: Codable, Sendable, Equatable {
    public let label: String
    public let prompt: String
    public let iterations: Int
    /// Per-run wall-clock latencies in milliseconds, in run order.
    public let latenciesMs: [Double]
    public let meanMs: Double
    public let medianMs: Double
    public let minMs: Double
    public let maxMs: Double
    public let p90Ms: Double
    public let provenance: AIProvenanceRecord
    public let capturedAt: String

    /// Build a report from raw latency samples, computing summary statistics.
    public init(label: String,
                prompt: String,
                latenciesMs: [Double],
                provenance: AIProvenanceRecord,
                capturedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.label = label
        self.prompt = prompt
        self.iterations = latenciesMs.count
        self.latenciesMs = latenciesMs
        self.provenance = provenance
        self.capturedAt = capturedAt

        let sorted = latenciesMs.sorted()
        if sorted.isEmpty {
            self.meanMs = 0; self.medianMs = 0; self.minMs = 0; self.maxMs = 0; self.p90Ms = 0
        } else {
            self.meanMs = sorted.reduce(0, +) / Double(sorted.count)
            self.minMs = sorted.first!
            self.maxMs = sorted.last!
            let mid = sorted.count / 2
            self.medianMs = sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
            // Nearest-rank p90: index ceil(0.9·n) − 1, clamped.
            let rank = Int((0.9 * Double(sorted.count)).rounded(.up))
            self.p90Ms = sorted[min(max(rank - 1, 0), sorted.count - 1)]
        }
    }

    /// Pretty JSON, for writing a durable record next to run logs.
    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }
}
