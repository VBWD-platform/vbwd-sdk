# Sprint 49 — LINE Pay (JP / TW / TH)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** LINE Pay is the LINE-messenger-native wallet,
strongest in JP + TW; secondary to PayPay in JP, to JKOPay in TW, and
to TrueMoney/PromptPay in TH. 90M+ Japanese LINE users with LINE Pay
eligibility. Used by LINE Shopping, LINE Store, TH retailers.

**Repos touched:**
- `vbwd-plugin-line-pay` (NEW — direct LINE Pay Merchant API v3)
- `vbwd-fe-user-plugin-line-pay` (NEW — QR + deep-link UI)
- `vbwd-fe-admin-plugin-line-pay` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/jp-saas/` (existing — enable)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable
  for TH scenarios)

## Goal

Single plugin covers JP / TW / TH via LINE Pay Merchant API v3. LINE
Pay is a common secondary method for merchants whose customer base
skews toward LINE users (Japanese 20-40s, Taiwanese general, Thai
Gen-Z).

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `LinePayAdapter.request_payment(invoice, region)` spec first —
  HMAC-SHA256 signature per v3 spec; region → API host + currency
  (JPY / TWD / THB).
- `LinePayAdapter.confirm_payment(transaction_id, amount, currency)`
  spec first — server-side 2-step finalization after user redirect.
- Webhook handler + idempotency spec first.

## Deliverables

### D1 — `vbwd-plugin-line-pay` backend

- Folder: `vbwd-plugin-line-pay/line_pay/`.
- `adapters/line_pay_adapter.py` — HMAC-signed v3 client; region
  router (JP / TW / TH).
- `services/line_pay_service.py` — invoice → request + confirm;
  currency enforcement.
- `routes.py`:
  - `POST /api/v1/line-pay/payments` — request payment; returns
    `{ paymentUrl, paymentUrlApp }`.
  - `POST /api/v1/line-pay/confirm` — server-side confirm
    (called by return-URL handler).
  - `GET /api/v1/line-pay/payments/:id/status` — polling.
  - `POST /api/v1/line-pay/payments/:id/refund` — refund.
- `models/line_pay_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-line-pay`

- `components/LinePayCheckout.vue` — device-aware: desktop QR via
  `paymentUrl`, mobile deep-link via `paymentUrlApp`.
- `components/LinePayReturn.vue` — handles `transactionId` +
  `orderId` return, calls `/confirm`.
- i18n: ja, zh-Hant, th, en.
- E2E: JP desktop QR, TW mobile deep-link.

### D3 — `vbwd-fe-admin-plugin-line-pay`

- Config: channel ID, channel secret (masked), region selector,
  test/live.
- Transaction list with region column + refund button.

### D4 — demo wiring

- Enable LINE Pay in `jp-saas` + `sea-saas` instances. Document
  region config per instance.

## Tests

- Unit: ≥ 25 backend, ≥ 12 frontend.
- Integration: ≥ 3 LINE Pay sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Two-step finalization**: LINE Pay v3 requires explicit `confirm`
  call after redirect. Skipping it leaves funds in hold state.
  Return-URL handler must always call `confirm`, idempotently.
- **Region sandbox split**: LINE Pay has separate JP / TW / TH
  sandboxes. CI integration tests gated per region.

## Effort estimate

- Backend: **2 days**
- fe-user: **1 day**
- fe-admin: **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~4 person-days.**
