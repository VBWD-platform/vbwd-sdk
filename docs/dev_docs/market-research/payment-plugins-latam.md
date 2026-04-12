# 10 Payment Plugins Popular in Latin America

**Date:** 2026-04-12
**Region:** Brazil, Mexico, Argentina, Colombia, Chile, Peru, Ecuador, Uruguay, Costa Rica, Panama

---

## 1. Mercado Pago (Regional)

- **Type:** Fintech super-app + payment gateway (Mercado Libre ecosystem)
- **Coverage:** Brazil, Mexico, Argentina, Colombia, Chile, Uruguay, Peru (18 countries)
- **Integration:** Mercado Pago Checkout API (REST, OAuth2), Checkout Pro (hosted), Checkout Bricks (embedded components)
- **Plugin scope:** Cards, Pix (Brazil), bank transfer, cash (boleto, OXXO), wallet balance, installments (up to 12x), subscription billing, split payments for marketplaces, QR code
- **Volume:** 50M+ unique payers, processes for Mercado Libre (largest LATAM e-commerce)
- **Priority:** HIGH — single integration covers most LATAM countries with all local methods. The Stripe of Latin America
- **Key advantage:** Built-in fraud prevention, buyer protection, installment plans without merchant risk

## 2. Pix (Brazil)

- **Type:** Instant payment system (Central Bank of Brazil)
- **Coverage:** Brazil (150M+ users — 75% of adult population)
- **Integration:** Via bank APIs (Banco do Brasil, Itaú, Bradesco) or PSPs (Mercado Pago, PagSeguro, Stripe Brazil)
- **Plugin scope:** Generate Pix QR code (static/dynamic), copy-paste key, instant confirmation webhook, refunds via Pix Devolução, scheduled Pix for subscriptions
- **Volume:** 40B+ transactions/year, surpassed credit cards in Brazil in 2023
- **Priority:** HIGH — mandatory for any Brazil operation. Similar to PromptPay in Thailand
- **Key advantage:** Instant settlement 24/7, zero cost for consumers, near-zero for merchants

## 3. PagSeguro / PagBank (Brazil)

- **Type:** Payment gateway + digital bank
- **Coverage:** Brazil (primary), expanding LATAM
- **Integration:** PagSeguro API v4 (REST), supports transparent checkout (embedded) and redirect
- **Plugin scope:** Credit/debit cards, Pix, boleto bancário (cash slip), bank transfer (TEF), installments (up to 18x), recurring billing, PagBank wallet
- **Volume:** 30M+ merchants in Brazil, from micro-businesses to enterprise
- **Priority:** MEDIUM — strong in Brazil, complements Mercado Pago for broader coverage

## 4. OXXO Pay (Mexico)

- **Type:** Convenience store cash payment
- **Coverage:** Mexico (21,000+ OXXO stores — largest convenience chain in LATAM)
- **Integration:** Via Conekta, Stripe Mexico, Mercado Pago, or OXXO Pay API directly
- **Plugin scope:** Generate payment voucher with barcode → customer pays cash at any OXXO → webhook confirms (24-72h settlement). Essential for Mexico's unbanked population
- **Volume:** ~20% of Mexican e-commerce is paid at OXXO
- **Priority:** HIGH — Mexico's equivalent of Japan's Konbini. Cannot sell in Mexico without OXXO support

## 5. Conekta (Mexico)

- **Type:** Payment gateway (Mexico-focused)
- **Coverage:** Mexico
- **Integration:** Conekta API (REST, Bearer token), Conekta.js (embedded tokenization)
- **Plugin scope:** Cards (Visa/MC/Amex), OXXO cash, SPEI bank transfer, installments (MSI — Meses sin Intereses), subscription billing, anti-fraud, 3DS2
- **Volume:** Powers Uber Mexico, Rappi, Cinépolis
- **Priority:** HIGH — best developer experience for Mexico, covers all local methods
- **Key advantage:** MSI (interest-free installments) is critical in Mexico — 40%+ of card transactions use MSI

## 6. Boleto Bancário (Brazil)

- **Type:** Bank payment slip (cash or online banking)
- **Coverage:** Brazil (universal — even unbanked can pay at any bank branch, lottery house, or post office)
- **Integration:** Via bank APIs or PSPs (Mercado Pago, PagSeguro, Stripe Brazil, Iugu)
- **Plugin scope:** Generate boleto PDF with barcode, configurable expiry (1-30 days), auto-cancel unpaid boletos, webhook on payment (1-3 business day settlement), registered boleto (boleto registrado) with protest option
- **Volume:** Still significant despite Pix growth — essential for B2B invoicing and government payments
- **Priority:** MEDIUM — declining for B2C (replaced by Pix) but still critical for B2B

## 7. dLocal (Regional Aggregator)

- **Type:** Cross-border payment platform for emerging markets
- **Coverage:** Brazil, Mexico, Argentina, Colombia, Chile, Peru, Uruguay, Ecuador, Paraguay, Bolivia, Costa Rica, Panama + 20 more countries
- **Integration:** dLocal REST API (API key + secret), unified webhook format, payins + payouts
- **Plugin scope:** Single API for all LATAM payment methods — cards, bank transfers, cash vouchers (OXXO, boleto, PagoEfectivo, etc.), wallets, installments. Also handles payouts to local bank accounts
- **Volume:** Processes for Spotify, Amazon, Microsoft, Didi in LATAM
- **Priority:** HIGH — fastest path to pan-LATAM coverage. Already listed in ASEAN report — same plugin covers both regions

## 8. PSE — Pagos Seguros en Línea (Colombia)

- **Type:** Bank redirect (real-time online bank debit)
- **Coverage:** Colombia (dominant online payment — used by 70%+ of online purchases)
- **Integration:** Via ACH Colombia API or PSPs (PayU, Mercado Pago, dLocal)
- **Plugin scope:** Bank selection page, redirect to bank's online portal, instant confirmation, refunds. Similar to iDEAL in Netherlands
- **Volume:** Most used online payment method in Colombia
- **Priority:** MEDIUM — essential for Colombia, but available via dLocal/Mercado Pago

## 9. PayU (Regional)

- **Type:** Payment gateway (Naspers/Prosus group)
- **Coverage:** Colombia, Mexico, Argentina, Brazil, Chile, Peru, Panama
- **Integration:** PayU Latam API (REST), PayU Hub (multi-country), Tokenization API
- **Plugin scope:** Cards, bank transfer, cash (Baloto, Efecty in Colombia; OXXO in Mexico), installments, recurring billing, anti-fraud (Bayonet integration)
- **Volume:** Dominant gateway in Colombia, strong across LATAM
- **Priority:** MEDIUM — strong in Colombia/Mexico, overlaps with Mercado Pago and dLocal

## 10. Kushki (Regional — Modern)

- **Type:** Modern payment infrastructure (LATAM-focused fintech)
- **Coverage:** Mexico, Colombia, Chile, Peru, Ecuador, Costa Rica, Panama, El Salvador, Guatemala
- **Integration:** Kushki API (REST, modern SDK), Kushki.js (PCI-compliant tokenization)
- **Plugin scope:** Cards, bank transfer, cash (OXXO, PagoEfectivo, Efecty), subscription billing, card-on-file, 3DS2, split payments
- **Volume:** Growing — backed by SoftBank, processing for enterprise clients
- **Priority:** MEDIUM — modern API, good developer experience, strong in Andean countries (Colombia, Peru, Ecuador, Chile)
- **Key advantage:** Best coverage for smaller LATAM markets (Ecuador, Costa Rica, Panama, Central America) where Mercado Pago is weaker

---

## Honorable Mentions

| Provider | Country | Type | Notes |
|----------|---------|------|-------|
| **Nequi** | Colombia | Mobile wallet (Bancolombia) | 17M+ users, P2P dominant, growing merchant acceptance |
| **Yape** | Peru | Mobile wallet (BCP bank) | 15M+ users, QR payments, dominant in Peru |
| **SPEI** | Mexico | Real-time bank transfer (Banco de México) | Mexico's Pix equivalent, instant interbank transfer |
| **Webpay** | Chile | Card gateway (Transbank monopoly) | Only card processor in Chile, being challenged by new entrants |
| **PagoEfectivo** | Peru | Cash voucher network | Pay at banks, agents, pharmacies — critical for Peru's unbanked |
| **RapiPago / PagoFácil** | Argentina | Cash payment network | 10,000+ collection points, essential despite digital growth |
| **Iugu** | Brazil | Subscription billing platform | Stripe-like for Brazil, strong in SaaS recurring billing |

---

## Implementation Priority

| Tier | Plugins | Markets | Rationale |
|------|---------|---------|-----------|
| **Tier 1** | Mercado Pago, dLocal | All LATAM | Two plugins cover 18+ countries with all local methods |
| **Tier 2** | Pix (standalone), Conekta, OXXO Pay | BR + MX | Country-dominant methods for the two largest markets |
| **Tier 3** | PSE, PayU, Kushki | CO + Andean | Colombia + smaller markets |
| **Tier 4** | PagSeguro, Boleto, Nequi, Yape | BR + CO + PE | Market completeness |

## Regional Aggregator Strategy

For fastest coverage with fewest integrations:

| Strategy | Plugins | Coverage |
|----------|---------|----------|
| **Minimum viable** | Mercado Pago | BR, MX, AR, CO, CL, UY, PE |
| **Full coverage** | Mercado Pago + dLocal | All LATAM (dLocal fills gaps in Central America, Ecuador, etc.) |
| **Deep local** | Above + Conekta (MX) + standalone Pix (BR) | Best UX for the two largest markets |

## Key LATAM Payment Patterns

| Pattern | Description | Countries |
|---------|-------------|-----------|
| **Installments** | Interest-free monthly payments on credit cards (MSI/parcelamento) — 40-60% of card transactions | BR, MX, AR, CO |
| **Cash vouchers** | Online purchase → print voucher → pay cash at store/bank | BR (boleto), MX (OXXO), PE (PagoEfectivo), CO (Efecty), AR (RapiPago) |
| **Instant bank transfer** | QR/app-based real-time payment | BR (Pix), MX (SPEI/CoDi), CO (PSE) |
| **Tax ID required** | CPF (Brazil) or RFC (Mexico) required for all transactions | BR, MX |
| **Currency controls** | Foreign currency restrictions, dual exchange rates | AR (blue dollar), VE (multiple rates) |

## Plugin Architecture

Same `IPaymentProvider` pattern:
```python
class MercadoPagoPlugin(BasePlugin):
    def get_blueprint(self): ...
    def register_event_handlers(self, bus): ...
    # Routes: /api/v1/payment/mercadopago/checkout, /webhook
    # Config: access_token, public_key, country, installment_config
```

**LATAM-specific considerations:**
- CPF/RFC tax ID collection in checkout form
- Installment selector UI component (show monthly price)
- Cash voucher PDF generation + expiry handling
- Multi-currency: BRL, MXN, ARS, COP, CLP, PEN, USD
