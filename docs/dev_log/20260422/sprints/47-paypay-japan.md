# Sprint 47 — PayPay (Japan direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** PayPay is Japan's #1 QR payment wallet; 60M+
users, 3.8M+ merchants. Launched 2018, now the de-facto QR standard
at LAWSON, FamilyMart, Rakuten partners.

**Repos touched:**
- `vbwd-plugin-paypay` (NEW — direct PayPay for Business API)
- `vbwd-fe-user-plugin-paypay` (NEW — QR + deep-link + web-payment)
- `vbwd-fe-admin-plugin-paypay` (NEW — config + tx list + refund)
- `vbwd-demo-instances/instances/local/jp-saas/` (NEW — Japan demo)

## Goal

Direct PayPay integration for Japanese merchants. Two flows in v1:
1. **Web Payment** (QR scan + in-app confirm) — merchant site shows
   QR, user scans with PayPay app, confirms, web polls status.
2. **App Invoke** (mobile deep-link) — `paypay://` scheme → in-app
   confirm → Universal Link return.

Also reachable via Komoju aggregator — direct plugin is for merchants
with a PayPay for Business contract (lower fees for JPY 30K+
transactions).

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `PayPayAdapter.create_code(invoice)` spec first — HMAC-SHA256
  signature per PayPay spec v2; required fields `merchantPaymentId`,
  `amount.amount`, `amount.currency=JPY`, `codeType=ORDER_QR`.
- `PayPayAdapter.get_code_details(code_id)` + `delete_code(code_id)`
  spec first — expiry cleanup.
- `PayPayWebhookHandler.handle(payload)` spec first — HMAC verify +
  idempotency by `merchantPaymentId`.
- Currency locked to JPY; integer amounts (no sub-unit).

## Deliverables

### D1 — `vbwd-plugin-paypay` backend

- Folder: `vbwd-plugin-paypay/paypay/`.
- `adapters/paypay_adapter.py` — HMAC-signed HTTP client; endpoints:
  `/v2/codes`, `/v2/codes/:id`, `/v2/codes/:id/payments`,
  `/v2/payments/:id/refunds`.
- `services/paypay_service.py` — invoice mapping; JPY integer
  enforcement; code lifecycle.
- `routes.py`:
  - `POST /api/v1/paypay/codes` — issue payment code.
  - `POST /api/v1/paypay/webhooks` — verified receiver.
  - `GET /api/v1/paypay/payments/:id/status` — polling.
  - `POST /api/v1/paypay/payments/:id/refund` — refund.
- `models/paypay_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-paypay`

- `components/PayPayQR.vue` — QR + 5-min countdown + auto-poll.
- `components/PayPayDeepLink.vue` — mobile `paypay://` intent +
  return handler.
- i18n: ja (primary), en.
- E2E: desktop QR, mobile deep-link.

### D3 — `vbwd-fe-admin-plugin-paypay`

- Config: merchant ID, API key, API secret (masked), test/live.
- Transaction list with refund button.

### D4 — JP demo instance

- `vbwd-demo-instances/instances/local/jp-saas/` — localhost JP demo.
- Seed: 1 admin, 1 JP customer, 2 JPY subscription plans.
- README: "clone, `make up`, buy with PayPay sandbox".

## Tests

- Unit: ≥ 22 backend, ≥ 12 frontend.
- Integration: ≥ 3 sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Code expiry**: PayPay codes default to 5 min. UI countdown
  matches backend expiry exactly to avoid "expired but still shown"
  state.
- **JPY sub-unit**: zero sub-unit currency; any float amount is a
  bug. Validate.

## Effort estimate

- Backend: **1.5 days**
- fe-user: **0.75 day**
- fe-admin: **0.5 day**
- JP demo: **0.5 day**

**Total: ~3.25 person-days.**
