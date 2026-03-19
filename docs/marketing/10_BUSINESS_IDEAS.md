# 10 Business Ideas for Solo/Small Dev Teams on VBWD

**Date:** March 2026
**Audience:** Solo developers or teams of 2-3 who want to build a product business on top of the VBWD platform
**License:** BSL 1.1 — production use requires a VBWD license

---

## How This Works

You buy a VBWD license, deploy it on a server, enable the plugins you need, build your vertical-specific plugin(s), and sell the result to end clients as a turnkey solution. You own your plugin code. Your clients pay you — not VBWD — for the product and ongoing service.

**Your cost structure:**
- VBWD license: one-time (per deployment)
- Server: $5-25/mo (Hetzner/DigitalOcean)
- Stripe fees: 2.9% + $0.30 per transaction (paid by your client's customers)
- Your time: the only real cost

**Your revenue model:** SaaS subscription to your clients, one-time setup fees, ongoing support retainers, or reselling VBWD licenses with your vertical solution on top.

---

## 1. Online Course Platform (Teachable/Kajabi Killer)

**What you build:** A plugin that adds course modules (video lessons, text content, quizzes, progress tracking) gated by subscription tiers.

**VBWD plugins used:** CMS (content pages), Stripe/PayPal (payments), Email (drip sequences), Analytics

**What you add:**
- Course model: modules, lessons, progress tracking
- Video hosting integration (Bunny.net or Mux — simple API calls)
- Certificate generation on completion
- Student dashboard showing enrolled courses + progress

**Target clients:** Online educators, coaches, fitness trainers, language tutors

**Pricing to your clients:** $49/mo hosted or $1,500 one-time self-hosted setup

**Why it works:** Teachable charges $149/mo + 5% transaction fee on their basic plan. Kajabi starts at $149/mo. Your client pays $49/mo with 0% platform transaction fee. At 20 clients you're earning $11,760/year recurring.

**Dev effort:** 2-3 weeks for MVP (course model + progress tracking + video embed)

---

## 2. Membership Community Platform

**What you build:** A plugin that adds forum/community features gated by subscription level — threads, comments, member directory, private messaging.

**VBWD plugins used:** CMS (announcements/articles), Email (notifications), Stripe, Analytics

**What you add:**
- Forum model: categories, threads, posts
- Member profiles with subscription-tier badges
- Notification system (new posts in followed threads)
- Optional: Discord/Slack webhook integration for real-time chat bridge

**Target clients:** Niche communities — photography clubs, developer groups, hobbyist networks, professional associations, alumni groups

**Pricing to your clients:** $39/mo hosted or $999 one-time self-hosted

**Why it works:** Circle.so charges $89-399/mo. Mighty Networks $33-119/mo. Most communities need <1,000 members — overkill to pay platform prices. At 30 clients, $14,040/year recurring.

**Dev effort:** 3-4 weeks (forum CRUD + notifications + tier gating)

---

## 3. Client Portal for Agencies/Freelancers

**What you build:** A branded portal where agencies deliver work to clients — project status, file sharing, invoice history, subscription billing for retainers.

**VBWD plugins used:** CMS (project updates/knowledge base), Stripe (retainer billing), Email, Analytics

**What you add:**
- Project model: status, timeline, deliverables
- File upload/delivery (extend CMS image storage to general files)
- Client-facing dashboard: "Your projects", "Your invoices", "Your subscription"
- White-label: client sees agency's brand, not VBWD

**Target clients:** Marketing agencies, web dev shops, design studios, consulting firms

**Pricing to your clients:** $79/mo hosted (includes white-label) or $2,000 one-time setup

**Why it works:** Agencies currently cobble together Notion + Stripe + Google Drive + a custom portal. This replaces all of it. Retainer billing is already built. At 15 clients, $14,220/year recurring.

**Dev effort:** 2-3 weeks (project model + file delivery + white-label theming)

---

## 4. Newsletter/Paid Media Platform (Substack Alternative)

**What you build:** Minimal — this almost works out of the box. Add an RSS feed generator and email-to-subscriber dispatch.

**VBWD plugins used:** CMS (articles), Email + Mailchimp (newsletter dispatch), Stripe/PayPal, Analytics

**What you add:**
- RSS feed generation from CMS pages
- Scheduled publishing (draft → publish at date/time)
- Email dispatch: new post → send to all paying subscribers
- Public/subscriber/premium tier content visibility
- Import tool: migrate from Substack/Ghost (CSV import)

**Target clients:** Writers, journalists, niche newsletter operators, industry analysts

**Pricing to your clients:** $29/mo hosted or $499 one-time self-hosted

**Why it works:** Substack takes 10% of all subscriber revenue. A writer earning $5,000/mo loses $500/mo to Substack — $6,000/year. Your $29/mo saves them $5,652/year. Sell it on that math. At 40 clients, $13,920/year recurring.

**Dev effort:** 1-2 weeks (RSS + scheduled publish + email broadcast are straightforward)

---

## 5. AI Tool Wrapper Platform

**What you build:** Nothing — VBWD already has this. Chat plugin (LLM-powered) + Taro plugin (AI interpretations) + token economy for metered billing.

**VBWD plugins used:** Chat, Taro (as template), Stripe, Analytics, Token bundles

**What you add:**
- Swap the LLM behind the chat plugin (Claude, GPT-4, local models)
- Custom system prompts per subscription tier
- API key management (let paying users access via API)
- Usage dashboard showing tokens consumed

**Target clients:** Entrepreneurs who want to sell AI tools but can't build the billing/auth/user management layer

**Pricing to your clients:** $2,500 one-time setup + $99/mo hosting/support

**Why it works:** Building auth + billing + token metering + user portal from scratch costs $30-50K. You deliver it in a week. At 8 clients with hosting, $9,504/year recurring + $20,000 in setup fees.

**Dev effort:** 1 week (mostly configuration, the hard parts are built)

---

## 6. Appointment Booking SaaS for a Specific Vertical

**What you build:** Take the existing booking plugin and customize it deeply for ONE vertical — e.g., barbershops, dental clinics, yoga studios, or tattoo parlors.

**VBWD plugins used:** Booking, Email (confirmations/reminders), Stripe, CMS (service descriptions), Analytics

**What you add:**
- Vertical-specific booking flow (e.g., "Pick your barber → Pick service → Pick time")
- SMS reminders (Twilio integration — 20 lines of code)
- Google Calendar sync
- Public booking page (embeddable widget)
- Staff management: each staff member has their own schedule

**Target clients:** Pick ONE vertical and dominate it. Example: barbershops.

**Pricing to your clients:** $29/mo per location

**Why it works:** Calendly is generic. Fresha (salon-specific) takes a cut of payments. Square Appointments charges $29/mo but locks you into Square payments. You offer: their own payment processor, no transaction cut, branded booking page. There are 80,000+ barbershops in Germany alone. At 50 clients, $17,400/year recurring.

**Dev effort:** 2-3 weeks (vertical-specific UI + SMS + calendar sync)

---

## 7. Digital Asset Marketplace (Themes, Templates, Plugins)

**What you build:** A marketplace where creators list digital products (WordPress themes, Figma templates, code snippets, Notion templates) and buyers purchase via subscription or one-time.

**VBWD plugins used:** GHRM (for code products), CMS (product listings), Stripe/PayPal, Email, Analytics, Token bundles (for credits-based purchasing)

**What you add:**
- Product listing model: title, description, preview images, download file
- Creator accounts (multi-vendor): each creator uploads products, sees their sales
- Revenue split: platform takes X%, creator gets rest (use Stripe Connect)
- Review/rating system
- License key generation per purchase

**Target clients:** You ARE the client — you run the marketplace. Or sell the white-labeled platform to niche communities.

**Revenue model:** 10-15% commission on each sale (still less than Gumroad's 10% + fees or Creative Market's 40%)

**Why it works:** This is a platform play. Build it once, recruit creators, take a cut. If 100 creators each sell $500/mo through your platform at 12% commission, that's $72,000/year.

**Dev effort:** 4-6 weeks (multi-vendor is the complex part — Stripe Connect integration)

---

## 8. Subscription Box Management Platform

**What you build:** A plugin for physical subscription box businesses — manage subscribers, billing cycles, shipping address collection, box customization preferences.

**VBWD plugins used:** Stripe (recurring billing), Email (shipping notifications), CMS (box previews/blog), Analytics

**What you add:**
- Shipping address collection + management in user profile
- Box preference model: size, dietary restrictions, color preferences, etc.
- Fulfillment dashboard: "This month, ship 47 boxes — here's the address CSV export"
- Pause/skip month (extend subscription management)
- Shipping integration: generate labels via EasyPost/Shippo API

**Target clients:** Subscription box entrepreneurs (coffee, snacks, beauty, books, craft supplies)

**Pricing to your clients:** $59/mo hosted or $1,500 one-time

**Why it works:** Cratejoy charges $39/mo + 1.25% of sales + payment processing. Subbly charges $29-79/mo. Your platform: flat fee, no transaction cut. At 25 clients, $17,700/year recurring.

**Dev effort:** 3-4 weeks (address management + preference model + fulfillment export)

---

## 9. White-Label SaaS for Web Agencies

**What you build:** Not a single product — a repeatable service. You become "the VBWD agency" that deploys custom subscription platforms for clients.

**VBWD plugins used:** All of them, mixed per client

**What you offer:**
- Discovery call: understand what the client needs
- Configure VBWD with the right plugins
- Build 1-2 custom plugins for their specific needs
- Deploy, brand, and hand over (or host for them)
- Ongoing support retainer

**Target clients:** Web agencies who get asked "can you build us a subscription platform?" and currently say no or quote $50K+

**Pricing model:**
- Setup fee: $3,000-$8,000 per client (depending on customization)
- Hosting + support: $149/mo per client
- You resell the VBWD license (earn partner commission)

**Why it works:** You're not building from scratch each time. Each project takes 1-3 weeks instead of 3-6 months. At 10 clients/year: $30,000-$80,000 in setup fees + $17,880/year recurring hosting.

**Dev effort:** Variable per client, but your VBWD expertise is the moat

---

## 10. Micro-SaaS: Niche Subscription API

**What you build:** A headless subscription API for a specific niche — no frontend needed. Developers integrate via REST API. Think "Stripe but with user management, plans, and invoicing built in."

**VBWD plugins used:** Core API only (no frontend apps needed), Stripe, Email, Webhooks

**What you add:**
- API documentation site (Swagger/Redoc — Flask auto-generates this)
- API key management per client
- Rate limiting per subscription tier
- Webhook events for all subscription lifecycle changes
- SDKs: Python + JavaScript client libraries (auto-generated from OpenAPI spec)

**Target clients:** Developers building apps who need subscription billing but don't want to build the billing logic themselves. Mobile app developers. IoT device vendors with subscription services.

**Pricing to your clients:** Usage-based — $0.01 per API call or $29-99/mo per tier

**Why it works:** This is Stripe + Auth0 + Chargebee combined into one self-hosted API. Chargebee charges $249/mo for their standard plan. You charge $99/mo. At 30 clients on the $99 tier, $35,640/year recurring.

**Dev effort:** 2-3 weeks (API docs + key management + rate limiting)

---

## Summary: Effort vs Revenue Potential

| # | Business | Dev Time | Revenue Model | Year 1 Potential |
|---|----------|----------|---------------|------------------|
| 1 | Course Platform | 2-3 weeks | $49/mo per client | $12-20K |
| 2 | Membership Community | 3-4 weeks | $39/mo per client | $14-20K |
| 3 | Agency Client Portal | 2-3 weeks | $79/mo per client | $14-24K |
| 4 | Newsletter Platform | 1-2 weeks | $29/mo per client | $10-14K |
| 5 | AI Tool Wrapper | 1 week | $2,500 setup + $99/mo | $20-30K |
| 6 | Vertical Booking SaaS | 2-3 weeks | $29/mo per location | $15-20K |
| 7 | Digital Asset Marketplace | 4-6 weeks | 12% commission | $20-72K |
| 8 | Subscription Box Platform | 3-4 weeks | $59/mo per client | $15-20K |
| 9 | White-Label Agency | 0 (services) | $3-8K setup + $149/mo | $50-100K |
| 10 | Niche Subscription API | 2-3 weeks | $29-99/mo per client | $15-36K |

**Fastest path to revenue:** #5 (AI Tool Wrapper) and #9 (White-Label Agency) — least custom development, highest per-client value.

**Highest recurring potential:** #7 (Marketplace) and #9 (Agency) — but require more effort to get rolling.

**Easiest solo dev play:** #4 (Newsletter) and #6 (Vertical Booking) — small scope, clear market, easy to explain.

---

## Partner Opportunity

As a VBWD partner, you can also earn:
- **20-30% commission** on VBWD license resales to your clients
- **Revenue share** on payment provider referrals (Stripe Partners Program)
- **Listing** on the VBWD partner directory at vbwd.io

Contact: partners@vbwd.io