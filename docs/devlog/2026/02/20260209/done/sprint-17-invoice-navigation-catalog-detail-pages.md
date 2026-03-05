# Sprint 17: Invoice Navigation & Read-Only Catalog Detail Pages

## Context
Users need to navigate from the dashboard to invoice details, and from invoice line items to the specific catalog item (plan, addon, or token bundle) that was purchased. Currently:
- Dashboard invoice items are NOT clickable (plain divs)
- Invoice line item links go to generic list pages (`/dashboard/plans`, `/dashboard/tokens`, `/dashboard/add-ons`) instead of the specific item
- No read-only detail views exist for plans or token bundles on the user side

The user should see the same fields as the admin edit pages, but in **read-only** mode. We'll create reusable `DetailField`/`DetailGrid` components in view-component (DRY), then build three read-only catalog views.

---

## Core Requirements (enforced across all tasks)

| Principle | How it applies in this sprint |
|-----------|-------------------------------|
| **TDD-First** | Write failing tests (RED) before implementation (GREEN), then refactor. Tests for DetailField/DetailGrid, PlanDetailView, TokenBundleDetailView, AddonInfoView all written before the views. |
| **DRY** | Shared `DetailField` + `DetailGrid` in `@vbwd/view-component` eliminate repeated label+value markup across PlanDetailView, TokenBundleDetailView, AddonInfoView, and existing AddonDetail. |
| **SOLID — SRP** | Each new view has one responsibility (display a single catalog item read-only). DetailField renders one field; DetailGrid handles layout. |
| **SOLID — OCP** | DetailField is open for extension via `badge` prop and slot support, closed for modification — no need to change it per-view. |
| **SOLID — LSP** | DetailField accepts any `string | number | null` value — subtypes (plan name, price, token amount) all work identically. |
| **SOLID — ISP** | DetailField exposes minimal props (`label`, `value`, `badge`, `badgeVariant`). Views consume only what they need. |
| **SOLID — DIP** | Views depend on the `api` abstraction (ApiClient from view-component), not concrete HTTP implementations. New views follow the same DI pattern as existing AddonDetail. |
| **Clean Code** | Self-documenting component names, consistent `data-testid` attributes, no magic strings (all labels from i18n). |
| **Type Safety** | Strict TypeScript — explicit interfaces for API responses, no `any` types. Props fully typed. |
| **Coverage** | 95%+ for core SDK components (DetailField, DetailGrid). 80%+ for user views (loading, render, error, navigation states). |

---

## Task 1: Shared Components in `@vbwd/view-component`

### 1a. `DetailField.vue` — `core/src/components/ui/DetailField.vue`
A label + value display component for read-only detail views.

Props:
- `label: string` (required)
- `value: string | number | null` (default: `'-'`)
- `badge: boolean` (default: false — renders value as a Badge)
- `badgeVariant: string` (default: 'info' — passed to Badge when badge=true)

Template: `.vbwd-detail-field > .vbwd-detail-field-label + .vbwd-detail-field-value` (or Badge)

### 1b. `DetailGrid.vue` — `core/src/components/ui/DetailGrid.vue`
A responsive grid container for DetailField components.

Props:
- `columns: number` (default: 2)

Template: `.vbwd-detail-grid` with `grid-template-columns: repeat(columns, 1fr)` and slot for children.

### 1c. Export & register
- Add exports to `core/src/components/ui/index.ts`

### 1d. Tests
- `core/tests/unit/components/ui/DetailField.spec.ts`
  - renders label and value
  - shows '-' when value is null/undefined
  - renders Badge when badge=true
  - passes badgeVariant to Badge
- `core/tests/unit/components/ui/DetailGrid.spec.ts`
  - renders slot content
  - applies correct grid columns style
  - defaults to 2 columns

### Files:
- NEW: `core/src/components/ui/DetailField.vue`
- NEW: `core/src/components/ui/DetailGrid.vue`
- EDIT: `core/src/components/ui/index.ts` (add exports)
- NEW: `core/tests/unit/components/ui/DetailField.spec.ts`
- NEW: `core/tests/unit/components/ui/DetailGrid.spec.ts`

---

## Task 2: Make Dashboard Invoice Items Clickable

### `user/vue/src/views/Dashboard.vue` lines 282-300
Wrap each `.invoice-item` div with `<router-link>` to `/dashboard/invoices/:id`, matching the existing addon-item pattern (lines 184-193 use `router-link` with `.addon-item-link` class).

Change `<div>` to `<router-link>` with `:to="/dashboard/invoices/${invoice.id}"` and add `.invoice-item-link` CSS (same pattern as existing `.addon-item-link`).

### Files:
- EDIT: `user/vue/src/views/Dashboard.vue`

---

## Task 3: New User Views — Read-Only Catalog Detail Pages

### 3a. `PlanDetailView.vue` — `user/vue/src/views/PlanDetailView.vue`
Route: `/dashboard/plans/:planId`
Fetches plan via `GET /tarif-plans/:planId` (same endpoint used by checkout plugin).
Displays read-only using DetailField/DetailGrid: name, price, billing_period, features, description.

### 3b. `TokenBundleDetailView.vue` — `user/vue/src/views/TokenBundleDetailView.vue`
Route: `/dashboard/tokens/:bundleId`
Fetches bundle via `GET /token-bundles/:bundleId`.
Displays read-only: name, description, token_amount, price.

### 3c. `AddonInfoView.vue` — `user/vue/src/views/AddonInfoView.vue`
Route: `/dashboard/add-ons/info/:addonId`
Fetches addon via `GET /addons/:addonId` (public catalog endpoint).
Displays read-only: name, slug, description, price, billing_period.

Note: Separate from existing `AddonDetail.vue` at `/dashboard/add-ons/:id` which shows user's addon SUBSCRIPTION. This shows the CATALOG addon item.

### Files:
- NEW: `user/vue/src/views/PlanDetailView.vue`
- NEW: `user/vue/src/views/TokenBundleDetailView.vue`
- NEW: `user/vue/src/views/AddonInfoView.vue`

---

## Task 4: Router Updates

### `user/vue/src/router/index.ts`
Add three routes. Place `/dashboard/add-ons/info/:addonId` BEFORE `/dashboard/add-ons/:id`:
```ts
{ path: '/dashboard/plans/:planId', name: 'plan-detail', ... },
{ path: '/dashboard/tokens/:bundleId', name: 'token-bundle-detail', ... },
{ path: '/dashboard/add-ons/info/:addonId', name: 'addon-info', ... },
```

### Files:
- EDIT: `user/vue/src/router/index.ts`

---

## Task 5: Update Invoice Detail Line Item Links

### `user/vue/src/views/InvoiceDetail.vue` — `itemLink()` (line 226)
Change from generic list pages to specific detail pages:
- `subscription` → `/dashboard/plans/${item.item_id}`
- `token_bundle` → `/dashboard/tokens/${item.item_id}`
- `add_on` → `/dashboard/add-ons/info/${item.item_id}`

### Files:
- EDIT: `user/vue/src/views/InvoiceDetail.vue`

---

## Task 6: i18n — EN + DE translations

Add keys for `planDetail`, `tokenBundleDetail`, `addonInfo` sections to both locale files (title, loading, error, field labels).

### Files:
- EDIT: `user/vue/src/i18n/locales/en.json`
- EDIT: `user/vue/src/i18n/locales/de.json`

---

## Task 7: Tests (TDD)

### New test files (follow existing `addon-detail.spec.ts` pattern):
- `user/vue/tests/unit/views/plan-detail.spec.ts` — loading, fetch+render, error, features, back link
- `user/vue/tests/unit/views/token-bundle-detail.spec.ts` — loading, fetch+render, error, back link
- `user/vue/tests/unit/views/addon-info.spec.ts` — loading, fetch+render, error, back link
- `core/tests/unit/components/ui/DetailField.spec.ts` (from Task 1d)
- `core/tests/unit/components/ui/DetailGrid.spec.ts` (from Task 1d)

---

## Implementation Order

1. Task 1 — Shared components (DetailField, DetailGrid) + tests
2. Task 6 — i18n keys
3. Task 7 — Write tests first (TDD)
4. Task 3 — Create the three new views (make tests pass)
5. Task 4 — Router updates
6. Task 5 — Update InvoiceDetail itemLink
7. Task 2 — Dashboard invoice clickability

---

## Verification

```bash
cd vbwd-frontend/core && npx vitest run
cd vbwd-frontend/user && npx vitest run --config vitest.config.js
cd vbwd-frontend/admin/vue && npx vitest run
```
