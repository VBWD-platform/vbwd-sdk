# S47.3 — Public rendering: PostList/PostCard + PostDetail + content-type renderer registry + widgets + image CWV

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Depends on:** [S47.0](s47-0-unified-data-model-and-registries.md) (SEO-complete with [47.1](s47-1-seo-pipeline-and-prerender.md)/[47.2](s47-2-serving-cache-bypass-and-handoff.md)) · **Status:** DRAFT — 2026-06-03
**Repos:** `vbwd-fe-user-plugin-cms` (renderer + registry + widgets), **new** `vbwd-fe-user-plugin-cms-youtube` (the worked extension example).
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** · **plugin baseline config files** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: fe-user `npm run lint && npm run test` GREEN; widget e2e GREEN.

---

## 1. Goal

The WordPress-style public frontend, **DRY**: one generic post-list every source feeds, one post-detail that renders typed content blocks via an **extensible registry**, the category/tag listing widget, and Core-Web-Vitals-correct images — all reusing the 47.0 read endpoints and the 47.1/47.2 SEO/serving path.

## 2. The DRY spine — `PostList` + `PostCard`

`vbwd-fe-user/plugins/cms/src/components/PostList.vue`:
- **Input:** post summaries (from a source) + a `display` config; **does NOT fetch** (sources pass data → single render path for every listing).
- `display`: `mode` ∈ `titles|excerpt|full|gallery|video`; `meta` = ordered subset of `["author","time_ago","tags","published_at","reading_time"]`.
- `PostCard.vue`: title (links to detail) + the configured metadata row + excerpt + lead image (**lazy, explicit dims** — §5).
- `usePosts` composable — the **single** fetch path: `byTerm(type, term_type, slug, page)`, `bySlug(type, slug)`; (47.4 adds `bySearch`). Pagination lives here, not in components.

## 3. Post detail + the content-type renderer registry

`PostDetail.vue` mounts from `__POST__` (47.2) or fetches `bySlug`; renders title + metadata + **body via the content-type registry**; injects SEO meta via the shared mapping (47.1) with marker-based dedup. For **hierarchical pages** it resolves the **nested path** (`/about/team`) and renders a **breadcrumb from the parent chain** (which also feeds the `BreadcrumbList` JSON-LD in 47.1).

**Media extensibility (master D10):** `cms_image` stays the stored asset; **new media/attachment kinds (gallery, video, audio, embeds) are added by other plugins through this same content-type registry** — no cms change. Media is deliberately *not* a post type; the `cms-youtube` plugin (§6) is the first worked example of the seam.

`vbwd-fe-user/plugins/cms/src/registry/contentTypeRegistry.ts`:
- `registerPostContentType(type, component, opts?: { placement?: 'top'|'inline'|'bottom' })`
- `resolvePostContentType(type) -> { component, opts } | undefined`

A post body is an ordered block list in `content_json` (`{ blocks: [{ type, data, position }] }`); **a post with no blocks renders its `content_html` as one implicit `richtext` block** (back-compat — and `content_html` stays the crawlable body in the prerender). Render rule: `placement:'top'` blocks above in-flow blocks (ordered by `position` within the top zone), `inline` in `position` order, `bottom` after. **Unknown type → safe fallback** (quiet "unsupported block", never crash — Liskov). cms registers the built-in **`richtext`** (`inline`).

### 3.1 Lazy-load ordering contract (REQUIRED — composes with 47.2)
Block renderers (and the term widgets, §4) are registered by **lazily-loaded plugins**. `PostDetail`/widgets must **re-render when a type registers late** (reactive registry), so a block whose plugin loads after first mount (e.g. a `top` hero embed) is **not** stuck on the fallback. For **bots** this is moot (the prerender + 47.2 snapshot already carry `content_html`); for **logged-in CSR** the reactive re-render prevents pop-in / empty slots.

## 4. The **"Category"** (term-list) widget — first of the three widgets

`PostTermListWidget.vue` (registered name **`Category`** / `PostTermList`) — via the existing cms `vueComponentRegistry` (`resolveCmsVueComponent`) in the plugin's `install()` (same mechanism shop/booking use). Config from the widget's `content_json`: `{ type, term_type, term_slug, mode, meta[], limit, paginate }`. Fetches `usePosts.byTerm` → renders `PostList`. An admin drops a `vue-component` widget (`content_json.component="Category"` + config) onto any cms page → that page lists the term's posts. **No bespoke route** — archives are CSR pages (D8: `noindex`, sitemap-omitted; discovery is via the per-post sitemap). *(The other two widgets — **Search** + **Search-results** — ship in 47.4.)*

## 5. Image pipeline (Core Web Vitals)

cms image component: **AVIF + WebP `<picture>` + original**, **explicit `width`/`height`** (dims already stored on the image model → prevents CLS), `loading="lazy"` below the fold, **hero preloaded/eager**. The **same** component markup is what the 47.1 prerender emits in `content_html`, so the CSR swap (47.2) causes **no CLS** (byte-identical lazy/`<picture>`/dims). LCP target = the hero image path.

## 6. The worked extension — `cms-youtube` (separate plugin, zero cms change)

`vbwd-fe-user-plugin-cms-youtube`: in `install()` calls `registerPostContentType('youtube', YouTubeEmbed, { placement:'top' })`. `YouTubeEmbed.vue` renders a **privacy-friendly, responsive** embed (`youtube-nocookie.com`, `loading="lazy"`, 16:9 box, `title` for a11y) from `data={ video_id|url, title? }`. Because it's `placement:'top'`, any post with a `youtube` block shows the video **as the topmost element**. Ships `config.json`+`admin-config.json`(+`debug_mode`)+locales (baseline rule). The template for future types (`gallery`,`video`,`audio`,…).

## 7. TDD (RED first)
- `PostList`: renders N cards; `mode` toggles excerpt/full; `meta[]` shows exactly the configured fields in order; empty → empty-state (no crash). `PostCard`: title links to detail; image lazy + dims; time-ago formatting.
- `contentTypeRegistry`: register/resolve; unknown → fallback (no throw); `placement` honored; **late registration triggers re-render** (§3.1).
- `PostDetail`: renders blocks in order; `top` block renders above in-flow; back-compat (no blocks → `content_html` as one richtext); SEO meta present + deduped; a **hierarchical page renders a breadcrumb** from its parent chain.
- `PostTermListWidget`: reads config from `content_json`; calls `byTerm` with right args; renders `PostList`; empty/unknown term → graceful.
- `cms-youtube`: registers on install; builds correct `youtube-nocookie` src from `video_id` and full URL; lazy + aspect-ratio; a post with a youtube block shows the embed **first/topmost**; uninstall removes it with **no cms change**.

## 8. Acceptance
- An admin places a `PostTermList` widget (`type=post, term_type=category, term_slug=news, mode=excerpt, meta=[author,time_ago,tags]`) on a cms page → it lists that category's published posts with exactly those fields. Clicking a card opens the post detail with content + SEO meta.
- The same `PostList` renders the term widget today and search results (47.4) tomorrow — one component.
- A post with `blocks:[{type:'youtube',position:0},{type:'richtext',…}]` shows the embed at the very top; an unknown block never breaks the page; a legacy `content_html`-only post renders unchanged.
- Content pages ship AVIF/WebP images with explicit dims, lazy below-fold, hero preloaded (Lighthouse spot-check meets LCP/CLS).
- fe-user lint+test GREEN; widget + youtube e2e GREEN.

## 9. Out of scope
Search (47.4), RSS (47.5), fe-admin authoring (47.6), rich admin block-builder UI, server-side oEmbed, non-YouTube providers (each its own extension plugin), likes/comments.

## 10. Engineering-requirements check
- **DRY:** one `PostList` + one `usePosts` feed every source; one block-render loop; the image component markup is shared with the prerender.
- **Core agnostic / OCP:** content types + term widgets via registries from **separate plugins**; cms/core untouched (the `cms-youtube` plugin is the proof).
- **Liskov:** unknown block → safe fallback; every renderer honors the same block contract.
- **NO OVERENGINEERING:** blocks in `content_json` (no new table); one example provider; archives stay CSR.
