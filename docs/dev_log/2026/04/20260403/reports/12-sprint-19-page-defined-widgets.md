# Report — Sprint 19: Page-Defined Widgets

**Date:** 2026-04-12
**Status:** Complete

---

## Problem

Every page sharing the same layout displayed the same widgets. To show a different widget on one page, admin had to create an entirely new layout — leading to dozens of nearly identical layouts differing by a single widget.

## Solution

New layout area type `page-widget` — widget placeholder slots that each page fills individually. The layout defines *where* a widget goes; the page editor defines *which* widget. Same pattern as `content` areas (each page has its own content), but for widgets.

---

## How It Works

### Layout Editor

Admin adds areas of type `page-widget` alongside the existing types (`content`, `header`, `footer`, `vue`, etc.). These slots:
- Do NOT appear in the layout's "Widget Assignments" section (those are for shared layout-level widgets)
- Do NOT have a default widget — each page fills them individually
- Have a label visible in the page editor (e.g., "Sidebar Widget", "Promo Banner")

### Page Editor

"Page Widgets" section appears when the layout has `page-widget` areas. Admin clicks "Choose widget" per slot, picks from the widget library. Widget assignment saves together with the page (single Save button — no separate save). Each page using the same layout can have different widgets in the same slots.

### Rendering

`CmsLayoutRenderer` checks page assignments first, then layout assignments for each area. `page-widget` areas have no layout assignment, so they render only the page's chosen widget (or skip if empty).

---

## What Was Built

### 19a — Backend: Model + Migration + API

**New model: `CmsPageWidget`**
- Table: `cms_page_widget`
- Fields: `page_id`, `widget_id`, `area_name`, `sort_order`, `required_access_level_ids`

**New area type: `page-widget`**
- Added to `AREA_TYPES` in `cms_layout.py`
- Excluded from layout-level widget assignments (backend validates, frontend filters)

**Migration:** `20260412_1000_cms_page_widget.py` (with `IF NOT EXISTS` guard)

**Repository: `CmsPageWidgetRepository`**
- `find_by_page(page_id)` — list assignments for a page
- `replace_for_page(page_id, assignments)` — atomic replace

**API endpoints:**
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/admin/cms/pages/<id>/widgets` | List page widget assignments (with embedded widget data) |
| PUT | `/admin/cms/pages/<id>/widgets` | Replace page widget assignments |
| GET | `/admin/cms/pages/<id>` | Now includes `page_assignments` in response |
| GET | `/cms/pages/<slug>` | Public: includes `page_assignments` with widget data, access-level filtered |

**Backend validation:** Layout-level widget assignments are rejected for `page-widget` and `content` areas.

### 19b — Admin: Page Editor Widget Section

**`CmsPageEditor.vue`:**
- "Page Widgets" section shows only `page-widget` type areas from the layout
- Per-slot widget picker via `CmsWidgetPicker` modal
- "Visible to" access level tags per widget (reuses Sprint 18 pattern)
- Saves with the main page Save button (no separate save)
- Loads widget list and access levels on mount
- Populates from `page_assignments` in page API response

**`CmsLayoutEditor.vue`:**
- `page-widget` added to `AREA_TYPES` dropdown
- `page-widget` areas excluded from layout's "Widget Assignments" section
- Updated hint text to explain the distinction

### 19c — Frontend: Merge Page + Layout Widgets

**`CmsLayoutRenderer.vue`:**
- New prop: `pageAssignments` (optional)
- `widgetFor(areaName)` checks page assignments first, then layout assignments
- `page-widget` areas render only from page assignments

**`CmsPage.vue`:**
- Passes `pageWidgetAssignments` from store to renderer

### 19d — Seed Data + Import/Export

**`populate_cms.py`:**
- `_get_or_create_page()` now returns the page object
- New `_set_page_widgets()` helper — idempotent page widget assignment
- Demo: "About Us" page gets a `testimonials` widget in the footer area
- New "Page Widgets" section in populate output

**`cms_import_export_service.py`:**
- Export includes `page_widget_assignments` per page (widget_slug + area_name + sort_order + required_access_level_ids)
- Import creates `CmsPageWidget` records from `page_widget_assignments`
- Constructor accepts optional `pw_repo` parameter

**Import sample:** `docs/dev_log/2026/03/20260302/cms-import-samples/page-with-page-widgets.json`

### 19e — Migration Safety

All incremental migrations updated with `IF NOT EXISTS` / `_table_exists` / `_column_exists` guards:
- `20260406_1800_add_user_access_levels.py` — checks tables before CREATE
- `20260408_1000_cms_access_level_visibility.py` — checks columns before ADD COLUMN
- `20260412_1000_cms_page_widget.py` — checks table before CREATE

Safe on both fresh databases (where consolidated `vbwd_001` already created tables) and existing databases.

### 19f — Tests

**E2E: `page-defined-widgets.spec.ts` — 4 tests:**
1. Page widget assignment persists via API
2. Admin page detail includes `page_assignments`
3. Public page response includes `page_assignments` with embedded widget data
4. Page widget overrides layout widget for same area

**E2E: `page-widget-slots.spec.ts` — 5 tests:**
1. Admin assigns widget to `page-widget` slot
2. Assignment persists after reload
3. Public page includes page widget in `page_assignments`
4. Widget with access level restriction hidden from anonymous users
5. Widget visible to authenticated user with correct level

---

## Architecture

```
Layout defines:
  [header]  [content]  [page-widget: sidebar]  [footer]
   fixed     per-page    per-page widget slot    fixed

Page A fills:  content A  +  sidebar → Testimonials
Page B fills:  content B  +  sidebar → Contact Form
Page C fills:  content C  +  sidebar → (empty, skipped)
All share ONE layout.
```

**Area type behavior:**
| Type | Widget source | Set in |
|------|--------------|--------|
| `content` | TipTap content | Page editor (WYSIWYG) |
| `page-widget` | Per-page widget | Page editor (widget picker) |
| `header`, `footer`, `vue`, etc. | Layout-level widget | Layout editor |

**Rendering logic:**
```
For each layout area:
  1. If type === 'content' → render content block
  2. Else check page_assignments → use page widget if found
  3. Else check layout assignments → use layout widget
  4. Else → skip
```

---

## Test Results

| Module | Check | Result |
|--------|-------|--------|
| Backend unit | 1409 passed, 5 skipped | PASS |
| fe-admin ESLint | 0 errors | PASS |
| fe-admin TypeScript | 0 errors | PASS |
| fe-admin Vitest | 428 passed | PASS |
| fe-user Vitest | 427 passed, 1 skipped | PASS |
| E2E page-defined-widgets | 4 passed | PASS |
| E2E page-widget-slots | 5 passed | PASS |

---

## Files Changed

### New Files (6)
| File | Purpose |
|------|---------|
| `plugins/cms/src/models/cms_page_widget.py` | Page-level widget assignment model |
| `plugins/cms/src/repositories/cms_page_widget_repository.py` | CRUD repository |
| `alembic/versions/20260412_1000_cms_page_widget.py` | Migration (with IF NOT EXISTS) |
| `vue/tests/e2e/page-defined-widgets.spec.ts` | 4 E2E tests |
| `vue/tests/e2e/page-widget-slots.spec.ts` | 5 E2E tests (access level filtering) |
| `docs/dev_log/2026/03/20260302/cms-import-samples/page-with-page-widgets.json` | Import sample |

### Modified Files (10)
| File | Change |
|------|--------|
| `plugins/cms/src/models/cms_layout.py` | Added `page-widget` to `AREA_TYPES` |
| `plugins/cms/src/services/cms_layout_service.py` | Exclude `page-widget` from layout assignments validation |
| `plugins/cms/src/routes.py` | `_page_widget_repo()`, admin GET/PUT, public page `page_assignments`, import/export factory |
| `plugins/cms/src/services/cms_import_export_service.py` | Export/import `page_widget_assignments`, `pw_repo` param |
| `plugins/cms/src/bin/populate_cms.py` | `_set_page_widgets()`, demo assignment, return page from `_get_or_create_page` |
| `plugins/cms-admin/src/stores/useCmsAdminStore.ts` | `required_access_level_ids` on interface |
| `plugins/cms-admin/src/views/CmsLayoutEditor.vue` | `page-widget` in AREA_TYPES, excluded from layout assignments |
| `plugins/cms-admin/src/views/CmsPageEditor.vue` | Page widget slots UI, saves with main Save button |
| `vbwd-fe-user/plugins/cms/src/components/CmsLayoutRenderer.vue` | `pageAssignments` prop, page-first resolution |
| `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` | Passes `pageWidgetAssignments` to renderer |

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| New area type `page-widget` | Clean distinction: layout says "there's a widget slot here", page fills it — like `content` but for widgets |
| Saves with main Save button | One save action per page — no confusing separate save for widgets |
| Excluded from layout assignments | `page-widget` areas have no default — each page chooses its own widget |
| Same access level filtering | Reuses `_filter_assignments_by_access()` — no new permission logic |
| IF NOT EXISTS on migrations | Safe for both fresh and existing databases |
| Import/export support | `page_widget_assignments` array per page in export ZIP |
