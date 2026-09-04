# Issue #32 — v0.3 milestone execution plan

> Working plan for [#32](https://github.com/mazze93/context-synapse/issues/32):
> *lock decay equations, versioned calibration artifact, ADR-006 affect.*
> Drafted 2026-08-31. This is a **plan**, not a decision record — decisions land
> in `docs/journal/DECISIONS.md`, ADRs in `docs/adr/`. Owner: @mazze93.

## The principle that changes how we operate

#32's core move is **three evidence layers that must not collapse into each
other**, and **only two of them gate a release**:

```
  Implementation invariants (I2–I7)  ──┐
  Calibration artifact (repro + safe) ─┼──►  GATES v0.3 software release (CI)
                                        │
  Falsification study (P1–P4, N-of-1) ─┴──►  DOES NOT gate. A falsified
                                             prediction is a research finding →
                                             ADR review, never a silent
                                             threshold retune or exclusion.
```

That inversion is the operating-model change: empirical results can neither
block a ship nor be "fixed" by moving goalposts. `FALSIFICATION.md` supersedes
I2–I7 *naming* where they overlap (P1≈I3, P3≈I2, P4≈I5) but does **not** replace
the code-level invariant tests.

## Dependency & state check (verified 2026-08-31)

| #32 needs | State on `main` (`ae7c40f`) |
|---|---|
| Append-only verify path (**PR #28**) | ✅ merged (`2ea3215`) — **guard P1 fixed** on branch `fix/journal-append-guard-p1` (this work): NUL-delimited archive iteration + regression harness `scripts/ops/test_check_journal_append.sh` |
| `calibration/decay-params.json` | ❌ not present |
| `FALSIFICATION.md` + `data/events.jsonl` | ❌ neither — **clean slate, no study data** (freeze-before-data still achievable) |
| `scripts/analyze_falsification.py` + lockfile | ❌ not present |
| The four release-gating constants | hardcoded literals (locations below) |
| ADR-006 | next number free (002, 003-004, 005 all present on `main` — verified) |

**Constant locations on `main`** (the `chore/v0.3-cleanup-and-doc-sync` branch
that deletes `DecayConstants.swift` is a *dead, abandoned* split queued for
deletion — read constants from these canonical locations, not that branch):

- `rotLambdaAmplifier = 1.5` — `Sources/SynapseCore/InteractionRecord.swift:92`
- `errorDecayAmplifier = 1.2` (γ) — `Sources/SynapseCore/Circuit/CircuitTypes.swift:73`
- `lighthouseFloorCeiling = 0.4` (c₀) — `Sources/SynapseCore/Circuit/CircuitTypes.swift:78`
  (and `lighthouseFloor = 0.4` — `InteractionRecord.swift:100`)
- `lambdaBase` (λ) — **locate**; referenced in `docs/adr/INTEGRATION.md` recipe

## Phased execution

### Phase 0 — Make custody trustworthy ✅ DONE (this branch)
Fixed the #28 guard word-splitting P1 (`check_journal_append.sh:52`) so a dated
decision in a space-named archive file can no longer be deleted while the guard
passes. Added `scripts/ops/test_check_journal_append.sh` (6-case matrix incl. the
P1 case); proven to discriminate (buggy guard → exit 0, fixed → exit 1).
**Next:** wire the test into CI alongside the existing guard step.

### Phase 1 — Freeze the preregistration ⚠️ HUMAN-GATED, before any data
Draft `FALSIFICATION.md` (P1–P4 hypotheses, utility rubric 0.0/0.5/1.0 + reason
codes, missing-observation rules, ledger + custody schema). **@mazze93** commits
it and runs `git tag -a falsification-v1` while `data/events.jsonl` has **zero**
records, then stamps the SHA/tag back into the file. Irreversible by design.
*Claude drafts; mazze freezes.*

### Phase 2 — Calibration artifact lifecycle (GATES ship)
`calibration/decay-params.json`: `schemaVersion`, `artifactVersion`, the four
params (range-validated: λ,γ,rot-amp ≥ 0; c₀ ∈ (0,1]), `provenance`
(`fixtureHash`, `harnessVersion`, `gitSha`, `generatedAt`, `objectiveScore`),
`previousArtifactVersion`. Add a `SynapseCore` loader: reject malformed/out-of-
range → fall back last-validated (`calibration/history/`) → compiled defaults;
expose active version; non-sensitive diagnostics only. **Remove the λ/γ/rot-amp/c₀
literals** and source them from the artifact (wiring in `INTEGRATION.md`). CI:
harness reproduces within tolerance.

### Phase 3 — Code oracles I2–I7 (GATES ship)
New file under `Tests/` (per the repo rule — do not append to
`BayesianConvergenceTests.swift`). Fixtures declare μ̄, α, β, Rot, e(s),
passCount, Δt. Deterministic assertions I2–I7; **property test for I5** (Rot ⊥ ε
randomized independently). Boundaries: e∈{0,1}, Rot∈{0,sat}, pass∈{19,20,21},
cap∈{exact,+1}. Reuse the deterministic `MaxDistanceStrategy` pattern from
`DecayWeightTests.swift`. Float tol 1e-9 relative unless documented.

### Phase 4 — State migration
Persist `calibrationArtifactVersion` on session/synapse records; lazy recompute
on next observe; downgrade reads without silent re-decay; surface mismatch.
Document in `INTEGRATION.md`; load old fixtures in tests.

### Phase 5 — Analysis lock + ledger (before study window opens)
`scripts/analyze_falsification.py` + `requirements.lock`/`uv.lock` + fixture-
ledger tests proving each P-fail branch reachable + a hash-chain verify command
that fails on reorder/alter/delete (monotonic `seq`, `previousHash`/`recordHash`,
one write path, verification result folded into analysis output). Single
invocation, seeded. No cloud-sync/telemetry of event contents by default.

### Phase 6 — ⚠️ ADR-006 affect — STOP, decision required
`ADR-006`. #32 scopes it as *flag default-off, zero persistence, no prior nudge*
— consent-gated affect vector (ADR-001), **not** operational inference. But the
project's **HARD STOP** (ADR-002, and `CLAUDE.md` "Scope Constraint") forbids
inferring cognitive/affective/collapse state as an operational input. The ADR
must open by stating **which side of that boundary it lands on** and why
default-off/zero-write keeps it there. Privacy tests: flag off ⇒ zero writes,
TTL enforced, fail-closed. **Do not write a line of ADR-006 without @mazze93's
explicit boundary ruling.** Coordinate first with peer sessions `creative-32`
and `Audit ledger authentication`, which may already hold live #32 work
(flagged 2026-08-31; confirm before drafting to avoid duplicate ADRs).

### Phase 7 — CI + release notes
CI runs unit + property + calibration-repro + privacy — **explicitly not** P1–P4
outcomes. Release notes name behavioral changes + `artifactVersion`. Then cut
`v0.3.0` via the `cut-release` workflow (once the site-deploy token from the
parallel thread is provisioned, the release also syncs the site).

## Critical path to a shippable v0.3

```
Phase 0 ✅ → 2 → 3 → 4 → 6 → 7        (software release; CI-gated)
         └─ 1 → 5 → 30-day study run   (parallel; NEVER gates the ship)
```

## Coordination notes (2026-08-31)

- `chore/v0.3-cleanup-and-doc-sync` (`b5031c4e`) is **dead** — abandoned
  DecayConstants/SynapseContent split, 0 source added to main, queued for
  deletion (DECISIONS.md 2026-08-18). Do not plan against its layout.
- Live #32 code ownership possibly with `creative-32` / `Audit ledger
  authentication` — confirm before Phases 5–6.
- GitHub MCP gateway dropped credentials mid-session; reconnect before GitHub
  API ops (per global `CLAUDE.md`).
