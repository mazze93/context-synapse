# ContextSynapse — Claude Context

Local-first Bayesian prompt orchestration engine. Research-grade.
Not a consumer product — built by and for a neurodivergent developer exploring human-machine context negotiation.

---

## CURRENT STATE — START HERE

**Version:** v0.3.0-decay (active sprint)
**Branch model:** all work on feature branches, PRs against `main`

### Open PRs

| PR | Branch | Status | Contents |
|----|--------|--------|----------|
| #11 | `claude/repo-docs-value-trust-dLqaj` | Draft | README + INSTALL.md rewrite: real prerequisites (macOS 13+, Swift 5.8+), real CLI flags, correct config JSON, maintenance posture, SECURITY.md link |
| #12 | `claude/circuit-bedrock-v0.3` | Draft, CI failing → **fix pushed** | Bedrock layer: SynapticCircuit actor, CircuitTypes, FaultInjectionSuite, 3 ADRs |

### PR #12 CI failure — root cause and fix

`SynapseCore.swift:183` defines `public struct Prior` (the existing simple Beta wrapper).
`CircuitTypes.swift` originally also defined `public struct Prior` (the new richer type).
Both land in the `SynapseCore` module. Duplicate type = build failure.

**Fix:** Renamed the circuit-layer type to `SynapticPrior` throughout `CircuitTypes.swift`.
The old `Prior` in `SynapseCore.swift` is untouched — it is serialized to disk in `config.json`, do not rename or move it.

Verify the fix is clean: `grep -rn "^public struct Prior" Sources/SynapseCore/` should return exactly one result (`SynapseCore.swift:183`).

### assemblePrompt — RESOLVED, do not reopen

ROADMAP flagged this as HIGH/BUG. Verified: `main.swift:299` correctly calls
`core.assemblePrompt(tone: chosenTone, intent: chosenIntent, domain: chosenDomain, query: userQuery)`.

---

## Stack

| Concern | Detail |
|---------|--------|
| Language | Swift 5.8+, macOS 13+ only |
| Build | `swift build -c release` |
| Test | `swift build && swift test --parallel` — build first, some tests exec the CLI binary |
| CI | GitHub Actions (`macos-15` runner) — no Swift toolchain in this Linux container |
| Persistence | JSON files in `~/Library/Application Support/ContextSynapse/` |
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
  BayesianConvergenceTests.swift  # All current tests

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
- `RefereeConfig { mode: RefereeMode }` — exists but is not yet persisted (P1 sprint item)

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
8.  loadLighthouse → SynapseWeightState.recomputeRotScore → RavenState.from(rotScore:lighthouseSet:)
9.  core.assemblePrompt(tone: chosenTone, intent: chosenIntent, domain: chosenDomain, query: userQuery)
                                           ↑ verified correct, main.swift:299
10. print(finalPrompt) + blank line
11. RavenRenderer.render(state: edgarState, ...)
12. If edgarState == .cauterize: EdgarIntervention.render(...)
13. core.logRun(...)   — writes run-<iso>.json with context map
14. core.applyFeedbackUpdate(...) if --feedback good|bad|yes|no
```

Lighthouse state persists across invocations via `lighthouse.json` in the user's AppSupport dir.
**Design note:** `loadLighthouse`/`saveLighthouse`/`clearLighthouse` live in `main.swift`. They belong in `SynapseCore` for testability and GUI access. Move when `SynapseManager` is built (v0.4).

---

## Sprint Backlog — Ordered by Priority

### P0 — Get PR #12 green

- [x] Rename `Prior` → `SynapticPrior` in `CircuitTypes.swift` — eliminates module-level duplicate type
- [ ] Push fix to `claude/circuit-bedrock-v0.3`, confirm CI passes
- [ ] Consider adding strict concurrency flag to `Package.swift` for SynapseCore target:
  ```swift
  .target(name: "SynapseCore", path: "Sources/SynapseCore",
          swiftSettings: [.enableExperimentalFeature("StrictConcurrency")])
  ```
  This surfaces latent actor isolation warnings without bumping swift-tools-version. Recommended before v0.4 actor wiring.

### P1 — v0.3.0 remaining items (all new files, no modifications to existing)

- [ ] **`Tests/DecayWeightTests.swift`** — three tests:
  1. Lighthouse floor invariant: `finalWeight(baseWeight:maxConnections:at:)` with `isLighthouse=true` never returns < `DecayConstants.lighthouseFloor` regardless of time elapsed
  2. Cauterization threshold: `rotScore >= DecayConstants.rotCauterizeThreshold` must set `requiresCauterization = true`
  3. Decay monotonicity: `decayWeight` decreases as `at` moves further from `lastInteractionAt`
  Use UUID-suffixed folder names in any `SynapseCore` instances (match `BayesianConvergenceTests.swift` isolation pattern).

- [ ] **`Sources/SynapseCore/RunLogDecay.swift`** — extend `SynapseCore.RunLog` via extension (no modification to `SynapseCore.swift`):
  Add `DecaySnapshot: Codable` struct with fields: `decayWeight`, `rotScore`, `lighthouseSaliency`, `refereeMode`, `interventionFired: Bool`.
  Wire the additional fields into `main.swift`'s `RunLog` context dict (currently `rotScore` and `edgarState` are stored as raw strings — upgrade them).

- [ ] **`Sources/SynapseCore/BreadcrumbWriter.swift`** — on lighthouse load, emit a re-sync line before the prompt:
  `⚓ Lighthouse: [text] — saliency [X]% — last touched [N]min ago`
  Append to `logs/breadcrumb-<iso>.txt`. Called from CLI after `loadLighthouse` returns non-nil.

- [ ] **`Sources/SynapseCore/RefereeConfigStorage.swift`** — `RefereeConfig` persistence round-trip.
  `RefereeConfig` is defined in `SynapseReferee.swift` but never saved or loaded. Add load/save from `config.json` alongside `Weights` using an extension on `SynapseCore`.

### P2 — Docs

- [ ] **Merge PR #11** — `main` currently has wrong prerequisites (macOS 12, Swift 5.7) and fabricated CLI flags (`--status`, `--config`, `--feedback positive`). PR #11 has the correct versions. Merge before any public-facing work or Show HN post.

### P3 — Architecture prep for v0.4

- [ ] **`Sources/SynapseCore/SynapseManager.swift`** — session coordinator skeleton. Will own: session-level `SynapseWeightState` map, lighthouse designation, `SynapticCircuit` lifecycle, backward-pass wiring after each interaction. Integration recipe is in `docs/adr/INTEGRATION.md`.
- [ ] **Migrate lighthouse helpers from CLI to `SynapseCore`** — `loadLighthouse`/`saveLighthouse`/`clearLighthouse` in `main.swift` are not accessible to the GUI or tests. Move to `SynapseCore` before `SynapseManager` is built.

---

## Known Issues

| Issue | Severity | Target | Notes |
|-------|----------|--------|-------|
| Silent write failures in GUI | Medium | v1.0 | No error surface in AppViewModel for disk I/O failures |
| Unbounded prior growth | Low | v1.0 | alpha/beta accumulate indefinitely; add EMA decay |
| Multi-process write collision | Low | v1.0 | No file lock; single-writer assumption must be documented prominently |
| `minutesInDrift` hardcoded to 15 in `main.swift:318` | Low | v0.4 | Should be computed from `lighthouse.setAt` timestamp in `LighthouseRecord` |
| `RegionModel.swift` duplicates `canonicalVector` | Intentional | — | Extension separation design; creates drift risk — keep in sync manually |
| `SynapseCore.swift` is a ~900-line monolith | Design debt | v1.0 | Split into focused files (BayesianEngine, SimilarityEngine, Persistence) once API is frozen |
| `emitDriftEvent` in `SynapticCircuit` writes to stdout | Technical debt | v0.4 | Replace with injected RunLog writer at construction |

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

No Swift toolchain in this Linux container. CI runs on `macos-15` and is the build authority.

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

## Repo

- GitHub: `mazze93/context-synapse`
- Default branch: `main`
- Releases: `v*` tags that are ancestors of `main`
- Maintainer: @mazze93 (solo project, best-effort, breaking changes possible until v1.0)
- Security: report via GitHub Security Advisories — see `SECURITY.md`
