# Sprint 41 — PromptPay (Thailand direct QR)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** PromptPay + Thai QR is the national instant rail;
linked to national ID / phone. ~30B transactions/yr, ~70M TH
bank-account holders. Government and every TH retailer accept it.

**Repos touched:**
- `vbwd-plugin-promptpay` (NEW — direct PromptPay QR renderer +
  bank-confirmation webhook)
- `vbwd-fe-user-plugin-promptpay` (NEW — QR + auto-poll UI)
- `vbwd-fe-admin-plugin-promptpay` (NEW — PromptPay ID config +
  reconciliation dashboard)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing from
  Sprint 31 — enable PromptPay direct alongside 2C2P)

## Goal

Direct PromptPay integration so Thai merchants pay **zero** per-
transaction fees (only bank-side interchange, typically THB 0 for
PromptPay ≤ 5000 THB). Merchant receives payment directly to their
Thai bank account; VBWD matches the bank-side confirmation against
the issued QR via memo / amount / transaction-id webhook.

Two reconciliation options:
1. **Bank-webhook** (recommended): Thai bank API (KBank, SCB, BBL,
   Krungsri) pushes a confirmation webhook with the QR reference
   number.
2. **Polling**: if the merchant's bank doesn't expose webhooks, poll
   the merchant's statement API on a cron.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `PromptPayQRRenderer.render(merchant_id, amount, reference)` spec
  first — EMVCo QR format compliant with BoT spec; covers static QR
  (no amount) and dynamic QR (with amount); CRC16/CCITT-FALSE
  snapshot tests.
- `KBankWebhookHandler`, `ScbWebhookHandler`, `BblWebhookHandler` —
  one handler per supported bank, each with signature verification +
  idempotency by `bank_transaction_id`.
- `PromptPayReconciler.match(payment, bank_tx)` spec first — matches
  by reference (preferred), falls back to amount+timestamp window
  when the bank strips the memo.

## Deliverables

### D1 — `vbwd-plugin-promptpay` backend

- Folder: `vbwd-plugin-promptpay/promptpay/`.
- `adapters/qr_renderer.py` — EMVCo payload builder for PromptPay
  (tag 29 = National Clearing ID, tag 30 = Billpayment).
- `adapters/bank_clients/` — one file per supported bank
  (KBank, SCB, BBL, Krungsri); each implements `IBankReconciler`.
- `services/promptpay_service.py` — invoice → QR payment record;
  reconciliation pipeline.
- `routes.py`:
  - `POST /api/v1/promptpay/payments` — issue QR; returns payload
    + expiry.
  - `GET /api/v1/promptpay/payments/:id/status` — polling.
  - `POST /api/v1/promptpay/webhooks/<bank>` — per-bank receiver.
- `models/promptpay_payment.py` — payment_id, invoice_no, amount,
  reference, qr_payload, status, matched_bank_tx_id.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-promptpay`

- `components/PromptPayQR.vue` — QR + 10-minute countdown +
  amount + reference; auto-polls every 3 s for up to 10 min.
- Mobile UX: "Open in Bank App" deep-link via `thaiqr://` intent.
- i18n: th (primary), en.
- E2E: happy path, expiry timeout.

### D3 — `vbwd-fe-admin-plugin-promptpay`

- Config: merchant PromptPay ID (national ID / tax ID / phone),
  supported bank integrations (enable/disable per bank), webhook
  secrets (masked).
- Reconciliation dashboard: unmatched bank txs, matched payments,
  manual match override.
- No refund UI — PromptPay refunds are manual bank transfers back;
  document the workflow.

### D4 — demo wiring

- Enable PromptPay direct in `sea-saas` instance alongside 2C2P.
- Document "direct PromptPay" vs "PromptPay via 2C2P" trade-off
  (direct = lower fees but requires bank integration setup; via 2C2P
  = faster onboarding, merchant pays aggregator fee).

## Tests

- Unit: ≥ 35 backend (one bank client × 4 + renderer + reconciler),
  ≥ 15 frontend.
- Integration: ≥ 6 bank-sandbox round-trips across 2+ banks.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **Bank API heterogeneity**: KBank / SCB / BBL / Krungsri all have
  different webhook formats + auth schemes. `IBankReconciler`
  abstracts them; ship KBank + SCB in v1, others in S41.1.
- **Reference stripping**: some Thai banks strip the QR reference
  on the statement line. `PromptPayReconciler` falls back to
  amount+timestamp window (±5 min, ±0 THB); ambiguous matches are
  surfaced to admin for manual resolution.
- **QR expiry**: default 10 min. Shorter than most wallet QRs because
  Thai customers complete quickly via bank app.

## Open questions

- [ ] **Q1** — launch-set of banks: KBank + SCB, or also BBL +
  Krungsri? Recommended **KBank + SCB for v1** (largest SME share).
- [ ] **Q2** — static QR for low-value repeat customers? Recommended
  **no in v1** — reconciliation is harder without the embedded
  amount; revisit for POS use case.

## Effort estimate

- QR renderer + EMVCo spec: **0.5 day**
- Bank adapters (KBank + SCB) + reconciler: **2 days**
- Service + routes + webhooks: **1 day**
- fe-user QR + polling: **0.75 day**
- fe-admin config + reconciliation dashboard: **1 day**
- Demo wiring: **0.25 day**

**Total: ~5.5 person-days.**
