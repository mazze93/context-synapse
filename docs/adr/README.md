# Architecture Decision Records

Context Synapse keeps **two ADR tracks**. They were numbered independently and
historically reuse the numbers 002–004, so disambiguate an ADR reference by its
**domain**, not the number alone. Source-code comments cite these IDs; see the
"Known wart" note at the end.

## Track A — Foundational & ethics decisions

These govern consent, scope boundaries, and the human-in-the-loop posture. They
are recorded inline (no separate files yet).

| ID | Decision | Summary |
|----|----------|---------|
| ADR-001 | Affect vector update strategy | **Asynchronous.** Affect surfaces as available context only; lighthouse anchors are set on confirmed user choice, never via automatic inference. |
| ADR-002 | Operational context layer | **Out of scope (permanent).** The Referee models distraction, not cognitive collapse. No surveillance or inference of operator state. |
| ADR-003 | Referee protocol | `FunctionalReferee` (default, silent) + `AbrasiveReferee` (opt-in). Abrasive activates on distraction, not collapse. |
| ADR-004 | CDL / observability alignment | Local-first. Observability via the extended RunLog; no cloud dependency added. |

Cited in code as `ADR-001` (affect vector) and `ADR-002` (operational-context
boundary) in `SynapseWeightState.swift` and `SynapseReferee.swift`.

## Track B — Bedrock layer decisions (v0.3 circuit)

These govern the `SynapticCircuit` math. Each has a full record file.

| ID | Decision | Record |
|----|----------|--------|
| ADR-002 | Bidirectional prediction-error propagation | [ADR-002-bidirectional-prediction-error-propagation.md](ADR-002-bidirectional-prediction-error-propagation.md) |
| ADR-003 | Lighthouse floor mutability (earned, not granted) | [ADR-003-004-lighthouse-floor-and-decay-amplifier.md](ADR-003-004-lighthouse-floor-and-decay-amplifier.md) |
| ADR-004 | Decay amplifier (prediction-error → λ) | [ADR-003-004-lighthouse-floor-and-decay-amplifier.md](ADR-003-004-lighthouse-floor-and-decay-amplifier.md) |

Cited in code as `ADR-002/003/004` in `Circuit/CircuitTypes.swift` and
`Circuit/SynapticCircuit.swift`. See also [INTEGRATION.md](INTEGRATION.md) for the
wiring recipe between the circuit and the decay layer.

## Known wart

Tracks A and B both use 002–004. Source comments depend on the current numbers,
so a renumber is deferred until it can be done atomically across code and docs.
Until then, read any `ADR-00X` reference in its domain context — referee/ethics
(Track A) versus circuit/math (Track B).
