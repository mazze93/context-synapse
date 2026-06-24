# AGENTS.md

Context for coding agents (Codex, Claude, and others) working in this repository.

**This file is a pointer.** The authoritative, detailed agent context lives in
[`CLAUDE.md`](CLAUDE.md) — read it before making changes. It carries the current
sprint state, full architecture map, build/test commands, and the
non-negotiable design constraints.

## Quick facts

- **Project:** Context Synapse — a local-first Bayesian prompt orchestration
  engine. Experimental / research-grade, not a consumer product.
- **Language / platform:** Swift 5.8+, macOS 13+. No external dependencies.
- **Targets:** `SynapseCore` (library), `contextsynapse` (CLI),
  `ContextSynapseApp` (SwiftUI app). Tests in `Tests/`.
- **Build:** `swift build -c release`
- **Test:** `swift build && swift test --parallel` — build first; some tests
  exec the CLI binary.
- **State:** plain JSON under `~/Library/Application Support/ContextSynapse/`.
- **Core types:** `SynapseCore`, `Weights`/`Priors`/`Prior`, `Region`,
  `SynapseWeightState`, `SynapticCircuit`. (There is no `ContextRegion` type —
  named embedding vectors are `Region`.)

## Non-negotiable design rules

- **Local-first:** no required network calls; the AI clients are opt-in.
- **Interpretability:** all weights, priors, and similarity scores are
  human-readable JSON — nothing hidden.
- **Fragility is intentional:** fault injection is a first-class feature, not a
  bug to fix.
- **No operational/affective-state modelling** (ADR-002, referee track) — a
  permanent design boundary, not a roadmap gap.

See [`ROADMAP.md`](ROADMAP.md) for the version plan, [`CHANGELOG.md`](CHANGELOG.md)
for history, and [`docs/adr/`](docs/adr/) for architecture decisions.
