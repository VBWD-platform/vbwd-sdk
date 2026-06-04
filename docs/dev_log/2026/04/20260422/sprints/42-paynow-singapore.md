# Sprint 42 — PayNow (Singapore direct QR)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** PayNow is Singapore's national real-time retail
rail. Most SG banks support API issuance and reconciliation.

**Repos touched:**
- `vbwd-plugin-paynow` (NEW — direct PayNow QR renderer +
  reconciliation)
- `vbwd-fe-user-plugin-paynow` (NEW — QR + poll UI)
- `vbwd-fe-admin-plugin-paynow` (NEW — PayNow config + reconciliation)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable
  PayNow direct)

## Goal

Direct PayNow QR issuance + bank reconciliation for SG merchants.
Similar economic motivation as PromptPay (Sprint 41) — bypass
aggregator fees and receive instant settlement to SG corporate bank
account (UEN-linked PayNow ID).

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `PayNowQRRenderer.render(uen, amount, reference)` spec first —
  SGQR payload per Singapore Payments Council spec; covers static +
  dynamic QR; CRC16 snapshot.
- Bank adapter tests for DBS + OCBC (launch set).
- `PayNowReconciler.match(payment, bank_tx)` spec first.

## Deliverables

### D1 — `vbwd-plugin-paynow` backend

- Folder: `vbwd-plugin-paynow/paynow/`.
- `adapters/qr_renderer.py` — SGQR builder.
- `adapters/bank_clients/dbs.py`, `ocbc.py` — bank reconciliation
  clients (DBS IDEAL API, OCBC Velocity API).
- `services/paynow_service.py` — invoice → QR + reconciliation.
- `routes.py`:
  - `POST /api/v1/paynow/payments` — issue QR.
  - `GET /api/v1/paynow/payments/:id/status` — polling.
  - `POST /api/v1/paynow/webhooks/<bank>` — per-bank receiver.
- `models/paynow_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-paynow`

- `components/PayNowQR.vue` — QR + 10-min countdown + bank-app
  deep-link on mobile; auto-poll.
- i18n: en (primary), zh-Hans, zh-Hant, ta.
- E2E: happy path, timeout.

### D3 — `vbwd-fe-admin-plugin-paynow`

- Config: merchant UEN, PayNow ID, supported banks, reconciliation
  mode (webhook vs polling), bank credentials (masked).
- Reconciliation dashboard as in Sprint 41.

### D4 — demo wiring

- Enable PayNow in `sea-saas` instance; seed SGD-priced plan.

## Tests

- Unit: ≥ 25 backend, ≥ 12 frontend.
- Integration: ≥ 4 bank-sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **UEN validation**: Singapore UEN has well-defined checksum; validate
  at admin config save time.
- **Corporate PayNow setup**: merchant needs PayNow Corporate (not
  retail) linked to their UEN before this plugin can issue QRs.
  Document in README.

## Effort estimate

- QR renderer: **0.5 day**
- Bank adapters (DBS + OCBC) + reconciler: **1.5 days**
- Service + routes + webhooks: **1 day**
- fe-user: **0.75 day**
- fe-admin: **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~4.75 person-days.**
