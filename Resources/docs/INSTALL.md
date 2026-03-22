# ContextSynapse — Install & Build Guide (Bayesian + Fault Injection Edition)

This guide describes building the ContextSynapse package (with Bayesian priors and fault injection).

## Requirements
- macOS 13+ (recommended for SwiftUI Canvas)
- Xcode 14+ or Swift 5.8 toolchain
- Optional: Apple Developer account to sign/notarize .app

## Quick build (CLI)
```bash
swift build
.build/debug/context_synapse "Summarize my notes" --app Notes
```

## Quick build (release)
```bash
swift build -c release
cp .build/release/context_synapse /usr/local/bin/context_synapse
```

## Feedback (Bayesian)
- CLI supports `--feedback good` or `--feedback bad`. Each call increments the corresponding Beta prior (alpha / beta) and recomputes numeric weights stored in `~/Library/Application Support/ContextSynapse/config.json`.
- Prior counts are naive integer increments; consider adding decay if you expect non-stationary behavior.

## Fault injection (resilience testing)
- The UI includes a slider and a "Disintegrate Sky Plates" button that will simulate small corruptions.
- CLI supports a per-run flag: `--fault-prob 0.0` to temporarily set `faultProbability` for that run.
- Default is 0.0 (disabled).

## Files & locations
- `~/Library/Application Support/ContextSynapse/config.json` — weights + priors + triggers
- `~/Library/Application Support/ContextSynapse/regions.json` — region vectors
- `~/Library/Application Support/ContextSynapse/logs/` — run logs

## Notes
- If you change weight keys (add/remove intents/tones/domains), regenerate region vectors using canonicalVector helper or reset regions to defaults.
- See `docs/REVIEW.md` for a two-pass review and known issues.


## Tests

Run the unit test suite:

```bash
swift test
```

## CI

A GitHub Actions workflow is included at `.github/workflows/ci.yml` to build and test on macOS runners.
