# Sprint 56 — PSE (Colombia direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** PSE (Pagos Seguros en Línea) is Colombia's
national bank-redirect rail — 70%+ of online payments, 18M+ bank
customers. Operated by ACH Colombia. Used by Rappi CO, Falabella,
government.

**Repos touched:**
- `vbwd-plugin-pse` (NEW — direct ACH Colombia PSE API or via a
  PSP like Wompi or ePayco)
- `vbwd-fe-user-plugin-pse` (NEW — bank picker + redirect)
- `vbwd-fe-admin-plugin-pse` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/co-shop/` (NEW — CO demo)

## Goal

Direct PSE integration for Colombian merchants. PSE requires either
a direct ACH Colombia contract (large enterprises) or a PSP agreement
(Wompi, ePayco, PayU). This sprint uses the PSP-abstraction pattern
with Wompi + ePayco as v1 clients.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `IPsePspAdapter` interface spec first — `create_transaction`,
  `get_status`, `list_banks`.
- `WompiPseAdapter`, `EpaycoPseAdapter` concrete — HMAC or HS512
  signed HTTP clients; COP-only currency guard.
- `PseWebhookHandler` spec first — signature verify + idempotency.

## Deliverables

### D1 — `vbwd-plugin-pse` backend

- Folder: `vbwd-plugin-pse/pse/`.
- `adapters/base.py`, `adapters/wompi.py`, `adapters/epayco.py`.
- `services/pse_service.py` — invoice → transaction; bank list
  cache (refresh nightly); reconciliation.
- `routes.py`:
  - `GET /api/v1/pse/banks` — list of PSE-participating banks.
  - `POST /api/v1/pse/transactions` — create; returns redirect
    URL.
  - `POST /api/v1/pse/webhooks/<psp>` — per-PSP receiver.
  - `GET /api/v1/pse/transactions/:id/status` — polling.
- `models/pse_transaction.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-pse`

- `components/PseBankPicker.vue` — bank grid from backend.
- `components/PseRedirect.vue` — redirect to PSP URL.
- `components/PseReturn.vue` — status polling post-return.
- i18n: es-CO, en.
- E2E: happy path, user-cancelled.

### D3 — `vbwd-fe-admin-plugin-pse`

- Config: PSP selector, merchant credentials (masked).
- Transaction list with bank column.

### D4 — CO demo instance

- `vbwd-demo-instances/instances/local/co-shop/` with PSE enabled
  via Wompi sandbox; seed COP-priced products.

## Tests

- Unit: ≥ 25 backend, ≥ 12 frontend.
- Integration: ≥ 4 PSP sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Bank downtime**: some Colombian banks' PSE integration has
  scheduled maintenance windows. Plugin does not retry across
  banks — user returns with "banco no disponible" and is offered
  a retry button.
- **Person vs business flow**: PSE distinguishes natural person vs
  legal entity at form-fill time. Plugin surfaces this in the
  bank-picker.

## Effort estimate

- Base interface + 2 PSP adapters: **2 days**
- Service + routes + webhook: **1 day**
- fe-user: **1 day**
- fe-admin: **0.75 day**
- CO demo: **0.5 day**

**Total: ~5.25 person-days.**
