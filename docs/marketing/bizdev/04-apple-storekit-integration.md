# VBWD — Apple StoreKit Integration: Gate, Not Bridge

**Author context.** Solo dev, day job, 8–12 hrs/week, async-only, no sales calls. Targets: **€100k brutto Y1**, **€300k brutto 24mo**. DACH-first, B2B-leaning white-label SaaS. Companion to [`03-integration-bridges-strategy.md`](03-integration-bridges-strategy.md). Researched May 2026.

**TL;DR.** StoreKit is **not** a distribution bridge like the ones in doc 03 — it is a *payment gate* on a channel you already occupy (the `vbwd-ios` app). WooCommerce was killed because it had no buyer pull. StoreKit fails a *different* test: it is structurally incompatible with VBWD's core business — multi-tenant, white-label, dynamic plan catalog, merchant-of-record VAT invoicing for DACH B2B. Apple wants to *be* the merchant of record and take 15–30%; that collides head-on with the invoice plugin, the admin-defined plan catalog, and the per-tenant deployment model. **So: do not build StoreKit as a payment provider for the core B2B subscription business. Build it only as a demand-gated, B2C-only plugin if/when a specific consumer app (meinchat-plus, taro) ships to the App Store selling subscriptions to end-consumers — because there it stops being optional and becomes the gate you must pass.** The good news: the existing plugin seams (`ISubscriptionLifecycle`, payment-action ports, the iOS `PlatformSDK`) mean we can defer this with **zero architectural debt**. The seam is already there; we just don't fill it yet.

---

## 1. Why this is a different question than WooCommerce

WooCommerce was rejected because it's a *discretionary inbound channel with no pull* — you'd build a connector and wait for merchants who never come. The verdict was "useless" = **no demand**.

StoreKit is the opposite shape. There is no "demand" question, because **the moment you sell a subscription inside an iOS app on the App Store, Apple's rules force the question on you.** App Review Guideline 3.1.1: if you unlock features, content, or subscriptions inside the app, you **must** use In-App Purchase. We already have `vbwd-ios` with `subscription` and `stripe` plugins. The day that app tries to sell a subscription on the App Store, Apple rejects it unless we either (a) use StoreKit IAP, or (b) qualify for a narrow exemption (reader app / external-link, see §5).

So the WooCommerce frame ("is there pull?") is the wrong lens. The right lens is: **does StoreKit fit the shape of VBWD's business, and where is it mandatory anyway?** The answer splits cleanly by audience: it's a *bad fit and avoidable* for B2B, and a *mandatory gate* for B2C-consumer apps.

---

## 2. What StoreKit actually is (so the trade-offs are concrete)

Modern Apple IAP is three cooperating pieces — and notably, it maps almost 1:1 onto the payment-plugin pattern we already have for Stripe:

| Apple piece | What it does | VBWD analog |
|---|---|---|
| **StoreKit 2** (Swift, on-device) | Shows the native purchase sheet, returns a **JWS-signed transaction** | `vbwd-ios-plugin-stripe` payment action on the device |
| **App Store Server API** (server→Apple) | Backend sends a `transactionId`, gets back signed transaction/subscription status; you no longer store receipts | `plugins/stripe/stripe/sdk_adapter.py` calling the provider |
| **App Store Server Notifications V2** (Apple→server webhook) | Real-time JWS events: `SUBSCRIBED`, `DID_RENEW`, `EXPIRED`, `GRACE_PERIOD_EXPIRED`, `REFUND`, etc. | `plugins/stripe/stripe/routes.py` webhook → `ISubscriptionLifecycle` |

Technically this is a clean fit. A StoreKit plugin would be a backend `plugins/apple_storekit/` (JWS verification, Server Notifications V2 webhook, drives the **same** `ISubscriptionLifecycle` port + line-item registry the subscription extraction already exposes) plus an `vbwd-ios-plugin-storekit` (registers a payment action via `PlatformSDK`, exactly like the iOS Stripe plugin). **The architecture is not the problem.** The economics and the business model are.

**Commission reality (2026):**
- Standard **30%** first year, **15%** from a subscriber's second year onward.
- **Small Business Program: 15% from day one** (proceeds under $1M/yr — that's us, for now). EU alternative terms can drop to **10%** after year one.
- US "link-out": post–*Epic v. Apple* (Apr 2025) Apple was barred from any commission on external-link purchases; the Dec 2025 Ninth Circuit ruling lets Apple charge a "reasonable" coordination fee, **rate still undetermined** and headed back to district court (and toward the Supreme Court). **Do not build a strategy on a number that doesn't exist yet.**

---

## 3. Why StoreKit is the wrong rail for the *core B2B subscription business*

Four structural collisions, in order of severity. Any one of them is disqualifying; together they're decisive.

### 3.1 Multi-tenant / white-label breaks the App Store product model (the killer)
VBWD is white-label and multi-tenant: each customer runs their own instance (`vbwd-demo-instances/instances/{main,shop,hotel,doctor,ghrm}`) with **their own admin-defined plan catalog**. StoreKit products are pre-registered **in one App Store Connect account — ours.** There is no mechanism for 100 tenants to each define their own IAP products under our developer account, and Apple won't let tenants transact under our merchant identity. This is the *same class of failure* as WooCommerce: **the integration can't represent the tenant-specific catalog that is the product.** A single first-party app selling VBWD's *own* license is the only shape that fits — and that's a niche, not the business.

### 3.2 Apple becomes merchant of record → kills the DACH B2B invoice
Our whole invoice + subscription stack assumes **we** are the merchant of record: we issue the VAT invoice, we own the customer billing relationship, we control dunning. With IAP, **Apple is the merchant of record.** The customer gets an Apple receipt, not a VBWD `invoice` with the buyer's company VAT details. For German/DACH B2B buyers a proper *Rechnung* is non-negotiable. This collides directly with the `invoice` core model and the entire reason a business buys VBWD instead of a consumer app.

### 3.3 Dynamic, admin-configurable plan catalog vs. pre-registered products
VBWD's value prop includes **self-serve plan creation** in the admin (`planAdmin`, `tarif-plans`). StoreKit requires every purchasable product to be registered in App Store Connect ahead of time and pass review. Admins can't mint a new IAP product from the VBWD admin panel. The dynamic catalog — a core feature — simply can't be sold through IAP.

### 3.4 Margin + lock-in on an already-thin white-label deal
15% (best case) off the top of a SaaS subscription where we're already competing on price is margin we can't spare. And the subscription becomes **Apple-managed**: cancellation, refunds, grace period, upgrades all live in Apple's system, not ours — a support and reconciliation burden (two sources of truth: Apple's subscription state vs. VBWD's) for a solo dev with 10 hours a week.

**Verdict for B2B core:** same bottom line as WooCommerce — **don't build it** — but for the opposite reason. WooCommerce had no pull; StoreKit has a *gate* but the gate leads somewhere our business model can't follow.

---

## 4. Where StoreKit *is* mandatory and worth building (the B2C carve-out)

There is exactly one scenario where the verdict flips: **a consumer-facing iOS app that sells digital subscriptions to end-consumers through the App Store.** Candidates in the portfolio: **meinchat-plus** (consumer chat upgrade), **taro** (consumer readings). For B2C digital goods sold to consumers in an app, IAP is **mandatory** — there is no compliant Stripe-in-app path, and the reader-app exemption (§5) forbids in-app selling. If any of these go to the App Store as a paid consumer app, StoreKit isn't a choice; it's the cost of being on the store.

In that scenario the trade-offs invert:
- 15% is the *price of the highest-converting checkout on earth* (native sheet, Apple Pay, one tap, stored payment method, global storefronts you'd never onboard a PSP into).
- Apple-as-merchant-of-record is a *feature* for B2C — no VAT invoice to issue, Apple handles tax/refunds/dunning across every country.
- A single first-party consumer app = one App Store Connect account = §3.1 no longer applies.

So StoreKit is **demand-gated, exactly like Shopify in doc 03**: build it the moment a specific consumer app needs to ship paid, not before.

---

## 5. The exemptions, and why they don't rescue the B2B case

- **External-link / "link-out" (US, post-Epic).** US storefront can now link out to web checkout; commission currently 0% but legally in flux (§2). Tempting, but: US-only, legally unstable, and Apple still expects IAP to *also* be offered in most non-reader apps. Too fragile to anchor a roadmap on.
- **Reader-app entitlement.** If the iOS app is a pure *companion* — users sign in to accounts/subscriptions bought on the web and the app sells **nothing** in-app (only a permitted external link) — you avoid IAP entirely. **This is the cleanest answer for the B2B app.** Position `vbwd-ios` as a companion to the web-first product: no in-app purchase CTA, subscriptions bought at the web checkout, the app just consumes entitlements. Zero commission, zero StoreKit code, fully compliant. This is effectively the "do nothing on iOS payments" path and it's *defensible*, not a cop-out.
- **EU DMA alternative terms.** Real but complex (Core Technology Fee math, alternative-marketplace rules); only worth modeling if EU B2C volume becomes material.

---

## 6. Recommendation

1. **Core B2B subscription business: do not integrate StoreKit.** It's margin-destroying and structurally incompatible (multi-tenant catalog, merchant-of-record VAT invoice, dynamic plans). Same "no" as WooCommerce, sharper reasons.
2. **Make `vbwd-ios` a reader-style companion app.** No in-app purchase CTA; subscriptions are bought at the existing web/Stripe checkout; the app consumes entitlements. Compliant, free, ships now, no StoreKit code. This neutralizes the App Review gate without paying Apple a cent.
3. **Treat StoreKit as a demand-gated B2C-only payment plugin.** Build `plugins/apple_storekit` + `vbwd-ios-plugin-storekit` **only when** a specific consumer app (meinchat-plus / taro) is going to the App Store selling consumer subscriptions. There, it's mandatory and the economics flip in its favor.
4. **Keep the seam, write no code now.** The subscription extraction already gives us `ISubscriptionLifecycle`, the line-item registry, and DI-registered payment plugins; the iOS side has the `PlatformSDK` payment-action port proven by `vbwd-ios-plugin-stripe`. A future StoreKit plugin slots into those with **no core changes** (core stays agnostic; the plugin is gnostic). Deferring costs us nothing architecturally.

### If/when we do build it (B2C trigger), the shape is known
- **Backend `plugins/apple_storekit/`:** JWS transaction verification via App Store Server API; **Server Notifications V2** webhook → `ISubscriptionLifecycle`; line-item handler registered in `on_enable`; repos registered as DI providers (don't repeat the 2026-03-27 omission); migrations in `plugins/apple_storekit/migrations/`; `config.json` + `admin-config.json` with `debug_mode`.
- **iOS `vbwd-ios-plugin-storekit`:** StoreKit 2 purchase flow behind a `PlatformSDK` payment action, mirroring the Stripe plugin; sends `transactionId` to the backend for verification (no on-device entitlement logic).
- **Reconciliation:** Apple subscription state is the source of truth for IAP-originated subs; VBWD subscription mirrors it via Server Notifications V2. Never let the two drift — entitlement is derived from Apple events, not guessed.
- **Engineering bar (binding):** TDD-first, SOLID/DI/Liskov, DRY, **no overengineering**, `bin/pre-commit-check.sh --full` green on every touched repo = done. Core agnostic, plugin gnostic.

---

## 7. The pitch, condensed

1. **StoreKit isn't a bridge — it's a tollgate on the App Store channel we already stand in.** The question isn't "is there demand," it's "does it fit our model."
2. **For B2B, it doesn't fit:** multi-tenant catalogs can't be App Store products, Apple-as-merchant-of-record kills the DACH VAT invoice, dynamic plans can't be pre-registered, and 15% off a thin white-label deal hurts.
3. **Dodge the gate with the reader/companion-app model:** no in-app selling, buy on web, consume entitlements in-app — compliant, free, ships now.
4. **For B2C consumer apps it's mandatory and good** — build it demand-gated, only when meinchat-plus/taro actually go paid on the App Store.
5. **The seam already exists** (`ISubscriptionLifecycle`, payment-action ports), so deferring is free and building later is a thin plugin, not a rewrite.

**Bottom line:** WooCommerce was a "no" because nobody was coming. StoreKit is a "not for the core, yes-when-forced for B2C" — avoid it where it fights your business model, adopt it only where Apple leaves no choice and the economics actually favor it.

---

### Sources

- [StoreKit 2 — Apple Developer](https://developer.apple.com/storekit/) · [StoreKit docs](https://developer.apple.com/documentation/storekit) · [App Store Server Notifications V2](https://developer.apple.com/documentation/AppStoreServerNotifications/App-Store-Server-Notifications-V2) · [Auto-renewable Subscriptions](https://developer.apple.com/app-store/subscriptions/) · [Small Business Program](https://developer.apple.com/app-store/small-business-program/) · [Reader apps](https://developer.apple.com/support/reader-apps/) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Commission/validation: [App Store Server API guide (Qonversion)](https://qonversion.io/blog/app-store-server-api) · [Server-side validation (Adapty)](https://adapty.io/blog/validating-iap-with-app-store-server-api/) · [15% fee guide 2026 (RevenueCat)](https://www.revenuecat.com/blog/engineering/small-business-program/)
- Epic v. Apple / external links: [Appeals court modifies injunction, Dec 2025 (MacRumors)](https://www.macrumors.com/2025/12/11/apple-app-store-fees-external-payment-links/) · [Ninth Circuit analysis (Perkins Coie)](https://perkinscoie.com/insights/update/epic-v-apple-ninth-circuit-weighs) · [Anti-steering ruling & strategy (RevenueCat)](https://www.revenuecat.com/blog/growth/apple-anti-steering-ruling-monetization-strategy/) · [App-to-web purchase guidelines (RevenueCat)](https://www.revenuecat.com/blog/engineering/app-to-web-purchase-guidelines/)