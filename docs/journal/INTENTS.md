# Intents — stated before contact, append-only

One row per task, written at Phase 0 before real work. `outcome` is set at
close: `as-stated` (shipped what was asked), `diverged` (shipped something
else — say what in the last column), `abandoned` (stopped without shipping).
A row left `—` means the session dropped before closing itself out.

Pipe-delimited. Write any literal `|` in prose as `or` or `\|`.

| Date | Restated ask | Load-bearing assumption (+ check) | Outcome | Notes / divergence |
|------|--------------|----------------------------------|---------|--------------------|
| 2026-09-02 | Review comment on `deploy-site.yml:80`: pin mutable action tags that receive privileged Cloudflare creds to full commit SHAs; same for `actions/checkout@v7` in `cut-release.yml`. Follow-up: pin the remaining mutable tags in `ci.yml`, `codeql.yml`, `release.yml` too. | The `deploy-site.yml` / `cut-release.yml` pins the comment named were still un-pinned. CHECK: **false** — already done in `3a0dd08` (session-start state), the comment was filed against pre-`3a0dd08` code. Real work = the follow-up on the other three workflows. | as-stated | Original comment needed no fix (verified, reported). Follow-up shipped as `0008a9c` on `feat/site-deploy-release-sync`: all 8 `uses:` across ci/codeql/release pinned to SHAs (checkout v7.0.1, upload-artifact v7.0.1, download-artifact v8.0.1, codeql-action v4.37.9), SHAs resolved live via GitHub gateway. Delivery cost: heavy jj working-copy thrash (see DECISIONS 2026-09-02) — recovered, no work lost. |
| 2026-11-04 | Close study run 1 (expired 2026-11-03, 16 events/1 synapse/3 days) and pre-register run 2 with Mazze's attribution directive: an observation = a change Mazze directed and signed off on; add the sign-off filter to the jj collector with a test. No collection, no other repos. | Sign-off trailers are routinely present, so the rule yields data. CHECK: **false** — 3 of 90 non-bot commits on `main` carry it; v2 must make stamping a precondition. | — | |
