# S36 — Discounts & coupons at checkout (wire the island into both checkouts)

**Status:** ✅ **DONE & GREEN — 2026-06-02.** All three parts implemented
TDD-first; coupon island wired into both checkouts, proven by 7 Playwright specs
vs the live stack ([report 07](../reports/07-s36-discounts-at-checkout-complete.md)).
Backend 24 tests · fe-core 6 · fe-user 18 unit + 7 e2e · fe-admin 2 e2e · lint +
agnosticism oracles green. §9 decisions honoured.
**Repos:** `vbwd-backend` (core seam + `plugins/discount` + `plugins/subscription` + `plugins/shop`),
`vbwd-fe-core` (reusable coupon input), `vbwd-fe-user` (public + private checkout wiring + e2e),
`vbwd-fe-admin` (e2e only — admin CRUD already ships).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY ·
Liskov · clean code · NO OVERENGINEERING —
[`_engineering_requirements.md`](_engineering_requirements.md). Core stays
**agnostic** (the discount plugin is gnostic; core/subscription/shop must not
`import` the discount plugin — they reach it only through a generic port).
Gate: `bin/pre-commit-check.sh --full` green on **every** touched repo +
the new Playwright specs green against the docker stack.

---

## 0. Readiness (re-verified 2026-06-01)

Every grounded claim in §2 was re-checked against the current tree and **still
holds** — the consumer checkout path is still unwired. Confirmed present:

- `DiscountService.{validate_coupon,calculate_discount,redeem_coupon,record_application}`
  and `POST /api/v1/coupons/validate` exist; that endpoint is still the **only**
  caller of the discount math.
- `subscription/.../routes/user_checkout.py` and `shop/shop/routes.py` still
  accept **no** `coupon_code` (grep clean).
- Core registries to mirror exist (`vbwd/events/line_item_registry.py`,
  `vbwd/services/deletion_dependency_registry.py`); the planned
  `checkout_price_adjustment_registry.py` does **not** exist yet.
- fe-user `CheckoutSource` has `getOrderTotal()` only — no `applyCoupon`; neither
  checkout view renders a coupon field; `vbwd-fe-core/src/components/CouponInput.vue`
  does not exist; fe-admin `discount-admin/` ships CRUD but has **no** `tests/e2e/`.
- `populate_db.py` seeds `SUMMER2026 / WELCOME5 / FREESHIP / SUB30 / EARLYBIRD`.
- `DiscountScope` = `GLOBAL / ECOMMERCE / SUBSCRIPTION`; `DiscountRule.stackable`
  exists.

**⚠ S43 naming drift (since this doc was written):** Sprint 43 renamed the
discount tables/classes. The model is now **`DiscountRule`** (table
**`discount_rule`**), `Coupon` → table **`discount_coupon`**, `CouponUsage` →
**`discount_coupon_usage`** (`discount_application` unchanged). All code paths in
§2/§7 are still valid (files unchanged: `discount/models/discount.py` etc.); only
the **class name** `Discount` → `DiscountRule` and the table names changed. New
code + tests must use `DiscountRule` / the `discount_*` table names.

**Verdict:** the plan is sound, current, and architecturally consistent (the
adjustment-registry seam mirrors two existing core registries and keeps core
agnostic). The three §9 decisions are **LOCKED** (2026-06-01) to the recommended
defaults — **no remaining blockers.** Ready to implement TDD-first, RED on every
layer, starting with Part A (the core `checkout_price_adjustment_registry` + the
discount plugin's adjustment registration).

---

## 1. Goal

A buyer can type a coupon code in **both** checkouts — the **public**
(anonymous) checkout and the **private** (authenticated subscription) checkout
— have the code validated, see the price drop by the discount, and pay the
reduced amount. The persisted invoice carries a discount line item and the
coupon's usage counter is incremented. Admin-created discounts/coupons are the
ones that take effect.

Concretely, this sprint must end with these provable facts:
- The coupon input is **visible** in the public checkout and the private checkout.
- Entering a seeded code (`SUMMER2026`, `WELCOME5`, `SUB30`, …) **reduces the
  displayed total** and the **charged amount**.
- `populate_db.py` **seeds discounts + coupons on install** (proven by an
  integration assertion + an e2e that uses a seeded code with no manual setup).
- An admin's discount/coupon **injection is visible and operable** end-to-end:
  a Playwright spec creates a discount + coupon in fe-admin, then a second spec
  redeems that exact code in the fe-user checkout and sees the price drop.

## 2. What is broken, and why (grounded diagnosis)

The discount feature is **half-built**: the backend `discount` plugin and the
fe-admin `discount-admin` plugin are complete, but the **consumer checkout path
was never wired**. The gap is in three layers.

### 2a. Backend — the discount plugin is a standalone island
- The plugin is real and enabled: models / repos / service / routes at
  `vbwd-backend/plugins/discount/discount/{models,repositories,services,routes.py}`;
  enabled in `vbwd-backend/plugins/plugins.json` (`"discount": {"enabled": true}`).
- `DiscountService` (`…/services/discount_service.py`) has `validate_coupon`,
  `calculate_discount`, `redeem_coupon`, `record_application` — all correct.
- **But the only caller** of any of them is the plugin's own public endpoint
  `POST /api/v1/coupons/validate` (`…/discount/routes.py:61`), which is
  **read-only validation**. A grep for `validate_coupon` / `calculate_discount`
  / `redeem_coupon` / `record_application` across the whole backend returns
  hits only inside the discount plugin itself.
- **Neither checkout endpoint accepts or applies a coupon:**
  - `POST /api/v1/user/checkout` —
    `plugins/subscription/subscription/routes/user_checkout.py:18` — accepts
    `plan_id`, `token_bundle_ids`, `add_on_ids`, `currency`,
    `payment_method_code`. No `coupon_code`. The checkout handler
    (`…/subscription/handlers/checkout_handler.py:55-221`) sums line items into
    `invoice.amount = subtotal = total_amount` with **no reduction**.
  - `POST /api/v1/shop/cart/checkout` — `plugins/shop/shop/routes.py:786-896`
    — same story; `total_price = unit_price * quantity`, no discount.
- `IDiscountRule` + `DiscountRuleRegistry` (`…/discount/interfaces.py:44`,
  `…/discount/registry.py`) exist but **no plugin registers a rule** and
  **no checkout consumes the registry** → the registry is empty and dead.
- **Net:** even if the frontend posted a `coupon_code`, the backend would
  ignore it. The price is never reduced anywhere.

### 2b. fe-user — no coupon input exists in either checkout
- Public checkout `vbwd-fe-user/plugins/checkout/PublicCheckoutView.vue` and
  private checkout
  `vbwd-fe-user/plugins/subscription/subscription/views/Checkout.vue` render
  email / order-summary / billing / payment / terms — **no coupon field**.
- A repo-wide search for `discount|coupon|promo|voucher` in `vbwd-fe-user`
  finds only the unrelated `conekta-payment/ConektaVoucherView.vue`.
- Totals are plain sums with **no discount term**:
  - core store `vue/src/stores/checkout.ts:39` —
    `orderTotal = activeSource.getOrderTotal()`.
  - subscription source
    `plugins/subscription/subscription/stores/checkout.ts:150-155` — plan +
    bundles + add-ons.
  - shop source `plugins/shop/shop/checkoutSource.ts:41` →
    `useCartStore().subtotal` (`plugins/shop/shop/stores/cart.ts:43-45`).
- The submit payloads carry **no coupon field**
  (`subscription/stores/checkout.ts:323-336` → `POST /user/checkout`;
  `shop/checkoutSource.ts:45-56` → `POST /shop/cart/checkout`).
- The `CheckoutSource` contract
  (`vue/src/registries/checkoutSourceRegistry.ts:66-85`) has **no concept of a
  discount** — so there is nowhere to thread one even if a field existed.

### 2c. fe-admin — fully built, just unverified by e2e
- `vbwd-fe-admin/plugins/discount-admin/` has Discounts/Coupons list + form +
  bulk-generate + usage views, store, routes under `/admin/promotions/*`,
  permission-gated. **No e2e coverage** exists for it.

**Root cause in one line:** the discount plugin and its admin UI were shipped,
but the *checkout consumer path* (UI input → validate → reduce price → persist
discount line + redeem coupon) was never built. "The discount input is not
shown in the checkouts" because it does not exist — and the backend would
ignore it if it did.

## 3. Design

Three parts, each respecting core-agnosticism (OCP/DIP via a generic seam,
never a core→plugin or cross-plugin import). The discount plugin remains the
**only** place that knows discount math.

### Part A — Backend: apply the coupon during checkout via a generic core seam

The problem: subscription-checkout and shop-checkout live in *their own*
plugins and must reduce the price using the *discount* plugin's math — without
any of them importing each other. Solution mirrors the existing
`vbwd/events/line_item_registry.py` and `vbwd/services/deletion_dependency_registry.py`
core registries.

1. **New core port + registry** (generic, no "discount" domain knowledge):
   `vbwd-backend/vbwd/services/checkout_price_adjustment_registry.py`.
   ```python
   class CheckoutPriceAdjustment(Protocol):
       def apply(self, *, code: str, subtotal: Decimal, user_id: str | None,
                 scope: str, currency: str) -> PriceAdjustmentResult: ...
   ```
   `PriceAdjustmentResult` = `{ valid, discount_amount, label, error,
   on_committed: callable }`. Default registry is **empty** → callers get a
   no-op (zero adjustment, `valid=True` when no code given). This is the Liskov
   null-default: checkout with the discount plugin **disabled** behaves exactly
   as today.
2. **Discount plugin registers** one adjustment in its `on_enable`
   (`plugins/discount/__init__.py`) that wraps
   `DiscountService.validate_coupon` + `calculate_discount`, and returns an
   `on_committed` closure that calls `redeem_coupon` + `record_application`
   only after the invoice is actually created/paid. No core/other-plugin import
   needed in either direction — both sides depend on the core port (DIP).
3. **Both checkout handlers consume the registry** (their own plugin code, not
   core):
   - subscription `checkout_handler.py` — accept `coupon_code` (threaded from
     `user_checkout.py` request → `CheckoutRequestedEvent`), call the registry
     after summing line items, and if `discount_amount > 0` append a
     **negative-priced `DISCOUNT` line item** and reduce
     `invoice.total_amount`. Run `on_committed` after the invoice persists.
   - shop `routes.py` checkout — same: accept `coupon_code`, adjust, add the
     discount line, reduce totals.
4. **Coupon scope** maps to the checkout: subscription checkout passes
   `scope="SUBSCRIPTION"`, shop passes `scope="ECOMMERCE"`; `GLOBAL` discounts
   apply to both (`DiscountScope` already models this).
5. **NO OVERENGINEERING:** we do *not* build out the `IDiscountRule` registry
   path (it is dead and unused) — the adjustment seam is the single narrow hook
   today's two checkouts need. We do not add a `DISCOUNT` everywhere; only the
   two checkout writers create the line. The validate endpoint stays as-is.

> **Open decision for the user (§7):** persist the discount as a **negative
> line item** (recommended — keeps `sum(line_items) == total_amount`, audit-
> friendly, the FE already renders line items) vs. a separate
> `invoice.discount_total` column (schema change, more invasive). The sprint
> assumes the negative line item.

### Part B — fe-core + fe-user: one reusable coupon input, both checkouts

Keep the core checkout store agnostic — "coupon code" and "discount amount"
are generic checkout concepts (like payment method), so core may own the
*state*; the *validation call* is delegated to the active `CheckoutSource`.

1. **fe-core** — new reusable `CouponInput.vue` design-system component
   (`var(--vbwd-*)` tokens, mobile-ready) with `data-testid` hooks:
   `coupon-input`, `coupon-apply`, `coupon-clear`, `coupon-error`,
   `coupon-applied`. Emits `apply(code)` / `clear()`. Lives in fe-core because
   both fe-user checkouts (and later fe-admin previews) consume it.
2. **`CheckoutSource` contract** gains optional methods (additive — Liskov:
   sources that don't implement them behave as today):
   ```ts
   applyCoupon?(code: string): Promise<{ valid: boolean; discountAmount: number; error?: string }>;
   getDiscountAmount?(): number;   // 0 when none
   clearCoupon?(): void;
   ```
   `getOrderTotal()` returns the **net** total (source subtracts its own
   discount). Core store adds generic `couponCode` / `couponError` /
   `discountAmount` state + `applyCoupon()` / `clearCoupon()` actions that
   delegate to `activeSource`.
3. **Both checkout views render `CouponInput`** in the order-summary block —
   `PublicCheckoutView.vue` and subscription `Checkout.vue` — plus a discount
   row in the summary (`data-testid="order-discount"`) shown when
   `discountAmount > 0`, and `order-total` reflects the net.
4. **Subscription + shop `CheckoutSource`s implement** `applyCoupon` by POSTing
   to `/api/v1/coupons/validate` (`{ code, cart_total }`), storing the returned
   discount, and including `coupon_code` in their submit payload
   (`/user/checkout`, `/shop/cart/checkout`).
5. Stale-module gotcha: after editing fe-user plugin/fe-core, rebuild fe-core
   `dist/` and `docker compose restart dev` before e2e
   ([[project_fe_user_two_fe_core_checkouts]]).

### Part C — fe-admin: no code change, add e2e

The admin CRUD already works (`plugins/discount-admin/`). This sprint only adds
the Playwright spec proving an admin injection is visible and operable, and
that it flows through to the user checkout (the cross-app requirement in §5.3).

## 4. TDD plan (RED first, every layer)

**Backend (`vbwd-backend`)**
- `plugins/discount/tests/unit/test_checkout_price_adjustment.py` — the
  registered adjustment: valid code → correct `discount_amount`; unknown/expired
  → `valid=False`, zero; `on_committed` calls `redeem_coupon` +
  `record_application` exactly once.
- `vbwd/tests/unit/services/test_checkout_price_adjustment_registry.py` — empty
  registry returns a zero/no-op result (disabled-plugin Liskov path).
- `plugins/subscription/tests/integration/test_checkout_with_coupon.py` —
  `POST /user/checkout` with `coupon_code=SUB30` → invoice has a negative
  `DISCOUNT` line, `total_amount` reduced 30%, coupon `current_uses` incremented.
- `plugins/shop/tests/integration/test_shop_checkout_with_coupon.py` —
  `POST /shop/cart/checkout` with `coupon_code=WELCOME5` (min-order met) → €5 off.
- Negative paths: invalid code → 4xx with clear error, **no** invoice mutation,
  **no** redemption; min-order-not-met → rejected.

**fe-core / fe-user (Vitest)**
- `vbwd-fe-core` unit: `CouponInput.spec.ts` — emits `apply`, shows error,
  shows applied state.
- `vbwd-fe-user` unit: core checkout store `applyCoupon` delegates to active
  source and exposes `discountAmount`; subscription + shop source `applyCoupon`
  posts to `/coupons/validate` and threads `coupon_code` into submit.
- Agnosticism oracle stays green: core store names no plugin domain.

**Seeder (Part of §6)**
- `plugins/discount/tests/integration/test_populate_db_seeds.py` — run
  `populate(app)` against a clean test DB → 5 discounts + 5 coupons exist
  (`SUMMER2026`, `WELCOME5`, `FREESHIP`, `SUB30`, `EARLYBIRD`); idempotent on
  second run (no duplicates). Seeding goes **through the service/repo layer**,
  never raw SQL ([[feedback_no_direct_db_for_test_data]]).

## 5. Playwright e2e (the headline deliverable)

Run against the docker stack (`E2E_BASE_URL=http://localhost:8080` for fe-user,
`:8081` for fe-admin). Seeded codes are available with **zero manual setup** —
that is itself the seeder proof (§6). Credentials: `test@example.com /
TestPass123@`, `admin@example.com / AdminPass123@`.

### 5.1 Public checkout — `vbwd-fe-user/vue/tests/e2e/checkout/coupon-public.spec.ts`
- Land on the public (anonymous) checkout for a plan.
- Assert `coupon-input` is **visible** (regression guard for §2b).
- Capture `order-total`; type a seeded `SUMMER2026`; click `coupon-apply`.
- Assert `order-discount` appears and `order-total` **dropped by 20%**.
- Type a bogus code → assert `coupon-error` shown, total unchanged.
- Clear → total returns to original.
- (Optional, env-gated) confirm checkout → success state shows the discounted
  amount.

### 5.2 Private checkout — `vbwd-fe-user/vue/tests/e2e/checkout/coupon-private.spec.ts`
- `loginAsTestUser`, navigate to the authenticated subscription checkout.
- Same assertions with `SUB30` (subscription-scope) → total drops 30%.
- Assert a global code also applies; assert a shop-only code is rejected for a
  subscription (scope correctness).

### 5.3 Admin injection is visible & operable — **new binding requirement**
Two specs proving the admin-created discount reaches the buyer:
- `vbwd-fe-admin/plugins/discount-admin/tests/e2e/discount-injection.spec.ts` —
  `loginAsAdmin`; navigate **by URL** (`navigateViaNavbar` is broken —
  [[project_fe_admin_navbar_e2e_helper_rot]]) to
  `/admin/promotions/discounts/new`; create a percentage discount; create a
  coupon (deterministic code, e.g. `E2ETEST25`) bound to it at
  `/admin/promotions/coupons/new`; assert it appears in the list and its detail
  view is operable (edit, view usage = 0). Seed both admin localStorage keys
  `admin_token` + `admin_token_user` ([[project_fe_admin_e2e_auth_harness]]).
- `vbwd-fe-user/vue/tests/e2e/checkout/coupon-admin-injected.spec.ts` — in the
  user checkout, apply `E2ETEST25` → total drops by the admin-set percent.
  (If cross-app sequencing in CI is awkward, this spec creates the coupon via a
  direct authenticated `POST /api/v1/admin/discounts` + `/admin/coupons` API
  call in its `beforeAll`, asserting the admin **API** injection path, then
  redeems via UI. Document whichever sequencing CI uses — no silent skips.)

## 6. Seeder proof — discounts ARE seeded on install

- `plugins/discount/populate_db.py` already seeds 5 discounts + 5 coupons
  (`SUMMER2026 / WELCOME5 / FREESHIP / SUB30 / EARLYBIRD`) idempotently.
- **Prove it three ways:**
  1. Integration test in §4 asserting the rows after `populate(app)`.
  2. The e2e specs (§5.1/§5.2) use seeded codes with no manual creation — if
     seeding were missing, they fail.
  3. Confirm the installer runs it: `recipes/dev-install-ce.sh` /
     `dev-install-taro.sh` invoke each plugin's `populate_db.py` inside the api
     container (verify the discount plugin is included; if the loop is
     plugin-discovery based, assert `discount` is discovered). Capture the
     install-time log line in the report.

## 7. Files

| Action | Path |
| --- | --- |
| new  | `vbwd-backend/vbwd/services/checkout_price_adjustment_registry.py` (generic port + empty default) |
| new  | `vbwd-backend/vbwd/tests/unit/services/test_checkout_price_adjustment_registry.py` |
| edit | `vbwd-backend/plugins/discount/__init__.py` — register the adjustment in `on_enable` |
| new  | `vbwd-backend/plugins/discount/tests/unit/test_checkout_price_adjustment.py` |
| new  | `vbwd-backend/plugins/discount/tests/integration/test_populate_db_seeds.py` |
| edit | `vbwd-backend/plugins/subscription/subscription/routes/user_checkout.py` — accept `coupon_code` |
| edit | `vbwd-backend/plugins/subscription/subscription/handlers/checkout_handler.py` — adjust + discount line + commit hook |
| new  | `vbwd-backend/plugins/subscription/tests/integration/test_checkout_with_coupon.py` |
| edit | `vbwd-backend/plugins/shop/shop/routes.py` — accept `coupon_code`, adjust, discount line |
| new  | `vbwd-backend/plugins/shop/tests/integration/test_shop_checkout_with_coupon.py` |
| new  | `vbwd-fe-core/src/components/CouponInput.vue` (+ unit spec + rebuild `dist/`) |
| edit | `vbwd-fe-user/vue/src/registries/checkoutSourceRegistry.ts` — optional discount methods |
| edit | `vbwd-fe-user/vue/src/stores/checkout.ts` — generic coupon state + actions |
| edit | `vbwd-fe-user/plugins/checkout/PublicCheckoutView.vue` — render `CouponInput` + discount row |
| edit | `vbwd-fe-user/plugins/subscription/subscription/views/Checkout.vue` — same |
| edit | `vbwd-fe-user/plugins/subscription/subscription/stores/checkout.ts` — `applyCoupon` + payload |
| edit | `vbwd-fe-user/plugins/shop/shop/checkoutSource.ts` — `applyCoupon` + payload |
| new  | `vbwd-fe-user/vue/tests/e2e/checkout/coupon-public.spec.ts` |
| new  | `vbwd-fe-user/vue/tests/e2e/checkout/coupon-private.spec.ts` |
| new  | `vbwd-fe-user/vue/tests/e2e/checkout/coupon-admin-injected.spec.ts` |
| new  | `vbwd-fe-admin/plugins/discount-admin/tests/e2e/discount-injection.spec.ts` |

## 8. Acceptance (done = all of)

- Public **and** private checkout show a working coupon input that reduces the
  total when a seeded/admin-created code is applied (and rejects bad codes).
- The persisted invoice reflects the discount (negative `DISCOUNT` line, reduced
  `total_amount`) and the coupon's `current_uses` increments exactly once.
- `populate_db.py` seeds discounts+coupons on install — proven by the
  integration test, the e2e specs that rely on seeded codes, and the captured
  installer log.
- The admin-injection e2e proves an admin-created discount is visible/operable
  in fe-admin **and** takes effect in the fe-user checkout.
- Core stays agnostic — all three agnosticism oracles green; no core→plugin or
  undeclared cross-plugin import (subscription/shop reach discount only via the
  core port).
- `bin/pre-commit-check.sh --full` green on `vbwd-backend`, `vbwd-fe-core`,
  `vbwd-fe-user`, `vbwd-fe-admin`; all new Playwright specs green against docker.
- No `# noqa` / `# type: ignore` without prior approval
  ([[feedback_no_noqa_without_permission]]); no commits unless instructed
  ([[feedback_no_commit_without_ask]]).

## 9. Decisions — LOCKED 2026-06-01

All three resolved to the recommended defaults; the sprint is fully unblocked.

1. **Discount persistence shape** → ✅ **Negative `DISCOUNT` line item.** No
   schema migration; `sum(line_items) == total_amount` preserved; both checkout
   writers append the negative line.
2. **Stacking** → ✅ **Single coupon per checkout (v1).** One `coupon_code`
   field; `DiscountRule.stackable` is NOT honoured this sprint (deferred).
3. **Admin-injection e2e sequencing** → ✅ **Create via authenticated admin API
   in `beforeAll`, redeem via UI** (CI-robust), PLUS a separate fe-admin spec
   proving the admin-UI CRUD is visible/operable (§5.3). No full UI cross-app
   sequencing.