# Sprint 50 — KakaoPay (Korea direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** KakaoPay is Korea's #1 mobile payment wallet;
37M users (~72% of population), est. USD 90B+ TPV. Dominant in
Kakao-ecosystem merchants, Korean Air, CJ Olive Young.

**Repos touched:**
- `vbwd-plugin-kakao-pay` (NEW — direct KakaoPay Online API)
- `vbwd-fe-user-plugin-kakao-pay` (NEW — QR + KakaoTalk deep-link)
- `vbwd-fe-admin-plugin-kakao-pay` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/kr-saas/` (existing from
  Sprint 34 — enable KakaoPay direct alongside Toss)

## Goal

Direct KakaoPay plugin. Also reachable via Toss (Sprint 34) — direct
plugin gives merchants with a KakaoPay CID better rates. Two-step
flow: `/v1/payment/ready` → user approves in KakaoTalk → server
calls `/v1/payment/approve`.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `KakaoPayAdapter.payment_ready(invoice)` spec first — admin-key
  auth, required fields (cid, partner_order_id, partner_user_id,
  item_name, quantity, total_amount, tax_free_amount), returns
  `{ next_redirect_pc_url, next_redirect_mobile_url,
  next_redirect_app_url, tid }`.
- `KakaoPayAdapter.payment_approve(tid, pg_token)` spec first —
  required `pg_token` from return URL.
- Idempotent finalization via `tid`.

## Deliverables

### D1 — `vbwd-plugin-kakao-pay` backend

- Folder: `vbwd-plugin-kakao-pay/kakao_pay/`.
- `adapters/kakao_pay_adapter.py` — admin-key authenticated HTTP
  client; endpoints: `/v1/payment/ready`, `/v1/payment/approve`,
  `/v1/payment/order`, `/v1/payment/cancel`.
- `services/kakao_pay_service.py` — invoice → ready + approve;
  KRW integer enforcement.
- `routes.py`:
  - `POST /api/v1/kakao-pay/ready` — start.
  - `POST /api/v1/kakao-pay/approve` — finalize (called by return).
  - `GET /api/v1/kakao-pay/payments/:tid/status`
  - `POST /api/v1/kakao-pay/payments/:tid/cancel` — refund.
- `models/kakao_pay_payment.py` — tid, invoice_no, status,
  partner_user_id.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-kakao-pay`

- `components/KakaoPayCheckout.vue` — device detect → PC URL /
  mobile URL / KakaoTalk deep-link.
- `components/KakaoPayReturn.vue` — handles `pg_token`; POSTs to
  backend `/approve`.
- i18n: ko (primary), en.
- E2E: desktop QR, mobile deep-link.

### D3 — `vbwd-fe-admin-plugin-kakao-pay`

- Config: CID, admin key (masked), test/live.
- Transaction list + cancel/refund button.

### D4 — demo wiring

- Enable KakaoPay direct in `kr-saas` instance. Document direct vs
  Toss trade-off.

## Tests

- Unit: ≥ 25 backend, ≥ 12 frontend.
- Integration: ≥ 3 KakaoPay sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **CID onboarding**: KakaoPay issues CIDs per merchant contract;
  test CID works only with test keys. Document clearly in README.
- **Receipt flow**: Korean cash-receipt (현금영수증) is handled by the
  Toss plugin (Sprint 34) — this plugin does not duplicate.
  Merchants using KakaoPay-direct must pair with Toss for cash-
  receipt issuance, **or** integrate an e-receipt provider
  separately.

## Effort estimate

- Backend: **1.75 days**
- fe-user: **0.75 day**
- fe-admin: **0.5 day**
- Demo wiring: **0.25 day**

**Total: ~3.25 person-days.**
