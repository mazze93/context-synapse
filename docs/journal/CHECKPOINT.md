# Checkpoint — resume here if the session drops

## Active — 2026-07-18: known-issues cleanup sweep

**Branch:** `chore/known-issues-cleanup-v0.4` (off `main` @ `eab27fa`).
Read PLAN.md then DECISIONS.md, continue at first unchecked phase.

<<<<<<< New base: chore: known-issues cleanup sweep (prior cap, GUI error surface, drift sink, sin
- [ ] **A. Scaffold** — journal + branch
- [x] **B. Unbounded prior growth** — renormalization cap + PriorGrowthTests (4 tests green)
- [x] **C. Silent GUI write failures** — Bool-returning saves + AppViewModel error surface + ContentView banner (full suite 198 green, CLI smoke ok, touchstone HELD)
- [x] **D. emitDriftEvent stdout** — injectable sink, stderr default (stdout confirmed clean; drift branch unreachable under shipped eta — noted in test perimeter)
- [x] **E. Multi-process write collision** — documented (README single-writer note + saveWeights doc comment); CLAUDE.md + README Known Issues tables updated for B–E; release build clean, full suite green, CLI smoke ok
||||||| Common ancestor
---
=======
- [ ] **A. Scaffold** — journal + branch
- [x] **B. Unbounded prior growth** — renormalization cap + PriorGrowthTests (4 tests green)
- [ ] **C. Silent GUI write failures** — Bool-returning saves + AppViewModel error surface
- [ ] **D. emitDriftEvent stdout** — injectable sink, stderr default
- [ ] **E. Multi-process write collision** — document + CLAUDE.md table + full build/test/smoke
>>>>>>> Current commit: chore(journal): scaffold known-issues cleanup sweep

<<<<<<< New base: chore: known-issues cleanup sweep (prior cap, GUI error surface, drift sink, sin
## ALL PHASES COMPLETE — PR #22 open against main

- [x] **F. Follow-up (post-review)** — Link 1 GUI-failure verification:
  `baseOverride` seam + `PersistenceFailureTests` + ADR-005 (Links 2-3 deferred/
  perimeter). Added to PR #22.
- Pushed `chore/known-issues-cleanup-v0.4`; PR #22 → main.

## To resume
||||||| Common ancestor
## Active — 2026-07-18: resolve & merge stale PR #20

**Branch:** `chore/v0.3-cleanup-and-doc-sync` (mid-merge with `main` when this
session picked it up — `git status` showed `UU` conflicts in AGENTS.md,
CLAUDE.md, README.md, ROADMAP.md, plus a bunch of clean adds/deletes from
main's side already auto-staged).

### What this branch actually is

PR #20 on GitHub, open since it diverged from `main` right after commit
`3278208`/`e081abe` (2026-05-04) — before the real v0.3 bedrock layer
(`SynapticCircuit`, `FaultInjectionSuite`) and v0.4 (`SynapseManager`,
`LighthouseStore`, `RavenRenderer`, `docs/adr/`, `docs/journal/`, `site/`)
landed on `main`. Confirmed by reading content, not just commit messages:
every conflicting doc hunk on `main`'s side described what's actually in the
repo; the chore branch's side documented an abandoned file split
(`DecayConstants.swift` / `SynapseContent.swift` pulled out of
`InteractionRecord.swift`) that never shipped, plus three renamed test files
(`SynapseWeightStateTests.swift`, `SynapseRefereeTests.swift`,
`SemanticDistanceTests.swift`) duplicating what `main` covers as
`DecayWeightTests.swift` / `SynapticCircuitTests.swift`.

### What was done (all local, nothing pushed yet)

1. Resolved the 4 `UU` conflicts by taking `main`'s side (`git checkout
   --theirs`).
2. Caught that git's non-conflicting auto-merge had silently resurrected the
   abandoned `DecayConstants.swift`/`SynapseContent.swift` plus the 3 renamed
   test files as new adds alongside `main`'s real `InteractionRecord.swift` —
   a real duplicate-type risk, same class of bug as the `Prior`/`SynapticPrior`
   incident (see CLAUDE.md). Reconciled by making the whole tree match `main`
   exactly (`git checkout main -- .` then `git rm --cached` the 5 stale
   files). Verified `git diff main chore/v0.3-cleanup-and-doc-sync` = 0 lines.
3. Committed the merge as `5120f97` on `chore/v0.3-cleanup-and-doc-sync`.
   `swift build` passes clean.

### Still open — needs user decision before continuing
=======
## To resume
>>>>>>> Current commit: chore(journal): scaffold known-issues cleanup sweep

Continue at the first unchecked box. Each phase = one commit. `swift build`
then `swift test --parallel` must be green before committing a code phase.

## Deferred / needs-user

- **Push + PR to `main`** — NOT asked for. User requested cleanup with
  checkpoints (= local commits). Offer push/PR at the end; do not push
  autonomously (repo is public/HIGH posture).

## Historical (done, merged)

PR #20 merge task and the v0.3 CI-repair/P1 sprint are complete and on `main`
(`eab27fa`, `ac141f8`, `af16eab`). Detail in git history — do not reopen.
