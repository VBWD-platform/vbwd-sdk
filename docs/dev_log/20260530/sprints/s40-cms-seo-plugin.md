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
- **Server delivery (pick render strategy — Q1):**
  - **(A) Crawler-aware edge prerender (Recommended):** nginx detects bot/preview UAs on public slug routes → a backend render route returns a full HTML document built from the page record: full `<head>` + `<body>` = `content_html`. Humans keep the SPA (which hydrates + injects the same meta via the shared builder). Smallest change, reuses `content_html`.
  - **(B) Universal head SSR** for all public-slug requests; or **(C) static prerender at publish** (publish hook writes per-slug `.html`, nginx serves it; invalidate on edit).

### Increment 2 — `sitemap.xml` + `robots.txt` via a core-agnostic seam

- **Core (agnostic):** `vbwd/services/seo_registry.py` — `ISeoSitemapProvider` protocol + `SitemapEntry`; `vbwd/routes/seo.py` — `GET /sitemap.xml` (aggregates all registered providers; sitemap-index past 50k URLs) + `GET /robots.txt` (`Disallow: /dashboard`,`/api`,`/admin`; `Sitemap:` line). Core declares **no** providers.
- **cms:** registers a provider in `on_enable` yielding every `is_published` page (`loc` from slug, `lastmod` from `updated_at`, `changefreq`/`priority`, hreflang alternates from Increment 3). Excludes `noindex`/unpublished.

### Increment 3 — hreflang / translation linking

- `cms_page.translation_group_id` (UUID, nullable, indexed; Alembic migration **in the plugin**). Pages sharing a group are translations; renderer + sitemap emit `<link rel="alternate" hreflang="{language}">` per sibling + `x-default`.
- `CmsPageEditor.vue` gains a "translation of →" picker.

### Increment 4 — Rich structured data (per-type JSON-LD mappers)

- A small mapper registry in cms: `schema_type → JSON-LD`. Default `WebPage`/`Article` from page fields when `schema_json` is empty; author can still override via `schema_json`. Add `BreadcrumbList` (from category path) and a site-level `Organization`/`WebSite` (+ Sitelinks search box) emitted on the home/public shell. Validate against Google's Rich Results Test in CI.

### Increment 5 — Core Web Vitals / image pipeline

- cms image delivery: AVIF with WebP fallback + original; serve with **explicit `width`/`height`** (prevents CLS — dims already stored on `cms_image`), `loading="lazy"` below the fold, **hero image preloaded**. Critical CSS inlined; defer non-critical/3rd-party scripts. Fonts `font-display: swap`. The LCP element on a content page is the hero image — optimize that path.

### Increment 6 — Authoring polish

- **Live SERP preview** (title + URL + description, char-count warnings) in `CmsPageEditor.vue` — highest real-world ROI per the audit. Per-page "include in sitemap" toggle (default on when published). hreflang picker (from Increment 3). Optional inline Rich-Results validity hint.

## 4. TDD plan (RED first)

- **cms backend:** meta-builder mapping (incl. fallbacks, HTML escaping); a published page's server response contains title/description/og/twitter/canonical/robots/JSON-LD/hreflang (integration via the render route); per-type JSON-LD mappers; cms sitemap provider yields correct entries (excludes unpublished/`noindex`); hreflang alternates resolve from `translation_group_id`.
- **core:** `GET /sitemap.xml` aggregates providers + paginates; `GET /robots.txt` shape; aggregator returns `[]` with no providers (Liskov null default).
- **fe-user:** client injection uses the **shared** mapping (no duplication); hydration doesn't double-inject server-emitted tags; image components emit explicit dims + lazy/eager correctly.
- **fe-admin:** SERP preview reflects field values + char-count thresholds; translation picker writes `translation_group_id`.
- **e2e/curl:** `curl -A Googlebot <slug>` returns head+content with no JS; `curl /sitemap.xml` + `/robots.txt` shape; (optional) Rich Results Test in CI.

## 5. Files (indicative)

| Action | Path |
|---|---|
| new | `plugins/cms/src/services/seo_meta_builder.py` — shared field→tags + JSON-LD mappers (incl. per-type + Breadcrumb/Organization) |
| new | `plugins/cms/src/routes/...` — public server-render route (head + `content_html`) |
| edit | `plugins/cms/__init__.py` — register the cms sitemap provider in `on_enable` |
| new | migration `plugins/cms/migrations/versions/…_cms_page_translation_group.py` |
| new | core `vbwd/services/seo_registry.py` — `ISeoSitemapProvider` + `SitemapEntry` |
| new | core `vbwd/routes/seo.py` — `GET /sitemap.xml`, `GET /robots.txt` |
| edit | `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` — consume shared mapping (DRY); image dims/lazy/preload |
| new/edit | fe-user cms image component(s) — AVIF/WebP, explicit dims, lazy, hero preload |
| edit | `vbwd-fe-admin/plugins/cms-admin/.../CmsPageEditor.vue` — SERP preview, translation picker, sitemap toggle |
| edit | `vbwd-demo-instances` nginx — crawler routing (if option A) |

## 6. Acceptance

- `curl -A "Googlebot" <public-slug>` (and a plain `curl`, per chosen strategy) returns a document whose `<head>` carries the page's title/description/og/twitter/canonical/robots/JSON-LD/hreflang **and** whose `<body>` contains `content_html` — no JS required.
- `GET /sitemap.xml` lists every published page (with `lastmod` + hreflang) and excludes unpublished/`noindex`; `GET /robots.txt` blocks `/dashboard`,`/api`,`/admin` and names the sitemap.
- Localized variants emit correct `hreflang` + `x-default`.
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

## 8. Open questions

- **Q1.** Render strategy — (A) crawler-aware edge prerender (recommended), (B) universal head SSR, or (C) static prerender at publish?
- **Q2.** hreflang model — `translation_group_id` (recommended) vs `locale_alternates` JSON?
- **Q3. RESOLVED:** built into `cms` + a core sitemap/robots seam (no separate `cms-seo` plugin).
- **Q4.** Scope cut for a first PR? (Recommended landing order: Increment 1 → 2 → 3, then 4/5/6 as follow-on PRs — each shippable.)

## 9. Engineering-requirements check

- **Core agnostic:** the **only** core addition is the `ISeoSitemapProvider` registry + `/sitemap.xml`+`/robots.txt` (declares no providers). All per-page SEO lives in `cms`. No core→cms dependency.
- **DRY:** one meta-builder + one JSON-LD mapper shared by the server renderer and the `CmsPage.vue` client injection (replaces today's duplicated mapping).
- **SOLID/Liskov:** sitemap aggregator returns `[]` with zero providers; providers + per-type schema mappers are substitutable.
- **NO OVERENGINEERING:** reuse existing SEO fields + `content_html` + stored image dims; in-plugin (no useless `cms-seo` plugin); increments are independently shippable so we never land a big-bang.
- **DevOps-first:** schema change (`translation_group_id`) via an in-plugin Alembic migration; SEO assertions runnable in CI from a cold start.
