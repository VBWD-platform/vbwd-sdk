# Sprint 52 — Alipay / Alipay+ (China + regional tourist wallets)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** Alipay has ~1B global users; Alipay+ aggregates
Alipay itself + regional wallets (Kakao Pay, Touch 'n Go, GCash,
AlipayHK, TrueMoney, Rabbit LINE Pay, DANA, EasyPaisa, bKash,
Mercado Pago via partnership). For merchants serving Chinese tourists
or pan-Asian traffic, this is the highest-leverage single plugin.

**Repos touched:**
- `vbwd-plugin-alipay` (NEW — direct Alipay + Alipay+ unified)
- `vbwd-fe-user-plugin-alipay` (NEW — QR + deep-link)
- `vbwd-fe-admin-plugin-alipay` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable)

## Goal

Accept Alipay QR (cross-border desktop) and Alipay+ for in-region
mobile customers across Asia. Single plugin, one merchant agreement
with Ant International.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `AlipayAdapter.create_payment(invoice, scenario)` spec first —
  RSA-2048 signature per Alipay OpenAPI v3; scenarios:
  `WEB_ORDER` (QR), `IN_APP` (deep-link), `ENTRY_CODE` (POS-style).
- `AlipayAdapter.verify_webhook(payload, signature)` spec first —
  RSA public-key verify; idempotency by `out_trade_no`.
- Multi-currency (CNY + HKD + SGD + MYR + THB + IDR + PHP + AUD +
  KRW + JPY): adapter validates merchant-enabled currency set.

## Deliverables

### D1 — `vbwd-plugin-alipay` backend

- Folder: `vbwd-plugin-alipay/alipay/`.
- `adapters/alipay_adapter.py` — RSA-signed OpenAPI v3 client;
  auto-selects `alipay.trade.*` for CN vs `ams.alipayplus.*` for
  cross-border / regional.
- `services/alipay_service.py` — invoice mapping + currency lookup +
  scenario routing.
- `routes.py`:
  - `POST /api/v1/alipay/payments` — create (QR or deep-link).
  - `POST /api/v1/alipay/webhooks` — verified receiver.
  - `GET /api/v1/alipay/payments/:id/status` — polling.
  - `POST /api/v1/alipay/payments/:id/refund` — refund.
- `models/alipay_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-alipay`

- `components/AlipayQR.vue` — desktop QR + auto-poll.
- `components/AlipayDeepLink.vue` — mobile deep-link (detects
  regional variant: alipayhk://, tngd://, etc. for Alipay+).
- i18n: zh-Hans, zh-Hant, en, ja, ko, th.
- E2E: QR + deep-link happy paths.

### D3 — `vbwd-fe-admin-plugin-alipay`

- Config: merchant ID, app ID, RSA private key path, Alipay public
  key path, enabled wallet regions (for Alipay+).
- Transaction list with wallet column + refund button.

### D4 — demo wiring

- Enable Alipay in `sea-saas` instance; seed HKD-priced plan.

## Tests

- Unit: ≥ 30 backend, ≥ 15 frontend.
- Integration: ≥ 4 Alipay sandbox round-trips (CN + 2 regions).
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Key rotation**: RSA keys from Alipay rotate on merchant
  request. Plugin logs active key fingerprint at startup.
- **Alipay+ scope**: Alipay+ partner wallet list grows quarterly.
  Ship the merchant-enabled list as a config; do not hard-code.

## Effort estimate

- Backend: **2.5 days**
- fe-user: **1 day**
- fe-admin: **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~4.5 person-days.**
