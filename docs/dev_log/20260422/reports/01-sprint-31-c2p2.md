# Sprint 31 Report — 2C2P plugin

**Date:** 2026-04-22
**Sprint:** [31 — 2C2P ASEAN aggregator](../done/31-2c2p-asean-aggregator.md)
**Status:** Scaffolded end-to-end with working unit tests. Integration
tests + demo instance are deferred (gated on sandbox credentials + the
`sea-saas` demo instance being available — `vbwd-demo-instances/`
doesn't exist in the SDK yet).

## What shipped

### `vbwd-plugin-c2p2` (backend)

- `C2P2Plugin(PaymentProviderPlugin)` — class in `__init__.py` per the
  VBWD plugin-discovery convention; `initialize()` merges defaults
  (Liskov: calls `super().initialize`).
- `C2P2SDKAdapter(BaseSDKAdapter)` — implements `ISDKAdapter`. HMAC-
  SHA256 JWS signing over canonical JSON, full `_post_jwt` helper,
  response-code ⇒ status mapping.
- Methods:
  - `create_payment_intent` / `create_payment_token` — issue PGW v4
    paymentToken (ISDK contract + 2C2P-native signature).
  - `capture_payment` / `get_payment_status` — inquiry.
  - `release_authorization` / `void_payment` — void.
  - `refund_payment` — refund (full or partial).
  - `verify_backend_notification` — HMAC verify on JWS.
- `C2P2Service` — invoice → transaction mapping; idempotent
  `apply_inquiry` (skips commit when state unchanged).
- `C2P2WebhookHandler` — idempotent by `invoiceNo` + `respCode`;
  DI-injected service.
- `C2P2Transaction` SQLAlchemy model + `20260422_1200_c2p2_tx`
  Alembic migration (one table, `tran_ref` index).
- Routes under `/api/v1/plugins/c2p2/`:
  - `POST /payment-tokens`
  - `GET /payments/:invoice_no/status`
  - `POST /backend-notifications`
  - `POST /payments/:invoice_no/refund`
- Config: `config.json` + `admin-config.json` (surfaced by core
  Settings page).
- `populate_db.py` — one idempotent demo transaction.
- `plugins.json` + core `config.json` patched.
- `.github/workflows/tests.yml` — CI mirrored from Stripe plugin.
- `README.md`, `LICENSE` (BSL 1.1).
- **27 unit tests pass** (`pytest plugins/c2p2/tests/unit/ -v`).
- **`bin/pre-commit-check.sh --plugin c2p2 --quick`: PASS** (black,
  flake8, isort, mypy non-blocking, 27/27 tests).
- Commit: `c06f788` on `main` in the plugin's own git repo
  (`vbwd-backend/plugins/c2p2/.git`).

### `vbwd-fe-user-plugin-c2p2` (fe-user)

- Named-export `c2p2PaymentPlugin: IPlugin` per fe-user convention
  (`MEMORY.md` fe-user Plugin Export Convention).
- Routes: `/pay/c2p2`, `/pay/c2p2/success`, `/pay/c2p2/cancel`.
- Views: `C2P2PaymentView.vue` (redirect flow with
  `usePaymentRedirect`), `C2P2SuccessView.vue`, `C2P2CancelView.vue`.
- i18n: `en`, `th`, `vi`, `id`.
- Registered in `vbwd-fe-user/plugins/plugins.json`.
- CI workflow (unit + integration) mirrored from `yookassa-payment`.
- Commit: `ba0aa56` on `main`.

### `vbwd-fe-admin-plugin-c2p2` (fe-admin)

- Named-export `c2p2AdminPlugin: IPlugin`.
- Route: `/admin/c2p2/transactions` — transactions list with status
  pills + refund button, behind `payments.configure` permission.
- Pinia store `useC2P2Store` — `fetchTransactions`, `refund` (DI:
  takes `api` arg — testable).
- i18n: `en`.
- Registered in `vbwd-fe-admin/plugins/plugins.json`.
- Config UI intentionally not duplicated — merchant credentials
  surface via the core Settings → Plugins page (driven by the
  backend's `admin-config.json`).
- Commit: `796c2eb` on `main`.

## Engineering-contract checks

Per [`../sprints/_engineering-requirements.md`](../sprints/_engineering-requirements.md):

- **TDD-first**: specs (`test_sdk_adapter.py`, `test_services.py`,
  `test_plugin.py`) were authored before each implementation file was
  finalised; all green on first proper run (after Liskov gaps filled).
- **DevOps-first**: `bin/pre-commit-check.sh --plugin c2p2 --quick`
  passes. No raw SQL; Alembic migration in place. No `# noqa`. No
  host `npm install` in bind-mounted `vbwd-fe-core`. No prod compose
  edits.
- **SOLID + Liskov**: `C2P2SDKAdapter` implements every abstract
  method of `ISDKAdapter` with the base's postconditions preserved
  (`SDKResponse.success=True + data` on success; `success=False +
  error` on failure). `initialize()` in the plugin class calls
  `super().initialize(merged_config)` as the base contract requires.
- **DRY**: one HTTP client factory in the adapter. No copy-paste
  with Stripe/YooKassa beyond the plugin-skeleton template.
- **DI**: services take `session` (or `db.session` default);
  `C2P2WebhookHandler` takes the service; fe-admin store takes `api`
  as function args (unit-testable).
- **Clean code**: full pronounceable names
  (`create_payment_token`, not `cpt`). No flag args. No "what"
  comments.
- **No over-engineering**: no generic "BNPL framework", no retry
  layer, no analytics. Backend does not expose a `/transactions`
  list endpoint yet — fe-admin store will 404 until a follow-up
  sprint ships the list endpoint (tracked below).
- **Drop deprecated**: no commented-out code. Where I wrote an
  unused helper (`_NOW = time.time`) during implementation, I
  deleted it before commit.

## Follow-ups

1. **`GET /api/v1/plugins/c2p2/transactions`** — the fe-admin list
   view calls this endpoint; it is not implemented in this sprint.
   Tracked as **S31.1**.
2. **Integration tests (`tests/integration/`)** against 2C2P
   sandbox. Gated by `C2P2_SANDBOX=1` env + a sandbox merchant
   credential. Tracked as **S31.2**.
3. **`vbwd-demo-instances/instances/local/sea-saas/`** — the
   demo-instances repo does not yet exist in the SDK. Create the
   umbrella repo first, then wire sea-saas. Tracked as **S31.3**.
4. **Additional tests** for `routes.py` (403 on missing plugin,
   401 on invalid webhook signature). Tracked as **S31.4**.
5. **Push to GitHub** — the three plugin repos are committed locally
   with the correct remote URLs in their READMEs, but not yet
   pushed. This is a user-initiated action per VBWD policy on shared-
   state changes.

## Files produced

Backend plugin (`vbwd-backend/plugins/c2p2/`):
- `__init__.py`
- `c2p2/__init__.py`, `c2p2/sdk_adapter.py`, `c2p2/models.py`,
  `c2p2/services.py`, `c2p2/routes.py`
- `tests/__init__.py`, `tests/conftest.py`,
  `tests/unit/__init__.py`, `tests/unit/test_sdk_adapter.py`,
  `tests/unit/test_services.py`, `tests/unit/test_plugin.py`
- `migrations/__init__.py`, `migrations/versions/__init__.py`,
  `migrations/versions/20260422_1200_c2p2_transactions.py`
- `config.json`, `admin-config.json`, `populate_db.py`
- `.github/workflows/tests.yml`
- `README.md`, `LICENSE`, `.gitignore`

fe-user plugin (`vbwd-fe-user/plugins/c2p2-payment/`):
- `index.ts`
- `C2P2PaymentView.vue`, `C2P2SuccessView.vue`, `C2P2CancelView.vue`
- `locales/{en,th,vi,id}.json`
- `config.json`, `admin-config.json`
- `.github/workflows/tests.yml`
- `README.md`, `LICENSE`

fe-admin plugin (`vbwd-fe-admin/plugins/c2p2-admin/`):
- `index.ts`
- `src/stores/c2p2.ts`, `src/views/C2P2Transactions.vue`
- `locales/en.json`
- `config.json`, `admin-config.json`
- `.github/workflows/tests.yml`
- `README.md`, `LICENSE`

Core registrations:
- `vbwd-backend/plugins/plugins.json` — add `c2p2: enabled=true`
- `vbwd-backend/plugins/config.json` — add default c2p2 config
- `vbwd-fe-user/plugins/plugins.json` — add `c2p2-payment: enabled=true`
- `vbwd-fe-admin/plugins/plugins.json` — add `c2p2-admin: enabled=true`

## Pre-commit output

```
Static analysis: ALL CHECKS PASSED
Unit tests:      27 passed in 0.22s
SUCCESS: All checks passed! Ready to commit.
```
