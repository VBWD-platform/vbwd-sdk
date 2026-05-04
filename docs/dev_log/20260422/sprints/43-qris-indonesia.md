# Sprint 43 — QRIS (Indonesia direct QR)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** QRIS is Indonesia's BI-standardised QR payment
scheme; all ID wallets (OVO, DANA, GoPay, ShopeePay, LinkAja) and
banks interoperate on it. 170M+ Indonesians with at least one
compatible wallet.

**Repos touched:**
- `vbwd-plugin-qris` (NEW — QRIS renderer + acquirer integration)
- `vbwd-fe-user-plugin-qris` (NEW — QR + poll UI)
- `vbwd-fe-admin-plugin-qris` (NEW — merchant config + tx list)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable)

## Goal

Single QR accepts every Indonesian wallet / bank. Merchant registers
as a QRIS Merchant (MPM — Merchant Presented Mode) with a QRIS
acquirer (BCA, Mandiri, BRI, BNI, or a PSP like Midtrans). This
plugin renders the dynamic-amount QR and reconciles via the
acquirer's webhook.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `QrisRenderer.render(merchant, amount, reference)` spec first —
  EMVCo QR per BI QRIS spec; MPM dynamic profile (tag 26 + 27 for
  acquirer data); CRC16 snapshot.
- Acquirer adapter tests for Midtrans QRIS + BCA QRIS (launch set).
- `QrisWebhookHandler` signature verification + idempotency.

## Deliverables

### D1 — `vbwd-plugin-qris` backend

- Folder: `vbwd-plugin-qris/qris/`.
- `adapters/qris_renderer.py` — dynamic QRIS builder.
- `adapters/acquirer_clients/midtrans_qris.py`, `bca_qris.py` —
  per-acquirer issuance + reconciliation.
- `services/qris_service.py` — invoice → QRIS + reconciliation.
- `routes.py`:
  - `POST /api/v1/qris/payments` — issue QR.
  - `GET /api/v1/qris/payments/:id/status` — polling.
  - `POST /api/v1/qris/webhooks/<acquirer>` — per-acquirer receiver.
- `models/qris_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-qris`

- `components/QrisQR.vue` — QR + 15-min countdown + wallet-app
  deep-link on mobile + auto-poll.
- i18n: id (primary), en.
- E2E: happy path, timeout.

### D3 — `vbwd-fe-admin-plugin-qris`

- Config: merchant NMID (from BI), acquirer selection + credentials
  (masked).
- Transaction list + refund UI (QRIS refunds route through
  acquirer).

### D4 — demo wiring

- Enable QRIS in `sea-saas` instance; seed IDR-priced plan.

## Tests

- Unit: ≥ 25 backend, ≥ 12 frontend.
- Integration: ≥ 4 acquirer-sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **NMID vs MID**: Indonesian QRIS uses NMID (National Merchant ID)
  distinct from per-acquirer MID. Plugin must store both.
- **Cross-border QRIS**: Indonesia has live QRIS-interop with
  Singapore, Thailand, Malaysia. Defer cross-border to S43.1 —
  domestic-only in v1.

## Effort estimate

- QR renderer: **0.5 day**
- Acquirer adapters (Midtrans + BCA): **1.5 days**
- Service + routes + webhooks: **1 day**
- fe-user: **0.75 day**
- fe-admin: **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~4.75 person-days.**
