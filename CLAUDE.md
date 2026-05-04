# ContextSynapse — Claude Context

Local-first Bayesian context engine. Treats context as a living system — it decays, rots, and forgets on purpose. Status: **experimental/research-grade**.

---

## Stack

| Concern | Detail |
|---------|--------|
| Language | Swift 6.0+, macOS 13+ |
| Build | `swift build -c release` |
| Test | `swift test --parallel` |
| CI | GitHub Actions (`macos-15` runner) |
| Persistence | JSON in `~/Library/Application Support/ContextSynapse/` |
| Dependencies | None (pure Swift stdlib + Foundation) |

---

## Repository Layout

```
Package.swift
default_config.json           # Canonical seed config (priors + referee config)
Resources/default_config.json # Bundled duplicate
scripts/demo_convergence.sh

Sources/
  SynapseCore/
    SynapseCore.swift          # Bayesian engine, AI clients, fault injection
    DecayConstants.swift       # All decay/rot/lighthouse constants — single source of truth
    SynapseContent.swift       # Immutable synapse content descriptor
    InteractionRecord.swift    # Event classification + successWeight mapping
    SemanticDistanceStrategy.swift  # Distance protocol + StructuralHeuristicDistance
    SynapseWeightState.swift   # Per-synapse decay math, rot score, lighthouse floor
    SynapseReferee.swift       # FunctionalReferee, AbrasiveReferee, RefereeConfig
  contextsynapse/
    main.swift                 # CLI entry point
  ContextSynapseApp/
    AppMain.swift
    ContentView.swift
    HeatmapView.swift
    WeightGridView.swift
    RegionModel.swift

Tests/
  BayesianConvergenceTests.swift
  SynapseWeightStateTests.swift  # Lighthouse floor, cauterization, decay convergence
  SynapseRefereeTests.swift      # Referee activation logic
  SemanticDistanceTests.swift    # Distance contract tests
```

---

## Package Targets

| Product | Type | Entry |
|---------|------|-------|
| `SynapseCore` | Library | `Sources/SynapseCore/` (multi-file) |
| `contextsynapse` | Executable (CLI) | `Sources/contextsynapse/main.swift` |
| `ContextSynapseApp` | Executable (SwiftUI GUI) | `Sources/ContextSynapseApp/AppMain.swift` |
| Test targets | XCTest | `Tests/*.swift` |

---

## Core Architecture

### v0.2 Layer — Bayesian Engine (`SynapseCore.swift`)

```
Weights
├── intents:  [String: Double]
├── tones:    [String: Double]
├── domains:  [String: Double]
├── triggers: [String: [String: Double]]
└── priors:   Priors
    ├── intents:  [String: Prior]  # Beta(alpha, beta)
    ├── tones:    [String: Prior]
    └── domains:  [String: Prior]

Prior { alpha, beta }            # probability() = alpha/(alpha+beta)
Region { name, vector }          # Named embedding vector for cosine similarity
ExportBundle                     # Full state snapshot
UserProfile                      # Per-user metadata
```

### v0.3 Layer — Decay + Rot + Lighthouse

```
DecayConstants                   # λ_base, μ, rotAlpha, lighthouseFloor, thresholds

SynapseContent                   # Immutable: id, text, fileReferences, functionNames

InteractionEventType             # git.commit | file.save | build.success | build.failure |
                                 # keystroke.burst | window.switch.away | manual.feedback
InteractionRecord                # timestamp, eventType, successWeight, synapseId

SemanticDistanceStrategy         # Protocol: distance(from:to:) → [0.0, 1.0]
StructuralHeuristicDistance      # Option A: file/function overlap + text Jaccard fallback

SynapseWeightState               # Per-synapse mutable state:
  isLighthouse: Bool             #   lighthouse floor protection
  interactions: [InteractionRecord]
  rotScore: Double               #   RotScore(s) = D × tanh(T_drift/T_threshold) × VelocityAmp
  requiresCauterization: Bool    #   true when rotScore >= 0.82

SessionContext                   # Session-level: lighthouse content, maxConnections, drift time

SynapseReferee (protocol)
FunctionalReferee                # Default: silent. Velocity 50% / Connectivity 30% / Decay 20%
AbrasiveReferee                  # Opt-in: kicks to 0.1 on rot+drift. Never activates on collapse.
ContextIntervention              # Emitted by AbrasiveReferee: data report + 4 choices, no lecture
RefereeConfig                    # mode, driftThresholdMinutes, rotThreshold, cooldown
RefereeMode                      # .functional | .abrasive
```

---

## Key Methods

### SynapseCore (v0.2)

| Method | Purpose |
|--------|---------|
| `loadOrCreateDefaultWeights()` | Read config.json or seed defaults |
| `saveWeights(_:)` | Atomic write |
| `applyFeedbackUpdate(chosenIntent:chosenTone:chosenDomain:positive:)` | Beta update + weight recompute |
| `applyTriggers(base:triggers:activeKeys:)` | Apply context booster multipliers |
| `weightedPick(_:)` | Stochastic weighted sampling |
| `assemblePrompt(tone:intent:domain:query:)` | `[Tone] [Intent] [Domain]: query` |
| `cosineSimilarity(_:_:)` | Shared-prefix tolerant |
| `computeRegionSimilarities(regionsIn:)` | NxN matrix + nearest-neighbor map |
| `maybeInjectFaults(into:)` | Stochastic vector corruption |
| `exportState(to:metadata:)` | Serialize ExportBundle |
| `importState(from:merge:)` | Replace or merge state |
| `logRun(_:)` | Write per-run JSON log |
| `listUsers()` | Enumerate user profiles |

### SynapseWeightState (v0.3)

| Method | Purpose |
|--------|---------|
| `record(_:)` | Append InteractionRecord, cap history |
| `utilityScore(at:)` | Recency-weighted average: Σ successᵢ·e^(-μΔt) / Σ e^(-μΔt) |
| `dynamicDecayConstant(maxConnections:)` | λ_base · (1 - connectivity) · rotMultiplier |
| `decayWeight(baseWeight:maxConnections:at:)` | W_base · e^(-λt) · U(s,t) |
| `recomputeRotScore(content:lighthouse:at:)` | D × tanh(drift/threshold) × VelocityAmp |
| `finalWeight(baseWeight:maxConnections:at:)` | max(floor, W_decay · (1 - α·RotScore)) |
| `cauterizedDecayConstant(maxConnections:)` | λ × 2.5 when requiresCauterization |
| `lighthouseNeedsResync(maxConnections:at:)` | true when 0.4 ≤ W_final < 0.6 |

### SynapseReferee (v0.3)

| Method | Purpose |
|--------|---------|
| `FunctionalReferee.evaluateSaliency(for:content:in:)` | Silent saliency score |
| `FunctionalReferee.shouldForkToShadowContext(state:)` | true when rotScore > 0.5 |
| `AbrasiveReferee.evaluateSaliency(for:content:in:)` | Kicks to 0.1 on rot+drift |
| `AbrasiveReferee.buildIntervention(...)` | Builds ContextIntervention for UI |
| `RefereeConfig.makeReferee(lighthouseSaliencyAtStart:)` | Factory from config |

---

## Architecture Decision Records

### ADR-001: Affect Vector — ASYNC
Lighthouse anchors on confirmed user choice only. Never passive inference. Consent model is non-negotiable.

### ADR-002: Operational Context Layer — PERMANENT BOUNDARY
The Referee does not model collapse. Only distraction. Surveillance risk + shame amplification make this permanently out of scope for any deployment context, especially Secure Pride.

### ADR-003: Referee Default — FUNCTIONAL
AbrasiveReferee is opt-in: `referee.mode = "abrasive"` in config. User preference noted but not made default. ADR-002 applies.

### ADR-004: Observability — LOCAL ONLY
RunLog extended with decay/rot snapshots. No cloud dependency added. CDL is complementary — not a dependency.

---

## Bayesian Update Flow

1. Query assembled stochastically (intent/tone/domain picked via `weightedPick`)
2. User provides `--feedback good|bad`
3. `applyFeedbackUpdate` increments `alpha` (positive) or `beta` (negative)
4. `updateWeightsFromPriors` maps `probability()` → [0.1, 3.0]
5. Converges over time toward preferred dimensions

---

## Decay + Rot Flow

1. Each user interaction → `SynapseWeightState.record(event)`
2. Periodic tick → `recomputeRotScore(content, lighthouse)`
3. `finalWeight()` applies floor (lighthouse) or rot penalty (non-lighthouse)
4. `SynapseReferee.evaluateSaliency()` combines velocity + connectivity + decay
5. AbrasiveReferee: if rot + drift > threshold → kick to 0.1 + emit ContextIntervention

---

## Hard Invariants (enforced by tests)

- Lighthouse `finalWeight` ≥ `DecayConstants.lighthouseFloor` (0.4) at all times
- `requiresCauterization` iff `rotScore` ≥ 0.82
- `cauterizedDecayConstant` = normal × 2.5 when flagged
- Lighthouse `rotScore` is always 0.0
- `StructuralHeuristicDistance.distance()` output always in [0.0, 1.0]
- Distance is symmetric: d(a,b) == d(b,a)

---

## Design Constraints (Non-Negotiable)

- **Local-first**: no required network calls
- **Interpretability**: all weights, priors, constants in plain JSON
- **Fragility is intentional**: do not "fix" fault injection
- **Consent-first**: no passive inference of user state (ADR-001, ADR-002)
- **Determinism**: stochastic paths are explicitly labeled
- **No external dependencies**: keep Package.swift dependency-free

---

## Coding Conventions

- Atomic writes (`options: .atomic`) for all persistence
- User input sanitized at `SynapseCore.init` boundary
- Errors to stderr; stdout reserved for machine-readable output
- Test isolation via unique `UUID().uuidString` folder names
- `DecayConstants` is the single source of truth — never scatter magic numbers
- `SemanticDistanceStrategy` is a protocol — swap implementations without touching rot formula

---

## Repo

- GitHub: [mazze93/context-synapse](https://github.com/mazze93/context-synapse)
- Default branch: `main`
- Releases triggered by `v*` tags on `main`
