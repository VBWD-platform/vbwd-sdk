# Sprint 12 — Admin Access Levels

**Status:** Draft — pending Q&A
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · DevOps-first · Clean Code

---

## Goal

Implement granular access control for the admin panel. Admins can have different access levels (e.g., Super Admin, Content Manager, Sales Manager, Support Agent). Each level defines which plugins, views, API endpoints, and settings the admin can access.

---

## Current State

| Component | Current | Target |
|-----------|---------|--------|
| **Backend auth** | Binary: `@require_admin` checks `user.role == ADMIN` | Permission-based: `@require_permission('shop.products.manage')` |
| **RBAC models** | `Role`, `Permission` tables exist but are **unused** | Wired into auth middleware, plugin system, and admin UI |
| **User.role** | Single hardcoded enum: `USER`, `ADMIN`, `VENDOR` | Enum removed. Roles are DB records. Multi-role via `vbwd_user_roles` junction. Two defaults: `admin`, `user`. |
| **Frontend** | All admin users see all routes/nav | Routes and sidebar filtered by permissions |
| **Plugins** | No permission metadata | Each plugin declares required permissions |

---

## Architecture

### Roles are DB Records, Not Enums

The current `UserRole` enum (`USER`, `ADMIN`, `VENDOR`) is **removed**. Roles become fully dynamic DB records:

```
Role (DB record)
├── name: "Content Manager"
├── slug: "content-manager"
├── description: "Can manage CMS pages, images, widgets"
├── is_system: true/false (system roles cannot be deleted)
├── is_admin: true/false (grants admin panel access)
└── permissions: [many-to-many → Permission table]
    ├── cms.pages.view
    ├── cms.pages.manage
    ├── cms.images.view
    └── cms.widgets.manage
```

A user can have **multiple roles**. Effective permissions = union of all assigned roles.

### Permission Naming Convention

```
{resource}.{action}                  # core
{plugin}.{resource}.{action}         # plugin-specific
```

**Actions (grouped, extensible to per-action later):**
- `view` — read-only access
- `manage` — create + update + delete
- `configure` — plugin settings (assignable per plugin)

**System-level (super-admin only by default):**
- `settings.system` — payment providers, API keys, dangerous config

**Core permissions:**
- `users.view`, `users.manage`
- `invoices.view`, `invoices.manage`
- `settings.view`, `settings.manage`, `settings.system`
- `analytics.view`

**Plugin permissions (declared by each plugin):**
- `cms.pages.view`, `cms.pages.manage`, `cms.images.manage`, `cms.widgets.manage`, `cms.configure`
- `shop.products.view`, `shop.products.manage`, `shop.orders.view`, `shop.orders.manage`, `shop.stock.manage`, `shop.configure`
- `booking.resources.view`, `booking.resources.manage`, `booking.bookings.view`, `booking.bookings.manage`, `booking.configure`
- `subscription.plans.view`, `subscription.plans.manage`, `subscription.subscriptions.view`, `subscription.configure`
- `discount.discounts.manage`, `discount.coupons.manage`, `discount.configure`
- `email.templates.view`, `email.templates.manage`, `email.configure`

**Default system roles (seeded, non-deletable):**
- `super-admin` — wildcard `*` permission, full access
- `admin` — default role for existing admins (mapped from old `ADMIN` enum)
- `user` — default role for regular users (mapped from old `USER` enum)

**Example custom roles (admin-created):**
- `content-manager` — CMS only
- `sales-manager` — shop + subscriptions + invoices
- `support-agent` — view users, invoices, orders, bookings (read-only)
- `vendor` — replaces old `VENDOR` enum, specific permissions for vendor access

### Backend Implementation

**1. New decorator: `@require_permission(permission_string)`**
```python
@require_auth
@require_permission("shop.products.manage")
def admin_create_product():
    ...
```

- Checks if the authenticated user has the permission via their assigned roles
- Super admin (`*` permission) bypasses all checks
- Returns 403 with `{"error": "Permission denied", "required": "shop.products.manage"}`

**2. Plugin permission declaration**
```python
class ShopPlugin(BasePlugin):
    @property
    def admin_permissions(self) -> list[str]:
        return [
            "shop.products.view",
            "shop.products.manage",
            "shop.orders.view",
            "shop.orders.manage",
            "shop.stock.manage",
            "shop.warehouses.manage",
            "shop.categories.manage",
            "shop.configure",  # plugin settings
        ]
```

**3. Admin API routes for access management**
- `GET /api/v1/admin/access/levels` — list roles/access levels
- `POST /api/v1/admin/access/levels` — create access level
- `PUT /api/v1/admin/access/levels/<id>` — update access level
- `DELETE /api/v1/admin/access/levels/<id>` — delete (non-system only)
- `GET /api/v1/admin/access/permissions` — list all available permissions (from all plugins)
- `GET /api/v1/admin/access/levels/<id>/users` — users with this access level
- `POST /api/v1/admin/users/<id>/roles` — assign role to user
- `DELETE /api/v1/admin/users/<id>/roles/<role_id>` — revoke role
- `POST /api/v1/admin/access/export` — export roles + permissions as JSON
- `POST /api/v1/admin/access/import` — import roles + permissions from JSON

### Frontend Implementation

**1. Permission-aware sidebar**
- `AdminSidebar.vue` filters nav items based on user permissions
- Plugin nav items hidden if user lacks the plugin's `view` permission
- Settings section hidden if user lacks `settings.view`

**2. Permission-aware routes**
- Route meta: `meta: { requiredPermission: 'shop.products.view' }`
- Router guard checks permission before rendering
- 403 page if permission denied

**3. Admin Settings → Access section**
- **Access Levels tab**: CRUD for roles, permission assignment via checkbox matrix
- **Users tab**: assign roles to users, view user's effective permissions

### Plugin Contract

Each plugin (backend + admin frontend) must:
1. Declare `admin_permissions` in the backend plugin class
2. Declare `requiredPermission` in the admin plugin's route meta
3. Declare `requiredPermission` in the sidebar nav item

---

## Sub-Sprints

| # | Sprint | Scope |
|---|--------|-------|
| 12a | [Permission Middleware](12a-permission-middleware.md) | `@require_permission` decorator, wire `vbwd_user_roles` to User, remove UserRole enum, seed system roles |
| 12b | [Access Management API](12b-access-management-api.md) | CRUD routes for roles, permission listing, user-role assignment, export/import |
| 12c | [Plugin Permission Declaration](12c-plugin-permissions.md) | Add `admin_permissions` to all plugins, migrate `@require_admin` → `@require_permission` |
| 12d | [Frontend Permission Routing](12d-frontend-permission-routing.md) | `usePermissions` composable, router guard, sidebar filter, 403 page |
| 12e | [Access Management UI](12e-access-management-ui.md) | Settings → Access Levels, permission matrix editor, user role assignment, export/import |
| 12f | [Plugin Access Integration](12f-plugin-access-integration.md) | Update ALL plugins (backend + fe-admin) to declare permissions and use `requiredPermission` |
| 12g | [Tests + Pre-commit](12g-tests-precommit.md) | Unit + integration + E2E tests, all repos green |

---

## Design Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | **Multi-role vs single-role** | **Multi-role.** Users can have multiple roles. Effective permissions = union of all assigned roles. |
| 2 | **Vendor role** | **Part of the same system.** `UserRole` enum is removed. Only two defaults: `ADMIN` and `USER`. Admin can create any role (e.g., Vendor, Editor) and assign permissions. Roles are DB records, not hardcoded enums. |
| 3 | **Plugin settings access** | **Two levels.** Per-plugin `configure` permission (assignable). Plus a global `settings.system` permission for dangerous things (payment providers, API keys) — super-admin only by default. |
| 4 | **Permission granularity** | **Start grouped, model supports per-action.** Ship with `view`/`manage`/`configure`. Data model stores individual permission strings so per-action (`.create`, `.update`, `.delete`) can be added later without migration. |
| 5 | **Existing admins after migration** | **All become super-admin.** Existing `role = ADMIN` users automatically get the `super-admin` role with wildcard `*` permission. No disruption. |
| 6 | **API keys** | **Design for it, don't implement now.** Permission system supports API key integration later. Not in this sprint. |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. Permission checks covered by unit + integration tests. |
| **SOLID** | `IPermissionChecker` interface. Open/Closed: plugins declare permissions without modifying core. |
| **Liskov** | All permission-declaring plugins honor the `admin_permissions` contract. |
| **DI** | PermissionService injected into middleware. RoleRepository injected into service. |
| **DRY** | Single `@require_permission` decorator. No duplicate permission checks. |
| **Clean Code** | Permission strings are constants, not magic strings. |
| **No over-engineering** | Start with `view`/`manage`/`configure` granularity. Don't build field-level permissions. |
| **DevOps-first** | `pre-commit-check.sh --full` passes in all 3 repos. |

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
