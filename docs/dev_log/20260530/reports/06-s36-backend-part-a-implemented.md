# Report 06 — S36 Discounts at Checkout: Part A (backend) IMPLEMENTED

**Date:** 2026-06-02
**Sprint:** [S36](../sprints/s36-discounts-at-checkout.md)
**Status:** 🟡 **Part A (backend) DONE & GREEN.** Part B (fe-core/fe-user) and
Part C (Playwright e2e) **not yet started.** Ticket remains open.

Implemented TDD-first against the §9-locked decisions (negative DISCOUNT line,
single coupon, API-in-beforeAll e2e). **24 new backend tests pass; black +
flake8 clean; all three core-agnosticism oracles green.**

## What landed (Part A)

| Layer | File | Note |
|-------|------|------|
| Core seam | `vbwd/services/checkout_price_adjustment_registry.py` | Generic port + empty no-op default (Liskov). Core names **no** discount domain. |
| Core event | `vbwd/events/checkout_events.py` | `CheckoutRequestedEvent.coupon_code` (generic, like `payment_method_code`). |
| Discount math | `plugins/discount/discount/services/discount_service.py` | New `compute_discount_amount` — scope-independent %/fixed/cap (the rule-registry only defaults GLOBAL, so SUB30 would be 0). |
| Discount bridge | `plugins/discount/discount/checkout_adjustment.py` | Implements the core port: validate → scope-check → quote → `on_committed` (redeem + record once). Registered in `__init__.py` `on_enable`, unregistered in `on_disable`. |
| Subscription consumer | `subscription/routes/user_checkout.py` + `handlers/checkout_handler.py` | Accept `coupon_code`; apply adjustment after summing line items; append negative `CUSTOM` discount line (`extra_data.discount`); reduce total; reject invalid (no mutation); run `on_committed`. |
| Shop consumer | `shop/shop/routes.py` | Same, ECOMMERCE scope. **Pre-validates the coupon before block_stock** (block_stock commits mid-flow, so a late rollback can't undo a rejected checkout). |

### Tests (24, all green)
- `tests/unit/services/test_checkout_price_adjustment_registry.py` (5) — empty/no-op, invoke, invalid, unregister.
- `plugins/discount/tests/unit/test_compute_discount_amount.py` (8) — %/fixed/cap/free-shipping/subtotal-clamp.
- `plugins/discount/tests/integration/test_checkout_price_adjustment.py` (5) — valid/global/scope-mismatch/unknown/`on_committed` redeems+records once.
- `plugins/subscription/tests/integration/test_checkout_with_coupon.py` (2) — SUB30 → invoice 70.00 + negative line + `current_uses==1`; invalid → 400, no invoice.
- `plugins/shop/tests/integration/test_shop_checkout_with_coupon.py` (2) — WELCOME5 €5 off (min-order met) + redeemed; below-min → 400, no invoice.
- `plugins/discount/tests/integration/test_populate_db_seeds.py` (2) — 5 discounts + 5 coupons seeded; idempotent.

### Design notes / deviations (vs the sprint doc)
- **Discount line type:** used the existing `LineItemType.CUSTOM` (flagged via
  `extra_data.discount`) instead of adding a `DISCOUNT` enum value, which on a
  native PG enum would need an `ALTER TYPE` migration. Keeps
  `sum(line_items) == total_amount`, no schema change (NO-OVERENGINEERING).
- **`compute_discount_amount`** added rather than reusing the rule-registry's
  `calculate_discount` (which returns 0 for non-GLOBAL scopes with the empty
  registry — the doc's design would silently 0-out SUB30). The dead
  `IDiscountRule` registry is left untouched per the doc.
- **`on_committed`** runs at invoice creation (after persist), redeeming the
  coupon once. (Redeem-at-payment was considered; creation-time matches the
  acceptance "current_uses increments once" and the e2e.)

## Remaining (NOT done)

- **Part B — fe-core + fe-user:** `CouponInput.vue` (+ spec), `CheckoutSource`
  optional discount methods, core checkout-store coupon state/actions, both
  checkout views render the input + discount row, subscription + shop sources
  `applyCoupon` + payload, Vitest. Requires fe-core `dist/` rebuild + dev
  restart (stale-bundle gotcha).
- **Part C — Playwright e2e:** `coupon-public`, `coupon-private`,
  `coupon-admin-injected` (API-in-`beforeAll`), fe-admin `discount-injection`.
- **Gate:** `bin/pre-commit-check.sh --full` green on `vbwd-fe-core`,
  `vbwd-fe-user`, `vbwd-fe-admin` (backend Part-A slice is green).

**Not committed** (standing rule).
