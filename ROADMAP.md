# Context Synapse — Roadmap

> Last updated: May 4, 2026  
> Version: 0.3.0-decay (active development)

---

## Architecture Decision Log

### ADR-001: Affect Vector Update Strategy — DECIDED
**Decision:** ASYNCHRONOUS  
Affect vector surfaces as available context only. Lighthouse anchors set on confirmed user choice, never via automatic inference. Synchronous updates allow passive inference to trigger Lighthouse pinning without user action — violates the detection/inference/autonomy boundary established in the Breakthrough Artifact. Consent model holds across Secure Pride deployment contexts.

### ADR-002: Operational Context Layer — PERMANENT BOUNDARY
**Decision:** OUT OF SCOPE (permanently)  
The Referee has no model for collapse — the state where the lighthouse is visible, the goal is clear, and the person cannot execute. Not distraction. Degraded operating system. The operational context layer introduces surveillance risk, inference danger for marginalized populations, and shame amplification. This system is for context management, not mental health support. This boundary is not a roadmap gap — it is a design principle.

### ADR-003: Referee Protocol — DECIDED
**Decision:** FunctionalReferee (default) + AbrasiveReferee (user-initiated opt-in)  
User stated preference for AbrasiveReferee. AbrasiveReferee is NOT the default. Requires explicit `referee.mode = "abrasive"` in config.json. AbrasiveReferee activates on distraction, not collapse. See ADR-002.

### ADR-004: CDL / Observability Alignment — DECIDED
**Decision:** Local-first aligned. CDL (Patrick Debois) is DevOps for prompts; Context Synapse is an OS for context. Complementary, not competing. Observability via extended RunLog (decay/rot snapshots, lighthouse saliency, Referee mode, intervention flag). No cloud dependency added.

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
- [x] REVIEW.md: two-pass code review complete

---

## v0.3.0 — Decay Layer 🔧 IN PROGRESS

### Shipped in this sprint (May 4, 2026)
- [x] `InteractionRecord.swift` — timestamped event classification, `successWeight` mapping
- [x] `SynapseContent.swift` — immutable content descriptor (file refs, function names, text)
- [x] `DecayConstants.swift` — single source of truth for all decay/rot constants
- [x] `SemanticDistanceStrategy.swift` — protocol + `StructuralHeuristicDistance` (Option A)
- [x] `SynapseWeightState.swift` — full decay math, rot formula, lighthouse floor, cauterization
- [x] `SynapseReferee.swift` — `FunctionalReferee`, `AbrasiveReferee`, `RefereeConfig`, `ContextIntervention`
- [x] ADR-001 through ADR-004 documented

### Remaining v0.3.0
- [ ] **FIX (HIGH/BUG):** `assemblePrompt` already exists in `SynapseCore` — verify it is called correctly from CLI entry point (`Sources/contextsynapse/`)
- [ ] Unit tests: decay convergence, lighthouse floor invariant (never below 0.4), cauterization threshold (triggers at RotScore ≥ 0.82)
- [ ] Extend `RunLog` schema with: decay snapshot, rot score, lighthouse saliency, Referee mode, intervention flag
- [ ] Breadcrumb file writer: on session resume, emit lighthouse re-sync line immediately
- [ ] `RefereeConfig` round-trip: load/save from `default_config.json`

---

## v0.4.0 — Rot Layer + Lighthouse

- [ ] `SynapseManager.swift` — coordinates session state, lighthouse designation, shadow context forking
- [ ] Lighthouse designation at session start (explicit or inferred from first high-utility interaction)
- [ ] Lighthouse re-sync UI message: `⚓ Lighthouse: [description] — saliency [X]% — last touched [N]min ago`
- [ ] Shadow Context fork mechanism (side-quest sandbox, breadcrumb trail)
- [ ] Async affect vector integration (ADR-001): cursor scanpath, scroll cadence, webcam pupil proxies
- [ ] Session diff CLI command: compare two run logs across decay/rot/lighthouse trajectories
- [ ] `SynapseManager` integration: detect `requiresCauterization`, apply cauterized decay constant
- [ ] Lighthouse promotion workflow: explicit user choice to make side-quest the new primary

---

## v0.5.0 — Referee + Friction UI

- [ ] Friction slider in SwiftUI app (`referee.mode` toggle: functional ↔ abrasive)
- [ ] Context Intervention UI: surface `ContextIntervention.formattedMessage` with action buttons
- [ ] AbrasiveReferee cooldown persistence across sessions
- [ ] `shouldForkToShadowContext` wired to UI — dimmed Lighthouse indicator when side-quest active
- [ ] Async affect conditioning in trigger weight pipeline (ADR-001 full implementation)
- [ ] TF-IDF distance strategy (`TFIDFCosineDistance` — Option B)

---

## v1.0.0 — Production

- [ ] Prior decay — exponential moving average for alpha/beta (fixes unbounded growth, see REVIEW.md)
- [ ] File lock for write safety (single-writer assumption documented, needs enforcement)
- [ ] UI error surface for IO failures (REVIEW.md known issue: silent write failures)
- [ ] Full test harness
- [ ] README and contributor documentation (Show HN ready)
- [ ] arXiv preprint: *Intentional Fragility: Bayesian Context Decay and Semantic Rot in Local-First LLM Orchestration*

---

## Known Issues (from REVIEW.md)

| Issue | Severity | Status | Mitigation |
|---|---|---|---|
| Silent write failures | Medium | Open | Add UI error reporting, check AppSupport permissions on init |
| Schema drift: key changes break region vectors | Medium | Open | Use `canonicalVector(for:)` to regenerate after schema changes |
| Unbounded prior growth | Low | Open | Add EMA decay to alpha/beta — target v1.0 |
| Concurrency: multi-process write collision | Low | Open | Add file lock — single-writer assumption documented |
| `assemblePrompt` CLI wiring | High/Bug | Verify | Already defined in SynapseCore — confirm CLI entry point calls it |
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
