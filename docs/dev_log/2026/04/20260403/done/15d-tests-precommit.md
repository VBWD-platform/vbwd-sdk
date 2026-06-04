# Sprint 15d — Tests + Pre-commit

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DRY · Clean Code · DevOps-first
**Parent:** [15 — Shipping & Discount Admin](15-shipping-discount-admin.md)

---

## Goal

All shipping, discount, and tax features tested end-to-end. All repos pass pre-commit. Playwright E2E proves the full flows.

---

## Playwright E2E Tests

### Shipping (fe-admin)

```
- test_shipping_methods_page_shows_registered_providers
    → login → Shop → Shipping → see "Pick-up at Store" + "Flat Rate" in list
- test_toggle_shipping_method
    → disable flat rate → status badge changes → re-enable → active again
- test_shipping_provider_config_link
    → click flat rate → opens plugin config page
```

### Discounts (fe-admin)

```
- test_create_percentage_discount
    → Promotions → Discounts → New → fill form (20%, GLOBAL, active) → save → visible in list
- test_create_fixed_amount_discount
    → New → FIXED_AMOUNT, €5, min order €25 → save → visible
- test_edit_discount
    → click discount → change value → save → updated
- test_delete_discount
    → select → delete → removed
- test_create_coupon_linked_to_discount
    → Coupons → New → manual code "TEST50" → link to discount → save
- test_auto_generate_coupon_code
    → New → click "Generate Code" → code auto-filled → save
- test_bulk_generate_coupons
    → Bulk Generate → select discount, count=5 → generate → 5 coupons in list
- test_coupon_usage_history
    → click coupon → Usage tab → see redemption records
- test_discount_scope_filtering
    → create ECOMMERCE-scoped discount → only visible when filtering by ECOMMERCE
```

### Tax (fe-admin)

```
- test_create_tax_rate_for_germany
    → Settings → Tax → New Rate → DE, 19%, standard → save → in list
- test_create_reduced_tax_class
    → New Class → "Reduced", 7% → save → in list
- test_edit_tax_rate
    → click → change to 20% → save → updated
- test_delete_tax_rate
    → select → delete → removed
```

### Checkout with Discount (fe-user)

```
- test_apply_coupon_at_checkout
    → add product to cart → checkout → enter "SUMMER2026" → discount shown → total reduced
- test_invalid_coupon_shows_error
    → checkout → enter "INVALID" → error "Coupon not found"
- test_discount_applied_to_invoice
    → complete checkout with coupon → invoice shows discount amount
```

---

## Unit Tests

### Backend
- Shipping method registry (register, list, toggle)
- Coupon bulk generate endpoint
- Tax rate CRUD routes

### Fe-admin
- Discounts list rendering
- DiscountForm type-dependent fields
- CouponForm auto-generate
- TaxRates list + form
- Discount admin sidebar nav visible with permission

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
