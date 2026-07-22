# Decisions — append-only

- 2026-07-22 · Discarded the local GitButler branch state; `main` reset to
  `origin/main` (`2b70c48`) · **Salvage audit first — nothing was thrown away
  unexamined.** GitButler had left this repo on `gitbutler/workspace`, 13
  commits ahead of `origin/main` and 3 behind, with unresolved conflict markers
  **committed into history** across 5 files (its `<<<<<<< New base:` /
  `Common ancestor` / `Current commit:` rebase format) and commit messages with
  words run together and dropped (e.g. `fix(docs): …docsRemove leftover markers
  CLAUDE and docs/j/CHECKPOINT.md,`).
  Audit method and result: the merge base was `d25ace4` — the **squash-merge of
  PR #22 itself** — meaning the 7 "clean-looking" commits were the sweep's work
  *re-applied on top of its own squashed merge*, which is what generated the
  conflicts. `git diff origin/main HEAD` showed **141 insertions / 631
  deletions**; filtering conflict markers and blank lines out of the additions
  left only (a) stale journal prose describing PR #22 as still open, and (b) one
  `CLAUDE.md` "Local-first" bullet that `origin/main` already carries in a
  strictly longer form (main's adds the `FoundationModelsClient` on-device
  clause). **Zero unique source or test code.** `ml-branch-2` was audited
  separately (its head `e41e70e` was not among the 13) and contained the same
  stale prose and nothing else.
  Meanwhile local was *missing* four files that exist on main —
  `Sources/SynapseCore/{AIProvenance,FoundationModelsClient}.swift` and their
  tests — from merged PR #24. The local branch was strictly worse than main.
  Verified after reset: no conflict markers in HEAD, all four files restored,
  `swift build` clean, `swift test --parallel` exit 0 with 216 tests and zero
  errors.
  **Untouched by this:** `chore/v0.3-cleanup-and-doc-sync` (PR #20, still open,
  22 commits) and `claude/v0.3-ci-repair-and-p1` both survive intact.
  Reverse: `git reset --hard backup/gitbutler-workspace-2026-07-22` (and
  `backup/ml-branch-2-2026-07-22` for the other head) — both annotated tags
  preserve the exact pre-reset commits.
- 2026-07-15 · Fix SynapticCircuitTests by renaming `Prior` → `SynapticPrior`
  in the test file (not a typealias shadow) · CLAUDE.md declares the two types
  intentionally separate; a typealias would re-blur exactly the ambiguity the
  rename removed · Reverse: sed the name back.
- 2026-07-15 · Untrack `.vscode/settings.json` rather than allowlist it in CI ·
  Workspace v2 retired VS Code config; the guardrail is correct, the tracked
  file is the bug · Reverse: `git checkout main -- .vscode/settings.json`.
- 2026-07-15 · `minutesInDrift` computed from `LighthouseRecord.setAt` (was
  hardcoded 15) · The record now travels to the CLI via LighthouseStore, so the
  known-issue fix costs two lines here · Reverse: restore literal 15.
- 2026-07-15 · BreadcrumbWriter writes one file per run (`breadcrumb-<iso>.txt`,
  atomic) rather than appending a single growing log · matches the `logRun`
  per-run pattern; CLAUDE.md said "append" but a shared append file breaks the
  single-writer assumption already flagged in Known Issues · Reverse: switch to
  FileHandle append on one path.
- 2026-07-15 · Landing page second color is amber (#f0b445) = the lighthouse
  beam; cyan stays Edgar/system · the two voices of the scene are the two
  voices of the palette · Reverse: collapse to cyan-only.
- 2026-07-15 · Breadcrumb prints to stdout before the prompt · CLAUDE.md P1
  spec says "emit a re-sync line before the prompt"; RavenRenderer already uses
  stdout, so the machine-readable-stdout rule is already scoped to the prompt
  line itself · Reverse: route through stderr.
- 2026-07-18 · Resolved PR #20 (`chore/v0.3-cleanup-and-doc-sync`) merge
  conflicts entirely in favor of `main`, including removing 5 non-conflicting
  files (`DecayConstants.swift`, `SynapseContent.swift`,
  `SynapseWeightStateTests.swift`, `SynapseRefereeTests.swift`,
  `SemanticDistanceTests.swift`) that git's auto-merge had silently added ·
  Verified by content, not commit messages, that the branch diverged before
  v0.3 bedrock/v0.4 landed and its unique changes were an abandoned file split
  that never shipped — keeping it would duplicate types already defined
  inline in `main`'s `InteractionRecord.swift`, the same failure class as the
  `Prior`/`SynapticPrior` incident · Reverse: `git revert` commit `5120f97` on
  `chore/v0.3-cleanup-and-doc-sync` (not yet merged into `main`).

---

## Sprint — known-issues cleanup sweep (2026-07-18)

- 2026-07-18 · Cap unbounded prior growth by **mean-preserving
  renormalization** (scale alpha & beta down proportionally when their sum
  exceeds a cap) rather than clamping alpha/beta independently · preserving the
  ratio keeps `probability()` and the mapped weight stable while bounding
  evidence weight — independent clamps would silently shift the mean · Reverse:
  remove the cap check in `applyFeedbackUpdate`'s `bump`.
- 2026-07-18 · touchstone pass on the prior-growth cap: HELD · probed
  composition (is `applyFeedbackUpdate` the only unbounded accumulator? — yes;
  circuit `SynapticPrior` already self-caps via `isOssified`, import merge
  averages) and spec (does `mapPriorToWeight` depend only on the ratio? — yes,
  `probability()` only, so renorm leaves weights unchanged) · perimeter: GUI
  error banner not driven against a real disk failure (no GUI test target);
  cap=200 is policy not correctness.
- 2026-07-18 · Silent GUI write failures: `saveWeights`/`saveRegions`/`logRun`
  now `@discardableResult -> Bool` (CLI discards, unaffected); `AppViewModel`
  gains `@Published lastError`, set on failure and shown as a dismissable
  banner in `ContentView` · disk-I/O errors previously only reached stderr,
  invisible in the GUI · Reverse: restore `Void` returns and drop `lastError`.
- 2026-07-18 · `emitDriftEvent` no longer prints to stdout · new
  `CircuitDriftEvent` Sendable type + `SynapticCircuit.init(driftSink:)`
  injection point; default `stderrDriftSink` keeps the signal but off the
  machine-readable stdout channel (Coding Conventions) · touchstone perimeter:
  the `drift > 0.1` branch is unreachable via public backwardPass under shipped
  `etaBase = 0.1` (max single-pass mean movement ≈ 0.024), so end-to-end firing
  is untested — pre-existing property, not introduced here · Reverse: restore
  the `print(...)` in emitDriftEvent and drop the sink parameter.
- 2026-07-18 · Multi-process write collision resolved as DOCUMENTATION, not a
  lock · README gains a prominent single-writer note + the `saveWeights` doc
  comment states the contract; actual file-locking enforcement stays v1.0 · the
  Known Issue text explicitly asked for the assumption to be "documented
  prominently"; a lock is a larger, separate change · Reverse: delete the note
  and doc comment.
- 2026-07-18 · Close the GUI-write-failure test perimeter (Link 1 only) via a
  `baseOverride: URL?` DI seam on `SynapseCore.init` + `PersistenceFailureTests`
  (read-only temp dir → real EACCES → `save*` return false), guarded against
  root · ADR-005 records the full strategy: Link 2 (ViewModel reflection)
  deferred until `AppViewModel` moves to a library target, Link 3 (SwiftUI
  banner render) accepted as inherent perimeter (needs XCUITest, near-zero
  marginal value) · added to PR #22 since it closes that PR's own documented
  perimeter · Reverse: drop `baseOverride` + delete the test; prod path
  unchanged.

---

## Sprint — on-device AI client + provenance (2026-07-21, PR #24, merged 4a1f65c)

- 2026-07-21 · FoundationModels API surface confirmed by SDK type-check probes
  (`SystemLanguageModel.default.availability`, `LanguageModelSession().respond`,
  `supportedLanguages`) before writing any client code · getting symbol names
  wrong = won't compile; the API is macOS 26+ and undocumented in our training ·
  Reverse: n/a (evidence step).
- 2026-07-21 · `FoundationModelsClient` double-guarded `#if
  canImport(FoundationModels)` + `@available(macOS 26)` · framework ships only
  in the macOS 26+ SDK, but CI runs macos-15 and the package deploys to macOS
  13 — canImport compiles the file out on CI (still builds), @available gates
  runtime use · **consequence: CI never compiles this code; only local macOS
  26+ does** — verified end-to-end locally instead · Reverse: delete the file.
- 2026-07-21 · AI provenance/benchmark records persist **on-device only**
  (`SynapseCore.recordAIBenchmark` → Application Support), never stdout · records
  carry a host fingerprint (chip/model/memory/OS); stdout is a CI-log leak
  channel and CI logs are public · enforced by
  `AIProvenanceTests.testBenchmarkRecordsStayOnDeviceNotInRepo` (portable) +
  `.gitignore` defense-in-depth; full benchmark JSON deliberately kept out of
  the PR body too · Reverse: remove `recordAIBenchmark` + the containment test.
