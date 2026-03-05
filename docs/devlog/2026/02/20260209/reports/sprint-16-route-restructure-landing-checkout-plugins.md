# Sprint 16 Report — Route Restructure + Landing1 & Checkout Plugins

**Date:** 2026-02-09
**Status:** DONE
**Priority:** HIGH

---

## Summary

Moved all authenticated user pages under `/dashboard/` prefix, then added two frontend plugins (Landing1 and Checkout) that inject public routes accessible without login. Total test count: 270 admin + 99 user = 369 frontend tests passing.

---

## Changes

### Phase 1: Route Restructure
All authenticated routes moved from top-level to `/dashboard/` prefix (e.g. `/plans` → `/dashboard/plans`). Route names kept unchanged so name-based navigation still works. Updated hardcoded links in 9 view/layout files.

### Phase 2: Plugin Infrastructure
`main.ts` now bootstraps the plugin system: creates `PluginRegistry` and `PlatformSDK`, registers plugins, installs routes via `router.addRoute()`, activates all, then mounts the app.

### Phase 3: Landing1 Plugin
- **Route:** `/landing1` (public, no auth)
- **View:** Fetches `GET /api/v1/tarif-plans` via `fetch()`, renders plan cards grid
- "Choose Plan" navigates to `/checkout?tarif_plan_id=<slug>`

### Phase 4: Checkout Plugin
- **Route:** `/checkout` (public, no auth), name `checkout-public`
- **View:** Reads `tarif_plan_id` from query params, reuses existing checkout components (EmailBlock, BillingAddressBlock, PaymentMethodsBlock, TermsCheckbox)
- Works for both anonymous and logged-in users

### Phase 5: i18n
Added `landing1.*` keys (title, subtitle, noPlans, choosePlan) to EN and DE.

### Phase 6: Tests
- 8 new landing1 tests (plugin registration + view behavior)
- 7 new checkout-public tests (plugin registration + view behavior)
- No existing test changes needed (store tests are path-agnostic)

---

## Files Changed

### New (6):
| File | Purpose |
|------|---------|
| `plugins/landing1/index.ts` | Landing1 plugin definition |
| `plugins/landing1/Landing1View.vue` | Public tariff plan chooser |
| `plugins/checkout/index.ts` | Checkout plugin definition |
| `plugins/checkout/PublicCheckoutView.vue` | Public checkout page |
| `tests/unit/plugins/landing1.spec.ts` | 8 tests |
| `tests/unit/plugins/checkout-public.spec.ts` | 7 tests |

### Modified (13):
| File | Change |
|------|--------|
| `src/router/index.ts` | Auth routes → `/dashboard/` prefix |
| `src/main.ts` | Plugin bootstrap |
| `src/layouts/UserLayout.vue` | Nav links + goToCheckout |
| `src/views/Dashboard.vue` | ~12 route links |
| `src/views/Checkout.vue` | Route links |
| `src/views/Subscription.vue` | Route links |
| `src/views/Tokens.vue` | Route links |
| `src/views/AddOns.vue` | Route links |
| `src/views/InvoiceDetail.vue` | Route links |
| `src/views/InvoicePay.vue` | Route links |
| `src/views/Invoices.vue` | Route links |
| `src/i18n/locales/en.json` | Added `landing1.*` keys |
| `src/i18n/locales/de.json` | Added `landing1.*` keys |

---

## Test Results

```
User:  99 tests (15 files) — all passing
Admin: 270 tests (26 files) — all passing
Total: 369 frontend tests
```
