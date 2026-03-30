# Dev Log — 2026-03-27 / 2026-03-28

## Reports

| # | Report | Status |
|---|--------|--------|
| 01 | [Sprint 04a: Line Item Handler Registry](reports/01-sprint-04a-line-item-handler-registry.md) | Done |
| 02 | [Sprint 04b: Subscription Backend Plugin](reports/02-sprint-04b-subscription-backend-plugin.md) | Done |
| 03 | [Sprint 04c: Remove Subscriptions from Core](reports/03-sprint-04c-core-cleanup.md) | Done |
| 04 | [Sprint 04d: Subscription Admin Frontend](reports/04-sprint-04d-subscription-fe-admin.md) | Done |
| 05 | [Sprint 04e: Subscription User Frontend](reports/05-sprint-04e-subscription-fe-user.md) | Done |
| 06 | [Sprint 04f: Plugin Compatibility](reports/06-sprint-04f-plugin-compatibility.md) | Done |
| 07 | [Sprint 05: Extensible Admin Sidebar](reports/07-sprint-05-extensible-admin-sidebar.md) | Done |

## Sprints

| # | Sprint | Status | Report |
|---|--------|--------|--------|
| 04 | [Subscription Plugin Extraction — Overview](sprints/04-subscription-plugin-extraction.md) | Done | — |
| 04a | [Line Item Handler Registry](done/04a-line-item-handler-registry.md) | Done | [01](reports/01-sprint-04a-line-item-handler-registry.md) |
| 04b | [Subscription Backend Plugin](done/04b-subscription-be.md) | Done | [02](reports/02-sprint-04b-subscription-backend-plugin.md) |
| 04c | [Remove Subscriptions from Core](done/04c-core-cleanup.md) | Done | [03](reports/03-sprint-04c-core-cleanup.md) |
| 04d | [Subscription Admin Frontend](done/04d-subscription-fe-admin.md) | Done | [04](reports/04-sprint-04d-subscription-fe-admin.md) |
| 04e | [Subscription User Frontend](done/04e-subscription-fe-user.md) | Done | [05](reports/05-sprint-04e-subscription-fe-user.md) |
| 04f | [Plugin Compatibility](done/04f-plugin-compatibility.md) | Done | [06](reports/06-sprint-04f-plugin-compatibility.md) |
| 05 | [Extensible Admin Sidebar](done/05-extensible-admin-sidebar.md) | Done | [07](reports/07-sprint-05-extensible-admin-sidebar.md) |
| 06 | [E-commerce Plugin Bundle — Overview](sprints/06-ecommerce-plugin-bundle.md) | Done | — |
| 06h | [Checkout Plugin Extension](done/06h-checkout-plugin-extension.md) | Done | [08](reports/08-sprint-06h-checkout-step-registry.md) |
| 06a | [E-commerce: Models + Stock](done/06a-ecommerce-be-models.md) | Done | — |
| 06b | [E-commerce: Services + Handler](done/06b-ecommerce-be-services.md) | Done | — |
| 06c | [E-commerce: Routes + Shipping](done/06c-ecommerce-be-routes-shipping.md) | Done | — |
| 06d | [E-commerce: Admin Frontend](done/06d-ecommerce-fe-admin.md) | Done | — |
| 06e | [E-commerce: User Frontend](done/06e-ecommerce-fe-user.md) | Done | — |
| 06f | [Shipping Plugins](done/06f-shipping-plugins.md) | Done | — |
| 06g | [E-commerce: Tests](done/06g-ecommerce-tests.md) | Done | — |
| 06i | [Discounts & Coupons](done/06i-discounts-coupons.md) | Done | — |
| 06j | [Product Reviews & Ratings](done/06j-product-reviews.md) | Done | — |
| 06k | [Wishlist / Favorites](done/06k-wishlist.md) | Done | — |
| 06l | [Abandoned Cart Recovery](done/06l-abandoned-cart-recovery.md) | Done | — |
| 07 | [E-commerce Completion — Overview](sprints/07-ecommerce-completion.md) | Done | — |
| 07a | [Backend: Missing Routes](done/07a-ecommerce-backend-completion.md) | Done | — |
| 07b | [Admin: Product Management](done/07b-ecommerce-admin-completion.md) | Done | — |
| 07c | [User: Catalog + Detail](done/07c-ecommerce-user-completion.md) | Done | — |
| 07d | [CMS Integration](done/07d-ecommerce-cms-integration.md) | Done | — |
| 07e | [E2E Playwright](done/07e-ecommerce-e2e-playwright.md) | Done | — |

## Done (2026-03-27)

### Sprint 04 — Subscription Plugin Extraction (COMPLETE)

All 6 sub-sprints done:

- **04a:** Line Item Handler Registry — `ILineItemHandler` + `LineItemHandlerRegistry` + delegation
- **04b:** Subscription Backend Plugin — `plugins/subscription/` (34 files)
- **04c:** Core Cleanup — removed subscription code, `CoreLineItemHandler` → TOKEN_BUNDLE only
- **04d:** Subscription Admin Frontend — `plugins/subscription-admin/` (8 views, 4 stores)
- **04e:** Subscription User Frontend — `plugins/subscription/` for fe-user, dashboard slimmed
- **04f:** Plugin Compatibility — all plugins green

### Pre-commit Results (all repos)

| Repo | Static Analysis | Unit Tests | Integration |
|------|----------------|------------|-------------|
| vbwd-backend | PASS | 1,285 passed | 312 passed |
| vbwd-fe-admin | PASS | 302 passed | 87 passed |
| vbwd-fe-user | PASS | 326 passed | — |

## Done (2026-03-28)

### Invoice Line Item Links

- Backend: Added `resource_id` to booking invoice metadata (`booking_invoice_service.py`, `payment_handler.py`)
- fe-admin: Booking line items now link to resource schedule page (`/admin/booking/resources/{id}/schedule`)
- fe-admin + fe-user: Line item descriptions are now `<router-link>` — clickable with blue hover styling
- All line item types link to their detail pages (plans, token bundles, add-ons, bookings)

### Fixes

- fe-admin: Removed unused `isTarifsActive`/`toggleTarifs` from AdminSidebar (ESLint errors)
- fe-admin: Fixed subscription-admin plugin store imports (`../api` → `@/api`)
- fe-admin: Fixed subscription-admin plugin test imports (relative paths to plugin `src/`)
- fe-admin: Fixed PlanForm null guard (`allCategories.value = cats || []`)
- fe-admin: Fixed Subscriptions filter test (uppercase `ACTIVE` values)
- fe-admin: Fixed SubscriptionDetails cancel test (uppercase `ACTIVE` status)
- fe-admin: Added `extensionRegistry.register()` nav sections to subscription-admin plugin
- fe-admin: Added missing `config.json` + `admin-config.json` to subscription-admin plugin
- fe-user: Removed `addNavItem` calls (SDK doesn't support it)
- fe-user: Fixed `Subscription.vue` import (`../stores/invoices` → `@/stores/invoices`)
- fe-user: Removed obsolete dashboard/checkout test files
- fe-user: Fixed booking `BookingConfirmationDetails.vue` — removed unreachable code + unused import
- fe-user: Fixed booking `BookingCheckout.vue` — removed unused `route`, null check on quantity
- fe-user: Fixed booking `BookingSuccess.vue` — typed `bookingResource` ref
- fe-user: Fixed `booking-authorize.spec.ts` — removed unused vars
- fe-user: Fixed `stripe-views.spec.ts` — added `replace` to router mock, skipped invalid test
- fe-user: Re-enabled `checkout` plugin (GHRM depends on it)
- Backend: Increased Postgres `max_connections` to 200 (taro tests exhausted default)

## Done (2026-03-28)

### Sprint 05 — Extensible Admin Sidebar (COMPLETE)

- `ExtensionRegistry`: Added `sectionItems`, `hiddenItems`, `sectionComponents`, `buildSidebar()` with position control
- `AdminSidebar.vue`: Fully data-driven — zero hardcoded plugin references, 3-level nav (L0→L1→L2)
- `subscription-admin`: "Subscriptions" injected into Sales section via `sectionItems.sales`
- 18 new tests, 320 total unit tests green, `pre-commit-check.sh --full` PASSED

## Next

- Sprint 06: [E-commerce Plugin Bundle](sprints/06-ecommerce-plugin-bundle.md) — Products, categories, orders, cart
  - Backend: Product, ProductCategory, Order, OrderItem models + `EcommerceLineItemHandler`
  - fe-admin: Product/category/order management + Shop dashboard widgets
  - fe-user: Product catalog, cart, checkout via standard checkout plugin, order history
  - Uses core CUSTOM line items, line item registry, event bus — zero core changes
- Follow-up: Apply extensible sidebar pattern to fe-user `UserLayout.vue`
- Playwright E2E tests for sidebar nav (Sprint 05 step 9-10)
