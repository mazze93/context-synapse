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

Alternative: Cloudflare Pages (`npx wrangler pages deploy public`) works
identically for a static page; the Workers-assets route was chosen so a future
worker script (e.g. a JSON badge endpoint for release status) can share the
project.

**Posture note (HIGH):** review the rendered page before first deploy; no
unreviewed publishes.
