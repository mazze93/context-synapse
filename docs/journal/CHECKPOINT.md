# Checkpoint — resume here if the session drops

Branch: `claude/v0.3-ci-repair-and-p1`

- [x] A. Scaffold (journal + branch)
- [x] B. CI repair (.vscode untrack + SynapticCircuitTests rename + real
      CircuitEdge.withWeight identity bug found & fixed)
- [x] C. Lighthouse migration + tests
- [x] D. DecayWeightTests.swift
- [x] E. RunLogDecay.swift (+ typed run-log context wiring)
- [x] F. RefereeConfigStorage.swift (+ new `--referee` CLI flag)
- [x] G. Strict concurrency flag (+ @Sendable AIClient closures, stderr global fix)
- [x] H. Close out — CLAUDE.md reconciled; CLI verified end-to-end
      (lighthouse → breadcrumb → prompt → run-log snapshot → resync)
- [x] I. Landing page (`site/public/index.html`) — verified in Chrome, all
      sections render; preview artifact published for user review
- [x] J. Cloudflare scaffolding (`site/wrangler.toml`, Workers static assets;
      deploy notes in `site/README.md`); deploy itself deferred to user

## To resume
Read PLAN.md then DECISIONS.md; continue at first unchecked phase.
`swift build && swift test --parallel` is the green gate for every phase.

## Deferred / needs user
- Cloudflare deploy: `wrangler login` + DNS record on mazzeleczzare.com
  (suggested host: contextsynapse.mazzeleczzare.com). HIGH posture — user
  reviews the page before it goes live.
