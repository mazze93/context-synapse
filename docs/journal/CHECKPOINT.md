# Checkpoint — resume here if the session drops

## Active — 2026-07-18: known-issues cleanup sweep

**Branch:** `chore/known-issues-cleanup-v0.4` (off `main` @ `eab27fa`).
Read PLAN.md then DECISIONS.md, continue at first unchecked phase.

- [ ] **A. Scaffold** — journal + branch
- [x] **B. Unbounded prior growth** — renormalization cap + PriorGrowthTests (4 tests green)
- [x] **C. Silent GUI write failures** — Bool-returning saves + AppViewModel error surface + ContentView banner (full suite 198 green, CLI smoke ok, touchstone HELD)
- [x] **D. emitDriftEvent stdout** — injectable sink, stderr default (stdout confirmed clean; drift branch unreachable under shipped eta — noted in test perimeter)
- [x] **E. Multi-process write collision** — documented (README single-writer note + saveWeights doc comment); CLAUDE.md + README Known Issues tables updated for B–E; release build clean, full suite green, CLI smoke ok

## SHIPPED — 2026-07-19

- [x] **F. Follow-up (post-review)** — Link 1 GUI-failure verification:
  `baseOverride` seam + `PersistenceFailureTests` + ADR-005 (Links 2-3 deferred/
  perimeter).
- **PR #22 MERGED** into `main` — squash merge commit `d25ace4` (mergedAt
  2026-07-19T03:07Z). All required checks green on the merge: Analyze (Swift),
  Build/test/guardrails, CodeQL, Greptile.
- Post-merge re-verification on `main` (2026-07-21): `swift build`,
  `swift build -c release`, `swift test --parallel` (204 tests) all green; CLI
  smoke ok; zero conflict markers on `origin/main` or on disk.
- **Cleanup:** a stale duplicate PR #23 (same head branch, re-pushed by
  GitButler with unresolved conflict markers — Greptile 1/5, non-compiling) was
  closed as superseded; the `chore/known-issues-cleanup-v0.4` branch was deleted
  local + remote. All four known issues are resolved on `main`.

## Deferred limitations (documented, not gaps in shipped code)

- **GUI write-failure Links 2–3** (ADR-005): ViewModel→`lastError` reflection
  test deferred until `AppViewModel` moves to a library target; SwiftUI banner
  *render* is inherent perimeter (needs XCUITest). Link 1 (disk-I/O → `false`)
  is verified.
- **Circuit drift branch:** `drift > 0.1` is unreachable via the public API
  under shipped `etaBase = 0.1`; drift-sink firing is untested end-to-end by
  design (no production behavior changed to force it).

## Historical (done, merged)

PR #20 merge task and the v0.3 CI-repair/P1 sprint are complete and on `main`
(`eab27fa`, `ac141f8`, `af16eab`). Detail in git history — do not reopen.
