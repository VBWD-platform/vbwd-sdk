# Sprint 45 — MoMo (Vietnam direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** MoMo is Vietnam's #1 mobile payment wallet; 31M
users, est. USD 15B+ TPV. Used by Tiki, Shopee VN, Grab VN.

**Repos touched:**
- `vbwd-plugin-momo` (NEW — direct MoMo Merchant API)
- `vbwd-fe-user-plugin-momo` (NEW — QR + deep-link UI)
- `vbwd-fe-admin-plugin-momo` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable)

## Goal

Direct MoMo integration for Vietnamese merchants. MoMo supports four
flows — this sprint ships the two most-used for e-commerce:
1. **QR Code** (desktop) — user scans MoMo QR from merchant site.
2. **App-in-App** (mobile) — redirect into MoMo app, return via
   Universal Link.

Also reachable via 2C2P (Sprint 31); this is the direct path.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `MomoAdapter.create_payment(invoice, mode)` spec first — RSA
  signature per MoMo public key; `mode ∈ {'qr', 'app'}`; currency
  locked VND.
- `MomoWebhookHandler.handle(payload)` spec first — RSA signature
  verify + idempotency by `orderId`.
- QR renderer spec first — MoMo QR payload (NAPAS QR standard since
  2023).

## Deliverables

### D1 — `vbwd-plugin-momo` backend

- Folder: `vbwd-plugin-momo/momo/`.
- `adapters/momo_adapter.py` — RSA-signed HTTP client.
- `services/momo_service.py` — invoice → MoMo request; VND-only
  guard; reconciliation.
- `routes.py`:
  - `POST /api/v1/momo/payments` — create; returns QR or deep-link
    per mode.
  - `POST /api/v1/momo/ipn` — MoMo IPN (webhook) receiver.
  - `GET /api/v1/momo/payments/:id/status` — polling.
  - `POST /api/v1/momo/payments/:id/refund` — refund.
- `models/momo_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-momo`

- `components/MomoQR.vue` — QR + countdown + auto-poll.
- `components/MomoDeepLink.vue` — mobile redirect.
- i18n: vi (primary), en.
- E2E: desktop QR, mobile deep-link.

### D3 — `vbwd-fe-admin-plugin-momo`

- Config: partner code, access key, secret key (masked), public key
  path for webhook verify.
- Transaction list + refund button.

### D4 — demo wiring

- Enable MoMo in `sea-saas` instance; seed VND-priced plan.

## Tests

- Unit: ≥ 22 backend, ≥ 12 frontend.
- Integration: ≥ 3 sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **RSA key management**: MoMo issues one public key per merchant
  for webhook verification. Rotate annually; plugin must log
  public-key fingerprint on startup.
- **Currency precision**: VND has no sub-unit; amounts must be
  integer. Validate at service layer.

## Effort estimate

- Backend: **1.5 days**
- fe-user: **0.75 day**
- fe-admin: **0.5 day**
- Demo wiring: **0.25 day**

**Total: ~3 person-days.**
