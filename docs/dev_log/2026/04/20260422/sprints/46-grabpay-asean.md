# Sprint 46 — GrabPay (pan-ASEAN wallet)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** GrabPay is the only pan-ASEAN wallet; 35M+
monthly transacting users. Used by Grab platform, 7-Eleven SG, KFC
ASEAN. Live in SG, MY, ID, PH, TH, VN.

**Repos touched:**
- `vbwd-plugin-grabpay` (NEW — direct GrabPay Partner API)
- `vbwd-fe-user-plugin-grabpay` (NEW — deep-link + QR)
- `vbwd-fe-admin-plugin-grabpay` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable)

## Goal

One plugin covers 6 ASEAN countries via GrabPay. Use cases: SEA SaaS
with regional customer base, cross-border creator platforms.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `GrabPayAdapter.create_charge(invoice, country)` spec first —
  signed with HMAC-SHA256; country-to-currency mapping
  (SGD/MYR/IDR/PHP/THB/VND); returns redirect + deep-link.
- `GrabPayWebhookHandler.handle(payload)` spec first — signature
  verify + idempotency.
- Cross-currency reconciliation spec first — GrabPay settles per-
  country; plugin logs currency per transaction, does not aggregate.

## Deliverables

### D1 — `vbwd-plugin-grabpay` backend

- Folder: `vbwd-plugin-grabpay/grabpay/`.
- `adapters/grabpay_adapter.py` — HMAC-signed client.
- `services/grabpay_service.py` — invoice → charge; country-to-
  currency enforcement; refund support.
- `routes.py`:
  - `POST /api/v1/grabpay/charges`
  - `POST /api/v1/grabpay/webhooks`
  - `GET /api/v1/grabpay/charges/:id/status`
  - `POST /api/v1/grabpay/charges/:id/refund`
- `models/grabpay_charge.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-grabpay`

- `components/GrabPayCheckout.vue` — mobile deep-link + desktop
  QR redirect.
- i18n: en, id, ms, th, vi, tl, zh-Hans.
- E2E: SG redirect, ID deep-link.

### D3 — `vbwd-fe-admin-plugin-grabpay`

- Config: partner ID, secret, country allow-list (6-country set).
- Transaction list with country column + refund button.

### D4 — demo wiring

- Enable GrabPay in `sea-saas` instance; seed per-country test
  customers.

## Tests

- Unit: ≥ 22 backend, ≥ 15 frontend.
- Integration: ≥ 4 sandbox round-trips (one per 2 countries).
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Partner onboarding**: GrabPay merchant onboarding takes 2-4
  weeks per country. Plugin must gracefully disable unconfigured
  countries.
- **Currency lock per country**: don't try to charge SGD to an ID
  user — GrabPay will reject. Service validates before call.

## Effort estimate

- Backend: **1.75 days**
- fe-user: **1 day**
- fe-admin: **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~3.75 person-days.**
