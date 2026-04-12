# Sprint 19 — Page-Defined Widgets

**Status:** In Progress
**Date:** 2026-04-12
**Principles:** TDD-first · DevOps-first · SOLID · Liskov · DRY · No over-engineering · Clean core

---

## Problem

Every page shares its layout's widget assignments. To show different widgets on different pages, admin must create separate layouts. This leads to layout proliferation — dozens of nearly identical layouts differing only by one sidebar widget.

## Solution

Allow admin to assign widgets directly on the **page editor**. Page-level widget assignments override or supplement layout-level assignments for the same area.

---

## Decisions

| Question | Answer |
|----------|--------|
| Override vs supplement | Page widgets **replace** layout widgets for the same area |
| Pages without layout | Page widgets work even without a layout (areas defined inline) |
| Access level support | Page widgets inherit `required_access_level_ids` (same as layout widgets) |
| Data model | New `CmsPageWidget` model (mirrors `CmsLayoutWidget` but FK to page) |
| Admin UI | Widget assignment section on page editor (like layout editor) |
| API change | Page response includes `page_assignments` alongside layout `assignments` |

---

## Data Model

### New table: `cms_page_widget`

```
cms_page_widget
├── id (UUID PK)
├── page_id (FK → cms_page, CASCADE)
├── widget_id (FK → cms_widget, RESTRICT)
├── area_name (VARCHAR 64)
├── sort_order (INT, default 0)
├── required_access_level_ids (JSON, default [])
├── created_at, updated_at, version
```

Mirrors `cms_layout_widget` but references a page instead of a layout.

---

## Rendering Logic

```
Page renders:
  1. Load layout areas (if layout_id set)
  2. Load layout assignments (from CmsLayoutWidget)
  3. Load page assignments (from CmsPageWidget)
  4. For each area:
     - If page has assignment for this area → use page widget
     - Else if layout has assignment → use layout widget
     - Else if content area → render content block
     - Else → skip
```

---

## Implementation

### 19a — Backend: Model + Migration + API

- `CmsPageWidget` model
- Alembic migration
- `CmsPageWidgetRepository` (CRUD + find_by_page)
- Update page API: `GET /cms/pages/<slug>` includes `page_assignments` with embedded widget data
- Admin API: `PUT /admin/cms/pages/<id>/widgets` — set page widget assignments
- Server-side access level filtering on page assignments (same as layout)
- Unit tests

### 19b — Admin: Page Editor Widget Section

- Widget assignment UI on page editor (reuse pattern from layout editor)
- "Visible to" dropdown per widget (reuse from layout editor)
- Widget picker modal
- Save via `PUT /admin/cms/pages/<id>/widgets`

### 19c — Frontend: Merge Page + Layout Widgets

- `CmsLayoutRenderer` accepts both `layout.assignments` and `pageAssignments`
- Page assignments override layout assignments for same area
- `useCmsStore` passes page_assignments to renderer

### 19d — Tests + Pre-commit

- Backend unit tests for model, repository, API
- E2E: assign page widget, verify it appears on user frontend
- `pre-commit-check.sh --full` all modules
