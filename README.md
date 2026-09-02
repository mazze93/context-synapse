# Context Synapse

![Swift](https://img.shields.io/badge/Swift-5.8%2B-orange)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Status](https://img.shields.io/badge/status-v0.3--experimental-yellow)
![License](https://img.shields.io/badge/license-MIT-lightgrey)
![Local-First](https://img.shields.io/badge/architecture-local--first-success)
![No Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

**Context Synapse is a local-first macOS system for modeling, retrieving, and
inspecting contextual weight across AI-assisted work.**

Most systems treat AI context as either a flat history buffer or an opaque vector
store. Context Synapse treats it as a belief system: weights that decay with time
and disuse, priors that update when observations contradict predictions, anchors
that hold stable only when earned. The goal is a context layer that can learn from
surprise — not one that merely accumulates or discards.

All state is plain JSON. Nothing leaves your machine.

## Status

**v0.3.0-decay — experimental/research-grade.** Maintained by one person. The
core Bayesian architecture is stable; the API is not frozen before v1.0. See
[Known Issues](#known-issues) and [ROADMAP.md](ROADMAP.md) before building
integrations on top of this.

## The core problem

A static `W_base(s)` constant can forget (via decay) but cannot revise beliefs
about which synapses are actually useful based on whether predictions were correct.
Prior to v0.3, Context Synapse had this flaw by design. The Bayesian label was
aspirational: no prior update mechanism existed; no prediction error was computed
or used as a learning signal.

v0.3 fixed that. v0.4 hardened it.

## Quick start

```bash
git clone https://github.com/mazze93/context-synapse.git
cd context-synapse
swift build -c release
.build/release/contextsynapse "Draft a status update"
```

See [INSTALL.md](INSTALL.md) for prerequisites, optional system-wide install,
GUI setup, and troubleshooting.

## How it works

Context Synapse manages named **synapses** — weighted connections between semantic
regions (intent, tone, domain). A synapse's relevance decays over time and disuse;
it is reinforced when interaction outcomes confirm its utility; it is penalized
when they do not.

The decay formula:

```
W_decay(s, t) = prior.mean(s) · e^(−λ(s,t) · Δt) · U(s, t)

λ(s, t) = λ_base
         · (1 − connectivity_factor(s))
         · rot_multiplier(s)
         · (1 + predictionError(s) · 1.2)
```

`W_base(s)` is no longer a constant. It is the **mean of a Beta-distributed
prior** (`α`, `β`) that updates conjugately from observed interaction outcomes.
The Beta distribution is bounded `[0,1]`, conjugate to Bernoulli observations, and
transparent: `α + β` directly encodes how much evidence the prior carries.

The **SynapticCircuit** actor implements this:

- **Forward pass** — generates predictions from priors, computes
  `connectivity_factor` from circuit edge topology, returns `ForwardPassResult`.
- **Backward pass** — records observations, computes `|predicted − observed|` as
  prediction error, updates priors, propagates uncertainty through edges.
- **Lighthouse floor** — per ADR-003, the minimum weight for a lighthouse synapse
  is `prior.mean × 0.4`. The floor is earned from evidence, not granted at
  initialization.
- **Fault injection** — `FaultInjectionSuite` runs controlled adversity against
  nodes, measures propagation depth, and returns a `CalibrationReport` that can
  update `CircuitConstants.errorDecayAmplifier` empirically.

## CLI usage

```bash
# Basic — stochastic intent/tone/domain from current weights
contextsynapse "your query"

# Force specific dimensions
contextsynapse "your query" --intent Create --tone Technical --domain Work

# Apply feedback (shifts priors toward this session's choices)
contextsynapse "your query" --feedback good
contextsynapse "your query" --feedback bad

# Contextual triggers
contextsynapse "your query" --app Mail --focus DoNotDisturb --time 09:00

# Multi-user namespaces
contextsynapse "your query" --user alice

# Export / import state
contextsynapse --export snapshot.json --metadata project=myapp
contextsynapse --import snapshot.json           # replace state
contextsynapse --import snapshot.json --merge   # average priors

# Fault injection (resilience research)
CONTEXT_SYNAPSE_FAULT_PROB=0.4 contextsynapse "test query"
```

ContextSynapse holds Beta-distribution priors for three dimensions:

| Dimension | Defaults |
|-----------|---------|
| Intents | Summarize, Create, Analyze, Brainstorm, ActionableSteps |
| Tones | Concise, Technical, Casual, Persuasive, Creative |
| Domains | Work, Personal, GameDesign, Marketing, Writing |

Time bucketing: `05:00–11:59` → `time.morning`, `12:00–16:59` →
`time.afternoon`, otherwise `time.evening`.

## Programmatic usage

```swift
import SynapseCore

let core = SynapseCore(user: "default")
let weights = core.loadOrCreateDefaultWeights()

// Stochastic assembly
let tone   = core.weightedPick(weights.tones)   ?? "Concise"
let intent = core.weightedPick(weights.intents) ?? "Summarize"
let domain = core.weightedPick(weights.domains) ?? "Work"
let prompt = core.assemblePrompt(tone: tone, intent: intent, domain: domain, query: "Explain this")

// Feedback update
core.applyFeedbackUpdate(chosenIntent: intent, chosenTone: tone, chosenDomain: domain, positive: true)

// Region similarity (NxN cosine matrix)
let regions = core.loadOrSeedRegions()
let (matrix, nearest) = core.computeRegionSimilarities(regionsIn: regions)
```

`SynapseCore` is a pure Swift library with no external dependencies. The optional
`OpenAIClient` and `AnthropicClient` are HTTP adapters that send an assembled
prompt to those chat-completion APIs; the CLI and GUI do not require them.

## Architecture

```
SynapseCore (library — no external deps)
├── Bayesian engine      — Beta priors, feedback update, weight interpolation [0.1, 3.0]
├── Trigger system       — app / time / focus context boosters (multiplicative)
├── Region similarity    — cosine NxN matrix, nearest-neighbour map, fault injection
├── SynapticCircuit      — forward/backward pass, dynamic lighthouse floor, fault calibration
├── Decay layer (v0.3)   — SynapseWeightState: rot score, lighthouse floor, cauterization
├── Referee (v0.3)       — FunctionalReferee / AbrasiveReferee context interventions
├── Export / Import      — full state as ExportBundle JSON (versioned)
└── AI clients           — optional OpenAI + Anthropic adapters; FoundationModelsClient (macOS 26+)

contextsynapse (CLI)     — thin argument parser, stdin support, all flags above
ContextSynapseApp (GUI)  — SwiftUI: weight grid sliders, cosine heatmap, feedback UI
```

## Design invariants

These are not aspirational — each has a corresponding ADR, test, or enforcement
mechanism:

| Invariant | Enforcement |
|-----------|------------|
| Affect is asynchronous — lighthouse anchors set on confirmed user choice only, never via inference | ADR-001; `SynapseWeightState.swift` |
| Operational context is permanently out of scope — the Referee models distraction, not cognitive collapse | ADR-002; `SynapseReferee.swift` |
| The lighthouse floor is earned, not granted — stability derives from prior evidence | ADR-003; `lighthouseFloor` = `prior.mean × 0.4` |
| Prediction error drives decay rate — surprise is first-class; EMA smoothing was rejected | ADR-004; `λ` formula |
| Local-first — AI provenance records persist to Application Support only, never stdout, CI, or repo | `AIProvenanceTests.testBenchmarkRecordsStayOnDeviceNotInRepo` |
| stdout is machine-readable only — drift events route to stderr | `CircuitDriftSinkTests`; injectable sink |
| Single-writer assumption — concurrent writes can collide; file locking tracked for v1.0 | Documented at persistence boundary; `saveWeights` doc comment |
| Decisions are append-only and enforced — deletion fails CI, rotation passes | `scripts/ops/check_journal_append.sh` |

## On-device AI (macOS 26+)

`FoundationModelsClient` wraps Apple's on-device `FoundationModels` framework.
It is double-guarded: `#if canImport(FoundationModels)` compiles it out on CI
(macOS 15); `@available(macOS 26)` gates runtime use. Benchmarks produce
`AIProvenanceRecord` and `AIBenchmarkReport` objects carrying a host fingerprint
(chip, model, memory, OS version) that persist on-device only.

Public CI logs are a fingerprint leak channel. The architecture was designed
around this constraint from the start. `AIProvenanceTests
.testBenchmarkRecordsStayOnDeviceNotInRepo` verifies the containment boundary
portably across all build environments.

## Threat model (circuit layer)

Documented threats against the SynapticCircuit layer and their mitigations:

| Threat | Description | Mitigation |
|--------|-------------|------------|
| T1 Prior poisoning | Adversarial observations inflate weak-synapse priors | Learning-rate decay; evidence-weight cap at 100 |
| T2 Error flooding | High-frequency all-zero backward passes collapse priors | Minimum alpha floor (1.0); backward pass ordering guard |
| T3 Lighthouse ossification | Lighthouse floors calcify, blocking revision | Earned-not-granted floor derivation (ADR-003) |
| T4 Timing side-channel | Decay rates reveal interaction patterns | Documented; mitigation tracked for v1.0 |
| T5 Schema drift | Prior values mis-calibrate after `canonicalVector()` regeneration | Schema version hash in `CircuitSnapshot` |

## Testing

```bash
swift build              # required for CLI-integration tests
swift test --parallel
```

A passing test only proves what it reaches. Untested perimeters are documented
explicitly — not silently assumed closed. All tests run in UUID-isolated
directories; no shared state.

| Suite | Coverage focus |
|-------|---------------|
| `BayesianConvergenceTests` | Prior convergence, cosine similarity, fault injection, region similarity, export/import round-trips, weight correctness |
| `SynapticCircuitTests` | Forward/backward pass, circuit topology, lighthouse floors, prediction error propagation |
| `DecayWeightTests` | Decay formula parameters, λ modulation |
| `PriorGrowthTests` | Mean-preserving renormalization cap — α+β bounded, ratio preserved |
| `PersistenceFailureTests` | Real `EACCES` on atomic write → `save*` returns `false`; guarded against root (see ADR-005) |
| `CircuitDriftSinkTests` | Injectable drift sink; stdout confirmed clean |
| `LighthouseStoreTests` | Lighthouse record retrieval and floor derivation |
| `RunTelemetryTests` | Per-run telemetry isolation |
| `AIProvenanceTests` | On-device containment; host fingerprint never reaches stdout or repo |
| `FoundationModelsClientTests` | macOS 26+ availability guard behavior |
| `SynapseManagerTests` | End-to-end manager orchestration |

See ADR-005 for the GUI write-failure verification strategy and its explicit
three-link chain (disk-I/O → `false`, `false` → `lastError`, `lastError` →
banner render). Each link has a documented status: verified, deferred, or
inherent perimeter.

## Known issues

| Issue | Severity | Target |
|-------|----------|--------|
| Multi-process write collision (no file lock — see single-writer note above) | Low | v1.0 |
| `AppViewModel` in executable target — ViewModel reflection test deferred until library target move | Low | v1.0 |
| Circuit drift branch (`drift > 0.1`) unreachable via public API under shipped `etaBase` | Tech debt | v0.4 |
| `SynapseCore.swift` ~900-line monolith split | Design debt | v1.0 |

See [ROADMAP.md](ROADMAP.md) for the full version plan, architecture decision
log, and v0.4–v1.0 milestones.

## Documentation

| Document | Purpose |
|----------|---------|
| [INSTALL.md](INSTALL.md) | Build prerequisites, CLI and GUI setup |
| [CONTEXT-SYNAPSE-OPS-MANUAL](docs/) | Full operational reference (PGP-signed) |
| [docs/adr/](docs/adr/) | Architecture Decision Records — two tracks: ethics/consent (A) and circuit math (B) |
| [ROADMAP.md](ROADMAP.md) | Version plan and milestone log |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [DECISIONS.md](DECISIONS.md) | Append-only decision journal |
| [LESSONS.md](LESSONS.md) | Distilled, portable takeaways |
| [SECURITY.md](SECURITY.md) | Vulnerability disclosure and artifact verification |
| [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) | Pre-release verification protocol |

## Maintenance posture

- **Maintainer:** [@mazze93](https://github.com/mazze93) — solo project
- **Response time:** best-effort; no SLA
- **Breaking changes:** possible until v1.0; pin to a tag if building integrations
- **Security:** report vulnerabilities privately via [GitHub Security Advisories](https://github.com/mazze93/context-synapse/security/advisories) — see [SECURITY.md](SECURITY.md) for full disclosure policy and artifact verification
- **Contributing:** PRs welcome. Fork → branch → tests → PR. Architectural changes need a discussion issue first — this is a HITL (Human-in-the-Loop) research project

## License

MIT — see [LICENSE](LICENSE).

---

*Context Synapse is what AI and neurodivergent intelligence have in common: both are brilliant, distracted, and prone to losing the forest for the trees. This is the bridge.*
