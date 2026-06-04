# Sprint 14d — E2E: Access Control Scenarios (Playwright)

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [14 — Access Control Bulletproof Tests](14-access-bulletproof-tests.md)

---

## Goal

End-to-end Playwright tests that prove the access control system works in real browser scenarios across the full stack (backend + frontend together).

---

## Test Scenarios

### Scenario 1: Super Admin Has Full Access

| # | Step | Expected |
|---|------|----------|
| 1 | Login as `admin@example.com` (super-admin) | Dashboard loads |
| 2 | Navigate to `/admin/shop/products` | Products page renders |
| 3 | Navigate to `/admin/booking/resources` | Resources page renders |
| 4 | Navigate to `/admin/cms/pages` | Pages page renders |
| 5 | Navigate to `/admin/settings/access` | Access Levels page renders |
| 6 | Sidebar shows all sections (Sales, CMS, Settings, etc.) | All nav items visible |

### Scenario 2: Limited Role — Content Manager

| # | Step | Expected |
|---|------|----------|
| 1 | Create role "content-manager" with only `cms.pages.view`, `cms.pages.manage`, `cms.images.view`, `cms.images.manage` | Role created |
| 2 | Create test user, assign "content-manager" role | User has role |
| 3 | Login as test user | Dashboard loads |
| 4 | Sidebar shows only CMS section | No Shop, no Booking, no Settings |
| 5 | Navigate to `/admin/cms/pages` | Pages page renders |
| 6 | Navigate to `/admin/shop/products` via URL | Forbidden page (403) |
| 7 | Navigate to `/admin/settings/access` via URL | Forbidden page (403) |
| 8 | API call `GET /admin/shop/products` | 403 response |
| 9 | API call `GET /admin/cms/pages` | 200 response |

### Scenario 3: Plugin Disabled — Shop Off

| # | Step | Expected |
|---|------|----------|
| 1 | Login as super-admin | Dashboard loads |
| 2 | Disable "shop" plugin via admin settings | Plugin deactivated |
| 3 | Sidebar no longer shows "Shop" section | Nav items gone |
| 4 | Navigate to `/admin/shop/products` via URL | 404 or forbidden |
| 5 | API call `GET /admin/shop/products` | 404 (blueprint not registered or plugin check) |
| 6 | Permission matrix on access level edit — shop permissions gone | No shop rows in table |
| 7 | Re-enable "shop" plugin | Plugin activated |
| 8 | Sidebar shows "Shop" section again | Nav items back |
| 9 | Navigate to `/admin/shop/products` | Products page renders |
| 10 | Permission matrix shows shop permissions again | Shop rows in table |

### Scenario 4: Role Assignment + Immediate Effect

| # | Step | Expected |
|---|------|----------|
| 1 | Login as super-admin | Full access |
| 2 | Create role "sales-only" with `shop.products.view`, `shop.orders.view`, `invoices.view` | Role created |
| 3 | Create test user, assign "sales-only" | User created |
| 4 | Login as test user | Dashboard loads |
| 5 | Can see Shop Products (view) | Page renders |
| 6 | Cannot create new product (no `shop.products.manage`) | Create button hidden or 403 |
| 7 | Can see Invoices | Page renders |
| 8 | Cannot access CMS | Forbidden |
| 9 | Login as super-admin, revoke "sales-only" from test user | Role revoked |
| 10 | Login as test user again | Minimal access (no sales, no CMS) |

### Scenario 5: Bulk Role Assignment

| # | Step | Expected |
|---|------|----------|
| 1 | Login as super-admin | Full access |
| 2 | Go to Users list | Users page renders |
| 3 | Select 3 users via checkboxes | Bulk actions visible |
| 4 | Select "content-manager" from access level dropdown | Selected |
| 5 | Click "Apply" | Success message "Assigned to 3 users" |
| 6 | Verify each user now has "content-manager" role | API confirms |

### Scenario 6: System Role Protection

| # | Step | Expected |
|---|------|----------|
| 1 | Navigate to Access Levels list | System roles visible |
| 2 | "super-admin" row has no Delete button | Cannot delete |
| 3 | "admin" row has no Delete button | Cannot delete |
| 4 | API call `DELETE /admin/access/levels/{super-admin-id}` | 400 "System roles cannot be deleted" |
| 5 | Custom role has Delete button and can be deleted | Role deleted |

---

## Test Fixtures

```typescript
// tests/e2e/fixtures/access.fixtures.ts

const API = process.env.E2E_API_URL || 'http://localhost:5000/api/v1';
const BASE = process.env.E2E_BASE_URL || 'http://localhost:8081';

async function loginAsAdmin(page: Page): Promise<void> {
  // Login as admin@example.com
}

async function createRole(name: string, slug: string, permissions: string[]): Promise<string> {
  // Create role via API, return role ID
}

async function createUserWithRole(email: string, roleId: string): Promise<string> {
  // Create user + assign role, return user ID
}

async function deleteRole(roleId: string): Promise<void> {
  // Cleanup
}

async function deleteUser(userId: string): Promise<void> {
  // Cleanup
}

async function disablePlugin(pluginName: string): Promise<void> {
  // Disable plugin via admin API
}

async function enablePlugin(pluginName: string): Promise<void> {
  // Re-enable plugin via admin API
}
```

---

## Screenshot Strategy

Take screenshots at every assertion failure point:
- `page.screenshot({ path: 'test-results/access-forbidden.png' })`
- Console log collection: `page.on('console', msg => ...)`

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create `tests/e2e/fixtures/access.fixtures.ts` | — |
| 2 | Scenario 1: super-admin full access | TDD |
| 3 | Scenario 2: limited role (content manager) | TDD |
| 4 | Scenario 3: plugin disabled → no access | TDD |
| 5 | Scenario 4: role assignment + immediate effect | TDD |
| 6 | Scenario 5: bulk role assignment | TDD |
| 7 | Scenario 6: system role protection | TDD |
| 8 | `pre-commit-check.sh --full` (fe-admin) | — |

---

## Pre-commit Validation

```bash
E2E_BASE_URL=http://localhost:8081 cd vbwd-fe-admin && npx playwright test
E2E_BASE_URL=http://localhost:8080 cd vbwd-fe-user && npx playwright test
```
