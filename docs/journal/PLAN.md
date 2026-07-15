# Sprint plan — CI repair + lighthouse migration + P1 backlog

Branch: `claude/v0.3-ci-repair-and-p1` · Started 2026-07-15

## Context

- `main` CI is red: guardrails step rejects tracked `.vscode/settings.json`
  (fails in ~13s, before build).
- That early exit masks a second breakage: `Tests/SynapticCircuitTests.swift`
  (PR #13) references the pre-rename `Prior` circuit API — 95 compile errors.
  PR #13 must have merged before/independently of the PR #12 rename.
- A previous session left `Sources/SynapseCore/LighthouseStore.swift` untracked
  (P3 migration + P1 BreadcrumbWriter); CLI rewiring finished this session.

## Phases

- **A. Scaffold** — journal files, feature branch. Commit.
- **B. CI repair** — untrack `.vscode/settings.json` (v2 retired VS Code);
  fix `Prior` → `SynapticPrior` in SynapticCircuitTests.swift. Build+test green
  locally. Commit.
- **C. Lighthouse migration** — LighthouseStore.swift + CLI rewire +
  BreadcrumbWriter + real `minutesInDrift` + LighthouseStoreTests. Commit.
- **D. DecayWeightTests.swift** — P1 item 1: floor invariant, cauterization
  threshold, decay monotonicity. Commit.
- **E. RunLogDecay.swift** — P1: `DecaySnapshot` extension on RunLog; upgrade
  main.swift context payload. Commit.
- **F. RefereeConfigStorage.swift** — P1: persist `RefereeConfig` round-trip in
  config.json; CLI reads mode from it. Commit.
- **G. Strict concurrency** — P0 leftover: add StrictConcurrency to SynapseCore
  target; keep only if build stays clean. Commit.
- **H. Close out** — update CLAUDE.md backlog/known-issues, full build+test,
  end-to-end CLI verify, push, PR to main.

## Constraints

- No modifications to serialized `Prior` (SynapseCore.swift:183).
- New SynapseCore files auto-join the module (SPM rule) — no Package.swift edit
  except Phase G.
- Tests: separate files, UUID-isolated folders.
- ADR-001/ADR-002 boundaries untouched.
