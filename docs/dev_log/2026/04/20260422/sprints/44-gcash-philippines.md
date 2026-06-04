# Sprint 44 — GCash (Philippines direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** GCash is the #1 Philippines wallet — 76M users
(~60% of adults), USD 100B+ TPV (2023 disclosed). Dominant in Shopee
PH, Lazada PH, Jollibee, SM Retail.

**Repos touched:**
- `vbwd-plugin-gcash` (NEW — direct GCash Merchant API)
- `vbwd-fe-user-plugin-gcash` (NEW — redirect + deep-link UI)
- `vbwd-fe-admin-plugin-gcash` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable)

## Goal

Direct GCash integration for PH merchants with an approved G-Xchange
merchant agreement. Two flows:
1. **Redirect** (desktop default) — redirect to GCash hosted page
   where user authenticates via mobile + OTP.
2. **Deep-link** (mobile default) — open `gcash://` intent, return
   via Universal Link.

GCash is also reachable via 2C2P (Sprint 31); this direct plugin is
for merchants who want lower rates / direct settlement.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `GcashAdapter.create_payment(invoice)` spec first — HMAC request
  signature, required fields (merchant_id, transaction_ref,
  amount, currency=PHP), returns redirect URL + deep-link.
- `GcashWebhookHandler.handle(payload)` spec first — signature
  verification + idempotency by `transaction_ref`.
- Status polling endpoint spec first.

## Deliverables

### D1 — `vbwd-plugin-gcash` backend

- Folder: `vbwd-plugin-gcash/gcash/`.
- `adapters/gcash_adapter.py` — HMAC-signed HTTP client.
- `services/gcash_service.py` — invoice mapping; currency locked to
  PHP; reconciliation.
- `routes.py`:
  - `POST /api/v1/gcash/payments` — create; returns redirect + deep.
  - `POST /api/v1/gcash/webhooks` — verified receiver.
  - `GET /api/v1/gcash/payments/:id/status` — polling.
  - `POST /api/v1/gcash/payments/:id/refund` — refund (GCash
    supports within 180 days).
- `models/gcash_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-gcash`

- `components/GcashCheckout.vue` — device-aware button: mobile
  deep-link (primary) + desktop redirect.
- `components/GcashReturn.vue` — status polling post-redirect.
- i18n: en, tl (Filipino).
- E2E: desktop redirect, mobile deep-link fallback to redirect.

### D3 — `vbwd-fe-admin-plugin-gcash`

- Config: merchant ID, secret key (masked), test/live.
- Transaction list with refund button.

### D4 — demo wiring

- Enable GCash in `sea-saas` instance; seed PHP-priced plan.

## Tests

- Unit: ≥ 22 backend, ≥ 12 frontend.
- Integration: ≥ 3 sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Deep-link fallback**: if GCash app not installed, deep-link
  silently fails on iOS. UI offers 5-s timeout + fallback to
  redirect.
- **G-Xchange onboarding**: merchant must have a GCash Business /
  Enterprise account. Document prerequisites in plugin README.

## Effort estimate

- Backend: **1.5 days**
- fe-user: **0.75 day**
- fe-admin: **0.5 day**
- Demo wiring: **0.25 day**

**Total: ~3 person-days.**
