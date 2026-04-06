# Sprint 14c — Frontend: Permission UI Tests

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [14 — Access Control Bulletproof Tests](14-access-bulletproof-tests.md)

---

## Goal

Unit tests proving the frontend permission system works correctly: sidebar filtering, router guard, permission matrix, disabled plugin nav.

---

## Test Cases

### Auth Store — hasPermission (fe-core)

| # | Test | Expected |
|---|------|----------|
| 1 | `hasPermission('shop.products.view')` with `['shop.products.view']` | true |
| 2 | `hasPermission('shop.products.view')` with `[]` | false |
| 3 | `hasPermission('anything')` with `['*']` | true (wildcard) |
| 4 | `hasPermission('shop.orders.view')` with `['shop.*']` | true (plugin wildcard) |
| 5 | `hasPermission('cms.pages.view')` with `['shop.*']` | false (wrong plugin) |
| 6 | `hasAnyPermission(['shop.products.view', 'cms.pages.view'])` with `['shop.products.view']` | true |
| 7 | `hasAnyPermission(['shop.products.view', 'cms.pages.view'])` with `[]` | false |
| 8 | `isAdmin` with roles `['super-admin']` | true |
| 9 | `isAdmin` with roles `['user']` | false |

### AdminSidebar — Permission Filtering (fe-admin)

| # | Test | Expected |
|---|------|----------|
| 10 | Nav item with `requiredPermission: 'shop.products.view'` — user has it | Item visible |
| 11 | Nav item with `requiredPermission: 'shop.products.view'` — user lacks it | Item hidden |
| 12 | Child nav item hidden but parent visible (parent has different permission) | Parent shown, child hidden |
| 13 | All children hidden → parent also hidden (empty section removed) | Section gone |
| 14 | No `requiredPermission` on item — always visible | Item visible regardless of permissions |
| 15 | Plugin disabled → plugin nav items not registered → not in sidebar | No shop items |

### Router Guard (fe-admin)

| # | Test | Expected |
|---|------|----------|
| 16 | Navigate to `/admin/shop/products` with `shop.products.view` permission | Renders page |
| 17 | Navigate to `/admin/shop/products` without permission | Redirects to `/admin/forbidden?required=shop.products.view` |
| 18 | Navigate to `/admin/settings/access` with `settings.system` | Renders page |
| 19 | Navigate to `/admin/settings/access` without `settings.system` | Redirects to forbidden |
| 20 | Navigate to `/admin/dashboard` (no `requiredPermission`) | Always renders |

### Permission Matrix Table (fe-admin)

| # | Test | Expected |
|---|------|----------|
| 21 | Table renders groups from API permissions | Core, Shop, CMS sections visible |
| 22 | Disabled plugin's permissions not in table | Shop section gone when shop disabled |
| 23 | Group header checkbox toggles view + manage (not configure) | Correct checkboxes toggled |
| 24 | Row checkbox toggles view + manage | Correct checkboxes toggled |
| 25 | Special permissions appear in separate section | `settings.system` in special section |
| 26 | Resource without `view` shows `—` in view column | Dash rendered |

### User Edit — Role Assignment (fe-admin)

| # | Test | Expected |
|---|------|----------|
| 27 | Available roles loaded from API | Dropdown shows super-admin, admin, user |
| 28 | User's current roles pre-checked | Checkboxes match user's roles |
| 29 | Toggle role sends API call immediately | POST/DELETE to access API |

---

## Test Utilities (shared)

```typescript
// tests/fixtures/permissions.ts

function mountWithPermissions(component, permissions: string[], options = {}) {
  // Mount component with auth store pre-loaded with given permissions
}

function mockAuthStore(roles: string[], permissions: string[]) {
  // Create mock auth store with specific roles/permissions
}
```

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create `tests/fixtures/permissions.ts` shared utilities | — |
| 2 | Unit tests: auth store hasPermission (cases 1-9) | TDD |
| 3 | Unit tests: sidebar filtering (cases 10-15) | TDD |
| 4 | Unit tests: router guard (cases 16-20) | TDD |
| 5 | Unit tests: permission matrix table (cases 21-26) | TDD |
| 6 | Unit tests: user edit role assignment (cases 27-29) | TDD |
| 7 | `pre-commit-check.sh --full` (fe-admin) | — |

---

## Pre-commit Validation

```bash
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
