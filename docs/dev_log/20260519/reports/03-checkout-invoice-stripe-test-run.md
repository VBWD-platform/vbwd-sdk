# Report 03 — Checkout / Invoice / Stripe test run (post Sprint 10)

**Date:** 2026-05-24 · **Author:** Claude (Opus 4.7) · **Context:** verification
after [Sprint 10](02-phase0-outcome-and-locked-decisions.md#3o) made the core
fe-user checkout store plugin-agnostic (generic store + `checkoutSourceRegistry`;
subscription + shop register their own `CheckoutSource`).

**Question asked:** run the checkout tests in the invoice and stripe flows and
report results, with comments.

---

## 1. Summary

| Layer | Suite scope | Result |
|---|---|---|
| **Unit** | checkout / invoice / stripe (8 files) | **69 / 69 pass** ✅ |
| **E2E** | `vue/tests/e2e/checkout/` (8 files, 27 tests) | **1 pass / 26 fail** ⚠️ pre-existing stale fixtures |
| **E2E** | invoices + booking-checkout + booking-invoice-payment (15 tests) | **6 pass / 9 fail** ⚠️ stale routes + Stripe/login nav timeouts |
| **E2E** | `prod-checkout-all.spec.ts` | **not run** — targets production URLs (see §5) |

E2E totals (local): **7 pass / 35 fail** — every failure traced to stale
fixtures or an integration dependency (real Stripe / seeded data), none to
Sprint 10.

**Bottom line:** every **unit** test covering the Sprint 10 surface and the
invoice/stripe consumers passes. The **e2e** failures are **not** caused by
Sprint 10 — they are pre-existing breakage from the earlier `/dashboard/*` route
restructure (Sprint 07), which left the e2e fixtures pointing at routes that no
longer exist. Proof in §3.

---

## 2. Unit tests — 69/69 pass

Run: `npx vitest run <files>` (fe-user).

| File | Tests | What it guards |
|---|---|---|
| `vue/tests/unit/stores/checkout.spec.ts` | 8 | the **new generic** core store — drives a registered fake `CheckoutSource`, asserts load / lineItems / total / submit / reset delegate to it, highest-priority match wins |
| `plugins/subscription/tests/unit/checkout-store.spec.ts` | 12 | the subscription checkout store (relocated from core) — `/user/checkout`, plan/bundles/addons, `loadFromCart` |
| `vue/tests/unit/plugins/checkout-step-registry.spec.ts` | 14 | checkout step/context extension framework |
| `vue/tests/unit/stores/invoices.spec.ts` | 8 | invoice store (consumes checkout-created invoices) |
| `vue/tests/unit/views/invoice-detail-line-items.spec.ts` | 5 | invoice line-item rendering (`CheckoutResult.invoice.line_items`) |
| `vue/tests/unit/plugins/stripe-payment.spec.ts` | 6 | stripe plugin routes incl. **`/pay/stripe`** — the redirect target the checkout watcher pushes to after a successful checkout |
| `vue/tests/unit/subscription-agnostic.spec.ts` | 5 | the Sprint 10 oracle — core checkout names no plugin domain |
| `plugins/shop/tests/unit/cart.spec.ts` | 11 | shop cart store (backs the shop `CheckoutSource`) |

**Comment.** This is the meaningful regression check for Sprint 10. The store
split (generic core ↔ subscription/shop sources) and the `CheckoutResult` shape
change are both exercised: the stripe redirect target still resolves, and the
invoice view still renders line items from a checkout result.

---

## 3. Checkout e2e — 26 fail / 1 pass (PRE-EXISTING, not Sprint 10)

Run: `E2E_BASE_URL=http://localhost:8080 npx playwright test vue/tests/e2e/checkout` (9.4 min).

Failing files: `addons` (5), `token-bundles` (5), `checkout-display` (5),
`checkout-submit` (7), `post-checkout` (3), `checkout-confirmation-page-exists`
(1). 1 test passed.

### Root cause — stale fixtures from the `/dashboard/*` route move

`vue/tests/e2e/fixtures/checkout.fixtures.ts` targets routes that **no longer
exist** in the current app:

```ts
navigateToCheckout: page.goto(`/checkout/${planSlug}`)   // default 'pro'
// post-checkout asserts:  /subscription   /plans   /invoices
```

Current routing (set in a **prior** sprint, not Sprint 10):
- subscription plugin: `/dashboard/plans`, `/dashboard/subscription`,
  `/dashboard/checkout/:planSlug`, `/dashboard/checkout/cart`
- checkout plugin: `/checkout` (reads `?tarif_plan_id=`), `/checkout/confirmation`

There is **no** `/checkout/:planSlug`, and **no** top-level `/subscription`,
`/plans`, `/invoices`. There is also no `pro` plan seeded (the DB has `free`,
`plugin-ghrm`, `pkg-*`).

### Captured failure point (proves it's the fixture, not the store)

```
checkout-display.spec.ts:12 › displays plan details in order summary
  expect(locator('[data-testid="order-summary"]')).toBeVisible() failed
  Error: element(s) not found
```

The test dies waiting for `order-summary` because the `beforeEach` navigated to
the dead `/checkout/pro`. **My Sprint 10 `PublicCheckoutView` still renders
`data-testid="order-summary"`** — confirmed live: `/checkout?tarif_plan_id=free`
shows the order summary + `PlanCheckoutSummary` ("Free"), and
`/dashboard/checkout/free` renders the subscription checkout. The failure is at
navigation, before any checkout-store code runs.

### Attribution evidence

- Sprint 10's working diff touches **none** of: `checkout.fixtures.ts`, the e2e
  specs, or `router/index.ts` (the +7-line router diff is a prior-sprint invoices
  route — no checkout/source additions).
- The fixtures reference routes removed in the Sprint 07 `/dashboard` restructure
  — i.e. they were already broken before Sprint 10.
- Live manual verification of the real routes passes (§3 above).

**Comment.** These 26 failures are real *test rot*, but they predate and are
unrelated to Sprint 10. They should be fixed as a separate e2e-maintenance task
(update the fixtures to `/dashboard/checkout/:slug` + `/checkout?tarif_plan_id=`,
seed a paid plan, fix the post-checkout URL assertions). I did **not** silently
"fix" them under the Sprint 10 banner.

---

## 4. Invoice / booking / stripe-redirect e2e — 6 pass / 9 fail

Run: `E2E_BASE_URL=http://localhost:8080 npx playwright test invoices.spec.ts
booking-checkout.spec.ts booking-invoice-payment.spec.ts --timeout=25000` (3.2 min).

Captured failure signatures:

```
invoices.spec.ts   expect(locator('[data-testid="invoice-search"]')).toBeVisible() — not found
invoices.spec.ts   expect(locator('[data-testid="status-filter"]')).toBeVisible() — not found
                   page.fill / page.selectOption on those → 25s timeout
booking-*          page.waitForURL: Test timeout of 25000ms exceeded (waiting for navigation)
```

**Cause, by file:**
- **`invoices.spec.ts`** — navigates to the stale top-level **`/invoices`** (the
  real route is `/dashboard/subscription/invoices`), so the invoice list never
  renders and `invoice-search` / `status-filter` are absent. Same stale-route
  class as §3.
- **`booking-checkout.spec.ts`** — drives a real booking → **`checkout.stripe.com`**
  redirect; without Stripe configured + a seeded booking resource on this local
  stack, `waitForURL` times out. Integration-environment, not a code defect.
- **6 passed** — the assertions that don't depend on the stale UI routes or the
  external Stripe redirect (e.g. direct `fetch` API checks in
  `booking-invoice-payment.spec.ts`).

**Comment.** None of these touch the Sprint 10 checkout store. `booking-checkout`
in particular exercises the *booking* flow (a different `CheckoutSource`-free
path) and the live Stripe handoff — neither is what Sprint 10 changed.

---

## 5. Not run — `prod-checkout-all.spec.ts`

This spec hardcodes **production** URLs (`https://vbwd.cc`,
`https://hotel.vbwd.cc`, `https://doctor.vbwd.cc`, `ghrm.vbwd.cc`). It is a prod
smoke test for live incidents (2026-05-04, 2026-05-10), not a local regression
test. Running it would hit production sites and tells us nothing about a local
Sprint 10 change, so it was intentionally skipped.

---

## 6. Recommendations

1. **Trust the unit layer for Sprint 10** — 69/69 green across the generic core
   store, both plugin sources, invoice consumers, and the stripe redirect target.
2. **Open a separate e2e-maintenance task** to de-stale the checkout/invoice
   fixtures (routes → `/dashboard/*` + `?tarif_plan_id=`, seed a paid plan, fix
   post-checkout assertions). Tracked distinctly from the extraction work.
3. **Leave `prod-checkout-all` to the prod smoke pipeline** (run with
   `E2E_BASE_URL=https://vbwd.cc` against a deployed build, never locally).
