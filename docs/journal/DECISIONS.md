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
- 2026-07-15 · Breadcrumb prints to stdout before the prompt · CLAUDE.md P1
  spec says "emit a re-sync line before the prompt"; RavenRenderer already uses
  stdout, so the machine-readable-stdout rule is already scoped to the prompt
  line itself · Reverse: route through stderr.
