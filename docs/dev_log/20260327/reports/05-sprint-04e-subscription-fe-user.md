# Report 05 — Sprint 04e: Subscription User Frontend Plugin

**Date:** 2026-03-27
**Status:** Done

---

## What Was Done

Created `plugins/subscription/` in fe-user containing all plan/subscription/addon/checkout views, stores, and components. Slimmed Dashboard.vue to core-only blocks.

### Files Moved to Plugin

- **Views (8):** Plans, PlanDetailView, TarifPlanDetail, Subscription, AddOns, AddonDetail, AddonInfoView, Checkout
- **Stores (3):** plans, subscription, checkout
- **Components (4):** BillingAddressBlock, EmailBlock, PaymentMethodsBlock, TermsCheckbox
- **Tests (3):** dashboard-addons, dashboard-subscription-history, checkout-public

### Dashboard Changes

**Removed blocks:**
- Subscription card (primary + multi-subscriptions)
- Subscription history card
- Add-ons card
- Quick actions card

**Kept blocks:**
- Profile summary card
- Token activity card
- Recent invoices card
- Plugin widget slots (new — renders `sdk.getComponents()` starting with "Dashboard")

### Core Router Changes

Removed 12 routes: `/dashboard/subscription`, `/dashboard/plans/*`, `/dashboard/add-ons/*`, `/dashboard/checkout/*`, legacy invoice redirects.

### Other Changes

- `checkout` plugin disabled in `plugins.json` (merged into subscription)
- `subscription` plugin registered in `plugins.json` + `config.json` + `.gitignore`

### Test Results

- Core: **42 test files, 318 passed** (all green)
- Pre-existing: `stripe-views.spec.ts` — 3 failures (`router.replace is not a function`), unrelated to this sprint
