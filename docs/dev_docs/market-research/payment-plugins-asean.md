# Payment Plugins — ASEAN + Japan + Korea

**Date:** 2026-04-12
**Region:** Southeast Asia, Thailand (expanded), Japan, South Korea

---

## 1. PromptPay (Thailand)

- **Type:** QR code real-time bank transfer
- **Coverage:** Thailand (universal — linked to national ID or phone)
- **Integration:** BOT (Bank of Thailand) API, generates QR payloads per ISO 20022
- **Plugin scope:** Generate PromptPay QR, verify payment via bank webhook, auto-reconcile
- **Volume:** 30B+ transactions/year in Thailand
- **Priority:** HIGH — Thailand is the #1 ASEAN market for QR payments

## 2. GCash (Philippines)

- **Type:** Mobile wallet + QR
- **Coverage:** Philippines (76M+ users, 60% of adult population)
- **Integration:** GCash API (OAuth2 + REST), supports one-time and recurring
- **Plugin scope:** Redirect flow, webhook confirmation, refunds, subscription billing
- **Volume:** $100B+ annual transaction value
- **Priority:** HIGH — dominant payment method in Philippines

## 3. GrabPay (Regional)

- **Type:** Super-app wallet
- **Coverage:** Singapore, Malaysia, Thailand, Vietnam, Philippines, Indonesia, Cambodia, Myanmar
- **Integration:** GrabPay Partner API (OAuth2), tokenized payments
- **Plugin scope:** In-app redirect, QR code generation, subscription debit, refunds
- **Volume:** Used by 35M+ monthly transacting users
- **Priority:** HIGH — only regional wallet with pan-ASEAN coverage

## 4. ShopeePay (Regional)

- **Type:** E-commerce wallet
- **Coverage:** Indonesia, Vietnam, Thailand, Philippines, Malaysia, Singapore, Taiwan
- **Integration:** ShopeePay Merchant API (REST + HMAC signature)
- **Plugin scope:** QR payments, deep-link checkout, cashback campaigns, refunds
- **Volume:** Dominant in Indonesia and Vietnam e-commerce
- **Priority:** HIGH — largest e-commerce ecosystem in SEA

## 5. OVO (Indonesia)

- **Type:** Digital wallet
- **Coverage:** Indonesia (100M+ users)
- **Integration:** OVO Payment API (REST, API key + signature)
- **Plugin scope:** Push payment, QR code, auto-debit for subscriptions, refunds
- **Volume:** Top 3 e-wallet in Indonesia alongside GoPay and DANA
- **Priority:** MEDIUM — Indonesia-specific but massive market

## 6. GoPay / GoTo Financial (Indonesia)

- **Type:** Super-app wallet (Gojek ecosystem)
- **Coverage:** Indonesia, expanding Vietnam
- **Integration:** Midtrans (GoTo Financial's payment gateway) — supports GoPay, bank transfer, VA
- **Plugin scope:** Midtrans snap integration, GoPay tokenization, recurring billing
- **Volume:** 170M+ Gojek users
- **Priority:** HIGH — Midtrans is the Stripe of Indonesia

## 7. DANA (Indonesia)

- **Type:** Digital wallet
- **Coverage:** Indonesia (130M+ users)
- **Integration:** DANA Open API (REST + RSA signature)
- **Plugin scope:** Agreement pay (subscription), QR, mini-app redirect, refunds
- **Volume:** Top 3 e-wallet in Indonesia
- **Priority:** MEDIUM — complements GoPay/OVO for full Indonesia coverage

## 8. MoMo (Vietnam)

- **Type:** Mobile wallet + QR
- **Coverage:** Vietnam (31M+ users, 50% smartphone penetration)
- **Integration:** MoMo Payment API (REST + HMAC-SHA256), IPN webhooks
- **Plugin scope:** QR payment, app redirect, subscription billing, refunds
- **Volume:** Dominant mobile payment in Vietnam
- **Priority:** HIGH — Vietnam is fastest-growing ASEAN digital economy

## 9. PayMaya / Maya (Philippines)

- **Type:** Digital bank + wallet
- **Coverage:** Philippines (rival to GCash)
- **Integration:** Maya Business API (REST), supports cards, wallet, QR Ph
- **Plugin scope:** Checkout page, vault (tokenized recurring), QR Ph payments, refunds
- **Volume:** 47M+ registered users
- **Priority:** MEDIUM — second player in Philippines after GCash

## 10. dLocal (Regional Aggregator)

- **Type:** Payment aggregator for emerging markets
- **Coverage:** All ASEAN + LATAM + Africa (one API, 40+ countries)
- **Integration:** dLocal REST API (API key + secret), unified webhook format
- **Plugin scope:** Single integration covering all local payment methods per country (bank transfer, wallets, cards), subscription billing, payouts
- **Volume:** Processes for Spotify, Amazon, Nike in emerging markets
- **Priority:** HIGH — fastest path to multi-country ASEAN coverage with one plugin

---

## Thailand — Additional Providers

## 11. TrueMoney Wallet (Thailand)

- **Type:** Mobile wallet (True Group / CP Group ecosystem)
- **Coverage:** Thailand (30M+ users), expanding to Cambodia, Myanmar, Vietnam, Indonesia
- **Integration:** TrueMoney Open API (REST, OAuth2), WeCard virtual card, TrueMoney Pay gateway
- **Plugin scope:** Wallet checkout redirect, QR code payment, top-up balance debit, auto-pay for subscriptions, refunds via API
- **Volume:** 2nd largest e-wallet in Thailand after PromptPay
- **Priority:** HIGH — covers unbanked/underbanked users in Thailand who don't use PromptPay

## 12. 2C2P (Thailand / Regional)

- **Type:** Payment gateway aggregator (the "Stripe of Southeast Asia")
- **Coverage:** Thailand, Singapore, Malaysia, Indonesia, Philippines, Vietnam, Myanmar, Hong Kong, Taiwan
- **Integration:** 2C2P Payment API (REST + redirect), supports 250+ payment methods per country
- **Plugin scope:** Unified checkout supporting cards, bank transfer, QR (PromptPay/PayNow/DuitNow), e-wallets, installments, recurring. Single API for multi-country ASEAN payments
- **Volume:** Processes for AirAsia, Grab, Lazada, Tesco Lotus
- **Priority:** HIGH — one integration covers most Thai + ASEAN methods. Direct competitor to dLocal for the region

## 13. KBank Payment Gateway (Thailand)

- **Type:** Bank-direct payment gateway (Kasikornbank — largest Thai bank)
- **Integration:** KBank KPay API (REST), supports QR PromptPay, credit/debit cards, installment plans, KPlus mobile banking redirect
- **Plugin scope:** Direct bank integration (lower fees than aggregators), installment plans (3/6/10 months), KPlus app redirect, corporate billing
- **Volume:** KBank holds 40%+ of Thai merchant acquiring market
- **Priority:** MEDIUM — lower fees for Thailand-focused merchants, but less flexible than 2C2P

## 14. Rabbit LINE Pay (Thailand)

- **Type:** Mobile wallet (LINE messaging app + Rabbit transit card ecosystem)
- **Coverage:** Thailand (LINE has 54M users in Thailand — almost entire population)
- **Integration:** LINE Pay API v3 (REST, HMAC signature), Rabbit wallet balance
- **Plugin scope:** In-chat payment (LINE mini-app), QR code, online checkout redirect, subscription debit, transit card top-up
- **Volume:** Integrated with Rabbit transit system (BTS Skytrain), 7-Eleven, major retailers
- **Priority:** MEDIUM — strong in Thailand, especially for LINE's chat-commerce users

## 15. Thai QR Payment (Standardized — multiple banks)

- **Type:** Unified QR payment standard (Bank of Thailand)
- **Coverage:** Thailand (all banks, all wallets — PromptPay, bank apps, e-wallets accept the same QR)
- **Integration:** EMVCo QR standard, merchant presents QR → customer scans with any banking app
- **Plugin scope:** Generate merchant-presented QR (static or dynamic), amount auto-filled, real-time notification via bank API or PromptPay webhook
- **Difference from PromptPay:** PromptPay is the transfer rail; Thai QR is the merchant payment presentation layer that works across all banks simultaneously
- **Priority:** HIGH — universal acceptance, works with every Thai bank app

---

## Japan

## 16. PayPay (Japan)

- **Type:** QR code / barcode mobile payment (SoftBank + Yahoo Japan)
- **Coverage:** Japan (60M+ users — largest mobile payment in Japan)
- **Integration:** PayPay Web Payment API (REST, HMAC-SHA256), supports QR and online checkout
- **Plugin scope:** Online payment redirect, QR code generation for in-person, subscription billing, refunds, cashback campaign integration
- **Volume:** #1 QR payment in Japan, accepted at 3.8M+ locations
- **Priority:** HIGH — dominant mobile payment in Japan

## 17. LINE Pay (Japan)

- **Type:** Mobile wallet (LINE messaging app ecosystem)
- **Coverage:** Japan (90M+ LINE users), Taiwan, Thailand
- **Integration:** LINE Pay API v3 (REST), supports online and POS payments
- **Plugin scope:** Reserve → confirm payment flow, subscription billing, refunds, mini-app integration
- **Volume:** Major in Japan, integrated with LINE ecosystem (messaging, stickers, commerce)
- **Priority:** MEDIUM — strong but PayPay is dominant

## 18. Rakuten Pay (Japan)

- **Type:** E-commerce wallet + QR payment (Rakuten ecosystem)
- **Coverage:** Japan (Rakuten is Japan's Amazon — 100M+ member IDs)
- **Integration:** Rakuten Pay Online API (REST), requires Rakuten merchant partnership
- **Plugin scope:** Checkout redirect to Rakuten, Rakuten Points integration, subscription billing, one-click payment for Rakuten members
- **Volume:** Significant — leverages Rakuten Super Points loyalty ecosystem
- **Priority:** MEDIUM — important for reaching Rakuten's massive user base

## 19. Konbini Payment (Japan)

- **Type:** Convenience store cash payment
- **Coverage:** Japan (50,000+ konbini locations — 7-Eleven, FamilyMart, Lawson, Ministop)
- **Integration:** Via payment gateways (GMO Payment Gateway, Stripe Japan, Komoju)
- **Plugin scope:** Generate payment slip with barcode → customer pays cash at konbini → webhook confirms payment. Unique to Japan — significant % of e-commerce is paid via cash at konbini
- **Volume:** ~10% of Japanese e-commerce transactions
- **Priority:** MEDIUM — essential for Japanese customers who prefer cash / don't have credit cards

---

## South Korea

## 20. KakaoPay (South Korea)

- **Type:** Mobile wallet (Kakao messaging app — Korea's LINE/WhatsApp)
- **Coverage:** South Korea (37M+ users — 72% of population)
- **Integration:** KakaoPay Online Payment API (REST, OAuth2)
- **Plugin scope:** Checkout redirect to KakaoTalk app, subscription billing, one-click payment, in-app mini program, refunds
- **Volume:** #1 mobile payment in Korea
- **Priority:** HIGH — dominant payment app in Korea

## 21. Naver Pay (South Korea)

- **Type:** E-commerce wallet (Naver — Korea's Google/Yahoo)
- **Coverage:** South Korea (30M+ users)
- **Integration:** Naver Pay API (REST), Naver Checkout integration
- **Plugin scope:** One-click payment for Naver users, order sync with Naver Shopping, subscription billing, point accumulation
- **Volume:** #2 mobile payment in Korea, dominant in e-commerce (Naver Shopping)
- **Priority:** HIGH — essential for Korean e-commerce

## 22. Toss Payments (South Korea)

- **Type:** Fintech payment gateway (Toss — Korea's fintech super-app, 21M+ users)
- **Coverage:** South Korea
- **Integration:** Toss Payments API (REST), supports cards, bank transfer, virtual account, mobile wallets
- **Plugin scope:** Unified Korean payment gateway — one integration for cards, Toss Pay, bank transfer, virtual accounts. PG (payment gateway) license, subscription billing, split payments
- **Volume:** Fast-growing — Toss is Korea's largest fintech
- **Priority:** HIGH — modern API, developer-friendly, covers most Korean payment methods in one integration

## 23. Samsung Pay (South Korea / Global)

- **Type:** Mobile NFC + MST wallet
- **Coverage:** South Korea (primary), Global (Galaxy device users)
- **Integration:** Samsung Pay Web Checkout SDK (JavaScript + REST)
- **Plugin scope:** In-browser Samsung Pay button, tokenized payment, works with existing card networks, biometric auth
- **Volume:** Pre-installed on all Samsung Galaxy devices
- **Priority:** MEDIUM — good UX for Samsung users, but not a standalone payment method

---

## Updated Implementation Priority

| Tier | Plugins | Markets | Rationale |
|------|---------|---------|-----------|
| **Tier 1** | 2C2P, dLocal, Toss Payments | ASEAN + KR | One API per region covers most local methods |
| **Tier 2** | PromptPay + Thai QR, PayPay, KakaoPay, Naver Pay | TH + JP + KR | Country-dominant, high-volume |
| **Tier 3** | GrabPay, Midtrans, MoMo, GCash | SG/MY + ID + VN + PH | Country-specific leaders |
| **Tier 4** | TrueMoney, Rabbit LINE Pay, KBank | TH | Full Thailand coverage |
| **Tier 5** | LINE Pay, Rakuten Pay, Konbini, Samsung Pay, ShopeePay, OVO, DANA, Maya | JP + KR + ASEAN | Market completeness |

## Plugin Architecture

Each payment plugin follows the existing `IPaymentProvider` pattern:
```python
class PromptPayPlugin(BasePlugin):
    def get_blueprint(self): ...
    def register_event_handlers(self, bus): ...
    # Routes: /api/v1/payment/promptpay/create-qr, /webhook
```

Frontend: redirect flow or QR code display component registered via `sdk.addComponent()`.

## Regional Aggregator Strategy

For fastest multi-country coverage:
- **Thailand:** 2C2P (covers PromptPay + Thai QR + TrueMoney + cards + installments)
- **Indonesia:** Midtrans (covers GoPay + OVO + DANA + bank transfer + cards)
- **Japan:** Komoju or GMO PG (covers PayPay + LINE Pay + Konbini + cards)
- **Korea:** Toss Payments (covers cards + bank transfer + Toss Pay + virtual accounts)
- **Pan-ASEAN:** dLocal (covers all countries with one API, lower local depth)
