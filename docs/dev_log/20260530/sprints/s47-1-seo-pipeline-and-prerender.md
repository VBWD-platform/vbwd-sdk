# S47.1 — One SEO pipeline: meta-builder + Python-template prerender + core sitemap/robots seam

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Depends on:** [S47.0](s47-0-unified-data-model-and-registries.md) · **Status:** DRAFT — 2026-06-03
**Repos:** `vbwd-backend` (core sitemap/robots seam + SEO-renderable protocol — **agnostic**), `vbwd-plugin-cms` (meta-builder, prerender writer, sitemap provider).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin cms --full` GREEN (core seam tests in the backend gate); SEO curl assertions green.

---

## 1. Goal

Every **published** `post` (page or post or custom type) is search-/share-ready **from the first HTTP byte**: a static prerendered file carrying the full `<head>` + `content_html` body, discoverable via `sitemap.xml`, governed by `robots.txt`. **Render once at publish; nginx serves static** (D7). Archives/search are **not** prerendered (D8).

## 2. Core (agnostic) — the only core addition

- `vbwd/services/seo_registry.py` — `ISeoSitemapProvider` protocol + `SitemapEntry`; aggregator returns `[]` with no providers (Liskov null default). Core declares **no** providers.
- `vbwd/services/seo_renderable.py` — a **duck-typed protocol** `SeoRenderable` (the SEO/identity fields a content object must expose: slug, language, robots, meta_*, og_*, canonical_url, schema_json, translation siblings, `is_search_visible()`). The meta-builder consumes *this*, not a `cms_post`, so future content plugins feed the same pipeline.
- `vbwd/routes/seo.py` — `GET /sitemap.xml` (aggregate all providers; sitemap-index past 50k URLs) + `GET /robots.txt` (`Disallow: /dashboard`,`/api`,`/admin`; `Sitemap:` line; `seo.mode=off` ⇒ `Disallow: /`). No plugin names appear in core.

## 3. cms — the meta-builder (DRY single mapping)

`plugins/cms/src/services/seo_meta_builder.py`: `SeoRenderable → (list[head_tag], json_ld)` — title, description, `og:*`, `twitter:*`, canonical (self-referencing), `robots`, `hreflang` alternates (+ `x-default`) from `translation_group_id` siblings. **Per-type JSON-LD mappers** (registry `schema_type → JSON-LD`): default `WebPage`/`Article` from fields; `BreadcrumbList` from the term path; site-level `Organization`/`WebSite`. Author `schema_json` overrides. **This same mapping is consumed by the client meta-injection (47.2/47.3)** — the field→tag map exists **once**.

### 3.1 Search-visibility predicate (single source of truth)
`page_is_search_visible(post) -> bool` =
`post.status == "published" AND NOT post.seo_excluded AND none(term.seo_excluded for term in post.terms) AND "noindex" not in post.robots`.
(`draft`/`pending`/`scheduled`/`private`/`trash` → not visible.) **Every** consumer — meta-builder, prerender writer, sitemap provider — calls this one predicate.

## 4. cms — the Python-template prerender writer (D7)

`plugins/cms/src/services/seo_prerender.py`, invoked from `PostService` on the `content.changed` hook (publish/update/delete):

- **On publish/update of a search-visible-or-direct-linkable post:** render a complete document to `${VAR_DIR}/seo/<canonical-slug>.html`:
  - `<head>` from the meta-builder;
  - `<body>` = `<div id="app">{content_html}</div>`;
  - an **inlined payload** `<script type="application/json" id="__POST__">{slug,title,content_html,seo}</script>` (so the SPA mounts without a re-fetch — 47.2);
  - the **current build's hashed entry tags** (`<script type=module src=/assets/index-<hash>.js>` + CSS `<link>`), read from the deployed `index.html`/Vite manifest at write time.
- **`seo_excluded` / term-excluded post:** the file is **still written** (direct-link visitors get the fast page) but its `<head>` carries `robots: noindex,nofollow`; it is **omitted from the sitemap**. (Invisible to search ≠ 404.)
- **Status-driven triggers:** only **`published`** writes a **public** prerender file (+ sitemap entry); **`private`** is **never prerendered** — served live-CSR to an authorized session only; **`scheduled`** writes nothing until the 47.0 tick flips it to `published` (which fires `content.changed`); **`draft`/`pending`** write nothing; **`trash`** / unpublish / delete **remove** the file.
- **Keyed by canonical slug**, never raw request URL.

### 4.1 Prerender ↔ cms routing-rules compatibility (REQUIRED)
cms has a routing engine (`CmsRoutingService` + middleware): a URL can resolve to different posts by context (`language`/`country`/`cookie`/`path_prefix`). Resolution (carried over from S40 §3.7):

| URL kind | Prerender file? | Resolved by | SEO outcome |
|---|---|---|---|
| **Canonical** (`/de/pricing`) | ✅ yes | nginx `try_files` serves the static file | Indexed; self-canonical + hreflang |
| **Contextual** (`/`, lang/country/cookie rule) | ❌ none | falls through → middleware → 301/302 → canonical | Crawler follows redirect to the canonical |

A **context-dependent rewrite on a canonical, indexed URL** (same URL silently serving different content) is **disallowed for indexed posts** (cloaking/duplicate-content); the writer **logs+skips** it. The correct model is distinct canonical URLs per locale + hreflang. **SEO adds ZERO per-page nginx generation** (the pre-existing `layer:"nginx"` redirect mechanism is untouched).

## 5. cms — the sitemap provider

Registered in `on_enable`: yields every **search-visible** `post` (`loc` from `(type, slug)`, `lastmod` from `updated_at`, `changefreq`/`priority`, hreflang alternates), **excluding** `noindex`/unpublished/`seo_excluded` (page- or term-level, via the §3.1 predicate). **Archives/search URLs are NOT emitted** (D8) — only directly-prerendered, crawlable posts/pages.

## 6. TDD (RED first)
- **Core:** `/sitemap.xml` aggregates + paginates providers; `[]` with none (Liskov); `/robots.txt` shape incl. `seo.mode=off`. The `SeoRenderable` protocol is satisfiable by a non-cms stub (proves agnosticism).
- **cms meta-builder:** field→tag mapping incl. fallbacks + HTML escaping; per-type JSON-LD (`WebPage`/`Article`/`BreadcrumbList`/`Organization`); hreflang from `translation_group_id`.
- **cms predicate:** truth table — published+clean → visible; `post.seo_excluded` → not; any term `seo_excluded` → not (inheritance); `noindex` in robots → not; unpublished → not. Asserted to be called by all three consumers (no duplicated rule).
- **cms prerender writer:** writes `/seo/<slug>.html` with head+body+`__POST__`+stamped assets; excluded post writes file **with noindex** + sitemap omits it; unpublish removes file; **keyed by canonical slug**; a context-rewrite on a canonical slug is **skipped+logged**; a contextual/redirect URL gets **no** file.
- **curl:** `curl -A Googlebot <slug>` returns head+content, no JS; `curl /sitemap.xml` lists published posts (excludes unpublished/noindex/excluded); `/robots.txt` blocks `/dashboard`,`/api`,`/admin` + names the sitemap.

## 7. Files (indicative)
| Action | Path |
|---|---|
| new | core `vbwd/services/seo_registry.py`, `vbwd/services/seo_renderable.py`, `vbwd/routes/seo.py` |
| new | `plugins/cms/src/services/seo_meta_builder.py` (+ per-type JSON-LD mappers) |
| new | `plugins/cms/src/services/seo_prerender.py` |
| edit | `plugins/cms/src/services/cms_post_service.py` — fire prerender on `content.changed` |
| edit | `plugins/cms/__init__.py` — register the sitemap provider in `on_enable` |
| new | `plugins/cms/docs/seo/nginx-prerender.md` — runbook (filled in 47.2) |

## 8. Acceptance
- A published post's `/seo/<slug>.html` carries title/description/og/twitter/self-canonical/robots/JSON-LD/hreflang in `<head>` and `content_html` in `<body>` — no JS required.
- `/sitemap.xml` lists every search-visible post (with `lastmod`+hreflang), excludes unpublished/`noindex`/`seo_excluded`, omits archives/search. `/robots.txt` correct.
- An excluded post serves 200 with `noindex,nofollow` and is absent from the sitemap.
- **SEO parity (SEO side of the 47.0 URL/slug gate):** post-migration, each page's `canonical_url` and its `sitemap.xml` `loc` are **byte-identical** to pre-migration — no canonical drift, no lost/changed indexed URL.
- The meta-builder is driven by the `SeoRenderable` protocol (a non-cms stub satisfies it).
- `--plugin cms --full` + core gate GREEN; SEO curl assertions GREEN.

## 9. Out of scope
The nginx branch + SPA hand-off + asset re-stamp on deploy (47.2); image CWV (47.3); `on_the_fly` SSR (deferred); prerendered archives (D8).

## 10. Engineering-requirements check
- **Core agnostic:** core ships only the registry + `/sitemap.xml`+`/robots.txt` + the `SeoRenderable` protocol (no providers, no plugin names). Oracle stays green.
- **DRY:** one meta-builder + one JSON-LD mapper shared by server prerender and client injection; **one** `page_is_search_visible` predicate across meta/prerender/sitemap.
- **SOLID/Liskov:** aggregator `[]` default; providers + schema mappers substitutable.
- **NO OVERENGINEERING:** Python template (no headless browser, no SSR); reuse `content_html` + stored SEO columns.
