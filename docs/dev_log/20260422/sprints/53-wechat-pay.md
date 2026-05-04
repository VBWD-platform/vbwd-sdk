# Sprint 53 — WeChat Pay (China + cross-border)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** WeChat Pay has ~900M MAU within the WeChat app.
For merchants with Chinese customer flow (domestic or cross-border
tourism), second only to Alipay. Often paired with Alipay in "Pay
by QR" setups across Asia.

**Repos touched:**
- `vbwd-plugin-wechat-pay` (NEW — direct WeChat Pay API v3)
- `vbwd-fe-user-plugin-wechat-pay` (NEW — QR + JSAPI + H5)
- `vbwd-fe-admin-plugin-wechat-pay` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing — enable)

## Goal

Direct WeChat Pay integration covering:
- **Native QR** — desktop e-commerce scan.
- **H5 Pay** — mobile web with WeChat browser detection.
- **JSAPI** — in-WeChat-browser (for WeChat Official Account stores)
  [optional, defer if scope tight].

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `WeChatPayAdapter.native_prepay(invoice)` spec first — API v3
  JWT signature (SHA256-RSA), required fields, returns `code_url`
  for QR rendering.
- `WeChatPayAdapter.h5_prepay(invoice, user_ip)` spec first —
  returns `h5_url`.
- Webhook verify + idempotency spec first.
- Currency CNY-only; cross-border merchants use CNY settlement.

## Deliverables

### D1 — `vbwd-plugin-wechat-pay` backend

- Folder: `vbwd-plugin-wechat-pay/wechat_pay/`.
- `adapters/wechat_pay_adapter.py` — v3 RSA-signed client; endpoints:
  `/v3/pay/transactions/native`, `/v3/pay/transactions/h5`,
  `/v3/refund/domestic/refunds`.
- `services/wechat_pay_service.py` — invoice mapping + CNY guard.
- `routes.py`:
  - `POST /api/v1/wechat-pay/native` — QR prepay.
  - `POST /api/v1/wechat-pay/h5` — H5 prepay.
  - `POST /api/v1/wechat-pay/webhooks` — verified receiver.
  - `GET /api/v1/wechat-pay/payments/:id/status` — polling.
  - `POST /api/v1/wechat-pay/payments/:id/refund` — refund.
- `models/wechat_pay_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-wechat-pay`

- `components/WeChatPayQR.vue` — QR from `code_url` + 2-min
  countdown + auto-poll.
- `components/WeChatPayH5.vue` — mobile browser redirect to
  `h5_url`.
- i18n: zh-Hans (primary), en.
- E2E: QR happy path.

### D3 — `vbwd-fe-admin-plugin-wechat-pay`

- Config: mch_id, app_id, RSA private key path, platform cert path,
  api_v3_key (masked).
- Transaction list + refund button.

### D4 — demo wiring

- Enable WeChat Pay in `sea-saas` instance.

## Tests

- Unit: ≥ 25 backend, ≥ 12 frontend.
- Integration: ≥ 3 WeChat Pay sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Platform cert rotation**: WeChat Pay rotates the platform
  certificate regularly. Plugin auto-downloads + caches via
  `/v3/certificates` with signature verification.
- **IP whitelist**: some merchant categories require whitelist of
  callback IPs at WeChat Pay admin side. Document in README.

## Effort estimate

- Backend: **2 days**
- fe-user: **0.75 day**
- fe-admin: **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~3.75 person-days.**
