# Report — Access Level Management System

**Date:** 2026-04-06
**Status:** Complete

---

## Summary

Full access control system implemented across backend API and frontend admin panel. Three-tier role model with granular permission-based access levels for ADMIN users.

---

## Role Model

| Role | Admin Panel | Permissions | Access Levels |
|------|------------|-------------|---------------|
| **SUPER_ADMIN** | Full access | Wildcard `*` — bypasses all checks | Not needed |
| **ADMIN** | Dashboard only (without access levels) | Only what access levels grant | Required for any action beyond dashboard |
| **USER** | Never | N/A | N/A |
| **VENDOR** | Never | N/A | N/A |

---

## What Was Built

### Backend — 73 Admin Routes Secured

Every admin API route now enforces `@require_permission` in addition to `@require_admin`:

| File | Routes | Permissions |
|------|--------|-------------|
| `users.py` | 10 | `users.view` / `users.manage` |
| `invoices.py` | 10 | `invoices.view` / `invoices.manage` |
| `payment_methods.py` | 12 | `settings.manage` |
| `plans.py` | 9 | `subscription.plans.view` / `.manage` |
| `addons.py` | 8 | `subscription.addons.manage` |
| `subscriptions.py` | 7 | `subscription.subscriptions.view` / `.manage` |
| `categories.py` | 7 | `subscription.plans.manage` |
| `countries.py` | 6 | `settings.view` / `settings.manage` |
| `plugins.py` | 5 | `settings.view` / `settings.system` |
| `settings.py` | 2 | `settings.view` / `settings.manage` |
| `token_bundles.py` | 7 | `settings.view` / `settings.manage` |
| `analytics.py` | 1 | `analytics.view` |
| `access.py` | 11 | `settings.system` (already had) |
| `tax.py` | 9 | `settings.manage` (already had) |

**Total: 104 protected routes**

### Backend — User Model Refactored

- `UserRole` enum: added `SUPER_ADMIN`
- `User.is_admin`: checks `role in (SUPER_ADMIN, ADMIN)` — no legacy fallbacks
- `User.has_permission()`: SUPER_ADMIN → always True; ADMIN → checks RBAC access levels
- `User.effective_permissions`: SUPER_ADMIN → `["*"]`; ADMIN → union of access level permissions
- `User.to_dict()`: returns `role` (enum string), `access_levels` (RBAC), `permissions`
- `Role` model: dropped `is_admin` column — roles are now purely "access levels"

### Frontend — Route Protection

All admin routes have `meta: { requiredPermission }`:

- Core routes (router/index.ts): users, invoices, settings, payment methods, token bundles
- Plugin routes: CMS (16 routes), booking (8), shop (9), subscription (11), discount (7), email (3)

Router guard redirects to `/admin/forbidden` when permission is missing.

### Frontend — Sidebar Filtering

- Core sidebar items: `requiredPermission` added to Users, Invoices, Settings, Payment Methods, Access Levels
- Plugin sidebar items: already had `requiredPermission` but were being stripped during injection
- **Bug fix**: `extensionRegistry._insertItem()` was dropping `requiredPermission` when copying plugin nav items — fixed

### Frontend — Dashboard

- Analytics cards hidden without `analytics.view` permission
- ADMIN without analytics permission sees only "Active Sessions" plugin widget

### Frontend — Permission Matrix

- Column header checkboxes: click "view" header → toggles ALL view permissions across all groups
- Same for "manage" and "configure" columns
- Indeterminate state when partially selected

### Frontend — User Management

- `UserCreate.vue`: role dropdown with SUPER_ADMIN, ADMIN, USER, VENDOR
- `UserEdit.vue`: shows access level checkboxes only for ADMIN users
- `Users.vue`: role column shows enum value (SUPER_ADMIN, ADMIN, USER)
- `AccessLevelForm.vue`: removed "Grants admin panel access" checkbox
- `AccessLevels.vue`: removed "Admin Access" column

---

## Permission Map

### Core Permissions (8)

| Key | Action | Group |
|-----|--------|-------|
| `users.view` | View user list and details | Users |
| `users.manage` | Create, edit, delete, suspend users | Users |
| `invoices.view` | View invoice list, details, PDF | Invoices |
| `invoices.manage` | Mark paid, void, refund, delete | Invoices |
| `analytics.view` | View dashboard analytics | Analytics |
| `settings.view` | View settings, countries, token bundles | Settings |
| `settings.manage` | Edit settings, payment methods, tax | Settings |
| `settings.system` | Manage plugins, access levels, API keys | Settings |

### Plugin Permissions (50+)

Each plugin declares `admin_permissions` on its backend class. Examples:

- **Shop**: `shop.products.view`, `shop.products.manage`, `shop.orders.view`, `shop.orders.manage`, `shop.stock.manage`, `shop.warehouses.manage`, `shop.categories.manage`, `shop.configure`
- **CMS**: `cms.pages.view`, `cms.pages.manage`, `cms.images.view`, `cms.images.manage`, `cms.layouts.manage`, `cms.widgets.view`, `cms.widgets.manage`, `cms.styles.manage`, `cms.configure`
- **Booking**: `booking.bookings.view`, `booking.bookings.manage`, `booking.resources.view`, `booking.resources.manage`, `booking.schemas.manage`, `booking.configure`
- **Subscription**: `subscription.plans.view`, `subscription.plans.manage`, `subscription.subscriptions.view`, `subscription.subscriptions.manage`, `subscription.addons.manage`, `subscription.configure`
- **Discount**: `discount.discounts.view`, `discount.discounts.manage`, `discount.coupons.view`, `discount.coupons.manage`, `discount.configure`
- **Email**: `email.templates.view`, `email.templates.manage`, `email.configure`

---

## Enforcement Stack

```
HTTP Request
  → @require_auth (JWT token validation)
    → @require_admin (user.role is SUPER_ADMIN or ADMIN)
      → @require_permission("resource.action")
        SUPER_ADMIN → always passes (wildcard *)
        ADMIN → checks assigned access levels for matching permission
        → 403 {"error": "Permission denied", "required": "resource.action"}
```

Frontend mirrors this:
```
Route Navigation
  → router.beforeEach (isAuthenticated check)
    → meta.requiredPermission check (authStore.hasPermission)
      → Redirect to /admin/forbidden if denied

Sidebar Rendering
  → NavItem.requiredPermission check (authStore.hasPermission)
    → Item hidden if permission missing
```

---

## Test Users

| Email | Password | Role | Access Level |
|-------|----------|------|-------------|
| `admin@example.com` | `AdminPass123@` | SUPER_ADMIN | N/A (wildcard) |
| `user.pro@demo.local` | `demo123` | ADMIN | Observer (view-only) |
| `test@example.com` | `TestPass123@` | USER | N/A |
| `user.free@demo.local` | `demo123` | USER | N/A |

---

## Playwright E2E Tests

| Test File | Tests | What It Proves |
|-----------|-------|----------------|
| `admin-limited-access.spec.ts` | 5 | ADMIN with CMS-only access: sidebar shows only CMS, API returns 403 for users/invoices/settings, CMS API works, super admin has full access |
| `access-level-management.spec.ts` | 6 | CRUD access levels via API, system roles protected, permissions API works, export/import roundtrip |
| `access-control-toggle.spec.ts` | 1 | Full toggle demo: super admin sidebar → create restricted role → assign to user → login as restricted → 403 on restricted pages → cleanup |
| `observer-login.spec.ts` | 3 | Observer role login works, restricted pages blocked, admin full access |
| `super-admin-crud.spec.ts` | 5 | Super admin: login, list users, create/delete user, update role, access all restricted endpoints |

---

## Bug Fixes During Implementation

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| ADMIN user could access all APIs | Routes only had `@require_admin`, not `@require_permission` | Added `@require_permission` to all 73 admin routes |
| Plugin sidebar items visible without permission | `extensionRegistry._insertItem()` dropped `requiredPermission` during copy | Added `requiredPermission` to the copy |
| Core sidebar items visible without permission | Core nav items had no `requiredPermission` | Added `requiredPermission` to Users, Invoices, Settings items |
| Core frontend routes accessible without permission | Routes in `router/index.ts` had no `meta.requiredPermission` | Added to all core admin routes |
| `isAdmin` check used RBAC roles instead of enum | `is_admin` property checked `role.is_admin` on RBAC roles | Changed to check `user.role in (SUPER_ADMIN, ADMIN)` |
| Login response missing `role` field | `UserData` and schema didn't include role enum | Added `role` field to dataclass and Marshmallow schema |
| Checkout 500 error | Plugin handler imported wrong `CheckoutRequestedEvent` class + missing DI repos | Fixed import path + added repos to container |

---

## Architecture Principles Applied

| Principle | How Applied |
|-----------|------------|
| **Core agnostic** | Core defines permission format (`resource.action`) but doesn't know about plugin permissions. Plugins declare their own. |
| **Defense in depth** | Both backend (API) and frontend (routes + sidebar) enforce permissions independently |
| **SOLID — Open/Closed** | New plugins add permissions without modifying core access routes or sidebar logic |
| **SOLID — Single Responsibility** | `@require_admin` checks panel access; `@require_permission` checks granular access; separate concerns |
| **DRY** | One `hasPermission()` method on User model used by decorator, auth store getter, and sidebar filter |
| **Liskov** | All permission types (core + plugin) follow same `{key, label, group}` interface; any permission works anywhere |
| **No over-engineering** | Simple enum for roles, simple permission strings, no complex policy engines |
