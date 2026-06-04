# Report — Sprints 12-14: Admin Access Levels

**Date:** 2026-04-03 / 2026-04-04
**Status:** Complete

---

## What Was Built

### Sprint 12 — Admin Access Levels (7 sub-sprints)

A complete RBAC (Role-Based Access Control) system replacing the old hardcoded `UserRole` enum with dynamic, DB-backed roles and permissions.

**Backend:**
- `@require_permission(*permissions)` decorator with wildcard support (`*`, `shop.*`)
- `Role` model: `slug`, `is_admin`, `is_system`, many-to-many with `Permission`
- `User` model: multi-role via `assigned_roles`, `has_permission()`, `effective_permissions`
- 11 API routes for access management (CRUD levels, permissions listing, user-role assignment, export/import)
- `BasePlugin.admin_permissions` property — 12 plugins declare 50 permissions
- 9 core permissions seeded (`users.view/manage`, `invoices.view/manage`, `analytics.view`, `settings.view/manage/system`)
- System roles: `super-admin` (wildcard `*`), `admin`, `user` — non-deletable
- Legacy backward compatibility: `UserRole.ADMIN` fallback when no RBAC roles assigned

**Frontend (fe-admin):**
- `usePermissions` composable with wildcard matching
- Router guard: `meta.requiredPermission` → 403 page
- `AdminSidebar`: filters nav items + children by `requiredPermission`
- `AccessLevels.vue`: list page with export/import
- `AccessLevelForm.vue`: create/edit with permission matrix
- `PermissionMatrixTable.vue`: table component (columns: bulk/resource/view/manage/configure, special section)
- `NavItem.requiredPermission` — all plugins declare permissions on routes + nav items
- Users page: bulk role assignment dropdown
- User edit: role checkboxes (multi-role assignment)
- Auth store: `hasPermission` with wildcards, user data persisted to localStorage
- i18n: `access.*` keys in all 8 locale files

### Sprint 13 — Permission Matrix Table

Redesigned the flat checkbox grid into a structured table:
- Columns: bulk checkbox | Resource | view | manage | configure
- Group headers with bulk toggle (view + manage only)
- Row-level bulk toggle
- Special permissions section below table
- Fully dynamic — disabled plugins' permissions disappear

### Sprint 14 — Bulletproof Tests (5 sub-sprints)

- **30 backend unit tests**: decorator enforcement, wildcards, multi-role union, CRUD protection
- **6 plugin isolation tests**: permission listing, system role protection, export/import roundtrip
- **11 frontend unit tests**: `hasPermission` wildcards, `isAdmin` role checks
- **8 E2E Playwright tests**: super-admin access, API protection, system roles, unauthenticated
- All 3 repos pass `pre-commit-check.sh --full`

---

## Test Counts

| Repo | Unit Tests | Integration | E2E (Playwright) |
|------|-----------|-------------|-------------------|
| **backend** | 681 passed | 111 passed | — |
| **fe-admin** | 335+ passed | PASS | 8 passed |
| **fe-user** | 340 passed | PASS | 17 passed |

---

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Multi-role (union of permissions) | Flexible — build small focused roles, combine them |
| Dynamic roles (DB records, not enums) | Admin creates any role without code changes |
| Two-level settings: `configure` + `settings.system` | Per-plugin config assignable; dangerous settings super-admin only |
| Start grouped (view/manage/configure), extensible to per-action | Simple now, data model supports granularity later |
| Legacy ADMIN fallback | Zero disruption — existing admins keep full access before DB seeding |
| Permissions from enabled plugins only | Disabled plugin = invisible permissions |
| User data persisted to localStorage | Survives page refresh without re-fetching profile |

---

## Key Files Changed

**Backend (25+ files):**
- `vbwd/middleware/auth.py` — `@require_permission` decorator
- `vbwd/models/user.py` — `has_permission()`, `effective_permissions`, `_get_roles()`
- `vbwd/models/role.py` — `slug`, `is_admin`, wildcard `has_permission()`
- `vbwd/routes/admin/access.py` — 11 API routes
- `vbwd/interfaces/auth.py` — `permissions` field in `UserData`
- `vbwd/services/auth_service.py` — permissions in login response
- `vbwd/schemas/auth_schemas.py` — `permissions` in `UserDataSchema`
- `vbwd/plugins/base.py` — `admin_permissions` property
- All 12 plugin `__init__.py` — declare permissions
- `bin/install_demo_data.py` — seed system roles + core permissions

**Frontend fe-admin (15+ files):**
- `vue/src/composables/usePermissions.ts`
- `vue/src/components/PermissionMatrixTable.vue`
- `vue/src/views/AccessLevels.vue`, `AccessLevelForm.vue`
- `vue/src/views/Users.vue` — bulk role assignment
- `vue/src/views/UserEdit.vue` — role checkboxes
- `vue/src/views/Dashboard.vue` — lazy-loaded stores
- `vue/src/layouts/AdminSidebar.vue` — permission filtering
- `vue/src/router/index.ts` — permission guard
- `vue/src/plugins/extensionRegistry.ts` — `requiredPermission` on `NavItem`
- All plugin `index.ts` — `requiredPermission` on routes + nav

**Frontend fe-core (1 file):**
- `src/stores/auth.ts` — `hasPermission` wildcards, `hasAnyPermission`, user localStorage persistence
