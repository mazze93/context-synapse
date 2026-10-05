# ADR-005: Verifying the GUI Write-Failure Surface

**Status:** Accepted — July 18, 2026
**Author:** Mazze LeCzzare Frazer (with Claude)
**Relates to:** Known Issue "Silent write failures in GUI" (resolved); the
`saveWeights`/`saveRegions`/`logRun` → `Bool` change and `AppViewModel.lastError`
banner.

---

## Context

The "silent write failures in GUI" fix added a three-link chain:

```
real disk-I/O failure
  → SynapseCore.save*/logRun returns false        (Link 1 — branching logic)
  → AppViewModel.lastError is set                  (Link 2 — reflection)
  → ContentView renders the warning banner         (Link 3 — SwiftUI view)
```

A touchstone pass on the fix flagged that **none of these links was exercised
against an actual disk failure** — the unit tests proved the happy path and that
the code compiles, but a fix whose entire purpose is "make failures visible"
that is never tested *on a failure* is the classic hollow checkmark. Each link
has a different cost/value profile, and testing them uniformly is wasteful.

## Decision

Test the links that carry logic; document the rest as deferred or as inherent
perimeter. Do not build UI-automation infrastructure for a one-line binding.

### Link 1 — `save*` returns `false` on real failure — **DONE (this PR)**

This is the only link with real branching logic and the one most likely to
regress silently (e.g. a future refactor that swallows the `catch`). Verified
directly:

- Added a `baseOverride: URL? = nil` dependency-injection seam to
  `SynapseCore.init`. `nil` preserves the production `~/Library/Application
  Support` location — no behaviour change for normal callers.
- `Tests/PersistenceFailureTests.swift` points storage at a temp directory made
  read-only (`chmod 0555`), inducing a genuine `EACCES` on the atomic write, and
  asserts `saveWeights`/`saveRegions`/`logRun` all return `false`. A writable-root
  control proves the failure is caused by permissions, not by the seam itself.
- Guarded with `XCTSkipIf(geteuid() == 0, …)`: **root bypasses POSIX permission
  bits**, so under a root test runner the write would succeed and the test would
  pass without proving anything — itself a touchstone trap (the verifier's own
  blind spot). Skipping is the honest outcome there.

### Link 2 — `false` propagates to `AppViewModel.lastError` — **DEFERRED**

`saveConfig()` is trivial reflection
(`lastError = (okWeights && okRegions) ? nil : "…"`). Testing it in isolation
requires a seam (`AppViewModel` depends on a `Persisting` protocol —
`saveWeights/saveRegions/logRun -> Bool` — that `SynapseCore` already satisfies;
a `FailingStub` returns `false`). The blocker is structural: `AppViewModel` lives
in the `ContextSynapseApp` **executable** target, which the test target cannot
import. Closing this link is worth doing **when** the view model (or its
error-deriving logic) is moved into a library target for other reasons; it is not
worth a refactor on its own. Tracked as a v1.0 hygiene item.

### Link 3 — the SwiftUI banner actually renders — **INHERENT PERIMETER**

`if let error = vm.lastError { … }` rendering into a visible view can only be
verified by driving the built app (XCUITest / UI automation). High cost, near-zero
marginal value over Link 2 — the binding is about as simple as SwiftUI gets. Left
as documented perimeter; not planned.

## Consequences

- `SynapseCore.init` gains one optional parameter. It is a legitimate DI seam
  (temp-dir isolation, failure injection), not a test-only backdoor into
  production logic, and it composes with the existing UUID-folder test convention.
- The persistence layer now has real negative-path coverage; a regression that
  re-swallows write errors will fail `PersistenceFailureTests`.
- The remaining perimeter (Links 2–3) is explicit and bounded, not silently
  assumed.

## Reversal

Drop the `baseOverride` parameter and delete `Tests/PersistenceFailureTests.swift`.
The production storage path is unchanged either way.
