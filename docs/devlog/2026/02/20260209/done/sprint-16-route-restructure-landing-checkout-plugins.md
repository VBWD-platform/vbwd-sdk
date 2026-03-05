# Sprint 16 — Route Restructure + Landing1 & Checkout Plugins

## Goal

Move all authenticated user pages under `/dashboard/` prefix, then add two frontend plugins (Landing1 and Checkout) that inject public routes accessible without login.

## Phases

### Phase 1: Route Restructure — Move Auth Routes Under `/dashboard/`

**Router (`user/vue/src/router/index.ts`):**

| Name | Old Path | New Path |
|------|----------|----------|
| dashboard | `/dashboard` | `/dashboard` (unchanged) |
| profile | `/profile` | `/dashboard/profile` |
| subscription | `/subscription` | `/dashboard/subscription` |
| invoices | `/invoices` | `/dashboard/invoices` |
| invoice-detail | `/invoices/:invoiceId` | `/dashboard/invoices/:invoiceId` |
| invoice-pay | `/invoices/:invoiceId/pay` | `/dashboard/invoices/:invoiceId/pay` |
| plans | `/plans` | `/dashboard/plans` |
| tokens | `/tokens` | `/dashboard/tokens` |
| add-ons | `/add-ons` | `/dashboard/add-ons` |
| addon-detail | `/add-ons/:id` | `/dashboard/add-ons/:id` |
| checkout-cart | `/checkout/cart` | `/dashboard/checkout/cart` |
| checkout | `/checkout/:planSlug` | `/dashboard/checkout/:planSlug` |

**Update hardcoded links in:** UserLayout.vue, Dashboard.vue, Checkout.vue, Subscription.vue, Tokens.vue, AddOns.vue, InvoiceDetail.vue, InvoicePay.vue, Invoices.vue

### Phase 2: Plugin Infrastructure in `main.ts`

- Import `PluginRegistry`, `PlatformSDK` from `@vbwd/view-component`
- Import `landing1Plugin` and `checkoutPlugin` from `../plugins/`
- Register both, `installAll(sdk)`, inject routes via `router.addRoute()`, activate all
- Wrap `app.mount('#app')` in async bootstrap

### Phase 3: Landing1 Plugin

**New files:** `user/vue/plugins/landing1/index.ts`, `user/vue/plugins/landing1/Landing1View.vue`

- Route: `/landing1` with `requiresAuth: false`
- Fetches `GET /api/v1/tarif-plans` (public, no auth)
- Plan cards grid with "Choose Plan" button navigating to `/checkout?tarif_plan_id=<slug>`

### Phase 4: Checkout Plugin

**New files:** `user/vue/plugins/checkout/index.ts`, `user/vue/plugins/checkout/PublicCheckoutView.vue`

- Route: `/checkout` with `requiresAuth: false`, name `checkout-public`
- Reads `tarif_plan_id` from query params
- Reuses EmailBlock, BillingAddressBlock, PaymentMethodsBlock, TermsCheckbox
- Submit via checkout store

### Phase 5: i18n

Add `landing1.*` keys (title, subtitle, noPlans, choosePlan) to EN and DE locale files.

### Phase 6: Tests

- Update existing tests for `/dashboard/` prefix
- New: `tests/unit/plugins/landing1.spec.ts` (~6 tests)
- New: `tests/unit/plugins/checkout-public.spec.ts` (~6 tests)

## File Summary

### New files (6):
| File | Purpose |
|------|---------|
| `plugins/landing1/index.ts` | Landing1 plugin definition |
| `plugins/landing1/Landing1View.vue` | Tariff plan chooser |
| `plugins/checkout/index.ts` | Checkout plugin definition |
| `plugins/checkout/PublicCheckoutView.vue` | Public checkout page |
| `tests/unit/plugins/landing1.spec.ts` | Landing1 tests |
| `tests/unit/plugins/checkout-public.spec.ts` | Checkout tests |

### Modified files (~13):
| File | Change |
|------|--------|
| `src/router/index.ts` | All auth routes get `/dashboard/` prefix |
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
| `src/i18n/locales/en.json` | Add `landing1.*` keys |
| `src/i18n/locales/de.json` | Add `landing1.*` keys |

## Verification

1. `cd vbwd-frontend/user && npx vitest run --config vitest.config.js` — all tests pass
2. `cd vbwd-frontend && make test` — admin + user tests pass
3. Docker rebuild and manual verification of routes
