# S11 — token-payment follow-ups (post-e2e polish)

**Status:** IMPLEMENTED & E2E-VERIFIED — 2026-05-26 (20 unit tests green; lint
clean; live e2e: paid invoice now reports `payment_method=token_payment`,
`new_balance` reflects post-capture, panel rows visually separated). Follow-ups from the s10 live e2e
([report 06](../reports/06-s9-s10-e2e-verification.md)). Low risk, mostly polish.
**Track:** independent (continues s10). **Repos:** `vbwd-backend` (core, item 1),
`vbwd-plugin-token-payment` (item 2), `vbwd-fe-user-plugin-token-payment` (item 3).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **core agnostic** · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md).
Gate: `bin/pre-commit-check.sh --full` (backend) + `npm run lint && npm run test`
(fe-user) green per touched repo.

---

## Item 1 — record the actual capturing provider on the invoice (core)

**Severity:** low (reporting accuracy). **Repo:** `vbwd-backend` (core, generic —
not token-specific).

**Observed:** after paying a `stripe`/`invoice`-method invoice with tokens, the
invoice shows `payment_method = "invoice"`/`"stripe"`, not `token_payment`.

**Root cause:** `vbwd/handlers/payment_handler.py:43-47` marks the invoice PAID by
setting `status`, `payment_ref`, `paid_at` directly — it **never sets
`payment_method`**, even though `event.provider` carries the capturing provider
(e.g. `"token_payment"`). So the field keeps whatever checkout set.

**Fix (generic, agnostic):** when `event.provider` is present, set
`invoice.payment_method = event.provider` in the handler — record the method that
*actually* captured the payment. Benefits every method (token-balance just makes
the gap visible). Prefer routing through `invoice.mark_paid(payment_ref,
payment_method)` (which already takes both) instead of the inline field writes, to
keep one home for the PAID transition (DRY).

**TDD:**
- Characterisation: a stripe/paypal capture still ends with the expected
  `payment_method` (provider string == existing code → no behaviour change).
- New: a `provider="token_payment"` capture sets `payment_method == "token_payment"`.
- Edge: empty/absent `provider` leaves `payment_method` unchanged (Liskov — old
  callers unaffected).

**Risk:** medium — central to *all* payment flows. Guard with the characterisation
tests above + the subscription integration suite before "done".

## Item 2 — pay response returns the post-capture balance (plugin)

**Severity:** low (cosmetic). **Repo:** `vbwd-plugin-token-payment`.

**Observed:** `POST …/pay` returns `new_balance` computed right after the debit;
for a **token-bundle** invoice the capture event then credits the bundle, so the
returned `new_balance` is stale (e.g. returned 7784 while the real balance was
8784).

**Fix:** in `token_payment/routes.py`, after a successful `emit_payment_captured`,
re-read `current_app.container.token_service().get_balance(user_id)` and return
*that* as `new_balance`. Single source of truth = the wallet after all capture
side-effects. Plugin-only; no core change.

**TDD:** route/service test — when capture credits tokens (fake line-item effect),
the response `new_balance` equals the wallet's post-capture balance, not the
post-debit interim value.

**Risk:** low.

## Item 3 — panel label/value spacing (fe-user)

**Severity:** trivial (CSS). **Repo:** `vbwd-fe-user-plugin-token-payment`.

**Observed:** in the narrow panel box the rows render label and value flush
("Your balance8724 tokens").

**Fix:** in `TokenPaymentPanel.vue`, give `.token-payment__row` a `gap` (e.g.
`gap: 0.75rem`) and the panel a sensible `min-width` so `space-between` actually
separates the columns. No logic change.

**TDD:** covered by the existing panel component test (rendering unaffected);
visual check via the e2e screenshot.

**Risk:** trivial.

---

## Acceptance
- Token-paid invoices report `payment_method = "token_payment"`; stripe/paypal/
  invoice flows unchanged (regression tests green).
- `pay` `new_balance` matches the wallet balance after capture (incl. bundle
  credit-back).
- Panel rows are visually separated.
- Gate green on each touched repo. (Backend integration deferred only if the live
  stack is unavailable.)

## Explicitly out of scope
Automated token refunds, multi-currency rate CRUD table, partial token+card —
all already deferred in [s10](s10-pay-with-token-balance.md) §7.
