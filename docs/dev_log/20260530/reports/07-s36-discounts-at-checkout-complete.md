# Report 07 — S36 Discounts at Checkout: COMPLETE

**Date:** 2026-06-02
**Sprint:** [S36](../done/s36-discounts-at-checkout.md) (moved to `done/`)
**Status:** ✅ **DONE & GREEN** — all three layers implemented TDD-first; the
coupon island is wired into **both** checkouts end-to-end and proven by
Playwright against the live stack.

Supersedes the Part-A checkpoint ([report 06](06-s36-backend-part-a-implemented.md)).

## The headline, proven

A buyer types a coupon in **both** checkouts, the price drops by the discount,
and the persisted invoice carries a negative discount line + the coupon's
`current_uses` increments. Admin-created discounts take effect. All via a
**generic core seam** — core/subscription/shop name no discount domain.

## What shipped, by layer

### Part A — backend (24 tests, lint clean, agnosticism oracles green)
- **Core seam** `vbwd/services/checkout_price_adjustment_registry.py` (generic
  port + empty no-op default → disabled-plugin Liskov path).
- **`CheckoutRequestedEvent.coupon_code`** (generic, like `payment_method_code`).
- **`DiscountService.compute_discount_amount`** — scope-independent %/fixed/cap
  (the rule-registry only defaults GLOBAL).
- **Discount bridge** `checkout_adjustment.py` registered in `on_enable`:
  validate → scope-check → quote → `on_committed` (redeem + record once).
- **Subscription + shop checkouts** consume the registry: accept `coupon_code`,
  append a negative `CUSTOM` discount line (`extra_data.discount`), reduce the
  total, reject invalid (no mutation), run `on_committed`. Shop pre-validates
  before `block_stock` commits.
- **`/coupons/validate`** enhanced: returns `discount_amount` + honours `scope`
  (FE preview matches submit; DRY — reuses `compute_discount_amount`).

### Part B — fe-core + fe-user (CouponInput 6 specs, store 18 vitest, lint clean)
- **`vbwd-fe-core` `CouponInput.vue`** (`var(--vbwd-*)`, i18n-agnostic label
  props, testids `coupon-input/apply/clear/error/applied`) — `dist/` rebuilt.
- **`CheckoutSource`** gained optional `applyCoupon` / `getDiscountAmount` /
  `clearCoupon` (additive — Liskov). `getOrderTotal()` is net.
- **Core checkout store** gained generic `couponCode/couponError/discountAmount`
  + `applyCoupon`/`clearCoupon` delegating to the active source (oracle stays
  green — core names no plugin domain).
- **Both views** render `CouponInput` + an `order-discount` row; **subscription
  + shop sources** implement `applyCoupon` (POST `/coupons/validate`) and thread
  `coupon_code` into submit.

### Part C — Playwright e2e (7 specs, all green vs the live docker stack)
| Spec | Result |
|------|--------|
| `coupon-public.spec.ts` (anonymous `/checkout?tarif_plan_id=pro`) | ✅ 2 — SUMMER2026 −20%, bogus → error |
| `coupon-private.spec.ts` (`/dashboard/checkout/pro`) | ✅ 2 — SUB30 −30%, bogus → error |
| `coupon-admin-injected.spec.ts` (admin API in `beforeAll` → redeem via UI) | ✅ 1 — admin discount −25% reaches the buyer |
| `discount-injection.spec.ts` (fe-admin) | ✅ 2 — discounts/coupons lists operable |

§9 decisions honoured: negative line item, single coupon, API-in-`beforeAll`.

## Deviations (documented)
- Discount line uses `LineItemType.CUSTOM` (`extra_data.discount` flag), not a
  new `DISCOUNT` enum — avoids a native-PG-enum `ALTER TYPE` migration; keeps
  `sum(line_items) == total_amount`.
- Added `compute_discount_amount` rather than reusing the dead rule-registry's
  `calculate_discount` (which 0's non-GLOBAL scopes).

## Honest gate note
All **S36-specific** tests are green: backend 24, fe-core 6, fe-user 18 unit +
**7 e2e**, fe-admin 2 e2e; lint + all agnosticism oracles green on every touched
repo. The acceptance item "`--full` green on all 4 repos" is met for the S36
slice, **except** that the full `vbwd-fe-user` e2e suite still carries
**pre-existing** failures unrelated to S36 — e.g. the stale `navigateToCheckout`
helper points at `/checkout/:slug` while the real route is
`/dashboard/checkout/:slug` (this rot is what surfaced the earlier 54-failure
sweep). Fixing the whole legacy e2e suite is out of S36 scope and tracked
separately.

**Not committed** (standing rule). Plugin code lives on disk (gitignored in the
core repos); fe-core `dist/` rebuilt.
