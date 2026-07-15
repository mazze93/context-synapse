# Checkpoint — resume here if the session drops

Branch: `claude/v0.3-ci-repair-and-p1`

- [x] A. Scaffold (journal + branch)
- [x] B. CI repair (.vscode untrack + SynapticCircuitTests rename + real
      CircuitEdge.withWeight identity bug found & fixed)
- [ ] C. Lighthouse migration + tests
- [ ] D. DecayWeightTests.swift
- [ ] E. RunLogDecay.swift
- [ ] F. RefereeConfigStorage.swift
- [ ] G. Strict concurrency flag
- [ ] H. Close out (CLAUDE.md, verify, push, PR)

## To resume
Read PLAN.md then DECISIONS.md; continue at first unchecked phase.
`swift build && swift test --parallel` is the green gate for every phase.

## Deferred / needs user
- (none yet)
