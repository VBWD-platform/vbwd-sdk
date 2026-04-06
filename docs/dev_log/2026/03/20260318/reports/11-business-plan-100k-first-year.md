# VBWD-SDK Business Plan: $100K First Year

**Author:** Solo Enterprise Developer
**Date:** 2026-03-19
**Product:** VBWD-SDK — Self-hosted SaaS subscription platform
**License:** BSL 1.1 (Business Source License)

---

## Executive Summary

VBWD-SDK is a production-ready, self-hosted subscription platform with 12 backend plugins, 3 payment gateways, and full admin/user portals. Licensed under **BSL 1.1** — source code is publicly readable, free for development and small use (under 5,000 EUR annual revenue OR under 24 users), and requires a commercial license for production use above those thresholds. Revenue target: **$100,000 in Year 1** through license sales, partner program, managed hosting, and custom development.

**Core advantage:** 0% transaction fees, full data ownership, GDPR-compliant by architecture. Competes with Kajabi ($149-$399/mo), Substack (10% cut), Gumroad (10% cut), Calendly ($12-$20/mo), and custom SaaS builds ($50K-$200K).

---

## License Model: BSL 1.1

### Additional Use Grant (AUG)

Production use is permitted **without a commercial license** if BOTH conditions are met:
- Annual revenue of the licensee does not exceed **5,000 EUR**
- Total number of registered users does not exceed **24**

Everyone else needs a commercial license. This means:
- Developers can freely evaluate, test, and build on the platform
- Hobbyists and micro-businesses get started for free (builds community, word of mouth)
- Any business making real money or scaling past 24 users pays for a license
- The code is publicly visible on GitHub (builds trust, enables evaluation)
- After **4 years**, each version converts to **Apache 2.0** (true open source)

### Why BSL Works Better Than CC0

| Aspect | CC0 (old) | BSL 1.1 (new) |
|--------|-----------|---------------|
| Source visibility | Public | Public |
| Free dev/testing | Yes | Yes |
| Free production use | Unlimited | Under 5K EUR / 24 users |
| Commercial production | Free (no revenue) | **Requires license** |
| Fork protection | None | Cannot compete without license |
| Partner model | None | License resale + revenue share |
| Enterprise trust | Low (too permissive) | High (clear commercial terms) |

### What This Changes for the Business

1. **License sales become enforceable** — production use above AUG thresholds legally requires purchase
2. **No more "why pay when it's free?"** — clear boundary between free and paid use
3. **Enterprise buyers prefer BSL** — it signals a sustainable vendor, not an abandoned project
4. **Partner resale is real** — partners can resell licenses with legal backing
5. **Fork risk is managed** — competitors can't take your code and sell it for 4 years

---

## 1. Product Packaging

### 1.1 License Tiers

| Tier | Price | AUG Status | What's Included |
|------|-------|------------|-----------------|
| **Community** | Free | Within AUG | Full platform + all plugins, self-hosted, under 5K EUR revenue AND under 24 users |
| **Starter** | $499/year | Above AUG | Production license for 1 deployment, up to 500 users, email support |
| **Professional** | $1,499/year | Above AUG | Production license, unlimited users, all plugins, priority support, deployment guide |
| **Enterprise** | $4,999/year | Above AUG | Everything + multi-deployment, 1 year dedicated support, custom plugin consultation (4h), white-label rights |
| **Managed Hosting** | $149/mo | License included | We host it, SSL, backups, updates, monitoring, license included |
| **Support Plan** | $199/mo | Add-on | Priority bug fixes, Slack/email, monthly check-in (requires active license) |
| **Custom Plugin Dev** | $150/hr | Separate | Build custom plugins on the VBWD platform |

**Key changes from CC0 model:**
- **Annual licensing** (not one-time) — creates recurring revenue
- **Free tier is real** (AUG) — not a trial, an actual usable free tier that converts
- **Higher prices justified** — you're selling a legal right, not just support
- **Managed hosting includes license** — simplifies the offering

### 1.2 Revenue Math to $100K

**Conservative scenario (12 months):**

| Revenue Stream | Units | Price | Total |
|----------------|-------|-------|-------|
| Starter licenses (annual) | 35 | $499 | $17,465 |
| Professional licenses (annual) | 18 | $1,499 | $26,982 |
| Enterprise licenses (annual) | 4 | $4,999 | $19,996 |
| Managed hosting (avg 8 clients by month 6) | ~60 client-months | $149 | $8,940 |
| Support plans (avg 5 clients by month 6) | ~35 client-months | $199 | $6,965 |
| Custom plugin dev | 140 hours | $150 | $21,000 |
| **Total** | | | **$101,348** |

This requires ~57 license sales over 12 months = **~5 sales per month** average, ramping from ~2/month in Q1 to ~8/month in Q4. Fewer sales needed than CC0 model because annual pricing is higher.

**Year 2 upside:** License renewals from Year 1 clients create a $65K baseline before any new sales.

---

## 2. The 5 Demo Servers

Each demo is a fully working instance with pre-loaded data, showcasing a specific vertical. Visitors can explore freely. The AUG means they can even self-deploy for free if they're small — and they upgrade to paid when they grow.

### Demo 1: Booking Platform (Calendly/Acuity killer)
- **URL:** booking.vbwd.io
- **Plugins:** booking, email, stripe, cms
- **Pitch:** "Launch your appointment booking platform. Coaching, consulting, salon, clinic. Zero transaction fees."
- **Target buyers:** Coaches, consultants, salon owners, clinics, yoga studios
- **Demo data:** Sample rooms, time slots, booking flow, email confirmations
- **Competitor pricing:** Calendly $12-20/user/mo, Acuity $20-46/mo
- **VBWD:** Free under 24 users, $499/year after

### Demo 2: Software Store (Gumroad/Paddle alternative)
- **URL:** store.vbwd.io
- **Plugins:** ghrm, stripe, paypal, email, cms
- **Pitch:** "Sell software, scripts, templates. Subscription-gated GitHub repos. Keep 100% of revenue."
- **Target buyers:** Indie devs, template creators, plugin authors, course creators with code repos
- **Demo data:** Sample software catalogue, subscription tiers, gated repo access
- **Competitor pricing:** Gumroad 10% + fees, Paddle 5% + fees
- **VBWD:** Free under 5K EUR, $499/year after — still saves thousands vs percentage-based fees

### Demo 3: Content Subscription Platform (Substack/Ghost/OnlyFans alternative)
- **URL:** content.vbwd.io
- **Plugins:** cms, email, stripe, paypal, mailchimp
- **Pitch:** "Premium content with subscriber billing. Newsletter, articles, media. Own your audience."
- **Target buyers:** Writers, journalists, content creators, newsletter operators
- **Demo data:** Published pages, subscriber tiers, paywall demo, email campaigns
- **Competitor pricing:** Substack 10%, Ghost $9-199/mo, OnlyFans 20%
- **VBWD:** Free to start, $499/year when revenue exceeds 5K EUR — a writer earning $1K/mo saves $1,200/year vs Substack after the license cost

### Demo 4: Digital SaaS (AI Tools Platform)
- **URL:** saas.vbwd.io
- **Plugins:** taro, chat, stripe, email, analytics, cms
- **Pitch:** "Launch AI-powered SaaS with token billing. Chat, tools, API access. Metered usage built in."
- **Target buyers:** AI wrapper builders, SaaS founders, API tool creators
- **Demo data:** Working taro readings, AI chat with token deduction, usage analytics
- **Competitor pricing:** Custom build $50-200K
- **VBWD:** $1,499/year Professional (most SaaS builders will exceed AUG quickly)

### Demo 5: Merchant / E-commerce (Shopify-lite)
- **URL:** merchant.vbwd.io
- **Plugins:** cms, stripe, paypal, yookassa, email, booking (for services), analytics
- **Pitch:** "Subscription commerce for digital + physical goods. Multi-currency, multi-gateway."
- **Target buyers:** Small merchants, subscription box operators, digital + physical hybrid sellers
- **Demo data:** Product pages, checkout flow, multi-currency pricing, invoice management
- **Competitor pricing:** Shopify $39-399/mo + 2.9%
- **VBWD:** Free under 5K EUR, $499/year after — pays for itself in 2 months vs Shopify basic
- **Note:** E-commerce plugin (product catalog, cart, inventory) is the next plugin to build

---

## 3. Sales Funnel (BSL-Specific)

```
Visit demo site (free, no signup)
  |
Try it (pre-loaded demo data, full admin access)
  |
Star GitHub repo / join Discord
  |
Self-deploy under AUG (free — under 5K EUR / 24 users)
  |
Business grows past AUG thresholds
  |
  +---> Buy Starter license ($499/year)
  |       |
  |       +---> Upgrade to Professional ($1,499/year)
  |               |
  |               +---> Upgrade to Enterprise ($4,999/year)
  |
  +---> Buy Managed Hosting ($149/mo — license included)
  |
  +---> Request Custom Plugin ($150/hr)
```

**Key difference from CC0 funnel:** The free tier (AUG) is a genuine growth engine, not friction. Users start free, build their business on VBWD, and naturally convert to paid when they succeed. This is the same model that made Sentry, CockroachDB, and HashiCorp successful.

**Conversion triggers:**
- Revenue crosses 5K EUR → automatic license requirement
- User count crosses 24 → automatic license requirement
- Need priority support → Support plan add-on
- Don't want to manage servers → Managed hosting

---

## 4. Partner Program

The BSL license enables a real partner ecosystem — partners can resell licenses and earn from the platform.

### 4.1 Partner Types

| Partner Type | What They Do | How They Earn |
|--------------|-------------|---------------|
| **Reseller** | Sells VBWD licenses to their clients | 20-30% commission on license sales |
| **Solution Partner** | Builds vertical solutions on VBWD, sells to end clients | Keeps 100% of their service revenue + 20% license commission |
| **Hosting Partner** | Offers VBWD as managed service on their infrastructure | Revenue share on hosting fees |
| **Integration Partner** | Builds plugins/integrations for the VBWD ecosystem | Sells their plugins independently, listed in partner directory |

### 4.2 Partner Revenue Sharing

| Revenue Stream | How It Works | Partner Cut |
|----------------|-------------|-------------|
| **License resale** | Partner sells VBWD to their client, you fulfill the license | 20-30% of license price |
| **Stripe referral** | Stripe Partners Program — $2/activated account + revenue share | Split 50/50 with partner |
| **PayPal referral** | PayPal Partner Program — referral bonuses | Split 50/50 with partner |
| **Managed hosting referral** | Partner's client signs up for your $149/mo hosting | $30/mo recurring to partner |
| **Custom dev referral** | Partner refers a custom plugin project to you | 15% finder's fee |
| **Partner's own services** | Partner charges their own rates for config/customization | 100% theirs |

### 4.3 Partner Economics Example

A web agency becomes a VBWD Solution Partner:
- Builds a booking solution for yoga studios using VBWD + booking plugin
- Charges each studio $2,000 setup + $79/mo hosting (on their own infra)
- Resells VBWD Professional license ($1,499/year) — earns $450 commission per client
- Signs up 10 studios in Year 1:
  - Setup revenue: $20,000 (theirs)
  - Hosting revenue: $9,480/year (theirs)
  - License commissions: $4,500/year (from you)
  - **Partner's total: $33,980/year from one vertical**
  - **Your revenue: $10,490/year in licenses from this one partner**

### 4.4 Payment Provider Cashback

**Stripe Partners Program:**
- Apply at stripe.com/partners
- Earn for every new Stripe account activated through VBWD deployments
- Revenue share on processing volume (typically 0.05-0.15% of volume)
- Split with the partner who brought the merchant

**PayPal Commerce Platform:**
- Referral fees for new PayPal merchant accounts
- Negotiable rates for platform volume

**YooKassa (CIS markets):**
- Referral program for new merchant activations
- Relevant for Russian/CIS market deployments

**Estimated Year 1 from payment referrals:** $2,000-$5,000 (grows significantly in Year 2+ as merchant volume increases)

---

## 5. Marketing Strategy (Solo Developer, Low Budget)

### 5.1 Content Marketing (Free, High ROI)

**Month 1-3: Foundation**

| Channel | Action | Frequency |
|---------|--------|-----------|
| **Dev.to / Hashnode** | Architecture articles, build-in-public, BSL case study | 2x/month |
| **Hacker News** | Show HN posts for each demo launch | 5 posts total |
| **Reddit** | r/selfhosted, r/SaaS, r/webdev, r/Entrepreneur, r/indiehackers | 3x/week |
| **Twitter/X** | Build in public thread, demo GIFs, architecture decisions | Daily |
| **YouTube** | "Deploy your own [X] in 10 minutes" for each vertical | 5 videos |
| **GitHub** | Public repo, detailed README, contribution guide | Ongoing |

**Key articles to write:**
1. "Source-available SaaS platform: why BSL is the right license for indie developers"
2. "0% transaction fees: The self-hosted alternative to Substack/Gumroad"
3. "Free under 24 users: How our pricing grows with your business"
4. "GDPR compliance by architecture, not by checkbox"
5. "From monolith to 12 plugins: A solo dev's SaaS journey"
6. "Why agencies should become VBWD partners (the math)"

### 5.2 Community & SEO (Month 2-6)

- **Self-hosted community:** Submit to awesome-selfhosted list (BSL-licensed projects are accepted), r/selfhosted wiki
- **Product Hunt:** Launch each vertical as a separate product (5 launches = 5 chances to trend)
- **AlternativeTo:** List as alternative to Kajabi, Substack, Gumroad, Calendly, Ghost
- **SEO landing pages:** One per vertical — "self-hosted [Substack/Calendly/Gumroad] alternative"
- **Comparison pages:** "VBWD vs Kajabi", "VBWD vs Substack" (with cost calculators showing AUG → paid transition)
- **Discord community:** Free support for AUG users, partner channel, plugin showcase

### 5.3 Paid Marketing (Month 4+, reinvest early revenue)

| Channel | Budget/mo | Expected |
|---------|-----------|----------|
| Google Ads ("self-hosted subscription platform", "open source Substack alternative") | $200 | 5-10 leads |
| Sponsoring self-hosted newsletters (Noted, selfh.st) | $100 | Brand awareness |
| Dev tool directories (StackShare, LibHunt, etc.) | Free-$50 | SEO backlinks |

**Total monthly marketing budget: $300-500** (from Month 4, funded by early sales)

### 5.4 Partnership Acquisition

- **Hosting providers:** Partner with Hetzner, DigitalOcean, Contabo for one-click deploy images
- **Web agencies:** Direct outreach to agencies in target verticals (booking, content, SaaS)
- **Freelancer platforms:** Upwork/Toptal profiles offering "VBWD deployment specialist" services
- **Plugin marketplace:** Community plugins welcome (partners keep 100% of their plugin revenue)

---

## 6. Technical Requirements for Demo Servers

### 6.1 Infrastructure

| Item | Provider | Cost/mo |
|------|----------|---------|
| 5 VPS (2GB RAM each) | Hetzner CX22 | 5 x $4.50 = $22.50 |
| Domain (vbwd.io) | Cloudflare | ~$10/year |
| SSL | Let's Encrypt | Free |
| Email (transactional) | Mailchimp Transactional (Mandrill) | Free tier (500/day) |
| Stripe test/live account | Stripe | Free (2.9% per tx) |
| Monitoring | UptimeRobot free tier | Free |
| **Total infrastructure** | | **~$25/mo** |

### 6.2 Demo Data Setup

Each demo needs:
- 3-5 tariff plans with realistic pricing
- 10-20 content items (pages, products, repos)
- Sample user accounts (viewer + admin)
- Working payment flow (Stripe test mode or live with $1 products)
- Reset cron: daily database reset to clean state
- Banner: "This is a demo — get your own instance free under 24 users"

### 6.3 Demo Server Deployment Checklist

```bash
# Per demo server:
1. Provision VPS (Hetzner CX22, Ubuntu 24.04)
2. Install Docker + docker-compose
3. Clone vbwd-platform scaffold
4. Configure plugins.json (only vertical-relevant plugins)
5. Configure .env (DB, Redis, payment keys, email)
6. Run make install && make up
7. Load demo data (populate_db.py per plugin)
8. Configure Nginx + Let's Encrypt SSL
9. Set up daily DB reset cron
10. Set up UptimeRobot monitoring
```

---

## 7. Timeline

### Q1 (Months 1-3): Launch

| Week | Action |
|------|--------|
| 1-2 | Deploy 5 demo servers, load demo data, test payment flows |
| 3 | Launch marketing site (vbwd.io) with pricing, 5 vertical landing pages, license purchase flow |
| 4 | Write first 3 blog posts, submit to HN, Reddit, Dev.to |
| 5-6 | Product Hunt launch #1 (booking vertical) |
| 7-8 | Product Hunt launch #2 (content subscription) |
| 9-10 | YouTube "Deploy in 10 min" videos for 2 verticals |
| 11-12 | Product Hunt launch #3 (software store), begin partner outreach |

**Q1 Target:** 8-12 license sales ($6K-$10K), 50+ AUG users, 200+ GitHub stars, 2-3 partner applications

### Q2 (Months 4-6): Growth

- Launch remaining Product Hunt verticals (#4 SaaS, #5 merchant)
- Start Google Ads ($200/mo)
- Begin managed hosting service
- Build e-commerce plugin (merchant demo)
- Onboard first 3-5 partners (agencies/freelancers)
- First AUG → paid conversions (users who outgrew free tier)
- Establish Discord community (100+ members)

**Q2 Target:** 15-20 license sales ($15K-$25K), 5+ managed hosting clients, 5 active partners, first custom dev gigs

### Q3 (Months 7-9): Scale

- SEO starts compounding (comparison pages ranking)
- Partner network generating referrals
- AUG → paid conversion rate stabilizing
- Community plugins appearing
- Speaking at 1-2 online meetups/podcasts
- One-click deploy on DigitalOcean/Hetzner marketplace
- Apply to Stripe Partners Program

**Q3 Target:** 18-25 license sales ($20K-$30K), 8+ managed hosting, 10+ partners, steady custom dev pipeline

### Q4 (Months 10-12): Compound

- License renewals begin (Q1 annual licenses renewing)
- Partner-driven sales becoming significant (20-30% of new licenses)
- Payment provider cashback starting to flow
- Word of mouth from satisfied customers
- Case studies from early adopters
- Consider hiring first contractor for support

**Q4 Target:** 20-30 license sales ($25K-$35K), 12+ managed hosting, recurring support plans

---

## 8. Competitive Positioning

### Price Comparison (Annual Cost for User)

| Platform | Year 1 Cost | Transaction Fee | Data Ownership | Source Available |
|----------|-------------|-----------------|----------------|-----------------|
| **VBWD Community** | **Free** | **0% (own Stripe)** | **Full** | **Yes** |
| **VBWD Starter** | **$499** | **0%** | **Full** | **Yes** |
| **VBWD Professional** | **$1,499** | **0%** | **Full** | **Yes** |
| Kajabi | $1,788-$4,788 | 0% | No | No |
| Substack | Free | 10% of revenue | No | No |
| Gumroad | Free | 10% of revenue | No | No |
| Ghost Pro | $108-$2,388 | 0% | Partial | Yes (MIT) |
| Calendly | $144-$240/user | 0% | No | No |
| Shopify | $468-$4,788 | 0.5-2% + gateway | No | No |
| OnlyFans | Free | 20% of revenue | No | No |
| Custom build | $50,000-$200,000 | Varies | Full | N/A |

### One-line Pitch Per Vertical

- **Booking:** "Calendly without the monthly fee. Self-hosted. Free under 24 users."
- **Software Store:** "Gumroad without the 10% cut. Free until you make 5K EUR."
- **Content:** "Substack without the platform tax. Own your subscribers forever."
- **Digital SaaS:** "Ship AI tools with built-in billing. $1,499/year, not $200K."
- **Merchant:** "Shopify-lite, self-hosted. Free to start, $499/year when you scale."

### The AUG Advantage in Sales Conversations

The free tier under AUG is a powerful sales tool:
- "Start free. No credit card. No trial expiration. Build your business."
- "When you outgrow 24 users or 5K EUR, you're already making money — the license pays for itself."
- "Your first 24 customers cost you $0 in platform fees."

This eliminates the #1 objection ("why should I pay?") and replaces it with a success-aligned upgrade path.

---

## 9. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Low initial traffic | Slow sales | Double down on content marketing, HN/Reddit are free |
| Support burden as solo dev | Burnout | Tier support (email only for Starter, limit Enterprise to 4 clients) |
| BSL enforcement | Someone uses in production without license | Automated user-count check in admin panel; legal notice for detected violations |
| Competitors drop prices | Price pressure | AUG free tier + annual pricing already competitive; sell on ownership |
| Technical issues on demo servers | Lost trust | Daily monitoring, DB reset cron, Hetzner snapshots |
| Someone forks and waits 4 years | Delayed competition | You're 4 years of features ahead; change date keeps moving with each release |
| Partners underperform | Slow partner revenue | Low cost to maintain; focus on 2-3 high-performing partners |
| AUG users never convert | Free riders | Expected — they're marketing. 5% conversion rate is the target |
| Custom dev projects scope creep | Unprofitable hours | Fixed-scope quotes only, $150/hr for overages, clear SOWs |

---

## 10. Key Metrics to Track

| Metric | Tool | Target (Month 12) |
|--------|------|-------------------|
| AUG deployments (free) | Telemetry opt-in / GitHub clones | 200+ |
| AUG → Paid conversion rate | Stripe + license system | 5-10% |
| Demo site visits | Plausible/Umami | 5,000/mo |
| GitHub stars | GitHub | 1,000+ |
| Discord members | Discord | 300+ |
| Monthly license sales | Stripe dashboard | 8+/mo |
| License renewal rate | Stripe | 70%+ |
| Managed hosting MRR | Stripe | $1,200+/mo |
| Support plan MRR | Stripe | $1,000+/mo |
| Active partners | Partner portal | 10+ |
| Partner-sourced license sales | Attribution tracking | 20-30% of sales |
| Payment provider cashback | Stripe/PayPal partner dashboards | $200+/mo |
| Custom dev pipeline | Linear/Notion | 2-3 active projects |
| Content pieces published | Blog | 30+ total |
| Conversion rate (visit → AUG deploy) | Plausible | 3-5% |
| Conversion rate (visit → paid) | Plausible | 1-2% |

---

## 11. What to Build Next (Revenue-Ordered Priority)

| Priority | Plugin/Feature | Why | Revenue Impact |
|----------|---------------|-----|----------------|
| 1 | **License management system** | Enforce BSL, automate license key generation/validation | Critical |
| 2 | **Marketing site** (vbwd.io) | Required for sales funnel, pricing page, license purchase | Critical |
| 3 | **E-commerce plugin** | Completes merchant vertical, largest market | High |
| 4 | **One-click deploy scripts** (DO, Hetzner) | Removes biggest friction for self-hosters and AUG users | High |
| 5 | **Partner portal** | Partner registration, commission tracking, license resale | High |
| 6 | **Demo data presets** per vertical | Makes demos compelling | High |
| 7 | **Webhook/Zapier plugin** | Integration story for non-developers | Medium |
| 8 | **White-label theme system** | Enterprise upsell | Medium |
| 9 | **Multi-tenant mode** | SaaS builders who want to resell | High (future) |
| 10 | **Mobile app shell** (Capacitor) | Differentiation from web-only competitors | Medium |

---

## Summary

You have a **production-ready platform** with 1,851+ tests, 12 plugins, 3 payment gateways, and full admin/user portals. The **BSL 1.1 license** transforms the business model from "selling support around free code" to "selling the right to use the code commercially" — a fundamentally stronger position.

**The formula:**
- Free tier (AUG: <5K EUR, <24 users) drives adoption and word-of-mouth
- 5 demo servers showing real verticals (~$25/mo hosting)
- Content marketing on HN, Reddit, Dev.to, YouTube (free)
- 5 Product Hunt launches (free)
- SEO comparison pages (free)
- Partner program generating 20-30% of license sales by Q4
- Payment provider cashback as passive income
- Custom dev work fills gaps between license sales
- $300-500/mo paid marketing from Month 4

**$100K = 57 licenses + 8 hosting clients + 140 dev hours + partner commissions.**

**Year 2 baseline before any new sales: ~$65K** from license renewals + recurring hosting + support plans. The BSL annual licensing model builds compounding recurring revenue that CC0 never could.