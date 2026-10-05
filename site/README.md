# ContextSynapse landing page

Self-contained static page (`public/index.html` — no external assets, fonts,
or scripts). Terminal-native aesthetic built from the product itself: Edgar's
actual ASCII frames, the RavenRenderer state palette, the real decay math, and
a genuine CLI transcript.

## Local preview

```sh
open public/index.html            # or any static server
```

## Deploy — Cloudflare Workers static assets

```sh
cd site
npx wrangler login                # once
npx wrangler deploy               # publishes contextsynapse-site worker
```

Then attach the custom domain (dashboard → Workers & Pages →
`contextsynapse-site` → Settings → Domains & Routes → Add → Custom domain):

    contextsynapse.mazzeleczzare.com

Cloudflare creates the DNS record automatically when the zone
(`mazzeleczzare.com`) is on the same account.

## Automated deploy + release sync

`.github/workflows/deploy-site.yml` deploys on push to `main` touching `site/**`,
on each published GitHub Release, and on manual dispatch. Add two repo secrets to
activate it (until then the deploy step skips green, never red):

    CLOUDFLARE_API_TOKEN    # Workers Scripts:Edit for the account
    CLOUDFLARE_ACCOUNT_ID   # the Cloudflare account id

**Staying in sync with releases** works two ways:

- **Live** — the Worker (`src/index.js`) serves `GET /api/release`, the latest
  GitHub Release as edge-cached JSON. The page fetches it and updates the nav
  badge without a redeploy.
- **Baked** — on a release, the deploy workflow injects the tag into the badge's
  `__RELEASE_TAG__` placeholder as a static baseline (shown before the fetch
  resolves). Locally / with no release, the badge stays hidden.

Cut a release from the Actions tab via **Cut release** (`cut-release.yml`): give
it `vX.Y.Z`, it tags `main`, and that triggers `release.yml` (build + publish)
and `deploy-site.yml` (site resync).

Alternative host: the page is fully self-contained, so Cloudflare Pages
(`npx wrangler pages deploy public`) or any static host works — you'd only lose
the `/api/release` Worker endpoint (the baked badge still works).

**Posture note (HIGH):** review the rendered page before first deploy; no
unreviewed publishes.
