# Sprint 33 — Mercado Pago (LATAM regional aggregator)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market wedge:** Pan-LATAM creator / SaaS — see
[`payment-plugins-market.md §6.5`](../../../dev_docs/market-research/payment-plugins-market.md)
and [`payment-plugins-latam.md`](../../../dev_docs/market-research/payment-plugins-latam.md).

**Repos touched:**
- `vbwd-plugin-mercado-pago` (NEW — regional aggregator adapter)
- `vbwd-fe-user-plugin-mercado-pago` (NEW — checkout + Pix QR + OXXO
  voucher UI)
- `vbwd-fe-admin-plugin-mercado-pago` (NEW — config, tx list, refunds,
  installment rules)
- `vbwd-demo-instances/instances/local/latam-shop/` (NEW — LATAM demo)

## Goal

One plugin covers the seven most relevant LATAM markets (Brazil,
Mexico, Argentina, Colombia, Chile, Uruguay, Peru) via Mercado Pago's
unified Payments API. Methods exposed in v1:

- **Pix (BR)** — instant rail, now exceeding cards in Brazil.
- **Boleto Bancário (BR)** — cash voucher.
- **OXXO (MX)** — cash voucher.
- **SPEI (MX)** — bank transfer.
- **PSE (CO)** — bank redirect.
- **Webpay (CL)** — Transbank redirect (via Mercado Pago).
- **PagoEfectivo / RapiPago (PE / AR)** — cash vouchers.
- **Cards** — Visa, Mastercard, Amex, Hipercard, Elo with installments
  (parcelamento BR, MSI MX).
- **Mercado Pago wallet** — native account balance.

After this sprint a merchant can install VBWD, drop in Mercado Pago
credentials, pick target countries, and immediately accept payments in
any of the 7 markets with correct installment options, cash-voucher
generation, and Pix QR.

## Engineering requirements

Inherit the full framework from
[Sprint 29 §Core engineering requirements](29-klarna-dach-wedge.md#core-engineering-requirements-binding-for-every-deliverable).
Specific checkpoints:

- `MercadoPagoAdapter.create_preference(invoice, country)` spec
  authored first — Preference is the Mercado Pago high-level object;
  spec covers min/max installments, country-appropriate method
  filtering, notification URL injection.
- `MercadoPagoWebhookHandler.handle(payload)` spec first — idempotency
  by `data.id`, signature verification using Mercado Pago's HMAC
  header.
- `PixQRRenderer.render(preference)` spec first — produces EMVCo Pix QR
  payload (BR-specific) with correct CRC16.
- `BoletoVoucherRenderer` / `OxxoVoucherRenderer` spec first — returns
  a PDF voucher via core `PdfService` (from Sprint 28) with scannable
  barcode and payable amount.
- `InstallmentCalculator.available_plans(amount, country, card_brand)`
  spec first — returns valid installment counts (e.g., 1–12 in BR for
  most cards; MSI 3/6/9/12 in MX).

## Deliverables

### D1 — `vbwd-plugin-mercado-pago` backend

- Folder per plugin convention: `vbwd-plugin-mercado-pago/mp/`.
- `adapters/mercado_pago_adapter.py` — wraps Mercado Pago's official
  Python SDK (`mercadopago>=2.3`); isolates per-country token selection
  (BR, MX, AR, CO, CL, UY, PE each have their own MP app).
- `services/mercado_pago_service.py` — maps invoice + country →
  preference request; computes installments; handles Pix QR + voucher
  generation.
- `routes.py`:
  - `POST /api/v1/mp/preferences` — create preference for invoice and
    selected country; returns `{ init_point, qr_payload?, voucher_url? }`.
  - `POST /api/v1/mp/webhooks` — Mercado Pago webhook receiver
    (topic: `payment`).
  - `GET /api/v1/mp/payments/:id/status` — polling for async methods
    (Boleto, OXXO, Pix).
  - `POST /api/v1/mp/payments/:id/refund` — admin-triggered refund.
- `models/mp_payment.py` — payment_id, preference_id, country, method,
  invoice_no, amount, currency, status, last_observed_status,
  installment_count, extra_data (JSON).
- Alembic migration for the one table.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-mercado-pago`

- `components/MPMethodPicker.vue` — dynamic method grid per detected /
  selected country.
- `components/MPPixQR.vue` — Brazilian Pix QR with countdown, copy-paste
  key, auto-poll.
- `components/MPVoucher.vue` — PDF voucher download + "Pay at OXXO /
  Pago Fácil / RapiPago" instructions (i18n'd per country).
- `components/MPCardForm.vue` — Mercado Pago.js v2 secure fields for
  card entry + installment selector (parcelamento BR / MSI MX).
- `components/MPRedirect.vue` — for PSE, Webpay, MP-wallet flows →
  redirect to `init_point`.
- `stores/mercadoPago.ts` — country detection, method list, session.
- i18n: pt-BR, es-MX, es-AR, es-CO, es-CL, es-PE, es-UY, en.
- Playwright E2E: Pix QR flow (BR), OXXO voucher flow (MX),
  parcelamento card flow (BR).

### D3 — `vbwd-fe-admin-plugin-mercado-pago`

- Per-country credential config (one access-token per country app).
- Method enable/disable per country.
- Installment rules editor (min/max per country, interest rate
  passthrough on/off).
- Transaction list with Mercado Pago dashboard link, refund button,
  chargeback reflection.

### D4 — LATAM demo instance

- `vbwd-demo-instances/instances/local/latam-shop/` — localhost-only
  LATAM demo: backend + fe-user + fe-admin, Mercado Pago enabled for
  BR + MX (most common launch combo).
- Seed: 1 admin, 1 BR customer, 1 MX customer, 3 products priced in
  BRL and MXN, 2 subscription plans.
- README: "clone, `make up`, buy with Pix, buy with OXXO".

## Tests

- Unit: ≥ 40 backend (7 countries × methods), ≥ 25 frontend.
- Integration: ≥ 8 MP sandbox round-trips (Pix, OXXO, card BR, card MX,
  SPEI, PSE, Boleto, refund).
- E2E: 3 flows (Pix BR, OXXO MX, card parcelamento).

## Risks

- **Per-country app sprawl**: Mercado Pago issues one app + credential
  per country. The admin UI must make per-country setup clear — a
  merchant configuring "LATAM" is actually configuring 1–7 separate
  credential sets.
- **Pix CRC16 subtlety**: the EMVCo Pix payload uses CRC16/CCITT-FALSE
  with a specific polynomial. Use a well-tested library (`pycrc` or
  `crcmod`) and cover with a snapshot test.
- **Boleto expiration**: default 3 working days. Config must allow per-
  merchant override and enforce a min/max sanity range.
- **MSI eligibility**: MSI (meses sin intereses) in MX depends on the
  card brand + issuing bank. The `InstallmentCalculator` must match
  Mercado Pago's per-brand rules; fallback is "no MSI, pay in full".

## Open questions

- [ ] **Q1** — launch with all 7 countries or 2 (BR + MX)? Recommended
  **all 7 at once** — one adapter, config gates availability.
- [ ] **Q2** — expose Mercado Pago's native "Subscription" object, or
  keep using VBWD's recurring billing + one-off MP charges? Recommended
  **VBWD recurring** — keeps one billing model across all plugins.
- [ ] **Q3** — support MercadoPago checkout-pro (hosted) in addition to
  inline Mercado Pago.js? Recommended **yes**, ~0.5 day extra.

## Effort estimate

- Backend adapter + service + webhook + tests: **3 days**
- Pix + voucher renderers + installment calculator: **1 day**
- fe-user (method picker + Pix + voucher + card form): **2 days**
- fe-admin (per-country config + installment rules + tx list): **1.5 days**
- LATAM demo instance: **0.5 day**

**Total: ~8 person-days.**
