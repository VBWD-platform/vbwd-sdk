# Sprint 35 — Conekta (Mexico)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market wedge:** Mexican cross-border / SMB SaaS — see
[`payment-plugins-market.md §6.1-ish (MX row)`](../../../dev_docs/market-research/payment-plugins-market.md)
and [`payment-plugins-latam.md`](../../../dev_docs/market-research/payment-plugins-latam.md).

**Repos touched:**
- `vbwd-plugin-conekta` (NEW — backend adapter + webhook receiver)
- `vbwd-fe-user-plugin-conekta` (NEW — card + OXXO voucher + SPEI
  transfer UI)
- `vbwd-fe-admin-plugin-conekta` (NEW — config + MSI rules + tx list)
- `vbwd-demo-instances/instances/local/mx-shop/` (NEW — MX demo
  instance)

## Goal

Deliver a production-ready Mexican checkout. Conekta is the
best-developer-experience PSP in Mexico; merchants prefer it over
Stripe-MX for OXXO + SPEI coverage and better MSI (meses sin
intereses) support.

Methods in v1:
- **Cards** — Visa, Mastercard, Amex, Carnet with **MSI 3 / 6 / 9 / 12**
  (interest-free installments on eligible cards).
- **OXXO Pay** — cash voucher at 21K+ OXXO stores.
- **SPEI** — bank transfer with CLABE reference.
- **Cash** (other chains: 7-Eleven MX, Farmacias del Ahorro, etc. —
  Conekta lumps these under "oxxo_cash" or "cash"; use whatever config
  Conekta supports at integration time).

## Engineering requirements

Inherit the full framework from
[Sprint 29 §Core engineering requirements](29-klarna-dach-wedge.md#core-engineering-requirements-binding-for-every-deliverable).
Specific checkpoints:

- `ConektaAdapter.create_order(invoice, method)` spec first — spec
  covers card + OXXO + SPEI payloads; MSI adds `monthly_installments`
  payload parameter only when eligible.
- `ConektaWebhookHandler.handle(event)` spec first — signature
  verification via Conekta's `digest` header; idempotency by `event.id`;
  event types: `order.paid`, `order.expired`, `order.canceled`,
  `charge.refunded`.
- `MSICalculator.available_plans(amount, card_bin)` spec first —
  MSI eligibility is bin-dependent; must match Conekta's published
  rules. Fallback: single-payment.
- `OxxoVoucherRenderer` spec first — renders PDF voucher via core
  `PdfService`; includes Conekta `reference` + OXXO-specific expiry
  (default 3 days).

## Deliverables

### D1 — `vbwd-plugin-conekta` backend

- Folder convention: `vbwd-plugin-conekta/conekta/`.
- `adapters/conekta_adapter.py` — wraps Conekta Python SDK
  (`conekta>=3.0`) with pinned API version header (`Accept:
  application/vnd.conekta-v2.2.0+json`).
- `services/conekta_service.py` — invoice → order mapping; dispatches
  to card / OXXO / SPEI payload builders.
- `routes.py`:
  - `POST /api/v1/conekta/orders` — create order, return
    `{ checkout_url }` (card) or `{ voucher_url, reference, expires_at }`
    (OXXO) or `{ clabe, reference, expires_at }` (SPEI).
  - `POST /api/v1/conekta/webhooks` — Conekta webhook receiver.
  - `POST /api/v1/conekta/orders/:id/refund` — refund.
- `models/conekta_order.py` — order_id, invoice_no, amount, method,
  status, last_observed_status, msi, reference, clabe, expires_at.
- Alembic migration for the one table.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-conekta`

- `components/ConektaMethodPicker.vue` — card / OXXO / SPEI radio
  group with MX-appropriate imagery.
- `components/ConektaCardForm.vue` — Conekta.js v2 tokeniser for PCI
  SAQ-A compliance. MSI selector appears when card bin supports MSI.
- `components/ConektaOxxoVoucher.vue` — displays barcode + "Pay at
  OXXO" instructions + reference + PDF download.
- `components/ConektaSpei.vue` — displays CLABE + reference +
  instructions.
- `stores/conekta.ts` — payment state, MSI availability.
- i18n: es-MX (primary), en.
- Playwright E2E: card flow with MSI 6, OXXO voucher flow, SPEI flow.

### D3 — `vbwd-fe-admin-plugin-conekta`

- Config: public key + private key (write-only masked), test/live
  toggle.
- MSI rules: enable toggle + merchant share of interest passthrough.
- OXXO expiry days: input (default 3, min 1, max 30).
- SPEI expiry days: input (default 1, min 1, max 7).
- Transaction list with status, method, customer, refund button,
  Conekta dashboard link.

### D4 — MX demo instance

- `vbwd-demo-instances/instances/local/mx-shop/` — localhost-only MX
  demo: backend + fe-user + fe-admin + Conekta plugin in test mode.
- Seed: 1 admin, 1 MX customer, 3 products priced in MXN, 1
  subscription plan.
- README walkthrough: "clone, `make up`, buy with card + MSI 6, buy
  with OXXO, refund".

## Tests

- Unit: ≥ 30 backend, ≥ 20 frontend.
- Integration: ≥ 6 Conekta sandbox round-trips (card, card+MSI, OXXO,
  SPEI, refund, expired-voucher reconciliation).
- E2E: 3 flows (card+MSI6, OXXO, SPEI).

## Risks

- **MSI bin tables**: Conekta provides programmatic access but data
  can lag reality. Fallback must be graceful (single-payment) when an
  MSI attempt gets rejected.
- **OXXO voucher expiry reconciliation**: if user doesn't pay within
  expiry, Conekta sends `order.expired` webhook. VBWD must flip the
  invoice from `pending` to `expired` and let merchant manually re-
  issue.
- **CLABE payment detection delay**: SPEI transfers take 10–60 min
  to reconcile even during banking hours. UI copy must set expectation.

## Open questions

- [ ] **Q1** — ship MSI in v1? Recommended **yes** — MSI is table-
  stakes for Mexican e-commerce and Conekta handles the complexity.
- [ ] **Q2** — integrate Conekta's "Link de Pago" hosted page as a
  fallback? Recommended **no** for v1 — we own the UX.
- [ ] **Q3** — how does Conekta overlap with Mercado Pago (Sprint 33)
  for Mexican merchants? Recommendation: ship both, let merchant pick;
  Conekta has deeper MX-native UX, MP has pan-LATAM reach.

## Effort estimate

- Backend adapter + service + webhook + tests: **2 days**
- MSI calculator + voucher renderer: **0.75 day**
- fe-user (method picker + card + OXXO + SPEI): **1.5 days**
- fe-admin (config + MSI rules + tx list): **1 day**
- MX demo instance: **0.25 day**

**Total: ~5.5 person-days.**
