# Sprint 54 — CMS: bulk-assign layout + default-layout fallback

**Status:** DONE — 2026-06-07 (owner-confirmed).
**Repos touched:** `vbwd-backend` (`plugins/cms`: bulk action + config key + render-time resolution) · `vbwd-fe-admin` (`plugins/cms-admin`: bulk "Assign layout" control + settings field) · `vbwd-fe-user` (`plugins/cms`: consume the resolved layout). No core change — all logic lives in the `cms` plugin trio ([[feedback_core_never_depends_on_plugins]]).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** (narrowest change that satisfies the requirement) · **plugin baseline config files** ([[feedback_plugin_baseline_config_files]]) · test/demo data only through services ([[feedback_no_direct_db_for_test_data]]). **Gate:** `bin/pre-commit-check.sh --plugin cms --full` green on the backend; `npm run lint && npm run test` green on both fe apps.

---

## 1. Problem

Freshly **imported** pages/posts land with **no layout** (`layout_id = NULL`). At render time the fe-user public renderer then falls back to a bare `<article>` (no header/footer/chrome), so imported content looks broken until each page is opened and a layout is picked by hand — unworkable at import scale.

Two gaps, addressed by two independent, complementary parts:

- **Part B (safety net): a default layout.** No page should ever render layout-less. A `default_layout_id` defined in the **cms backend plugin settings** is used **at render time** whenever a page/post has no explicit `layout_id`. This immediately fixes every imported (and any future layout-less) page without mutating data.
- **Part A (explicit fix): bulk-assign a layout.** Add an **"Assign layout"** bulk action to the page/post admin list so an admin can set a real layout on many items at once (e.g. all freshly imported pages), overriding the default permanently in the data.

This is the **same shape the CMS already uses for styles** — `resolved_style_id` resolves *explicit-else-default* server-side ([[feedback_cms_styling_no_theme_switcher]]). S54 gives **layouts** the identical treatment. That symmetry is the design: mirror `_with_resolved_style()` → `_with_resolved_layout()`; mirror the style `resolved_*` consumption in fe-user.

## 2. Context (verified)

- **Model already supports it — no migration.** `cms_post.layout_id` is a nullable, indexed `UUID` FK → `cms_layout.id` (`ondelete=SET NULL`) (`plugins/cms/src/models/cms_post.py:116-121`). `CmsLayout` + `CmsLayoutRepository` exist; layouts list at `GET /api/v1/admin/cms/layouts` (`routes.py:1077-1093`). **S54 adds no schema** — only a config key, a service method, and a route.
- **Style already does the fallback we want.** `PostService._with_resolved_style()` (`post_service.py:155-181`) computes `resolved_style_id` (+ source). The public path `resolve_published_path()` (`post_service.py:257-269`, served by `GET /api/v1/cms/posts/<slug>` `routes.py:2291-2312`) returns `post.to_dict()`. **Layout has no such resolution yet** — that's the Part B insertion point.
- **fe-user consumes resolved style, not layout.** `useCmsStore._fetchPostAssets` uses `post.resolved_style_id ?? post.style_id` for CSS but `post.layout_id` directly for layout (`vbwd-fe-user/plugins/cms/src/stores/useCmsStore.ts:302-312`). `CmsPage.vue:62-85` renders `<CmsLayoutRenderer>` when a layout exists, else a bare `<article>`.
- **Bulk actions are per-action POSTs.** Current: `/posts/bulk` (delete), `/posts/bulk/status`, `/posts/bulk/searchable`, `/posts/bulk/assign-term` (`routes.py:1960-2014`), backed by `PostService.bulk_*` (`post_service.py:419-459`). The list UI (`CmsContentList.vue`, used for both pages and posts) renders the bulk bar with an "Assign to a category" select (`:156-217`) calling `store.bulkAssignTerm`; selection state via `useCmsBulkSelection` (`resolveIds()` handles explicit ids + "all matching"). Layouts are already fetched into the list (`store.fetchLayouts({per_page:100})`, store `:141-143`, state `store.layouts.items`).
- **cms plugin config** lives in `plugins/cms/__init__.py` `DEFAULT_CONFIG` (`:9-35`), read at runtime via `current_app.config_store.get_config("cms")` (route helper `_cms_config()` `routes.py:372-383`).

## 3. Design

### Part A — bulk "Assign layout"

**Backend (mirror `assign-term`):**
- `PostService.bulk_assign_layout(ids: list[str], layout_id: str) -> dict` (after `:459`): validate `layout_id` via `CmsLayoutRepository.find_by_id` (raise the existing `InvalidLayoutOrStyleError` if missing — same as single-post update `_apply_layout_style`); set `post.layout_id` on each; `self._repo.save(post)`; emit `content.changed (reason="updated")` per post (keeps SEO prerender consistent); return `{"updated": n}`.
- Route `POST /api/v1/admin/cms/posts/bulk/assign-layout` (after `:2014`), `require_admin` + `cms.manage` like its siblings; body `{ ids: [...], layout_id: "<uuid>" }`; `400` on validation failure.
- **No raw SQL** — through the service/repo ([[feedback_no_direct_db_for_test_data]]).

**fe-admin (`CmsContentList.vue`, mirror "Assign to a category"):**
- A layout-picker `<select data-testid="bulk-assign-layout">` in the bulk-bar actions slot (gated by `canManage`), options from `store.layouts.items` (already loaded). On change → `onBulkAssignLayout(layoutId)`: `ids = await bulk.resolveIds()` (respects explicit + all-matching), guard empty, `await store.bulkAssignLayout(ids, layoutId)`, `bulk.clear()`, `load()`, reset the select.
- Store: `bulkAssignLayout(ids, layoutId)` → `api.post('/admin/cms/posts/bulk/assign-layout', { ids, layout_id: layoutId })` (after `bulkAssignTerm`).
- i18n key `cms.assignLayout` ("Assign layout") across the existing cms-admin locale set.

### Part B — default layout (render-time, explicit-else-default)

**Config (single source of truth = cms backend plugin settings, per the task):**
- Add `"default_layout_id": None` to cms `DEFAULT_CONFIG` (`__init__.py`), plus the matching entry in the plugin's `config.json`; surface it in `admin-config.json` so an admin sets it in the **cms plugin settings** (see §3.1 for the picker). Empty/None → no default (today's behaviour, bare `<article>`).

**Backend resolution (mirror `_with_resolved_style`):**
- `PostService._with_resolved_layout(post_dict) -> post_dict`: if `layout_id` set → `resolved_layout_id = layout_id`, `resolved_layout_source = "explicit"`; else if config `default_layout_id` set **and the layout still exists** → `resolved_layout_id = default_layout_id`, source `"default"`; else `resolved_layout_id = None`, source `"none"`. Read config via `current_app.config_store.get_config("cms")` (same access the routes use; inject/resolve consistently with how the service already reaches style defaults — verify before coding).
- Apply it in the **public render path** (`resolve_published_path` and any sibling that returns a published post dict) right where `_with_resolved_style` is applied, so the public payload carries `resolved_layout_id` + `resolved_layout_source`. **Admin/editor payloads keep raw `layout_id`** (the editor must show the real, possibly-empty value — never the default — so "no layout" stays visible and bulk-assign/clear is honest).

**fe-user (mirror style consumption):**
- `useCmsStore._fetchPostAssets`: `const layoutId = post.resolved_layout_id ?? post.layout_id;` then fetch as today. `CmsPage.vue` is unchanged — it already renders `<CmsLayoutRenderer>` whenever a layout resolves, bare `<article>` only when truly none.

#### 3.1 Where the admin sets the default — RECOMMENDATION (open for negotiation)

The default's home is the **cms plugin config** (`default_layout_id`) per the task. The only question is the admin control to choose it. **Recommended:** a layout `<select>` in the cms plugin settings tab (`admin-config.json`), populated from `GET /api/v1/admin/cms/layouts`. If the generic settings-field framework can't render a catalog-backed dropdown, the **narrowest** alternative is a small **"Set as default layout"** affordance on the existing layouts list (`CmsLayoutList.vue`) that writes `cms.default_layout_id` via the plugin-config update endpoint, with the current default badged in the list. (Considered + rejected for now: an `is_default` boolean on `CmsLayout` — diverges from the task's "in plugin settings" instruction and adds a migration; styles use `is_default`, but the task explicitly puts the layout default in config.)

### 3.2 Deliberately NOT built (NO OVERENGINEERING)

- **No auto-mutation on import.** Import does not write the default into `layout_id`; the render-time fallback covers imported pages without dirtying data, and bulk-assign is the explicit override. (Auto-assign-on-import is a possible later nicety, out of scope.)
- No bulk style-assign (this sprint is layout-only; the same pattern trivially extends later if asked).
- No per-page "use default" toggle — empty `layout_id` *is* "use default".

## 4. TDD plan (RED first)

**Backend (`vbwd-backend`, pytest — `--plugin cms`):**
- `PostService.bulk_assign_layout`: sets `layout_id` on all given ids + returns `{updated:n}`; unknown `layout_id` → `InvalidLayoutOrStyleError`; emits `content.changed` per post. (MagicMock repos.)
- Route `POST /posts/bulk/assign-layout`: admin-only (403 without `cms.manage`); happy path `200 {updated}`; bad layout → 400. (integration with `db` fixture for the round-trip.)
- `_with_resolved_layout`: explicit `layout_id` → source `explicit`; no `layout_id` + config default set → `resolved_layout_id == default`, source `default`; default points at a deleted layout → source `none`; no default → source `none`. Public `resolve_published_path` payload carries the resolved fields; **admin payload keeps raw `layout_id`** (no default leak into the editor).

**fe-admin (Vitest):**
- `CmsContentList`: the `bulk-assign-layout` select renders layouts; choosing one calls `store.bulkAssignLayout(selectedIds, layoutId)` then clears selection + reloads; empty selection → no call.
- store `bulkAssignLayout` posts the right body to the right endpoint (api mocked).

**fe-user (Vitest):**
- `_fetchPostAssets` prefers `resolved_layout_id` over `layout_id`; a post with no `layout_id` but a `resolved_layout_id` (default) fetches and renders that layout (not bare `<article>`); a truly layout-less post still renders `<article>`.

## 5. Files (indicative)

| Action | Path |
|---|---|
| edit | `vbwd-backend/plugins/cms/src/services/post_service.py` — `bulk_assign_layout`, `_with_resolved_layout`, apply in `resolve_published_path` |
| edit | `vbwd-backend/plugins/cms/src/routes.py` — `POST /admin/cms/posts/bulk/assign-layout` |
| edit | `vbwd-backend/plugins/cms/__init__.py` — `default_layout_id` in `DEFAULT_CONFIG` |
| edit | `vbwd-backend/plugins/cms/config.json` + `admin-config.json` — expose `default_layout_id` (layout picker, §3.1) |
| edit | `vbwd-backend/plugins/cms/tests/...` — service + route + resolution tests |
| edit | `vbwd-fe-admin/plugins/cms-admin/src/views/CmsContentList.vue` — bulk "Assign layout" select + handler |
| edit | `vbwd-fe-admin/plugins/cms-admin/src/stores/useCmsContentStore.ts` — `bulkAssignLayout` |
| edit | `vbwd-fe-admin/plugins/cms-admin/locales/*.json` — `cms.assignLayout` |
| edit | `vbwd-fe-admin/plugins/cms-admin/.../CmsLayoutList.vue` — "Set as default" affordance (only if §3.1 alternative chosen) |
| edit | `vbwd-fe-user/plugins/cms/src/stores/useCmsStore.ts` — prefer `resolved_layout_id` |
| edit | tests in both fe apps |

## 6. Acceptance

- In the page/post admin list, selecting rows shows an **"Assign layout"** picker; choosing a layout assigns it to all selected (explicit or all-matching) and the list reflects it. Bad/no layout → no-op / clear error; admin-only.
- An admin sets a **default layout** in the **cms plugin settings**. A published page/post **with no `layout_id`** (e.g. freshly imported) now renders **with the default layout** on fe-user — not a bare `<article>`. Clearing the default restores today's behaviour.
- The **editor** still shows a layout-less page as "no layout" (the default never silently appears as the page's own value); a page with an explicit layout is unaffected by the default.
- `bin/pre-commit-check.sh --plugin cms --full` green; fe-admin + fe-user `lint && test` green.

## 7. Out of scope

- Auto-writing the default into `layout_id` on import (render-time fallback handles it).
- Bulk style assignment; per-page default toggle; default *style* changes (styles already resolve explicit-else-default).

## 8. Engineering-requirements check

- **Core agnostic / NO OVERENGINEERING:** changes live entirely in the `cms` plugin trio; no schema/migration (reuses existing `layout_id`); the default is one config key + one resolution method that **mirrors the proven `_with_resolved_style` pattern** rather than inventing a new mechanism.
- **SOLID/DRY/Liskov:** `bulk_assign_layout` parallels `bulk_assign_term`; `_with_resolved_layout` parallels `_with_resolved_style`; fe-user consumes `resolved_layout_id` exactly as `resolved_style_id`.
- **Render vs data integrity:** the default is applied only on the **public** payload; admin/editor payloads keep the raw value so "no layout" stays truthful and bulk-assign is the only thing that mutates data.
- **Plugin baseline:** `default_layout_id` shipped in `config.json` + `admin-config.json`; `debug_mode` already present.
- **TDD-first / gate:** service + route + resolution + fe specs land RED first; pre-commit gate green on all three repos = done. Implementation delegated to the **`vbwd-tdd`** agent. [[feedback_use_tdd_agent_for_implementation]]
