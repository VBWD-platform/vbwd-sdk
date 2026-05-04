# Sprint 54 — Pix (Brazil direct, via PSPs)

**Status:** PLANNED — 2026-04-22
**Date:** 2026-04-22
**Market context:** Pix is the BCB (Banco Central do Brasil) national
instant-payment rail. 2023 volume surpassed cards. 40B+ tx/yr, 150M
users. Used by every BR e-commerce. Direct connection to BCB requires
a bank; most merchants integrate via a Pix-PSP (Banco Inter, Gerencianet,
PagSeguro, Stone, or corporate-bank Pix API).

**Repos touched:**
- `vbwd-plugin-pix` (NEW — Pix PSP-adapter abstraction with Banco
  Inter + Gerencianet as v1 concrete clients)
- `vbwd-fe-user-plugin-pix` (NEW — QR + copy-paste key + poll UI)
- `vbwd-fe-admin-plugin-pix` (NEW — config + tx list)
- `vbwd-demo-instances/instances/local/br-shop/` (NEW — BR demo
  instance, independent of the pan-LATAM `latam-shop` for Sprint 33)

## Goal

Direct Pix plugin for Brazilian merchants who want to bypass Mercado
Pago / Stripe aggregation fees. Pix per-transaction cost is BRL 0 or
a tiny fixed amount at the PSP level — aggregators charge 0.99-1.99%.
For a BRL 1M/mo merchant, the fee difference is BRL 20K/mo.

## Core engineering requirements

See [`_engineering-requirements.md`](./_engineering-requirements.md).

**Method-specific TDD checkpoints:**
- `IPixPspAdapter` interface spec first — methods:
  `create_charge(invoice)`, `get_charge(txid)`,
  `create_refund(e2e_id, amount)`.
- `BancoInterPixAdapter`, `GerencianetPixAdapter` concrete
  implementations — mTLS with client cert; token cache;
  `/v2/cob/:txid` POST + GET.
- `PixQRRenderer.render(emv_payload)` spec first — BRcode EMV
  format per BCB spec; CRC16/CCITT-FALSE snapshot.
- `PixWebhookHandler` spec first — signature verify + idempotency
  by `txid` and `endToEndId`.

## Deliverables

### D1 — `vbwd-plugin-pix` backend

- Folder: `vbwd-plugin-pix/pix/`.
- `adapters/base.py` — `IPixPspAdapter`.
- `adapters/banco_inter.py`, `adapters/gerencianet.py` — v1
  concrete PSPs.
- `adapters/pix_qr_renderer.py` — BRcode EMV builder with CRC16.
- `services/pix_service.py` — invoice → charge; TXID generation
  (26-char uuid-derived per BCB spec); reconciliation.
- `routes.py`:
  - `POST /api/v1/pix/charges` — create.
  - `POST /api/v1/pix/webhooks/<psp>` — verified per-PSP receiver.
  - `GET /api/v1/pix/charges/:txid/status` — polling.
  - `POST /api/v1/pix/charges/:txid/refund` — refund.
- `models/pix_charge.py` — txid, e2e_id, invoice_no, amount,
  status, qr_payload, expires_at.
- Alembic migration.
- Implements `IPaymentAdapter`.

### D2 — `vbwd-fe-user-plugin-pix`

- `components/PixQR.vue` — QR + copy-paste key (BRcode string
  with "copy" button) + 30-min countdown + auto-poll.
- Mobile: deep-link `pix://` (works on most BR banking apps).
- i18n: pt-BR (primary), en.
- E2E: QR happy path, copy-paste happy path, expiry.

### D3 — `vbwd-fe-admin-plugin-pix`

- Config: PSP selector, merchant-certificate path + passphrase,
  Pix key (CPF / CNPJ / email / phone / random).
- Transaction list with e2e_id, txid, status, refund button.

### D4 — BR demo instance

- `vbwd-demo-instances/instances/local/br-shop/` — localhost BR
  demo with Pix in Banco Inter sandbox.
- Seed: 1 admin, 1 BR customer (CPF), 3 products in BRL.
- README: "clone, `make up`, buy with Pix sandbox".

## Tests

- Unit: ≥ 40 backend (2 PSP adapters × mapping + renderer +
  service + webhook), ≥ 15 frontend.
- Integration: ≥ 6 PSP sandbox round-trips.
- E2E: 2 flows.
- `bin/pre-commit-check.sh --full` green.

## Risks

- **mTLS certificate handling**: each Pix PSP issues a client cert
  per merchant. Store paths in env, never commit; cert expiry
  warnings at startup.
- **TXID collisions**: must be 26-chars and unique per merchant.
  Use uuid4 hex (32-char) trimmed to 26 — document the pattern.
- **CRC16 polynomial**: BRcode uses CRC16/CCITT-FALSE. Wrong
  polynomial = QR rejected silently. Snapshot test catches
  regressions.

## Effort estimate

- Base interface + QR renderer: **0.75 day**
- 2 PSP adapters (Inter + Gerencianet) + mTLS: **2.5 days**
- Service + routes + webhook + reconciler: **1.25 days**
- fe-user QR + copy + polling: **1 day**
- fe-admin config + tx list: **0.75 day**
- BR demo: **0.5 day**

**Total: ~6.75 person-days.**
