# Context Synapse

![Swift](https://img.shields.io/badge/Swift-5.8%2B-orange)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Status](https://img.shields.io/badge/status-v0.3--experimental-yellow)
![License](https://img.shields.io/badge/license-MIT-lightgrey)
![Local-First](https://img.shields.io/badge/architecture-local--first-success)
![No Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

A local-first Bayesian prompt engine for macOS. Give it a query; it picks an intent, tone, and domain from weights shaped by your feedback and context signals. All state is plain JSON. Nothing leaves your machine.

Built for neurodivergent developers who need structured, adaptive prompting without cloud lock-in or opaque heuristics.

## Status

**v0.3.0-decay — experimental/research-grade.** Maintained by one person. The core Bayesian architecture is stable; the API is not frozen before v1.0. See [Known Issues](#known-issues) and [ROADMAP.md](ROADMAP.md) before building integrations on top of this.

## What it does

```bash
contextsynapse "Summarize this document"
# → [Concise] [Summarize] [Work]: Summarize this document
```

ContextSynapse holds Beta-distribution priors for three dimensions:

| Dimension | Defaults |
|-----------|---------|
| Intents | Summarize, Create, Analyze, Brainstorm, ActionableSteps |
| Tones | Concise, Technical, Casual, Persuasive, Creative |
| Domains | Work, Personal, GameDesign, Marketing, Writing |

Each run it:
1. Applies **contextual triggers** — active app, time-of-day, focus mode — to boost relevant dimensions.
2. Picks stochastically from weighted distributions, assembles `[Tone] [Intent] [Domain]: query`.
3. On `--feedback good|bad`, updates the Beta priors so the next session reflects what worked.

All weights and priors live in `~/Library/Application Support/ContextSynapse/users/default/config.json` — a plain JSON file you can read, edit, or reset at any time.

## Quick start

### Prerequisites

- macOS 13 (Ventura) or later
- Swift 5.8+ (ships with Xcode 15+, or install the Swift toolchain standalone)

```bash
git clone https://github.com/mazze93/context-synapse.git
cd context-synapse
swift build -c release
.build/release/contextsynapse "Draft a status update"
```

See [INSTALL.md](INSTALL.md) for the full build guide, optional system-wide install, GUI app setup, and troubleshooting.

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

Time bucketing: `05:00–11:59` → `time.morning`, `12:00–16:59` → `time.afternoon`, otherwise `time.evening`.

## Bayesian learning

`--feedback good` increments `alpha` on the chosen intent, tone, and domain; `--feedback bad` increments `beta`. `Prior.probability() = alpha / (alpha + beta)` climbs for dimensions you reinforce. Weights are linearly mapped to `[0.1, 3.0]` and persisted after every update.

After a few sessions of consistent feedback, preferred dimensions appear more often. You can inspect or hand-edit the JSON at any time — the format is intentionally human-readable.

## Programmatic usage

```swift
import SynapseCore

let core = SynapseCore(user: "default")

// Stochastic assembly
let tone   = core.weightedPick(core.weights.tones)   ?? "Concise"
let intent = core.weightedPick(core.weights.intents) ?? "Summarize"
let domain = core.weightedPick(core.weights.domains) ?? "Work"
let prompt = core.assemblePrompt(tone: tone, intent: intent, domain: domain, query: "Explain this")

// Feedback update
core.applyFeedbackUpdate(chosenIntent: intent, chosenTone: tone, chosenDomain: domain, positive: true)

// Region similarity (NxN cosine matrix)
let regions = core.loadOrSeedRegions()
let (matrix, nearest) = core.computeRegionSimilarities(regionsIn: regions)
```

`SynapseCore` is a pure Swift library with no external dependencies. The optional `OpenAIClient` and `AnthropicClient` are HTTP adapters for embedders; the CLI and GUI do not require them.

## Architecture

```
SynapseCore (library — no external deps)
├── Bayesian engine      — Beta priors, feedback update, weight interpolation [0.1, 3.0]
├── Trigger system       — app / time / focus context boosters (multiplicative)
├── Region similarity    — cosine NxN matrix, nearest-neighbour map, fault injection
├── Decay layer (v0.3)   — SynapseWeightState: rot score, lighthouse floor, cauterization
├── Referee (v0.3)       — FunctionalReferee / AbrasiveReferee context interventions
├── Export / Import      — full state as ExportBundle JSON (versioned)
└── AI clients           — optional OpenAI + Anthropic adapters (not wired to CLI)

contextsynapse (CLI)     — thin argument parser, stdin support, all flags above
ContextSynapseApp (GUI)  — SwiftUI: weight grid sliders, cosine heatmap, feedback UI
```

## Design principles

| Principle | In practice |
|-----------|------------|
| Context is probabilistic | Intent, tone, and domain are inferred from Bayesian priors — not hard-coded rules |
| Interpretability is non-negotiable | Every weight, prior, and similarity score is human-readable JSON — nothing is hidden |
| Fragility is intentional | `CONTEXT_SYNAPSE_FAULT_PROB` corrupts region vectors to test how the system degrades gracefully |
| Local-first, always | No required network calls; cloud AI clients are opt-in library extensions only |
| Prompting as cognition | The assembled prompt encodes intent + environment + history, not just string concatenation |

## Testing

```bash
swift build              # required for CLI-integration tests
swift test --parallel
```

The suite (`BayesianConvergenceTests`) covers Bayesian convergence, cosine similarity, fault injection, region similarity, export/import round-trips, and weight correctness. Each test runs in a unique UUID folder — no shared state.

## Known issues

| Issue | Severity | Target |
|-------|----------|--------|
| Silent write failures (no UI error surface in GUI) | Medium | v1.0 |
| Unbounded prior growth (alpha/beta accumulate indefinitely) | Low | v1.0 |
| Multi-process write collision (no file lock; single-writer assumed) | Low | v1.0 |

See [ROADMAP.md](ROADMAP.md) for the full version plan, architecture decision log, and v0.4–v1.0 milestones.

## Maintenance posture

- **Maintainer**: [@mazze93](https://github.com/mazze93) — solo project
- **Response time**: best-effort; no SLA
- **Breaking changes**: possible until v1.0; pin to a tag if you are building integrations
- **Security**: report vulnerabilities privately via [GitHub Security Advisories](https://github.com/mazze93/context-synapse/security/advisories) — see [SECURITY.md](SECURITY.md) for full disclosure policy and artifact verification
- **Contributing**: PRs welcome. Fork → branch → tests → PR. Architectural changes need a discussion issue first — this is a HITL (Human-in-the-Loop) research project

## License

MIT — see [LICENSE](LICENSE).

---

*Context Synapse is what AI and neurodivergent intelligence have in common: both are brilliant, distracted, and prone to losing the forest for the trees. This is the bridge.*
