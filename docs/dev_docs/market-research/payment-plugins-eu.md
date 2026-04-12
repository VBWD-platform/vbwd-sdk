# 10 Payment Plugins Popular in EU

**Date:** 2026-04-12
**Region:** European Union + UK, Switzerland, Norway

---

## 1. Stripe (Pan-European)

- **Type:** Full-stack payment platform
- **Coverage:** 46 countries, all EU + UK + EEA
- **Integration:** Stripe API (REST + client SDK), Stripe Elements, Checkout Sessions
- **Plugin scope:** Already implemented — `plugins/stripe/`. Cards, SEPA, iDEAL, Bancontact, Klarna via Payment Methods API
- **Status:** DONE — existing plugin
- **Priority:** N/A — already built

## 2. PayPal (Pan-European)

- **Type:** Wallet + card processing
- **Coverage:** Global, strong in DE, UK, FR, IT, ES
- **Integration:** PayPal REST API v2, Orders + Subscriptions API
- **Plugin scope:** Already implemented — `plugins/paypal/`. Orders, subscriptions, webhooks
- **Status:** DONE — existing plugin
- **Priority:** N/A — already built

## 3. Klarna (Northern / Western Europe)

- **Type:** Buy Now Pay Later (BNPL) + Pay Now
- **Coverage:** DE, AT, SE, NO, FI, DK, NL, BE, UK, US (19 countries)
- **Integration:** Klarna Payments API (REST), Klarna Checkout (hosted)
- **Plugin scope:** Pay in 3/4 installments, pay later (30 days), pay now (bank redirect). Widget for product pages showing installment price. Webhook for order status.
- **Volume:** 150M+ users, 500K+ merchants
- **Priority:** HIGH — dominant BNPL in DACH and Nordics

## 4. SEPA Direct Debit (Eurozone)

- **Type:** Bank-to-bank direct debit
- **Coverage:** All 36 SEPA countries (EU + EEA + CH + UK)
- **Integration:** Via Stripe SEPA, GoCardless API, or native bank API
- **Plugin scope:** Mandate collection (digital signature), recurring debit scheduling, R-transaction handling (returns/refunds), SDD Core vs B2B scheme
- **Volume:** 22B+ SEPA DD transactions/year
- **Priority:** HIGH — essential for B2B subscriptions in EU

## 5. iDEAL (Netherlands)

- **Type:** Bank redirect (real-time bank transfer)
- **Coverage:** Netherlands (70%+ of online payments)
- **Integration:** iDEAL 2.0 API (via Mollie, Adyen, or Stripe), redirect flow
- **Plugin scope:** Bank selection, redirect to bank app, webhook confirmation, refunds
- **Volume:** 1.1B+ transactions/year
- **Priority:** MEDIUM — essential for NL market, available via Stripe/Mollie

## 6. Bancontact (Belgium)

- **Type:** Debit card + mobile app
- **Coverage:** Belgium (80%+ of card payments)
- **Integration:** Bancontact Payconiq API, QR flow, redirect flow
- **Plugin scope:** Card payment redirect, QR code generation, recurring (via mandate), refunds
- **Volume:** 2B+ transactions/year in Belgium
- **Priority:** MEDIUM — essential for BE market

## 7. Przelewy24 / P24 (Poland)

- **Type:** Bank redirect aggregator
- **Coverage:** Poland (dominant online payment method)
- **Integration:** P24 REST API, redirect to bank, webhook notification
- **Plugin scope:** Bank selection page, redirect flow, instant confirmation, refunds
- **Volume:** 50%+ of Polish e-commerce payments
- **Priority:** MEDIUM — Poland is 6th largest EU economy

## 8. Mollie (Pan-European Aggregator)

- **Type:** Payment service provider
- **Coverage:** EU-wide — aggregates iDEAL, Bancontact, SEPA, Klarna, Sofort, Giropay, EPS, and cards
- **Integration:** Mollie API (REST, API key), Mollie Components (embedded forms)
- **Plugin scope:** Single integration for 20+ EU payment methods, subscription API, mandate management, multi-currency
- **Volume:** 200K+ merchants, €35B+ processed
- **Priority:** HIGH — one plugin covers most EU local payment methods

## 9. Adyen (Enterprise Pan-European)

- **Type:** Enterprise payment platform
- **Coverage:** Global (60+ payment methods, 30+ currencies)
- **Integration:** Adyen Checkout API (REST + Drop-in component), webhooks
- **Plugin scope:** Unified checkout with local methods auto-detected by country, tokenization, recurring, 3DS2, risk management
- **Volume:** Processes for Uber, Spotify, Microsoft
- **Priority:** MEDIUM — enterprise tier, higher volume requirements

## 10. Revolut Pay (Emerging)

- **Type:** Fintech app wallet
- **Coverage:** EU + UK (45M+ users, growing fast)
- **Integration:** Revolut Merchant API (REST), one-click checkout widget
- **Plugin scope:** One-click payment for Revolut users, instant settlement, refunds
- **Volume:** Growing — 45M personal users, 500K+ business accounts
- **Priority:** LOW-MEDIUM — emerging but fast-growing, especially in UK/Baltics/IE

---

## Implementation Priority

| Tier | Plugins | Rationale |
|------|---------|-----------|
| **Done** | Stripe, PayPal | Already built |
| **Tier 1** | Mollie, Klarna, SEPA DD | Mollie covers most local methods; Klarna is essential BNPL; SEPA DD for B2B subscriptions |
| **Tier 2** | iDEAL, Bancontact, P24 | Country-dominant methods (available via Mollie but standalone gives better UX) |
| **Tier 3** | Adyen, Revolut Pay | Enterprise / emerging — lower priority |

## Plugin Architecture

Same `IPaymentProvider` pattern as existing Stripe/PayPal plugins:
```python
class MolliePlugin(BasePlugin):
    def get_blueprint(self): ...
    def register_event_handlers(self, bus): ...
    # Handles: payment.authorized, payment.captured, payment.failed
    # Routes: /api/v1/payment/mollie/checkout, /webhook
```

Frontend: hosted checkout redirect or embedded payment form via `sdk.addComponent()`.
