# Sprint 36 — iDEAL (Netherlands direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** iDEAL carries 70%+ of all Dutch online payments,
~1.1B transactions/yr, 15M users (≈90% of NL adults). See
[`payment-plugins-eu.md`](../../../dev_docs/market-research/payment-plugins-eu.md).

**Repos touched:**
- `vbwd-plugin-ideal` (NEW — direct iDEAL 2.0 API client)
- `vbwd-fe-user-plugin-ideal` (NEW — bank picker + redirect handling)
- `vbwd-fe-admin-plugin-ideal` (NEW — config + transaction list)
- `vbwd-demo-instances/instances/local/nl-shop/` (NEW — NL demo)

## Goal

Direct iDEAL 2.0 integration so Dutch merchants bypass aggregator
per-transaction fees. iDEAL is also reachable via Mollie (Sprint 30),
but merchants with ING / Rabo / ABN-AMRO direct merchant contracts
want the lower rate (typically EUR 0.18 vs EUR 0.29 via aggregator).

iDEAL 2.0 (launched 2024) replaces the per-bank picker with a single
unified flow — user enters IBAN or uses the iDEAL QR, no bank
selection screen. This sprint ships the 2.0 flow; legacy 1.0 is not
implemented (deprecated by Currence EOY 2025).

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `IdealAdapter.create_transaction(invoice)` spec first — verifies
  iDEAL 2.0 request signature (X.509 mutual-TLS), required fields
  (`entranceCode`, `purchaseId`, `amount`, `currency=EUR`,
  `language=nl|en`), and returns `issuerAuthenticationURL`.
- `IdealAdapter.status_request(transaction_id)` spec first — covers
  `Success`, `Cancelled`, `Expired`, `Failure`, `Open` state mappings.
- `IdealBlueprint.callback` spec first — the return-URL handler that
  confirms status via `status_request` (never trusts query string
  alone).

## Deliverables

### D1 — `vbwd-plugin-ideal` backend

- Folder per plugin convention in `MEMORY.md`: `vbwd-plugin-ideal/ideal/`.
- `adapters/ideal_adapter.py`:
  - TLS mutual-auth client (client cert + private key stored as env
    paths — never committed).
  - XML request signing per iDEAL 2.0 XMLSig spec.
  - Endpoints: `/directory`, `/transaction`, `/status`.
- `services/ideal_service.py` — invoice → iDEAL transaction mapping;
  entrance-code generation (RFC 4122 UUID, stripped of hyphens); status
  reconciliation.
- `routes.py`:
  - `POST /api/v1/ideal/transactions` — create, return
    `{ issuerUrl, transactionId, expires_at }`.
  - `GET /api/v1/ideal/callback?trxid=...&ec=...` — return-URL; calls
    `status_request` server-side, transitions invoice state.
  - `POST /api/v1/ideal/status/refresh` — cron-triggered reconciler
    for `Open` transactions older than 5 minutes.
- `models/ideal_transaction.py` — transaction_id, invoice_no,
  entrance_code, status, last_observed_status, issuer_id (if 1.0-style
  optional telemetry).
- Alembic migration for the one table.
- Implements `IPaymentAdapter`.
- Unit tests: XML sign/verify, status mapping, expiry handling.
- Integration tests gated by `IDEAL_SANDBOX=1` against iDEAL 2.0
  sandbox (Currence-issued test certs).

### D2 — `vbwd-fe-user-plugin-ideal`

- `components/IdealCheckout.vue` — minimal UI: "Pay with iDEAL" button
  → POST `/api/v1/ideal/transactions` → window.location to `issuerUrl`.
- No bank picker — iDEAL 2.0 handles that at Currence's page.
- `components/IdealReturn.vue` — post-redirect landing route that
  shows a progress spinner, polls `/api/v1/ideal/transactions/:id/status`,
  and routes to `/checkout/success` or `/checkout/failed`.
- i18n: nl (primary), en, de.
- Playwright E2E: happy path (sandbox Success), Cancelled (user
  aborts at issuer).

### D3 — `vbwd-fe-admin-plugin-ideal`

- Config: merchant ID, sub-ID, certificate paths (references to env —
  admin shows status, not key material), acquirer selector
  (ING / Rabobank / ABN-AMRO / Knab / others per Currence directory).
- Transaction list with status filter + manual status-refresh button.
- No refund UI — iDEAL does not support merchant-initiated refunds
  (must be done as a separate SEPA credit transfer; link to SEPA DD
  plugin from Sprint 29 and document the workflow).

### D4 — NL demo instance

- `vbwd-demo-instances/instances/local/nl-shop/` — localhost-only NL
  demo: backend + fe-user + fe-admin with iDEAL in sandbox.
- Seed: 1 admin, 1 NL customer, 3 products in EUR.
- README: "clone, `make up`, buy with iDEAL sandbox (any Bunq test
  issuer)".

## Tests

- Unit: ≥ 25 backend, ≥ 12 frontend.
- Integration: ≥ 4 iDEAL sandbox round-trips.
- E2E: 2 flows (Success, Cancelled).
- Verified via `bin/pre-commit-check.sh --full` before merge.

## Risks

- **Certificate rotation**: iDEAL client certs expire every 2 years.
  Plugin must log cert expiry at startup and emit a warning 60 days
  before expiry.
- **Refund story**: merchants will expect a "refund" button. UI must
  clearly state iDEAL has no refund API; merchant performs a SEPA
  credit transfer back to the payer. Link the SEPA DD plugin.
- **iDEAL 2.0 vs 1.0**: Mollie and some PSPs still speak 1.0. Our
  direct adapter is 2.0-only by design (1.0 deprecation EOY 2025 per
  Currence).

## Open questions

- [ ] **Q1** — iDEAL QR (mobile scan) as a secondary flow? Recommended
  **yes in v1** — same API, just a different `returnUrl` flag.
- [ ] **Q2** — fallback to Mollie when direct merchant creds missing?
  Recommended **no** — keep plugins single-purpose; merchant picks.

## Effort estimate

- Backend adapter + TLS + XMLSig + tests: **2 days**
- Services + routes + reconciler: **1 day**
- fe-user redirect + return polling: **0.75 day**
- fe-admin config + tx list: **0.75 day**
- NL demo instance: **0.25 day**

**Total: ~4.75 person-days.**
