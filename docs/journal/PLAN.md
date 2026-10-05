# Sprint plan — Known-issues cleanup sweep

Branch: `chore/known-issues-cleanup-v0.4` · Started 2026-07-18

> Supersedes the PR #20 merge task (done, merged as of `eab27fa`). Prior sprint
> detail lives in git history — do not reopen.

## Goal

Targeted, scoped sweep of the Known Issues table in CLAUDE.md. Real fixes,
budget-conscious. Explicitly OUT of scope this sweep: the ~900-line
`SynapseCore.swift` monolith split (design debt, v1.0, risky) and the
intentional `RegionModel` `canonicalVector` duplication (by design).

## Phases (each finish-and-commit)

- **A. Scaffold** — journal + feature branch. Commit.
- **B. Unbounded prior growth** (Known Issue, Low/v1.0) — mean-preserving
  renormalization cap in `SynapseCore.applyFeedbackUpdate` bump so `alpha+beta`
  can't accumulate without bound. New cap constant. Test in a new
  `Tests/PriorGrowthTests.swift` (UUID-isolated). Commit.
- **C. Silent GUI write failures** (Known Issue, Medium/v1.0) — make
  `saveWeights` / `saveRegions` / `logRun` return `@discardableResult Bool`
  (CLI callers unaffected — they discard). Surface a `@Published` error string
  in `AppViewModel` so GUI disk-I/O failures are no longer invisible. Commit.
- **D. `emitDriftEvent` stdout pollution** (Known Issue, tech debt/v0.4) —
  make the drift sink injectable at `SynapticCircuit.init`; default routes to
  **stderr** not stdout (stdout is machine-readable-only per conventions).
  Wire `SynapseManager` to construct with the default. Commit.
- **E. Multi-process write collision** (Known Issue, Low/v1.0) — document the
  single-writer assumption prominently (README + doc comment at the persistence
  boundary). Update CLAUDE.md Known Issues table for B–E. Full build + test +
  CLI smoke. Commit. Push/PR left for user confirmation (not asked).

## Constraints

- `Prior` (SynapseCore.swift:184) is serialized — cap changes VALUES only, never
  the `{alpha,beta}` schema. Safe.
- New SynapseCore/Tests files auto-join their targets (SPM) — no Package.swift edit.
- Tests: separate files, UUID-isolated folders, never share state.
- ADR-001/ADR-002 boundaries untouched. No operational-context inference.
- Do not touch serialized shapes, `assemblePrompt`, or the drift-clock anchor.
