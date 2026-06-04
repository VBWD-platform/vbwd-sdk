# Sprint 51 — Naver Pay (Korea direct)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** Naver Pay is Korea's #1 e-commerce wallet; 30M
users. Default payment at Naver Shopping, Coupang partners,
Smartstore sellers.

**Repos touched:**
- `vbwd-plugin-naver-pay` (NEW — direct Naver Pay E-commerce API)
- `vbwd-fe-user-plugin-naver-pay` (NEW — checkout button + return)
- `vbwd-fe-admin-plugin-naver-pay` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/kr-saas/` (existing — enable)

## Goal

Direct Naver Pay plugin for Korean e-commerce merchants. Naver Pay
is two products — "Standard Naver Pay" (general checkout) and
"Naver Shopping" (platform-bound). This plugin targets Standard.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `NaverPayAdapter.reserve_payment(invoice)` spec first — Naver
  Pay uses a reservation → user-approval → capture pattern;
  required fields `merchantPayKey`, `productName`, `totalPayAmount`,
  `returnUrl`.
- `NaverPayAdapter.approve_payment(reserve_id)` spec first — called
  server-side after user-approval return.
- Idempotent finalization + 60-minute reservation TTL handling.

## Deliverables

### D1 — `vbwd-plugin-naver-pay` backend

- Folder: `vbwd-plugin-naver-pay/naver_pay/`.
- `adapters/naver_pay_adapter.py` — x-naver-client-id + secret auth.
- `services/naver_pay_service.py` — invoice → reserve + approve;
  KRW integer enforcement.
- `routes.py`:
  - `POST /api/v1/naver-pay/reserve`
  - `POST /api/v1/naver-pay/approve`
  - `GET /api/v1/naver-pay/payments/:id/status`
  - `POST /api/v1/naver-pay/payments/:id/cancel` — refund.
- `models/naver_pay_payment.py`.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-naver-pay`

- `components/NaverPayCheckout.vue` — "Naver Pay" button → redirect
  to Naver's approval page.
- `components/NaverPayReturn.vue` — handles return, calls
  `/approve`.
- i18n: ko, en.
- E2E: desktop happy path, mobile deep-link.

### D3 — `vbwd-fe-admin-plugin-naver-pay`

- Config: client ID, client secret (masked), merchant ID.
- Transaction list with cancel button.

### D4 — demo wiring

- Enable Naver Pay in `kr-saas` instance alongside Toss + KakaoPay.

## Tests

- Unit: ≥ 22 backend, ≥ 12 frontend.
- Integration: ≥ 3 Naver Pay sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Reservation expiry**: 60-min TTL. If user doesn't approve,
  reservation auto-expires; plugin should reconcile periodically.
- **Cash receipt (현금영수증) ownership**: same as KakaoPay (Sprint 50)
  — handled by Toss plugin, not duplicated here.

## Effort estimate

- Backend: **1.5 days**
- fe-user: **0.75 day**
- fe-admin: **0.5 day**
- Demo wiring: **0.25 day**

**Total: ~3 person-days.**
