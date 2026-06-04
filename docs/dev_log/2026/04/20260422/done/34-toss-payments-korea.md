# Sprint 34 — Toss Payments (Korea)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market wedge:** Korean creator / SaaS pack — see
[`payment-plugins-market.md §6.4`](../../../dev_docs/market-research/payment-plugins-market.md)
and [`payment-plugins-asean.md`](../../../dev_docs/market-research/payment-plugins-asean.md).

**Repos touched:**
- `vbwd-plugin-toss-payments` (NEW — backend adapter + webhook
  receiver)
- `vbwd-fe-user-plugin-toss-payments` (NEW — Toss Payments widget
  integration)
- `vbwd-fe-admin-plugin-toss-payments` (NEW — config + cash-receipt
  (현금영수증) handling)
- `vbwd-demo-instances/instances/local/kr-saas/` (NEW — Korean SaaS
  demo)

## Goal

Toss Payments is Korea's modern aggregator — cards (local + international),
KakaoPay, Naver Pay, Samsung Pay, Payco, and Korean bank transfers in
one widget. After this sprint a Korean merchant can drop in Toss
credentials and expose the full local method set.

Korea has a **regulatory surface** most Western platforms ignore: mandatory
cash receipt (현금영수증) issuance for individuals and tax invoice
(세금계산서) for businesses. This sprint covers both.

## Engineering requirements

Inherit the full framework from
[Sprint 29 §Core engineering requirements](29-klarna-dach-wedge.md#core-engineering-requirements-binding-for-every-deliverable).
Specific checkpoints:

- `TossPaymentsAdapter.request_payment(invoice)` spec first — Toss uses
  a two-phase flow (client-side widget → server-side confirm).
  Spec covers: `requestPayment` JWT, server-side `/v1/payments/confirm`
  with `paymentKey` + `orderId` + `amount`.
- `TossPaymentsWebhookHandler.handle(payload)` spec first — Toss
  webhooks are idempotent by `paymentKey`; spec verifies signature
  header `toss-signature`.
- `CashReceiptService.issue(payment, identifier, identifier_type)` spec
  first — issues cash receipt for individual (phone/card-linked) or
  business (business registration number). Covers `income-deduction`
  vs `proof-of-expense` types.
- `TaxInvoiceService.issue(payment, business_info)` spec first — issues
  electronic tax invoice (NTS / 홈택스 integration via Toss's own tax
  invoice API or external module).

## Deliverables

### D1 — `vbwd-plugin-toss-payments` backend

- Folder convention: `vbwd-plugin-toss-payments/toss/`.
- `adapters/toss_adapter.py` — HTTP client over Toss Payments API v1
  with Basic-auth (base64 of `secretKey:`).
- `services/toss_service.py` — invoice → payment confirmation mapping;
  handles success/fail routing; attaches `orderId` = VBWD invoice
  reference.
- `services/cash_receipt_service.py` — issues cash receipts; stores
  issuance records.
- `services/tax_invoice_service.py` — issues tax invoices; guarded
  behind a config flag (not all merchants have NTS integration ready).
- `routes.py`:
  - `POST /api/v1/toss/payments/confirm` — server-side confirm (called
    by fe-user after widget success).
  - `POST /api/v1/toss/webhooks` — webhook receiver.
  - `POST /api/v1/toss/cash-receipts` — issue cash receipt for a
    completed payment.
  - `POST /api/v1/toss/payments/:id/refund` — refund.
- `models/toss_payment.py` — payment_key, order_id (vbwd invoice ref),
  method, amount, status, receipt_type, receipt_identifier.
- `models/toss_cash_receipt.py` — receipt_id, payment_key, identifier
  (phone / business-id), type (income-deduction / expense-proof),
  issued_at, cancellation_at.
- Alembic migration for the two tables.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-toss-payments`

- `components/TossCheckout.vue` — mounts Toss Payments Widget v2 (JS
  SDK). Widget handles all method selection UI (card / KakaoPay / Naver
  Pay / Samsung Pay / bank transfer).
- `components/TossCashReceiptForm.vue` — optional form shown post-
  payment: individual (enter phone) or business (enter biz-reg-no), or
  skip. For individuals, store consent for future purchases.
- `stores/toss.ts` — session state; cash-receipt preference memory
  for authenticated users.
- i18n: ko (primary), en.
- Playwright E2E: widget card flow, KakaoPay redirect flow, cash
  receipt issuance form.

### D3 — `vbwd-fe-admin-plugin-toss-payments`

- Config: client key + secret key (write-only masked), test/live
  toggle.
- Method visibility toggle (some merchants want card-only, no wallet
  redirects).
- Cash receipt issuance list + manual issue/cancel UI.
- Tax invoice config: on/off toggle + NTS business info.
- Transaction list with refund button.

### D4 — Korean SaaS demo instance

- `vbwd-demo-instances/instances/local/kr-saas/` — localhost-only
  Korean demo with Toss Payments enabled in test mode.
- Seed: 1 admin, 1 KR customer, 2 subscription plans priced in KRW.
- README: "clone, `make up`, buy with Toss widget, issue cash receipt".

## Tests

- Unit: ≥ 35 backend, ≥ 20 frontend.
- Integration: ≥ 6 Toss sandbox round-trips (card + KakaoPay + Naver
  Pay + bank transfer + cash receipt + refund).
- E2E: 2 flows (card + cash receipt, KakaoPay redirect).

## Risks

- **Tax invoice integration**: NTS e-tax-invoice is non-trivial and may
  require a third-party gateway (bill36524, popbill, etc.) beyond Toss.
  V1 ships tax-invoice **issue flag + stub** — actual NTS submission
  via an external service is gated by a config flag and is out of scope
  if not available. Document the gap in the plugin README.
- **Receipt identifier privacy**: phone numbers submitted for cash
  receipts are PII. Store hashed + encrypted; expose plaintext only to
  the merchant admin.
- **Widget versions**: Toss ships widget v1 and v2 in parallel. Use v2
  only; document migration note in README.

## Open questions

- [ ] **Q1** — ship Naver Pay / Samsung Pay in v1? Recommended **yes** —
  Toss widget handles them transparently, zero extra code.
- [ ] **Q2** — tax invoice NTS integration scope. Recommended **stub
  in v1**, deliver in S34.1 once we pick an e-invoice gateway partner.
- [ ] **Q3** — recurring subscriptions via Toss's Billing Key feature
  or keep VBWD's scheduler + one-off charges? Recommended **VBWD
  scheduler** for consistency with other plugins.

## Effort estimate

- Backend adapter + service + webhook + tests: **2 days**
- Cash-receipt + tax-invoice services: **1.5 days**
- fe-user (widget + cash receipt form): **1.5 days**
- fe-admin (config + cash receipt management + tx list): **1.5 days**
- KR demo instance: **0.5 day**

**Total: ~7 person-days.**
