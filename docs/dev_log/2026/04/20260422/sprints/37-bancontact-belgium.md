# Sprint 37 — Bancontact / Payconiq (Belgium direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** Bancontact carries 80%+ of Belgian card payments,
~2B transactions/yr, 12M users. Payconiq is the mobile QR wallet
integrated with Bancontact since 2018. See
[`payment-plugins-eu.md`](../../../dev_docs/market-research/payment-plugins-eu.md).

**Repos touched:**
- `vbwd-plugin-bancontact` (NEW — direct Bancontact/Payconiq API)
- `vbwd-fe-user-plugin-bancontact` (NEW — QR + card flow UI)
- `vbwd-fe-admin-plugin-bancontact` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/be-shop/` (NEW — BE demo)

## Goal

Direct Bancontact + Payconiq integration for Belgian merchants.
Bancontact card flow is e-commerce redirect (similar to iDEAL);
Payconiq is mobile QR scan via the Bancontact app. Both share the
same merchant account and settlement pipeline.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `BancontactAdapter.create_payment(invoice, mode)` spec first —
  `mode ∈ {'card', 'qr'}`; card returns redirect URL, QR returns
  deep-link + EMVCo QR payload.
- `PayconiqQRRenderer.render(payment)` spec first — emits EMVCo
  QR with Payconiq-specific merchant prefix.
- Webhook handler signature verification + idempotency by
  `paymentId`.

## Deliverables

### D1 — `vbwd-plugin-bancontact` backend

- Folder: `vbwd-plugin-bancontact/bancontact/`.
- `adapters/bancontact_adapter.py` — OAuth2 client for Bancontact
  Payments API; HMAC-signed webhooks.
- `services/bancontact_service.py` — invoice mapping; mode dispatch
  (card-redirect vs QR); reconciliation.
- `routes.py`:
  - `POST /api/v1/bancontact/payments` — create; returns redirect URL
    or QR payload per mode.
  - `POST /api/v1/bancontact/webhooks` — verified webhook receiver.
  - `GET /api/v1/bancontact/payments/:id/status` — polling.
- `models/bancontact_payment.py` — payment_id, invoice_no, mode,
  status, qr_payload, expires_at.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-bancontact`

- `components/BancontactMethodPicker.vue` — "Bancontact card" /
  "Payconiq by Bancontact" radio.
- `components/BancontactQR.vue` — QR + countdown + deep-link (mobile)
  + auto-poll.
- `components/BancontactRedirect.vue` — card-flow return handler.
- i18n: nl, fr, de, en.
- E2E: card-redirect happy path, QR happy path.

### D3 — `vbwd-fe-admin-plugin-bancontact`

- Config: merchant ID, API key (masked), OAuth credentials, test/live.
- Transaction list with refund button (Bancontact supports refunds
  within 365 days).

### D4 — BE demo instance

- `vbwd-demo-instances/instances/local/be-shop/` with Bancontact
  enabled + seed Belgian customer + EUR products.

## Tests

- Unit: ≥ 22 backend, ≥ 12 frontend.
- Integration: ≥ 4 sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **QR payload CRC**: EMVCo CRC16/CCITT-FALSE. Use `crcmod` or
  tested library; snapshot test.
- **Dual mode confusion**: UX must clearly separate card vs QR.

## Effort estimate

- Backend: **2 days**
- fe-user: **1 day**
- fe-admin: **0.75 day**
- Demo: **0.25 day**

**Total: ~4 person-days.**
