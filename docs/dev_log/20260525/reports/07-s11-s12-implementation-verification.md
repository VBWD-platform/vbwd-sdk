# Report 07 — s11 + s12 implementation verification

**Date:** 2026-05-26. Both planned sprints from the handoff (`handsoff.md`) are
**IMPLEMENTED & e2e-verified** on the live local stack.

## s11 — token-payment follow-ups

| # | Item | Code | Verified |
|---|------|------|----------|
| 1 | **Record capturing provider** — `PaymentCapturedHandler` (`vbwd/handlers/payment_handler.py:43-50`) now routes through `invoice.mark_paid(event.payment_reference, event.provider or invoice.payment_method or "")` — single home for the PAID transition (DRY), regression-safe for stripe/paypal | Backend core | 5 unit cases (stripe/paypal/token/absent-provider/already-paid) + live e2e: `payment_method=token_payment` on the s11 invoice and the s12 confirmation page |
| 2 | **Post-capture `new_balance`** — `routes.py` now re-reads `TokenPaymentService.read_balance(user_id)` after `emit_payment_captured`, so the response reflects line-item credits (e.g. token-bundle activation) | token-payment plugin | 1 service test + live e2e: bundle invoice returned `new_balance=8924` exactly matching the wallet |
| 3 | **Panel CSS spacing** — `TokenPaymentPanel.vue` gains `gap: 1rem` on rows + `min-width: 240px` | fe-user plugin | Visual: `screenshots/s11-panel-spacing-fixed.png` (rows now read "Your balance · 8924 tokens") |

Also closed a **discovered config-store quirk**: rates come back as a
JSON-encoded string when persisted via the admin text-input field, breaking
`TokenPaymentService.__init__`. Made the service tolerant of either dict or
JSON-string for `rates` (with a unit test).

**Backend total:** 29 unit tests green (5 handler + 23 plugin + 1 read_balance), flake8 @120 clean.

## s12 — token balance as an instant checkout payment method

| Layer | What | Verified |
|---|---|---|
| Backend (plugin) | `GET /api/v1/plugins/token-payment/quote?amount=&currency=` (thin over the existing `TokenPaymentService.quote_for_amount`); `on_enable` upserts `vbwd_payment_method` `code=token_balance`, `on_disable` deactivates | 3 quote-for-amount tests + 5 upsert/deactivate tests; live: endpoint returns `{available, tokens_needed, balance, balance_after, sufficient}`; `token_balance` appears in `GET /api/v1/settings/payment-methods` |
| fe-user (core seam) | New `vue/src/registries/checkoutPaymentMethods.ts` (~25 lines, mirrors s10's `invoicePaymentMethods` + the existing `checkout*Registry`); `PaymentMethodsBlock.vue` renders the selected method's registered detail; `PublicCheckoutView.vue` calls a registered `instantPay(invoiceId)` after invoice creation (else existing routing); `stores/checkout.ts` exposes `currency` (computed) | 4 registry tests + 5 panel tests; live UI |
| fe-user (plugin) | `TokenCheckoutQuote.vue` (live block: balance now / tokens to pay / balance after, re-quotes on cart-total change); `index.ts` registers `token_balance → { detailComponent, instantPay = api.post('/plugins/token-payment/invoices/:id/pay') }` | 5 component tests; live UI — see screenshots below |

**fe-user total:** 24 unit tests green, eslint + vue-tsc clean.

### Live e2e walk-through

1. Plan `Pro` ($29.99 USD) loaded at `/checkout?tarif_plan_id=…`.
2. **"Token balance"** appears in the Payment Method list (data-driven from
   `vbwd_payment_method` upsert).
3. Selecting it renders the **live quote block** —
   `screenshots/s12-checkout-with-token-balance.png`:
   ```
   Pay with tokens
   Token balance now            9124 tokens
   Tokens to pay                 600 tokens
   Balance after payment        8524 tokens
   ```
4. Accept terms → click **Pay $29.99** → app routes to
   `/checkout/confirmation?invoice_id=…` (no gateway redirect).
5. Confirmation page (`screenshots/s12-after-instant-pay.png`) shows:
   *Payment Successful · Status: Paid · Amount: $29.99 · **Payment Method:
   token_payment** · Pro · $29.99*.
6. API verify: invoice `4283cb97-…` is **PAID** with `payment_method=token_payment`;
   wallet balance dropped (600 spent, 200 bundle credited back — net −400 — same
   pattern observed in s10).

## Architectural integrity

- **Core agnostic** — the only fe-user core changes are: one tiny `currency` getter
  added to `checkoutStore` and the generic `checkoutPaymentMethods` registry +
  `PaymentMethodsBlock`/`PublicCheckoutView` hooks (no token-specific code).
- **DRY** — all token math stays in `TokenPaymentService`; checkout reuses the s10
  `/pay` route via `instantPay`; the capture path is the same `emit_payment_captured`
  every payment plugin uses.
- **DI/Liskov** — registry returns plain `Component` + async function; `instantPay`
  any-async, `detailComponent` any Vue component.
- **No overengineering** — `instantPay` is an optional hook on the existing
  registry, not a new payment framework.

## Not done / follow-ups

- Plugin repos are still local-only; `git status` shows uncommitted s11/s12 changes
  across `vbwd-backend/plugins/token_payment/`, `vbwd-fe-user/plugins/token-payment/`,
  and the small core seams in `vbwd-fe-user/vue/src/`. **Nothing pushed to remotes.**
- Optional polish: surface the registered detail label/icon in `PaymentMethodsBlock`
  (currently the option uses the backend-stored `name`/`description`). Adequate
  for now.
