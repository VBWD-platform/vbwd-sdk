# Dev Log — 2026-04-03

## Sprints

| # | Sprint | Status | Report |
|---|--------|--------|--------|
| 12 | [Admin Access Levels — Overview](sprints/12-admin-access-levels.md) | Done | — |
| 12a | [Permission Middleware](done/12a-permission-middleware.md) | Done | — |
| 12b | [Access Management API](done/12b-access-management-api.md) | Done | — |
| 12c | [Plugin Permission Declaration](done/12c-plugin-permissions.md) | Done | — |
| 12d | [Frontend Permission Routing](done/12d-frontend-permission-routing.md) | Done | — |
| 12e | [Access Management UI](done/12e-access-management-ui.md) | Done | — |
| 12f | [Plugin Access Integration](done/12f-plugin-access-integration.md) | Done | — |
| 12g | [Tests + Pre-commit](done/12g-tests-precommit.md) | Done | — |
| 13 | [Permission Matrix Table UI](done/13-permission-matrix-table.md) | Done | — |
| 14 | [Access Control Bulletproof Tests — Overview](sprints/14-access-bulletproof-tests.md) | Done | — |
| 14a | [Backend: Permission Enforcement Tests](done/14a-backend-permission-tests.md) | Done | — |
| 14b | [Backend: Plugin Isolation Tests](done/14b-backend-plugin-isolation.md) | Done | — |
| 14c | [Frontend: Permission UI Tests](done/14c-frontend-permission-ui.md) | Done | — |
| 14d | [E2E: Access Control Scenarios](done/14d-e2e-access-scenarios.md) | Done | — |
| 14e | [Pre-commit + CI](done/14e-precommit-ci.md) | Done | — |
| 15 | [Shipping & Discount Admin — Overview](sprints/15-shipping-discount-admin.md) | Done | [Report](reports/03-sprint-15-shipping-discount-tax.md) |
| 15a | [Shop: Shipping Methods](done/15a-shop-shipping.md) | Done | — |
| 15b | [Discount Admin Plugin](done/15b-discount-admin.md) | Done | — |
| 15c | [Tax Configuration](done/15c-tax-admin.md) | Done | — |
| 15d | Tests + Pre-commit | Done | — |
| 15e | Role Refactor (SUPER_ADMIN/ADMIN/USER) | Done | [Report](reports/04-access-level-management.md) |
| 15f | Security Hardening (292 routes + 44 views) | Done | [Report](reports/05-access-level-security-hardening.md) |
| 16 | [Pay with Token Balance](sprints/16-token-payment.md) | Planned | — |
| 17 | [User Access Levels (fe-user)](sprints/17-user-access-levels.md) | In Progress | — |

## Done (2026-04-06)

### Sprint 15e — Role System Refactor (COMPLETE)

- `UserRole` enum: added `SUPER_ADMIN` — full wildcard access
- `ADMIN` without access levels = dashboard only
- `USER` = never accesses admin panel
- Dropped `is_admin` column from `vbwd_role` — roles are purely "access levels"
- `User.is_admin`: checks enum, not RBAC
- `User.has_permission`: SUPER_ADMIN → always True; ADMIN → checks access levels
- Login response: `role` (enum), `is_admin` (bool), `access_levels` (objects), `permissions`
- Frontend: `isAdmin` checks `user.role`, `isSuperAdmin` getter added
- UserCreate: SUPER_ADMIN option in dropdown
- UserEdit: access level checkboxes only for ADMIN users
- Permission matrix: column header checkboxes for bulk View/Manage/Configure toggle
- Dashboard: analytics hidden without `analytics.view` permission

### Sprint 15f — Security Hardening (COMPLETE)

- 73 core admin routes + 188 plugin routes secured with `@require_permission`
- 15 core frontend routes + 55 plugin routes with `meta.requiredPermission`
- Core sidebar items: `requiredPermission` added
- Bug fix: `extensionRegistry._insertItem()` was stripping `requiredPermission`
- Edit pages: require `view` to open, `manage` to save/delete
- 44 view files: `v-if="canManage"` guards on all destructive buttons
- Playwright E2E: admin with CMS-only access → sidebar shows only CMS, API returns 403 for everything else

### Checkout Bug Fix

- Plugin's `CheckoutHandler` imported wrong `CheckoutRequestedEvent` class → `isinstance()` failed
- Missing DI registrations: subscription/addon/plan repositories removed from container during plugin extraction

### Auth Store Fix

- User data persisted to localStorage for page-reload survival
- `isAdmin` getter fixed: checks `user.role` enum, not role slug strings
