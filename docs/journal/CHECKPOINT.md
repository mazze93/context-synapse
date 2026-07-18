# Checkpoint — resume here if the session drops

## Active — 2026-07-18: known-issues cleanup sweep

**Branch:** `chore/known-issues-cleanup-v0.4` (off `main` @ `eab27fa`).
Read PLAN.md then DECISIONS.md, continue at first unchecked phase.

- [ ] **A. Scaffold** — journal + branch
- [x] **B. Unbounded prior growth** — renormalization cap + PriorGrowthTests (4 tests green)
- [x] **C. Silent GUI write failures** — Bool-returning saves + AppViewModel error surface + ContentView banner (full suite 198 green, CLI smoke ok, touchstone HELD)
- [x] **D. emitDriftEvent stdout** — injectable sink, stderr default (stdout confirmed clean; drift branch unreachable under shipped eta — noted in test perimeter)
- [x] **E. Multi-process write collision** — documented (README single-writer note + saveWeights doc comment); CLAUDE.md + README Known Issues tables updated for B–E; release build clean, full suite green, CLI smoke ok

## ALL PHASES COMPLETE — awaiting user decision on push/PR

## To resume

Continue at the first unchecked box. Each phase = one commit. `swift build`
then `swift test --parallel` must be green before committing a code phase.

## Deferred / needs-user

- **Push + PR to `main`** — NOT asked for. User requested cleanup with
  checkpoints (= local commits). Offer push/PR at the end; do not push
  autonomously (repo is public/HIGH posture).

## Historical (done, merged)

PR #20 merge task and the v0.3 CI-repair/P1 sprint are complete and on `main`
(`eab27fa`, `ac141f8`, `af16eab`). Detail in git history — do not reopen.
