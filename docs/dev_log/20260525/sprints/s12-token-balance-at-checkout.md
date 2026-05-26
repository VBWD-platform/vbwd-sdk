# S12 — Token balance as an instant checkout payment method

**Status:** IMPLEMENTED & E2E-VERIFIED — 2026-05-26 (24 unit tests green; lint
clean; live e2e: Token balance selectable → live quote block (balance now /
tokens to pay / balance after) → submit → instant pay → confirmation with
`payment_method=token_payment`, balance dropped by the token cost). Extends [s10](s10-pay-with-token-balance.md)
(which paid an *existing* invoice) to the **checkout** flow: pick "token balance"
as the payment method and see a live quote, paid instantly.
**Track:** independent (continues s10). **Repos:** `vbwd-plugin-token-payment`
(backend), `vbwd-fe-user` (one small core seam), `vbwd-fe-user-plugin-token-payment`.
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · clean code ·
**core agnostic** · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md).
Gate: backend `bin/pre-commit-check.sh --full` + fe-user `npm run lint && npm run test`.

---

## 1. Goal (user value)

In checkout, when the user selects **Token balance** as the payment method, show a
new block:

```
Token balance now:        500 tokens
Tokens to pay:            200 tokens
Token balance after:      300 tokens     [Pay — instant]
```

Token payment is **instant**: on submit the invoice is created and immediately
paid from the balance — no gateway redirect, no PENDING wait. The figures update
live with the cart total.

## 2. Current flow (grounded)

- `PaymentMethodsBlock.vue` is **data-driven** — it iterates methods from
  `GET /api/v1/payment-methods` (`vbwd/routes/settings.py:10`, the
  `vbwd_payment_method` table). So a method becomes selectable by adding a DB
  record — no core list edit.
- `PublicCheckoutView.vue` creates the invoice, then routes by
  `checkoutStore.paymentMethodCode` (`:222-232`): `stripe`/`paypal` → gateway,
  else → `/checkout/confirmation`.
- The checkout already uses extension registries (`checkoutStepRegistry`,
  `checkoutContextRegistry`, …) — the pattern to mirror.
- s10 already gives us: `TokenPaymentService` (rate + `compute_tokens_needed` +
  balance), and `POST /plugins/token-payment/invoices/<id>/pay`.

## 3. Design

### Backend (token-payment plugin) — DRY, reuses s10's service

1. **Amount-based quote** (checkout has no invoice yet):
   `GET /api/v1/plugins/token-payment/quote?amount=<total>&currency=<cur>` →
   `{ available, tokens_needed, balance, balance_after, sufficient }`. Thin route
   over the **existing** `TokenPaymentService` (`rate_for`, `compute_tokens_needed`,
   `get_balance`) — no new logic. (The invoice-based quote from s10 stays.)
2. **Make it selectable:** on `on_enable`, **upsert** a `vbwd_payment_method`
   record `{code:"token_balance", name:"Token balance", plugin_id:"token_payment",
   is_active:true}`; deactivate on `on_disable`. Then `/payment-methods` lists it
   and `PaymentMethodsBlock` shows it automatically — agnostic, no fe-user list
   change.

### fe-user — one small agnostic core seam + plugin component

3. **`checkoutPaymentMethods` registry** (fe-user core, ~15 lines; mirrors s10's
   `invoicePaymentMethods` + the existing `checkout*Registry`): keyed by method
   `code` → `{ detailComponent?: Component; instantPay?: (invoiceId) => Promise }`.
4. **`PaymentMethodsBlock.vue`** (core, additive): when the *selected* method has a
   registered `detailComponent`, render it under that option, passing the cart
   `total` + `currency`. (Generic — any plugin method can show a detail block.)
5. **`PublicCheckoutView.vue`** (core, additive): after the invoice is created, if
   the selected method has a registered `instantPay`, `await instantPay(invoiceId)`
   then route to `/checkout/confirmation` (instant, no gateway). Else the existing
   routing. Core never names "token".
6. **token-payment fe-user plugin** registers `token_balance` →
   - `detailComponent: TokenCheckoutQuote.vue` — shows *balance now / tokens to pay
     / balance after*, fetched from the amount-quote endpoint and **watched** on
     the cart total; warns + blocks submit when `!sufficient`.
   - `instantPay: (invoiceId) => api.post('/plugins/token-payment/invoices/'+invoiceId+'/pay')`.

### SOLID / DI / DRY / no overengineering

- **SRP:** quote endpoint (read), method-record upsert (enable/disable), checkout
  component (display), registry (wiring). **DRY:** all token math stays in
  `TokenPaymentService`; the `/pay` capture path is the s10 one (debit →
  `emit_payment_captured` → line-item registry). **DI/agnostic:** checkout core
  calls a registered `instantPay`/`detailComponent`, never token-specific code.
- **No overengineering:** reuse the existing `/pay`; no new "instant payment"
  framework — just an optional `instantPay` hook on the registry. No partial
  pay, no rate table (config rate from s10).

## 4. TDD (RED first)

Backend: amount-quote endpoint (available / insufficient / no-rate-for-currency);
`on_enable` upserts an active `token_balance` method, `on_disable` deactivates it.

fe-user:
- `TokenCheckoutQuote.vue` — renders balance/cost/after from a mocked quote; emits
  "ready/blocked"; re-quotes when the total prop changes; insufficient → disabled.
- `checkoutPaymentMethods` registry — register/get; PaymentMethodsBlock renders the
  registered detail component only for the selected method.
- `PublicCheckoutView` instant path — selecting `token_balance` → after invoice
  creation `instantPay(invoiceId)` is called and routes to confirmation (not a
  gateway); a non-instant method keeps existing routing.

E2e (when stack runnable): select Token balance in checkout → block shows
balance/cost/after → submit → invoice created **and PAID** in one step → balance
dropped → confirmation.

## 5. Files

| Action | Repo / path |
| --- | --- |
| new | backend `token_payment/routes.py` — amount-quote route (+ tests) |
| edit | backend `__init__.py` `on_enable/on_disable` — upsert/deactivate `token_balance` payment method |
| new | fe-user `vue/src/registries/checkoutPaymentMethods.ts` |
| edit | fe-user `components/checkout/PaymentMethodsBlock.vue` (render selected method's detail) + `PublicCheckoutView.vue` (instantPay hook) |
| new | plugin `TokenCheckoutQuote.vue` + register in `index.ts` (+ tests) |

## 6. Acceptance

- "Token balance" appears in checkout only when the plugin is enabled + a rate
  exists for the cart currency.
- Selecting it shows balance-now / tokens-to-pay / balance-after, live with the
  total; insufficient balance blocks submit.
- Submit = invoice created **and** paid instantly from tokens → confirmation, no
  gateway redirect, no PENDING.
- Core checkout untouched except the one generic registry + the additive renders;
  agnosticism oracle green. Gate green per repo.

## 7. Out of scope
Partial token+card, multi-currency rate CRUD, refunds — deferred (s10 §7).
Carries the s11 follow-ups’ fixes once those land (post-capture `new_balance`).
