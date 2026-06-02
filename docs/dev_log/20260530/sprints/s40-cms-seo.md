# S40 — Full-scale CMS SEO (built into the `cms` plugin) + a core sitemap/robots seam

**Status:** DRAFT for negotiation — 2026-05-29
**Architecture decision (LOCKED 2026-05-29):** SEO is **built into the `cms` plugin**, not a separate `cms-seo` plugin. The page's SEO data, authoring UI, and rendering already live in cms; per-page SEO is intrinsic to the page and splitting it out would only create a useless-without-cms plugin reaching into cms internals (fails cohesion; NO OVERENGINEERING). The **only** piece lifted to core is the cross-cutting, agnostic `sitemap.xml`/`robots.txt` aggregation seam that *all* content plugins feed (cms today, shop tomorrow). *(Filename keeps the legacy `-plugin` suffix; this is an in-plugin enhancement, not a new plugin.)*

**Repos touched:** `vbwd-backend` (core SEO seam + `plugins/cms`), `vbwd-fe-user` (public render / hydration + image pipeline), `vbwd-fe-admin` (`cms-admin` authoring polish), `vbwd-demo-instances` (nginx, if crawler routing chosen).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin cms --full` GREEN; fe-user + fe-admin `npm run lint && npm run test` GREEN; the new SEO e2e/curl assertions green against the running stack.

---

## 1. Problem (what the audit found)

A live audit of `https://vbwd.cc/` returned an **empty HTML shell** — only `<title>VBWD User Portal</title>` + a viewport tag, no body, no links — because the whole site is a client-side-rendered SPA; the domain has **zero search-index presence**. The CMS is the surface that produces the *public* pages we want ranked.

**What already exists (do NOT rebuild):**
- **Data model is SEO-complete.** `cms_page` (`plugins/cms/src/models/cms_page.py`): `meta_title`, `meta_description`, `meta_keywords`, `og_title`, `og_description`, `og_image_url`, `canonical_url`, `robots` (default `index,follow`), `schema_json`, `language`, plus `content_html` (pre-rendered). `cms_image` has `alt_text`/`og_image_url`/`robots`/`schema_json`/`width_px`/`height_px`.
- **Authoring UI exists.** `vbwd-fe-admin/plugins/cms-admin/src/views/CmsPageEditor.vue` already edits every SEO field.
- **Client-side meta injection exists.** `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` injects `document.title`, `meta description`, `og:*`, canonical, and JSON-LD — **but only after JS runs (`document.head.appendChild` on mount).**

**The gaps full-scale SEO must close:**
1. **The SEO `<head>` + content are delivered client-side only** → non-JS crawlers (Bing/Yandex/DuckDuckGo), social-preview bots, and LLM crawlers see the empty shell. *(Root cause of the zero index presence.)*
2. **No `sitemap.xml`, no `robots.txt`.**
3. **No hreflang / translation linking** (pages have `language` but nothing relates EN/DE/RU variants).
4. **No rich structured data beyond a free-form `schema_json`** (no per-type mappers, no Breadcrumb/Organization/FAQ).
5. **No Core Web Vitals discipline** (image format/dimensions/lazy-load/hero preload) — a ranking factor.
6. **Authoring lacks a SERP preview** and a sitemap/hreflang control surface (the fields exist but author feedback doesn't).

## 2. Goal (full-scale)

Every **published** public CMS page is fully search- and share-ready from the **initial HTTP response** — server-delivered `<head>` (title, description, og/twitter, canonical, robots, hreflang, JSON-LD) + `content_html` body — discoverable via `sitemap.xml`, governed by `robots.txt`, correctly cross-linked across locales, marked up with per-type structured data, and fast (Core Web Vitals). The authenticated dashboard stays CSR + `noindex`.

## 3. Design — delivered as ordered, independently-shippable increments

> All cms work lands **inside `plugins/cms`** (core stays agnostic). The single core addition is the sitemap/robots seam (§3.2). Each increment is shippable on its own and moves the needle.

### Increment 1 — Shared meta-builder + server-delivered head & content (the crux)

- **One shared meta-builder** (`plugins/cms/src/services/seo_meta_builder.py`): `page → list[tag]` (title, description, og:*, twitter:*, canonical, robots) + a JSON-LD blob. Today the field→tag mapping is **duplicated** inside `CmsPage.vue`; both server and the (kept) client injection consume this single mapping (**DRY**).
- **Server delivery — RESOLVED (Q1): static prerender at publish (`seo.mode = pregenerated`).** A publish/update hook assembles `<head>` (from the shared meta-builder) + `<body>` (assembled `content_html`/content-blocks) and writes a per-**canonical-slug** file `${VAR_DIR}/seo/<slug>.html`; unpublish/delete removes it. The file is a flat snapshot — **no rendering at request time**, just a file read. The SPA hydrates over it (idempotent meta injection). On-the-fly (universal SSR / crawler-aware) stays an enum value but is **deferred** (§3.7).
- **nginx is STATIC and written once** — never regenerated when pages/categories/SEO settings change:
  - One block: `try_files /seo/$uri.html $uri $uri/ @app;` (fall-through to SPA/backend).
  - **Adding/removing a page = adding/removing a file** in the mounted `${VAR_DIR}/seo/`; nginx config is untouched.
  - **Changing SEO mode (`off`/`pregenerated`) is a backend flag**, not an nginx edit (`off` → core emits `robots.txt: Disallow:/` + global `noindex`; backend writes no prerender files).
  - Prerender files are keyed by **canonical slug**, never by raw request URL (routing — §3.7 — decides the slug; prerender supplies the HTML).

### Increment 2 — `sitemap.xml` + `robots.txt` via a core-agnostic seam

- **Core (agnostic):** `vbwd/services/seo_registry.py` — `ISeoSitemapProvider` protocol + `SitemapEntry`; `vbwd/routes/seo.py` — `GET /sitemap.xml` (aggregates all registered providers; sitemap-index past 50k URLs) + `GET /robots.txt` (`Disallow: /dashboard`,`/api`,`/admin`; `Sitemap:` line). Core declares **no** providers.
- **cms:** registers a provider in `on_enable` yielding every `is_published` page (`loc` from slug, `lastmod` from `updated_at`, `changefreq`/`priority`, hreflang alternates from Increment 3). Excludes `noindex`/unpublished **and anything the SEO-scope predicate marks not-search-visible** (page- or category-level opt-out — Increment 7).

### Increment 3 — hreflang / translation linking

- `cms_page.translation_group_id` (UUID, nullable, indexed; Alembic migration **in the plugin**). Pages sharing a group are translations; renderer + sitemap emit `<link rel="alternate" hreflang="{language}">` per sibling + `x-default`.
- `CmsPageEditor.vue` gains a "translation of →" picker.

### Increment 4 — Rich structured data (per-type JSON-LD mappers)

- A small mapper registry in cms: `schema_type → JSON-LD`. Default `WebPage`/`Article` from page fields when `schema_json` is empty; author can still override via `schema_json`. Add `BreadcrumbList` (from category path) and a site-level `Organization`/`WebSite` (+ Sitelinks search box) emitted on the home/public shell. Validate against Google's Rich Results Test in CI.

### Increment 5 — Core Web Vitals / image pipeline

- cms image delivery: AVIF with WebP fallback + original; serve with **explicit `width`/`height`** (prevents CLS — dims already stored on `cms_image`), `loading="lazy"` below the fold, **hero image preloaded**. Critical CSS inlined; defer non-critical/3rd-party scripts. Fonts `font-display: swap`. The LCP element on a content page is the hero image — optimize that path.

### Increment 6 — Authoring polish

- **Live SERP preview** (title + URL + description, char-count warnings) in `CmsPageEditor.vue` — highest real-world ROI per the audit. **"Exclude from search engines" toggle** per page (and the category-level toggle — Increment 7), with the *effective* state shown (e.g. "noindex — inherited from category X"). hreflang picker (from Increment 3). Optional inline Rich-Results validity hint.

### Increment 7 — SEO scope exclusion (per-page & per-category opt-out)

Authors must be able to keep specific pages — or a whole category — **invisible to search engines** while the rest of the site is indexed. This is the per-content counterpart to the instance-wide `seo.mode = off` switch.

- **Model (migration in the plugin):**
  - `cms_page.seo_excluded` (Boolean, `default False`, not null) — opt a single page out.
  - `cms_category.seo_excluded` (Boolean, `default False`, not null) — opt out an entire category; **all its pages inherit** the exclusion.
- **One effective predicate = single source of truth (DRY).** `seo_meta_builder` (or a small `seo_scope.py` helper) exposes `page_is_search_visible(page) -> bool`:
  `is_published AND NOT page.seo_excluded AND NOT (page.category and page.category.seo_excluded) AND "noindex" not in page.robots`.
  **Every** consumer — meta-builder, prerender writer, sitemap provider — calls this one predicate; none re-derives the rule.
- **Behaviour when a page is NOT search-visible:**
  - **Meta/head:** emit `robots: noindex, nofollow` (overrides the page's stored `robots`).
  - **Prerender:** the static `.html` is **still written** (default `pregenerated`) so a person holding the direct link still gets the fast page — it just carries `noindex`. (It is *not* deleted; "invisible to search" = `noindex` + sitemap-omission, **not** an HTTP 404.)
  - **Sitemap:** the page is **omitted** entirely.
- **Why `noindex` over `robots.txt Disallow` for per-page scope:** a `Disallow`-ed URL can still surface in results via backlinks (Google may index the URL without content). `noindex` is the reliable "do not index this page" signal. `robots.txt` stays the blunt instrument for whole trees (`/dashboard`,`/api`,`/admin`) and for `seo.mode = off`.
- **Authoring:** the per-page toggle lands in `CmsPageEditor.vue` (Increment 6); the per-category toggle lands in the category editor, with inheritance surfaced on the page editor ("noindex — inherited from category X").

### 3.7 — Prerender ↔ CMS routing-rules compatibility (REQUIRED analysis)

The `cms` plugin has a routing-rules engine (`CmsRoutingService` + `routing_middleware` + `matchers`): a request URL resolves to a target page, possibly **by request context** — `match_type` ∈ {`default`, `language`, `ip_range`, `country`, `path_prefix`, `cookie`} — in two layers: `layer:"nginx"` (written into nginx conf, reloaded on CRUD) and `layer:"middleware"` (Flask `before_request`, producing a redirect or a `is_rewrite`). So the **same URL can resolve to different pages per visitor**. The prerender strategy must not break this, and a static file served *in front of* Flask would bypass the middleware entirely.

**Resolution — split URLs by role (canonical = SEO surface; contextual = routing surface):**

| URL kind | Prerender file? | Resolved by | SEO outcome |
|---|---|---|---|
| **Canonical page URL** (`/de/pricing`) | ✅ yes | nginx `try_files` serves the static file | Indexed; self-canonical + hreflang |
| **Contextual entry URL** (`/`, or a URL with a lang/country/cookie rule) | ❌ none | `try_files` falls through → backend → **middleware runs** → 301/302 to the canonical | Crawler follows redirect to the canonical |

Why this composes cleanly:
1. **Redirect rules (301/302) are fully compatible** — they rewrite the URL *before* any static file is reached; the crawler lands on the canonical (= the prerendered file).
2. **Rewrites on non-canonical URLs are compatible** — those URLs have no prerender file → `try_files` falls through to Flask → middleware resolves context → the canonical (separately prerendered) is what gets indexed.
3. **The one incompatible case — a context-dependent *rewrite* on a canonical, indexed URL** (same URL silently serving different content by country/cookie) — is **disallowed for SEO-indexed pages**. It cannot be statically prerendered *and* it's a Google cloaking/duplicate-content anti-pattern. The correct model is **distinct canonical URLs per locale + hreflang** (Increment 3), not silent per-visitor rewrites. The prerender writer logs/skips such a page rather than emitting an ambiguous file.

**Consequences baked into the design:**
- Prerender is keyed by **canonical slug**, so routing decisions (which slug) and content delivery (the HTML) stay decoupled — no per-URL nginx state.
- Each canonical prerendered page emits a **self-referencing `<link rel="canonical">`** + hreflang alternates, so a crawler arriving via any redirect indexes the canonical.
- **Pre-existing caveat (not introduced here):** the `layer:"nginx"` routing rules *do* mutate nginx + reload via `sync_nginx()` — a separate operator-redirect mechanism. **The SEO/prerender feature adds ZERO per-page nginx generation.** Fully-static end-to-end nginx (migrating nginx-layer redirects to middleware) is noted as out-of-scope follow-up (§7).

## 4. TDD plan (RED first)

- **cms backend:** meta-builder mapping (incl. fallbacks, HTML escaping); a published page's server response contains title/description/og/twitter/canonical/robots/JSON-LD/hreflang (integration via the render route); per-type JSON-LD mappers; cms sitemap provider yields correct entries (excludes unpublished/`noindex`); hreflang alternates resolve from `translation_group_id`.
- **cms backend — SEO scope exclusion (Increment 7):** `page_is_search_visible` truth table — published+clean → visible; `page.seo_excluded=True` → not visible; `category.seo_excluded=True` → every page in it not visible (inheritance); `robots` containing `noindex` → not visible; unpublished → not visible. Excluded page's meta-builder emits `noindex,nofollow`; prerender still writes the file (with noindex); sitemap provider omits it. The predicate is called by all three consumers (assert no duplicated rule).
- **core:** `GET /sitemap.xml` aggregates providers + paginates; `GET /robots.txt` shape; aggregator returns `[]` with no providers (Liskov null default).
- **fe-user:** client injection uses the **shared** mapping (no duplication); hydration doesn't double-inject server-emitted tags; image components emit explicit dims + lazy/eager correctly.
- **fe-admin:** SERP preview reflects field values + char-count thresholds; translation picker writes `translation_group_id`.
- **cms backend — routing compatibility (§3.7):** prerender writer keys files by **canonical slug** (not request URL); a context-dependent **rewrite** targeting a canonical indexed slug is skipped+logged (not emitted); a published canonical page emits a **self-referencing canonical**. (Redirect rules need no prerender-side change — assert a contextual URL with no file falls through, i.e. the writer never creates a file for a non-canonical/redirect-source URL.)
- **e2e/curl:** `curl -A Googlebot <slug>` returns head+content with no JS; `curl /sitemap.xml` + `/robots.txt` shape; (optional) Rich Results Test in CI. **nginx-static proof:** publish a new page → its `${VAR_DIR}/seo/<slug>.html` appears and is served, with **no nginx reload/conf change**; delete it → file gone, nginx untouched; flip `seo.mode=off` → `robots.txt` becomes `Disallow:/` with **no nginx edit**.

## 5. Files (indicative)

| Action | Path |
|---|---|
| new | `plugins/cms/src/services/seo_meta_builder.py` — shared field→tags + JSON-LD mappers (incl. per-type + Breadcrumb/Organization) |
| new | `plugins/cms/src/services/seo_prerender.py` — assemble `<head>`+`<body>` and write/remove `${VAR_DIR}/seo/<canonical-slug>.html`; called from page create/update/delete; skips non-canonical/rewrite-target slugs (§3.7) |
| edit | `plugins/cms/src/services/cms_page_service.py` — invoke the prerender writer on create/update/publish/unpublish/delete (invalidation) |
| edit | `plugins/cms/__init__.py` — register the cms sitemap provider in `on_enable` |
| new | migration `plugins/cms/migrations/versions/…_cms_page_translation_group.py` |
| new | core `vbwd/services/seo_registry.py` — `ISeoSitemapProvider` + `SitemapEntry` |
| new | core `vbwd/routes/seo.py` — `GET /sitemap.xml`, `GET /robots.txt` |
| edit | `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` — consume shared mapping (DRY); image dims/lazy/preload |
| new/edit | fe-user cms image component(s) — AVIF/WebP, explicit dims, lazy, hero preload |
| edit | `vbwd-fe-admin/plugins/cms-admin/.../CmsPageEditor.vue` — SERP preview, translation picker, **"Exclude from search engines" toggle** (+ inherited-state hint) |
| edit | `vbwd-fe-admin/plugins/cms-admin/.../` category editor — **per-category `seo_excluded` toggle** (Increment 7) |
| new | `plugins/cms/src/services/seo_scope.py` (or in `seo_meta_builder`) — `page_is_search_visible` single-source predicate (Increment 7) |
| new | migration `plugins/cms/migrations/versions/…_cms_seo_excluded.py` — `cms_page.seo_excluded` + `cms_category.seo_excluded` |
| edit | `vbwd-fe-user/nginx.prod.conf.template` + `nginx.dev.conf` — `try_files /seo/$uri.html …` for the prerendered page; **source templates only, never the prod instance trees** |
| new | **`plugins/cms/docs/seo/nginx-prerender.md`** — full, detailed documentation of every nginx change (the `try_files` rule, the shared `${VAR_DIR}/seo` mount, dev vs prod template diffs, request-flow diagram, rollback). **All nginx changes for this sprint MUST be documented here.** |

## 6. Acceptance

- `curl -A "Googlebot" <public-slug>` (and a plain `curl`, per chosen strategy) returns a document whose `<head>` carries the page's title/description/og/twitter/canonical/robots/JSON-LD/hreflang **and** whose `<body>` contains `content_html` — no JS required.
- `GET /sitemap.xml` lists every published page (with `lastmod` + hreflang) and excludes unpublished/`noindex`; `GET /robots.txt` blocks `/dashboard`,`/api`,`/admin` and names the sitemap.
- Localized variants emit correct `hreflang` + `x-default`.
- **SEO scope exclusion:** a page with `seo_excluded=True`, or a page in a category with `seo_excluded=True`, is served with `noindex,nofollow` in its `<head>` and is **absent** from `sitemap.xml`, while sibling non-excluded pages stay indexable. The excluded page still returns 200 with its content (invisible to search ≠ 404).
- **nginx changes are fully documented** in `plugins/cms/docs/seo/nginx-prerender.md` (try_files rule, `${VAR_DIR}/seo` mount, dev/prod template diffs, request-flow + rollback) — a reviewer can reproduce the routing from that doc alone.
- **nginx config is static:** adding/removing/editing pages or categories, and toggling `seo.mode`, cause **no nginx reload and no conf change** (verified by the e2e nginx-static proof). Routing-rule compatibility (§3.7) holds: a canonical URL serves its prerendered file; a contextual URL falls through to middleware → 301/302 → canonical.
- JSON-LD (WebPage/Article + Breadcrumb + Organization) passes Google's Rich Results Test.
- Content pages ship AVIF/WebP images with explicit dims, lazy below-fold, hero preloaded (LCP target met in a Lighthouse spot-check).
- `CmsPageEditor` shows a live SERP preview + translation picker.
- Authenticated dashboard remains `noindex` + CSR.
- Gates: `--plugin cms --full` GREEN; fe-user + fe-admin lint+test GREEN; SEO e2e green.

## 7. Out of scope (genuinely deferred)

- Per-tenant **subdomain** SEO / multi-tenant sitemap sharding.
- Non-CMS public surfaces (e.g. shop product pages) — they register their **own** provider via the core seam later; this sprint ships only the seam + cms's provider.
- Search Console submission, backlink/off-page strategy (ops, not code).
- A/B title testing, programmatic content generation (the latter is the S41 AI-helper track).
- **`on_the_fly` render mode** (universal SSR / crawler-aware) — enum value reserved, pipeline deferred until an instance needs live public content; falls back to `pregenerated` with a logged warning.
- **Migrating `layer:"nginx"` routing rules to middleware** for fully-static end-to-end nginx — the existing nginx-conf-generating redirect mechanism is pre-existing and untouched here (§3.7); SEO adds no per-page nginx generation.

## 8. Open questions

- **Q1. RESOLVED:** static prerender at publish (`seo.mode = pregenerated`) keyed by canonical slug; nginx static `try_files`; `seo.mode = off` for staging. On-the-fly (SSR/crawler-aware) is an enum value but deferred (§3.7 / §7). Drivers: `content_html` already stored, routing-rule compatibility (§3.7), and the static-nginx requirement.
- **Q2.** hreflang model — `translation_group_id` (recommended) vs `locale_alternates` JSON?
- **Q3. RESOLVED:** built into `cms` + a core sitemap/robots seam (no separate `cms-seo` plugin).
- **Q4.** Scope cut for a first PR? (Recommended landing order: Increment 1 → 2 → 3, then 4/5/6 as follow-on PRs — each shippable.)

## 9. Engineering-requirements check

- **Core agnostic:** the **only** core addition is the `ISeoSitemapProvider` registry + `/sitemap.xml`+`/robots.txt` (declares no providers). All per-page SEO lives in `cms`. No core→cms dependency.
- **DRY:** one meta-builder + one JSON-LD mapper shared by the server renderer and the `CmsPage.vue` client injection (replaces today's duplicated mapping). **One `page_is_search_visible` predicate** drives meta-builder, prerender, and sitemap — the exclusion rule is defined once.
- **DevOps documentation:** every nginx change is captured in `plugins/cms/docs/seo/nginx-prerender.md` (DevOps-first — infra change ships with its runbook, not tribal knowledge).
- **SOLID/Liskov:** sitemap aggregator returns `[]` with zero providers; providers + per-type schema mappers are substitutable.
- **NO OVERENGINEERING:** reuse existing SEO fields + `content_html` + stored image dims; in-plugin (no useless `cms-seo` plugin); increments are independently shippable so we never land a big-bang.
- **DevOps-first:** schema changes (`translation_group_id`, `cms_page.seo_excluded`, `cms_category.seo_excluded`) via in-plugin Alembic migrations; SEO assertions runnable in CI from a cold start.
