// MARK: - FoundationModelsClient.swift
// ContextSynapse — on-device AI client (opt-in library extension)
//
// Bridges Apple's on-device FoundationModels LLM (macOS 26+) to the existing
// AIClient protocol, alongside OpenAIClient / AnthropicClient. Unlike those,
// this client makes NO network call and needs NO API key — inference runs on
// the Neural Engine / GPU. It is the purest fit for ContextSynapse's
// local-first thesis: nothing leaves the device.
//
// Availability, two layers:
//   1. #if canImport(FoundationModels) — the framework ships only in the
//      macOS 26+ SDK. On older SDKs (incl. the macos-15 CI runner) this whole
//      file compiles out, so the package still builds; the type simply does
//      not exist there.
//   2. @available(macOS 26, *) — even with the SDK present, the symbols are
//      only callable at runtime on macOS 26+. The package deploys to macOS 13,
//      so every use of the framework sits behind an availability guard and
//      sendPrompt fails cleanly on older systems.
//
// This is opt-in: like OpenAIClient/AnthropicClient it is a library type, not
// wired into the CLI. Local-first remains non-negotiable — no required network.

#if canImport(FoundationModels)

import Foundation
import FoundationModels

/// On-device AI client backed by Apple's FoundationModels system model.
/// Conforms to `AIClient`, so it is a drop-in for the network clients while
/// keeping every token on the device.
public final class FoundationModelsClient: AIClient {

    /// Optional system-level instructions applied to each session (a persona /
    /// task frame). `nil` uses the bare model.
    private let instructions: String?

    public init(instructions: String? = nil) {
        self.instructions = instructions
    }

    /// Whether the on-device model is ready to serve requests *right now*.
    /// `false` when the OS is < macOS 26, Apple Intelligence is disabled, the
    /// device is unsupported, or the model assets are still downloading.
    /// Callers can gate UX on this without paying for a full inference.
    public static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// A human-readable reason the model is unavailable, or `nil` if available.
    public static var unavailabilityReason: String? {
        guard #available(macOS 26.0, *) else {
            return "FoundationModels requires macOS 26 or later"
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return "on-device model unavailable: \(String(describing: reason))"
        }
    }

    /// Send a prompt to the on-device model. Bridges the framework's async API
    /// onto the completion-based `AIClient` contract. Fails (rather than blocks
    /// or crashes) when the model is unavailable.
    public func sendPrompt(_ prompt: String,
                           completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard #available(macOS 26.0, *) else {
            completion(.failure(Self.error("FoundationModels requires macOS 26 or later")))
            return
        }
        let instructions = self.instructions
        // Explicit @Sendable so the region-based isolation checker takes the
        // Sendable path; all captures (prompt, instructions, completion) are
        // Sendable value types / @Sendable closures.
        Task { @Sendable in
            do {
                let text = try await Self.respond(to: prompt, instructions: instructions)
                completion(.success(text))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Identity & provenance

    /// Default prompt used by `benchmark(...)` — short, fixed, and neutral so
    /// runs are comparable over time. (Latency, not output, is the measurement;
    /// LLM output is not deterministic.)
    public static let defaultBenchmarkPrompt = "In one sentence, describe a lighthouse."

    /// A plain-JSON record of exactly what this client runs and where it derives
    /// inference. No inference is performed — safe to call any time, including
    /// when the model is unavailable.
    public func provenance() -> AIProvenanceRecord {
        var languages: [String] = []
        if #available(macOS 26.0, *) {
            languages = SystemLanguageModel.default.supportedLanguages
                .map(\.minimalIdentifier)
                .sorted()
        }
        return AIProvenanceRecord(
            framework: "FoundationModels",
            modelIdentity: "Apple on-device system language model (SystemLanguageModel.default)",
            execution: .onDevice,
            available: Self.isAvailable,
            unavailabilityReason: Self.unavailabilityReason,
            supportedLanguages: languages
        )
    }

    /// Run a repeatable latency benchmark: `iterations` fresh inferences of a
    /// fixed prompt, each timed with the monotonic clock. Returns a Codable
    /// report (per-run latencies + summary stats + provenance) so results are
    /// durable and comparable across machines. Throws if the model is
    /// unavailable rather than reporting meaningless zeros.
    @available(macOS 26.0, *)
    public func benchmark(prompt: String = FoundationModelsClient.defaultBenchmarkPrompt,
                          iterations: Int = 5,
                          label: String = "foundationmodels-latency") async throws -> AIBenchmarkReport {
        guard case .available = SystemLanguageModel.default.availability else {
            throw Self.error(Self.unavailabilityReason ?? "on-device model unavailable")
        }
        let runs = max(1, iterations)
        var latencies: [Double] = []
        latencies.reserveCapacity(runs)
        for _ in 0..<runs {
            // Fresh session per run: no accumulated context skewing the timing.
            let session = instructions.map { LanguageModelSession(instructions: $0) }
                ?? LanguageModelSession()
            let start = DispatchTime.now()
            _ = try await session.respond(to: prompt)
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            latencies.append(Double(elapsedNs) / 1_000_000.0)
        }
        return AIBenchmarkReport(label: label, prompt: prompt,
                                 latenciesMs: latencies, provenance: provenance())
    }

    // MARK: - Private

    @available(macOS 26.0, *)
    private static func respond(to prompt: String, instructions: String?) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            throw error(unavailabilityReason ?? "on-device model unavailable")
        }
        let session = instructions.map { LanguageModelSession(instructions: $0) }
            ?? LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }

    private static func error(_ message: String) -> Error {
        NSError(domain: "FoundationModels", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

#endif
