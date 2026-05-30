# S42.2 — Full-text search (Postgres FTS) + the "search" widget

**Parent:** [S42 — vbwd-press](s42-vbwd-press.md) · **Depends on:** [S42.0](s42-0-data-model-terms-crud.md), [S42.1](s42-1-post-list-and-term-widget.md) · **Status:** DRAFT — 2026-05-29
**Repos:** `vbwd-plugin-press` (backend FTS), `vbwd-fe-user-plugin-press` (search widget).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin press --full` GREEN; fe-user `npm run lint && npm run test` GREEN.

---

## 1. Goal

Search published posts and show results **through the same `PressPostList`** (42.1). A "search" widget (field + results) drops into any cms page as a `vue-component` widget.

## 2. Backend — Postgres FTS

- **Migration (in-plugin):** add a `tsvector` search column to `vbwd_press_post` (generated/maintained from `title` + `excerpt` + `content_html`-stripped text, weighted A/B/C) + a **GIN index**. Prefer a Postgres **generated `tsvector` column** (`GENERATED ALWAYS AS (to_tsvector(...))`) so it stays correct without trigger code; fall back to a trigger only if the stripped-HTML transform needs Python. Language config from the post's `language` where practical (default `simple`/`english`).
- **`SearchService.search(query, *, page, per_page, term_filter=None) -> Page[PostSummary]`** using `plainto_tsquery`/`websearch_to_tsquery`, ranked by `ts_rank`, **published only**, optional term filter (so "search within category" composes). Returns the same summary shape `PressPostList` consumes (DRY).
- **Route:** `GET /api/v1/press/search?q=&page=&term_type=&term_slug=` → paginated summaries + total. Empty/blank `q` → empty result (not all posts). Rate-limit-friendly (cheap read).

## 3. fe-user — the search widget

- `PressSearchWidget.vue` — registered in the cms `vueComponentRegistry` under e.g. `PressSearch`; config from `content_json`: `{ placeholder, mode, meta[], per_page, scope_term_type?, scope_term_slug? }`.
- Renders a **search field** (debounced) + **results below**, results rendered by `PressPostList` (42.1). Loading + empty + "no results" states. URL-syncs `?q=` so a search is shareable/back-button-able. Calls `usePressPosts.bySearch` (added here).
- An admin creates a `vue-component` widget `content_json.component="PressSearch"` and places it anywhere (e.g. a `/search` cms page, or a sidebar).

## 4. TDD (RED first)
- **Backend:** `SearchService` matches title/excerpt/body; ranks; excludes unpublished; blank query → empty; term filter narrows; pagination/total. Integration against real PG asserting the GIN index is used (EXPLAIN) on a seeded set.
- **fe-user:** widget debounces; renders results via `PressPostList`; empty-query + no-results states; `?q=` URL sync; reads config from `content_json`.

## 5. Acceptance
- `GET /press/search?q=hospitality` returns ranked published posts; `&term_type=category&term_slug=news` narrows to that category.
- The search widget on a cms page returns results rendered identically to the term widget (same cards/metadata).
- `--plugin press --full` GREEN; fe-user lint+test GREEN.

## 6. Out of scope
Typeahead/autocomplete suggestions, fuzzy/trigram matching, cross-plugin global search, search analytics. (Generated `tsvector` keeps it simple; revisit `pg_trgm` only if fuzzy is requested.)

## 7. Engineering-requirements check
- **DRY:** results reuse `PressPostList`; `SearchService` returns the same summary shape as the term query.
- **DevOps-first:** FTS column + GIN via in-plugin migration; integration proves index usage from cold start.
- **NO OVERENGINEERING:** native PG FTS, no external search engine; generated column over trigger where possible.
