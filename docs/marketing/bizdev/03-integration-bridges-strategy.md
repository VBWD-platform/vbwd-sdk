# VBWD — Integration Bridges: The Async Distribution Play

**Author context.** Solo dev, day job, 8–12 hrs/week, async-only, no sales calls. Targets: **€100k brutto Y1**, **€300k brutto 24mo**. This document must survive those constraints or it doesn't ship. Companion to [`01-next-90-days-plan.md`](01-next-90-days-plan.md) and [`02-geo-strategy.md`](02-geo-strategy.md).

**TL;DR.** Bridges are not a feature. They are a **distribution channel that sells while you sleep.** Every CRM/commerce platform you bridge to has an app marketplace with built-in buyer traffic and zero cold outreach. You list once, they send you customers forever. The catch: building N bespoke connectors is a full-time job you don't have. So the real move is to build **one Bridge Framework on top of the plugin system, ship two flagship bridges, and let the marketplace listings do the selling.** That's the whole pitch.

---

## 1. Why bridges, and why now — the honest sell

You have a structural problem the 90-day plan already named: **you can't sell synchronously.** No demos, no calls, no agency recruitment. That kills the normal SaaS growth motion. So you need channels where **the buyer finds you, qualifies themselves, and self-serve installs** — no human in the loop.

Integration marketplaces are exactly that channel:

| Marketplace | Buyer traffic | What a listing costs you | What it returns |
|---|---|---|---|
| **HubSpot App Marketplace** | 200k+ paying CRM customers actively shopping for integrations | One backend bridge + a listing review | Inbound installs, co-marketing, "Works with HubSpot" badge |
| **Shopify App Store** | Millions of merchants, highest-intent buyers on the planet | One backend bridge + Checkout Kit | Per-install revenue, recurring app subscriptions |
| **WordPress.org / WooCommerce** | ~40% of the web; DACH SMB stronghold | One WP plugin wrapper | Free top-of-funnel, upsell to VBWD license |
| **Zapier / Make** | 6000+ apps, every ops person uses them | **One** generic webhook bridge | Instant reach into hundreds of CRMs with zero per-app work |

Read that last row again. **One webhook bridge = presence in hundreds of tools.** That is the single highest-leverage thing you can build with 10 hours a week. It is the async-distribution equivalent of a Product Hunt front page, except it never falls off the front page.

**The sell in one sentence:** bridges turn other companies' marketplaces into your unpaid, always-on, no-calls-required sales team.

---

## 2. What to roll out — and in what order

Ruthlessly sequenced by *revenue-per-hour-of-your-time*, not by technical interest.

### Tier 0 — The Firehose (build first, build once)
**Generic outbound event bridge → signed webhook → Zapier/Make.**
- VBWD emits every meaningful event (signup, payment, churn, plan change, invoice) to a signed outbound webhook.
- Zapier/Make catch it and fan out to HubSpot, Pipedrive, Salesforce, Mailchimp, Slack, Sheets — whatever the customer already uses.
- **You build one thing. The customer does the mapping. You support nothing platform-specific.**
- This is the most async-compatible bridge possible: no OAuth dance you maintain, no per-CRM schema drift, no two-way sync bugs.
- **Sells as:** "VBWD connects to 6000+ apps." True, and you wrote ~600 lines to say it.

### Tier 1 — The Flagships (the two that earn the marketplace listings)
1. **WooCommerce inbound bridge.** Orders/customers → VBWD subscriptions; entitlement back. Cheapest real commerce bridge, REST + HMAC webhooks, WordPress/DACH-native. Gets you a **WordPress.org listing** = free perpetual top-of-funnel in your strongest geo.
2. **HubSpot native bridge.** Two-way contact/deal sync that the Firehose can't do (it's one-way). Gets you into the **HubSpot App Marketplace** = the highest-intent B2B SaaS buyers, and a co-marketing badge.

### Tier 2 — Demand-gated (build only when a paying customer asks)
- **Shopify** (backend + Checkout Kit) — big but more work; only once you have Shopify-merchant pull. Reward is the Shopify App Store, which can be a *revenue line on its own* (per-install app pricing).
- **Pipedrive / Zoho** — cheap native CRMs, add when the Firehose proves CRM demand is real.

### Tier 3 — Defer (do not build now)
- **Salesforce, Contentful, Webflow, native CRM mobile SDKs.** High effort, enterprise-shaped, sync-heavy, not your market this year. Saying "no" here is part of the strategy.

**Decision rule:** never build a bespoke connector before the Firehose has shown the demand for it. The Firehose is your market-research instrument *and* your MVP shipping vehicle.

---

## 3. What sales can we actually do — the money model

Three revenue mechanisms, all async, all compatible with the part-time constraint:

### A. Bridges as a paid VBWD add-on (your own checkout)
- Bundle bridges into a **"Connect" tier** of the VBWD license, or sell each bridge as a paid plugin via the checkout you already eat-your-own-dog-food on.
- Pricing anchor: **€149–€399/year per bridge**, or rolled into a higher license tier. Integrations are the #1 reason buyers upgrade tiers — you're not inventing demand, you're capturing it.
- Zero marginal selling cost: it's a toggle in the admin plugin manager.

### B. Marketplace-native monetization (their checkout, their traffic)
- **Shopify App Store** supports recurring app subscriptions billed by Shopify — a genuinely separate revenue stream where Shopify handles billing and dunning for you. This is the most "passive income" line available to a solo dev.
- **HubSpot Marketplace** drives qualified installs into your own checkout; the badge is the conversion lever.
- **WordPress.org** free listing → freemium upsell to the paid VBWD license.

### C. Affiliate / referral kickbacks
- Many of these platforms (and the payment providers behind commerce bridges) pay referral fees. The 90-day plan already counts affiliate fees as a revenue stack item — bridges are the natural place they land.

**How this ladders to €100k:** the bridges don't need to be a big line themselves. Their job is **funnel**, not just **fee**. A WooCommerce/WordPress listing that sends 30 self-serve license trials a month, converting at even 5% to a €490 license, is ~€9k/yr of license revenue you did no calls to earn — plus whatever the bridge add-on itself bills. Two listings + the Firehose realistically move the trial top-of-funnel enough to defend the "tight but achievable" €100k call in the 90-day plan.

---

## 4. What to build extra to the current plugin system

The plugin system is the right foundation — bridges are plugins, core stays agnostic, nothing here violates that. But shipping N bridges by hand-rolling N plugins is the trap. **Build the framework once; each new bridge becomes a thin config-plus-mapping plugin.** This is the only "extra" investment, and it pays for itself by bridge #2.

### 4.1 Bridge Framework (a base layer in the plugin system)
A reusable backend abstraction every bridge plugin extends — so a new bridge is ~a few hundred lines, not a few thousand:

- **`OutboundEventBus` / event emitter** — a single, well-defined set of domain events (signup, payment.captured, subscription.changed, churn, invoice.created) that any bridge can subscribe to. This is the backbone of the Firehose and reused by every native bridge. Sits beside the existing line-item / lifecycle port pattern, not inside core.
- **`IBridgeConnector` port** — uniform interface: `connect()`, `map_outbound(event) -> payload`, `ingest_inbound(payload) -> domain action`, `health()`. Each platform implements it. Liskov-clean, DI-injected, exactly the SOLID/port pattern you already enforce.
- **Signed-webhook primitives** — HMAC-SHA256 sign/verify, retry queue with backoff, idempotency keys, dead-letter handling. **Build once, every bridge inherits.** (WooCommerce, Shopify, and your own outbound all need the identical machinery — proven by the research.)
- **OAuth token vault** — encrypted storage + refresh loop for the OAuth bridges (HubSpot, Shopify, Pipedrive). One implementation, many consumers. Reuses the encryption approach already in the meinchat plugin.
- **Field-mapping engine** — declarative mapping config (VBWD field ↔ remote field) so per-platform differences are *data*, not code. This is what makes bridge #3 cheap.

### 4.2 Per-bridge backend plugin (thin)
Each bridge = a standard `plugins/<bridge>/` plugin: the connector implementation, its field-mapping defaults, its Alembic tables (in-plugin, per your migration rule), `config.json` + `admin-config.json` with the mandatory `debug_mode` toggle. That's it. The heavy lifting lives in the framework.

### 4.3 fe-admin config plugin (generic, reused by all)
One `vbwd-fe-admin` plugin that renders: **Connect (OAuth button) → field mapping → sync toggles → health/last-sync status.** Driven by each bridge's `admin-config.json`. Build the panel once; every bridge populates it. No bespoke admin UI per bridge.

### 4.4 Frontend / iOS / Android — deliberately minimal
The research is unambiguous: CRM/commerce bridges are **server-to-server**. The phone and the browser should call **VBWD's** API; VBWD talks to the third party. So:
- **fe-user:** only embedded widgets (e.g., a hosted-checkout redirect) — near-zero work.
- **iOS / Android:** **nothing now**, except the one genuinely mobile-native item worth doing — **SSO (Sign in with Apple / Google / OAuth-CRM)** via the OS-native credential APIs, shared with the backend OAuth vault. Shopify Checkout Kit only if/when a Shopify in-app sales case appears.
- This restraint *is* the strategy: it keeps the whole initiative inside your 10-hour week.

### Build budget, honestly
- **Bridge Framework + Firehose + fe-admin config panel:** the real upfront cost. Front-load it.
- **WooCommerce bridge:** small once the framework exists.
- **HubSpot bridge:** small-to-medium (two-way sync), gated behind the OAuth vault being done.
- Everything else: demand-gated, so it costs nothing until it earns.

All of it lands under the existing engineering bar — TDD-first, SOLID/DI/Liskov, `bin/pre-commit-check.sh --full` green, no core changes. Bridges are gnostic; core stays agnostic. The framework is just a *shared plugin-side* layer, not a core dependency.

---

## 5. The pitch, condensed

1. **You can't sell synchronously — so let marketplaces sell for you.** Bridges are listings, listings are inbound, inbound needs no calls.
2. **Build the Firehose first.** One webhook = hundreds of integrations = "connects to 6000+ apps," for ~a weekend of work.
3. **Two flagship listings** (WooCommerce/WordPress + HubSpot) put you in front of high-intent buyers in your strongest geo and your best B2B funnel.
4. **Monetize three ways** — paid add-on tier (your checkout), marketplace-native subscriptions (Shopify/HubSpot traffic), and referral fees. The bigger win is funnel, not fee.
5. **Invest once in a Bridge Framework** so every future bridge is a thin plugin — keeping the whole program inside 10 hours a week and inside the core-agnostic rule.
6. **Say no to Salesforce/enterprise/mobile SDKs this year.** Restraint is what makes it shippable.

**Bottom line:** bridges are the only growth lever that compounds *without* costing you synchronous time. Build the framework, ship the Firehose, list two flagships, and the marketplaces become an always-on top-of-funnel that defends the €100k Y1 target while you keep your day job.

---

*Sources for the technical claims (HubSpot OAuth/webhooks, Shopify Buy SDK + Checkout Kit, WooCommerce REST/HMAC webhooks, Salesforce Mobile SDK status) are captured in the integration-bridges research thread, May 2026.*
