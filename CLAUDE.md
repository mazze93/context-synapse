# ContextSynapse — Claude Context

Local-first Bayesian prompt orchestration engine. Status: **experimental/research-grade**.
Not a consumer product — built for neurodivergent developers exploring human-machine context negotiation.

## Stack
- **Language**: Swift 5.8+, macOS 13+
- **Components**: `SynapseCore` (Bayesian engine), CLI (`contextsynapse`), SwiftUI GUI (`ContextSynapseApp`)
- **Build**: `swift build -c release` | **Test**: `swift test`
- **Config**: `default_config.json` (Bayesian priors, fault_probability)
- **State**: JSON persistence (export/import via CLI)

## Key Architecture
- `SynapseCore.swift` — core engine: `applyFeedbackUpdate()`, `computeRegionSimilarities()`, `loadOrCreateDefaultWeights()`
- `ContextRegion` — weighted regions tracking intent, domain, tone
- Cosine similarity for context matching
- Deterministic + testable; intentional fault injection for resilience

## Design Rules
- **Local-first is non-negotiable** — no required cloud dependency
- **Interpretability first** — all weights/priors visible, no opaque heuristics
- **Fragility is intentional** — controlled weak points expose assumptions
- Prompting treated as cognitive process, not string concatenation

## Repo
- GitHub: `mazze93/context-synapse`
- Local: `/Users/daedalus/Code/ContextSynapse`
