# Report 09 — Pay Zero: free GHRM packages + free bookings

**Date:** 2026-06-02
**Status:** ✅ A €0 checkout completes with **no payment step** — the invoice is
marked PAID and the entitlement (subscription / booking) is created. Verified
live (`localhost:8080`) for both a **free GHRM package** and a **free bookable
resource**, plus backend integration + the full fe-user unit suite green.

## 1. Why GHRM "Pay Zero" was broken

The backend was already correct: the subscription checkout handler auto-pays a
€0 invoice (emits a zero-price `PaymentCapturedEvent` → invoice PAID →
subscription Active). API proof — every free GHRM package returns
`invoice.status = PAID, total = 0.00, message = "Free plan activated"`; priced
plans stay PENDING.

The breakage was **purely front-end**: the checkout views gated the Pay button
on a **selected payment method _and_ a billing address** regardless of total. A
free plan has nothing to pay and no method to pick, so the button was
permanently disabled — the user could never activate. The success banner also
always read "Complete payment to activate…", even for an already-PAID free plan.

### Fix (fe-user)
Both checkout views — private subscription `Checkout.vue` and public
`PublicCheckoutView.vue` — now treat a **zero total** as free:
- Payment-method + billing-address requirements are **waived** when
  `!hasPayableTotal` (and both blocks are hidden — nothing to pay, nothing to
  bill).
- The Pay button reads **"Activate for Free"** instead of "Pay $0.00".
- The success banner is conditional on `invoice.status`: **"Payment complete —
  your subscription is active."** when PAID, the old prompt otherwise.
- Also fixed the double-currency label `"Pay ${amount}"` → `"Pay {amount}"`
  (`formatMoney` already adds the symbol).

The public flow's agnostic post-checkout dispatch already falls through to
`/checkout/confirmation` when no method is selected, so the free path needed no
new dispatch logic.

## 2. Booking "Pay Zero" (new)

Booking had **no** zero-price path. Added one mirroring subscription, through
the shared core seam (no new core dependency):

**Backend** — `plugins/booking/booking/routes.py` (`booking_checkout`): after the
invoice is created (and any coupon applied), if the net total `<= 0` it calls
`vbwd.plugins.payment_route_helpers.emit_payment_captured(...)`. That is the
exact chain token-balance payments use: core `PaymentCapturedHandler` marks the
invoice PAID and publishes `invoice.paid`, which `BookingPaymentHandler` turns
into a confirmed `Booking`. No payment step.

**Frontend** — `BookingCheckout.vue`: `isFree = netTotal <= 0` waives the
payment-method + billing requirements (and hides both blocks), the button reads
**"Confirm Free Booking"**, and `handlePay` routes a free booking straight to
`/checkout/confirmation` (the backend already captured it).

## Tests

- **Backend integration** (permanent guard):
  `plugins/booking/tests/integration/test_booking_checkout_with_coupon.py::
  test_booking_checkout_zero_price_auto_pays` — €0 resource → checkout → invoice
  PAID + booking `confirmed`. **3 passed** (with the existing coupon cases).
- **fe-user unit:** full suite **673 passed / 1 skipped**; ESLint **0 errors**.
- **Browser (live, throwaway specs):** a fresh user activates a free GHRM
  package (success = subscription active, no payment prompt) and books a free
  resource (lands on confirmation, invoice PAID). Both passed; specs were
  environment-dependent (needed seeded free plan/resource) so were not kept in
  the CI suite. A free `free-community-room` resource was created via the admin
  API for the booking demo.

## Engineering requirements

TDD-first (backend test written against the new path), narrowest change (reused
the existing `emit_payment_captured` seam + `hasPayableTotal`/`isFree`
computeds — no new core coupling), core stays agnostic. `bin/pre-commit-check.sh`
scopes: backend booking lint (black + flake8 `--max-line-length=120`) clean;
fe-user ESLint clean.

**Not committed** (standing rule).
