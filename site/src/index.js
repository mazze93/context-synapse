// ContextSynapse landing-page Worker.
//
// Two jobs:
//   1. GET /api/release → the latest GitHub Release as small JSON, edge-cached
//      for 5 minutes. The page fetches this to stay in sync with releases
//      without a redeploy.
//   2. Everything else → the static asset (public/), via the ASSETS binding.
//
// No secrets: the GitHub REST call is unauthenticated (public repo, generous
// enough for a cached marketing endpoint). Returns tag:null gracefully when no
// Release has been published yet (404 from GitHub).

const REPO = "mazze93/context-synapse";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/api/release") {
      const cache = caches.default;
      const cached = await cache.match(request);
      if (cached) return cached;

      let payload;
      try {
        const gh = await fetch(
          `https://api.github.com/repos/${REPO}/releases/latest`,
          { headers: { "User-Agent": "contextsynapse-site", "Accept": "application/vnd.github+json" } }
        );
        if (gh.ok) {
          const j = await gh.json();
          payload = { tag: j.tag_name, name: j.name, url: j.html_url, published_at: j.published_at };
        } else {
          payload = { tag: null, reason: `github ${gh.status}` };
        }
      } catch (e) {
        payload = { tag: null, reason: "fetch failed" };
      }

      const res = new Response(JSON.stringify(payload), {
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "public, max-age=300",
          "access-control-allow-origin": "*",
        },
      });
      ctx.waitUntil(cache.put(request, res.clone()));
      return res;
    }

    return env.ASSETS.fetch(request);
  },
};
