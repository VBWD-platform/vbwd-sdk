# Sprint 40 — SOFORT / Klarna Bank Transfer (DACH bank redirect)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** SOFORT (now "Klarna Sofort") is a DACH bank-
redirect rail used heavily for B2B and cautious-consumer e-commerce;
user authenticates to their online-banking and confirms a transfer.
Common in DE/AT/CH/IT/BE/NL/PL. Also reachable via Klarna (Sprint 29);
this sprint ships a dedicated plugin when merchants want SOFORT-only
without the Klarna checkout experience.

**Repos touched:**
- `vbwd-plugin-sofort` (NEW — SOFORT / Klarna Sofort API)
- `vbwd-fe-user-plugin-sofort` (NEW — bank picker + redirect)
- `vbwd-fe-admin-plugin-sofort` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/dach-shop/` (existing from
  Sprint 29 — enable SOFORT alongside Klarna)

## Goal

Single-method SOFORT plugin that lets merchants accept bank transfers
via customer online-banking without bundling the full Klarna checkout
widget. Used in DACH B2B e-commerce, deposits, regulated sectors
(gambling, travel) where SOFORT is a compliance-friendly rail.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `SofortAdapter.create_payment(invoice, country)` spec first — tests
  country mapping (DE/AT/CH/IT/BE/NL/PL), currency EUR (CHF for CH),
  returns `payment_url`.
- `SofortAdapter.status(transaction_id)` spec first — covers
  `received`, `pending`, `refunded`, `loss`, `untraceable` states.
- Idempotent webhook handler via `transaction_id`.

## Deliverables

### D1 — `vbwd-plugin-sofort` backend

- Folder: `vbwd-plugin-sofort/sofort/`.
- `adapters/sofort_adapter.py` — uses Klarna's Sofort API
  (`api.sofort.com/api/xml`) or REST replacement.
- `services/sofort_service.py` — invoice mapping; country/currency
  guard; reconciliation.
- `routes.py`:
  - `POST /api/v1/sofort/payments` — create, returns `payment_url`.
  - `POST /api/v1/sofort/webhooks` — verified webhook receiver.
  - `GET /api/v1/sofort/payments/:id/status` — polling.
- `models/sofort_transaction.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-sofort`

- `components/SofortRedirect.vue` — "Pay by bank transfer (SOFORT)"
  button → `window.location` to `payment_url`.
- `components/SofortReturn.vue` — post-redirect landing with
  status polling.
- i18n: de, en, nl, it, pl.
- E2E: DE happy-path, CH CHF happy-path.

### D3 — `vbwd-fe-admin-plugin-sofort`

- Config: customer number, project ID, API key (masked).
- Country allow-list: DE, AT, CH, IT, BE, NL, PL.
- Transaction list.

### D4 — demo wiring

- Enable SOFORT in the `dach-shop` instance (Sprint 29). Document
  "Klarna vs SOFORT-only" trade-off in the instance README.

## Tests

- Unit: ≥ 22 backend, ≥ 10 frontend.
- Integration: ≥ 3 sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Deprecation**: Klarna has been gradually folding SOFORT into the
  main Klarna checkout. Monitor the Klarna roadmap; if SOFORT-as-a-
  standalone-API is sunset, this plugin becomes thin glue over the
  Klarna plugin's "Pay Now" path — document the migration plan.
- **Settlement timing**: SOFORT confirmations arrive within 2s but
  settlement is next-business-day. UI copy must match.

## Effort estimate

- Backend: **1.5 days**
- fe-user: **0.75 day**
- fe-admin: **0.5 day**
- Demo wiring: **0.25 day**

**Total: ~3 person-days.**
