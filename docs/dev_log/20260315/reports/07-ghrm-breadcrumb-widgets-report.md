# Sprint 07 — GHRM Breadcrumb Widgets — Completion Report
**Date:** 2026-03-15
**Sprint:** 07 — GHRM Breadcrumb Widgets
**Tests Added:** 42

## Summary

Breadcrumb navigation added to GHRM catalogue and package detail pages as configurable widgets. Config stored per-widget in `plugins/ghrm/widgets.json`. Admin gets a 3-tab config panel (General / CSS / Preview). Zero modifications to any plugin outside GHRM.

---

## Changes Delivered

### Backend — `vbwd-backend/plugins/ghrm/`

**Widget config storage** (`plugins/ghrm/widgets.json`):
- Flat JSON file with two default widgets: `catalogue` and `detail`
- Fields: `separator`, `root_name`, `root_slug`, `show_category`, `max_label_length`, `css`
- Helper functions `_load_widgets()` / `_save_widgets()` in `src/routes.py`
- Default CSS ships with the widget; overridable per admin config

**API Routes added to `src/routes.py`:**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/v1/ghrm/widgets` | public | Returns all widget configs for fe-user |
| `GET` | `/api/v1/admin/ghrm/widgets/<id>` | admin | Get single widget config |
| `PUT` | `/api/v1/admin/ghrm/widgets/<id>` | admin | Update widget config (whitelisted fields only) |

**Key implementation note:** `result = dict(widgets[widget_id])` captured before `_save_widgets()` call to avoid KeyError when the dict reference is cleared.

### fe-user — `vbwd-fe-user/plugins/ghrm/`

**`src/components/GhrmBreadcrumb.vue`** (new):
- Props: `config: BreadcrumbConfig`, `categoryLabel?`, `categoryTo?`, `packageName?`
- Injects `<style>` tag with `config.css` when non-empty
- `truncate()` respects `config.max_label_length`
- Category crumb hidden when `config.show_category === false`

**`src/api/ghrmApi.ts`** additions:
- `GhrmBreadcrumbConfig` TypeScript interface
- `getWidgets()` method → `GET /api/v1/ghrm/widgets`

**`src/views/GhrmCatalogueContent.vue`** additions:
- `GhrmBreadcrumb` injected at top of page
- `catalogueBreadcrumbConfig` ref + `loadWidgetConfig()` called in `onMounted()`

**`src/views/GhrmPackageDetail.vue`** additions:
- `GhrmBreadcrumb` injected at top of page
- `detailBreadcrumbConfig` ref + `categoryLabel` ref
- `loadWidgetConfig()` + `loadCategoryLabel()` added to `Promise.all(promises)` in `load()`

### fe-admin — `vbwd-fe-admin/plugins/ghrm-admin/`

**`src/api/ghrmWidgetApi.ts`** (new):
- `ghrmWidgetApi.getWidgets()` and `ghrmWidgetApi.updateWidget(widgetId, config)`

**`src/components/GhrmBreadcrumbWidgetConfig.vue`** (new):
- 3 tabs: General / CSS / Preview
- `draft = reactive<GhrmBreadcrumbConfig>({ ...props.initialConfig })`
- `save()` calls `ghrmWidgetApi.updateWidget()` — emits `saved` with updated config
- `reset()` restores to `initialConfig`
- Status indicators: `[data-testid="save-ok"]` / `[data-testid="save-error"]`

**`src/components/GhrmBreadcrumbPreview.vue`** (new):
- Static preview nav for Catalogue page and Detail page using `config` prop

**`src/views/GhrmWidgets.vue`** (new):
- Loads widgets on mount; renders one `GhrmBreadcrumbWidgetConfig` card per widget
- `onSaved(id, updated)` updates matching widget in local array
- Route: `/admin/ghrm/widgets`

---

## Tests

### Backend unit tests — `plugins/ghrm/tests/unit/test_widget_routes.py` (17 tests)
- Public `GET /api/v1/ghrm/widgets` returns both widgets
- `GET` admin route returns correct widget by id; 404 on unknown id
- `PUT` updates allowed fields; ignores unknown fields
- Auth bypass pattern: patch `AuthService.verify_token` + `UserRepository.find_by_id`

### fe-admin unit tests — `vue/tests/unit/plugins/ghrm-breadcrumb-widget-config.spec.ts` (12 tests)
- Tab switching renders correct tab panel
- `save()` calls `ghrmWidgetApi.updateWidget()` with draft values
- `save()` shows save-ok indicator on success; save-error on failure
- `reset()` restores all draft fields to initial values
- `saved` event emitted with updated config

### fe-user unit tests — (via existing ghrm test suite) (13 tests)
- `GhrmBreadcrumb.vue` renders root crumb, category crumb, package crumb
- Truncates labels exceeding `max_label_length`
- Hides category crumb when `show_category = false`
- CSS injected as `<style>` tag when `config.css` is non-empty

---

## Bugs Fixed

- **`KeyError: 'catalogue'` in `admin_update_widget`**: `fake_save` in tests did `storage.clear(); storage.update(data)` which cleared the dict `widgets` still referenced. Fixed by capturing `result = dict(widgets[widget_id])` before calling `_save_widgets()`.
- **401 UNAUTHORIZED on admin widget tests**: Patching decorators after they were applied to view functions had no effect. Fixed by patching `AuthService.verify_token` + `UserRepository.find_by_id` directly and providing `Authorization: Bearer fake-token` header.

---

## Pre-commit

- `make pre-commit-quick` ✅ (backend lint + unit)
- `npm run test` fe-admin ✅
- `npm run test` fe-user ✅
- `npm run lint` fe-admin ✅
- `npm run lint` fe-user ✅

---

## Known Gaps (Backlog)

- Preview tab in `GhrmBreadcrumbWidgetConfig.vue` shows static nav preview, not a live iframe render of the actual page
- No E2E test covering the full breadcrumb render on the live fe-user app
- Widget config API has no validation for `max_label_length` minimum (0 is currently accepted)
