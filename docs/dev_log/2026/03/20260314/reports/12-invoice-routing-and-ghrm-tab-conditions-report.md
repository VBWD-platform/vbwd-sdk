# Report 12 — Invoice Routing Unification & GHRM Tab Conditions

**Date:** 2026-03-15
**Scope:** `vbwd-fe-user`, `vbwd-fe-admin`

---

## Summary

This sprint resolved a cluster of routing, data-correctness, and UX-consistency issues across the user dashboard and admin backoffice. All changes were driven by TDD-first: failing tests were written, then implementation followed.

---

## Issues Fixed

### 1. Invoice Line Items — Wrong ID Field (fe-admin + fe-user)

**Symptom:** Clicking an invoice line item in admin produced a 404 (`GET /api/v1/admin/tarif-plans/<subscription-uuid>`). Same bug existed on the user dashboard invoice detail page.

**Root cause:** `itemLink()` used `item.item_id` (the purchase record UUID — a subscription, token bundle purchase, or addon subscription) instead of `item.catalog_item_id` (the catalog entity UUID — the plan, bundle, or addon definition).

The backend `InvoiceLineItem.to_dict()` returns both fields:
- `item_id` → purchase record (e.g. `UserSubscription.id`)
- `catalog_item_id` → catalog entity (e.g. `TarifPlan.id`)

**Fix:** Updated `itemLink()` in both `fe-admin/InvoiceDetails.vue` and `fe-user/InvoiceDetail.vue` to use `catalog_item_id`. Also fixed case handling (`.toUpperCase()` before switch) and corrected route names (`/dashboard/plan/` singular, not `/dashboard/plans/`).

**Tests:**
- `fe-admin/tests/unit/views/invoice-details-line-items.spec.ts` — 5 tests covering SUBSCRIPTION, TOKEN_BUNDLE, ADD_ON, missing catalog_item_id, and lowercase type
- `fe-user/tests/unit/views/invoice-detail-line-items.spec.ts` — 5 tests covering same scenarios for user view

---

### 2. Unified Invoice Route

**Symptom:** Invoices were accessed via `/dashboard/subscription/invoices/:id` — a sub-resource path that is semantically wrong (invoices are top-level resources, not children of subscriptions).

**Fix:**
- Added canonical route `/dashboard/invoice/:invoiceId` → `InvoiceDetail.vue`
- Added canonical route `/dashboard/invoice/:invoiceId/pay` → `InvoicePay.vue`
- Added legacy redirects so old bookmarked URLs still work
- Updated all navigation call sites:
  - `Dashboard.vue` → `/dashboard/invoice/${id}`
  - `Invoices.vue` → `viewInvoice()` and `payInvoice()` use new paths
  - `Subscription.vue` → `viewInvoice()` navigates to page instead of opening inline modal
  - `InvoiceDetail.vue` → "Pay Now" button uses `/dashboard/invoice/${id}/pay`

---

### 3. GHRM Tabs Showing on Non-GHRM Plans

**Symptom:** The GHRM plugin added "Software" and "GitHub Access" tabs to **all** plans (including generic plans like `pro`, `enterprise` with no GHRM packages).

**Root cause:** Tab registration happens unconditionally at plugin activation — the registry had no way to suppress tabs per plan.

**Fix:** Added `condition?: (planId: string) => Promise<boolean>` to `PlanDetailTab` interface. `TarifPlanDetail` evaluates all conditions after loading the plan (using the plan UUID), and only renders tabs that pass.

GHRM's condition calls `getPackageByPlan(planId)`:
- Returns `true` if a package exists → tab shown
- Returns `false` on 404 → tab hidden

This preserves the Open/Closed principle — core has no knowledge of GHRM; GHRM self-filters.

**Tests:** `tests/unit/views/tarif-plan-detail-tab-condition.spec.ts` — 3 tests: condition true shows, condition false hides, no condition always shows.

---

### 4. GitHub Connect → Redirect to Dashboard (Bug)

**Symptom:** Clicking the GitHub Connect button in GHRM redirected to `/dashboard` instead of triggering the OAuth flow.

**Root cause:** `connect()` in `GhrmGithubConnectButton.vue` had an `if (!authStore.isAuthenticated) router.push('/login')` guard. The button is on a protected page so the user is always authenticated — but the auth check was inverted in an earlier refactor. Router guard then bounced `/login` → `/dashboard`.

**Fix:** Removed the auth check entirely. The button is only rendered inside authenticated routes; just call `getOAuthUrl()` directly.

---

### 5. GHRM Tabs Using Plan Slug Instead of Plan UUID

**Symptom:** `GhrmPlanGithubAccessTab` and `GhrmPlanSoftwareTab` called `getPackageByPlan(props.planSlug)` but the endpoint expects a UUID plan ID, producing 404s.

**Fix:** Added `planId: string` prop to both tab components. `TarifPlanDetail` passes `:plan-id="plan?.id"` (UUID). The `planSlug` prop is kept for display purposes only.

---

### 6. Plan Route Rename

`/dashboard/tarif/:planSlug` renamed to `/dashboard/plan/:planSlug` for semantic consistency. Old path not redirected (it was internal-only, never bookmarked).

---

### 7. Nav — "Software Catalogue" Under Store Group

The GHRM nav item was floating at the top level of the sidebar. Moved it into a "Store" collapsible group, positioned last after add-ons, with an external link icon (↗) to signal it opens a different area (public catalogue).

Implementation: `userNavRegistry` gained `group?: 'store'` and `externalIcon?: boolean` fields. `getSidebarItems()` excludes grouped items. `getGroupItems('store')` powers the new Store section in `UserLayout.vue`.

---

## Hard Tasks

### GHRM Tab Condition — Open/Closed Without Core Coupling

The hardest design problem was: how do you suppress plugin-injected tabs for plans that don't have a matching package, **without** making core aware of GHRM?

The naive solution (checking inside `TarifPlanDetail` if the plan has a GHRM package) would couple core to a plugin. The correct solution is an inversion: let the plugin declare its own guard as a predicate function. Core evaluates predicates generically without knowing what they check.

The `condition?: (planId: string) => Promise<boolean>` pattern is exactly this. It took two iterations:
- First attempt: condition evaluated at registration time (wrong — plan ID isn't known yet)
- Second attempt: condition evaluated per-navigation after plan loads (correct)

### `vi.mock` Hoisting Trap

Several tests failed with `ReferenceError: Cannot access 'mockX' before initialization`. This is because `vi.mock` factories are hoisted to the top of the file before `const`/`let` declarations are executed. The fix: use `vi.fn()` inside the factory and then `vi.mocked(module.fn)` after import to get a typed reference.

### `catalog_item_id` vs `item_id`

The data model has two distinct ID fields on line items and confusing them produces 404s that look like missing routes. Understanding that `item_id` is the **purchase record** and `catalog_item_id` is the **catalog entity** (the thing that was bought) was critical — and neither field name is self-documenting.

---

## Files Changed

### fe-user
- `vue/src/router/index.ts` — new canonical invoice routes + legacy redirects; renamed plan route
- `vue/src/views/Dashboard.vue` — invoice links use canonical path
- `vue/src/views/Invoices.vue` — viewInvoice/payInvoice use canonical paths
- `vue/src/views/Subscription.vue` — viewInvoice navigates to page
- `vue/src/views/InvoiceDetail.vue` — itemLink uses catalog_item_id; pay link canonical; row click on line items
- `vue/src/views/TarifPlanDetail.vue` — evaluates tab conditions; passes planId to tabs
- `vue/src/utils/planDetailTabRegistry.ts` — condition field on PlanDetailTab
- `vue/src/plugins/userNavRegistry.ts` — group + externalIcon fields
- `vue/src/layouts/UserLayout.vue` — Store group section
- `plugins/ghrm/src/components/GhrmGithubConnectButton.vue` — removed auth guard
- `plugins/ghrm/src/components/GhrmPlanGithubAccessTab.vue` — planId prop
- `plugins/ghrm/src/components/GhrmPlanSoftwareTab.vue` — planId prop
- `plugins/ghrm/index.ts` — condition + nav group registration

### fe-admin
- `vue/src/views/InvoiceDetails.vue` — itemLink uses catalog_item_id

### Tests added
- `vue/tests/unit/views/invoice-detail-line-items.spec.ts`
- `vue/tests/unit/views/tarif-plan-detail-tab-condition.spec.ts`
- `vue/tests/unit/plugins/ghrm-connect-button.spec.ts`
- `vue/tests/unit/plugins/ghrm-plan-access-tab-plan-id.spec.ts`
- `vue/tests/unit/plugins/ghrm-tabs-not-on-non-ghrm-plans.spec.ts`
- `vue/tests/unit/nav-registry-group.spec.ts`
- `fe-admin/vue/tests/unit/views/invoice-details-line-items.spec.ts`

---

## Test Results

```
fe-user:   389 passed, 49 test files
fe-admin:  (invoice-details tests passing)
```
