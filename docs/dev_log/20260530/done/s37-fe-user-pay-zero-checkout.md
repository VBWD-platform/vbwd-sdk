# S37 — fe-user "Pay Zero" checkout (port the iOS zero-cost flow to web, both checkouts)

**Status:** ✅ DONE & GREEN — 2026-06-02 ([report 09](../reports/09-pay-zero-ghrm-and-booking.md)).
A €0 checkout completes with no payment step (invoice marked PAID, entitlement
created) for both free GHRM packages and free bookings — live-verified on
`localhost:8080`. Booking additionally got a backend zero-total auto-pay path via
the shared `emit_payment_captured` seam (the only backend change; subscription was
already auto-paying). Tests: backend booking integration guard + fe-user unit
suite 673 passed; ESLint clean.
**Repos:** `vbwd-fe-core` (shared zero-total notice + label) · `vbwd-fe-user`
(core checkout store + both checkout views + e2e) · `vbwd-backend`
(`plugins/booking` only). **As-built backend note:** subscription needed no
backend change (it already auto-pays a zero-total checkout — see §2c), but
**booking had no zero-total path** and gained one in `plugins/booking/booking/
routes.py` via the shared `emit_payment_captured` seam (no new core coupling).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · NO OVERENGINEERING —
[`_engineering_requirements.md`](_engineering_requirements.md). Core stays
**agnostic** — "zero total" is a generic checkout concept (like `orderTotal`
and `paymentMethodCode`), so the single source of truth lives in the core
checkout store, not in any plugin. Gate: `bin/pre-commit-check.sh --full` green
on `vbwd-fe-core` + `vbwd-fe-user` + new Playwright specs green against docker.

**Related:** [S36](s36-discounts-at-checkout.md) — once discounts land, a 100%
coupon can drive `orderTotal` to 0, so the same "Pay Zero" path must cover the
discounted-to-zero case, not just an intrinsically free plan.

---

## 1. Goal

When a checkout's total is **0** (a free plan, or a paid plan discounted to
zero), the fe-user web checkout behaves exactly like the iOS app: it does **not**
ask for a payment method, shows a "Pay Zero" notice, the confirm button reads
**"Pay Zero"**, and submitting activates the subscription immediately. This must
work **identically** on the **public** (anonymous) checkout and the **private**
(authenticated subscription) checkout — driven by one shared rule, not two
copies.

## 2. Reference behaviour & current state (grounded)

### 2a. iOS — the contract to replicate
- `vbwd-ios/.../vbwd-ios-core/Sources/VBWDCore/UI/Checkout/CheckoutViewModel.swift:121`
  — `public var isZeroTotal: Bool { orderTotal <= 0 }`.
- Lines 134-140 — when zero-total, payment methods are filtered to only
  `invoice` and that one is auto-selected (so a code is still sent).
- `CheckoutView.swift:66-76` — payment-method section is **hidden** when
  `isZeroTotal`; a notice is shown instead.
- `CheckoutView.swift:197-215` — `zeroTotalNotice`: *"Please finish subscription
  by the button Pay Zero"*.
- `CheckoutView.swift:244-248` — button label flips from `"Pay <cur> <amt>"` to
  **`"Pay Zero"`**.
- Same endpoint, same payload (`SubscriptionCheckoutSource.swift:84-86` →
  `POST /user/checkout`).

### 2b. fe-user — no zero branch exists today
- `orderTotal` single source of truth: core store
  `vbwd-fe-user/vue/src/stores/checkout.ts:39` —
  `orderTotal = activeSource.getOrderTotal() ?? 0`.
- **Both** checkouts unconditionally require a selected payment method:
  - public `plugins/checkout/PublicCheckoutView.vue` — `canCheckout` (~line 209)
    AND-s in `selectedPaymentMethod.value`; `PaymentMethodsBlock` always rendered
    (~lines 88-94); button label always `checkout.payButton` (~line 130).
  - private `plugins/subscription/subscription/views/Checkout.vue` — identical
    `canCheckout` (~line 395), always-rendered `PaymentMethodsBlock` (~line 190),
    `checkout.payButton` label (~line 292).
- The submit payload **already** sends `payment_method_code` only when set
  (`subscription/.../stores/checkout.ts:332-334`; `shop/.../checkoutSource.ts:52-54`)
  — so omitting it for a zero-total order is already wire-safe.
- No `is_free` / tier concept on `Plan` (`subscription/.../stores/plans.ts:4-20`)
  — a free plan is simply `display_price === 0`.

### 2c. Backend — already handles zero-total (no change needed)
- `plugins/subscription/subscription/handlers/checkout_handler.py:250-270` —
  when `total_amount == Decimal("0.00")` it emits `PaymentCapturedEvent`
  (`payment_reference="zero-price"`), the invoice is marked PAID by
  `vbwd/handlers/payment_handler.py:42-52`, line items activate via the
  registry, and the response message is *"Checkout complete. Free plan
  activated."* The endpoint accepts the request whether or not
  `payment_method_code` is present.

**Net:** the only missing piece is the **fe-user UI/flow branch**. This sprint
adds it, shared across both checkouts, with zero backend work.

## 3. Design (narrowest change, DRY across both views)

One rule, owned by the core store; one shared notice component in fe-core; two
thin view edits that consume both.

1. **Core store — single source of truth** (`vue/src/stores/checkout.ts`):
   add a computed `isZeroTotal = orderTotal <= 0` (mirrors iOS
   `CheckoutViewModel.isZeroTotal`) and export it. Generic — names no plugin
   domain. Both views read `checkoutStore.isZeroTotal`; neither re-derives it.
2. **fe-core — shared `ZeroTotalNotice.vue`** design-system component
   (`var(--vbwd-*)`, mobile-ready) with `data-testid="zero-total-notice"` and
   an i18n string (`checkout.zeroTotalNotice`). Lives in fe-core so both
   fe-user checkouts render the same notice (DRY). Also add the i18n key
   `checkout.payZeroButton` ("Pay Zero").
3. **Both checkout views**, identical edits:
   - **Hide** `PaymentMethodsBlock` when `isZeroTotal` (`v-if="!checkoutStore.isZeroTotal"`).
   - **Relax** `canCheckout`: payment method required **only** when
     `!isZeroTotal`. All other requirements (auth, billing address, terms) stay.
   - **Render** `<ZeroTotalNotice>` where the payment block would be.
   - **Button label**: `isZeroTotal ? $t('checkout.payZeroButton') : <existing Pay {amount}>`.
   - Requirements list (`data-testid="checkout-requirements"`) must **not** list
     "payment method" when `isZeroTotal`.
4. **Submit payload for zero-total** — match iOS for safety: if an `invoice`
   payment method is available, auto-select/send `payment_method_code="invoice"`;
   otherwise omit it (backend short-circuits on total==0 regardless). This lives
   in the existing per-source submit, gated on `isZeroTotal`. No new field.
   > **Decision note:** the backend ignores the method for zero-total, so
   > omitting is functionally sufficient — but sending `invoice` keeps web/iOS
   > byte-parity and avoids any future provider that asserts a method. Assumed:
   > send `invoice` when present, else omit.
5. **NO OVERENGINEERING:** no new "free plan" type/flag (price 0 is enough);
   no backend change; no new endpoint; no per-plugin duplication — the rule is
   one computed in core, the notice one component in fe-core.

### SOLID / DRY / Liskov
- **SRP / DRY:** zero-total truth in one computed; notice in one component.
- **OCP:** any future checkout source inherits the behaviour for free via the
  core `orderTotal`/`isZeroTotal` projection — no source-specific code.
- **Liskov:** a non-zero checkout is unchanged (payment block shown, label
  unchanged); the disabled/no-discount path is identical to today.

## 4. TDD plan (RED first)

**fe-core (Vitest)**
- `ZeroTotalNotice.spec.ts` — renders the notice text + `data-testid`.

**fe-user (Vitest)**
- core store: `isZeroTotal` is `true` when `orderTotal === 0`, false when `> 0`
  (drive via a fake CheckoutSource whose `getOrderTotal()` returns 0 / 10).
- public view + private view component tests:
  - `orderTotal === 0` → `PaymentMethodsBlock` **not** rendered, `ZeroTotalNotice`
    rendered, confirm button enabled without a payment method, label = "Pay Zero",
    requirements list omits "payment method".
  - `orderTotal > 0` → unchanged (payment block shown, label = "Pay {amount}",
    payment method required) — regression guard.
- submit: with `isZeroTotal`, payload sends `payment_method_code="invoice"` when
  available, else omits it; confirm still calls `submitCheckout`.

## 5. Playwright e2e (both checkouts, same behaviour)

Run against docker (`E2E_BASE_URL=http://localhost:8080`). Needs a zero-cost
checkout to exist deterministically (see §6).

- `vbwd-fe-user/vue/tests/e2e/checkout/pay-zero-public.spec.ts` — anonymous
  public checkout for a **free plan**:
  - assert `order-total` reads zero/Free,
  - assert `payment-methods-block` is **absent**,
  - assert `zero-total-notice` is visible and the confirm button reads "Pay Zero",
  - confirm without selecting any payment method → `checkout-success` (subscription
    activated, invoice PAID).
- `vbwd-fe-user/vue/tests/e2e/checkout/pay-zero-private.spec.ts` — same flow for
  the authenticated subscription checkout (`loginAsTestUser`), asserting
  **identical** behaviour.
- (If S36 has landed) one assertion that a 100%-discount-to-zero order takes the
  same path — apply a 100% coupon, confirm `payment-methods-block` disappears and
  the button flips to "Pay Zero". Skip-with-log if S36 not yet merged
  ([[feedback_ci_precommit_lessons]] — no silent skips).

## 6. Test data — a deterministic zero-cost path

The e2e needs a zero-price subscription plan that exists from a cold start.
- Verify whether the subscription plugin's `populate_db.py` already seeds a
  `display_price === 0` plan. If **not**, add one (e.g. slug `free`) **through
  the service/repo layer**, never raw SQL
  ([[feedback_no_direct_db_for_test_data]]); idempotent, runs local + CI.
- Stale-module gotcha: rebuild fe-core `dist/` and `docker compose restart dev`
  before running e2e ([[project_fe_user_two_fe_core_checkouts]]).

## 7. Files

| Action | Path |
| --- | --- |
| new  | `vbwd-fe-core/src/components/ZeroTotalNotice.vue` (+ unit spec + rebuild `dist/`) |
| edit | `vbwd-fe-core` i18n — `checkout.zeroTotalNotice`, `checkout.payZeroButton` |
| edit | `vbwd-fe-user/vue/src/stores/checkout.ts` — add/export `isZeroTotal` computed |
| edit | `vbwd-fe-user/plugins/checkout/PublicCheckoutView.vue` — hide payment block / notice / label / `canCheckout` |
| edit | `vbwd-fe-user/plugins/subscription/subscription/views/Checkout.vue` — same edits |
| edit | `vbwd-fe-user/plugins/subscription/subscription/stores/checkout.ts` — zero-total payload (`invoice`/omit) |
| edit | `vbwd-fe-user/plugins/shop/shop/checkoutSource.ts` — zero-total payload (parity) |
| edit | `vbwd-backend/plugins/subscription/.../populate_db.py` — seed a free (price 0) plan **iff** none exists |
| new  | `vbwd-fe-user/vue/tests/e2e/checkout/pay-zero-public.spec.ts` |
| new  | `vbwd-fe-user/vue/tests/e2e/checkout/pay-zero-private.spec.ts` |
| new  | fe-core + fe-user Vitest specs per §4 |

## 8. Acceptance (done = all of)

- A zero-total checkout in **both** the public and the private checkout:
  hides payment-method selection, shows the "Pay Zero" notice, the confirm
  button reads "Pay Zero", and confirming activates the subscription (invoice
  PAID, "Free plan activated.") without a payment method.
- A non-zero checkout is **unchanged** (regression guard green).
- Behaviour is driven by one core-store `isZeroTotal` computed + one fe-core
  notice component — no per-view duplication; core stays agnostic (oracles green).
- Backend untouched.
- `bin/pre-commit-check.sh --full` green on `vbwd-fe-core` + `vbwd-fe-user`;
  all new Playwright specs green against docker.
- No `# noqa`/`# type: ignore`/lint suppression without approval
  ([[feedback_no_noqa_without_permission]]); no commits unless instructed
  ([[feedback_no_commit_without_ask]]).

## 9. Open questions for the user

1. **Zero-total payload** — send `payment_method_code="invoice"` (iOS parity,
   assumed) or omit it entirely (backend short-circuits anyway)?
2. **Notice copy** — reuse the iOS string *"Please finish subscription by the
   button Pay Zero"* verbatim, or a web-tuned wording?
3. **Free-plan seeding** — OK to add a seeded `free` (price 0) plan via the
   subscription `populate_db.py` for the e2e, or should the zero case be reached
   only via a 100% S36 coupon (couples this sprint to S36)?
