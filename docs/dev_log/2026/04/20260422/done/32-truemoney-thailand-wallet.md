# Sprint 32 — TrueMoney (Thailand wallet plugin)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market wedge:** Thai SaaS / e-commerce direct-wallet coverage — see
[`payment-plugins-market.md §2.2`](../../../dev_docs/market-research/payment-plugins-market.md)
and [`payment-plugins-asean.md`](../../../dev_docs/market-research/payment-plugins-asean.md).

**Repos touched:**
- `vbwd-plugin-truemoney` (NEW — direct TrueMoney Wallet API adapter,
  independent of 2C2P — some merchants want direct settlement)
- `vbwd-fe-user-plugin-truemoney` (NEW — QR + deep-link UI + status
  polling)
- `vbwd-fe-admin-plugin-truemoney` (NEW — config + transaction list +
  refund)
- `vbwd-demo-instances/instances/local/sea-saas/` (existing from Sprint
  31 — enable TrueMoney alongside 2C2P)

## Goal

Direct TrueMoney Wallet integration so Thai merchants bypass aggregator
fees for the ~30M TrueMoney users in Thailand. Two surfaces in v1:

1. **QR-code flow** — user scans the merchant QR with the TrueMoney
   app, confirms, returns to VBWD, webhook lands, invoice transitions
   to `paid`.
2. **Deep-link flow** — on mobile, user taps a button that opens
   `truemoney://` URL scheme, completes in-app, returns via Universal
   Link / App Link.

TrueMoney can also be reached via 2C2P (Sprint 31). This direct plugin
exists for merchants with a direct TrueMoney merchant agreement and
better rates.

## Engineering requirements

Inherit the full framework from
[Sprint 29 §Core engineering requirements](29-klarna-dach-wedge.md#core-engineering-requirements-binding-for-every-deliverable).
Specific checkpoints:

- `TrueMoneyAdapter.create_transaction(invoice)` spec authored first —
  TrueMoney's OpenAPI requires HMAC-SHA256 signature over a canonical
  message string.
- `TrueMoneyWebhookHandler.handle(payload)` spec authored first —
  signature verification + idempotency by `transaction_id`.
- `TrueMoneyQRRenderer.render_emvco(transaction)` spec authored first
  — emits EMVCo QR payload compatible with TrueMoney app scanner.
- Currency locked to THB; any other currency rejected at validation.

## Deliverables

### D1 — `vbwd-plugin-truemoney` backend

- Folder convention: `vbwd-plugin-truemoney/truemoney/`.
- `adapters/truemoney_adapter.py` — HMAC-signed HTTP client for
  TrueMoney Merchant API. Endpoints: `/transactions`,
  `/transactions/:id`, `/transactions/:id/refund`.
- `services/truemoney_service.py` — invoice → transaction mapping.
- `routes.py`:
  - `POST /api/v1/truemoney/transactions` — create transaction for
    invoice, return `{ qr_payload, deep_link, expires_at }`.
  - `GET /api/v1/truemoney/transactions/:id/status` — polling endpoint.
  - `POST /api/v1/truemoney/webhooks` — signature-verified webhook
    receiver.
- `models/truemoney_transaction.py` — mirrored record: transaction_id,
  invoice_no, amount, status, last_observed_status.
- Alembic migration for the one table.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-truemoney`

- `components/TrueMoneyCheckout.vue` — detects device:
  - **Mobile**: primary button = "Pay with TrueMoney" → deep-link;
    secondary = "Show QR" (for rare cross-device scenarios).
  - **Desktop**: primary = QR (with countdown + poll); secondary =
    mobile deep-link (for users who want to finish on phone via email
    / SMS).
- Auto-poll `/status` every 3s for up to 5 minutes; on terminal state,
  route to `/checkout/success` or show failure UI.
- i18n: th (primary), en.

### D3 — `vbwd-fe-admin-plugin-truemoney`

- Config: merchant id, secret key (write-only masked), webhook URL
  (derived, displayed read-only), test/live toggle.
- Transaction list with status, amount, customer, refund button.

### D4 — Demo instance wiring

- Add TrueMoney to the existing `sea-saas` instance from Sprint 31.
- Seed a second test plan that pays via TrueMoney (to complement the
  2C2P-paid plan).

## Tests

- Unit: ≥ 25 backend, ≥ 15 frontend.
- Integration: ≥ 4 TrueMoney sandbox round-trips.
- E2E: 2 flows (desktop QR, mobile deep-link).

## Risks

- **QR freshness**: TrueMoney QRs expire (typically 15 min). UI must
  render countdown + "Generate new QR" on expiry. Backend must reject
  callback for expired QRs.
- **Deep-link fallback**: if TrueMoney app not installed, deep-link
  silently fails. UI should offer a fallback to "install TrueMoney" or
  "pay via 2C2P instead" after a 5-second no-return timeout.
- **Sandbox access**: TrueMoney Merchant API sandbox requires business
  onboarding. If we can't get a sandbox in time, integration tests gate
  on `TRUEMONEY_SANDBOX=1` and stay skipped in public CI.

## Open questions

- [ ] **Q1** — ship refund UI in v1 or S32.1? Recommended **v1** —
  refund logic is core to merchant trust.
- [ ] **Q2** — store transaction logs for how long? Recommended **24
  months** (matches Thai VAT audit window).

## Effort estimate

- Backend adapter + service + webhook + tests: **1.5 days**
- fe-user (QR + deep-link + polling): **1 day**
- fe-admin (config + tx + refund): **0.75 day**
- Demo wiring: **0.25 day**

**Total: ~3.5 person-days.**
