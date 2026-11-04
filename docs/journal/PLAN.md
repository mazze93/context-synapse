# Sprint plan — Study v2 pre-registration (Phase A)

Branch: `study/preregistration-v2` (off `main` @ `cf9e814`) · Started 2026-11-04

> Supersedes the 2026-07-18 known-issues sweep plan (merged; detail in git
> history — do not reopen).

## Ask (restated)

Run 1 of the N-of-1 study ended without usable data: the git observer never
fired under jj, the repaired collector was paused over agent/human
attribution, and Extension 1 expired 2026-11-03 with 16 events on 1 synapse
over 3 active days. Close run 1 honestly, and pre-register run 2 before any
new observation, with Mazze's attribution directive built in: an observation
is a change Mazze **directed and signed off on**, agent-authored or not.

## Files in scope

- `FALSIFICATION.md` — append-only: one "run 1 closed" line in the extensions
  log. Hypotheses, thresholds, and existing lines untouched.
- `docs/study/PREREGISTRATION-v2.md` — new.
- `scripts/collect-jj-events.sh` — sign-off filter in the collection revset.
- `scripts/ops/test_jj_collector.sh` — unsigned-never / signed-once test.
- `docs/journal/{PLAN,CHECKPOINT,DECISIONS,INTENTS}.md` — journal.

Out of scope (Phase B/C, separate go-ahead): colocating other repos,
installing or loading any collector, Meridian's comparison protocol.

## Phases (each finish-and-commit-and-push)

- **A0. Scaffold** — this plan, DECISIONS entry, INTENTS row, CHECKPOINT.
- **A1. Close run 1** — `FALSIFICATION.md` append + DECISIONS entry.
- **A2. Sign-off filter** — collector revset + test; `swift build`, collector
  tests, journal guard green.
- **A3. Pre-register v2** — `docs/study/PREREGISTRATION-v2.md`, dated, then PR.

## Constraints

- No collection until v2 is committed and pushed (pre-registration precedes data).
- No ingestion of Meridian affect data; no state inference (ADR-002, hard stop).
- DECISIONS.md append-only (guard enforced). Existing ledger rows preserved.
