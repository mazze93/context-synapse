# ContextSynapse — Claude Context

Local-first Bayesian prompt orchestration engine. Research-grade.
Not a consumer product — built by and for a neurodivergent developer exploring human-machine context negotiation.

---

## CURRENT STATE — START HERE

**Version:** v0.3 bedrock layer is **merged to `main`** (PR #12: SynapticCircuit
actor, CircuitTypes, FaultInjectionSuite, ADRs). Latest release tag is still
`v0.1.0` — no v0.3 tag has been cut. Docs rewrite (PR #11) and CodeRabbit test
generation (PR #13, added `Tests/SynapticCircuitTests.swift`) are also merged.
**Branch model:** all work on feature branches, PRs against `main`.

### Historical notes — resolved, do not reopen

- **`Prior` vs `SynapticPrior`:** the circuit-layer type was renamed
  `SynapticPrior` to avoid a module-level duplicate with `Prior`
  (`SynapseCore.swift:183`, serialized to disk — never rename or move it).
  The two types are intentionally separate; see Coding Conventions.
  Sanity check: `grep -rn "^public struct Prior" Sources/SynapseCore/` returns
  exactly one result.
- **assemblePrompt:** ROADMAP once flagged this HIGH/BUG. Verified correct —
  `main.swift:300` calls
  `core.assemblePrompt(tone: chosenTone, intent: chosenIntent, domain: chosenDomain, query: userQuery)`.

---

## Stack

| Concern | Detail |
|---------|--------|
| Language | Swift 5.8+, macOS 13+ only |
| Build | `swift build -c release` |
| Test | `swift build && swift test --parallel` — build first, some tests exec the CLI binary |
| CI | GitHub Actions (`macos-15` runner) — build authority for merges |
| Persistence | JSON files in `~/Library/Application Support/ContextSynapse/` (per-user: config, regions, lighthouse, referee, `session.json` epochs) |
| Dependencies | None (pure Swift stdlib + Foundation) |

---

## Repository Layout

```
Package.swift
default_config.json              # Canonical seed config (CI guardrails check requires this)
Resources/default_config.json   # Bundled duplicate
scripts/demo_convergence.sh      # Bayesian convergence demo

Sources/
  SynapseCore/                   # Library target — ALL .swift files in ALL subdirs auto-included by SPM
    SynapseCore.swift            # Core class, AI clients, persistence, Bayesian engine (~900 lines)
    SynapseWeightState.swift     # Per-synapse decay math, rot scoring, utility, lighthouse floor
    InteractionRecord.swift      # InteractionEventType, InteractionRecord, SynapseContent, DecayConstants
    SemanticDistanceStrategy.swift  # Protocol + StructuralHeuristicDistance (shipped), stubs for TFIDF/CoreML
    SynapseReferee.swift         # FunctionalReferee, AbrasiveReferee, ContextIntervention, RefereeConfig
    RavenRenderer.swift          # Edgar: RavenState enum, RavenRenderer, EdgarIntervention, ANSI palette
    SynapseManager.swift         # v0.4 session coordinator (actor): persistent synapse map,
                                 #   circuit lifecycle + backward pass, RSA epoch snapshots, RSARenderer
    Circuit/                     # Bedrock layer (PR #12)
      CircuitTypes.swift         # CircuitConstants, SynapticPrior, SynapticNode, CircuitEdge, output types
      SynapticCircuit.swift      # actor: forwardPass, backwardPass, lighthouseFloor, injectFault
    FaultInjection/
      FaultInjectionSuite.swift  # Calibration suite: runFullSuite, auditLighthouses, CalibrationReport

  contextsynapse/
    main.swift                   # CLI entry point, ~356 lines, full query/feedback/export/lighthouse flow

  ContextSynapseApp/
    AppMain.swift                # @main, AppViewModel (ObservableObject bridge to SynapseCore)
    ContentView.swift            # Two-pane: left (weights/query/fault controls), right (heatmap)
    HeatmapView.swift            # Canvas NxN cosine similarity visualization
    WeightGridView.swift         # Editable sliders per dimension
    RegionModel.swift            # Intentional duplicate of canonicalVector — extension separation
    AppShortcutsBridge.swift     # Stub for future App Intents / iOS

Tests/
  BayesianConvergenceTests.swift  # Bayesian engine + CLI-integration tests
  SynapticCircuitTests.swift      # Circuit/bedrock tests (added in PR #13)

docs/
  adr/
    ADR-002-bidirectional-prediction-error-propagation.md
    ADR-003-004-lighthouse-floor-and-decay-amplifier.md
    INTEGRATION.md               # Recipe for SynapseWeightState to consume ForwardPassResult
```

**Key SPM rule:** Adding a `.swift` file anywhere under `Sources/SynapseCore/` automatically includes it in the `SynapseCore` module. No `Package.swift` edit needed unless adding a new top-level target.

**Key test rule:** New test files go in `Tests/` as separate `.swift` files. Do not add to `BayesianConvergenceTests.swift` — add alongside it.

---

## Package Targets

| Product | Type | Path |
|---------|------|------|
| `SynapseCore` | Library | `Sources/SynapseCore/` |
| `contextsynapse` | Executable CLI | `Sources/contextsynapse/main.swift` |
| `ContextSynapseApp` | Executable SwiftUI | `Sources/ContextSynapseApp/AppMain.swift` |
| `BayesianConvergenceTests` | Test target | `Tests/` |

---

## Architecture — Full Map

### Layer 1: Persistence & Bayesian Weights (`SynapseCore.swift`)

The monolith. Owns all state I/O and the existing Beta-prior system for dimension weights.

Key public types:
- `Prior { alpha, beta; probability() -> Double }` — simple Beta wrapper. **Serialized to disk.** Do not rename, move, or add a `mean` computed property (conflicts with `SynapticPrior.mean`).
- `Priors { intents, tones, domains: [String: Prior] }` — groups the three weight dimensions
- `Weights { intents, tones, domains: [String: Double], triggers: [String: [String: Double]], priors: Priors }` — full persisted state
- `Region { name: String, vector: [Double] }` — named embedding vector for cosine similarity
- `ExportBundle` — full state snapshot for export/import
- `UserProfile` — per-user metadata in `users/<id>/profile.json`

Key methods on `SynapseCore`:
- `loadOrCreateDefaultWeights()` → reads `config.json` or seeds from `defaultWeights()`
- `saveWeights(_:)` → atomic write
- `applyFeedbackUpdate(chosenIntent:chosenTone:chosenDomain:positive:)` → bumps alpha or beta, calls `updateWeightsFromPriors`, saves
- `updateWeightsFromPriors(_:)` → maps `prior.probability()` linearly into `[0.1, 3.0]`
- `weightedPick(_:)` → stochastic weighted sampling
- `assemblePrompt(tone:intent:domain:query:)` → `"[Tone] [Intent] [Domain]: query"`
- `applyTriggers(base:triggers:activeKeys:)` → multiplicative trigger boosts
- `cosineSimilarity(_:_:)` → tolerates mismatched lengths (uses shared prefix)
- `computeRegionSimilarities(regionsIn:)` → NxN matrix + nearest-neighbour map; applies fault injection
- `maybeInjectFaults(into:)` → three corruption modes based on `faultProbability` env/flag
- `exportState(to:metadata:)` / `importState(from:merge:)` → JSON round-trip
- `logRun(_:)` → per-run JSON to `logs/run-<iso>.json`
- `listUsers()` / `switchUser(to:folderName:)` / `resetToFactoryDefaults()`

### Layer 2: Decay & Rot (`SynapseWeightState.swift`)

Per-synapse mutable weight state. Currently instantiated **per-query** in the CLI.
`SynapseManager` (v0.4 target) will own session-level persistence.

Core math:
```
U(s,t)       = Σ successᵢ · e^(−μ(t−tᵢ)) / Σ e^(−μ(t−tᵢ))      utility score
λ(s)         = λ_base · (1 − connFactor) · (1 + rot·rotAmplifier)  decay constant
W_decay(s,t) = W_base · e^(−λ(s)·Δt) · U(s,t)
RotScore(s)  = D(content, lighthouse) · tanh(T_drift/T_threshold) · velocityAmplifier
W_final(s,t) = max(floor(s), W_decay · (1 − α·RotScore))
```

Invariants:
- Lighthouse synapses: `RotScore` always 0.0; `floor = DecayConstants.lighthouseFloor` (0.4)
- Cauterization: `requiresCauterization = true` when `rotScore >= 0.82`
- `lighthouseNeedsResync()` returns true when `0.4 ≤ W_final < 0.6`

All tunable constants live in `DecayConstants` enum in `InteractionRecord.swift`. Change them there only.

After PR #12 is integrated, `W_base` and `connFactor` will be sourced from `SynapticCircuit.forwardPass()` — see `docs/adr/INTEGRATION.md` for the exact wiring.

### Layer 3: Events & Constants (`InteractionRecord.swift`)

- `InteractionEventType` → `successWeight`: `gitCommit(1.0)`, `fileSave(0.9)`, `buildSuccess(0.85)`, `buildFailure(0.2)`, `keystrokeBurst(0.1)`, `windowSwitchAway(0.0)`, `manualFeedback(0.75)`
- `SynapseContent { id, text, fileReferences, functionNames, createdAt }` — content descriptor passed to rot computation
- `DecayConstants` enum — single source of truth for all tunable decay/rot values

### Layer 4: Referee (`SynapseReferee.swift`)

- `FunctionalReferee` (default): saliency = velocity×0.5 + connectivity×0.3 + decayWeight×0.2. Silent — never surfaces to user unless an intervention is explicitly constructed.
- `AbrasiveReferee` (opt-in via `referee.mode = "abrasive"` in config.json): drops saliency to 0.1 when `rotScore >= 0.3` AND `timeSinceLighthouse >= 15min` AND not in cooldown. 15-minute cooldown prevents spam. **Only activates on distraction, not cognitive collapse — ADR-002 is permanent.**
- `ContextIntervention` — data passed to `EdgarIntervention.render()` for the 4-choice interrupt UI
- `RefereeConfig` — persisted in `referee.json` via `RefereeConfigStorage.swift`; set with CLI `--referee functional|abrasive`

### Layer 5: Semantic Distance (`SemanticDistanceStrategy.swift`)

- `StructuralHeuristicDistance` (shipped, Option A): Jaccard overlap on fileReferences + functionNames, falls back to whitespace-tokenized text overlap. Fast, zero dependencies, correct for code sessions.
- `TFIDFCosineDistance` (stub, Option B, v1.0)
- `LocalEmbeddingDistance` (future, Option C, CoreML MiniLM)

### Layer 6: Bedrock Circuit (PR #12)

Replaces the static `W_base(s)` constant with a mutable Beta-distributed prior and adds bidirectional prediction-error propagation. **No existing files are modified.**

**`SynapticPrior`** (renamed from `Prior` to avoid module conflict):
- Rich Beta distribution: `mean`, `uncertainty`, `evidenceWeight`, `isOssified`
- `update(observation:eta:)` — conjugate Bayesian update with learning rate decay and alpha floor
- `widenUncertainty(by:)` — used during error propagation: adjacent nodes become less confident without their mean shifting
- Factory: `.uninformed` (α=β=1, mean=0.5) and `.lighthouse(confidence:)` (high mean, high evidence weight)

**`SynapticNode`**: maps 1:1 to a synapse via `synapseID` (foreign key into SynapseCore). Holds `prior: SynapticPrior`, `lastPrediction`, `lastObservation`, `predictionError`, `isEpistemicallyUnstable`.

**`CircuitEdge`**: directional edge (source→target) with `weight` and `propagationCoefficient`. Bidirectional coupling requires paired edges — this is intentional, not all relationships are symmetric.

**`SynapticCircuit` (actor)** — Swift 6.0 actor model, all mutable state actor-isolated, all outputs `Sendable`:
- `forwardPass()` → `ForwardPassResult { predictions[synapseID], connectivityFactors[synapseID] }` — replaces W_base(s) and connectivity_factor(s) in the decay formula
- `backwardPass(observations: [String: Double])` → `BackwardPassResult { predictionErrors, epistemicallyUnstableNodes }` — feeds Referee/Edgar instability detection
- `lighthouseFloor(for:isLighthouse:)` → `prior.mean × 0.4` — earned floor (ADR-003), not a hard constant
- `injectFault(intoSynapse:severity:liveMutation:)` → snapshot-first by default; `liveMutation: true` only for deliberate stress sessions

**Updated λ(s,t)** (integration recipe in `docs/adr/INTEGRATION.md`):
```swift
let lambda = lambdaBase
    * (1.0 - forwardResult.connectivityFactors[id] ?? 0.0)
    * rotMultiplier
    * (1.0 + circuit.predictionError(for: id) * CircuitConstants.errorDecayAmplifier)
```

**`FaultInjectionSuite`**: `runFullSuite()` (all nodes, mild+severe), `runTargetedSuite(synapseIDs:)`, `auditLighthouses(lighthouseIDs:)`. All produce `CalibrationReport` with `formattedSummary` and empirical recommendations for `ROT_LAMBDA_AMPLIFIER` and `ROT_CAUTERIZE_THRESHOLD`.

### Layer 7: Edgar (`RavenRenderer.swift`)

- `RavenState`: `dormant` (no lighthouse), `perched` (rot 0–0.25), `watching` (0.25–0.5), `stirring` (0.5–0.75), `alarmed` (0.75–0.82), `cauterize` (≥0.82), `resync`, `export`
- `RavenRenderer.render(state:frameIndex:lighthouseLabel:rotScore:)` — prints ASCII bird + rot bar + status line to stdout
- `EdgarIntervention.render(intervention:)` — 4-choice context rot UI: return / promote / continue / dismiss
- `ANSI` color constants: purple=dormant, cyan=perched, yellow=stirring, orange=alarmed, red/white=cauterize

### CLI (`main.swift`) — Complete Flow

```
1.  Pre-scan: find --user flag before any init
2.  SynapseCore(user: selectedUser)
3.  --lighthouse <text> → saveLighthouse + render .perched → exit(0)
    --resync            → clearLighthouse + render .resync → exit(0)
4.  --export <file>     → exportState + render .export → exit(0)
    --import <file>     → importState → exit(0)
5.  Parse flags: --app, --focus, --intent, --tone, --domain, --time, --feedback, --fault-prob
6.  Read query: positional arg || stdin
7.  applyTriggers → weightedPick intent/tone/domain (or use forced flags)
8.  core.loadLighthouseRecord → recomputeRotScore(driftReference: record.setAt)
    → RavenState.from(rotScore:lighthouseSet:)
    ⚠ the drift clock is the LIGHTHOUSE's, never the per-query synapse's —
    an ephemeral synapse measured against its own clock has tDrift ≈ 0 and
    can never rot (regression-pinned in Tests/DecayWeightTests.swift §4)
9.  core.assemblePrompt(tone: chosenTone, intent: chosenIntent, domain: chosenDomain, query: userQuery)
                                           ↑ verified correct, main.swift:300
10. print(finalPrompt) + blank line
11. RavenRenderer.render(state: edgarState, ...)
12. If edgarState == .cauterize: EdgarIntervention.render(...)
13. core.logRun(...)   — writes run-<iso>.json with context map
14. core.applyFeedbackUpdate(...) if --feedback good|bad|yes|no
```

Lighthouse state persists across invocations via `users/<user>/lighthouse.json`.
Persistence lives in `SynapseCore` (`LighthouseStore.swift`) — accessible to CLI,
GUI, and tests. The CLI also supports `--referee functional|abrasive` (persists
`referee.json`) and emits a breadcrumb re-sync line before the prompt whenever
a lighthouse is loaded.

---

## Sprint Backlog — Ordered by Priority

### P0 — DONE (PR #12 merged to main)

- [x] Rename `Prior` → `SynapticPrior` in `CircuitTypes.swift` — eliminates module-level duplicate type
- [x] Push fix to `claude/circuit-bedrock-v0.3`, confirm CI passes — merged
- [x] Strict concurrency enabled on `SynapseCore` target (`Package.swift`).
  Surfaced and fixed: `@Sendable` on AIClient closures, per-call
  `StandardErrorStream` instead of a shared mutable global.

### P1 — v0.3.0 remaining items — ALL DONE (branch `claude/v0.3-ci-repair-and-p1`)

- [x] **`Tests/DecayWeightTests.swift`** — floor invariant, cauterization
  threshold, decay monotonicity (+ lighthouse-never-rots, connectivity slows
  decay). Uses a deterministic `MaxDistanceStrategy` for the rot case.
- [x] **`Sources/SynapseCore/RunLogDecay.swift`** — `DecaySnapshot` round-trips
  through `RunLog.context` keys; old logs yield `nil` snapshots. `main.swift`
  now writes the typed snapshot instead of raw `rotScore` string.
- [x] **BreadcrumbWriter** — lives in `LighthouseStore.swift`; emits the
  re-sync line before the prompt and appends `logs/breadcrumb-<iso>.txt`.
- [x] **`Sources/SynapseCore/RefereeConfigStorage.swift`** — persisted in
  **`referee.json`**, not `config.json` (deliberate deviation: `saveWeights()`
  rewrites `config.json` wholesale and would clobber sibling keys). New CLI
  flag `--referee functional|abrasive` is the only way to opt into abrasive
  (ADR-002).

### P2 — Docs

- [x] **Merge PR #11** — merged; README/INSTALL now carry the real prerequisites and CLI flags.

### P3 — Architecture prep for v0.4

- [x] **`Sources/SynapseCore/SynapseManager.swift`** — DONE (v0.4). Actor owning the session-level synapse map (persisted to `session.json`), lighthouse designation, `SynapticCircuit` lifecycle, and backward-pass wiring per interaction (INTEGRATION.md recipe). Every observation snapshots an **RSA epoch**: an NxN similarity matrix over [lighthouse + tracked synapses] plus anchor saliency — render with `contextsynapse --rsa` (heatmap + saliency sparkline). The old Region/NxN machinery's role, repointed at real session data; the GUI heatmap remains a consumer candidate.
- [x] **Migrate lighthouse helpers from CLI to `SynapseCore`** — done:
  `LighthouseStore.swift` (`LighthouseRecord`, save/load/clear on `SynapseCore`).
  Canonical path `users/<user>/lighthouse.json`; legacy pre-0.4 CLI path
  migrates transparently on first load.

---

## Known Issues

| Issue | Severity | Target | Notes |
|-------|----------|--------|-------|
| ~~Silent write failures in GUI~~ | Fixed | — | `saveWeights`/`saveRegions`/`logRun` return `Bool`; `AppViewModel.lastError` + `ContentView` banner surface disk-I/O failures |
| ~~Unbounded prior growth~~ | Fixed | — | `Prior.renormalizeIfSaturated` caps `alpha+beta` at `Prior.maxEvidence` (200), mean-preserving; applied in `applyFeedbackUpdate` |
| Multi-process write collision | Low | v1.0 | No file lock; single-writer assumption now documented prominently (README + `saveWeights` doc comment). Enforcement (lock) still v1.0 |
| ~~`minutesInDrift` hardcoded to 15~~ | Fixed | — | Now computed from `LighthouseRecord.setAt` |
| `RegionModel.swift` duplicates `canonicalVector` | Intentional | — | Extension separation design; creates drift risk — keep in sync manually |
| `SynapseCore.swift` is a ~900-line monolith | Design debt | v1.0 | Split into focused files (BayesianEngine, SimilarityEngine, Persistence) once API is frozen |
| ~~`emitDriftEvent` in `SynapticCircuit` writes to stdout~~ | Fixed | — | Injectable `driftSink` at construction; default `stderrDriftSink` (off the machine-readable stdout channel) |

---

## Design Constraints (Non-Negotiable)

- **Local-first**: no required network calls; AI clients (`OpenAIClient`, `AnthropicClient`) are opt-in library extensions only
- **Interpretability**: all weights, priors, and similarity scores are plain JSON — nothing hidden
- **Fragility is intentional**: fault injection is a first-class feature — do not "fix" stochastic degradation behavior
- **No operational context layer**: the system does not model cognitive/affective collapse states. This is ADR-002. It is a permanent design boundary, not a roadmap gap.
- **Affect vector is consent-gated**: lighthouse anchors are set on confirmed user choice only, never via automatic inference (ADR-001)
- **Prompting as cognition**: `assemblePrompt` encodes intent + environment + history; it is not string concatenation

---

## Coding Conventions

- No external dependencies — `Package.swift` stays dependency-free
- Atomic writes (`options: .atomic`) for all state persistence
- User input sanitized at `SynapseCore.init` boundary (strips `/`, `\`, `:`, `.` from folder names)
- Errors → stderr (`StandardErrorStream`); stdout is machine-readable output only
- Tests use unique UUID folder names for isolation — never break this pattern, never share state between test cases
- All bedrock output types must be `Sendable` — they cross actor isolation boundaries
- Actor methods in `SynapticCircuit` that lack `async` in their signature are still implicitly async to callers outside the actor. This is correct Swift behavior, not a bug.
- The `SynapticPrior` type (circuit layer) and `Prior` type (weight layer) are intentionally separate. Do not unify them — they have different roles, different serialization contracts, and different update semantics.

---

## Build & Test

```bash
# Build all targets
swift build -c release

# IMPORTANT: build before test — CLI-integration tests exec .build/debug/contextsynapse
swift build
swift test --parallel

# Run with fault injection env variable
CONTEXT_SYNAPSE_FAULT_PROB=0.4 .build/debug/contextsynapse "test query"

# Verify SynapticPrior rename is clean (must return exactly 1 result)
grep -rn "^public struct Prior" Sources/SynapseCore/
```

The local machine (macOS, Swift toolchain present) can build and test directly;
CI on `macos-15` remains the build authority for merges. (An earlier version of
this file was written from a Linux container without a toolchain — no longer true.)

---

## CI / CD

**`ci.yml`** — `pull_request` and `push` to `main` (macos-15):
1. Required files: `.gitignore`, `Package.swift`, `README.md`, `SECURITY.md`, `INSTALL.md`, `LICENSE`, `default_config.json` — all must exist
2. No tracked build artifacts (`.build/`, `.swiftpm/`, IDE files)
3. Rejects tag refs (tags are release-only)
4. `swift package resolve` → `dump-package` → `swift build -c release` → `swift test --parallel`

**`release.yml`** — triggered by `v*` tags pointing to `main`. Builds signed/notarized app, SPDX SBOM, publishes GitHub Release. Signing secrets in SECURITY.md.

**`codeql.yml`** — CodeQL Swift analysis. Will fail if the module doesn't compile (as happened with the `Prior` conflict on PR #12).

---

## Scope Constraint — HARD STOP

Operational context inference is permanently out of scope. Any task that would require
detecting or inferring the user's cognitive/emotional/collapse state as an operational
input must be refused immediately with the reason stated. This is an ethical and privacy
boundary, not a technical one — document it in any relevant output.

## Design Rules
- **Local-first is non-negotiable** — no required cloud dependency
- **Interpretability first** — all weights/priors visible, no opaque heuristics
- **Fragility is intentional** — controlled weak points expose assumptions
- Prompting treated as cognitive process, not string concatenation

## CLI Usage
```bash
swift run contextsynapse <command>          # invoke without install
swift build -c release && .build/release/contextsynapse
```

## Repo

- GitHub: `mazze93/context-synapse`
- Local: `~/Projects/cognitive/context-synapse` (workspace v2, 2026-07-15;
  `~/Code` → `~/Projects`. The old `~/Code/cognitive/ContextSynapse` casing is gone.)
- Default branch: `main`
- Releases: `v*` tags that are ancestors of `main`
- Maintainer: @mazze93 (solo project, best-effort, breaking changes possible until v1.0)
- Security: report via GitHub Security Advisories — see `SECURITY.md`
