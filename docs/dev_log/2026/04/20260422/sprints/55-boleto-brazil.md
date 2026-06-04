# Sprint 55 — Boleto Bancário (Brazil direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** Boleto Bancário is Brazil's legacy cash-voucher
rail; declining but still essential for B2B invoicing, government,
utilities, and "un-banked" BR customers. est. USD 60B+/yr. Universal
in BR.

**Repos touched:**
- `vbwd-plugin-boleto` (NEW — Boleto issuance via bank APIs)
- `vbwd-fe-user-plugin-boleto` (NEW — voucher display + PDF)
- `vbwd-fe-admin-plugin-boleto` (NEW — config + tx list +
  reconciliation dashboard)
- `vbwd-demo-instances/instances/local/br-shop/` (existing from
  Sprint 54 — enable)

## Goal

Direct Boleto issuance so BR merchants avoid aggregator per-boleto
fees. Issuance runs through the merchant's corporate bank (Itaú,
Bradesco, Banco do Brasil, Santander, Caixa) via their Cobrança API.
Reconciliation via CNAB 240 / 400 file retrieval or API webhook.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `IBoletoBank` interface spec first — `issue(invoice, due_date)`,
  `query(nosso_numero)`, `cancel(nosso_numero)`.
- `ItauBoletoBank`, `BancoDoBrasilBoletoBank` concrete clients —
  OAuth2 + mTLS; "nosso número" generation per-bank rules.
- `BoletoPdfRenderer.render(boleto)` spec first — standard BR
  boleto layout with ITF-14 barcode + digitable line.
- `BoletoReconciler.match(cnab_line, boleto)` spec first — CNAB 240
  parser.

## Deliverables

### D1 — `vbwd-plugin-boleto` backend

- Folder: `vbwd-plugin-boleto/boleto/`.
- `adapters/base.py` — `IBoletoBank`.
- `adapters/itau.py`, `adapters/banco_do_brasil.py` — launch set.
- `adapters/cnab_parser.py` — CNAB 240 + 400 parser.
- `services/boleto_service.py` — invoice → boleto; due date;
  digitable-line + barcode generation; reconciliation pipeline.
- `routes.py`:
  - `POST /api/v1/boleto/issue`
  - `GET /api/v1/boleto/:id/pdf` — PDF download via core
    `PdfService` (Sprint 28).
  - `POST /api/v1/boleto/webhooks/<bank>` — bank webhooks.
  - `POST /api/v1/boleto/cnab/import` — admin-triggered CNAB file
    upload for reconciliation.
- `models/boleto.py` — nosso_numero, invoice_no, bank, due_date,
  amount, digitable_line, barcode, status.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-boleto`

- `components/BoletoView.vue` — digitable line (copy button) +
  barcode + due date + "Download PDF" button.
- Auto-poll status until due date.
- i18n: pt-BR, en.
- E2E: issuance happy path, PDF download.

### D3 — `vbwd-fe-admin-plugin-boleto`

- Config: bank selector, merchant credentials (masked), "carteira"
  (portfolio) number.
- Boleto list with status, due date, digitable line.
- CNAB upload UI with dry-run preview before commit.

### D4 — demo wiring

- Enable Boleto in `br-shop` instance alongside Pix; seed a
  boleto-payable invoice.

## Tests

- Unit: ≥ 35 backend (2 bank adapters + CNAB parser + PDF
  renderer), ≥ 15 frontend.
- Integration: ≥ 4 bank sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Digitable-line math**: boleto digitable-line has a 47-digit
  structure with 3 check digits (DAC). Wrong math = boleto
  rejected at the bank window. Snapshot tests against bank-
  published reference boletos.
- **Bank-API heterogeneity**: each BR bank has a different API
  style. `IBoletoBank` abstracts; ship Itaú + BB in v1, others
  incrementally.
- **CNAB format variants**: CNAB 240 vs 400, and per-bank
  dialects. Parser must be tested against real files from each
  bank.

## Effort estimate

- Base interface + PDF renderer: **0.75 day**
- 2 bank adapters + CNAB parser: **3 days**
- Service + routes + reconciler: **1.5 days**
- fe-user view: **0.75 day**
- fe-admin + CNAB upload: **1.25 days**
- Demo wiring: **0.25 day**

**Total: ~7.5 person-days.**
