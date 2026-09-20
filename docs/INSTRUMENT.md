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
