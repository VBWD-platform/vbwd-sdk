# S47.4 — Full-text search (Postgres FTS) + search widget

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Depends on:** [S47.0](s47-0-unified-data-model-and-registries.md), [S47.3](s47-3-public-rendering-and-content-types.md) · **Status:** DRAFT — 2026-06-03
**Repos:** `vbwd-plugin-cms` (FTS backend), `vbwd-fe-user-plugin-cms` (search widget).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin cms --full` GREEN; fe-user `npm run lint && npm run test` GREEN.

---

## 1. Goal

Search published posts and show results **through the same `PostList`** (47.3). Ship **two decoupled `vue-component` widgets** — a **Search** box and a **Search-results** list — so an admin can place the box and the results on the **same page or on different pages** (box in a header, results on `/search`). **Search result pages are CSR + `noindex` + sitemap-omitted** (D8 — thin/duplicate content; you do not want `?q=` URLs indexed).

## 2. Backend — Postgres FTS

- **Migration (in-plugin):** add a `tsvector` search column to `cms_post`, **`GENERATED ALWAYS AS (to_tsvector(...))`** from `title` (weight A) + `excerpt` (B) + stripped `content_html` (C), + a **GIN index**. Prefer the generated column so it stays correct without trigger code; fall back to a trigger only if the HTML-strip must be Python. Language config from `post.language` where practical (default `english`/`simple`).
- **`SearchService.search(query, *, type=None, page, per_page, term_filter=None) -> Page[PostSummary]`** via `websearch_to_tsquery`, ranked by `ts_rank`, **published only**, optional `type` + term filter (so "search within category" composes). Returns the **same summary shape** `PostList` consumes (DRY). Blank/empty `q` → empty result (not all posts).
- **Route:** `GET /api/v1/cms/search?q=&type=&page=&term_type=&term_slug=` → paginated summaries + total. Cheap read (rate-limit-friendly).

## 3. fe-user — TWO decoupled widgets (Search box + Search-results)

Registered in the cms `vueComponentRegistry` as **separate** `vue-component` widgets that communicate via the URL `?q=` param (shareable, back-buttonable):
- **`Search`** (`PostSearch.vue`) — the **search box**: a debounced input; config `{ placeholder, target_path? }`. On submit/typing it **URL-syncs `?q=`**, navigating to `target_path` if the results live on another page.
- **`SearchResults`** (`PostSearchResults.vue`) — reads `?q=` from the URL, calls `usePosts.bySearch` (added here), and renders results via **`PostList`** (47.3) with loading / empty / "no results" states; config `{ type?, mode, meta[], per_page, scope_term_type?, scope_term_slug? }`.

The hosting cms page(s) carry `robots: noindex` (D8). Together with the 47.3 **Category** widget this is the WP-style trio: **Category · Search · Search-results**.

## 4. TDD (RED first)
- **Backend:** matches title/excerpt/body; ranks; excludes unpublished; blank `q` → empty; `type` + term filter narrow; pagination/total. **Integration (real PG)** asserts the **GIN index is used** (EXPLAIN) on a seeded set.
- **fe-user:** `Search` debounces + URL-syncs `?q=` (and navigates to `target_path`); `SearchResults` reads `?q=` and renders via `PostList`; empty-query + no-results states; both read config from `content_json`; **the two compose across pages** via the URL param.

## 5. Acceptance
- `GET /cms/search?q=hospitality` returns ranked published posts; `&type=post&term_type=category&term_slug=news` narrows to that category.
- The **Search** box and **Search-results** widgets work both on one page **and split across pages** (box in a header → results on `/search`), via `?q=`; results render identically to the **Category** widget (same `PostList` cards).
- Search pages are `noindex` and absent from the sitemap.
- `--plugin cms --full` + fe-user lint/test GREEN.

## 6. Out of scope
Typeahead/autocomplete, fuzzy/`pg_trgm` matching, cross-plugin global search, search analytics. (Revisit `pg_trgm` only if fuzzy is requested.)

## 7. Engineering-requirements check
- **DRY:** results reuse `PostList`; `SearchService` returns the same summary shape as the term query.
- **DevOps-first:** FTS column + GIN via in-plugin migration; integration proves index usage from cold start.
- **NO OVERENGINEERING:** native PG FTS (no external engine); generated column over trigger where possible.
