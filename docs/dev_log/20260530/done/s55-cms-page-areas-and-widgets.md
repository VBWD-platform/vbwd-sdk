# Sprint 55 — CMS: per-page content-areas + page widgets on the unified post

**Status:** DONE — 2026-06-07 (S55.0–55.3 implemented + live-verified; 55.4 retirement deferred).
**Repos touched:** `vbwd-backend` (`plugins/cms`: 2 models + migration + repos + routes) · `vbwd-fe-admin` (`plugins/cms-admin`: PostEditor content-area blocks + page-widgets panel + store) · `vbwd-fe-user` (`plugins/cms`: store passes `content_blocks` + `page_assignments` to the already-capable renderer). **No core change** — all logic in the `cms` plugin trio ([[feedback_core_never_depends_on_plugins]]).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** (narrowest change that satisfies the requirement) · plugin migrations live in the plugin ([[feedback_plugin_migrations_in_plugin]]) · test/demo data only through services ([[feedback_no_direct_db_for_test_data]]). **Gate:** `bin/pre-commit-check.sh --plugin cms --full` green (backend); `npm run lint && npm run test` green on both fe apps.

---

## 1. Problem (verified review, 2026-06-06)

The S47 unification moved authoring from legacy `cms_page` to the unified `cms_post`, but **dropped two `cms_page` features and never ported them to `cms_post`**:

1. **Multiple content areas.** A `cms_layout` can declare several `type:"content"` areas (e.g. `content`, `content-above`, `sidebar-content`). The legacy page had a `cms_page_content_block` per area. The unified `PostEditor` renders **one** content body (`content_html`) and **never reads the layout's `areas`** — so every content slot shows the same single body.
2. **Per-page widgets.** Legacy `cms_page_widget` let an admin assign a widget to a page area *on the page's edit screen*, overriding the layout's widget for that area — its own docstring: *"Allows pages to have unique widgets without creating separate layouts."* The unified path has **no `cms_post_widget`, no `/posts/<id>/widgets` route, no editor UI** — so the only widget mechanism is layout-wide (`cms_layout_widget`), forcing admins to **clone a whole layout to change one widget**. This is the user-reported pain.

**The fe-user renderer is already capable** (`CmsLayoutRenderer.vue`): for each `area.type==='content'` it uses `contentBlocks[area.name].content_html` (falling back to the main `contentHtml`); for widget areas `widgetFor()` uses `pageAssignments` (page-level) **and falls back to** `layout.assignments` (layout-level). It's simply **starved** — the posts endpoint returns neither `content_blocks` nor `page_assignments`, and the store has no field to hold them. **This sprint supplies the data + the editor; the renderer largely already works.**

**Dead-code note (separate, deferred — see §6):** `cms_page`, `cms_page_content_block`, `cms_page_widget` and `CmsPageEditor.vue` are now orphaned (Pages opens the unified `PostEditor`; the legacy admin/public page routes are unreachable from the UI; only the backfill CLI reads `cms_page`). Retiring them is **not** part of S55 — it's a follow-up cleanup.

## 2. Contract (verified shapes to mirror)

- **Layout area** (`cms_layout.areas` JSON list): each `{ name, type, ... }`; `type ∈ {header, footer, hero, slideshow, content, three-column, two-column, cta-bar, vue, page-widget}` (`cms_layout.py`).
- **Renderer** (`CmsLayoutRenderer.vue`): `contentBlocks?: Record<string,{content_html?,source_css?}>`; `pageAssignments?: WidgetAssignment[]` where `WidgetAssignment = {area_name, widget_id, widget, sort_order, required_access_level_ids}`. `widgetFor(area)` = page-assignment-by-area **else** layout-assignment-by-area. `contentBlockHtml(area)` = `contentBlocks[area].content_html` **else** `contentHtml`.
- **Legacy mirrors:** `cms_page_widget` (`page_id, widget_id, area_name, sort_order, required_access_level_ids`) and `cms_page_content_block` (`page_id, area_name, content_json, content_html, source_css, sort_order`, unique `(page_id, area_name)`). Legacy admin widget routes: `GET/PUT /api/v1/admin/cms/pages/<id>/widgets`. Legacy public enrichment: `/cms/pages/<slug>` returns `page_assignments` (access-filtered + each widget enriched via `widget_svc.get_widget`).

## 3. Design (mirror legacy onto `cms_post`)

**Primary content stays `content_html`** (keeps SEO/prerender/search/RSS untouched). The **first** `type:content` layout area binds to `content_html`; **each additional** content area binds to a `cms_post_content_block` row. The renderer's per-area fallback means the primary area renders from `content_html` and extra areas from their blocks — zero renderer change for the primary path.

### Data model (new plugin migration — `plugins/cms/migrations/versions/`)
- **`cms_post_widget`** — mirror of `cms_page_widget`: `post_id` FK→`cms_post.id` (CASCADE), `widget_id` FK→`cms_widget.id` (RESTRICT), `area_name`, `sort_order`, `required_access_level_ids` (JSON). No unique (an area may hold multiple ordered widgets, as legacy).
- **`cms_post_content_block`** — mirror of `cms_page_content_block`: `post_id` FK→`cms_post.id` (CASCADE), `area_name`, `content_json`, `content_html`, `source_css`, `sort_order`; unique `(post_id, area_name)`.
- Migration registered in `alembic.ini version_locations`; resolves standalone ([[project_migration_graph_fragmentation]] discipline — anchor on a cms revision, not another plugin).

### Backend
- Repos: `CmsPostWidgetRepository(find_by_post, replace_for_post)` + `CmsPostContentBlockRepository(find_by_post, replace_for_post)` — direct mirrors of the page repos. Register as DI providers if the route factories need them ([[project_plugin_di_provider_registration]]); else instantiate with `db.session` like the page repos.
- **Widgets endpoint** (mirror legacy): `GET /api/v1/admin/cms/posts/<id>/widgets` + `PUT .../widgets` (replace; body = array of `{widget_id, area_name, sort_order, required_access_level_ids}`), perm `cms.manage`.
- **Content blocks:** carried in the post create/update payload — `PostService.create_post/update_post` accept optional `content_blocks: [{area_name, content_html, source_css, sort_order, content_json?}]` and upsert them (primary area excluded — it's `content_html`). Mirror legacy `_apply_data`.
- **`admin_get_post`** returns `content_blocks` (dict keyed by area) + `page_assignments` (enriched) so the editor can load existing values.
- **Public `GET /cms/posts/<slug>`** enrichment (mirror `/cms/pages/<slug>:512-533`): add `content_blocks` (dict `{area_name:{content_html,source_css}}`) + `page_assignments` (access-filtered via `_filter_assignments_by_access`, each enriched via `_widget_service().get_widget`).

### fe-admin (`PostEditor.vue` + `useCmsAdminStore`)
- On layout select/load, read `layout.areas`. **Content areas:** first `type:content` area → the existing content editor (→ `content_html`); each additional content area → its own collapsible HTML/CSS editor bound to `form.content_blocks[area_name]`.
- **Page widgets panel:** for each layout area (esp. `type:'page-widget'`/widget areas, but allow any area to take an override), a row to pick a widget (from `store.widgets`) + optional access levels + sort; bound to `form.page_widgets[]`.
- **Save flow:** post create/update (now includes `content_blocks`) **then** `PUT /posts/<id>/widgets` (like terms are a separate PUT). Store actions: `fetchPostWidgets(id)`, `savePostWidgets(id, list)`; `content_blocks` ride the post payload.
- Single-content-area / no-layout pages are unchanged (one content editor → `content_html`).

### fe-user (`useCmsStore` + `CmsPage.vue`)
- Extend `CmsPageItem` with `content_blocks?: Record<string,{content_html?,source_css?}>` and `page_assignments?: WidgetAssignment[]`; `_fetchPostRaw`/`fetchPage` pass them through; `CmsPage.vue` feeds `:content-blocks` + `:page-assignments` to `CmsLayoutRenderer` (it already accepts them). **Renderer unchanged.**

## 4. SEO / prerender scope (explicit)
Prerender, FTS search, RSS, sitemap continue to use the **primary `content_html`** (main area) — unchanged. Additional content areas + page widgets render **client-side** (progressive enhancement); they are secondary, lower-SEO-value regions (sidebars/CTAs). Reworking the prerender pipeline to compose the full multi-area layout is **out of scope** (future). Document the limitation.

## 5. TDD plan (tests FIRST)
- **Backend unit** (MagicMock repos): `CmsPostWidgetRepository.replace_for_post` replaces; `find_by_post` ordered by sort_order; content-block upsert by `(post_id, area_name)`; `PostService` applies `content_blocks` on update and skips the primary area.
- **Backend integration** (`db`): create post → PUT widgets → `GET admin post` returns `page_assignments`; public `/cms/posts/<slug>` returns `content_blocks` + access-filtered `page_assignments` (enriched widget); a page-widget **overrides** a layout-widget for the same area (assert the public payload yields the page widget); access-level filtering hides a gated widget. Migration up/down clean.
- **Core-agnosticism oracle** + **vocabulary oracle** stay green (all in plugin; no core touch).
- **fe-admin vitest:** PostEditor renders N content-block editors for a layout with N content areas; renders the page-widgets panel; save calls post PUT (with `content_blocks`) + `/posts/<id>/widgets`; single-content-area layout renders one editor (no regression).
- **fe-user vitest:** store maps `content_blocks` + `page_assignments` from the posts endpoint; `CmsPage` passes them to `CmsLayoutRenderer`; a per-page widget overrides the layout widget in the rendered output.

## 6. Sub-sprints
- **S55.0 — backend models + migration + repos** (`cms_post_widget`, `cms_post_content_block`; DI). `--plugin cms --full` green.
- **S55.1 — backend routes + enrichment** (post widgets GET/PUT; `content_blocks` in create/update + `admin_get_post`; public posts endpoint returns `content_blocks` + `page_assignments`). TDD; gate green.
- **S55.2 — fe-admin PostEditor** (layout-area-driven content blocks + page-widgets panel + store + save flow). vitest + lint green.
- **S55.3 — fe-user store + CmsPage wiring** (pass `content_blocks` + `page_assignments` to the renderer). vitest + lint green; manual: a page with 2 content areas + a per-page widget renders correctly.
- **S55.4 — (DEFERRED, separate) retire dead `cms_page` / `cms_page_content_block` / `cms_page_widget` + `CmsPageEditor.vue` + legacy routes.** Tracked, not in S55.

## 7. Definition of done
A page/post on a multi-content-area layout shows **one editor per content area** and renders distinct content per area; an admin can **assign a widget to a page area on the edit screen** (overriding the layout widget) **without cloning the layout**; both flow through the existing `CmsLayoutRenderer` (page-over-layout widget priority, per-area content). Public + admin post endpoints return `content_blocks` + `page_assignments`; access-level filtering honored; primary `content_html` (SEO) unchanged; single-area pages unchanged. `--plugin cms --full` green; both fe apps lint+test green; core agnosticism + vocabulary oracles green. Not committed.
