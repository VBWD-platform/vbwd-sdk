# Sprint 34 Report — Toss Payments plugin

**Date:** 2026-04-24
**Sprint:** [34 — Toss Payments Korea](../done/34-toss-payments-korea.md)
**Status:** Scaffolded end-to-end. 36 unit tests green, pre-commit
gate PASS. Integration tests + NTS tax-invoice integration deferred.

## What shipped

### `vbwd-plugin-toss_payments` (backend)

- `TossPaymentsPlugin` with KRW-integer-only enforcement (fails
  clearly on USD or on Decimal with sub-unit digits).
- `TossPaymentsSDKAdapter` — Basic auth with
  `base64(secret_key + ":")`. Full `ISDKAdapter`:
  `create_payment_intent`, `capture_payment`, `release_authorization`,
  `refund_payment`, `get_payment_status`. Domain-specific:
  `confirm_payment(paymentKey, orderId, amount)`, `get_payment`,
  `cancel_payment` (full + partial), `issue_cash_receipt`,
  `verify_webhook` (HMAC-SHA256 on `toss-signature`). `error_code`
  propagates from Toss response so merchants see e.g.
  `INVALID_SECRET_KEY` in the admin UI.
- `TossPaymentService` + `TossCashReceiptService` + `TossWebhookHandler`.
  Cash receipts carry **only** a SHA-256 hash of the
  identifier — plaintext phones/biz-reg-numbers are sent to Toss at
  issuance and then forgotten (PII-safe ledger).
- Service guards identifier_type ∈ {phone, business} and
  receipt_type ∈ {소득공제, 지출증빙}; violations raise `ValueError`
  that bubbles to a 400 in the route.
- Migration `20260424_1000_toss` chains after `20260422_1400_mp`.
- Routes: `POST /payments/confirm`, `GET /payments/:order/status`,
  `POST /webhooks`, `POST /cash-receipts`, `POST /payments/:order/refund`.
- **36 unit tests** including Basic-auth base64 round-trip, 4xx
  provider error_code capture, partial vs full cancel payload
  shape, cash-receipt PII hash determinism, status mapping,
  webhook handler snake_case alias.
- `pre-commit-check.sh --plugin toss_payments --quick`: **PASS**.
- Commit: `c22b9e5` on `main`.

### `vbwd-fe-user-plugin-toss-payments-payment` (fe-user)

- Named-export `tossPaymentsPlugin`.
- `TossPaymentView.vue` loads Toss Widget v2 (via script injection)
  and calls `requestPayment` with `successUrl` / `failUrl`.
- `TossSuccessView.vue` parses `paymentKey` / `orderId` / `amount`
  from the return URL and calls backend `/payments/confirm`.
- Locales: `en`, `ko`.
- Registered in `vbwd-fe-user/plugins/plugins.json`.
- Commit: `b034714`.

### `vbwd-fe-admin-plugin-toss-payments-admin` (fe-admin)

- Named-export `tossPaymentsAdminPlugin`.
- Two routes: `/admin/toss/payments` (list + refund) and
  `/admin/toss/cash-receipts` (receipt ledger, hashes only).
- Pinia store `useTossStore` with `fetchPayments`, `fetchReceipts`,
  `refund` (all DI-passed `api`).
- Registered in `vbwd-fe-admin/plugins/plugins.json`.
- Commit: `a7e71aa`.

## Engineering-contract checks

- **TDD-first**: Basic-auth header format, cancel payload shape,
  cash-receipt identifier-type guard, PII hash determinism, status
  mapping per Toss state names — all spec'd first.
- **DevOps-first**: `pre-commit-check.sh` green. Alembic chain
  correctly follows `20260422_1400_mp`. No raw SQL.
- **SOLID + Liskov**: the adapter's `refund_payment` was initially
  missing (caught by pytest — `abstract method refund_payment`);
  added the implementation without breaking the service contract.
  Added KRW-integer guard preserves `create_payment_intent`
  postconditions (`success=True` ⇒ real preflight checks passed).
- **DRY**: one `_post` / `_get` helper in the adapter.
- **DI**: services take `session`; fe-admin store takes `api`.
- **Clean code**: full names (`issue_cash_receipt`, not `icr`);
  regulatory-rule comment on PII hash ("Why" comment — explains
  that plaintext identifiers are forgotten, which is not obvious
  from the code).
- **No over-engineering**: tax-invoice flag is a boolean config;
  actual NTS integration is deferred to a follow-up sprint
  (documented in README).
- **Drop deprecated**: the unused `Integer` import surfaced by
  flake8 was deleted, not suppressed with `# noqa`.

## Follow-ups

1. **`GET /api/v1/plugins/toss-payments/payments`** + `cash-receipts`
   list endpoints — **S34.1**.
2. **NTS tax-invoice (세금계산서)** integration via an e-invoice
   provider (bill36524 / popbill) — **S34.2**.
3. **Integration tests** gated by `TOSS_SANDBOX=1` — **S34.3**.
4. **Billing-key recurring** (Toss's native subscription primitive)
   — for now VBWD's scheduler calls one-off charges; native billing
   key is **S34.4**.

## Pre-commit output

```
Static analysis: ALL CHECKS PASSED
Unit tests:      36 passed in 0.22s
SUCCESS: All checks passed! Ready to commit.
```
