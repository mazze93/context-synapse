# Pre-Registered Predictions — N-of-1 Study, Run 2

**Status:** PRE-REGISTRATION. Committed **before** any run 2 observation.
Its value is destroyed if edited after data exists; corrections are appended
as dated lines in the logs below, never made in place.

**Registered:** 2026-11-04
**Supersedes:** run 1 (`FALSIFICATION.md`), closed 2026-11-04 as a collection
failure, not analysed. Run 1 rows stay in the ledger as collected and are
**excluded** from run 2.
**Analyst / subject:** Mazze LeCzzare Frazer. Same person; see Bias controls.

---

## What changed from run 1, and why

Run 1 failed on collection, not on its predictions:

- The git `post-commit` observer never fires under jj, which is the fleet
  workflow. The repaired jj poller (#50) was then paused because `mine()`
  matches author identity, not agency, and most work is agent-executed.
- Extension 1 expired with 16 events, 1 synapse and 3 active days, against
  thresholds of ≥300, ≥5 and ≥20.

Run 2 keeps the run 1 **predictions, thresholds, bias controls and reporting
rule unchanged**. It changes only what counts as an observation, which
synapses are observed, and when the window starts.

## Construct: directed work

An observation is a unit of **work Mazze directed and owns**, agent-executed
or not. In the subject's words (2026-11-04): "my decisions should be recorded
as a directive which demonstrated my accountability and presence".

**Eligibility rule** (mechanical, metadata-only, no inference about the
person). A finalized jj change is one observation when all of these hold:

1. Authored under the configured jj identity (`mine()`).
2. Its description carries a `Signed-off-by: Mazze LeCzzare Frazer` line.
3. It is not committed by `noreply@github.com`. Those are squash-merge copies
   of work already observed locally.
4. It is not the open working copy, and not an empty undescribed placeholder.

Implemented in `scripts/collect-jj-events.sh`. Every clause is covered by
`scripts/ops/test_jj_collector.sh` and `test_jj_collector_boundaries.py`.

**What the ledger can and cannot show.** The sign-off line is usually written
by an agent at Mazze's direction. The ledger therefore evidences
directed-and-owned work. It does not evidence keyboard presence, effort,
time-on-task or any internal state, and must not be read as such.

**Collection precondition.** On 2026-11-04, 3 of 90 non-bot commits on
`main` carried the trailer. An unsigned change is simply not an observation,
and it is not back-filled later. Agents must stamp every commit for the
window to accumulate data. Low counts caused by unstamped work are a
collection finding, reported as such.

## Synapses

A synapse is one repository (salted repo token), or a `.contextsynapse`
label within one. The minimum is ≥5 distinct synapses, as in run 1.

The synapse set is **fixed at collection start**: the jj-colocated
repositories whose collectors are loaded at that moment, named in the
collection log below. Repositories added after collection start are excluded
from confirmatory analysis.

## Window

- **Ledger start:** the first eligible event at or after the collection-start
  timestamp recorded below.
- Events timestamped before this file's registration commit are never part
  of run 2, whatever their eligibility.
- **Analysis window:** 30 calendar days from ledger start.
- Extensions follow the run 1 rule: 7-day increments, each logged below,
  never on the basis of results. Inspecting row counts for threshold checks
  is permitted.

## Minimum data requirements

Unchanged from run 1: ≥300 events, ≥5 distinct synapses, ≥20 active days of
30, and ≥20 events on the least-active analysed synapse.

## Predictions

P1–P4 are carried over **verbatim** from `FALSIFICATION.md` (§ P1 through
§ P4): statistics, thresholds, disconfirming outcomes and interpretations.
They are not restated here, so that two copies can never diverge. Any change
to them requires a new pre-registration.

## Bias controls and reporting

Unchanged from `FALSIFICATION.md` § Bias controls and § Pre-committed
reporting rule. Two additions for run 2:

6. **Sign-off reactivity.** Because the sign-off line is the observation
   trigger, the decision to stamp a commit is itself observable behavior.
   Stamping policy may not change mid-window to raise or lower counts. Any
   change is logged below with a date and treated as a protocol deviation.
7. **Domain boundary.** This ledger never ingests Meridian affect check-ins
   or any affective or cognitive-state signal, and nothing here infers such
   state (ADR-002, hard stop). The context-synapse ↔ Meridian cross-domain
   comparison gets its own pre-registration, committed before Meridian's
   model ships.

---

## Collection log (append-only)

- [ ] Collection start — date/time: ______ · loaded collectors (synapses): ______

## Extensions log (append-only)

## Deviations log (append-only)

---

## Outcome record — fill in AFTER the window closes

| ID | Prediction | Result | Statistic | Notes |
|----|-----------|--------|-----------|-------|
| P1 | Amplifier specificity | [ ] confirmed [ ] falsified [ ] indeterminate | rho = ____ | |
| P2 | Rank crossover | [ ] confirmed [ ] falsified [ ] indeterminate | n = ____ | |
| P3 | Prior stickiness | [ ] confirmed [ ] falsified [ ] indeterminate | | |
| P4 | Rot/error independence | [ ] confirmed [ ] falsified [ ] indeterminate | rho = ____ | |
