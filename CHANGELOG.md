# Changelog

All notable changes to Context Synapse are recorded here. The format loosely
follows [Keep a Changelog](https://keepachangelog.com/). The project is pre-1.0
and the API is not frozen — breaking changes are possible between minor versions.

This file supersedes the earlier `IMPROVEMENTS.md` and `REVIEW.md` snapshots,
whose still-accurate content has been folded in below.

## [Unreleased] — v0.3.0-decay

### Added
- **Decay layer** (`SynapseWeightState`): per-synapse decay math, rot scoring,
  lighthouse floor, and cauterization.
- **`InteractionRecord` / `InteractionEventType`**: timestamped event
  classification with success-weight mapping. `SynapseContent` and the
  `DecayConstants` single-source-of-truth live in the same file.
- **`SemanticDistanceStrategy`** protocol with the shipped
  `StructuralHeuristicDistance` (Jaccard overlap over file/function references,
  whitespace-token fallback).
- **Referee layer** (`SynapseReferee`): `FunctionalReferee` (default, silent) and
  opt-in `AbrasiveReferee`, plus `ContextIntervention` and `RefereeConfig`.
- **Edgar** (`RavenRenderer`): an ANSI raven state machine that renders the
  system's rot state on every CLI query, with a four-choice cauterize intervention.
- **Bedrock circuit** (`SynapticCircuit` actor): Beta-distributed `SynapticPrior`,
  bidirectional prediction-error propagation, earned lighthouse floor, and the
  `FaultInjectionSuite` calibration harness. (#12)

### Fixed
- CLI export prints a `Successfully exported state to: <file>` confirmation again,
  restoring symmetry with import and fixing the
  `testExportAndImportAcceptUserFlagBeforeCommandFlag` integration test. (#14)

## [v0.2.0] — Bayesian Scaffold

### Added
- Bayesian feedback with Beta priors for intents/tones/domains. Priors persist in
  `Weights.priors` and map to numeric weights in the range `[0.1, 3.0]`.
- Contextual **trigger system** (active app, time-of-day, focus mode) applying
  multiplicative boosts.
- Intentional **fault injection** (`faultProbability`, `maybeInjectFaults`) for
  resilience testing.
- Cosine similarity tolerant of mismatched vector lengths (shared-prefix fallback).
- Export / import of full state as a versioned `ExportBundle`.
- Multi-user profile support.
- CLI (`contextsynapse`) and SwiftUI app (`ContextSynapseApp`).

### Security & hardening
- User-ID sanitization at the `SynapseCore` init boundary (strips `/`, `\`, `:`,
  `.`) to prevent directory-traversal attacks.
- Empty-string validation for intent/tone/domain feedback parameters.
- HTTP 200 validation and a configured `URLSession` (30s timeout, no response
  caching) in the optional `OpenAIClient` / `AnthropicClient` adapters.
- Removed force-unwraps in prior updates in favor of safe optional handling.
- Shared HTTP logic extracted into a single `BaseHTTPAIClient`.
- Disk writes use atomic options; failures are logged to stderr via `logError`
  rather than failing silently.

[Unreleased]: https://github.com/mazze93/context-synapse/commits/main
