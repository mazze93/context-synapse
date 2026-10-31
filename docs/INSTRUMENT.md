# Instrument Layer — Wiring Guide

Converts the repo from a verified implementation into an instrument that
generates evidence. Three producers, one ledger, one export.

```
git commit ──► post-commit hook ──► contextsynapse --record ──► events.jsonl
                    │                                                │
              (all hashing here)                    contextsynapse --export-events
                                                                     │
                                                                  events.csv ──► analysis
```

## Files

| File | Purpose |
|---|---|
| `Sources/SynapseCore/EventLedger.swift` | Append-only JSONL store + CSV export |
| `Sources/contextsynapse/RecordCommand.swift` | `--record` / `--export-events` / `--events-summary` |
| `scripts/hooks/post-commit` | The observer. Does all hashing. |
| `scripts/install-git-hook.sh` | Idempotent installer; chains existing hooks |
| `FALSIFICATION.md` | **Commit before the first observation** |
| `docs/DATA-CLASSIFICATION.md` | Field-level handling; needs sign-off |
| `docs/adr/ADR-006-ledger-separation.md` | Why this ledger is separate from Stratum |

---

## Install

```bash
swift build
export PATH="$PWD/.build/debug:$PATH"          # or install the binary

# git does not preserve the executable bit through the GitHub Contents API
chmod +x scripts/install-git-hook.sh scripts/hooks/post-commit

bash scripts/install-git-hook.sh .              # this repo
bash scripts/install-git-hook.sh ~/Code/stratum # any other repo

echo "context-synapse" > .contextsynapse        # optional thread label (codename only)
```

Verify:

```bash
git commit -m "test" --allow-empty
contextsynapse --events-summary
contextsynapse --export-events /tmp/events.csv
```

Uninstall: `bash scripts/install-git-hook.sh --uninstall .`

---

## Verified behavior

Tested end-to-end in a scratch repository:

- A commit whose message contained a client name and a key path produced argv
  with **no message, no paths, no filenames** — only a hashed token and a count
- Salt written `-rw-------`; repo token stable across commits
- `.contextsynapse` label overrides the token-derived synapse ID
- Root commit counts changed files correctly
- Pre-existing `post-commit` hook preserved, backed up, and still runs
- Second install does not double-chain
- **With no CLI on PATH, the commit still succeeds** — the observer can never
  cost you work

Two bugs were found and fixed during testing:

1. `IFS=$'\n\t'` removes space from word splitting, so a `"shasum -a 256"`
   command *string* was executed as a single command name. Replaced with a
   dispatch function.
2. `git diff-tree` reports zero changed files on a root commit without
   `--root`. Fixed and re-verified.

## Not verified

**No Swift toolchain was available when this layer was written.** The shell
scripts are tested; the Swift is not compiled. CI is the gate. If the build
fails, the likely culprits are, in order:

1. `core.logDir` visibility — confirmed `public let` and equal to
   `<userDir>/logs`, so `deletingLastPathComponent()` yields the per-user dir
2. `InteractionEventType` conformance — confirmed `String`, `CaseIterable`,
   with `successWeight`
3. Top-level-code rules — `RecordCommand.swift` contains declarations only

---

## The open seam: folding the ledger into the circuit

The ledger is the producer's sink. Folding it into `SynapticCircuit` is a
separate task, deliberately not written here because it depends on
`SynapseManager`'s exact observation signature.

Sketch:

```swift
for event in ledger.readAll().events.sorted(by: { $0.timestamp < $1.timestamp }) {
    // feed each observation into the circuit's backward pass,
    // attributing to event.synapseId at event.timestamp
}
```

Keeping the fold separate is the point, not a shortcut: circuit state becomes a
**fold over an immutable log** rather than a field written from three
directions. A producer bug cannot corrupt circuit state, and when the decay
constants are recalibrated the whole history can be re-folded from zero against
the new constants. That property is worth more than the convenience of a
direct call.

---

## Order of operations

1. `swift build`, confirm `--events-summary` runs
2. Sign off `docs/DATA-CLASSIFICATION.md` (D1–D4)
3. Fill the date in `FALSIFICATION.md` and **commit it**
4. Only then install the hook and begin collecting
5. Write the analysis script before day 30; do not peek at outcome measures

Step 3 before step 4 is the whole point. A pre-registration committed after the
first observation is not a pre-registration.

## jj collection (2026-10-29)

Git post-commit hooks do not run for `jj commit`. For a colocated jj checkout,
install the local scheduled collector instead:

```bash
swift build -c release
bash scripts/install-jj-collector.sh "$PWD"
```

The installer pins a copy of the CLI and collector under Application Support;
it does not depend on a terminal's PATH or a mutable build output. A per-user
LaunchAgent checks this checkout every 60 seconds while logged in. No network
is involved. Only `mine() ~ @ ~ (empty() & description(exact:""))` changes are eligible: changes authored under the
configured jj identity, excluding the open working copy. Use ordinary `jj commit`
or `jj new` to finalize a change. Changing jj identity or importing new changes
by that identity changes eligibility; audit those actions during the study.

Installation baselines existing changes without recording them. No missing
historical events are reconstructed. Deduplication uses salted change-ID hashes,
so rewriting a commit does not create another event. Stable opaque event IDs
allow safe retries after a ledger write succeeds but checkpointing is interrupted.
The collector is serialized; `--event-id` deduplication assumes one producer per
ID. A forced kill can leave `state/lock`; inspect for a running collector before
removing that empty directory and retrying.

Health: inspect `instrument/jj-collector/state/last-success`, `stderr.log`, and
`contextsynapse --events-summary`. A successful empty poll updates the health
stamp. A missing CLI or failed ledger write exits nonzero and retains pending
changes for the next poll. Events use commit time and `source: jj-poll`.

Scope is explicitly this checkout only. Other repositories require separate
consent and configuration; this installer refuses a second installation. It
never discovers repositories automatically. Keep the existing Git observer
inactive in this checkout to avoid double collection. Stop collection with:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.contextsynapse.jj-collector.plist"
```

The installed scripts and binary are copies: reviewed updates must be installed
explicitly. Stopping the job retains all ledger and checkpoint data.

Commit events alone have constant utility 1.0 and one repository supplies one
synapse. Collection health is not evidence that P1–P4 are identifiable: varied
outcomes, at least five consented synapses, an offline replay/analysis script,
and the declared data thresholds remain prerequisites. Do not compute outcome
statistics during collection to diagnose these structural limitations.

### Polling boundaries and pause

The query uses both `--ignore-working-copy` and `--at-op @`: the former avoids
working-copy snapshots; the latter refuses ambiguous operation heads instead of
reconciling them. A failed query exits before events/checkpoints advance and
releases the normal invocation lock. The regression harness in
`scripts/ops/test_jj_collector_boundaries.py` creates and asserts two operation
heads before testing this behavior; it also checks that empty undescribed
placeholders remain eligible after receiving content.

Collection is currently paused for attribution and sampling validity. Described
empty changes and merges still need a prospective study eligibility decision;
the technical filter is not a definition of human effort. A forced kill can leave
the lock behind; automatic stale-lock recovery remains unimplemented.
