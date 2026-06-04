# Report — Sprint 17: User Access Levels (Complete)

**Date:** 2026-04-07
**Status:** Complete (all sub-sprints 17a–17g)

---

## Summary

Full user-facing permission system implemented across backend, subscription plugin, admin panel, and user-facing app. Admin configures user access levels that control which fe-user features, routes, widgets, and navigation items are visible. Plans auto-assign default levels via subscription events; admin can override manually.

---

## Sub-Sprint Completion

| Sprint | Scope | Status |
|--------|-------|--------|
| **17a** | Backend model, migration, service, decorator, seed data | Complete |
| **17b** | Subscription plugin event-driven auto-assignment | Complete |
| **17c** | Backend admin API (CRUD + permissions + import/export) | Complete |
| **17d** | Frontend admin UI (two tabs, bulk checkboxes, plan dropdown, UserEdit) | Complete |
| **17e** | Frontend user permission engine (auth store, router guard, sidebar filter) | Complete |
| **17f** | Frontend user plugin integration (requiredUserPermission on routes) | Complete |
| **17g** | E2E tests (24 passing, 5 new user access level tests) | Complete |

---

## What Was Built

### Backend (17a + 17b + 17c)

**Core (agnostic):**
- `UserAccessLevel` model with `linked_plan_slug` for auto-assignment
- Association tables: `vbwd_user_access_level_permissions`, `vbwd_user_user_access_levels`
- `User.has_user_permission()`, `User.effective_user_permissions` property
- `@require_user_permission` decorator for user route protection
- `UserAccessLevelService` — assign/revoke/find API
- `BasePlugin.user_permissions` property (default: empty list)
- Alembic migration: `20260406_1800_add_user_access_levels.py`
- 4 seeded default levels: new, logged-in, subscribed-basic, subscribed-pro

**Subscription Plugin (gnostic):**
- `SubscriptionAccessLevelHandler` — EventBus handler
  - `subscription.activated` → assign plan-linked access level
  - `subscription.cancelled` → revoke plan-linked levels, assign "logged-in" fallback
- `user_permissions` property — 7 user-facing permissions declared
- EventBus publishing from `LineItemHandler` after subscription activation/cancellation

**Admin API (12 new endpoints under `/api/v1/admin/access/`):**
- `GET/POST /user-levels` — list/create
- `GET/PUT/DELETE /user-levels/:id` — detail/update/delete
- `GET /user-permissions` — list user permissions from all plugins
- `POST /user-levels/export` / `POST /user-levels/import`
- `POST /users/:id/user-access-levels` / `DELETE /users/:id/user-access-levels/:levelId`

### Frontend Admin (17d)

- **AccessLevels.vue** — Two tabs: "Admin Access Levels" and "User Access Levels"
  - Both tabs have bulk checkboxes with "Delete Selected" action
  - User tab shows "Linked Plan" column with plan slug badges
- **AccessLevelForm.vue** — Linked plan `<select>` dropdown (populated from tarif-plans API)
  - User permission matrix (from `plugin.user_permissions`, not `admin_permissions`)
- **UserEdit.vue** — New "User Access Levels" checkbox section
  - Shows all available user access levels with system/plan badges
  - Toggle to assign/revoke levels per user

### Frontend Core Library (17e)

- **fe-core auth store** — Added `user_permissions`, `user_access_levels` to `AuthUser` interface
  - `hasUserPermission(permission)` getter
  - `hasAnyUserPermission(permissions)` getter
  - Rebuilt dist (`npm run build`)

### Frontend User App (17e + 17f)

- **Login.vue** — Stores `user_permissions` in localStorage from login response
- **api/index.ts** — Added `hasUserPermission()` and `getUserPermissions()` helpers
- **Router guard** — Checks `meta.requiredUserPermission` before navigation, redirects to dashboard if denied
- **UserLayout.vue** — Sidebar nav items filtered by `requiredUserPermission`; logout clears permissions
- **userNavRegistry.ts** — Added `requiredUserPermission` field to `UserNavItem` interface
- **Subscription plugin routes** — `requiredUserPermission` on plans, subscription, add-ons pages
- **Core routes** — `requiredUserPermission` on profile, tokens, invoices pages

### Tests (17g)

- **Backend unit tests:** 22 tests (11 service + 11 handler)
- **E2E tests:** 5 new tests in `user-access-levels.spec.ts`
  - Two tabs visible on access levels page
  - User access levels tab shows table or empty state
  - User-levels CRUD via API (create, read, update, delete with cleanup)
  - User-permissions API returns plugin permissions
  - Export/import roundtrip
- **Total:** 24/24 admin access level E2E tests pass

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    BACKEND                           │
│                                                     │
│  Core (agnostic)                                    │
│  ├── UserAccessLevel model + migration              │
│  ├── UserAccessLevelService (assign/revoke)          │
│  ├── @require_user_permission decorator             │
│  └── Admin API (/admin/access/user-levels/*)        │
│                                                     │
│  Subscription Plugin (gnostic)                      │
│  ├── SubscriptionAccessLevelHandler                 │
│  │   ├── subscription.activated → assign level      │
│  │   └── subscription.cancelled → revoke + fallback │
│  ├── user_permissions (7 permissions)               │
│  └── EventBus publishing from LineItemHandler       │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                   FRONTEND                           │
│                                                     │
│  fe-core (shared library)                           │
│  └── AuthUser.user_permissions + hasUserPermission() │
│                                                     │
│  fe-admin                                           │
│  ├── AccessLevels.vue — Two tabs (Admin / User)     │
│  ├── AccessLevelForm.vue — Plan dropdown + matrix   │
│  └── UserEdit.vue — User access level checkboxes    │
│                                                     │
│  fe-user                                            │
│  ├── Router guard (requiredUserPermission)           │
│  ├── Sidebar filtering by user permission           │
│  └── Plugin routes with requiredUserPermission      │
└─────────────────────────────────────────────────────┘
```

---

## Files Changed/Created

### New Files (14)

| File | Purpose |
|------|---------|
| `vbwd/services/user_access_level_service.py` | Core assign/revoke service |
| `plugins/subscription/subscription/handlers/access_level_handler.py` | EventBus auto-assignment handler |
| `plugins/subscription/tests/unit/test_access_level_handler.py` | 11 handler unit tests |
| `tests/unit/services/test_user_access_level_service.py` | 11 service unit tests |
| `alembic/versions/20260406_1800_add_user_access_levels.py` | Migration for existing DBs |
| `vbwd-fe-admin/vue/tests/e2e/user-access-levels.spec.ts` | 5 E2E tests |
| `docs/dev_log/20260403/reports/06-sprint-17b-subscription-access-levels.md` | Sprint 17b report |

### Modified Files (14)

| File | Change |
|------|--------|
| `vbwd/routes/admin/access.py` | Added 12 user-level endpoints + user-permissions endpoint |
| `vbwd/plugins/base.py` | Added `user_permissions` property (done in 17a) |
| `plugins/subscription/__init__.py` | Added `user_permissions`, registered access level handler |
| `plugins/subscription/subscription/handlers/line_item_handler.py` | Added event_bus.publish after activation/cancellation |
| `vbwd-fe-core/src/stores/auth.ts` | Added `user_permissions`, `hasUserPermission()`, `hasAnyUserPermission()` |
| `vbwd-fe-admin/vue/src/views/AccessLevels.vue` | Two tabs, bulk checkboxes, user table |
| `vbwd-fe-admin/vue/src/views/AccessLevelForm.vue` | Plan dropdown, user permissions matrix, type=user routing |
| `vbwd-fe-admin/vue/src/views/UserEdit.vue` | User access levels checkbox section |
| `vbwd-fe-user/vue/src/views/Login.vue` | Store user_permissions on login |
| `vbwd-fe-user/vue/src/api/index.ts` | Added hasUserPermission(), getUserPermissions() |
| `vbwd-fe-user/vue/src/router/index.ts` | requiredUserPermission guard + permission on core routes |
| `vbwd-fe-user/vue/src/layouts/UserLayout.vue` | Sidebar filtering, logout cleanup |
| `vbwd-fe-user/vue/src/plugins/userNavRegistry.ts` | Added requiredUserPermission to UserNavItem |
| `vbwd-fe-user/plugins/subscription/index.ts` | requiredUserPermission on all authenticated routes |
| `docs/dev_docs/access-level-management.md` | User access levels documentation |
| `docs/dev_docs/plugin-developer-guide.md` | User permissions, access level guidance |
