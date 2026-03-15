# Sprint 07 — GHRM Breadcrumb Widgets
**Status:** ⏳ Pending approval
**Date:** 2026-03-14

---

## Goal

Add breadcrumb navigation to GHRM pages (catalog list + software detail) as configurable **CMS layout widgets** — not hardcoded components.

Breadcrumbs are rendered by the GHRM plugin extending the CMS widget system. Each widget instance has a three-tab admin configuration panel: **General**, **CSS**, **Preview**.

---

## Widget Spec

### Widget ID: `ghrm-breadcrumb`

### General tab fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `separator` | string | `/` | Symbol displayed between crumbs (e.g. `/`, `>`, `›`, `»`) |
| `root_name` | string | `Home` | Label for the root breadcrumb item (the first crumb, links to `/`) |
| `root_slug` | string | `/` | URL path for the root crumb |
| `show_category` | boolean | true | Whether to show the category crumb between root and package |
| `max_label_length` | number | 40 | Truncate crumb labels longer than this |

### CSS tab

Free-form CSS textarea applied scoped to the widget's wrapper `<div>`. The admin can override all default styling.

Default CSS shipped with the widget:

```css
.ghrm-breadcrumb {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: #6b7280;
  padding: 8px 0 16px;
  flex-wrap: wrap;
}
.ghrm-breadcrumb a { color: #3498db; text-decoration: none; }
.ghrm-breadcrumb a:hover { text-decoration: underline; }
.ghrm-breadcrumb__separator { color: #9ca3af; user-select: none; }
.ghrm-breadcrumb__current { color: #374151; font-weight: 500; }
```

### Preview tab

Renders the full GHRM detail page (or catalog page, depending on context) with the current widget config applied. Uses an `<iframe>` or an in-place component render with mocked route.

---

## Architecture

### Plugin boundary

- All code lives in `vbwd-fe-user/plugins/ghrm/` — no modifications to the CMS plugin or any other plugin
- GHRM extends the CMS widget registry (if exposed) OR registers its own internal widget registry entry for breadcrumbs
- Admin widget configuration UI lives in `vbwd-fe-admin/plugins/ghrm-admin/` — no modifications to any other admin plugin

### Frontend files (fe-user)

| File | Action |
|------|--------|
| `plugins/ghrm/src/components/GhrmBreadcrumb.vue` | New — breadcrumb component, accepts `config` prop |
| `plugins/ghrm/src/widgets/GhrmBreadcrumbWidget.ts` | New — widget registration descriptor (id, defaultConfig, component ref) |
| `plugins/ghrm/src/views/GhrmCategoryList.vue` | Extend — slot or inject breadcrumb at top of page |
| `plugins/ghrm/src/views/GhrmPackageDetail.vue` | Extend — slot or inject breadcrumb at top of page |

### Frontend files (fe-admin)

| File | Action |
|------|--------|
| `plugins/ghrm-admin/src/components/GhrmBreadcrumbWidgetConfig.vue` | New — 3-tab config panel (General / CSS / Preview) |
| `plugins/ghrm-admin/src/views/GhrmWidgets.vue` | New — admin page listing all configurable GHRM widgets |

### Backend (vbwd-backend)

| Item | Description |
|------|-------------|
| GHRM plugin config | Add `breadcrumb_widgets` key — stores per-page widget configs as JSON |
| `GET /api/v1/ghrm/widgets` | Returns configured widgets for fe-user consumption |
| `GET /api/v1/admin/ghrm/widgets` | Admin: get all widget configs |
| `PUT /api/v1/admin/ghrm/widgets/<widget_id>` | Admin: save widget config (General fields + CSS) |

---

## Steps

| # | Where | Description |
|---|-------|-------------|
| 1 | Backend GHRM plugin | Add widget config storage: `breadcrumb_widgets` in plugin config; CRUD API routes |
| 2 | fe-user GHRM | `GhrmBreadcrumb.vue` — renders crumbs from `config` prop + current route |
| 3 | fe-user GHRM | Inject breadcrumb into `GhrmCategoryList.vue` and `GhrmPackageDetail.vue` (load config on mount) |
| 4 | fe-admin GHRM | `GhrmBreadcrumbWidgetConfig.vue` — 3-tab panel: General fields, CSS textarea, Preview |
| 5 | fe-admin GHRM | `GhrmWidgets.vue` — list + edit all GHRM widget configs |
| 6 | Tests | Unit: `GhrmBreadcrumb.vue` rendering for catalog/detail/root scenarios; Admin config panel tabs; Backend widget CRUD |

---

## Acceptance Criteria

- Breadcrumb appears at the top of `GhrmCategoryList` and `GhrmPackageDetail` pages
- Catalog page crumb: `Home / <category>` (e.g. `Home / Backend`)
- Detail page crumb: `Home / <category> / <package name>` (e.g. `Home / Backend / LoopAI Core`)
- Admin can configure separator, root name, root slug via General tab
- Admin can apply custom CSS via CSS tab with live scoping
- Preview tab renders the page with the current (unsaved) config
- Widget config persists via backend API
- Zero modifications to CMS, checkout, or any other plugin outside GHRM

---

## Notes

- "CMS widgets" here means GHRM's own widget concept inspired by CMS — NOT modifying `plugins/cms/`
- If the CMS plugin exposes a public widget registration API in the future, GHRM can migrate to it; for now GHRM owns its widget registry entirely
- The 3-tab admin panel pattern (General / CSS / Preview) is the standard for all future GHRM layout widgets

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before or alongside implementation. No step is done without passing tests. |
| **SOLID** | Single responsibility per component/service. Open for extension, closed for modification. |
| **DI** | Backend: services receive repositories via constructor, no `db.session` inside service methods. Frontend: composables and stores inject dependencies. |
| **DRY** | Reuse existing Vue components and store patterns. No duplicate logic. |
| **Liskov** | All widget implementations honour the widget interface contract. |
| **Clean code** | No `console.log`, no `as any`. Explicit TypeScript types on all props, emits, and store actions. |
| **No over-engineering** | Minimum complexity for the current task. No speculative abstractions. |
| **Drop deprecated** | Use current Vue 3 / Vite / marked APIs only. |

---

## Pre-commit Checks

Run after every step before marking it done.

### fe-user (`vbwd-fe-user/`)
```bash
# Style checks (ESLint + TypeScript)
./bin/pre-commit-check.sh --style

# Style + unit tests  (runs vue/tests/unit/)
./bin/pre-commit-check.sh --unit

# Full
./bin/pre-commit-check.sh --all
```

### fe-admin (`vbwd-fe-admin/`)
```bash
# Style checks
./bin/pre-commit-check.sh --style

# Style + unit tests  (runs vue/tests/unit/ plugins/)
./bin/pre-commit-check.sh --unit

# Full
./bin/pre-commit-check.sh --all
```

All checks must pass before the sprint is considered complete.
