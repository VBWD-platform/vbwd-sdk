# Sprint 17 Report — Invoice Navigation & Read-Only Catalog Detail Pages

**Date:** 2026-02-09
**Status:** DONE
**Priority:** HIGH

---

## Summary

Made dashboard invoices clickable, created three read-only catalog detail views (Plan, Token Bundle, Add-On), added shared DetailField/DetailGrid components to view-component, added public backend endpoints for single-item catalog lookups, and resolved catalog_item_id mapping in invoice line items. Total test count: 270 admin + 115 user + 289 core = 674 frontend tests, 594 backend tests.

---

## Changes

### Task 1: Shared Components — `@vbwd/view-component`
- **DetailField.vue** — Reusable label+value display (supports badge mode via Badge component)
- **DetailGrid.vue** — Responsive CSS grid container with configurable columns
- Exported from `core/src/components/ui/index.ts`
- 12 tests (8 DetailField + 4 DetailGrid)

### Task 2: Dashboard Invoice Items Clickable
- Changed `<div>` invoice items to `<router-link>` linking to `/dashboard/invoices/:id`
- Added `.invoice-item-link` CSS (merged with existing `.addon-item-link` selectors)

### Task 3: Read-Only Catalog Detail Views (TDD)
- **PlanDetailView.vue** — `/dashboard/plans/:planId` — fetches `GET /tarif-plans/:id`, shows name, price, billing_period, features, description
- **TokenBundleDetailView.vue** — `/dashboard/tokens/:bundleId` — fetches `GET /token-bundles/:id`, shows name, token_amount, price
- **AddonInfoView.vue** — `/dashboard/add-ons/info/:addonId` — fetches `GET /addons/:id`, shows name, price, billing_period, currency
- 16 tests (6 plan + 5 token-bundle + 5 addon-info)

### Task 4: Router Updates
- Added 3 new routes; `/dashboard/add-ons/info/:addonId` placed before `/dashboard/add-ons/:id` to avoid conflicts

### Task 5: Invoice Line Item Links
- Updated `itemLink()` in InvoiceDetail.vue to use `catalog_item_id` (actual catalog entity UUID) instead of `item_id` (purchase record UUID)

### Task 6: i18n
- Added `planDetail`, `tokenBundleDetail`, `addonInfo` sections to EN + DE locale files

### Task 7: Backend — Public Catalog Endpoints
- `GET /tarif-plans/<slug_or_id>` — now accepts UUID (finds by ID) or slug (finds by slug), returns full plan data including description, features, billing_period
- `GET /addons/<addon_id>` — new public endpoint, returns addon details
- `GET /token-bundles/<bundle_id>` — new public endpoint, returns bundle details
- `InvoiceLineItem.to_dict()` — added `catalog_item_id` field that resolves purchase→catalog entity (subscription→tarif_plan, token_bundle_purchase→token_bundle, addon_subscription→addon)

### Task 8: Infrastructure Fixes
- **Dockerfile** — Added `COPY admin/plugins/ /app/admin/plugins/` for admin build stage (plugins moved outside admin/vue/ in Sprint 16)
- **tsconfig.json** — Added `baseUrl` and explicit path mappings for `vue` and `@vbwd/view-component` so `vue-tsc` resolves modules in plugins directory

---

## Files Changed

### New (10):
| File | Purpose |
|------|---------|
| `core/src/components/ui/DetailField.vue` | Label+value display component |
| `core/src/components/ui/DetailGrid.vue` | Grid container component |
| `core/tests/unit/components/ui/DetailField.spec.ts` | 8 tests |
| `core/tests/unit/components/ui/DetailGrid.spec.ts` | 4 tests |
| `user/vue/src/views/PlanDetailView.vue` | Read-only plan detail |
| `user/vue/src/views/TokenBundleDetailView.vue` | Read-only token bundle detail |
| `user/vue/src/views/AddonInfoView.vue` | Read-only addon catalog detail |
| `user/vue/tests/unit/views/plan-detail.spec.ts` | 6 tests |
| `user/vue/tests/unit/views/token-bundle-detail.spec.ts` | 5 tests |
| `user/vue/tests/unit/views/addon-info.spec.ts` | 5 tests |

### Modified (11):
| File | Change |
|------|--------|
| `core/src/components/ui/index.ts` | Added DetailField, DetailGrid exports |
| `user/vue/src/router/index.ts` | 3 new routes |
| `user/vue/src/views/Dashboard.vue` | Invoice items → router-link |
| `user/vue/src/views/InvoiceDetail.vue` | itemLink uses catalog_item_id |
| `user/vue/src/i18n/locales/en.json` | planDetail, tokenBundleDetail, addonInfo keys |
| `user/vue/src/i18n/locales/de.json` | planDetail, tokenBundleDetail, addonInfo keys |
| `admin/vue/tsconfig.json` | baseUrl + vue/view-component path mappings |
| `container/frontend/Dockerfile` | COPY admin/plugins/ |
| `vbwd-backend: src/routes/tarif_plans.py` | UUID+slug lookup, full plan data |
| `vbwd-backend: src/routes/addons.py` | GET /<addon_id> endpoint |
| `vbwd-backend: src/routes/token_bundles.py` | GET /<bundle_id> endpoint |
| `vbwd-backend: src/models/invoice_line_item.py` | catalog_item_id resolution |

---

## Test Results

```
Core:    289 tests (32 files) — all passing (+12 new)
User:    115 tests (18 files) — all passing (+16 new)
Admin:   270 tests (26 files) — all passing
Backend: 594 tests — all passing
Total:   1268 tests
```
