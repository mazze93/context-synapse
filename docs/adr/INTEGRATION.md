# Integration Notes — v0.3 Bedrock Layer
## Context Synapse · May 27, 2026

---

## What This Adds (New Files Only)

```
Sources/ContextSynapse/
├── Circuit/
│   ├── CircuitTypes.swift          ← Prior, SynapticNode, CircuitEdge,
│   │                                  CircuitConstants, all output structs
│   └── SynapticCircuit.swift       ← The circuit actor
└── FaultInjection/
    └── FaultInjectionSuite.swift   ← Calibration suite + CalibrationReport

docs/adr/
├── ADR-002-bidirectional-prediction-error-propagation.md
└── ADR-003-004-lighthouse-floor-and-decay-amplifier.md
```

**No existing files are modified.** SynapseCore, RavenRenderer, and all existing
type definitions are untouched.

---

## Known Bug to Fix Before Merge

`RavenRenderer.swift`, line 37 — double quote on `circuitBlue`:
```swift
// BUG: extra closing quote
static let circuitBlue = "\u{001B}[38;5;39m""   // ← fix to single "
```
Not in scope for this PR. File separately.

---

## SynapseWeightState Integration (v0.3 target)

When implementing `SynapseWeightState`, consume the circuit like this:

```swift
// In SynapseWeightState.computeWeight(for synapse: Synapse) async -> Double

let forwardResult = await circuit.forwardPass()

let W_base        = forwardResult.predictions[synapse.id] ?? 0.5
let connFactor    = forwardResult.connectivityFactors[synapse.id] ?? 0.0
let predError     = await circuit.predictionError(for: synapse.id)
let floor         = await circuit.lighthouseFloor(for: synapse.id, isLighthouse: synapse.isLighthouse)

// Updated λ(s,t):
let lambda = lambdaBase
    * (1.0 - connFactor)
    * rotMultiplier(synapse)
    * (1.0 + predError * CircuitConstants.errorDecayAmplifier)

let W_decay = W_base * exp(-lambda * deltaT) * utilityScore(synapse)
let W_final = max(floor, W_decay * (1.0 - alpha * rotScore(synapse)))
```

---

## Backward Pass Wiring (SynapseManager, v0.4 target)

After each interaction event, record the observation:

```swift
// Map your successᵢ table to observations:
// git commit   → 1.0
// file save    → 0.9
// build pass   → 0.85
// build fail   → 0.2
// keystroke    → 0.1
// window leave → 0.0

let result = await circuit.backwardPass(observations: [
    affectedSynapse.id: successWeight(for: event)
])

// Surface instability to Referee:
if !result.epistemicallyUnstableNodes.isEmpty {
    referee.flagForIntervention(nodeIDs: result.epistemicallyUnstableNodes)
}
```

---

## Fault Injection Run (Calibration)

```swift
// Run once per 50 passes OR on Referee instability event:
let suite = FaultInjectionSuite(circuit: circuit)
let report = await suite.runFullSuite()
print(report.formattedSummary)

// Apply recommendations:
// Update CircuitConstants.errorDecayAmplifier with report.recommendedRotLambdaAmplifier
// Update ROT_CAUTERIZE_THRESHOLD with report.recommendedCauterizeThreshold
```

---

## Suggested Commit Message

```
feat(circuit): add SynapticCircuit bedrock layer (v0.3)

Replaces static W_base(s) constant with mutable Beta-distributed prior.
Implements bidirectional prediction-error propagation substrate.

- CircuitTypes.swift: Prior, SynapticNode, CircuitEdge, CircuitConstants,
  ForwardPassResult, BackwardPassResult, CircuitSnapshot, FaultInjectionReport,
  CalibrationReport
- SynapticCircuit.swift: actor with forward/backward pass, connectivity cache,
  dynamic lighthouse floor, fault injection (snapshot-first)
- FaultInjectionSuite.swift: calibration suite producing CalibrationReport

ADR-002: W_base → mutable Beta prior + circuit topology for connectivity_factor
ADR-003: lighthouse floor = prior.mean × 0.4 (earned, not granted)
ADR-004: prediction error added as dynamic decay amplifier in λ(s)

No existing files modified. SynapseWeightState integration: see INTEGRATION.md.

MAESTRO threats documented: T1 (prior poisoning), T2 (error flooding),
T3 (lighthouse ossification), T4 (timing side-channel), T5 (schema drift).
```
