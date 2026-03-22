# Bayesian Convergence Demo (CLI)

This demo shows how repeated feedback updates shift Beta priors and mapped weights.

## Run

```bash
./scripts/demo_convergence.sh
```

## Expected behavior

- After 30 positive updates (`--feedback good`) on `intent=Create`, posterior `p` rises and mapped weight increases.
- After 30 negative updates (`--feedback bad`), posterior `p` drops and mapped weight decreases.

## Files touched

This demo updates:

`~/Library/Application Support/ContextSynapse/config.json`

Back it up first if you want to preserve your current priors.
