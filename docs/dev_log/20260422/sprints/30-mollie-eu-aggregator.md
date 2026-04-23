# Sprint 30 — Mollie (EU aggregator plugin)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market wedge:** Europe broad-stroke — one plugin unlocks 15+ EU local
methods (iDEAL, Bancontact, SOFORT, Przelewy24, Klarna via Mollie,
EPS, Giropay, PayPal, cards, SEPA).
See [`payment-plugins-market.md §2.1`](../../../dev_docs/market-research/payment-plugins-market.md)
and [`payment-plugins-eu.md`](../../../dev_docs/market-research/payment-plugins-eu.md).

**Repos touched:**
- `vbwd-plugin-mollie` (NEW — backend adapter + webhook receiver)
- `vbwd-fe-user-plugin-mollie` (NEW — hosted-checkout redirect UI +
  embedded "Components" card entry)
- `vbwd-fe-admin-plugin-mollie` (NEW — API-key config, method toggle,
  transaction list)
- `vbwd-demo-instances/instances/local/eu-shop/` (existing or new EU
  demo instance — enable Mollie)

## Goal

One plugin, 15+ EU local payment methods, zero per-method integration
debt. After this sprint a VBWD operator can:

1. Paste a Mollie API key in the admin panel.
2. Toggle which of the 15 supported methods to expose on checkout.
3. Watch transactions, refunds, and chargebacks flow into VBWD's
   invoice + order state automatically via Mollie webhooks.

**Commercial wedge:** Dutch / Belgian / German SMB e-commerce merchants
who currently use Shopify + Mollie and want to own their checkout. One
Mollie plugin replaces several competitors' separate "iDEAL",
"Bancontact", "SOFORT" plugins.

## Engineering requirements

Inherit the full framework from
[Sprint 29 §Core engineering requirements](29-klarna-dach-wedge.md#core-engineering-requirements-binding-for-every-deliverable)
— TDD-first, DevOps-first, SOLID, DRY, DI, clean names, no
over-engineering, drop-deprecated. Specific checkpoints:

- `MollieAdapter.create_payment(order, method)` spec authored before
  implementation: happy path + invalid method 422 + idempotency on
  Mollie's `metadata.vbwd_order_id`.
- `MollieWebhookHandler.handle(payment_id)` spec authored first:
  Mollie webhooks carry only the payment id, so handler must fetch the
  payment and reconcile state. Spec covers `paid`, `failed`, `expired`,
  `canceled`, `refunded` transitions. Idempotency enforced by storing
  the last-observed Mollie status per payment.
- `MollieBlueprint` route specs: create-payment-session, return-url,
  webhook-callback.
- Methods launched in v1: `ideal`, `bancontact`, `creditcard`,
  `paypal`, `sofort`, `eps`, `giropay`, `przelewy24`, `kbc`, `klarna`,
  `belfius`, `directdebit`, `applepay`, `banktransfer`. Easy to add more
  via config; hard-coded allow-list to prevent typos in merchant config.

## Deliverables

### D1 — `vbwd-plugin-mollie` backend

- Folder structure: `mollie/`, `mollie/mollie/` for source (plugin-id
  convention from `MEMORY.md`).
- `adapters/mollie_adapter.py` — thin wrapper over the official
  `mollie-api-python` client (pinned `>=3.5`).
- `services/mollie_service.py` — VBWD domain mapping: given a VBWD
  invoice + chosen method, build Mollie `Payment` request; on webhook,
  reconcile by `payment.metadata.vbwd_invoice_id`.
- `routes.py` — blueprint under `/api/v1/mollie/`:
  - `POST /payments` — create Mollie payment for an invoice; returns
    `{ checkout_url }` for hosted flow, or `{ component_token }` for
    Mollie Components card embedding.
  - `GET /payments/:id/status` — client polling during redirect return
    flow.
  - `POST /webhooks` — Mollie webhook receiver; verifies by fetching
    the payment via API (Mollie webhooks are unsigned but safe because
    they only contain an id — content is retrieved server-side with the
    trusted API key).
- `models/mollie_payment.py` — minimal record: mollie_id, vbwd_invoice_id,
  method, status, last_observed_status, created_at.
- Alembic migration creating the one table.
- Implements `IPaymentAdapter` interface.
- 3.0 test coverage of adapter + service + webhook (≥ 30 unit tests,
  ≥ 6 integration tests against Mollie test API).

### D2 — `vbwd-fe-user-plugin-mollie`

- Two checkout experiences in one plugin:
  1. **Hosted checkout** (default) — redirect user to Mollie's hosted
     payment page, which handles method-selection UI.
  2. **Method-picked checkout** — VBWD's own method-picker UI (radio
     list of methods with logos), then Mollie's per-method redirect or
     Components card-entry inline.
- `components/MollieMethodPicker.vue` — grid of enabled method logos +
  names (i18n).
- `components/MollieCardForm.vue` — wraps Mollie Components JS for
  inline card entry (PCI SAQ-A eligible — card data never touches VBWD).
- `stores/mollie.ts` — list of enabled methods (fetched from backend
  config endpoint), payment status polling helper.
- i18n: en, nl, de, fr, pl for launch.
- Playwright E2E: iDEAL happy path (sandbox), card happy path, webhook
  arrives and order transitions to `paid`.

### D3 — `vbwd-fe-admin-plugin-mollie`

- API key management (write-only masked input, test-mode toggle).
- Method allow-list: list of 14 supported methods with enable/disable
  checkboxes + "Live-enabled at Mollie?" indicator (fetched from Mollie
  `GET /methods`).
- Transaction list with status filters + link back to Mollie dashboard
  for each payment.
- No chargeback UI in v1 — Mollie handles chargebacks; VBWD just
  reflects the status.

### D4 — EU demo instance wiring

- `vbwd-demo-instances/instances/local/eu-shop/` — enable Mollie in
  test mode, seed 1 admin + 1 customer + 3 products priced in EUR.
- Document the setup in the instance README.

## Tests

- Unit: ≥ 30 backend, ≥ 20 frontend.
- Integration: ≥ 6 Mollie sandbox round-trips.
- E2E: 2 flows (iDEAL, card).

## Risks

- **Webhook idempotency**: Mollie may retry a webhook. Handler must be
  idempotent — check `last_observed_status` + stored timestamp.
- **Method availability variance**: `creditcard` needs Mollie live-mode
  activation. The admin UI must show each method's live-activation
  status from Mollie's API so the merchant knows what's available.
- **Method rollout**: adding a new method later should not require a
  code change. The allow-list is a DB / config enum, not a hard-coded
  Python literal.

## Open questions

- [ ] **Q1** — ship Mollie Components (inline card) in v1, or
  redirect-only? Recommended **both**, Components is ~1 extra day.
- [ ] **Q2** — handle refunds in admin UI this sprint or ship in S30.1?
  Recommended **S30.1**; v1 shows status only.

## Effort estimate

- Backend adapter + service + webhook + tests: **2 days**
- fe-user (hosted + Components + methods): **1.5 days**
- fe-admin (config + tx list): **1 day**
- EU demo instance: **0.25 day**

**Total: ~4.75 person-days.**
