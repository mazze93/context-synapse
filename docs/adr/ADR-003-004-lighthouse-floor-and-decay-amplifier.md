# ADR-003: Lighthouse Floor Mutability

**Status:** Proposed — May 27, 2026
**Author:** Mazze LeCzzare Frazer
**Supersedes:** `floor(s) = 0.4 if isLighthouse, else 0.0` (hard constant, pre-v0.3)

---

## Context

The current lighthouse floor is a hard constant:
```
W_final(s, t) = max( floor(s), W_decay(s,t) · (1 − α · RotScore(s)) )
floor(s) = 0.4 if isLighthouse, else 0.0
```

This creates a permanent exemption from the cost structure the system is designed
to enforce. The core thesis — intentional fragility, information should earn its
place — is violated for exactly the synapses designated as most important.

Two concrete failure modes:

1. **Lighthouse misdesignation has no recovery path.** If the system is wrong about
   which synapses should be lighthouses (designation error), the hard floor prevents
   decay from correcting it. The error is permanent until manually overridden.

2. **Lighthouse designation is unauditable over time.** A lighthouse designated in
   session 1 with a strong rationale may be irrelevant by session 100. The floor
   persists regardless. There is no signal that the lighthouse has become stale.

This is the paternalism trap ADR-001 correctly rejected at the affect vector level,
applied to the weight floor. "Anchors that move without consent aren't anchors" —
but anchors that *cannot* move even when consent is revoked aren't anchors either.

---

## Decision

Replace the static lighthouse floor with a **prior-derived dynamic floor**:

```
floor(s) = prior.mean(s) · LIGHTHOUSE_FLOOR_CEILING
where LIGHTHOUSE_FLOOR_CEILING = 0.4   (constant ceiling, preserved from spec)
```

**Effect:**
- A newly designated lighthouse synapse with a strong prior (mean ≈ 0.8) starts
  with a floor of ≈ 0.32, rising toward 0.4 as evidence accumulates.
- If the prior erodes (repeated prediction failures), the floor drops with it.
- The lighthouse remains the lighthouse — high-prior designation is preserved.
- But the floor is **earned**, not granted. Misdesignation is self-correcting.

**Lighthouse designation is still meaningful.** `Prior.lighthouse(confidence:)` creates
a Beta prior with high mean and high evidence weight. The designation creates a strong
starting belief. It does not create an uncorrectable permanent exemption.

---

## Consequences

**Positive:**
- Lighthouse misdesignation becomes self-correcting through the prediction-error
  feedback loop (ADR-002).
- The lighthouse floor now participates in the system's intentional fragility design
  rather than exempting itself from it.
- `lighthouseFloor(for:isLighthouse:)` is testable: floor should decrease under
  sustained low-utility observations.

**Changed behavior:**
- Lighthouse re-sync UI message (`⚓ Lighthouse: …`) should surface prior strength,
  not just designation status. Suggested: `⚓ [label] — confidence: 78%`.

**Risks:**
- A high-traffic session could erode a legitimately important lighthouse prior
  through a cluster of failed interactions. Mitigated by evidence weight accumulation:
  a well-supported prior (high α+β) resists single-session erosion.

---

## Rejected Alternative

**Keep hard floor, add manual override mechanism:**
Manual override still requires active human intervention to correct a misdesignated
lighthouse. The point of the Bayesian layer is that correction should emerge from
evidence, not require the operator to notice and act. A hard floor with manual
override is a consent wall, not a safety net.

---

---

# ADR-004: Prediction Error as Decay Amplifier

**Status:** Proposed — May 27, 2026
**Author:** Mazze LeCzzare Frazer
**Modifies:** λ(s) dynamic decay constant formula

---

## Context

The current dynamic decay constant:
```
λ(s) = λ_base · (1 − connectivity_factor(s)) · rot_multiplier(s)
```

The `rot_multiplier(s)` component captures semantic drift from the lighthouse.
But no component captures the *predictive accuracy* of the synapse's prior.

A synapse that consistently overestimates its own utility is not captured by
rot scoring (which measures semantic distance) or connectivity (which measures
relational embedding). It is a distinct failure mode: the synapse is confident,
present, and wrong about how useful it will be.

This is the worst case for context pollution: a context chunk that displaces
more useful content while delivering less value than predicted.

---

## Decision

Add prediction error as a dynamic multiplier to the decay constant:

```
λ(s, t) = λ_base
         · (1 − connectivity_factor(s))
         · rot_multiplier(s)
         · (1 + predictionError(s) · errorDecayAmplifier)

where errorDecayAmplifier = 1.2 (CircuitConstants.errorDecayAmplifier)
```

**Effect:**
- A synapse with zero prediction error: no change to decay rate.
- A synapse with prediction error 0.5: decay rate multiplied by 1.6.
- A synapse with prediction error 1.0: decay rate multiplied by 2.2.

**Why 1.2 as the coefficient:**
This is a starting value, not a permanent constant. `FaultInjectionSuite.runFullSuite()`
produces `CalibrationReport.recommendedRotLambdaAmplifier` which should replace
this value after each calibration run. The initial 1.2 is intentionally moderate —
it penalizes inaccurate priors without catastrophically accelerating decay in
new sessions where all priors are weakly calibrated.

---

## Consequences

**Positive:**
- Synapses earn their decay resistance through predictive accuracy, not just recency.
- The system's intentional fragility philosophy is consistently applied:
  context must be useful *and* accurately self-represented to persist.
- Calibration is empirical: `FaultInjectionSuite` can recommend the coefficient
  value rather than requiring manual tuning.

**Watch-out:**
Early sessions (passCount < 20) have no prediction history. All prediction errors
are computed against the default prior prediction (0.5). This produces artificially
elevated errors in the bootstrapping period. Recommendation: apply a bootstrapping
discount — use `errorDecayAmplifier × 0.5` for the first 20 passes.

**Relationship to ROT_LAMBDA_AMPLIFIER:**
The existing `ROT_LAMBDA_AMPLIFIER = 1.5` in the spec is a static multiplier applied
to rot scoring. ADR-004 does not replace it — it adds a separate, dynamically computed
term driven by prediction error rather than semantic distance. Both terms now contribute
to λ(s), capturing two independent failure modes: semantic drift (rot) and predictive
inaccuracy (error amplifier).

---

## Rejected Alternative

**Fold prediction error into rot scoring:**
Rot scoring measures semantic distance from the lighthouse — a spatial/topological
concept. Prediction error measures calibration quality — a temporal/statistical concept.
These are orthogonal signals. Folding one into the other would produce a combined
score that cannot be individually audited or independently calibrated.
