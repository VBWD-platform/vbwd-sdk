# Sprint 39 — BLIK (Poland direct, non-P24)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** BLIK is a Polish national payment scheme
(operated by Polski Standard Płatności) that lives independently of
P24 / Stripe / aggregators. Direct BLIK merchant access gives the
lowest rate. BLIK 2023 volume: ~1.7B transactions.

**Repos touched:**
- `vbwd-plugin-blik` (NEW — direct BLIK merchant API)
- `vbwd-fe-user-plugin-blik` (NEW — 6-digit code input)
- `vbwd-fe-admin-plugin-blik` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/pl-shop/` (existing from Sprint
  38 — enable direct BLIK alongside P24)

## Goal

Direct BLIK integration for Polish merchants with a PSP-less merchant
agreement (via their issuing bank). Parallel to the BLIK-through-P24
path in Sprint 38 — merchant picks one based on their acquirer
relationship.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `BlikAdapter.authorize(code, amount, reference)` spec first —
  posts to merchant bank's BLIK endpoint; handles `pending`,
  `accepted`, `rejected`, `timeout` states.
- `BlikAdapter.cancel(reference)` spec first — cancellation window
  before user confirmation in the bank app.
- Time-to-live invariant: BLIK codes are valid 2 minutes; UI and
  backend must agree on the same expiry window.

## Deliverables

### D1 — `vbwd-plugin-blik` backend

- Folder: `vbwd-plugin-blik/blik/`.
- `adapters/blik_adapter.py` — adapter pattern supporting 1+
  acquirer bank APIs (config-driven; default to the merchant's
  configured bank endpoint).
- `services/blik_service.py` — invoice mapping + timeout management.
- `routes.py`:
  - `POST /api/v1/blik/authorize` — submit 6-digit code.
  - `GET /api/v1/blik/:reference/status` — polling.
  - `POST /api/v1/blik/:reference/cancel` — user cancellation.
- `models/blik_transaction.py` — reference, code_hash, invoice_no,
  status, expires_at.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-blik`

- `components/BlikCodeEntry.vue` — 6-digit masked input with 2-minute
  countdown + "Regenerate in app" reminder.
- Auto-poll `/status` every 2 s for up to 120 s.
- i18n: pl, en.
- E2E: happy-path accept, timeout, user-rejected-in-app.

### D3 — `vbwd-fe-admin-plugin-blik`

- Config: acquirer endpoint, merchant cert, acceptor ID.
- Transaction list with status + reference.

### D4 — demo wiring

- Enable BLIK direct in the `pl-shop` instance alongside P24-BLIK
  (Sprint 38); document the two-paths in the instance README.

## Tests

- Unit: ≥ 20 backend, ≥ 10 frontend.
- Integration: ≥ 3 sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Fragmented sandboxes**: each Polish acquirer has their own BLIK
  sandbox. Pick one (PKO BP or ING) for v1 and document; others
  ship as S39.1+.
- **Code reuse with Sprint 38**: keep BLIK-through-P24 and direct
  BLIK as two separate plugins — no shared adapter code. Merchant
  enables one or the other, not both.

## Effort estimate

- Backend: **1.5 days**
- fe-user: **0.75 day**
- fe-admin: **0.5 day**
- Demo wiring: **0.25 day**

**Total: ~3 person-days.**
