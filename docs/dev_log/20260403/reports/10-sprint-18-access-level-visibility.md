# Report — Sprint 18: Access-Level-Driven Content Visibility

**Date:** 2026-04-08
**Status:** Complete (sub-sprints 18a–18g)

---

## Summary

Admin can now control which widgets, pages, and dashboard cards are visible to each user access level. CMS widgets and pages have a "Visible to" multi-select in the admin editor. The server pre-filters content based on the requesting user's access levels — anonymous visitors are treated as "new" level. Dashboard cards are gated by `hasUserPermission()`.

---

## What Was Built

### 18a — Backend: Model + Migration + Server-Side Filtering

- Added `required_access_level_ids` (JSON, default `[]`) to `CmsLayoutWidget` model
- Added `required_access_level_ids` (JSON, default `[]`) to `CmsPage` model
- Alembic migration: `20260408_1000_cms_access_level_visibility.py`
- Updated `GET /api/v1/cms/layouts/<id>` — filters widget assignments by user's access levels
- Updated `GET /api/v1/cms/layouts/by-slug/<slug>` — same filtering
- Updated `GET /api/v1/cms/pages/<slug>` — returns 403 if page is restricted and user lacks level
- Updated `PUT /api/v1/admin/cms/layouts/<id>/widgets` — accepts `required_access_level_ids` per assignment
- Updated `CmsPageService._apply_data()` — handles `required_access_level_ids` field
- Helper: `_get_current_user_access_level_ids()` — resolves user from JWT or returns "new" level for anonymous
- Helper: `_filter_assignments_by_access()` — filters assignments by level match

### 18b — Admin: CMS Layout Editor "Visible to"

- Per-widget "Visible to" multi-select in `CmsLayoutEditor.vue`
- Tags show assigned levels (green "Everyone" when empty, blue level badges when restricted)
- Dropdown to add levels, × button to remove
- Loads user access levels from `/admin/access/user-levels`
- Saves `required_access_level_ids` array with widget assignments

### 18b (cont.) — Admin: CMS Page Editor "Page Visible to"

- Multi-select "Page visible to" field in `CmsPageEditor.vue` sidebar
- Same tag UI as layout editor
- Added `required_access_level_ids` to `PageForm` interface
- Loads and saves with page data

### 18c — Admin: Access Level Form — Visibility Overview

- New "Visible Content" section on user access level edit form
- Shows CMS pages restricted to this level
- Shows widget assignments restricted to this level
- New backend endpoint: `GET /admin/access/user-levels/:id/content`

### 18d — Dashboard Widget Filtering

- Token Activity card: `v-if="hasUserPermission('subscription.tokens.view')"`
- Recent Invoices card: `v-if="hasUserPermission('subscription.invoices.view')"`
- Dashboard card visibility now matches user's access level permissions

### 18e — CMS Page 403 Handling

- `useCmsStore` now tracks `accessDenied` boolean state
- `CmsPage.vue` shows access denied message with context:
  - Anonymous: "Login Required" with login link
  - Authenticated but lacking level: "Upgrade your plan"
- Separate from 404 "Page not found"

### 18f — Navigation Filtering

- Already done in Sprint 17e (sidebar `hasUserPermission` filtering)
- CMS menu widget items: future sprint (requires `required_access_level_ids` on `CmsMenuItem`)

---

## Test Results

| Module | Tests | Status |
|--------|-------|--------|
| Backend unit | 1409 passed, 5 skipped | PASS |
| fe-admin Vitest | 428 passed | PASS |
| fe-admin ESLint | 0 errors | PASS |
| fe-admin TypeScript | 0 errors | PASS |
| fe-user Vitest | 427 passed, 1 skipped | PASS |

---

## Files Changed

### New Files
- `alembic/versions/20260408_1000_cms_access_level_visibility.py`
- `docs/dev_log/20260403/sprints/18-access-level-visibility.md`

### Backend Modified
- `plugins/cms/src/models/cms_layout_widget.py` — added `required_access_level_ids`
- `plugins/cms/src/models/cms_page.py` — added `required_access_level_ids`
- `plugins/cms/src/repositories/cms_layout_widget_repository.py` — persists new field
- `plugins/cms/src/services/cms_page_service.py` — applies new field
- `plugins/cms/src/routes.py` — server-side filtering helpers + page 403
- `vbwd/routes/admin/access.py` — content overview endpoint

### Frontend Admin Modified
- `plugins/cms-admin/src/stores/useCmsAdminStore.ts` — `required_access_level_ids` on interface
- `plugins/cms-admin/src/views/CmsLayoutEditor.vue` — "Visible to" per widget
- `plugins/cms-admin/src/views/CmsPageEditor.vue` — "Page visible to" field
- `vue/src/views/AccessLevelForm.vue` — content overview section

### Frontend User Modified
- `plugins/cms/src/stores/useCmsStore.ts` — `accessDenied` state + 403 detection
- `plugins/cms/src/views/CmsPage.vue` — access denied UI
- `vue/src/views/Dashboard.vue` — permission-gated cards
- `vue/tests/unit/views/dashboard-token-history.spec.ts` — mock `hasUserPermission`

---

## Architecture: Server-Side Content Filtering

```
Request: GET /api/v1/cms/layouts/<id>
  ↓
  _get_current_user_access_level_ids()
    → JWT present? → verify token → load user → get level IDs
    → No JWT? → query "new" access level → return its ID
  ↓
  _filter_assignments_by_access(assignments, user_level_ids)
    → For each widget assignment:
       required_access_level_ids = [] → include (everyone)
       required_access_level_ids = [id1, id2] → include if user has ANY
  ↓
  Return filtered layout (restricted widgets never sent to client)
```
