# Sprint 31 — 2C2P (ASEAN regional aggregator)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market wedge:** Thai / SEA SaaS Launchpad — see
[`payment-plugins-market.md §6.2`](../../../dev_docs/market-research/payment-plugins-market.md)
and [`payment-plugins-asean.md`](../../../dev_docs/market-research/payment-plugins-asean.md).

**Repos touched:**
- `vbwd-plugin-2c2p` (NEW — backend adapter + webhook receiver)
- `vbwd-fe-user-plugin-2c2p` (NEW — checkout widget + method picker)
- `vbwd-fe-admin-plugin-2c2p` (NEW — config, transaction list)
- `vbwd-demo-instances/instances/local/sea-saas/` (NEW — SEA SaaS demo)

## Goal

One plugin covers Thailand, Singapore, Malaysia, Philippines, Vietnam,
Indonesia, Hong Kong, Taiwan via 2C2P's Payment Gateway v4 API. Methods
exposed in v1: cards (Visa / Mastercard / JCB / Amex / UnionPay),
PromptPay QR (TH), PayNow QR (SG), DuitNow QR (MY), QRIS (ID), GCash
(PH), MoMo (VN), ShopeePay (regional), TrueMoney (TH), Alipay (regional),
WeChat Pay (regional), FPX bank-transfer (MY), and Internet Banking
Thailand.

After this sprint a merchant in any of the 8 countries can configure
2C2P credentials, select which methods to expose, and take payments
end-to-end via the same VBWD invoice flow.

## Engineering requirements

Inherit the full framework from
[Sprint 29 §Core engineering requirements](29-klarna-dach-wedge.md#core-engineering-requirements-binding-for-every-deliverable).
Specific checkpoints for this sprint:

- `C2P2Adapter.create_payment_token(invoice, method)` spec authored
  first — 2C2P uses a JWT-signed request payload; spec verifies
  signature structure + required fields + version header.
- `C2P2BackendResponseHandler` (Backend Notification / Frontend Return)
  spec authored first — 2C2P posts a form-encoded, JWT-signed payload
  back to the merchant URL; spec verifies signature check, covers
  success / failure / pending states, and enforces idempotency by
  `invoice_no` + `tran_ref`.
- `PromptPayQRRenderer` spec authored first — renders the Thai EMVCo
  QR in the fe-user widget when merchant selects PromptPay.
- Multi-currency: THB, SGD, MYR, PHP, VND, IDR, HKD, TWD, USD. Validate
  currency allow-list per merchant country.

## Deliverables

### D1 — `vbwd-plugin-2c2p` backend

- Folder per plugin convention in `MEMORY.md`: `vbwd-plugin-2c2p/c2p2/`
  (plugin id source dir).
- `adapters/c2p2_adapter.py` — signs requests with merchant secret using
  HMAC-SHA256 as per 2C2P JWT spec; handles PGW v4 endpoints:
  `/paymentToken`, `/paymentInquiry`, `/refund`, `/void`.
- `services/c2p2_service.py` — VBWD invoice → 2C2P request mapping;
  maps 2C2P response codes (see `C2P2ResponseCodes` enum) to internal
  invoice states.
- `routes.py`:
  - `POST /api/v1/c2p2/payment-tokens` — issue a payment token for an
    invoice and redirect URL / embedded-form JWT.
  - `POST /api/v1/c2p2/backend-notifications` — Backend Notification
    (server-to-server webhook); verifies JWT signature.
  - `GET /api/v1/c2p2/payments/:invoice_no/status` — merchant- or
    user-side status polling (calls 2C2P `/paymentInquiry`).
- `models/c2p2_transaction.py` — our mirror of 2C2P's payment record:
  merchant_id, invoice_no, tran_ref, amount, currency, channel_code,
  status, last_observed_status, created_at.
- Alembic migration for the one table.
- Implements `IPaymentAdapter`.
- Unit tests cover JWT sign/verify, response-code mapping, idempotency
  on backend notifications, refund flow. Integration tests gated by
  `C2P2_SANDBOX=1`.

### D2 — `vbwd-fe-user-plugin-2c2p`

- Two UX modes:
  1. **Hosted redirect** (simplest) — token → redirect to 2C2P hosted
     page which handles method selection + card entry.
  2. **Inline** — VBWD renders method picker (QR, card, wallet logos
     with country-appropriate ordering), then embeds 2C2P's v4 secure
     field for card or redirects for wallet/QR.
- `components/C2P2MethodPicker.vue` — re-orders methods based on
  detected country / merchant config.
- `components/C2P2QRView.vue` — shows PromptPay / PayNow / DuitNow /
  QRIS QR with expiry countdown and auto-poll for payment completion.
- `components/C2P2CardForm.vue` — 2C2P secure field embed (PCI SAQ-A
  compliant).
- `stores/c2p2.ts` — session state, methods list per merchant.
- i18n: en, th, vi, id, ms, tl (Filipino), zh-Hans, zh-Hant.
- Playwright E2E: PromptPay QR flow, card flow, GCash redirect flow.

### D3 — `vbwd-fe-admin-plugin-2c2p`

- Merchant ID + secret key config (write-only masked, test/live toggle).
- Country / currency allow-list.
- Method enable/disable list.
- Transaction list with 2C2P `tran_ref` link + refund button (calls
  backend refund route).

### D4 — SEA SaaS demo instance

- `vbwd-demo-instances/instances/local/sea-saas/` — localhost-only
  demo: VBWD backend + fe-user + fe-admin with 2C2P plugin enabled in
  sandbox.
- Seed: 1 admin, 1 Thai customer, 2 subscription plans (monthly + yearly)
  priced in THB, test-enabled 2C2P credentials injected via
  `.env.sandbox`.
- README documents "clone, `make up`, buy a plan with PromptPay".

## Tests

- Unit: ≥ 35 backend, ≥ 25 frontend.
- Integration: ≥ 6 2C2P sandbox round-trips (one per method type —
  card, PromptPay, GCash, Alipay, WeChat, MoMo).
- E2E: 3 flows (card, PromptPay, GCash).

## Risks

- **JWT signature quirks**: 2C2P has a reputation for strict JSON
  key-order + whitespace rules in its signed payload. Use the vendor
  Python SDK (`2c2p-pgw-sdk`) if available; otherwise sign canonicalised
  JSON via `canonicaljson` library and document the pattern.
- **Wallet redirect UX on mobile**: QR flows must degrade to deep-link
  on mobile (no one scans a QR with their own phone on their own phone).
  `C2P2QRView.vue` detects mobile user-agent and switches to deep-link.
- **Currency support per method**: not all methods work in all
  currencies. Config validation must reject impossible combinations
  (e.g., PromptPay only in THB).

## Open questions

- [ ] **Q1** — 2C2P vendor SDK vs raw HTTP? Recommended **vendor SDK**
  when available to avoid JWT-sign debugging; else raw HTTP with
  canonical-JSON lib.
- [ ] **Q2** — QR auto-poll interval? Recommended **every 3s for 60s
  total, then idle + manual "Check again" button**.
- [ ] **Q3** — include WeChat Pay / Alipay in v1? These are primarily
  Chinese-tourist flows in SEA. Recommended **yes for HK/TW; defer
  elsewhere**.

## Effort estimate

- Backend adapter + service + webhook + tests: **2.5 days**
- fe-user (hosted + inline + QR + card): **2 days**
- fe-admin (config + tx + refund): **1 day**
- SEA demo instance: **0.25 day**

**Total: ~5.75 person-days.**
