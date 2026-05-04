# ContextSynapse — Agent Context

Local-first Bayesian context engine. Treats context as a living system: it decays, rots, and forgets on purpose. Status: **experimental/research-grade**.

## Stack
- **Language**: Swift 6.0+, macOS 13+
- **Build**: `swift build -c release` | **Test**: `swift test --parallel`
- **Persistence**: JSON in `~/Library/Application Support/ContextSynapse/`
- **Dependencies**: None (Swift stdlib + Foundation only)

## Repository Layout

```
Sources/SynapseCore/
  SynapseCore.swift          # Bayesian engine (priors, triggers, regions, AI clients)
  DecayConstants.swift       # All constants — single source of truth
  SynapseContent.swift       # Immutable synapse content descriptor
  InteractionRecord.swift    # Event classification + successWeight mapping
  SemanticDistanceStrategy.swift
  SynapseWeightState.swift   # Decay math, rot score, lighthouse floor
  SynapseReferee.swift       # FunctionalReferee, AbrasiveReferee, RefereeConfig
Sources/contextsynapse/main.swift   # CLI entry point
Sources/ContextSynapseApp/          # SwiftUI macOS GUI
Tests/
  BayesianConvergenceTests.swift
  SynapseWeightStateTests.swift
  SynapseRefereeTests.swift
  SemanticDistanceTests.swift
```

## Core Types (v0.3)

| Type | File | Role |
|------|------|------|
| `SynapseCore` | SynapseCore.swift | Bayesian engine: priors, triggers, regions |
| `Weights`, `Prior`, `Priors` | SynapseCore.swift | Bayesian state |
| `Region` | SynapseCore.swift | Named cosine-similarity vector |
| `DecayConstants` | DecayConstants.swift | λ, μ, rot thresholds, lighthouse floor |
| `SynapseContent` | SynapseContent.swift | Immutable content descriptor |
| `InteractionEventType` | InteractionRecord.swift | 7 event types with successWeight |
| `InteractionRecord` | InteractionRecord.swift | Timestamped interaction event |
| `SemanticDistanceStrategy` | SemanticDistanceStrategy.swift | Distance protocol |
| `StructuralHeuristicDistance` | SemanticDistanceStrategy.swift | File/function overlap (Option A) |
| `SynapseWeightState` | SynapseWeightState.swift | Per-synapse decay, rot, lighthouse |
| `SessionContext` | SynapseWeightState.swift | Session-level shared state |
| `SynapseReferee` | SynapseReferee.swift | Protocol |
| `FunctionalReferee` | SynapseReferee.swift | Silent default |
| `AbrasiveReferee` | SynapseReferee.swift | Active friction (opt-in) |
| `ContextIntervention` | SynapseReferee.swift | UI-surfaced data report + choices |
| `RefereeConfig` | SynapseReferee.swift | Persisted mode + thresholds |

## Key Formulas

- **Decay**: `W_decay = W_base · e^(-λ·t) · U(s,t)`
- **Utility**: `U(s,t) = Σ successᵢ·e^(-μΔt) / Σ e^(-μΔt)`
- **Rot**: `RotScore = D(s,lh) · tanh(T_drift/T_threshold) · VelocityAmp`
- **Final**: `W_final = max(floor, W_decay · (1 - α·RotScore))`
- **Lighthouse floor**: 0.4 always — enforced as hard invariant

## Architecture Decision Records

| ADR | Decision | Status |
|-----|----------|--------|
| ADR-001 | Affect vector updates are ASYNC — consent-first, no passive inference | Decided |
| ADR-002 | Operational context layer is permanently OUT OF SCOPE | Permanent boundary |
| ADR-003 | AbrasiveReferee is opt-in (`referee.mode = "abrasive"`) | Decided |
| ADR-004 | Observability is local-only — no cloud dependency added | Decided |

## Design Rules

- **Local-first is non-negotiable** — no required cloud dependency
- **Interpretability first** — all weights/priors/constants visible in plain JSON
- **Fragility is intentional** — do not "fix" fault injection
- **Consent-first** — no passive inference of user state (ADR-001, ADR-002)
- **`DecayConstants` is the single source of truth** — never scatter magic numbers
- **`SemanticDistanceStrategy` is a protocol** — swap distance implementations without touching rot formula
- **AbrasiveReferee activates on distraction, not collapse** (ADR-002 is a hard boundary)

## Hard Invariants

- Lighthouse `finalWeight` ≥ 0.4 at all times (all t, all sessions)
- `requiresCauterization` iff `rotScore` ≥ 0.82
- Lighthouse `rotScore` is always 0.0
- Distance output always in [0.0, 1.0]; symmetric

## CLI Flags

`--user`, `--app`, `--focus`, `--time`, `--intent`, `--tone`, `--domain`, `--feedback good|bad`, `--fault-prob`, `--export`, `--import [--merge]`, `--metadata key=value`

## Repo

- GitHub: [mazze93/context-synapse](https://github.com/mazze93/context-synapse)
- Default branch: `main`
