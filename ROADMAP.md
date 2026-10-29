# Context Synapse — Roadmap

> Last updated: May 30, 2026  
> Version: 0.3.0-decay (active development)

---

## Architecture decisions

Architecture decisions live in [`docs/adr/`](docs/adr/) — start with the
[ADR index](docs/adr/README.md). Two tracks are recorded there:

- **Foundational & ethics** (Track A): affect-vector consent, the
  operational-context boundary, the Referee protocol, and observability alignment.
- **Bedrock circuit** (Track B): prediction-error propagation, the earned
  lighthouse floor, and the decay amplifier.

---

## v0.2.0 — Bayesian Scaffold ✅ COMPLETE

- [x] SynapseCore: Bayesian priors with Beta updates
- [x] Trigger system (app, time, focus context signals)
- [x] Fault injection (`faultProbability`, `maybeInjectFaults`)
- [x] CLI + SwiftUI app
- [x] Run logging to `~/Library/Application Support/ContextSynapse/`
- [x] Cosine similarity with mismatch tolerance
- [x] Export/Import bundle
- [x] Multi-user profile support
- [x] Two-pass code review complete (folded into CHANGELOG)

---

## v0.3.0 — Decay Layer ✅ RELEASED (2026-09-21)

### Shipped this sprint
- [x] `InteractionRecord.swift` — timestamped event classification + `successWeight` mapping; also houses `SynapseContent` and the `DecayConstants` single source of truth
- [x] `SemanticDistanceStrategy.swift` — protocol + `StructuralHeuristicDistance` (Option A)
- [x] `SynapseWeightState.swift` — full decay math, rot formula, lighthouse floor, cauterization
- [x] `SynapseReferee.swift` — `FunctionalReferee`, `AbrasiveReferee`, `RefereeConfig`, `ContextIntervention`
- [x] `RavenRenderer.swift` — Edgar state machine + cauterize intervention UI
- [x] `Circuit/` + `FaultInjection/` — `SynapticCircuit` bedrock layer, Beta priors, fault-injection suite (#12)
- [x] Architecture decisions recorded — see the [ADR index](docs/adr/README.md)

### Completed v0.3.0 acceptance items
- [x] Unit tests: decay convergence, lighthouse floor invariant (never below 0.4), cauterization threshold (triggers at RotScore ≥ 0.82)
- [x] Extend `RunLog` schema with: decay snapshot, rot score, lighthouse saliency, Referee mode, intervention flag
- [x] Breadcrumb file writer: on session resume, emit lighthouse re-sync line immediately
- [x] `RefereeConfig` round-trip: load/save in dedicated `referee.json` (avoids config overwrite)

---

## v0.4.0 — Rot Layer + Lighthouse

Partially shipped in the v0.3.0 tag. No v0.4.0 release tag exists yet.
Next engineering order: session-diff CLI (read-only), then explicit Shadow
Context forks and promotion with anchor-specific histories. The manager does
not yet apply `cauterizedDecayConstant`; keep that integration open.

- [x] `SynapseManager.swift` — persisted session synapses, explicit lighthouse binding, circuit passes, and RSA epochs (included in v0.3.0; shadow forks remain below)
- [x] Explicit lighthouse designation with `--lighthouse`; inferred anchors are excluded by ADR-001
- [x] CLI lighthouse re-sync breadcrumb (SwiftUI integration remains separate): `⚓ Lighthouse: [description] — saliency [X]% — last touched [N]min ago`
- [ ] Shadow Context fork mechanism (side-quest sandbox, breadcrumb trail)
- Removed: cursor/scroll/webcam inference of operator state (Track A ADR-002 permanent boundary; opt-in does not override it)
- [ ] Session diff CLI command: compare two run logs across decay/rot/lighthouse trajectories
- [ ] `SynapseManager` integration: detect `requiresCauterization`, apply cauterized decay constant
- [ ] Lighthouse promotion workflow: explicit user choice to make side-quest the new primary

---

## v0.5.0 — Referee + Friction UI

- [ ] Friction slider in SwiftUI app (`referee.mode` toggle: functional ↔ abrasive)
- [ ] Context Intervention UI: surface `ContextIntervention.formattedMessage` with action buttons
- [ ] AbrasiveReferee cooldown persistence across sessions
- [ ] `shouldForkToShadowContext` wired to UI — dimmed Lighthouse indicator when side-quest active
- Explicit manual context choices only; operational/affective-state inference remains excluded (Track A ADR-001/002)
- [ ] TF-IDF distance strategy (`TFIDFCosineDistance` — Option B)

---

## v1.0.0 — Production

- [x] Bounded prior growth — mean-preserving evidence cap (200); EMA is not implemented or required for this fix
- [ ] File lock for write safety (single-writer assumption documented, needs enforcement)
- [x] UI error surface for IO failures — save results, ViewModel error state, and banner (ADR-005)
- [ ] Full test harness
- [ ] README and contributor documentation (Show HN ready)
- [ ] arXiv preprint: *Intentional Fragility: Bayesian Context Decay and Semantic Rot in Local-First LLM Orchestration*

---

## Known Issues

| Issue | Severity | Status | Mitigation |
|---|---|---|---|
| Silent write failures | Medium | Resolved | Bool-returning saves, ViewModel error state, SwiftUI banner; ADR-005 documents verification limits |
| Schema drift: key changes break region vectors | Medium | Open | Use `canonicalVector(for:)` to regenerate after schema changes |
| Unbounded prior growth | Low | Resolved | Mean-preserving cap on alpha + beta at 200 |
| Concurrency: multi-process write collision | Low | Open | Add file lock — single-writer assumption documented |
| `assemblePrompt` CLI wiring | High/Bug | ✅ Resolved | CLI calls `core.assemblePrompt(...)` correctly (`main.swift`) |
| No per-synapse decay tracking | High | ✅ Addressed | `SynapseWeightState` (v0.3) |
| No Lighthouse | High | ✅ Addressed | `SynapseWeightState.isLighthouse` + `lighthouseFloor` (v0.3) |
| No Referee | High | ✅ Addressed | `SynapseReferee` protocol + two implementations (v0.3) |
| Operational context layer | Intentional | Permanent | ADR-002: permanent design boundary |

---

## Synapse Network — Contributors

This project is built using a Human-in-the-Loop (HITL) architecture.
The core logic is a synthesis of human neurodivergent intent and LLM collaborative reasoning.

**Biological Logic (steering, intent, architecture):** @mazze93  
**Synthetic Logic (Bayesian math, Referee protocols, structural scaffolding):** Gemini (co-architect, v0.2), Claude/Perplexity (co-architect, v0.3+)

> *Context Synapse is what AI and neurodivergent intelligence have in common:  
> both are brilliant, distracted, and prone to losing the forest for the trees.  
> This is the bridge.*
