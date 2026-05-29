# ADR-002: Bidirectional Prediction-Error Propagation

**Status:** Proposed — May 27, 2026
**Author:** Mazze LeCzzare Frazer
**Supersedes:** W_base(s) static constant assumption (undocumented, pre-v0.3)

---

## Context

The decay formula specifies `W_base(s)` as a per-synapse base weight:

```
W_decay(s, t) = W_base(s) · e^(−λ(s) · t) · U(s, t)
```

Prior to v0.3, `W_base(s)` was a calibrated constant — set at initialization, never
revised by observed evidence. This is a design error with two concrete consequences:

1. **The system cannot learn.** It can forget (decay) but cannot revise beliefs about
   which synapses are actually useful based on whether predictions about their utility
   were correct.

2. **`connectivity_factor(s)` has no concrete implementation.** The decay formula
   references it in `λ(s)` but no subsystem computes it. It is an architectural
   placeholder treated as a known value.

The Bayesian label applied to the system is currently aspirational. No prior update
mechanism exists. No prediction error is computed or used as a learning signal.

---

## Decision

Replace `W_base(s)` with a **mutable Beta-distributed prior** (`Prior` struct).
Implement a **SynapticCircuit** actor that:

1. Runs a **forward pass** — generates predictions from priors, computes
   connectivity factors from edge topology, returns `ForwardPassResult`.

2. Runs a **backward pass** — records observations, computes `|predicted - observed|`
   as prediction error, updates priors via conjugate Bayesian update, propagates
   uncertainty through edges.

3. Provides **`lighthouseFloor(synapseID:isLighthouse:)`** — returns a dynamic floor
   derived from `prior.mean × 0.4`, not a static constant (see ADR-003).

4. Provides **`injectFault(intoSynapse:severity:liveMutation:)`** — runs controlled
   adversity against nodes, measures propagation depth, returns `FaultInjectionReport`
   for calibration use.

**Beta distribution rationale:**
- Bounded `[0,1]` — matches the utility score domain exactly.
- Conjugate prior for Bernoulli observations — interaction success scores
  (`successᵢ` table) map directly to update inputs without transformation.
- Computationally trivial — no sampling required; `E[Beta] = α/(α+β)`.
- Evidence weight is transparent — `α + β` directly reads how much history
  the prior reflects.

**Connectivity factor implementation:**
`connectivity_factor(s)` is now derived from the circuit's edge topology:
average incident edge weight across all edges (in + out) for a given node.
Computed in `SynapticCircuit.forwardPass()` and returned in `ForwardPassResult`.

**Updated decay formula:**
```
W_decay(s, t) = prior.mean(s) · e^(−λ(s,t) · Δt) · U(s, t)

λ(s, t) = λ_base
         · (1 − connectivity_factor(s))   ← from ForwardPassResult
         · rot_multiplier(s)               ← unchanged from spec
         · (1 + predictionError(s) · 1.2) ← NEW: ADR-004
```

---

## Consequences

**Positive:**
- System now learns: priors update from observed interaction outcomes.
- Prediction error is a first-class citizen with architectural home.
- `connectivity_factor(s)` has a concrete, testable implementation.
- Decay rate is dynamically modulated by prediction accuracy.
- FaultInjectionSuite can calibrate `ROT_LAMBDA_AMPLIFIER` empirically.

**Risks and mitigations:**

| Risk | Mitigation |
|------|-----------|
| Prior poisoning: adversarial observations inflate low-quality synapse priors | Learning rate decay (η → 0 as passCount grows); evidence weight cap at 100 |
| Error flooding: high-frequency backward pass with all-zero observations collapses priors | Minimum alpha floor (1.0); backward pass ordering guard |
| Schema drift: prior values mis-calibrated after `canonicalVector()` regeneration | Schema version hash in `CircuitSnapshot`; stale-prior protocol on hash mismatch |

---

## Rejected Alternatives

**EMA smoothing over W_base:**
Exponential moving average is a signal-averaging mechanism, not a belief-revision
mechanism. It responds to recency, not to the discrepancy between expected and
observed utility. The core thesis requires the system to learn from surprise.
EMA does not compute surprise.

**Gaussian prior:**
Unbounded. Requires clamping to `[0,1]`. Loses the conjugate update property.
Computationally equivalent complexity for worse domain fit.

---

## Integration Points

`SynapseWeightState` (v0.3 target) consumes this layer:
```swift
let forwardResult = await circuit.forwardPass()
let W_base = forwardResult.predictions[synapseID] ?? 0.5
let connFactor = forwardResult.connectivityFactors[synapseID] ?? 0.0
let predError = await circuit.predictionError(for: synapseID)
```

`Referee` / `EdgarIntervention` consumes `BackwardPassResult.epistemicallyUnstableNodes`
to drive `ContextIntervention` generation.
