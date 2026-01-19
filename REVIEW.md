# ContextSynapse: Two-Pass Review & Troubleshooting Notes

This document summarizes a two-pass code design review performed on the Bayesian+Fault scaffold, lists potential issues, and describes deliberate breakpoints (controlled fragility) that are included to exercise resilience.

## What I Changed (Summary)

- **Added Bayesian feedback** using Beta priors for intents/tones/domains
- Priors are persisted inside `Weights.priors` and map to numeric weights in range [0.1, 3.0]
- The CLI and UI can apply feedback which increments alpha/beta and recomputes weights
- **Introduced faultProbability** and `maybeInjectFaults(...)` to simulate small corruptions
- Made cosine similarity tolerant to mismatched vector lengths (compute over shared prefix)
- **UI additions**: fault slider, "Disintegrate Sky Plates" button, prior probability display beside sliders

## Two-Pass Review: What Was Checked

### Pass 1: Static/code-level

- Verified types and Codable conformance for all persisted structures (Weights, Priors, Prior, Region)
- Confirmed all file paths for config/regions/logging use `~/Library/Application Support/ContextSynapse`
- Ensured all public APIs used by the UI/CLI are present: `applyFeedbackUpdate`, `computeRegionSimilarities`, `mapPriorToWeight`
- Checked for obvious force-unwraps or unsafe array operations → replaced with safe indexing or length checks

### Pass 2: Runtime/behavioral scenarios

- **Startup**: missing config.json or regions.json is seeded with defaults. ✅ OK
- **Fault injection**: toggling faultProbability in UI applies controlled corruption without crashing (vectors are padded/truncated safely)
- **Feedback loop**: applying repeated positive feedback converges prior probability towards 1.0 and increases mapped numeric weight
- **Edge cases**:
  - Zero-length region vectors → handled by cosineSimilarity returns 0.0
  - Mismatched vector lengths → computed over shared prefix (robust fallback)
  - Disk write failures → writes use atomic option; errors are swallowed but not fatal (consider surfacing in UI later)

## Known Potential Issues & Mitigations

1. **Silent write failures**: we attempt atomic writes but don't surface permission errors
   - **Mitigation**: add UI error reporting and checks for Application Support permissions

2. **Schema drift**: if you change weight keys (add/remove intents), stored regions.json vectors will mismatch
   - **Mitigation**: `canonicalVector(for:)` helper included; regenerate regions after schema changes

3. **FaultProbability misuse**: accidentally setting a high probability (e.g., 0.9) can heavily degrade similarity scores
   - **Mitigation**: UI slider caps at 0.9 and the heatmap scales values; add a "safe mode" to clamp at 0.25 if desired

4. **Priors accumulation**: using naive integer increments means priors grow without bound (this is expected for a simple Bayesian counter)
   - For very long-lived systems, consider decay or bounding alpha+beta (e.g., use an exponential decay of counts)

5. **Concurrency**: simultaneous writes from multiple app instances may collide
   - **Mitigation**: single-writer assumption; use a small locking mechanism (e.g., a file lock) if needed in multi-process scenarios

## Deliberate Breakpoints (Intentional Fragility)

**Purpose**: make the system testable under small failures so that it hardens via exposure.

- **Fault injection point**: `SynapseCore.faultProbability`. When > 0, `maybeInjectFaults(into:)` will:
  - add tiny noise to vectors
  - zero random slices
  - or scale-down subsets of elements
  
  These are non-fatal and intentionally small — they simulate "sky plate disintegration" and let the UI/algorithms show graceful degradation.

- **Truncation tolerance**: cosineSimilarity computes over the shared prefix instead of failing for length mismatch, enabling partial-data operation

- **Safe logging**: log writes use atomic write but don't crash on failure; instead they silently fail (configurable later)

## Recommendations & Next Steps

- **Add unit tests** covering:
  - Bayesian update behavior and weight mapping boundaries
  - Fault injection scenarios with multiple probabilities
  - Region vector regenerations after schema changes

- Add a lightweight file-lock or serialized queue for write operations if you plan to use this across multiple processes

- Expose a decay parameter for priors to avoid unbounded alpha+beta growth

- Surface config/IO errors in the UI with actionable guidance

---

### Optional Next Actions

If you want, I can:
- Produce the unit test harness and a set of example CLI runs demonstrating weight convergence
- Tighten the priors update (add decay cap)
- Produce a small GitHub Actions CI that builds the package and runs lints
