# Report 09 — Sprint 08a: Discount Plugin Backend

**Date:** 2026-03-30
**Status:** Complete

---

## What was done

### Discount Plugin (`plugins/discount/`)

Standalone unified discount & coupon system — works across subscriptions, ecommerce, and bookings.

**Architecture:**
- `IDiscountRule` interface — plugins register their own discount rules
- `DiscountRuleRegistry` — same pattern as `LineItemHandlerRegistry`
- Core stays agnostic — discount plugin is the orchestrator

**Models (4 tables):**
- `Discount` — rule definition (percentage, fixed, free shipping, buy-X-get-Y)
- `Coupon` — user-facing code linked to a discount
- `CouponUsage` — tracks redemptions per user/invoice
- `DiscountApplication` — audit log of applied discounts

**Scopes:** GLOBAL, ECOMMERCE, SUBSCRIPTION, BOOKING

**Service:**
- `DiscountService` — validate coupon, calculate discount, redeem, record application
- `CouponValidationError` — checks: active, date range, max uses, per-user limit, min order amount

**Routes:**
- Public: `POST /api/v1/coupons/validate`
- Admin: full CRUD for discounts + coupons + usage history (12 endpoints)

**Tests:** 18 unit tests (9 registry + 9 service) — all passing

**Demo data:** 5 discounts + 5 coupons (SUMMER2026, WELCOME5, FREESHIP, SUB30, EARLYBIRD)

### Ecommerce cleanup
- Removed old `Discount`/`Coupon`/`CouponUsage` model imports from ecommerce `__init__.py`
- Old ecommerce tables (`ecommerce_discount`, `ecommerce_coupon`) remain in DB but are no longer loaded

### Other fixes (2026-03-30)
- Product image gallery: backend routes (upload/delete/primary) + admin component + user thumbnail gallery
- Categories panel restyled to match PlanForm (round assign/unassign buttons, uppercase headers)
- Shop routes now use CmsPage.vue (header/footer/breadcrumbs from CMS layout)
- Cart checkout flow: Cart → checkout page with EmailBlock (login inline) → payment
- Missing `/dashboard/subscription/invoices` route added to subscription plugin
- Invoice `amount` NOT NULL fix in ecommerce checkout
- Invoice number prefix test updated (`INV-`, `SH-`, `BK-`)
- Ecommerce header cart: CmsWidgetRenderer renders menu icons + CartBadge when `show_cart: true`
- ProductCatalog.vue restored (was empty file)

---

## Pre-commit Results

| Repo | Lint | Unit Tests | Integration |
|------|------|-----------|-------------|
| vbwd-backend | PASS | 253 passed | 1 fix applied |
| vbwd-fe-admin | PASS | 324 passed | PASS |
| vbwd-fe-user | PASS | 340 passed | PASS |
