# Data Classification — Instrument Layer

**Status:** PROPOSED — requires sign-off before the hook is installed on
any secure-pride-adjacent repository.

**Scope:** the `post-commit` observer, the `--record` CLI verb, and
`events.jsonl`. Does not cover `config.json`, `lighthouse.json`, or run logs,
which predate this layer.

**Escalation note:** the standing directive requires classification *before*
generating data-handling code. This document is that classification, written
with a default-deny posture: fields are excluded unless there is a stated
research reason to keep them. Where a judgment call was made, it is marked
**DECISION REQUIRED**.

---

## Threat model in one line

The realistic adversary is not a remote attacker. It is **future disclosure of
a local file** — a backup sync, a screen-share, a support bundle, a subpoena,
or a laptop handed to someone else — combined with the fact that commit
messages and file paths in secure-pride work can name clients, individuals,
infrastructure, and in the worst case imply SOGI-related affiliations of
people who never consented to being in your dataset.

The design consequence: **third parties who appear in your commit history are
not the subject of this study and must not be identifiable in its artifacts.**

---

## Classification table

| Field | Class | Handling | Rationale |
|---|---|---|---|
| Event type (`git.commit`) | Non-sensitive | Stored plain | Required for the success-weight mapping |
| `successWeight` | Non-sensitive | Stored plain | Derived from event type |
| Timestamp (commit time, ISO-8601) | **Low-sensitive** | Stored plain | Required for all decay math. See residual risk R1 |
| Changed-file **count** | Low-sensitive | Stored plain | Weak activity magnitude signal; no names |
| Repo identity | **Sensitive** | SHA-256(salt : remote-URL), truncated 64 bits | Needed for stable attribution; raw URL names clients |
| Synapse label (`.contextsynapse`) | **Operator-controlled** | Stored plain, charset-restricted | You choose it; treat as public. See D1 |
| Commit message | **Sensitive** | **NEVER CAPTURED** | Free text; highest disclosure risk; no research value |
| File paths / names | **Sensitive** | **NEVER CAPTURED** | Names clients, people, infrastructure |
| Branch names | **Sensitive** | **NEVER CAPTURED** | Frequently encode ticket IDs and client names |
| Commit SHA | Sensitive | **NEVER CAPTURED** | Directly re-identifies the commit and everything in it |
| Author name / email | **Sensitive** | **NEVER CAPTURED** | Identifies people; co-authors never consented |
| Diff content | **Sensitive** | **NEVER CAPTURED** | May contain secrets |
| Salt | **Secret** | `0600`, per-install, never transmitted | Compromise makes tokens dictionary-attackable |

**Enforcement is structural, not procedural.** All hashing happens in the shell
hook before any process boundary is crossed. The `contextsynapse` binary never
receives raw values, and `--repo-token` rejects any argument that is not hex —
so a raw path cannot be silently accepted even if a future producer passes one.

---

## Storage

- **Path:** `${CONTEXT_SYNAPSE_HOME:-~/Library/Application Support/ContextSynapse}/`
- **Ledger:** `events.jsonl`, `0600`
- **Salt:** `instrument/salt`, `0600`, directory `0700`
- **Encryption at rest:** inherited from FileVault. No application-layer
  encryption. **DECISION REQUIRED (D2).**
- **Transmission:** none. No network path exists in this layer.
- **Retention:** indefinite by default. **DECISION REQUIRED (D3).**
- **Deletion path:** `rm events.jsonl` is sufficient and complete — the ledger
  is the sole store of instrument data. Deleting the salt additionally makes
  historical tokens unlinkable to any repo, which is a useful one-way privacy
  ratchet if the study ends.

---

## Decisions required

**D1 — Synapse labels.** `.contextsynapse` contents are stored verbatim and
would appear in any published CSV. If you label a thread `acme-migration`, the
client is in your dataset in cleartext.
-> Recommended: **use project-internal codenames only** (`stratum-ingress`,
`brick-2`), never client-identifying strings. Treat the label as if it will be
published, because it may be.

**D2 — Application-layer encryption.** FileVault covers the at-rest case for a
powered-off machine. It does not cover a running machine, a Time Machine
backup, or an iCloud-synced Application Support directory.
-> Recommended for the study period: **rely on FileVault, and verify that
`~/Library/Application Support/ContextSynapse` is excluded from any cloud sync.**
Application-layer encryption would prevent the plaintext analysis this study
requires and is disproportionate given no raw identifiers are stored.

**D3 — Retention.** -> Recommended: **delete the ledger at study end**, retaining
only the derived aggregate statistics that appear in the paper. Set a calendar
reminder at day 30; indefinite retention of behavioral telemetry with no active
research use is exactly the pattern this project criticizes elsewhere.

**D4 — Secure-pride repositories.** The hook is opt-in per repository, so the
default is already exclusion.
-> Recommended: **do not install on secure-pride repos for the initial study.**
The token is salted and the paths are never captured, so the marginal risk is
low — but the marginal *research* value is also low, since commit cadence there
is not distinguishable from other work. This mirrors the MacProbe ingress block:
when value is low and sensitivity is high, the default is no.

---

## Residual risks (accepted, documented)

**R1 — Timestamp inference.** Commit timestamps are a behavioral trace. A
30-day ledger reveals working hours, sleep patterns, and activity gaps. For a
subject whose neurodivergence is a topic of the research, an activity-gap
pattern is arguably health-adjacent information about the author.
*Accepted because:* the subject is the sole author and consents; timestamps are
irreducibly required for decay math; the data never leaves the device.
*Condition:* published figures must use **elapsed time from ledger start**, not
wall-clock timestamps, and must not include a time-of-day axis.

**R2 — Salt compromise.** Anyone with the salt and a guess at your repo list can
confirm which repos are in the ledger. Not reversible without candidate
guessing, but confirmable.
*Mitigation:* `0600`, per-install, never in any export. `--export-events` emits
tokens but never the salt.

**R3 — Correlation with public GitHub activity.** Commit counts and timestamps
could be joined against public commit history to re-identify which repo a token
corresponds to.
*Accepted because:* the linkage reveals only what is already public.
*Condition:* do not publish the raw event-level CSV; publish aggregates only.

**R4 — Reactivity.** Being observed may change commit behavior. This is a
validity limitation, recorded in `FALSIFICATION.md` (Bias Controls), not a
privacy issue.

---

## Sign-off

- [ ] D1 synapse-label policy accepted
- [ ] D2 encryption posture accepted
- [ ] D3 retention period set: __________
- [ ] D4 secure-pride exclusion confirmed
- [ ] R1 publication constraint (elapsed time only) accepted

Signed: ______________________  Date: ______________
