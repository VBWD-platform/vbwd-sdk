# Sprint 48 — Konbini (Japan cash voucher)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** Konbini (convenience-store cash) accounts for
~10% of Japanese e-commerce, est. USD 40B+/yr. 50K+ konbini outlets
(7-Eleven, Lawson, FamilyMart, Ministop, Seicomart). Used by Mercari,
DMM, Amazon JP.

**Repos touched:**
- `vbwd-plugin-konbini` (NEW — direct konbini issuance via acquirer)
- `vbwd-fe-user-plugin-konbini` (NEW — voucher display + "pay at
  konbini" instructions)
- `vbwd-fe-admin-plugin-konbini` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/jp-saas/` (existing from
  Sprint 47 — enable konbini)

## Goal

Direct konbini voucher issuance so Japanese merchants accept cash
payments at 50K+ convenience stores. Konbini payment infrastructure
is not a single API — it runs through acquirers like SB Payment
Service, DG Financial, or GMO PG. This plugin implements an acquirer
adapter pattern with SB Payment Service as the v1 concrete client.

Also reachable via Komoju — direct plugin for merchants with an SBPS
/ DG / GMO contract.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `IKonbiniAcquirer` abstract interface spec first — methods:
  `issue_voucher(invoice, chain_preference)`,
  `status(voucher_id)`, `cancel(voucher_id)`.
- `SbpsAcquirer` concrete implementation spec first — signed HTTPS
  with merchant private key; returns chain-specific payment code
  (7-Eleven, Lawson, FamilyMart, Ministop, Seicomart formats
  differ).
- `KonbiniWebhookHandler` spec first — receives `paid` or `expired`
  from acquirer; idempotent.
- Voucher-expiry reconciliation spec first — default 14-day expiry;
  `expired` transitions invoice to `voided`.

## Deliverables

### D1 — `vbwd-plugin-konbini` backend

- Folder: `vbwd-plugin-konbini/konbini/`.
- `adapters/base.py` — `IKonbiniAcquirer` interface.
- `adapters/sbps_acquirer.py` — SB Payment Service v1.
- `services/konbini_service.py` — invoice → voucher; per-chain
  code rendering; expiry reconciliation.
- `routes.py`:
  - `POST /api/v1/konbini/vouchers` — issue.
  - `POST /api/v1/konbini/webhooks/<acquirer>` — verified receiver.
  - `GET /api/v1/konbini/vouchers/:id/status` — polling.
- `models/konbini_voucher.py` — voucher_id, invoice_no, chain,
  payment_code, barcode, expires_at, status.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-konbini`

- `components/KonbiniVoucher.vue` — chain selector (7-Eleven /
  Lawson / FamilyMart / Ministop / Seicomart) + payment code +
  expiry countdown + printable instructions.
- PDF voucher download via core `PdfService` (Sprint 28) — one
  template per chain with the correct barcode format.
- i18n: ja (primary), en.
- E2E: voucher issuance happy path, expired-voucher UI.

### D3 — `vbwd-fe-admin-plugin-konbini`

- Config: acquirer selection + credentials (masked), chain
  allow-list.
- Voucher list with chain, code, status, expiry, customer.
- No refund — Japanese konbini cash refunds are manual bank
  transfers; document the workflow.

### D4 — demo wiring

- Enable konbini in `jp-saas` instance; seed a voucher-payable
  invoice.

## Tests

- Unit: ≥ 28 backend (5 chain code renderers + acquirer + service
  + webhook), ≥ 15 frontend.
- Integration: ≥ 4 SBPS sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Chain format drift**: each konbini chain has its own code
  format (some barcode, some numeric, some QR). Renderer must
  match exact chain specs or customer can't pay.
- **Acquirer onboarding**: SBPS / DG / GMO have weeks-long
  onboarding. Plugin doesn't try to abstract the differences —
  merchant picks one.

## Effort estimate

- Interface + SBPS acquirer: **2 days**
- Chain renderers + PDF templates: **1 day**
- Service + routes + webhook: **1 day**
- fe-user voucher display + PDF: **1 day**
- fe-admin: **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~6 person-days.**
