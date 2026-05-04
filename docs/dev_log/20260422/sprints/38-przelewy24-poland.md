# Sprint 38 — Przelewy24 (Poland direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** P24 carries 50%+ of Polish e-commerce payments,
est. USD 30B+/yr, 200K+ merchants. Used by Allegro, Zalando PL, mBank.

**Repos touched:**
- `vbwd-plugin-przelewy24` (NEW — direct P24 REST API)
- `vbwd-fe-user-plugin-przelewy24` (NEW — bank picker + BLIK + QR)
- `vbwd-fe-admin-plugin-przelewy24` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/pl-shop/` (NEW — PL demo)

## Goal

Direct Przelewy24 integration for Polish merchants. P24 aggregates
25+ Polish bank pay-by-link redirects, BLIK, and cards in one API.
Merchants get lower rates than via Mollie, plus direct control over
the bank list shown to customers.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `P24Adapter.register_transaction(invoice)` spec first — covers CRC
  (SHA384 hash of canonical string), required fields, currency PLN.
- `P24Adapter.verify_transaction(session_id, amount, orderId)` spec
  first — server-side confirmation step (never trust client).
- `P24WebhookHandler` idempotency via `sessionId` + `orderId`.
- BLIK inline code handling + auto-submit to P24.

## Deliverables

### D1 — `vbwd-plugin-przelewy24` backend

- Folder: `vbwd-plugin-przelewy24/p24/`.
- `adapters/p24_adapter.py` — HTTP client with SHA384 CRC; endpoints:
  `/transaction/register`, `/transaction/verify`, `/payment/method`,
  `/payment/method/:id`, `/refund`.
- `services/p24_service.py` — invoice mapping; BLIK inline flow;
  method-list caching (refresh nightly).
- `routes.py`:
  - `POST /api/v1/p24/transactions` — register; returns
    `{ redirectUrl, sessionId }`.
  - `POST /api/v1/p24/blik` — BLIK inline submit (6-digit code from
    user) → P24 returns immediate status.
  - `GET /api/v1/p24/callback?sessionId&orderId&amount` —
    return-URL; triggers `verify_transaction`.
  - `POST /api/v1/p24/refund` — admin-initiated refund.
- `models/p24_transaction.py` — session_id, order_id, invoice_no,
  method_id, status, amount, last_observed_status.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-przelewy24`

- `components/P24MethodPicker.vue` — grid of bank logos + BLIK +
  card; methods fetched from backend.
- `components/P24BlikEntry.vue` — 6-digit code input + submit →
  polls status for 60 s.
- `stores/p24.ts` — methods list, session state.
- i18n: pl (primary), en.
- E2E: BLIK happy path, bank-redirect happy path.

### D3 — `vbwd-fe-admin-plugin-przelewy24`

- Config: merchant ID, POS ID, secret keys (CRC + reports, both
  masked), test/live.
- Method enable/disable list with P24 method IDs.
- Transaction list + refund button.

### D4 — PL demo instance

- `vbwd-demo-instances/instances/local/pl-shop/` with P24 in sandbox.

## Tests

- Unit: ≥ 28 backend, ≥ 15 frontend.
- Integration: ≥ 4 P24 sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **BLIK code expiry**: BLIK codes live 2 minutes. UI must warn at
  30 s remaining and offer a regen.
- **Method list drift**: Polish banks come and go; nightly refresh
  keeps the merchant UI accurate.

## Effort estimate

- Backend: **2 days**
- fe-user (picker + BLIK): **1.25 days**
- fe-admin: **0.75 day**
- Demo: **0.25 day**

**Total: ~4.25 person-days.**
