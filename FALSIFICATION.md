# Pre-Registered Predictions — N-of-1 Longitudinal Study

**Status:** PRE-REGISTRATION. Commit this file **before** the first observation
is recorded. Its value is entirely destroyed if edited after data exists.

**Registered:** _______________ (fill in, then commit)
**Ledger start:** first `timestamp` in `events.jsonl`
**Analysis window:** 30 calendar days from ledger start
**Analyst:** Mazze LeCzzare Frazer (also the subject — see Bias Controls)

---

## Why this file exists

The synthetic study produced two quantitative claims under stationary latent
utilities and i.i.d. noise. Real interaction traces are non-stationary and
bursty. The synthetic result is therefore a *prediction* about real data, not
evidence about it.

The subject and the analyst are the same person, and that person has spent
months arguing this architecture is correct. That is the single largest threat
to the validity of anything that follows. The only defense available is to fix
the predictions, the thresholds, and the disconfirming outcomes in advance, in
a version-controlled file with a commit timestamp that precedes the data.

**If a prediction below fails, that is the finding.** It goes in the paper as a
result, not in a drawer. A falsified decay model is a more valuable contribution
than an unfalsifiable one.

---

## Minimum data requirements

Analysis does not proceed unless all of these hold. Stopping early to look at
results and then continuing is a garden-of-forking-paths violation.

| Requirement | Threshold | Rationale |
|---|---|---|
| Total events | >= 300 | Below this, per-synapse counts are too thin for rank statistics |
| Distinct synapses | >= 5 | Cross-synapse comparison is the whole design |
| Active days | >= 20 of 30 | Guards against a single-week burst standing in for a month |
| Events on the least-active analysed synapse | >= 20 | Avoids conclusions drawn from noise |

If thresholds are unmet at day 30, extend the window in **7-day increments** and
record each extension below. Do not extend on the basis of having peeked at
results.

Extensions log:
- [ ] Extension 1 — reason: ______________ new end date: ______

---

## P1 — Amplifier specificity

**Synthetic result:** the error amplifier removed weight 13.4x more aggressively
from the overconfident-useless class than from the calibrated-low class.

**Prediction on real traces:** among synapses with >= 20 observations, the
correlation between a synapse's mean early prediction error (first 10
observations) and the amplifier's weight suppression on that synapse
(gamma=1.2 minus gamma=0, replayed offline over the same ledger) is positive,
with Spearman rho >= 0.4.

**Falsified if:** rho < 0.2, or rho is negative, or the 95% bootstrap CI on rho
includes 0.

**Interpretation if falsified:** prediction error on real traces is dominated by
observation noise rather than by miscalibration, and `errorDecayAmplifier` is
penalizing variance rather than overconfidence. ADR-004 would require revision
or withdrawal.

---

## P2 — Rank crossover

**Synthetic result:** the overconfident-useless synapse began with the highest
weight and crossed below the modest-useful synapse at pass 53.

**Prediction on real traces:** at least one synapse that starts in the top
tercile by initial prior mean and ends in the bottom tercile by observed mean
utility will be overtaken in final weight by a synapse that started lower and
delivered higher.

**Falsified if:** no such crossover occurs in the window, **or** crossovers
occur in both directions at similar rates (i.e. the ordering is churning
randomly rather than correcting).

**Interpretation if falsified:** either real work does not produce
misdesignated synapses at a detectable rate — in which case the mechanism
solves a problem that does not occur — or prior stickiness dominates entirely
over a 30-day horizon and the correction is too slow to matter in practice.

---

## P3 — Prior stickiness (directional)

**Synthetic result:** a Beta(8,2) prior fell 0.80 -> 0.60 over 60 passes;
0.41 at 400 passes.

**Prediction on real traces:** for any synapse designated lighthouse whose
observed utility runs below 0.4, the prior-derived floor
(`prior.mean x 0.4`) declines monotonically over the window, and the decline is
slower than the decline in that synapse's raw observed mean utility.

**Falsified if:** the floor fails to decline at all despite sustained low
observations (the prior is effectively frozen — ossification is real and the
evidence-weight cap is set wrong), **or** the floor tracks observed utility
essentially instantaneously (there is no meaningful prior inertia and the Beta
machinery is doing no work a moving average wouldn't do).

**Note:** P3 has *two* disconfirming directions. Both matter. The second would
indicate the Bayesian layer is ceremonial.

---

## P4 — Rot / decay independence (not covered synthetically)

The simulation deliberately held rot constant (rho=1) to isolate the error
channel. Real traces will not.

**Prediction:** rot score and prediction error are weakly correlated at most
(|Spearman rho| < 0.5) across synapse-days — they are intended to capture
*independent* failure modes (semantic drift vs. predictive miscalibration).

**Falsified if:** |rho| >= 0.7, indicating the two terms are measuring
substantially the same thing and lambda(s,t) is double-counting one signal.

**Interpretation if falsified:** ADR-004's rejected alternative ("fold
prediction error into rot scoring") was the correct call after all, and the
two-term decay constant should collapse to one.

---

## Bias controls

1. **Analysis script written before unblinding.** The script that computes
   P1–P4 is committed before any results are viewed. Running it is a single
   invocation; no interactive exploration precedes it.
2. **No mid-window peeking at outcome measures.** Checking that data is *being
   collected* (`--events-summary` row counts) is permitted. Computing
   prediction errors, weights, or correlations before day 30 is not.
3. **Synapse labels fixed in advance where possible.** Renaming a
   `.contextsynapse` thread mid-window splits one synapse into two and must be
   logged here:
   - [ ] Relabel event — date: ______ old: ______ new: ______
4. **Reactivity is acknowledged, not controlled.** Knowing that commits are
   observed may change commit behavior (a Hawthorne effect on the subject).
   This cannot be blinded in an N-of-1 design with an instrumented author. It
   is a stated limitation, not a solved problem, and must appear as such in
   the paper.
5. **Sparse-day handling declared in advance:** days with zero events are
   retained as genuine zero-activity days, not dropped. Dropping them would
   inflate apparent consistency.

---

## Pre-committed reporting rule

All four predictions are reported in the paper with their outcomes, whether
confirmed, falsified, or indeterminate for lack of data. No prediction may be
dropped from the write-up after the fact. If a post-hoc analysis is run, it is
labelled **exploratory** and may not be presented as confirmatory.

---

## Outcome record — fill in AFTER the window closes

| ID | Prediction | Result | Statistic | Notes |
|----|-----------|--------|-----------|-------|
| P1 | Amplifier specificity | [ ] confirmed [ ] falsified [ ] indeterminate | rho = ____ | |
| P2 | Rank crossover | [ ] confirmed [ ] falsified [ ] indeterminate | n = ____ | |
| P3 | Prior stickiness | [ ] confirmed [ ] falsified [ ] indeterminate | | |
| P4 | Rot/error independence | [ ] confirmed [ ] falsified [ ] indeterminate | rho = ____ | |
