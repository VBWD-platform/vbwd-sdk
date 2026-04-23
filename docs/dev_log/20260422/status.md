# Dev Log — 2026-04-22

## Theme

Global payment-plugin catalogue. Seven new payment-gateway plugins
scoped as independent sprints, following the per-wedge and per-region
analysis in
[`payment-plugins-market.md`](../../dev_docs/market-research/payment-plugins-market.md).

Each sprint:
- Delivers a dedicated `vbwd-plugin-<name>` backend plugin, a
  `vbwd-fe-user-plugin-<name>` checkout plugin, and a
  `vbwd-fe-admin-plugin-<name>` admin plugin — all in standalone
  repos per `feedback_plugins_always_in_own_repos.md`.
- Ships a demo instance in `vbwd-demo-instances/instances/local/`
  so a prospect can run the wedge end-to-end in one `make up`.
- Inherits the full TDD / DevOps / SOLID / DRY / DI / clean-code /
  no-over-engineering / drop-deprecated framework from
  [Sprint 29](sprints/29-klarna-dach-wedge.md#core-engineering-requirements-binding-for-every-deliverable).

## Sprints

| # | Sprint | Region | Wedge | Effort | Status |
|---|--------|--------|-------|--------|--------|
| 29 | [Klarna + SEPA DD (DACH wedge)](sprints/29-klarna-dach-wedge.md) | EU | §6.1 Klarna without Shopify | 10.5 d | Planned |
| 30 | [Mollie (EU aggregator)](sprints/30-mollie-eu-aggregator.md) | EU | EU broad-stroke | 4.75 d | Planned |
| 31 | [2C2P (ASEAN aggregator)](sprints/31-2c2p-asean-aggregator.md) | ASEAN | §6.2 SEA SaaS Launchpad | 5.75 d | Planned |
| 32 | [TrueMoney (TH wallet)](sprints/32-truemoney-thailand-wallet.md) | Thailand | §6.2 SEA extension | 3.5 d | Planned |
| 33 | [Mercado Pago (LATAM)](sprints/33-mercado-pago-latam.md) | LATAM | §6.5 Pan-LATAM | 8 d | Planned |
| 34 | [Toss Payments (Korea)](sprints/34-toss-payments-korea.md) | Korea | §6.4 Korean Creator Pack | 7 d | Planned |
| 35 | [Conekta (Mexico)](sprints/35-conekta-mexico.md) | Mexico | §6.1-ish MX depth | 5.5 d | Planned |

**Total:** 45 person-days; 7 payment-gateway plugins; 21 new repos (7
backend + 7 fe-user + 7 fe-admin); 5 new demo instances (`dach-shop`,
`eu-shop`, `sea-saas`, `latam-shop`, `kr-saas`, `mx-shop`).

## Regional coverage after completion

| Region | Countries unlocked | Methods exposed |
|--------|--------------------|-----------------|
| EU + UK (Sprints 29, 30) | DE, AT, CH, NL, BE, FR, UK, PL, ES, IT, + EU-wide SEPA | Klarna BNPL, iDEAL, Bancontact, SOFORT, P24, EPS, Giropay, Pay-later / Pay-in-3, cards, SEPA DD |
| ASEAN (Sprint 31) | TH, SG, MY, PH, VN, ID, HK, TW | PromptPay, PayNow, DuitNow, QRIS, GCash, MoMo, ShopeePay, TrueMoney (via 2C2P), Alipay, WeChat Pay, FPX, cards |
| Thailand direct (Sprint 32) | TH | TrueMoney Wallet (direct settlement, better merchant rate) |
| LATAM (Sprint 33) | BR, MX, AR, CO, CL, UY, PE | Pix, Boleto, OXXO, SPEI, PSE, Webpay, PagoEfectivo, RapiPago, cards with parcelamento / MSI |
| Korea (Sprint 34) | KR | Toss widget (cards + KakaoPay + Naver Pay + Samsung Pay + bank), cash receipt (현금영수증), tax invoice stub |
| Mexico (Sprint 35) | MX | Conekta cards + MSI 3/6/9/12 + OXXO + SPEI |

Combined with existing Stripe, PayPal, YooKassa plugins this brings
the VBWD payment catalogue to **≥ 90 countries** — the "minimum viable
9-plugin stack" in
[`payment-plugins-market.md §3.1`](../../dev_docs/market-research/payment-plugins-market.md).

## Suggested execution order

Sprints can run in parallel. Recommended sequencing if capacity is
constrained:

1. **Wave 1 (EU quickwin)**: Sprint 30 (Mollie) + Sprint 29 (Klarna).
   Mollie ships fast (4.75 d) and is the quickest way to put a working
   DACH demo in front of agency partners while Klarna finishes.
2. **Wave 2 (ASEAN)**: Sprint 31 (2C2P) as primary; Sprint 32
   (TrueMoney) as a follow-on if/when a Thai merchant wants direct
   settlement.
3. **Wave 3 (LATAM)**: Sprint 33 (Mercado Pago) + Sprint 35 (Conekta)
   in parallel — MP for pan-LATAM breadth, Conekta for MX depth.
4. **Wave 4 (Korea)**: Sprint 34 (Toss Payments) on its own; partner
   outreach with Toss Payments partner team starts Day 1.

## Dependencies

- **Core PDF service** (from Sprint 28, `vbwd-backend/vbwd/services/pdf_service.py`)
  is reused by Sprints 29 (SEPA mandate PDF), 33 (Boleto / OXXO /
  PagoEfectivo vouchers), 35 (OXXO voucher). Sprint 28 must be merged
  before these ship.
- **`IPaymentAdapter` interface** (already in `vbwd-backend`) is the
  contract all 7 plugins implement. Verify backward compatibility
  before multiple plugins register concurrently.
- **Demo-instance routing** (`vbwd-demo-instances/instances/local/*`)
  relies on existing nginx-based port-routing. No core change needed.

## Out-of-scope follow-ups (tracked separately)

- `vbwd-plugin-adyen` — enterprise-tier aggregator (~EU €1T volume).
  Own sprint when first ≥ USD 10M TPV merchant asks.
- `vbwd-plugin-dlocal` — cross-border emerging-markets aggregator.
  Complements Mercado Pago; defer until post-Wave-3.
- `vbwd-plugin-komoju` — Japanese aggregator (PayPay + LINE Pay +
  Konbini + cards). Market wedge §6.3 — separate sprint once Wave 4
  (Toss Korea) ships, to reuse the learnings on East-Asia flows.
- `vbwd-plugin-payu` / `vbwd-plugin-kushki` — Andean LATAM coverage
  beyond Mercado Pago.
- `vbwd-plugin-maya` / `vbwd-plugin-gcash-direct` / `vbwd-plugin-momo-direct`
  — direct-wallet ASEAN plugins (complement 2C2P the way Sprint 32
  complements it for TrueMoney).

## Market Research

| Report | Path |
|--------|------|
| Payment Plugins — Market Analysis & VBWD Go-to-Market | [payment-plugins-market.md](../../dev_docs/market-research/payment-plugins-market.md) |
| Payment Plugins EU | [payment-plugins-eu.md](../../dev_docs/market-research/payment-plugins-eu.md) |
| Payment Plugins ASEAN + JP + KR | [payment-plugins-asean.md](../../dev_docs/market-research/payment-plugins-asean.md) |
| Payment Plugins LATAM | [payment-plugins-latam.md](../../dev_docs/market-research/payment-plugins-latam.md) |

## Reports

_None yet — sprints are planned, not started._

## Links

- Previous dev log: [`20260403/status.md`](../20260403/status.md)
- Project guide: [`../../CLAUDE.md`](../../CLAUDE.md)
