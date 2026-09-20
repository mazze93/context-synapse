# ADR-006: Ledger Separation — Shared Discipline, Separate Stores

**Status:** PROPOSED
**Supersedes:** nothing
**Relates to:** ADR-004 *(Track A — CDL / observability alignment, local-first)*
**Depends on:** `docs/DATA-CLASSIFICATION.md` (D4, R1)

---

## Context

Context Synapse's instrument layer (`EventLedger`) and Stratum's epistemic
decision ledger implement the same architectural pattern: **status is a fold
over an immutable append-only log, never a mutable field.** The similarity is
real and was arrived at independently in both systems, which is weak evidence
that the pattern is correct.

The question raised: should Context Synapse adopt Stratum's ledger wholesale —
one ledger implementation, one store, one substrate?

---

## Decision

**No.** The two systems share a *discipline*, not a *store*, not a *schema*,
and not a runtime. Context Synapse's observation ledger remains local,
Swift-native, and file-backed (`events.jsonl`).

One directional link is adopted: **decisions about Context Synapse are recorded
in Stratum; observations from Context Synapse are not.** Claims flow out;
telemetry does not.

---

## Rationale

### 1. Different object types

| Dimension | Stratum entry | Context Synapse entry |
|---|---|---|
| Nature | authored claim (contestable) | observed event (not contestable) |
| Author | human, deliberate | git hook, automatic |
| Cardinality | ~20 over months | 10^3–10^4 over 30 days |
| Retraction | supersede/reverse is a core operation | never retracted — it happened |
| Lifecycle | permanent by design | deleted at study end (D3) |

A unified schema requires a union type in which most fields are null for most
rows, and retraction semantics that are undefined on the observation side. The
cost is paid in schema complexity to express a similarity that exists at the
pattern layer and disappears at the data layer.

### 2. Compliance boundary

Stratum runs on Cloudflare Workers + Durable Objects. Context Synapse's stated
compliance posture is **no remote transmission, local-only**. Routing
observations to Stratum would transmit behavioral telemetry — commit cadence,
session timing, activity gaps — to hosted infrastructure.

This is not a marginal breach. `DATA-CLASSIFICATION.md` R1 records that a
30-day activity-gap pattern is arguably health-adjacent information about the
subject, accepted *only* on the condition that the data never leaves the device.
Integration voids the condition under which R1 was accepted.

### 3. Precedent already set

ADR-004 (Track A) decided: *"Cloudflare-based CDL infrastructure is
architecturally misaligned"* for exactly this system, and specified local
equivalents for versioning, observability, and session diffing. Full
integration reopens a foreclosed decision. Pattern similarity is not new
information about why the foreclosure was wrong, and therefore does not meet
the bar for reopening.

### 4. Philosophical inversion

Stratum is optimized for durability: decisions must survive, remain auditable,
and never silently change. Context Synapse's thesis is that **permanence is not
a virtue in a cognitive system** — context should decay, rot visibly, and cost
something to retain.

Importing a durability-optimized substrate into a system arguing for principled
forgetting repeats the structural error corrected in ADR-003, where the static
lighthouse floor exempted the most important synapses from the cost structure
the system exists to impose. A component should not be exempt from the
philosophy it serves.

### 5. Runtime mismatch

TypeScript/Workers/Durable Objects versus Swift 6 with strict concurrency and a
zero-external-dependency library target. Sharing an implementation means either
a network boundary (see section 2) or a reimplementation that shares a spec but
no code — which is what is being adopted here, stated honestly.

---

## What does cross the boundary

Decisions, not observations. The following are recorded as Stratum entries:

| Entry | Content |
|---|---|
| `sb-020` | This decision (ledger separation, with reopen conditions) |
| `sb-021` | Data classification sign-off: D1–D4, incl. secure-pride exclusion |
| `sb-022` | **Falsification pre-registration**: P1–P4 with disconfirming thresholds |
| `sb-023` | Study window opened — ledger start timestamp |
| `sb-024` | Outcomes: each of P1–P4 confirmed / falsified / indeterminate |

`sb-022` carries the strongest justification. A pre-registration's entire value
derives from preceding the evidence, and its weakest link is that a git commit
timestamp inside the author's own repository is a timestamp the author
controls. Recording it in a live, externally-visible, append-only ledger is a
materially stronger integrity claim — and it imposes a real cost, since
falsified predictions must then be reported publicly. That cost is the point.

**Before publishing `sb-022`, check it against D1.** The predictions themselves
are safe, but if any synapse label named in them is client-identifying, it goes
public with the entry. Codenames only.

---

## Consequences

**Positive**
- Local-only compliance preserved; R1's acceptance condition remains intact
- ADR-004 not silently reversed
- Observation ledger can be deleted at study end (D3) without touching the
  decision record, which persists — correct lifecycle for each object type
- Pre-registration gains external timestamping

**Negative / accepted**
- The fold-over-log pattern is implemented twice, in two languages. Accepted:
  the alternative is a network boundary this system has foreclosed.
- No unified cross-project view of "everything that happened." Accepted: the
  two logs answer different questions and a merged view would mostly serve
  aesthetics.

**Risk**
- Pattern drift: the two implementations may diverge in ways that make the
  shared discipline nominal rather than real. Mitigation: this ADR is the
  shared spec. Any change to fold semantics in either system is reviewed
  against it.

---

## Rejected alternatives

**Full integration (Context Synapse writes to Stratum).**
Rejected: breaches no-remote-transmission; voids R1's acceptance condition;
reopens ADR-004 without new information.

**Shared ledger library.**
Rejected: TypeScript and Swift 6 have no shared runtime. A common library means
either a service boundary (same objection) or a spec shared without code — which
is what this ADR is.

**One-way event forwarding (observations -> Stratum, aggregate only).**
Rejected for the initial study, and this is the closest call. Aggregates
(commit counts per week) are far less sensitive than raw events. But it still
establishes a transmission path in a system whose compliance line is *no remote
transmission*, and the marginal research value is near zero — the aggregates
are recomputable locally from `events.jsonl` at any time. Building the path
before there is a use for it is the wrong order.

**Adopt Stratum's schema in Context Synapse without adopting its runtime.**
Rejected: imports retraction and supersession semantics that are undefined for
observations, in exchange for a symmetry no consumer requires.

---

## Reopen conditions

This decision should be revisited if **any** of the following becomes true:

1. **Stratum ships a local-only mode** — file- or SQLite-backed, no network
   dependency — in which case sections 2 and 5 both dissolve.
2. **A concrete consumer needs the merged view.** Not "it would be elegant" — a
   named question that cannot be answered from the two logs separately.
3. **The study ends and observations become claims.** Post-study, the surviving
   artifacts are *findings*, which are contestable authored claims and therefore
   genuinely Stratum's object type. Migrating results (not raw events) is in
   scope at that point.
4. **The no-remote-transmission constraint is deliberately revised** with its own
   ADR and a fresh data classification. This ADR must not be used as the vehicle
   for that revision.

Absent one of these, the separation stands.
