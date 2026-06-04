# Dev Log — 2026-04-22

## Theme

Global payment-plugin catalogue. Two sprint waves ship in parallel:

1. **Wave A — Aggregator plugins (Sprints 29-35)**: one plugin per
   gateway covers many methods through a single contract.
2. **Wave B — Per-method direct plugins (Sprints 36-56)**: one plugin
   per national-champion payment method for merchants who want lower
   fees, direct settlement, or better UX than aggregator passthrough
   provides.

Every sprint inherits the shared
[core engineering requirements](sprints/_engineering-requirements.md)
(TDD-first, DevOps-first, SOLID/LSP, DRY, DI, Clean Code, No
over-engineering, Drop deprecated, `bin/pre-commit-check.sh --full`
gate, learned lessons from `MEMORY.md`).

## Sprint index

### Wave A — Aggregator plugins

| # | Sprint | Region | Effort | Status |
|---|--------|--------|--------|--------|
| 29 | [Klarna + SEPA DD (DACH wedge)](sprints/29-klarna-dach-wedge.md) | EU | 10.5 d | Planned |
| 30 | [Mollie (EU aggregator)](sprints/30-mollie-eu-aggregator.md) | EU | 4.75 d | Planned |
| 31 | [2C2P (ASEAN aggregator)](done/31-2c2p-asean-aggregator.md) | ASEAN | 5.75 d | **Done 2026-04-22** ([report](reports/01-sprint-31-c2p2.md)) |
| 32 | [TrueMoney (TH direct)](done/32-truemoney-thailand-wallet.md) | Thailand | 3.5 d | **Done 2026-04-22** ([report](reports/02-sprint-32-truemoney.md)) |
| 33 | [Mercado Pago (LATAM)](done/33-mercado-pago-latam.md) | LATAM | 8 d | **Done 2026-04-22** ([report](reports/03-sprint-33-mercado-pago.md)) |
| 34 | [Toss Payments (Korea)](done/34-toss-payments-korea.md) | Korea | 7 d | **Done 2026-04-24** ([report](reports/04-sprint-34-toss-payments.md)) |
| 35 | [Conekta (Mexico)](done/35-conekta-mexico.md) | Mexico | 5.5 d | **Done 2026-04-24** ([report](reports/05-sprint-35-conekta.md)) |

**Wave A subtotal:** ~45 person-days, 7 plugins.

### Wave B — Per-method direct plugins

| # | Sprint | Method | Region | Effort | Status |
|---|--------|--------|--------|--------|--------|
| 36 | [iDEAL (Netherlands)](sprints/36-ideal-netherlands.md) | iDEAL 2.0 direct | NL | 4.75 d | Planned |
| 37 | [Bancontact / Payconiq](sprints/37-bancontact-belgium.md) | Bancontact + Payconiq | BE | 4 d | Planned |
| 38 | [Przelewy24](sprints/38-przelewy24-poland.md) | P24 bank-redirect + BLIK | PL | 4.25 d | Planned |
| 39 | [BLIK (direct)](sprints/39-blik-poland.md) | BLIK via acquirer bank | PL | 3 d | Planned |
| 40 | [SOFORT](sprints/40-sofort-sepa-bank-transfer.md) | Klarna SOFORT direct | DACH + EU | 3 d | Planned |
| 41 | [PromptPay (direct)](done/41-promptpay-thailand.md) | PromptPay QR + bank recon | TH | 5.5 d | **Done 2026-04-24** ([report](reports/06-sprint-41-promptpay.md)) |
| 42 | [PayNow (direct)](sprints/42-paynow-singapore.md) | PayNow SGQR + bank recon | SG | 4.75 d | Planned |
| 43 | [QRIS](sprints/43-qris-indonesia.md) | QRIS MPM dynamic | ID | 4.75 d | Planned |
| 44 | [GCash (direct)](sprints/44-gcash-philippines.md) | GCash Merchant API | PH | 3 d | Planned |
| 45 | [MoMo (direct)](sprints/45-momo-vietnam.md) | MoMo Merchant API | VN | 3 d | Planned |
| 46 | [GrabPay](sprints/46-grabpay-asean.md) | GrabPay pan-ASEAN | SG/MY/ID/PH/TH/VN | 3.75 d | Planned |
| 47 | [PayPay (direct)](sprints/47-paypay-japan.md) | PayPay for Business v2 | JP | 3.25 d | Planned |
| 48 | [Konbini](sprints/48-konbini-japan-cash.md) | Konbini cash voucher | JP | 6 d | Planned |
| 49 | [LINE Pay](sprints/49-line-pay-jp-tw-th.md) | LINE Pay v3 | JP/TW/TH | 4 d | Planned |
| 50 | [KakaoPay (direct)](sprints/50-kakao-pay-korea.md) | KakaoPay Online | KR | 3.25 d | Planned |
| 51 | [Naver Pay (direct)](sprints/51-naver-pay-korea.md) | Naver Pay E-commerce | KR | 3 d | Planned |
| 52 | [Alipay / Alipay+](sprints/52-alipay-plus.md) | Alipay + pan-Asian wallets | CN + regional | 4.5 d | Planned |
| 53 | [WeChat Pay](sprints/53-wechat-pay.md) | WeChat Pay v3 (Native + H5) | CN + cross-border | 3.75 d | Planned |
| 54 | [Pix (direct)](sprints/54-pix-brazil.md) | Pix via Banco Inter + Gerencianet | BR | 6.75 d | Planned |
| 55 | [Boleto Bancário](sprints/55-boleto-brazil.md) | Boleto via Itaú + BB | BR | 7.5 d | Planned |
| 56 | [PSE (Colombia)](sprints/56-pse-colombia.md) | PSE via Wompi + ePayco | CO | 5.25 d | Planned |

**Wave B subtotal:** ~91 person-days, 21 plugins.

**Grand total:** 28 plugins, ~136 person-days, 84 new repos
(28 backend + 28 fe-user + 28 fe-admin), ~12 new demo instances.

## Engineering contract

Every sprint in this log is bound by
[`sprints/_engineering-requirements.md`](sprints/_engineering-requirements.md).
Key non-negotiables summarised:

1. **TDD-first** — specs authored, failing, then implementation; no
   "refactor now, test later".
2. **DevOps-first** — `bin/pre-commit-check.sh --full` green on every
   touched repo; Alembic migrations only (no raw SQL); no `# noqa` or
   `# type: ignore` without user approval.
3. **SOLID + Liskov** — `IPaymentAdapter` implementations must honour
   every postcondition of the base contract; subclasses never weaken.
4. **DRY** — no copy-paste between plugins; one HTTP factory per
   plugin; promote helpers only on third consumer.
5. **Dependency injection** — constructor DI, no module-level
   singletons.
6. **Clean code** — full pronounceable names
   (`feedback_variable_naming.md`); <30-line functions; zero "what"
   comments; "why" only for regulatory rules.
7. **No over-engineering** — no generic routing frameworks, no retry
   layers, no analytics dashboards without real-merchant ask.
8. **Drop deprecated** — delete, don't comment out; no
   `// @deprecated`; never leave on temp branches
   (`feedback_no_temp_branches.md`); work in SDK dirs not `/tmp`
   (`feedback_work_in_sdk_dirs.md`).

## Plugin structure (reminder)

From `MEMORY.md`:

```
vbwd-plugin-<name>/
  <name>/__init__.py          # Plugin class
  <name>/<name>/               # plugin-id source dir
    adapters/, services/, routes.py, models/, utils/
  tests/unit/, tests/integration/
  alembic/versions/
  populate_db.py
  plugins.json patch + config.json patch
```

fe-user plugins use **named exports** per `MEMORY.md` fe-user
Plugin Export Convention.

Plugin enable/disable state lives centrally in
`${VAR_DIR}/plugins/*-plugins.json` — the backend is the only writer;
all three apps (backend / fe-admin / fe-user) read from the same
directory (per updated CLAUDE.md §Plugin Management).

## Regional coverage after full completion

| Region | Sprints | Methods unlocked |
|--------|---------|------------------|
| EU + UK | 29, 30, 36, 37, 38, 39, 40 | Klarna, SEPA DD, 15+ Mollie methods, iDEAL 2.0 direct, Bancontact+Payconiq direct, P24, BLIK, SOFORT |
| ASEAN | 31, 32, 41, 42, 43, 44, 45, 46, 49 | 2C2P 12 methods, TrueMoney direct, PromptPay direct, PayNow direct, QRIS direct, GCash direct, MoMo direct, GrabPay 6 countries, LINE Pay |
| Japan | 47, 48, 49 | PayPay direct, Konbini direct, LINE Pay JP |
| Korea | 34, 50, 51 | Toss full suite, KakaoPay direct, Naver Pay direct |
| China + cross-border | 52, 53 | Alipay + Alipay+, WeChat Pay |
| LATAM | 33, 35, 54, 55, 56 | Mercado Pago 7-country, Conekta MX full, Pix direct, Boleto direct, PSE Colombia |

Combined with existing Stripe, PayPal, YooKassa plugins this brings
the VBWD payment catalogue to **≥ 90 countries** and covers every
rail from
[`payment-plugins-market.md §3.1`](../../dev_docs/market-research/payment-plugins-market.md)
with at least one sprint per national champion.

## Execution strategy

### Priority order (recommended)

1. **Wave A first** — aggregator plugins unlock the most countries per
   day of work. Complete 29 (Klarna+SEPA) + 30 (Mollie) for a DACH/EU
   MVP in 15 days. Then 33 (Mercado Pago) + 31 (2C2P) + 34 (Toss) for
   global reach.
2. **Wave B as merchants ask.** Direct per-method plugins are
   economically justified only for merchants with enough volume to
   benefit from lower rates. Ship in order of merchant demand.
3. **Exceptions — ship early in Wave B:**
   - **Sprint 41 (PromptPay direct)** and **54 (Pix direct)** should
     ship in the first Wave B batch because the aggregator fee
     savings are disproportionately large (>1%) and both are highly
     requested by prospects.
   - **Sprint 47 (PayPay direct)** should pair with Sprint 48 (Konbini)
     for a complete "JP pack" that covers ~70% of Japanese consumer
     preference.

### Parallelism

- All plugins are independent repos with no shared code — any number
  of sprints run in parallel with independent devs.
- Shared dependencies: core `PdfService` (Sprint 28) is required by
  33, 48, 55, 56. Core `IPaymentAdapter` is required by every sprint —
  already in `vbwd-backend`.

## Dependencies

- **Sprint 28** (already done / in-progress) — provides core
  `PdfService` for cash-voucher and boleto rendering. Blocks Sprints
  48, 55.
- **`IPaymentAdapter` interface** — already in `vbwd-backend`. No
  modification required.
- **`${VAR_DIR}/plugins/` plugin state directory** (per updated
  CLAUDE.md §Plugin Management) — backend enable/disable routes are
  the single writer; verify before merging any Wave sprint.

## Out-of-scope follow-ups (tracked separately)

- `vbwd-plugin-adyen` — enterprise-tier aggregator (for merchants
  ≥ USD 10M TPV).
- `vbwd-plugin-dlocal` — cross-border emerging-markets aggregator.
- `vbwd-plugin-komoju` — Japanese aggregator (alternative to direct
  PayPay/Konbini/LINE Pay).
- `vbwd-plugin-payu` — pan-LATAM aggregator (alternative to Mercado
  Pago + Conekta for merchants who prefer PayU's UX).
- `vbwd-plugin-kushki` — Andean modern gateway (PE/EC/CL).
- `vbwd-plugin-maya`, `vbwd-plugin-ovo`, `vbwd-plugin-dana`,
  `vbwd-plugin-truemoney-subwallet` — direct-wallet plugins for
  secondary ASEAN wallets.
- `vbwd-plugin-rakuten-pay`, `vbwd-plugin-aupay`,
  `vbwd-plugin-merpay` — secondary JP wallets.
- `vbwd-plugin-samsung-pay`, `vbwd-plugin-payco` — secondary KR
  wallets.
- `vbwd-plugin-oxxo-direct`, `vbwd-plugin-spei-direct` — MX direct
  alternatives to Conekta (S35) for merchants with direct bank
  relationships.
- `vbwd-plugin-webpay-transbank`, `vbwd-plugin-pagoefectivo`,
  `vbwd-plugin-yape`, `vbwd-plugin-nequi` — LATAM country-direct
  methods.
- `vbwd-plugin-revolut-pay`, `vbwd-plugin-truelayer` — EU open-banking
  alternatives.

## Market Research

| Report | Path |
|--------|------|
| Payment Plugins — Market Analysis & VBWD Go-to-Market | [payment-plugins-market.md](../../dev_docs/market-research/payment-plugins-market.md) |
| Payment Plugins EU | [payment-plugins-eu.md](../../dev_docs/market-research/payment-plugins-eu.md) |
| Payment Plugins ASEAN + JP + KR | [payment-plugins-asean.md](../../dev_docs/market-research/payment-plugins-asean.md) |
| Payment Plugins LATAM | [payment-plugins-latam.md](../../dev_docs/market-research/payment-plugins-latam.md) |

## Reports

| # | Report | Date |
|---|--------|------|
| 01 | [Sprint 31 — 2C2P plugin](reports/01-sprint-31-c2p2.md) | 2026-04-22 |
| 02 | [Sprint 32 — TrueMoney plugin](reports/02-sprint-32-truemoney.md) | 2026-04-22 |
| 03 | [Sprint 33 — Mercado Pago plugin](reports/03-sprint-33-mercado-pago.md) | 2026-04-22 |
| 04 | [Sprint 34 — Toss Payments plugin](reports/04-sprint-34-toss-payments.md) | 2026-04-24 |
| 05 | [Sprint 35 — Conekta plugin](reports/05-sprint-35-conekta.md) | 2026-04-24 |
| 06 | [Sprint 41 — PromptPay plugin](reports/06-sprint-41-promptpay.md) | 2026-04-24 |
| 07 | [Session summary — payment plugins](reports/07-session-summary-payment-plugins.md) | 2026-04-24 |

## Links

- Shared engineering contract: [`sprints/_engineering-requirements.md`](sprints/_engineering-requirements.md)
- Previous dev log: [`20260403/status.md`](../20260403/status.md)
- Project guide: [`../../CLAUDE.md`](../../CLAUDE.md)
- MEMORY index: [`~/.claude/projects/-Users-dantweb-dantweb-vbwd-sdk-2/memory/MEMORY.md`](/Users/dantweb/.claude/projects/-Users-dantweb-dantweb-vbwd-sdk-2/memory/MEMORY.md)
