# S47 — Unified Content + SEO module (master) — supersedes S40 + S42

**Status:** DRAFT for negotiation — 2026-06-03
**Supersedes:** [S40 — CMS SEO](../cancelled/s40-cms-seo.md) and the whole [S42 — vbwd-press](../cancelled/s42-vbwd-press.md) series (`s42-0`…`s42-4`, now in `cancelled/`). Those remain readable for rationale; **S47 is the authority.**
**What it is:** one **WordPress-style content module** — a single `post` entity with a **type** discriminator (`page` · `post` · plugin-defined), an extensible **taxonomy** (`category` + `tag` defaults + plugin types), and **one** SEO pipeline (meta-builder → static prerender → core sitemap/robots seam). It is the existing **`cms` plugin evolved**; `cms_page` becomes `post(type=page)`. Extensions (custom post types, custom term types, content-block renderers, widgets) are **separate plugins** that extend cms via registries.

**Repos touched:** `vbwd-backend` (core SEO seam only), `vbwd-plugin-cms` (backend module), `vbwd-fe-user-plugin-cms` (public render + serving hand-off), `vbwd-fe-admin-plugin-cms` (`cms-admin` authoring), `vbwd-demo-instances` (nginx templates — source only, never prod trees).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** · **plugin baseline config files** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate per repo: `bin/pre-commit-check.sh --plugin cms --full` GREEN; fe-user + fe-admin `npm run lint && npm run test` GREEN; the SEO/serving e2e + curl assertions green against the running stack.

---

## 1. Problem (recap)

- The public site is a CSR SPA: a live audit of `https://vbwd.cc/` returned an **empty HTML shell** → **zero search-index presence**.
- S40 (SEO) targeted `cms_page`; S42 (press) introduced a **second** content entity `vbwd_press_post` with its **own** posts, taxonomy, and a *duplicate* SEO path. Two entities → two prerender hooks, two meta-builders, two sitemap providers, a press→cms coupling. That is the seam S47 removes.

**One entity, one taxonomy, one SEO pipeline** is the DRY-correct version of S40 + S42.

## 2. Locked architecture decisions (this conversation, 2026-06-03)

| # | Decision |
|---|---|
| **D1** | **One `post` entity** in cms with a `type` discriminator (`page`, `post`, + plugin-registered custom types via a **post-type registry**). `cms_page` migrates into it as `type=page`. **Hierarchy is page-only:** `parent_id` is permitted **only for post-types flagged `hierarchical`** (pages yes, posts no) → nested URLs (`/about/team`). |
| **D2** | **One taxonomy:** `term` with a `term_type` discriminator; built-ins **`category`** (hierarchical) + **`tag`** (flat); other plugins register types via a **term-type registry**. `cms_category` migrates into it as `term_type=category`. |
| **D3** | **No EAV.** Typed columns for known fields (incl. the full SEO set) + `content_json` (block body) + a small `type_data` JSON for type-specific fields. **Never** a WordPress-style `postmeta` key/value table. |
| **D4** | **Host = evolve `cms`** (it already owns pages, SEO fields, widgets, images, routing). Custom types / term-types / block renderers / widgets are **extension plugins** via registries — cms/core untouched to add one. |
| **D5** | **One SEO pipeline:** a shared **meta-builder** (`post → head tags + JSON-LD`) + a **Python-template prerender writer** (publish-time → static file) + a **core-agnostic** `sitemap.xml`/`robots.txt` seam every content plugin can feed. |
| **D6** | **Serving = cache-bypass, NOT SSR.** Anonymous + bots get the **prerendered static file** (nginx/CDN); logged-in users get the **live CSR SPA** (current behavior) via an nginx **auth-cookie branch**. **No Node SSR runtime** is introduced (the `on_the_fly` mode stays reserved + deferred). |
| **D7** | **Prerender = render-once-at-publish → static file.** The writer assembles `<head>` (meta-builder) + `<body>` (`content_html`) + an **inlined `__POST__` payload** + the **current build's hashed entry `<script>`/`<link>`**, and **re-stamps the asset tags on every frontend deploy**. Serve-time cost = a static file read → withstands 100–1000 req/s on one nginx (∞ behind a CDN). |
| **D8** | **No prerendered archives.** Category/tag/search pages are **CSR navigation** (widget-rendered, not prerendered, `noindex`, sitemap-omitted). Indexing happens via the **sitemap listing individual published posts/pages** + their prerendered detail files. *(Tradeoff accepted: archive pages don't rank; post/page detail does. Simplest model that needs no server-side list renderer.)* |
| **D9** | **Post status model** `draft · pending · scheduled · published · private · trash` (replaces a bare published bool). Only **`published`** is prerendered + in the sitemap; **`private`** is live-CSR for an authorized session (never prerendered); **`scheduled`** flips to `published` via a **TESTING-guarded scheduler tick** (then fires the prerender); **`trash`** is soft-delete (prerender removed). |
| **D10** | **Media stays `cms_image`** (not a post type) **but is plugin-extensible:** other plugins add media/attachment kinds (gallery, video, audio, embeds) via the **content-type renderer registry** (47.3) — no cms change (`cms-youtube` is the first example). **Revisions: out.** **Comments: a later sprint.** Menus/layouts/widgets keep their existing cms machinery (not folded into `post`). |
| **D11** | **Head/body injection seam (folds in S44 snippets).** One registry assembles the `<head>`/`body` from the **meta-builder + injection providers**; **snippets** (GA/GTM/Matomo/Pixel/ads) are the built-in provider, **baked into the prerendered head/body** (47.1) so they fire on first paint for anon/bots, with a **server-emitted CSP nonce** (no `unsafe-inline`); the SPA applies the same set idempotently for logged-in/CSR. A snippet change triggers a **prerender refresh** (47.2 hook). See 47.7. |

## 3. The unified model

```
cms_post                         cms_term                     cms_post_term
─────────────                    ──────────                   ──────────────
id (uuid pk)                     id (uuid pk)                 post_id  FK→cms_post  (cascade)
type        (str, indexed)       term_type (str, indexed)     term_id  FK→cms_term  (cascade)
slug        (str, indexed)       slug       (str, indexed)    UNIQUE(post_id, term_id)
title                            name
excerpt (text)                   parent_id  (self-FK, null)
content_json (json — blocks)     description (text, null)
content_html (text — rendered)   sort_order
type_data    (json, null)        UNIQUE(term_type, slug)
author_id  FK→user (SET NULL)
parent_id  (self-FK, null — hierarchical post-types only → nested URLs)
status     (enum: draft·pending·scheduled·published·private·trash, indexed)
published_at (tz dt, null)
language     (str, default en)
translation_group_id (uuid, null, indexed)   ← hreflang
sort_order
— SEO columns (from cms_page): meta_title/description/keywords, og_*, canonical_url,
  robots (default index,follow), schema_json, seo_excluded (bool, default false)
```

- **Tables prefixed `cms_`** (S43 naming rule). Migrations live in `plugins/cms/migrations/versions/` (registered in `alembic.ini`); revision ids ≤ 32 chars; the migration must resolve standalone (no anchoring on an unrelated plugin — see migration-graph fragmentation note).
- `cms_category.seo_excluded` is folded into `cms_term` (`seo_excluded` on the term); a post inherits exclusion from any excluded term it carries.

## 4. Serving model (the request lifecycle)

```
Anonymous / bot                              Logged-in editor
GET /de/pricing → nginx                      GET /de/pricing → nginx (vbwd_session cookie)
  try_files /seo/de/pricing.html  ──┐          if cookie → serve /index.html (SPA shell)
  → STATIC FILE (200), no Flask     │          → SPA boots → CSR → live data via API
  → instant paint: full <head>+body │          → sees latest unpublished edits
  → bots stop here (fully indexed)  │
  → <script> entry loads → SPA      │   In-app navigation (any user, after boot):
    reads #__POST__ → mounts        │     client-side router → lazy route chunk + API fetch
    (no refetch, no flash) → live   │     (never touches /seo/*.html)
```

The **high-volume traffic (anon + bots) is 100% static-file serving** → the throughput path. Flask/DB work is reserved for the small authenticated population + the SPA's API calls. **The one invariant (D7):** the static file must carry the *current* build's hashed assets, re-stamped on FE deploy, or real users' SPA won't boot (bots stay fine).

## 5. Sub-sprints

| # | Sub-sprint | Delivers |
|---|---|---|
| [47.0](s47-0-unified-data-model-and-registries.md) | Unified data model + post-type & term-type registries + CRUD + **cms_page→cms_post migration** | `cms_post`/`cms_term`/`cms_post_term`, both registries, repos/services, admin + public read routes, data backfill |
| [47.1](s47-1-seo-pipeline-and-prerender.md) | One meta-builder + Python-template prerender writer + **core sitemap/robots seam** + scope predicate + hreflang + JSON-LD | the SEO crux; `/seo/<slug>.html` on publish; `ISeoSitemapProvider`; `/sitemap.xml`+`/robots.txt` |
| [47.2](s47-2-serving-cache-bypass-and-handoff.md) | nginx cache-bypass branch + SPA hand-off (`__POST__` takeover, meta dedup) + **asset stamping & deploy re-stamp** | the request lifecycle made real; the D7 invariant |
| [47.3](s47-3-public-rendering-and-content-types.md) | Unified `PostList`/`PostCard` + `PostDetail` (hierarchical pages + breadcrumb) + **content-type renderer registry** (+ youtube example, media-extensible) + the **Category** widget + image CWV | the WordPress-style public frontend |
| [47.4](s47-4-fts-search.md) | Postgres FTS (`tsvector`+GIN) + the **Search** widget + the **Search-results** widget (decoupled, CSR, `noindex`) | search over published posts |
| [47.5](s47-5-rss-feeds.md) | RSS 2.0 per blog/term + autodiscovery (optional) | syndication |
| [47.6](s47-6-admin-authoring.md) | fe-admin unified, **type-aware** post editor + term manager + SERP preview + exclude-from-search toggles | authoring |
| [47.7](s47-7-snippets-and-head-injection.md) | **Head/body injection seam + snippets** (third-party scripts, baked into prerender, CSP-nonce) — **folds in S44** | GA/Pixel/Matomo/ads |

**Dependency order:** `47.0 → 47.1 → 47.2 → 47.3 → {47.4, 47.5, 47.6, 47.7 in parallel}` (47.7 uses the 47.1 prerender head + 47.2 serving + 47.3 widget registry; its admin UI lands with 47.6). Each is independently shippable; SEO is *complete* after 47.1+47.2, but content works (CSR) from 47.0.

## 6. Migration from `cms_page` (live data — vbwd.cc)

This is **not greenfield**. Phased, back-compatible:

1. **47.0** introduces `cms_post`/`cms_term` (additive migration) + the registries.
2. **Backfill via the service layer** (not raw SQL): `cms_page → cms_post(type=page)`, `cms_category → cms_term(term_type=category)`, page-image links preserved. Idempotent; runnable cold in CI. **This includes the content-population surfaces** (47.0 §2.6): the seeder `src/bin/populate_cms.py`, the `CmsImportExportService` (now typed `posts.json`/`terms.json` + a **legacy adapter** for old `pages.json`/`categories.json`), and the `docs/imports/*.json` seed tree (ingested via that adapter — no hand-edit) so demo/live instances populate unchanged.
3. cms read paths + routing resolve `post(type=page)`; keep a **compatibility shim** for `cms_page` reads for one release.
4. SEO pipeline (47.1/47.2) operates on `cms_post`; the meta-builder takes a **duck-typed "SEO-renderable" protocol** so future content plugins (e.g. shop product pages) feed the same pipeline.
5. Retire `cms_page`/`cms_category` once the shim window closes (separate migration).

**URL/slug-parity gate (the "nothing is lost on prod" guarantee — BLOCKS DEPLOY):** a regression test (47.0 §4) snapshots every existing published page's **URL + canonical + sitemap loc + prerendered availability** before the backfill and asserts they are **identical** after — every current link still 200s to the same content, **zero 404s, zero silent slug changes** (collisions resolve via 301, never a drop). Run in CI on the `docs/imports` set **and as a preflight against a real prod DB dump**; the migration is reversible (down + read shim) for safe rollback. **S47 is not "done" until this is green against prod data.**

## 7. Out of scope (deferred)

- **Node SSR / `on_the_fly`** live render — reserved enum, deferred (only needed for *public* content too dynamic to prerender).
- **Prerendered archives / server-side list rendering** (D8) — archives stay CSR.
- WordPress-style **`postmeta` EAV**, likes/comments, slug-change 301 history (FK/seam left only), per-tenant subdomain SEO, A/B titles, programmatic content (S41 AI track).
- Migrating `layer:"nginx"` routing rules to middleware (pre-existing mechanism, untouched — see 47.1 §routing compatibility).

## 8. Engineering-requirements check

- **Core agnostic:** the **only** core addition is `ISeoSitemapProvider` + `/sitemap.xml`+`/robots.txt` (declares no providers) + the SEO-renderable protocol. All content/SEO logic lives in `cms`. No core→cms dependency; the core-agnosticism oracle stays green.
- **DRY:** one entity, one taxonomy, one meta-builder, one prerender writer, one sitemap provider, one `PostList`, one query service — feeding pages, posts, custom types, search, and RSS alike.
- **No EAV** (D3): typed columns + JSON, never key/value meta.
- **SOLID/Liskov:** registries (post-type, term-type, content-block, sitemap) are substitutable; unknown type → safe fallback (never crash); aggregator returns `[]` with zero providers.
- **DevOps-first:** schema via in-plugin Alembic migrations resolving standalone; demo + backfill via services; every nginx change documented in `plugins/cms/docs/seo/nginx-prerender.md`; SEO/serving assertions runnable cold in CI.
- **NO OVERENGINEERING:** reuse existing cms machinery + `content_html`; cache-bypass instead of an SSR tier; no prerendered archives; increments independently shippable.
