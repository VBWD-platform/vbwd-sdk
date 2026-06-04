# Sprint 33 Report — Mercado Pago plugin

**Date:** 2026-04-22
**Sprint:** [33 — Mercado Pago LATAM](../done/33-mercado-pago-latam.md)
**Status:** Scaffolded end-to-end across 7 LATAM countries (BR/MX/AR/
CO/CL/UY/PE). 37 unit tests green. Integration tests + demo instance
deferred.

## What shipped

### `vbwd-plugin-mercado_pago` (backend)

- `MercadoPagoPlugin` — one plugin, per-country adapter selection.
  Country + currency enforcement at `create_payment_intent`
  (currency must match `COUNTRY_CURRENCY[country]`; unsupported
  country rejected). Liskov-safe deep-merge `initialize()` that
  recursively merges the nested `countries` config.
- `MercadoPagoSDKAdapter` — one instance per country, carrying its
  own access token + webhook secret. Implements full `ISDKAdapter`:
  - `create_preference` / `create_payment_intent` — posts
    `/checkout/preferences` with items, payer, back_urls,
    auto_return, notification_url, optional installments.
  - `get_payment_status` / `get_payment_status` — polls
    `/v1/payments/:id`.
  - `refund_payment` — posts `/v1/payments/:id/refunds`.
  - `verify_webhook` — HMAC-SHA256 on `x-signature`.
  - `capture_payment` / `release_authorization` — return
    well-formed `SDKResponse(success=False, error=…)` explaining
    why (Mercado Pago's preference flow captures on user
    redirect; no generic auth-hold). Preserves Liskov contract.
- `MercadoPagoService` — idempotent `apply_provider_update`.
  Correctly handles `mp_payment_id` as `str` regardless of whether
  MP returns int or string id.
- `compute_installment_plans(amount, country, card_brand,
  max_installments)` — per-country rules: BR 1-12, MX MSI
  3/6/9/12 for Visa/MC/Amex (else single-pay), Andean capped at 6.
- `MercadoPagoWebhookHandler` — accepts `external_reference` or
  `invoice_no` alias.
- `MercadoPagoPayment` model + Alembic migration
  `20260422_1400_mp` chain-follows `20260422_1300_truemoney`.
- Routes under `/api/v1/plugins/mercado-pago/`:
  - `POST /preferences` — country-routed
  - `GET /payments/:invoice/status` — country resolved from record
  - `POST /webhooks/:country` — country-keyed webhook
  - `POST /payments/:invoice/refund` — country resolved from record
- `config.json`, `admin-config.json` (tabbed per-country
  credentials + installment + voucher expiry), `populate_db.py`,
  README, LICENSE, `.gitignore`, CI workflow.
- Core `plugins.json` + `config.json` patched with 7-country
  default config.
- **37 unit tests pass**. `pre-commit-check.sh --plugin
  mercado_pago --quick` **PASS**.
- Commit: `79c26ab` on `main`.

### `vbwd-fe-user-plugin-mercado-pago` (fe-user)

- Named-export `mercadoPagoPaymentPlugin`.
- Routes: `/pay/mercado-pago`, `/pay/mercado-pago/success`,
  `/pay/mercado-pago/cancel`.
- `MercadoPagoPaymentView.vue` — creates a preference with
  `country`, `amount`, `currency`, `method`, `installments` from
  route query, then redirects to `init_point`.
- Locales: `en`, `pt` (Brazilian PT), `es` (pan-LATAM Spanish).
- CI workflow mirrored from `yookassa-payment`.
- Registered in `vbwd-fe-user/plugins/plugins.json`.
- Commit: `043e898`.

### `vbwd-fe-admin-plugin-mercado-pago` (fe-admin)

- Named-export `mercadoPagoAdminPlugin`.
- Route: `/admin/mercado-pago/payments` — list with per-country
  filter + refund action, behind `payments.configure` permission.
- Pinia store `useMercadoPagoStore` — `fetchPayments`,
  `filteredPayments` (computed), `refund` (all DI-passed `api`).
- Locales: `en`.
- Credentials live in core Settings → Plugins → Mercado Pago via
  backend's per-country `admin-config.json`.
- Registered in `vbwd-fe-admin/plugins/plugins.json`.
- Commit: `a2df12a`.

## Engineering-contract checks

Per [`../sprints/_engineering-requirements.md`](../sprints/_engineering-requirements.md):

- **TDD-first**: preference HTTP spec, 4xx/5xx/network branches,
  HMAC round-trip, installment per-country rules, service
  idempotency + int/str `mp_payment_id` normalisation, webhook
  handler fallback — **all authored before** the implementation
  was finalised. A first test run surfaced the int/str mismatch
  bug; fixed in-service (not in the test) and re-ran green.
- **DevOps-first**: `pre-commit-check.sh` green. Alembic migration
  chains the revision graph. No raw SQL. No `# noqa`. No host
  `npm install` in bind-mounted `vbwd-fe-core`. No prod-compose
  edits.
- **SOLID + Liskov**: `capture_payment` and `release_authorization`
  return well-formed `SDKResponse(success=False, error=…)` — do
  not raise, do not return `None`. `MercadoPagoPlugin.initialize`
  performs a deep merge and calls `super().initialize(merged)` —
  preserving the `BasePlugin` contract even with the nested
  `countries` dict.
- **DRY**: one HTTP helper `_post` / `_get` in the adapter;
  services share the same `_get_or_create` pattern as c2p2/truemoney
  but are NOT copy-pasted — each has its own state semantics.
- **DI**: all services take `session`; fe-admin store takes `api`.
- **Clean code**: `compute_installment_plans(amount, country,
  card_brand)` — full, pronounceable names. No flag args.
  Regulatory-rule comments only where relevant (MSI bin notes).
- **No over-engineering**: no generic "multi-country PSP routing
  framework"; the plugin dispatches adapters via a small
  dictionary of country configs. No retry layer. No analytics
  dashboard.
- **Drop deprecated**: the int/str bug surfaced during the first
  test run and was fixed by rewriting the comparison path, not
  by suppressing the failing assertion.

## Follow-ups

1. **`GET /api/v1/plugins/mercado-pago/payments`** — list endpoint
   for admin UI not implemented; tracked as **S33.1**.
2. **Per-country integration tests** gated by
   `MP_SANDBOX_BR=1`, `MP_SANDBOX_MX=1` etc. — **S33.2**.
3. **Pix QR rendering** for Brazilian merchants needing direct Pix
   QR (independent of Mercado Pago's hosted checkout). MP's
   preference response has a `point_of_interaction.transaction_data`
   with a Pix payload; surfacing that in fe-user is a follow-up —
   **S33.3** (or roll into Sprint 54 — Pix direct).
4. **Boleto / OXXO voucher rendering** via core `PdfService` from
   Sprint 28. MP returns `ticket_url` pointing to its own hosted
   voucher; VBWD-branded voucher PDF is **S33.4**.
5. **Installment rule editor** in fe-admin, keyed by card BIN.
   Current plugin uses a baseline; real MSI tables are bin-
   dependent and merchant-specific — **S33.5**.
6. **Push to GitHub** — three commits local, not pushed.

## Pre-commit output

```
Static analysis: ALL CHECKS PASSED
Unit tests:      37 passed in 0.23s
SUCCESS: All checks passed! Ready to commit.
```
