# PR #40 review — 2026-10-29

Reviewed head: 1153ae0ac6da6cbc1dda8d3cf47ed3bf9981b614.
Verdict: changes required; do not merge this revision.

## P1 — Default convenience initializer bypasses directory ownership checks

Sources/SynapseCore/SynapseCore.swift:323-324 delegates directly to the private
storage initializer. It never calls UserStorage.validate, unlike the explicit
user initializer. The SwiftUI AppViewModel calls this unchecked initializer.

Reproduced on the local case-insensitive volume in an isolated temporary root:
seed users/Default with its matching profile and Create weight 2.75. Explicit
SynapseCore(user: "default") throws, but SynapseCore() reads the same weights;
saveWeights then changes the stored Default owner's Create weight to 0.25.
The probe passed without skipping; it asserts the observed bypass, not safety.
No production user data was touched. Source and captured output are alongside
this report. Move the probe into Tests temporarily to rerun it with
swift build && swift test --filter PR40ReviewProbeTests.

The earlier default initializer also lacked ownership checks; this is a remaining
hole in the PR's collision repair, not proof that the PR introduced all of the
underlying behavior. New explicit-user checks do not protect the GUI entry point.

Required repair: apply the same ownership policy to implicit default construction
before profile updates, seeding, or caller writes. Propagate a recoverable error
to the GUI (or implement an explicitly documented, ownership-preserving default
resolution); do not replace this with fatalError. Add coverage for the GUI/default
entry point and conflicting profiles, including case-variant existing owners.

## Reviewed perimeter

Read identifier validation, initializer call paths, profile updating, lighthouse
migration, the frontier-depth correction, CLI user parsing, and their added tests.
The one-line BFS fix correctly avoids incrementing depth for an empty next layer.
The demonstrated ownership gap is sufficient to block approval. This is not an
exhaustive security assessment; symlink races and multi-process storage safety
remain outside this bounded review.
