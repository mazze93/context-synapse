# Checkpoint — 2026-10-29

## Collection is running locally

A controlled empty `jj commit` (`0fbe0004`) left the study ledger unchanged at
one event: Git post-commit hooks are bypassed. The CLI was absent from PATH too.
The opt-in LaunchAgent `com.contextsynapse.jj-collector` now polls this checkout
once per minute while logged in, with pinned copies of the collector and CLI.
The first post-install jj event was verified in the existing ledger. The original
Git observer is preserved but inactive (non-executable) to prevent duplicates.

Installed runtime/state: `~/Library/Application Support/ContextSynapse/instrument/jj-collector/`.
Check `state/last-success` and `stderr.log`. Baseline excludes historical changes;
no backfill. One opted-in repo supplies one synapse. Varied outcomes and at least
five consented synapses are still needed to evaluate P1–P4.

The study clock is not restarted. The original window ended October 27;
DECISIONS records the pre-specified first seven-day extension through November 3
at 23:53:20 America/New_York. FALSIFICATION.md remains unchanged by this work.

## Reviewable work

- #40: repaired compile failures earlier; now also preserves existing exact-owned
  Default/DEFAULT user state. New revision `1153ae0a` passes local tests and GitHub
  Build/test/guardrails. Merge is authorized only after review/checks pass; refresh
  review and CodeQL state before merging. No merge has been claimed here.
  App heartbeat `merge-context-synapse-40-after-review-passes` checks every
  15 minutes and is authorized to merge only after those conditions pass.
- #50: jj collector repair and study-window decision. Installed locally; PR open.
- #51: release/roadmap reconciliation, #44 close-proof entry, ethics correction,
  and this checkpoint. v0.3.0 is released; v0.4 is partly shipped. No new tag cut.
- #52: read-only `--session-diff` for two saved RunLogs. PR open.
- #53: draft explicit Shadow Context CLI fork/return/promotion, separate anchor
  histories and atomic selection index; retained-shadow resume/list and SwiftUI
  context selection remain deferred. No operator-state inference.

Local jj bookmark `codex/integration-validation` combines the five PRs for
verification without publishing or merging them to main. README and journal
append conflicts were resolved by preserving all additions. `swift build` and
the combined full suite pass: 236 tests, zero failures. Real-jj collector tests
also pass: repeated polls, rewrites, failure retries, interrupted checkpoint.

## Next steps

Refresh #40 checks/review and merge only when its condition is satisfied. Then
rebase the other PR bookmarks with jj onto updated main; journal additions must
be preserved when resolving append conflicts. Review #50/#51/#52 and draft #53
separately. Remaining v0.4 includes cauterized-decay integration, full trajectory
analysis, and the deferred Shadow/SwiftUI surfaces; completion is not claimed.
