# ContextSynapse — Claude Context

Local-first Bayesian prompt orchestration engine. Status: **experimental/research-grade**.
Not a consumer product — built for neurodivergent developers exploring human-machine context negotiation.

---

## Stack

| Concern | Detail |
|---------|--------|
| Language | Swift 5.8+, macOS 13+ only |
| Build | `swift build -c release` |
| Test | `swift test --parallel` |
| CI | GitHub Actions (`macos-15` runner) |
| Persistence | JSON files in `~/Library/Application Support/ContextSynapse/` |
| Dependencies | None (pure Swift stdlib + Foundation) |

---

## Repository Layout

```
Package.swift                    # Swift package manifest
default_config.json              # Canonical seed config (committed, used in CI sanity check)
Resources/default_config.json    # Duplicate for bundled resources
scripts/demo_convergence.sh      # Demo script for Bayesian convergence

Sources/
  SynapseCore/
    SynapseCore.swift            # Entire core library (single file)
  contextsynapse/
    main.swift                   # CLI entry point
  ContextSynapseApp/
    AppMain.swift                # SwiftUI @main + AppViewModel
    ContentView.swift            # Main UI layout
    HeatmapView.swift            # Canvas-based cosine similarity heatmap
    WeightGridView.swift         # Weight editing grid
    RegionModel.swift            # SynapseCore extension for canonical vector

Tests/
  BayesianConvergenceTests.swift # All tests in one file (XCTest)
```

---

## Package Targets

| Product | Type | Entry |
|---------|------|-------|
| `SynapseCore` | Library | `Sources/SynapseCore/SynapseCore.swift` |
| `contextsynapse` | Executable (CLI) | `Sources/contextsynapse/main.swift` |
| `ContextSynapseApp` | Executable (SwiftUI GUI) | `Sources/ContextSynapseApp/AppMain.swift` |
| `BayesianConvergenceTests` | Test target | `Tests/BayesianConvergenceTests.swift` |

All targets depend only on `SynapseCore`. There are no external Swift package dependencies.

---

## Core Architecture (`SynapseCore.swift`)

### Data Model

```
Weights
├── intents:  [String: Double]          # Summarize, Create, Analyze, Brainstorm, ActionableSteps
├── tones:    [String: Double]          # Concise, Technical, Casual, Persuasive, Creative
├── domains:  [String: Double]          # Work, Personal, GameDesign, Marketing, Writing
├── triggers: [String: [String: Double]] # Context boosters keyed by "app.X", "time.Y", "focus.Z"
└── priors:   Priors
    ├── intents:  [String: Prior]       # Beta distribution (alpha, beta) per intent
    ├── tones:    [String: Prior]
    └── domains:  [String: Prior]

Prior { alpha: Double, beta: Double }   # Beta prior; probability() = alpha/(alpha+beta)

Region { name: String, vector: [Double] } # Named embedding vector for cosine similarity

ExportBundle { version, exportDate, weights, regions, metadata } # State snapshot for export/import
UserProfile  { id, displayName, createdAt, lastUsedAt }          # Per-user metadata
```

### Key Methods on `SynapseCore`

| Method | Purpose |
|--------|---------|
| `loadOrCreateDefaultWeights()` | Read `config.json` or seed from `defaultWeights()` |
| `saveWeights(_:)` | Atomically write `config.json` |
| `loadOrSeedRegions()` | Read `regions.json` or seed from `defaultRegions(for:)` |
| `saveRegions(_:)` | Atomically write `regions.json` |
| `applyFeedbackUpdate(chosenIntent:chosenTone:chosenDomain:positive:)` | Bayesian Beta update on priors, recomputes numeric weights |
| `applyTriggers(base:triggers:activeKeys:)` | Multiply base weights by trigger boosters |
| `weightedPick(_:)` | Stochastic weighted sampling over a weight map |
| `assemblePrompt(tone:intent:domain:query:)` | Formats `[Tone] [Intent] [Domain]: query` |
| `cosineSimilarity(_:_:)` | Tolerates mismatched vector lengths (uses shared prefix) |
| `computeRegionSimilarities(regionsIn:)` | NxN similarity matrix + nearest-neighbor map; applies fault injection |
| `maybeInjectFaults(into:)` | Corrupts region vectors stochastically based on `faultProbability` |
| `canonicalVector(for:scale:)` | Sorted intents + tones + domains into a single `[Double]` |
| `exportState(to:metadata:)` | Serialize full state to `ExportBundle` JSON |
| `importState(from:merge:)` | Deserialize and replace or merge state |
| `logRun(_:)` | Write per-run JSON log to `logs/run-<iso8601>.json` |
| `listUsers()` | Enumerate user profiles from `users/` directory |
| `switchUser(to:folderName:)` | Static factory: returns new `SynapseCore` for a different user |
| `resetToFactoryDefaults()` | Overwrite config and regions with hard-coded defaults |

### Bayesian Update Flow

1. User receives an assembled prompt (intent/tone/domain were picked stochastically).
2. User provides `--feedback good|bad`.
3. `applyFeedbackUpdate` increments `alpha` (positive) or `beta` (negative) on that dimension's `Prior`.
4. `updateWeightsFromPriors` maps `Prior.probability()` → `[0.1, 3.0]` range via linear interpolation.
5. Updated weights are persisted. Over time, preferred dimensions converge toward higher probabilities.

### Fault Injection

`faultProbability` (default `0.0`, env: `CONTEXT_SYNAPSE_FAULT_PROB`) controls three corruption modes applied during `computeRegionSimilarities`:
- Gaussian noise addition
- Zeroing a contiguous slice
- Scaling down a random subset of elements

Intentional design: surfaces how similarity degrades under partial data loss.

---

## File System Layout (Runtime State)

```
~/Library/Application Support/ContextSynapse/
  users/
    default/
      profile.json    # UserProfile JSON
      config.json     # Weights (persisted Bayesian state)
      regions.json    # [Region] array
      logs/
        run-<iso>.json  # RunLog per invocation
    <other-users>/
      ...
```

User identifiers are sanitized (strips `/`, `\`, `:`, `.`) to prevent directory traversal.

---

## CLI (`contextsynapse`)

### Basic usage

```bash
contextsynapse "<query>" [flags]
```

Pipe input is also supported: `echo "query" | contextsynapse`.

Output format: `[Tone] [Intent] [Domain]: <query>`

### All flags

| Flag | Argument | Description |
|------|----------|-------------|
| `--user` | `<id>` | Select user namespace (default: `default`) |
| `--app` | `<name>` | Active app trigger key, e.g. `Mail`, `Notes` |
| `--focus` | `<mode>` | Focus mode trigger key, e.g. `DoNotDisturb` |
| `--time` | `HH:MM` | Override time bucket (morning/afternoon/evening) |
| `--intent` | `<name>` | Force a specific intent (skip stochastic pick) |
| `--tone` | `<name>` | Force a specific tone |
| `--domain` | `<name>` | Force a specific domain |
| `--feedback` | `good\|bad\|yes\|no` | Apply Bayesian feedback after printing the prompt |
| `--fault-prob` | `0.0–1.0` | Override fault injection probability for this run |
| `--export` | `<file.json>` | Export full state; cannot combine with `--import` |
| `--import` | `<file.json>` | Import state; add `--merge` to average priors instead of replace |
| `--metadata` | `key=value` | Attach metadata to an export (repeatable) |

Time buckets: `05:00–11:59` → `time.morning`, `12:00–16:59` → `time.afternoon`, else `time.evening`.

---

## SwiftUI GUI (`ContextSynapseApp`)

**`AppViewModel`** is the single `ObservableObject` bridging `SynapseCore` to the UI:
- `weights`, `regions`, `similarityMatrix`, `nearestMap` — published state
- `assemblePrompt()` — calls `core.weightedPick` then `core.assemblePrompt`, logs the run
- `setFaultEnabled(_:)` / `setFaultProbability(_:)` — toggle fault injection, restores last non-zero probability
- `disintegrateSkyPlates()` — calls `maybeInjectFaults` on the current regions and recomputes
- `saveConfig()` / `resetDefaults()` / `applyFeedback(...)` — delegate to core

**`HeatmapView`** — `Canvas`-based NxN heatmap. Color ramps from blue (low similarity) through orange/yellow (high). Tap to highlight a cell and show the pair + score in an overlay.

**`WeightGridView`** — Editable sliders for each weight entry in the `Weights` struct.

---

## AI Platform Integration

`SynapseCore` includes `OpenAIClient` and `AnthropicClient` implementing `AIClient`:

```swift
protocol AIClient {
    func sendPrompt(_ prompt: String, completion: @escaping (Result<String, Error>) -> Void)
}
```

Both share `BaseHTTPAIClient` for HTTP request/response handling (30s timeout, no caching, HTTP status validation). **Not wired into the CLI** — intended for embedders building on top of `SynapseCore` as a library.

---

## Build & Test

```bash
# Build all targets (release)
swift build -c release

# Build CLI only
swift build -c release --product contextsynapse

# Run all tests in parallel
swift test --parallel

# Run with fault injection via env
CONTEXT_SYNAPSE_FAULT_PROB=0.4 .build/debug/contextsynapse "test query"
```

The test suite (`BayesianConvergenceTests`) uses unique `folderName` UUIDs to isolate each test's state. Tests requiring the CLI binary call `ensureCLIExecutable()` which skips via `XCTSkip` if `.build/debug/contextsynapse` is not present — run `swift build` before `swift test` for full coverage.

---

## CI / CD

**`ci.yml`** — runs on `pull_request` and `push` to `main`, macOS 15:
1. Verifies required files exist: `.gitignore`, `Package.swift`, `README.md`, `SECURITY.md`, `INSTALL.md`, `LICENSE`, `default_config.json`
2. Checks no `.build/`, `.swiftpm/`, or IDE artifacts are tracked
3. Rejects tag refs (tags are release-only)
4. `swift package resolve` → `swift package dump-package` → `swift build -c release` → `swift test --parallel`
5. Optionally builds Xcode app scheme if a `.xcworkspace` or `.xcodeproj` is present

**`release.yml`** — triggered by `v*` tags or `workflow_dispatch` (dry-run only):
- Production: verifies tag points to `main`, builds CLI + optional signed/notarized app, generates SPDX SBOM, publishes GitHub Release
- Dry-run: builds unsigned artifacts, uploads as workflow artifacts only
- Signing secrets: `APPLE_DEVELOPER_ID_APP_CERT_BASE64`, `APPLE_CERT_PASSWORD`, `APPLE_KEYCHAIN_PASSWORD`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, `APPLE_NOTARY_PRIVATE_KEY_BASE64`

**`codeql.yml`** — CodeQL static analysis on Swift.

**`dependabot.yml`** — GitHub Actions dependency updates.

---

## Design Constraints (Non-Negotiable)

- **Local-first**: no required network calls; AI clients are opt-in library extensions only
- **Interpretability**: all weights and priors are stored as plain JSON, always human-readable
- **Fragility is intentional**: fault injection is a first-class feature, not a bug; do not "fix" it
- **Prompting as cognition**: the assembled prompt encodes context metadata, not just string concatenation
- **Determinism**: core algorithms are deterministic given fixed weights; stochastic paths (`weightedPick`, fault injection) use `Double.random` and are explicitly labeled

---

## Coding Conventions

- No external dependencies — keep `Package.swift` dependency-free
- Atomic writes (`options: .atomic`) for all state persistence
- User input sanitization at the `SynapseCore.init` boundary (directory traversal prevention)
- Errors to stderr via `StandardErrorStream`; stdout is reserved for machine-readable output (prompt string)
- Tests use unique folder names (`UUID().uuidString`) so they never share state
- `RegionModel.swift` in the GUI target duplicates `canonicalVector` — this is a deliberate extension separation, not a bug

---

## Repo

- GitHub: `mazze93/context-synapse`
- Default branch: `main`
- Releases triggered by pushing `v*` tags that are ancestors of `main`
