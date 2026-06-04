# Sprint 32 Report — TrueMoney plugin

**Date:** 2026-04-22
**Sprint:** [32 — TrueMoney Thailand direct](../done/32-truemoney-thailand-wallet.md)
**Status:** Scaffolded end-to-end with working unit tests +
pre-commit green. Integration tests + demo instance deferred
(sandbox credential gating + `sea-saas` instance not yet created).

## What shipped

### `vbwd-plugin-truemoney` (backend)

- `TrueMoneyPlugin(PaymentProviderPlugin)` — THB-only guard at
  `create_payment_intent`; Liskov-compliant `initialize` (merges
  defaults then calls `super().initialize(merged)`).
- `TrueMoneySDKAdapter(BaseSDKAdapter)` implementing full
  `ISDKAdapter` contract:
  - `create_transaction` / `create_payment_intent` — HMAC-SHA256
    signed POST, returns `{ transaction_id, qr_payload, deep_link,
    expires_at }`.
  - `get_transaction_status` / `capture_payment` / `get_payment_status`.
  - `refund_payment` with idempotency-key kwarg.
  - `release_authorization` — returns `SDKResponse(success=False)`
    with a clear message (TrueMoney has no auth-hold capability).
  - `render_qr_payload` — EMVCo builder with CRC16/CCITT-FALSE
    (NAPAS QR since 2023). Snapshot-tested.
  - `verify_webhook` — HMAC-SHA256 equality check
    (`hmac.compare_digest`).
- `TrueMoneyService` — idempotent
  `apply_provider_update(invoice_no, payload)` — only commits when
  status or `last_provider_status` changes.
- `TrueMoneyWebhookHandler` — accepts both `invoice_no` and
  `invoiceNo` (TrueMoney documentation is inconsistent across
  regions).
- `TrueMoneyTransaction` SQLAlchemy model + Alembic migration
  `20260422_1300_truemoney` (chains after `20260422_1200_c2p2_tx`).
- Routes under `/api/v1/plugins/truemoney/`:
  - `POST /transactions`
  - `GET /transactions/:invoice/status`
  - `POST /webhooks`
  - `POST /transactions/:invoice/refund`
- `config.json`, `admin-config.json`, `populate_db.py` (idempotent),
  README, LICENSE, `.gitignore`, `.github/workflows/tests.yml`.
- `plugins.json` + core `config.json` patched.
- **30 unit tests pass**; `pre-commit-check.sh --plugin truemoney
  --quick` **PASS** (black, flake8, isort, mypy non-blocking per
  plugin convention).
- Commit: `826917d` on `main` in the plugin's own git repo.

### `vbwd-fe-user-plugin-truemoney` (fe-user)

- Named-export `trueMoneyPaymentPlugin: IPlugin`.
- Routes: `/pay/truemoney`, `/pay/truemoney/success`,
  `/pay/truemoney/cancel`.
- `TrueMoneyPaymentView.vue` — QR payload display, deep-link button,
  auto-poll `/status` every 3 s, routes to success/cancel on
  terminal state. `onBeforeUnmount` clears the timer (no leak).
- `TrueMoneySuccessView.vue`, `TrueMoneyCancelView.vue`.
- Locales: `en`, `th`.
- CI workflow mirrored from `yookassa-payment`.
- Registered in `vbwd-fe-user/plugins/plugins.json`.
- Commit: `d30d6c9`.

### `vbwd-fe-admin-plugin-truemoney` (fe-admin)

- Named-export `trueMoneyAdminPlugin: IPlugin`.
- Route: `/admin/truemoney/transactions` — list with refund button,
  behind `payments.configure` permission.
- Pinia store `useTrueMoneyStore` — `fetchTransactions(api)` and
  `refund(invoiceNo, amount, api)` both take `api` as argument (DI,
  testable without Vite).
- Locales: `en`.
- Config is delegated to the core Settings → Plugins page via the
  backend's `admin-config.json`.
- Registered in `vbwd-fe-admin/plugins/plugins.json`.
- Commit: `34fbc44`.

## Engineering-contract checks

Per [`../sprints/_engineering-requirements.md`](../sprints/_engineering-requirements.md):

- **TDD-first**: QR CRC snapshot + HMAC verify + status mapping +
  webhook idempotency specs authored first. All 30 pass on clean run.
- **DevOps-first**: `pre-commit-check.sh` green. Alembic migration
  chains the global revision graph (20260422_1300 → 20260422_1200).
  No raw SQL. No `# noqa`. No host `npm install` in bind-mounted
  `vbwd-fe-core`. No prod-compose edits.
- **SOLID + Liskov**: every `ISDKAdapter` abstract method
  implemented; `release_authorization` returns a well-formed
  `SDKResponse(success=False, error=...)` — does not raise, does
  not return `None`, preserving the base contract.
  `Plugin.initialize()` merges defaults then calls
  `super().initialize(merged)` — the Liskov rule for `BasePlugin`.
- **DRY**: one HTTP factory in the adapter; QR payload built with a
  local `_tlv()` helper; no copy-paste with the 2C2P adapter
  (intentional — different APIs, different signing, promotion would
  be premature).
- **DI**: service takes `session`; webhook handler takes service;
  fe-admin store takes `api`. No module-level singletons.
- **Clean code**: `render_qr_payload`, `verify_webhook` — full
  pronounceable names. No flag args. No "what" comments.
- **No over-engineering**: no generic QR framework (2C2P has its own
  EMVCo renderer in its adapter — two copies is fine at N=2; promote
  on third consumer). No retry layer beyond single 30 s timeout. No
  analytics dashboard.
- **Drop deprecated**: the original flake8 warnings (`F401`, `F541`)
  were fixed by deleting the unused `pytest` import and removing the
  empty f-string prefix — not by suppressing.

## Follow-ups

1. **`GET /api/v1/plugins/truemoney/transactions`** — list endpoint
   for the admin UI is not implemented; tracked as **S32.1**.
2. **Integration tests** gated by `TRUEMONEY_SANDBOX=1`. TrueMoney
   Merchant API sandbox requires business onboarding — tracked as
   **S32.2**.
3. **Bank SFTP / CNAB reconciliation** if a merchant requests a
   non-webhook reconciliation path — **S32.3**.
4. **QR expiry cron reconciler** to flip `pending → expired` without
   waiting for the provider webhook — **S32.4**.
5. **Push to GitHub** — three local commits on `main` in each
   plugin; not yet pushed. User-initiated action.

## Pre-commit output

```
Static analysis: ALL CHECKS PASSED
Unit tests:      30 passed in 0.23s
SUCCESS: All checks passed! Ready to commit.
```
