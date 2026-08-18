# Checkpoint — resume here if the session drops

## Active — 2026-08-18: pivot from GitButler to jujutsu (jj)

Adopting jj for this repo after GitButler friction (raw commits were hook-
blocked; a stacked rebase wrote conflict markers that broke the build — see the
2026-07-22 salvage audit below). jj's first-class conflicts + `jj undo` + stable
change IDs + terminal-native model fit better. See DECISIONS 2026-08-18.

Prereqs already satisfied between sessions:
- [x] GitButler fully removed (no managed hook, no `.git/gitbutler/`)
- [x] jj installed — 0.44.0 via brew
- [x] Global jj identity set — `~/.config/jj/config.toml` (Mazze LeCzzare)

Remaining (staged, not yet run — awaiting go-ahead):
- [ ] **Colocate:** `jj git init --colocate` (imports git HEAD; `.git` untouched)
- [ ] **Verify:** `jj status` / `jj log`; confirm origin push via a bookmark
- [ ] **Orientation:** first-week jj loop (`new` / `describe` / `bookmark` / `git push`)

**To resume:** run the colocate one-liner in DECISIONS 2026-08-18. Fully
reversible: `rm -rf .jj` returns to plain git (`.git` is authoritative).
**Deferred/needs-user:** whether to colocate the rest of `~/Projects` (per-repo,
deliberate — not this session); keep `secure-pride/*` out of any experiment.

## 2026-07-22 — GitButler state discarded, repo realigned to origin/main

This repo is now on plain `main` @ `2b70c48`, clean, building, 216 tests green.
GitButler is fully removed here: no `gitbutler/*` refs, no `ml-branch-*`, no
`.git/gitbutler/`, no managed hooks. See DECISIONS.md 2026-07-22 for the
salvage audit that justified discarding the local branch (short version: it
contained zero unique code and was missing four files from merged PR #24).

**The section below is stale** — it describes the PR #22 sweep as in-progress.
PR #22 merged as `d25ace4` on 2026-07-18. Kept for history, not for resuming.

### Still open in this repo (not addressed 2026-07-22)
- **PR #20** (`chore/v0.3-cleanup-and-doc-sync`) is still open, with 22 commits
  unpushed on the local branch. Untouched by the realignment.
- `claude/v0.3-ci-repair-and-p1` is ahead 1 / behind 1 of its remote.

## Active — 2026-07-18: known-issues cleanup sweep

**Branch:** `chore/known-issues-cleanup-v0.4` (off `main` @ `eab27fa`).
Read PLAN.md then DECISIONS.md, continue at first unchecked phase.

- [ ] **A. Scaffold** — journal + branch
- [x] **B. Unbounded prior growth** — renormalization cap + PriorGrowthTests (4 tests green)
- [x] **C. Silent GUI write failures** — Bool-returning saves + AppViewModel error surface + ContentView banner (full suite 198 green, CLI smoke ok, touchstone HELD)
- [x] **D. emitDriftEvent stdout** — injectable sink, stderr default (stdout confirmed clean; drift branch unreachable under shipped eta — noted in test perimeter)
- [x] **E. Multi-process write collision** — documented (README single-writer note + saveWeights doc comment); CLAUDE.md + README Known Issues tables updated for B–E; release build clean, full suite green, CLI smoke ok

## SHIPPED — 2026-07-21: on-device AI client + provenance (PR #24)

`FoundationModelsClient` (on-device, opt-in, macOS 26+ via canImport/@available
so macos-15 CI still builds) + generic `AIProvenanceRecord`/`AIBenchmarkReport`
(identity, provenance, repeatable benchmark). Records persist **on-device only**
(`SynapseCore.recordAIBenchmark` → Application Support); never stdout/CI/repo —
enforced by a portable containment test + `.gitignore`. **PR #24 MERGED**
(squash `4a1f65c`); all checks green (Analyze/Swift, Build+guardrails on
macos-15, CodeQL, Greptile). Proven end-to-end locally on M5 Pro / macOS 27:
real on-device round-trip + 3-iteration benchmark. See DECISIONS 2026-07-21.
Deferred: Core ML `LocalEmbeddingDistance`; bootstrap script (separate repo).

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
