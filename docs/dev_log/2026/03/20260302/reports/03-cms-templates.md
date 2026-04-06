# Sprint 03 Report — CMS Templates (Layouts, Widgets, Styles)

**Status:** Done
**Date completed:** 2026-03-05

## Summary

Sprint 03 delivered the full CMS templating layer: layouts with named area slots, reusable content widgets (HTML/menu/slideshow), plain CSS stylesheets, and a WYSIWYG HTML tab in the editor. All frontend management UIs are wired to new backend CRUD endpoints.

---

## Backend

### Models (5 new)
| Model | Table | Notes |
|---|---|---|
| `CmsStyle` | `cms_style` | Named CSS stylesheet |
| `CmsWidget` | `cms_widget` | Reusable block: html/menu/slideshow |
| `CmsMenuItem` | `cms_menu_item` | Self-referential menu node (FK → cms_widget) |
| `CmsLayout` | `cms_layout` | Ordered area-slot template |
| `CmsLayoutWidget` | `cms_layout_widget` | Widget assigned to layout area |

### Migration
- `20260305_cms_templates.py` — creates all 5 tables; adds `layout_id`, `style_id`, `use_theme_switcher_styles` to `cms_page`
- Chains: `20260302_create_cms_tables` → `20260305_cms_widen_slug` → `20260305_cms_templates`

### Repositories (5 new)
`CmsStyleRepository`, `CmsWidgetRepository`, `CmsMenuItemRepository`, `CmsLayoutWidgetRepository`, `CmsLayoutRepository` — all with CRUD + bulk_delete.

### Services (3 new + 1 extended)
- `CmsStyleService` — list, get, get_css, create, update, delete, bulk_delete, import/export
- `CmsWidgetService` — same + replace_menu_tree, widget-in-use guard on delete
- `CmsLayoutService` — same + set_widget_assignments (guards content-type areas), validates area names/types
- `CmsPageService._apply_data()` — extended with `layout_id`, `style_id`, `use_theme_switcher_styles`
- `_slug.py` helper — idempotent slug collision avoidance for import

### API Routes (added to routes.py)
**Public:**
- `GET /api/v1/cms/layouts/<id>` — returns layout + assignments with **embedded widget data** (including menu_items)
- `GET /api/v1/cms/styles/<id>/css` — returns CSS as `text/css`

**Admin layouts:** list, create, bulk, export, import, get, put, delete, `PUT /widgets`
**Admin widgets:** list, create, bulk, export, import, get, put, delete, `PUT /menu`
**Admin styles:** list, create, bulk, export, import, get, put, delete

### Unit Tests
- `test_cms_style_service.py` — 10 tests
- `test_cms_widget_service.py` — 12 tests
- `test_cms_layout_service.py` — 10 tests
- **Total: 55 passed, 1 skipped (Pillow)**

### Demo Data Script
- `plugins/cms/src/bin/populate_cms.py` — creates 10 themes (5 light + 5 dark), 8 widgets, 4 layouts, 5 pages
- `plugins/cms/bin/populate-db.sh` — docker compose wrapper

---

## fe-admin

### New views
| File | Description |
|---|---|
| `CmsStyleList.vue` | Paginated table with search, sort, bulk delete |
| `CmsStyleEditor.vue` | CSS textarea + live preview iframe |
| `CmsWidgetList.vue` | Table with type filter |
| `CmsWidgetEditor.vue` | Type switcher: TipTap / menu tree / slideshow images |
| `CmsLayoutList.vue` | Table with area chips |
| `CmsLayoutEditor.vue` | Area builder + widget assignment panel |

### New components
| File | Description |
|---|---|
| `CmsMenuTreeEditor.vue` | Inline tree editor for menu widget items |
| `CmsWidgetPicker.vue` | Modal to select/search widgets for layout assignment |

### Updated files
- `TipTapEditor.vue` — added Visual / HTML two-way sync tabs
- `CmsPageEditor.vue` — added layout_id, style_id, use_theme_switcher_styles sidebar fields; loads layouts+styles on mount; passes `htmlValue` to TipTap
- `useCmsAdminStore.ts` — extended with all new interfaces and CRUD actions
- `index.ts` — registered 9 new routes (styles/widgets/layouts CRUD) + 3 nav items

---

## fe-user

### New files
| File | Description |
|---|---|
| `CmsWidgetRenderer.vue` | Renders html/menu/slideshow widgets |
| `CmsLayoutRenderer.vue` | Iterates layout areas, renders content or widget per slot |

### Updated files
- `useCmsStore.ts` — added `CmsLayout`, `CmsWidgetData`, `CmsMenuItemData` interfaces; `fetchLayout()`, `fetchStyleCss()`; `fetchPage()` now eagerly fetches layout+style in parallel
- `CmsPage.vue` — uses `CmsLayoutRenderer` when layout present; injects style CSS via `<style>` tag on mount; cleans up on unmount

---

## Design Decisions Applied

| Question | Decision |
|---|---|
| Widget assignment scope | Layout-level only (all pages sharing a layout share widgets) |
| Area types | Fixed catalogue: header, footer, hero, slideshow, content, three-column, two-column, cta-bar |
| Menu storage | Widget type = "menu"; items stored in `cms_menu_item` |
| CSS format | Plain CSS only |
| WYSIWYG HTML tab | Two-way sync: visual↔HTML |
| Import slug collision | Auto-rename with suffix (my-layout → my-layout-2) |
| Content area | Optional — layouts may omit it for landing pages |

---

## Files Created/Modified

**Backend (15+ files):**
- Models: `cms_style.py`, `cms_widget.py`, `cms_menu_item.py`, `cms_layout.py`, `cms_layout_widget.py`
- Services: `cms_style_service.py`, `cms_widget_service.py`, `cms_layout_service.py`, `_slug.py` (+ updated `cms_page_service.py`)
- Repos: 5 new repository files
- Migration: `20260305_cms_templates.py`
- Routes: `routes.py` extended (~350 lines added)
- Tests: 3 new unit test files (32 tests)
- Demo: `src/bin/populate_cms.py`, `bin/populate-db.sh`

**fe-admin (10+ files):** 6 new views, 2 new components, 3 updated files

**fe-user (4 files):** 2 new components, 2 updated files
