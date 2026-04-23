# Payment Plugins — Market Analysis & VBWD Go-to-Market

**Date:** 2026-04-22
**Scope:** EU + UK, ASEAN + JP + KR, LATAM — synthesised from the three
regional inventories
([`payment-plugins-eu.md`](payment-plugins-eu.md),
[`payment-plugins-asean.md`](payment-plugins-asean.md),
[`payment-plugins-latam.md`](payment-plugins-latam.md))
**Purpose:** Map the payment-rail landscape across our three priority
regions, size each rail, identify which providers are the highest-leverage
partners for VBWD, and outline concrete plays to win merchants onto
VBWD-based subscription solutions.

---

## 1. Executive Summary

Across the three target regions the payment landscape consolidates around
**three archetypes**:

1. **Regional aggregators** (Stripe, Adyen, Mollie, 2C2P, dLocal, Mercado
   Pago). A single integration unlocks 5–20+ countries. These are where
   VBWD should spend integration budget first — one plugin, broadest
   merchant reach.
2. **National champions** (Pix in Brazil, PromptPay in Thailand, iDEAL in
   the Netherlands, KakaoPay in Korea, PayPay in Japan). No aggregator
   substitutes them at scale; they are non-negotiable for merchants
   selling into those markets.
3. **Cash-voucher / bank-redirect rails** (OXXO, Boleto, Konbini,
   PagoEfectivo, Bancontact, P24). Thin margins per rail but they unlock
   the unbanked / cash-preferring segment — and are the #1 reason
   merchants buy into a platform instead of rolling their own.

The fastest path to a global payment stack inside VBWD is **~9 plugins**
(3 already built + 6 aggregators) covering **60+ countries** and an
estimated **≥USD 6T combined annual processed volume**.

The partnership angle for VBWD is attractive: every provider in this
document runs a partner / ISV programme with revenue share, co-marketing,
and preferential processing rates. Because VBWD sits one layer above
these gateways (as an OSS billing + subscription platform), it is a
natural distribution channel for them — not a competitor.

---

## 2. Master Market Table

Columns:

- **Rail** — provider name.
- **Region** — primary geography.
- **Type** — Agg (aggregator), Wallet, Cash, BNPL, Bank-redirect,
  Card-gateway, Instant-rail.
- **Share** — best-public-knowledge estimate of the rail's share within
  its primary geography (or rank).
- **Annual volume** — transaction count or GMV. `est.` for triangulated
  numbers, exact where publicly disclosed.
- **Users / merchants** — headline adoption number.
- **Notable merchants** — publicly-known operators using the rail.
- **VBWD tier** — our implementation priority (T0 built, T1–T3 from the
  three regional reports).

### 2.1 EU + UK

| Rail | Type | Primary share | Annual volume | Users / merchants | Notable merchants | VBWD tier |
|------|------|---------------|---------------|-------------------|-------------------|-----------|
| **Stripe** | Agg / Card-gateway | #1 online card acquirer in DACH/UK for SaaS | ~USD 1.4T processed globally (2023 disclosed) | ~4M+ merchants | Amazon Pay backend, Shopify merchants, BMW, Uber | T0 – built |
| **PayPal** | Wallet + card | ~40% of EU online checkout reach | ~USD 1.5T TPV (2023) | 435M active accounts globally | eBay, Zalando, ASOS, AliExpress, Booking.com | T0 – built |
| **Mollie** | Agg (EU local methods) | #1 SMB gateway NL/BE; fast-growing DE/FR | EUR 35B+ processed (2023) | 200K+ merchants | Helloprint, Brand New Day, Picnic | T1 |
| **Klarna** | BNPL | #1 BNPL in DACH + Nordics; ~25% of checkouts in SE/DE fashion | ~USD 100B GMV (2023) | 150M consumers, 500K merchants | H&M, IKEA, Sephora, Nike, Peloton | T1 |
| **SEPA Direct Debit** | Instant-rail (euro) | Universal across 36 SEPA countries | 22B+ transactions/yr (ECB) | All EU bank accounts | GoCardless, utilities, insurers, SaaS recurring | T1 |
| **iDEAL** | Bank-redirect | 70%+ of NL online payments | ~1.1B transactions/yr | 15M+ users (~90% NL adults) | Bol.com, Coolblue, Dutch tax authority | T2 |
| **Bancontact / Payconiq** | Bank-redirect + wallet | 80%+ of BE card payments | ~2B transactions/yr | 12M+ BE users | Colruyt, Delhaize, bpost | T2 |
| **Przelewy24 (P24)** | Bank-redirect agg | 50%+ of PL e-commerce payments | est. USD 30B+/yr | 200K+ merchants | Allegro, Zalando PL, mBank | T2 |
| **Adyen** | Enterprise Agg | ~5% of global card volume at enterprise tier | USD 970B TPV (2023 disclosed) | 6K+ enterprise merchants | Uber, Spotify, Microsoft, McDonald's, eBay | T3 |
| **Revolut Pay** | Fintech wallet | Emerging; strongest in UK/IE/Baltics | est. USD 30B TPV | 45M personal + 500K business | Wizz Air, Booking (early adopter), Revolut-native storefronts | T3 |

### 2.2 ASEAN + Japan + Korea

| Rail | Type | Primary share | Annual volume | Users / merchants | Notable merchants | VBWD tier |
|------|------|---------------|---------------|-------------------|-------------------|-----------|
| **2C2P** | Regional Agg | Top-3 gateway in TH/SG/MY; multi-country PSP | USD 100B+ TPV disclosed for AsiaPay group tier | 400K+ merchants regional | AirAsia, Grab, Lazada, Tesco Lotus, Shell SEA | T1 |
| **dLocal** | Cross-border Agg | #1 emerging-market cross-border PSP | USD 21B TPV (2023 disclosed) | 800+ global merchants | Spotify, Amazon, Nike, Microsoft, Didi | T1 |
| **Toss Payments** | KR Modern Gateway | Fast-growing #2 KR gateway by transaction count | est. USD 60B+ TPV | 21M+ Toss users; 150K+ merchants | Coupang partners, Kakao merchants, local SaaS | T1 |
| **PromptPay + Thai QR** | Instant-rail (national) | Universal — linked to national ID / phone | 30B+ transactions/yr | ~70M TH bank-account holders | 7-Eleven TH, Lazada TH, government payments | T2 |
| **PayPay (JP)** | QR Wallet | #1 QR payment in Japan | est. USD 80B+ TPV | 60M+ users, 3.8M+ merchants | LAWSON, FamilyMart, Rakuten, Sogo | T2 |
| **KakaoPay** | Wallet / super-app | #1 KR mobile payment | est. USD 90B+ TPV | 37M users (~72% population) | Kakao storefronts, Korean Air, CJ Olive Young | T2 |
| **Naver Pay** | E-commerce wallet | #1 KR e-commerce wallet | est. USD 50B+ TPV | 30M users | Naver Shopping, Coupang partners, Smartstore sellers | T2 |
| **GrabPay** | Super-app wallet | Only pan-ASEAN wallet | est. USD 15B+ TPV | 35M+ monthly transacting users | Grab platform, 7-Eleven SG, KFC ASEAN | T3 |
| **Midtrans / GoPay** | ID Gateway + wallet | Top-3 Indonesia PSP | est. USD 30B+ TPV | 170M+ Gojek users | Gojek, Tokopedia, BliBli | T3 |
| **MoMo (VN)** | Wallet | #1 Vietnam mobile payment | est. USD 15B+ TPV | 31M users | Tiki, Shopee VN, Grab VN | T3 |
| **GCash (PH)** | Wallet | #1 Philippines wallet | USD 100B+ TPV disclosed (2023) | 76M users (~60% adults) | Shopee PH, Lazada PH, Jollibee, SM | T3 |
| **ShopeePay** | E-commerce wallet | Top-3 in ID/VN/TH e-commerce | est. USD 40B+ TPV | Dominant in Shopee ecosystem | Shopee platforms, partner retailers | T4 |
| **OVO, DANA** | ID Wallets | Top-5 ID wallets (complement GoPay) | est. USD 20B+ TPV each | 100M+ each | Tokopedia, Grab ID, Blibli | T4 |
| **Maya / PayMaya** | PH Wallet | #2 PH wallet | est. USD 25B+ TPV | 47M users | Landmark retail PH, JG Summit | T5 |
| **TrueMoney, Rabbit LINE Pay, KBank** | TH Wallets / bank PG | Complete Thailand coverage | est. USD 10B+ TPV combined | 30M+ TH users each | 7-Eleven TH, CP Group retailers | T4 |
| **LINE Pay (JP/TW/TH)** | Messenger wallet | Strong in JP/TW, secondary to PayPay | est. USD 15B+ TPV | 90M JP LINE users | LINE Shopping, LINE Store, TH retailers | T5 |
| **Rakuten Pay** | E-commerce wallet | Top-3 JP wallet | est. USD 20B+ TPV | 100M+ Rakuten IDs | Rakuten Ichiba, Rakuten Mobile | T5 |
| **Konbini (JP)** | Cash voucher | ~10% of JP e-commerce | est. USD 40B+/yr | 50K+ konbini outlets | Mercari, DMM, Amazon JP | T5 |
| **Samsung Pay** | NFC wallet | Pre-installed on all Galaxy devices | est. USD 50B+ TPV global | Galaxy users | Walmart, Costco, Korean retail | T5 |

### 2.3 Latin America

| Rail | Type | Primary share | Annual volume | Users / merchants | Notable merchants | VBWD tier |
|------|------|---------------|---------------|-------------------|-------------------|-----------|
| **Mercado Pago** | Regional Agg + wallet | #1 LATAM PSP | USD 140B+ TPV (2023 disclosed) | 50M+ unique payers, 18 countries | Mercado Libre, McDonald's LATAM, YPF, Pedidos Ya | T1 |
| **Pix (BR)** | Instant-rail (national) | Surpassed cards in BR in 2023 | 40B+ transactions/yr | 150M users (~75% adults) | iFood, Magazine Luiza, Nubank, all BR e-commerce | T2 |
| **dLocal** | Cross-border Agg | Dominant for international merchants in LATAM | USD 21B TPV (2023 disclosed) | 800+ global merchants | Spotify, Amazon, Microsoft, Didi | T1 (shared with ASEAN) |
| **Conekta (MX)** | MX Gateway | Top-3 MX online PSP | est. USD 15B+ TPV | Tier-1 MX merchants | Uber MX, Rappi, Cinépolis | T2 |
| **OXXO Pay (MX)** | Cash voucher | ~20% of MX e-commerce | est. USD 25B+/yr | 21K+ OXXO stores | Netflix MX, Amazon MX, Uber MX top-ups | T2 |
| **Boleto Bancário (BR)** | Cash voucher | Declining but essential for B2B | est. USD 60B+/yr | Universal BR | Government, utilities, B2B invoicing | T4 |
| **PagSeguro / PagBank** | BR Gateway | Top-3 BR PSP | est. USD 120B+ TPV | 30M+ merchants | Micro-merchants, SMB, enterprise BR | T4 |
| **PSE (Colombia)** | Bank-redirect | 70%+ of CO online payments | est. USD 20B+/yr | 18M+ CO bank customers | Rappi CO, Falabella, government | T3 |
| **PayU** | Regional Gateway | Dominant in CO; strong MX/PE | est. USD 40B+ TPV | 400K+ merchants LATAM | Rappi, Netshoes, AVIANCA | T3 |
| **Kushki** | Modern Regional Gateway | Best Andean coverage | est. USD 5B+ TPV (growing) | Enterprise-focused | Kueski, Davivienda, partner banks | T3 |
| **Nequi, Yape, SPEI, Webpay, PagoEfectivo, RapiPago, Iugu** | Local wallets / cash / instant | Country-dominant in niche | est. USD 5–30B each | 10–20M users each | Local e-commerce, fintech apps | T4–T5 |

---

## 3. Cross-Region Roll-Up

### 3.1 Coverage-vs-plugins curve

The "minimum viable 9 plugins" to be credible in all three regions:

| # | Plugin | Covers | Cumulative countries |
|---|--------|--------|-----------------------|
| 1 | Stripe *(built)* | EU + UK + US baseline, cards + SEPA + iDEAL + Klarna via Payment Methods | 46 |
| 2 | PayPal *(built)* | Global wallet | 46 |
| 3 | YooKassa *(built)* | RU/CIS | 47 |
| 4 | Mollie | EU local methods (iDEAL, Bancontact, Klarna, SOFORT, P24 via Mollie) | 55 |
| 5 | 2C2P | Thailand + SG + MY + PH + VN + ID + HK + TW | 63 |
| 6 | dLocal | All LATAM + additional ASEAN/Africa fallback | 90+ |
| 7 | Mercado Pago | Deep LATAM (BR, MX, AR, CO, CL, UY, PE) with native installments | 90+ |
| 8 | Toss Payments | South Korea full stack | 91 |
| 9 | Komoju or GMO PG | Japan (PayPay + LINE Pay + Konbini + cards) | 92 |

**Nine plugins ≈ 90+ countries covered.** This is the strategic target for
VBWD v1 of the global payment catalogue.

### 3.2 Combined annual processed volume (disclosed + estimated)

| Tier | Rails | Combined annual TPV (disclosed + est.) |
|------|-------|-----------------------------------------|
| Aggregators (Stripe, PayPal, Adyen, Mollie, 2C2P, dLocal, MP) | 7 | **~USD 4.1T** |
| National champions (Pix, PromptPay, iDEAL, Bancontact, PayPay, KakaoPay, Naver, P24) | 8 | **~USD 1.8T** |
| Country wallets & cash (rest of table) | 25+ | **~USD 0.5T** |
| **Total reachable market via 9 aggregator plugins** | | **≈ USD 6T+** |

For comparison, global card-network volume (Visa + Mastercard + UnionPay)
was ~USD 23T in 2023 — so a 9-plugin VBWD stack addresses roughly **a
quarter of all global consumer payment flow**, concentrated in the three
regions most underserved by English-first SaaS billing platforms.

---

## 4. Strategic Analysis — Where VBWD Wins

### 4.1 Why VBWD is a natural partner for these providers

Every rail in the table above has one commercial motion: **grow processed
volume from new merchants**. Their partner programmes reward integrators
who bring merchants onto the rail.

VBWD sits exactly where that matters:

- VBWD is an **open-source, self-hosted SaaS billing platform**. Every
  merchant that deploys VBWD chooses at least one payment plugin on
  install day. That is a qualified lead for the provider.
- VBWD's plugin architecture (`IPaymentAdapter`) makes new rails a
  *weekend project*, not a *quarter-long integration*. Providers get to
  market faster.
- VBWD plugins are **open repos** — the provider's engineering team can
  contribute fixes and new features directly, no NDA.

### 4.2 Win themes for VBWD-based solutions

| Merchant segment | Pain today | VBWD + rail combination |
|------------------|-----------|--------------------------|
| **EU B2B SaaS** | Chargebee/Recurly at EUR 3K+/mo, no SEPA DD in cheap tier | VBWD + Stripe + SEPA DD (via GoCardless or Mollie) — fixed license, zero per-transaction platform fee |
| **DACH e-commerce** | Klarna BNPL is table-stakes, rolling it in without Shopify/Shopware is painful | VBWD + Klarna plugin — instalment widget on product page, PDP embeddable widget |
| **Thai / SEA SaaS** | Stripe doesn't cover PromptPay / TrueMoney natively; Shopify doesn't cover VAT-inclusive Thai invoicing | VBWD + 2C2P + PromptPay plugin — one install covers cards + QR + Thai tax invoice |
| **Japanese e-commerce** | ~10% of buyers want Konbini cash; PayPay share growing fast; Shopify JP coverage gaps | VBWD + Komoju plugin covering PayPay + LINE Pay + Konbini + cards |
| **Korean digital goods / creator economy** | Toss + KakaoPay + Naver Pay ecosystem opaque to foreign platforms | VBWD + Toss Payments + KakaoPay + Naver Pay — localised Korean checkout out of the box |
| **Brazilian SMB SaaS** | Stripe BR is limited; Mercado Pago Pro is ecommerce-first, not subscriptions | VBWD + Mercado Pago + native Pix plugin with CPF collection and Boleto fallback |
| **Mexican cross-border** | OXXO is mandatory; rolling it without Conekta or Stripe MX is slow | VBWD + Conekta + OXXO + MSI installments — drop-in for MX launch |
| **Pan-LATAM creator economy** | Fragmented rails per country; foreign platforms skip smaller markets | VBWD + Mercado Pago + dLocal — one login, 18 countries live |
| **Agency white-label** | Clients want own branding, own bank account, zero platform fee | VBWD license + any 1-2 rails the agency's client needs — flat cost, per-merchant revenue belongs to agency |

### 4.3 Competitive positioning

VBWD is not competing with these providers. It is competing with:

- **Chargebee / Recurly / Stripe Billing** on subscription management.
- **Shopify / WooCommerce / PrestaShop** on e-commerce stack.
- **Salesforce Commerce / Adobe Commerce** on the enterprise side.

Against those, VBWD's edge is **self-hosted, open-source, BSL-licensed,
and payment-provider-agnostic** — the merchant owns their data and their
processing relationships. That story resonates strongest in:

- EU (data sovereignty, GDPR, digital-sovereignty political push).
- Emerging markets where local rails matter and Western SaaS billing
  platforms undercover them.
- Agencies and fractional-CTO shops that resell platforms.

---

## 5. Partner Acquisition — Who to Approach and How

### 5.1 Tier-A targets (approach in next 90 days)

| Provider | Programme | Why us, why now | First ask |
|----------|-----------|------------------|-----------|
| **Mollie** | Mollie Partner Programme (referral + listing) | EU SMB sweet-spot overlaps 1:1 with VBWD's agency ICP | Listing on Mollie partner directory + revenue share on referred merchants |
| **Klarna** | Klarna Partner Hub (tech partners) | Every DACH/Nordics merchant needs Klarna; VBWD currently lacks it | Certified integration badge + co-marketing to Klarna's 500K merchants |
| **2C2P** | 2C2P ISV programme | No OSS SaaS billing platform ships 2C2P out of the box | Integration grant + co-launch Thailand agency network |
| **dLocal** | dLocal Connect partner programme | Amazon/Spotify trust dLocal for LATAM/Africa — we bring their long tail | Revenue share on processed volume, LATAM case studies |
| **Mercado Pago** | MP Developers / Certified Partners | Every LATAM SMB merchant uses MP; VBWD is a natural fit | Certified badge, API credits, featured in MP marketplace |
| **Toss Payments** | Toss Payments Partner API | Toss actively onboards foreign SaaS into Korea | Joint go-to-market into Korean SaaS/creator economy |
| **Conekta** | Conekta Partners | Best-loved dev experience in Mexico; VBWD extends their reach to subscription merchants | Co-marketing + integration certification |

### 5.2 Tier-B targets (quarters 2–4)

Adyen, PayU, Kushki, Razorpay (planned), Midtrans, GCash, Komoju. These
need either higher merchant-volume evidence (Adyen) or a dedicated
in-country partner (Komoju, Kushki).

### 5.3 Standard partnership ask

For every provider above, the conversation is:

1. **Integration grant** — test credentials + sandbox + reviewing engineer.
2. **Certified-integration badge** — listed on provider's partner directory.
3. **Revenue share / referral fee** — typical market is **10–25 bps on
   processed volume** for the first 12–24 months per referred merchant.
4. **Co-marketing** — joint webinar, joint landing page, inclusion in
   provider's SMB / ISV newsletter.

At the VBWD side we offer in return:

- Ship the plugin as a dedicated repo (`vbwd-plugin-<provider>`),
  public and self-installable.
- Reference implementation in our docs and on vbwd.io.
- Inclusion in all VBWD demo instances (main / shop / hotel / doctor /
  ghrm) that serve that provider's geography.

---

## 6. Client Acquisition — Wedges for VBWD-Based Solutions

### 6.1 Wedge A — "Klarna without Shopify" (DACH)

DACH merchants cannot sell physical goods at scale without Klarna, but
Shopify + Klarna costs 2.9% + 3.29% + EUR 0.30 per transaction. On VBWD:
merchant owns the Klarna merchant account, pays **only** Klarna's share.

- **Target:** DACH fashion / home-goods SMBs with EUR 300K–5M GMV.
- **Channel:** DACH agencies (approach via German Shopware / Adobe
  Commerce partner network).
- **Offer:** VBWD license + VBWD Shop + Klarna plugin + SEPA DD plugin
  for EUR 3–6K setup + EUR 99/mo hosting.

### 6.2 Wedge B — "Thai / SEA SaaS Launchpad"

No English-language OSS billing platform ships PromptPay natively.
VBWD + 2C2P + PromptPay is a genuine gap-filler.

- **Target:** Thai / Vietnamese / Filipino SaaS founders launching
  subscription products.
- **Channel:** Southeast Asia developer communities, Indie Hackers SEA
  chapter, Antler SEA portfolio.
- **Offer:** VBWD license + "SEA Payments Bundle" (2C2P + PromptPay +
  GCash + MoMo plugins).

### 6.3 Wedge C — "Japanese SaaS Pack"

PayPay + LINE Pay + Konbini together cover ~60% of JP consumer
preference. None of the Western OSS billing platforms ship all three.

- **Target:** Japanese SaaS, membership sites, creator economy.
- **Channel:** via Komoju partnership for go-to-market; Japan HackerNews
  equivalent (はてなブックマーク); local Vue.js / Laravel communities.
- **Offer:** VBWD + Komoju single-provider plugin covering PayPay +
  LINE Pay + Konbini + cards.

### 6.4 Wedge D — "Korean Creator Pack"

Korean creators want Toss + KakaoPay + Naver Pay and the Korean
mandatory-receipts flow. No OSS billing platform does this well.

- **Target:** Korean digital creators, course sellers, niche SaaS.
- **Channel:** Toss Payments partner ecosystem; NIPA (Korean IT
  industry body); Seoul Playground.
- **Offer:** VBWD + Toss + KakaoPay + Naver Pay bundle, includes
  Korean cash-receipt (현금영수증) flow.

### 6.5 Wedge E — "Pan-LATAM Creator / SaaS"

The most compelling LATAM story: one VBWD install, Mercado Pago primary,
dLocal for long tail, Conekta for Mexico depth, native Pix / OXXO
support. Zero Stripe-BR limitations.

- **Target:** LATAM creators, SaaS, agencies reselling into LATAM.
- **Channel:** Mercado Pago partner programme; Platzi community;
  Brazilian / Mexican dev ecosystems.
- **Offer:** VBWD + "LATAM Pack" — installments (MSI/parcelamento
  built in), Pix QR, OXXO voucher generation.

### 6.6 Wedge F — "Agency White-Label Everywhere"

The meta-wedge. An agency deploys VBWD per client; swaps in the
appropriate plugin stack; charges EUR/USD 3–8K setup + EUR/USD 99–249/mo
retainer. Agencies become our distribution arm.

- **Target:** Web / digital agencies with 10+ active clients.
- **Channel:** VBWD partner programme (`partners@vbwd.io`);
  Freelancermap / Upwork agency networks; regional WordPress / Shopify
  partner meet-ups.
- **Offer:** 20–30% license resale commission + free test licenses +
  agency-tier support.

---

## 7. Metrics to Watch

To know whether the above is working:

| Metric | Where | Target Q1-4 |
|--------|-------|-------------|
| Plugins shipped per region | `vbwd-plugin-*` repos | 9 total by end of Q4 |
| Processed volume through VBWD plugins | Analytics plugin aggregate | ≥ USD 50M/yr routed |
| Active VBWD-based merchant deployments | License telemetry | 500 by end of Q4 |
| Certified-integration badges | Provider partner directories | 5 (Stripe, PayPal, Mollie, MP, 2C2P) |
| Revenue share earned (referrals + resale) | Finance | USD 250K ARR |
| Partnership agreements signed | Business dev | 3 signed (MP, 2C2P, Mollie) |

---

## 8. Open Questions / Next Steps

1. **Which aggregator do we commission first?** Recommendation: Mollie —
   lowest build cost (well-documented REST API), highest immediate EU
   unlock, partner programme is open to ISVs with <200K EUR ARR.
2. **Do we build a dLocal or Mercado Pago plugin first for LATAM?**
   Mercado Pago for the depth (installments, Pix native); dLocal for
   geographic breadth. Ship them in parallel or MP first.
3. **Japan via Komoju vs direct PayPay/LINE Pay?** Komoju is faster to
   market (one plugin, three rails) but gives up margin; direct gives
   better unit economics. Phase: Komoju first, peel off native rails
   later when volume justifies.
4. **Legal review of BNPL plugins (Klarna).** BNPL carries consumer
   credit regulation — confirm that VBWD's role stays *integration layer*
   and not *credit broker*.
5. **Certify for PCI-DSS?** All plugins we list tokenise card data at
   the provider's side; VBWD itself does not store PANs. Confirm SAQ-A
   eligibility and document it for merchant partners.

---

*Cross-references:*
[`payment-plugins-eu.md`](payment-plugins-eu.md),
[`payment-plugins-asean.md`](payment-plugins-asean.md),
[`payment-plugins-latam.md`](payment-plugins-latam.md),
[`../marketing/cms-imports/README.md`](../../marketing/cms-imports/README.md)
(CMS "Payment Modules" page shipped with every vertical instance).
