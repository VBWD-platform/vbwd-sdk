# Report 14 — S47 Unified Content + SEO: implemented, running, live-reviewed

**Date:** 2026-06-03
**Scope:** Implemented the whole **S47 unified content + SEO** module (supersedes
S40 CMS-SEO + the S42 vbwd-press series + S44 snippets), then iterated it against
the **running localhost stack** over several rounds of direct product review.
WordPress-style: one `cms_post` entity (type `page`/`post`/custom) + one `cms_term`
taxonomy, one SEO pipeline (Python-template prerender + cache-bypass serving), and
a public route cutover so `/:slug` renders the unified engine. **Not committed**
(standing rule). Built TDD-first via the `vbwd-tdd` agent; every gate re-verified
by hand.

---

## TL;DR

- **9 build increments** (47.0a → 47.7) landed green, then **3 rework rounds**
  (snippets-simplify, posts=pages convergence, public cutover) driven by live review.
- The site now serves the unified engine: **34 legacy pages backfilled** into
  `cms_post`, `/sitemap.xml` lists **28 URLs**, and a brand-new `type=post`
  (`/test23`) **renders publicly** with its layout/style — **verified headlessly**,
  not inferred from green tests.
- **Three "passes-in-tests, breaks-when-run" bugs** were caught only by actually
  booting the app (see §4) — the value of running it.
- Gates green per repo: backend cms **349 unit + 86 integration**, full **core gate
  green**, fe-user **102 cms specs** (suite green), fe-admin **512** (59 cms-admin).

## 1. What shipped (the module)

| Increment | Delivered |
|---|---|
| 47.0a | `cms_post`/`cms_term`/`cms_post_term` + **post-type & term-type registries** + repos + `PostService`/`TermService` (status lifecycle `draft·pending·scheduled·published·private·trash`, **page-only hierarchy** w/ cycle refusal, TESTING-guarded scheduled-publish) + admin/public routes (nested-path resolution) |
| 47.0b | `cms_page → cms_post(type=page)` **backfill** + read shim + seeder rewrite + import/export legacy adapter + the **URL/slug-parity "nothing lost" gate** |
| 47.1 | **Core-agnostic** `ISeoSitemapProvider`/`SeoRenderable` seam + `/sitemap.xml` + `/robots.txt`; cms meta-builder + per-type JSON-LD + **one `page_is_search_visible` predicate** + status-aware **Python prerender writer** + sitemap provider |
| 47.2 | **Serving:** asset-stamping (hashed entry tags into prerender), **nginx cache-bypass** templates (anon→`/seo` static, logged-in→live CSR), `useSeoHandoff` (`__POST__` + idempotent meta dedup) |
| 47.3 | Public `PostList`/`PostCard`/`PostDetail` + **content-type renderer registry** + the **`cms-youtube`** extension plugin + Category widget + image CWV (`CmsImage` AVIF/WebP) |
| 47.4 | Postgres **FTS** (generated `tsvector` + GIN) + `Search` + `Search-results` widgets |
| 47.5 | **RSS 2.0** per blog/term + autodiscovery |
| 47.6 | fe-admin **type-aware authoring** |
| 47.7 | snippets (built, then re-scoped — see §3) |

**Core stays agnostic** throughout: the only `vbwd/` additions are the sitemap/robots
seam + the `SeoRenderable` protocol (no providers, no plugin names); the
agnosticism oracle stayed green.

## 2. Migrations (cms head, linear)
`20260603_1000_cms_unified` → `20260603_1100_cms_search_vec` → `20260603_1200_cms_post_layout`.
(The snippet migration `…_1200_cms_snippet` was created in 47.7 then **removed** in
the rework — dev DB cleanly downgraded; nothing released.)

## 3. Live-review rework (the product corrections)

After bringing the stack up and reviewing the admin/public UI, three rounds of
direct feedback reshaped the first cut:

- **Snippets → a widget, not a subsystem.** 47.7 over-built a backend `cms_snippet`
  table + CRUD + head-injection registry + CSP machinery + an admin page. Per
  feedback this was **ripped out** and replaced with a single **"Custom Code"
  Vue widget** (paste GA/gtag/etc. into the widget's `content_json`; it builds real
  `<script>` elements, never `v-html`). Backend subsystem removed (migration dropped).
- **Legacy CMS surfaces retired.** Removed the legacy **Categories** admin page
  (taxonomy replaces it); **Taxonomy** gained editable categories+tags + **JSON
  export/import**; **Pages** list rewired to the unified engine (`type=page`).
- **Editor parity + posts = pages.** `PostEditor` dropped the TipTap "visual" for
  the page-editor's **HTML/CSS/Preview tabs** + a **View Page** button; `cms_post`
  gained **`layout_id`/`style_id`/`use_theme_switcher_styles`** (backfilled);
  posts & pages now share **one `CmsContentList`** (1:1: import/export, bulk ops,
  full-row-click; `/posts`=type=post, `/pages`=type=page; type column dropped,
  category+tags added).
- **Public route cutover.** `/:slug` now renders `cms_post` (page **and** post)
  with layout/style via the unified `/cms/posts/<slug>` endpoint (bare→page,
  retry→post), reusing the one `CmsLayoutRenderer` + `useSeoHandoff`; existing page
  URLs keep rendering (parity).

## 4. Bugs that only surfaced by RUNNING it (not caught by green tests)

1. **`flask cms backfill` CLI not registered** — the 47.0b `src/cli.py` was never
   added via `current_app.cli.add_command`; ran the backfill through the service
   instead (34 pages copied).
2. **Sitemap 500 → empty** — the sitemap provider set `loc = canonical_url` with no
   fallback; all backfilled posts have `canonical_url = NULL` → `loc=None` →
   core's renderer crashed on `escape(None)` → HTTP 500 → "empty sitemap". Fixed
   with the same `canonical_url or base/slug` fallback RSS uses; live `/sitemap.xml`
   now **28 `<loc>`**. (Disproved my first hypothesis — the `on_enable` lifecycle
   was a red herring; the manager re-runs `on_enable` on every boot.)
3. **`/test23` showed 404 in the browser despite green code + working API** — a
   **stale Vite module** (HMR served the pre-cutover store). Cleared `.vite` +
   restarted dev → **headless Playwright confirms `/test23` renders** the post and
   `/home` renders (parity). Lesson logged: headless-verify "does it render," don't
   infer from green unit tests.

Also hit + recovered: the **esbuild bind-mount trap** (host-polluted
`vbwd-fe-core/node_modules/esbuild` 0.28.0 vs Linux 0.21.5) crashing the fe-admin
dev container on restart — fixed by reinstalling the Linux 0.21.5 binary in-container.

## 5. Current live state (localhost)
- Backend reloaded; `/api/v1/cms/posts` (33 published), `/sitemap.xml` (28 locs),
  `/robots.txt`, `/cms/search`, posts/terms **export/import**, all 200.
- Admin `localhost:8081`: Posts (type=post, category+tags cols, import/export, bulk,
  row-click), Pages (type=page, same shared list), unified PostEditor (layout/style +
  HTML/CSS/Preview + View Page), Taxonomy (cats+tags + JSON I/O), Custom Code widget;
  snippets + categories admin pages gone.
- Public `localhost:8080`: `/test23` and the 34 backfilled pages render via the
  unified engine.

## 6. Not done / next
- Full e2e URL-parity proof across **all** page slugs + **prerender regeneration**
  for the backfilled posts (anon/bot static path; backfill didn't fire
  `content.changed`).
- Wire the `flask cms backfill` CLI; cosmetic bare-slug double-fetch 404 (skip the
  bare attempt for known post slugs); remove orphaned legacy `CmsPageEditor.vue` +
  dead `useCmsAdminStore` category methods.
- Retire `cms_page`/`cms_category` after the shim window.

## 7. Engineering
TDD-first throughout (RED confirmed before GREEN); core agnostic (oracle green);
DRY (one entity, one taxonomy, one meta-builder/predicate, one list renderer, one
layout renderer); narrowest changes; **`bin/pre-commit-check.sh` re-run by hand**
on every touched repo. **No commits / pushes** — all changes on disk for review.
Sprint docs: [`sprints/s47-unified-content-seo.md`](../sprints/s47-unified-content-seo.md)
(+ `s47-0`…`s47-7`); superseded specs in [`cancelled/`](../cancelled/).
