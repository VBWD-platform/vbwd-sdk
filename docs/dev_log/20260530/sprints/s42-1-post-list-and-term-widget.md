# S42.1 — Generic PressPostList + post detail + the "category/term" widget

**Parent:** [S42 — vbwd-press](s42-vbwd-press.md) · **Depends on:** [S42.0](s42-0-data-model-terms-crud.md) · **Status:** DRAFT — 2026-05-29
**Repos:** `vbwd-fe-user-plugin-press` (+ a thin backend post-query endpoint if not already in 42.0).
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: fe-user `npm run lint && npm run test` GREEN; e2e of the widget on a running stack.

---

## 1. Goal

The **DRY spine**: one generic post-list component every source feeds, the post-detail view, and the first widget — a "category/term" listing — registered as a `vue-component` CMS widget so an admin can drop it into any page/layout area.

## 2. fe-user — `vbwd-fe-user/plugins/press/`

### 2.1 `PressPostList.vue` (the generic list — the spine)
- **Input:** a list of post summaries (from the 42.0 read endpoint) + a `display` config. **Does NOT fetch by itself** — sources (widget, search, term page) pass it data, so it stays the single render path for every listing.
- Renders `PostCard.vue` per post. **`display` config:**
  - `mode`: `titles` | `excerpt` | `full` | `gallery` | `video` (controls how much of each card shows; `gallery`/`video` defer to the 42.3 content-type renderers for the media).
  - `meta`: an **ordered, configurable** set from `["author","time_ago","tags","published_at","reading_time"]` — the card shows exactly these (the "configurable set of variables" requirement).
- `PostCard.vue`: title (links to detail), the configured metadata row, excerpt, and lead image (lazy, explicit dims — S40 CWV).

### 2.2 `usePressPosts` composable / query service
One place that calls the 42.0 endpoints: `byTerm(term_type, slug, page)`, `bySlug(slug)`, (42.2 adds `bySearch`). Returns summaries for `PressPostList`. Pagination state here, not in the components.

### 2.3 Post detail — `PressPostDetail.vue`
- Route registered by the plugin (e.g. `/blog/:slug` or a cms catch-all integration — confirm with cms routing). Fetches `bySlug`, renders title + metadata + content. **Body renders through the content-type renderer registry (42.3); until then, rich-text/`content_html`.**
- Injects SEO meta via the **S40 shared meta-builder** (Article JSON-LD + canonical + og); server-delivered for crawlers through S40's render path.

### 2.4 The "category/term" widget (registered Vue component)
- `PressTermListWidget.vue` — registered via `resolveCmsVueComponent`/the cms `vueComponentRegistry` under a name (e.g. `PressTermList`) in the plugin's `install()` (same mechanism shop/booking use).
- Reads its **config from the widget's `content_json`** (cms passes it): `{ term_type, term_slug, mode, meta[], limit, paginate }`. Fetches via `usePressPosts.byTerm` and renders `PressPostList`.
- An admin creates a `vue-component` cms widget with `content_json.component = "PressTermList"` + the config, and places it in any area — no press route needed for a category page; it's a cms page hosting the widget.

## 3. TDD (RED first)
- `PressPostList`: renders N cards; `mode` toggles excerpt/full; `meta[]` shows exactly the configured fields in order; empty → empty-state (no crash).
- `PostCard`: title links to detail; image lazy + dims; metadata formatting (time-ago).
- `PressTermListWidget`: reads config from `content_json`; calls `byTerm` with the right args; renders the list; unknown/empty term → graceful empty.
- `PressPostDetail`: renders a post; sets SEO meta via the shared builder (assert tags present).
- Mirror existing fe-user/cms test idioms (Vitest, pinia, i18n).

## 4. Acceptance
- Admin places a `PressTermList` `vue-component` widget (config `term_type=category, term_slug=news, mode=excerpt, meta=[author,time_ago,tags]`) on a cms page → the page lists that category's published posts as cards with exactly those metadata fields.
- Clicking a card opens the post detail at its slug with content + SEO meta.
- The same `PressPostList` renders the term widget today and the search results (42.2) tomorrow — one component.
- fe-user lint+test GREEN; widget e2e GREEN.

## 5. Out of scope
Search (42.2), gallery/video media rendering internals + the extensibility registry (42.3), RSS (42.4). `mode: gallery|video` may render a placeholder until 42.3.

## 6. Engineering-requirements check
- **DRY:** `PressPostList` is the sole list renderer; `usePressPosts` the sole fetch path.
- **Core agnostic:** the widget uses the existing cms vue-component registry; no cms edit.
- **SOLID:** list is presentational (data in via props); sources own fetching.
- **NO OVERENGINEERING:** config-driven display; no per-source bespoke lists.
