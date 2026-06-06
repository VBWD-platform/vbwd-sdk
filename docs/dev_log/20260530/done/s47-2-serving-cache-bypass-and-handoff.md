# S47.2 — Serving: nginx cache-bypass + SPA hand-off + asset stamping

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Depends on:** [S47.1](s47-1-seo-pipeline-and-prerender.md) · **Status:** DRAFT — 2026-06-03
**Repos:** `vbwd-fe-user-plugin-cms` (SPA hand-off), `vbwd-fe-user` (entry + asset-manifest read), `vbwd-demo-instances` (nginx **templates only** — never prod instance trees), `vbwd-plugin-cms` (asset-stamp source + deploy hook).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: fe-user `npm run lint && npm run test` GREEN; serving e2e GREEN against the running stack.

---

## 1. Goal

Wire the request lifecycle (D6/D7): **anonymous + bots → the prerendered static file; logged-in → the live CSR SPA**; and make the static→SPA hand-off **flash-free** and **deploy-safe**.

## 2. nginx — the cache-bypass branch (static, documented)

`vbwd-fe-user/nginx.{dev,prod}.conf.template` (source templates only):

```nginx
# logged-in users bypass the prerender cache → live CSR SPA
map $http_cookie $is_authed { default 0; "~*vbwd_session=" 1; }

location / {
    if ($is_authed) { rewrite ^ /index.html last; }       # cache-bypass
    try_files /seo$uri.html /seo$uri/index.html $uri /index.html @app;
}
```

- `${VAR_DIR}/seo/` is bind-mounted read-only into the fe-user container (shared with the backend writer).
- **Static config:** adding/removing a post = adding/removing a file in `${VAR_DIR}/seo/`; toggling `seo.mode` is a backend flag. **No nginx reload, no conf regeneration** for content changes (verified by the e2e static proof).
- **Every nginx change is documented** in `plugins/cms/docs/seo/nginx-prerender.md` (the `map`/`try_files`/`if`, the `${VAR_DIR}/seo` mount, dev↔prod template diffs, request-flow diagram, rollback) — a reviewer reproduces routing from that doc alone.

## 3. The SPA hand-off (flash-free takeover)

`vbwd-fe-user/plugins/cms/src/views/PostDetail.vue` (and the public shell):
- On boot, read the inlined `#__POST__` JSON (written by 47.1). If present, **mount the component from that payload synchronously** — same markup as the prerendered body → **no white flash, no redundant `GET /cms/posts/<slug>`**. If absent (logged-in / cold SPA route), fall back to the API fetch.
- **Meta dedup (idempotent injection):** server-emitted head tags carry a `data-seo="ssr"` marker; client injection **updates in place keyed by that marker** instead of appending — so title/canonical/og are never duplicated. (This replaces today's blind `appendChild` in `CmsPage.vue`.)
- Because the app is plain CSR (`createApp().mount('#app')`, not `createSSRApp`), the takeover **re-renders** `#app`; driving it from `__POST__` keeps that re-render visually identical and instant.

## 4. Asset stamping & deploy re-stamp (the D7 invariant)

The prerendered files embed **content-hashed** entry tags; a frontend deploy changes those hashes. Therefore:
- **At write time (47.1):** the prerender writer reads the deployed `index.html` / Vite `manifest.json` to source the current `<script>`/`<link>`.
- **On every frontend deploy:** a **re-stamp step** rewrites the entry tags in all existing `${VAR_DIR}/seo/*.html` (cheap string substitution; no re-render of content) **or** triggers a bulk prerender refresh. Without this, real users' SPA fails to boot on stale hashes (bots stay fine). This hook is part of the deploy pipeline and **documented in the runbook**.

## 5. TDD (RED first)
- **fe-user unit:** `PostDetail` mounts from `__POST__` without calling the API; falls back to fetch when `__POST__` absent; meta injection **updates-in-place** (no duplicate tags) against server-emitted `data-seo` tags.
- **e2e / curl (running stack):**
  - anon `GET /<slug>` → served from `/seo/<slug>.html` (assert server-rendered head+body, **no** API call needed for first paint); JS then boots and the page becomes interactive with no content flash (payload-driven).
  - logged-in (with `vbwd_session`) `GET /<slug>` → served `index.html` (SPA shell), live data via API.
  - **static proof:** publish a post → its `/seo/<slug>.html` appears and is served **with no nginx reload**; delete → file gone, nginx untouched; flip `seo.mode=off` → `robots.txt` becomes `Disallow:/` with no nginx edit.
  - **deploy proof:** simulate a hash change → re-stamp step updates `/seo/*.html` entry tags → SPA still boots.

## 6. Files (indicative)
| Action | Path |
|---|---|
| edit | `vbwd-fe-user/nginx.dev.conf` + `nginx.prod.conf.template` — `map`+`try_files`+cache-bypass `if` |
| edit | `vbwd-fe-user-plugin-cms/.../views/PostDetail.vue` — `__POST__` mount + meta dedup |
| edit | `vbwd-fe-user/vue/src/main.ts` (or factory) — expose the asset manifest for stamping if needed |
| new | `plugins/cms/src/services/seo_asset_stamp.py` — read manifest; stamp/re-stamp entry tags |
| edit | deploy pipeline (`vbwd-demo-instances` CI) — call the re-stamp step on FE deploy |
| edit | `plugins/cms/docs/seo/nginx-prerender.md` — full nginx + stamping runbook |

## 7. Acceptance
- Anon/bot first paint comes from the static file (no Flask, no API) with full head+body; the SPA then takes over with **no visible flash** and **no duplicate `GET`**.
- Logged-in users always get the live CSR app (cache-bypass), seeing unpublished edits.
- **No-404 parity (serving side of the 47.0 URL/slug gate):** every pre-migration public page URL serves a **prerendered 200 at the same path** post-migration — no existing link 404s after deploy.
- Content changes and `seo.mode` toggles cause **no nginx reload / no conf change**.
- A frontend deploy re-stamps the prerendered files so the SPA still boots; head tags never duplicate.
- fe-user lint+test GREEN; serving + static + deploy e2e GREEN.

## 8. Out of scope
Image CWV / `<picture>` pipeline (47.3); `on_the_fly` SSR (deferred); CDN config (ops — the static files are CDN-ready as-is).

## 9. Engineering-requirements check
- **Core agnostic:** no core change; all in cms/fe-user/nginx.
- **DRY:** the client meta-injection consumes the **same** mapping as the server meta-builder (47.1); one `__POST__` contract.
- **DevOps-first:** nginx + stamping shipped with the runbook (not tribal knowledge); static & deploy proofs in CI.
- **NO OVERENGINEERING:** cookie-branch cache-bypass instead of an SSR tier; string-substitution re-stamp instead of bulk re-render where possible.
