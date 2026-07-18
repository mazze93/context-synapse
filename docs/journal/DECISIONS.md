# Decisions — append-only

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
