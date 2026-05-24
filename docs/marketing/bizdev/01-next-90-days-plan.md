# VBWD — Next 90 Days, Honest Plan

**Author context.** Solo developer. Full-time job elsewhere. Available bandwidth for VBWD: realistically **8–12 hours/week**, occasionally 20 in a burst week. Wants to **minimise direct contact with merchants and end users**.

**Targets the plan must hit.**
- **Brutto €100k within 12 months** (May 2026 → May 2027).
- **Brutto €300k within 24 months** (May 2026 → May 2028) — interpreted as cumulative two-year revenue.

**TL;DR.** The existing Owner Business Plan ($73k Y1, $192k Y2) assumes 48–50 hrs/week of founder time, ~37% custom dev (consulting), and active partner recruitment. **None of that survives the actual constraints.** Hitting €100k in 12 months on 10 hrs/week with no synchronous selling requires a very different revenue mix — license-led, marketplace-led, partner-led, all async. This document is the realistic version.

---

## 1. Reality check (read this before the plan)

**The plan in `VBWD_OWNER_BUSINESS_PLAN.md` does NOT survive contact with reality** because:

| Assumption in existing plan | What actually happens part-time |
|---|---|
| 48 hrs/week founder time | You have 10 |
| 37% Y1 revenue from custom dev (~$27k) | Custom dev = synchronous client meetings. Off the table. |
| Manual partner recruitment | Recruiting 10 agencies = 10–30 sales calls. Off the table. |
| Founder-led demo + email support | Both are sync work that scales linearly with customers. Off the table. |
| Manual cold DMs (10/day) | Off the table. |

Strip out custom dev, sales calls, agency recruitment, founder support, and own-brand managed hosting (more on that next). What's **left** that pays:
1. **Self-serve license sales** (checkout already built — VBWD eats its own dog food)
2. **Hosting-platform revenue share** (Elest.io / Cloudron handle ops; you collect a cut for being listed)
3. **Async priority-support add-on** (€299/yr, 24h email SLA, no calls)
4. **Plugin marketplace cut** (other devs do the work)
5. **Affiliate/referral fees** from payment providers and integrations
6. **Pre-recorded paid content** (course / template pack)

That's the realistic stack. Anything that requires you to be on a Zoom is not in the plan.

**Why no own-brand managed hosting** — earlier drafts of this plan included a "VBWD Cloud" line at €29/€79/€199 per month with "85–90% margin." That line is **incompatible with the constraint** and has been cut. Real managed hosting means 24/7 monitoring, incident response when a customer's booking page dies on Saturday at 23:00, restore-from-backup runs at 2am, weekly OS patching, on-call rotation. A solo dev with a day job cannot deliver any of that without breaking the no-sync rule the same week. So the hosting-shaped revenue in this plan comes only from **revenue-share with platforms that already do the ops** — Elest.io's managed app catalog, Cloudron's app store ecosystem, Hetzner Cloud Marketplace snapshots. They run the customer's hosting; you collect a small recurring cut for being listed. If hosting demand from license customers gets loud in late Y1, the answer is then to find a **white-label DevOps partner** who runs "VBWD Cloud" under licence (defer to Y2).

**Honest read on the targets:**
- €100k brutto Y1 part-time + async-only: **achievable but tight**. Needs a launch hit (Product Hunt or HN front page) plus one good marketplace placement to compress the timeline. Without that, slips to €60–80k.
- €300k brutto cumulative 24mo: **achievable** if Y1 ≥ €80k, because Y2 inherits renewals + a much larger top-of-funnel. The math sits at €100k Y1 + €200k Y2 = €300k.
- €1M/year solo + part-time: **not credible**. Not a goal in this 90-day plan.

---

## 2. The competitive landscape — who you are actually fighting

The existing `MARKET_ANALYSIS.md` table is correct as a snapshot but blurs four very different competitor sets that buyers compare against. Treat them separately.

### Bucket A — Self-hosted billing engines (your "looks like us" peers)

| Competitor | License | Pricing | Frontend? | What they got right | What they suck at |
|---|---|---|---|---|---|
| **Lago** | AGPL + cloud | Free OSS / "contact us" cloud | No | YC backing, usage billing, big SDK | AGPL kills commercial reuse; no UI; no plugin system |
| **Kill Bill** | Apache 2.0 | Free | No | 12 years of production at Lyft, Domino's | Java, no UI, brutal learning curve |
| **OpenMeter** | Apache 2.0 | Free | No | ClickHouse-backed metering, fast | Just metering — no plans, no checkout, no UI |
| **BillaBear** | MIT | Free | Minimal | Symfony, single dev | Limited; barely any audience |
| **UniBee** | MIT | Free + cloud | Yes (basic) | Has a UI, recent traction | Still early; no plugin system |
| **Outseta** | Closed | $39–$273/mo + 0% (paid)/20% (free) | Yes | Polished UI, all-in-one for SaaS | Cloud-only, US-hosted, takes a cut on free tier |

**Verdict:** in this bucket, VBWD's differentiator is the **plugin trio + full FE-admin/FE-user + token economy + BSL 1.1 (not AGPL)**. Lago is the most-funded threat but ships zero frontend, and AGPL is poison for the agency channel. Buyers comparing here are technical, low-volume, and price-sensitive — they convert on docs, demo video, and "show HN" social proof.

### Bucket B — Creator/checkout platforms (the "we'll save you 10%" pitch)

| Competitor | Take rate | Hosting | Lock-in |
|---|---|---|---|
| Gumroad | 10% | Cloud | High (their CRM) |
| Lemon Squeezy (now Stripe) | 5% + $0.50 | Cloud (MoR) | Medium |
| Paddle | 5% + $0.50 | Cloud (MoR) | Medium |
| Polar.sh | 4% + $0.40 | Cloud (MoR) | Low — open source-ish |
| Stripe Checkout + custom | 2.9% | DIY | Low |
| Sellfy | 5–9% | Cloud | High |

**Verdict:** here VBWD wins on math at any volume above ~$2k/mo in sales — the slide deck `softwarestore/05-math.html` is correctly built around this. The buyer is non-technical and **will not self-host on a VPS**. Conversion requires a one-click managed deploy. Without that, this bucket converts at <1%.

### Bucket C — Agency white-label OS (the GoHighLevel killer pitch)

| Competitor | Price | Self-hosted? | EU/data sovereignty? |
|---|---|---|---|
| **GoHighLevel** | $97 / $297 / $497/mo | No | No (US-only) |
| **SuiteDash** | $19–$99/mo | No | No |
| **Bonsai** | $25–$66/mo | No | No |
| **Vendasta** | $499–$2,499/mo | No | No |

**Verdict:** the structural opening is real (EU Data Act + CLOUD Act exposure). But agencies buy through **demos and account managers**, both of which violate your constraint. This bucket is **not for the first 12 months**. It re-enters the plan in Y2 once you can afford a part-time SDR, or you sign 1–2 reseller agreements that put a partner agency on the demo calls instead of you.

### Bucket D — Open-core SaaS playbooks you should imitate

These aren't competitors — they're the templates of "solo / tiny team open-core company growing past €1M ARR without a sales motion."

| Company | Strategy that worked | What you can copy |
|---|---|---|
| **Plausible Analytics** | Open source + paid managed cloud, EU positioning, content SEO, no salespeople | EU positioning, "plausible.io vs google" SEO play, simple two-tier pricing |
| **Cal.com** (vs Calendly) | "Open-source X" framing; community PRs; managed cloud upsell | Self-hostable + managed cloud combo |
| **PostHog** | Aggressive content marketing; replace 3 SaaS in one bill | "Replace Stripe Billing + Recurly + Outseta" multi-tool framing |
| **Ghost** | Foundation model, no fundraise, paid hosted, 0% revenue cut | Managed hosting as primary monetisation |
| **Marc Lou (ShipFast)** | Productized boilerplate, one-time pricing, $25M+ revenue solo | One-time payment tier ("buy once, ship forever"); aggressive Twitter+SEO |
| **Pieter Levels (NomadList, etc.)** | No meetings, no investors, build in public, ship many products | The "no meetings" rule itself; cross-pollination between products |
| **Tony Dinh (TypingMind, DevUtils)** | Solo, productized, low-touch paid, content-led | Paddle/Lemon-style checkout; lifetime deals as launch boost |
| **Supabase (early days)** | Open core + cloud + Postgres-as-USP | Differentiator is positioning, not features |

**The playbook these all share:**
1. Open source / source-available is the marketing, not the product.
2. They DO operate their own managed hosting — but they have full-time SREs to do it. **You don't.** For VBWD the equivalent is distribution via existing self-host marketplaces (Cloudron, Elest.io, Coolify) that capture the hosting revenue without you running ops.
3. Founder writes; no founder-led sales calls.
4. Single hero comparison ("X vs Calendly" / "X vs Google Analytics").
5. Pricing on the page, no "contact us."
6. Documentation is the product surface.

**Conclusion:** VBWD's first 12 months should imitate the Plausible/Cal.com/Ghost playbook with a Marc Lou-style one-time license SKU as the launch lever. Skip the GoHighLevel-killer pitch until Y2.

---

## 3. The revenue stack that fits the constraints

Six lines, ranked by how well they survive "no sync work, 10 hrs/week."

### Line 1 — Self-serve annual license (Pro tier focused)

Five SKUs, all sold via Stripe Payment Link from a single pricing page. **No "contact us" button anywhere.** License key emailed via webhook on `checkout.session.completed` — already supported by the Shop plugin. Customer never talks to you to buy.

| Tier | Price | Hero buyer | Why this SKU exists |
|---|---|---|---|
| Community | €0 | Hobbyist / evaluator under €5k AUG | Funnel; no support owed; protects under BSL 1.1 |
| **Starter** | **€499/year** | First profitable year of a small product | Anchor SKU; cheap enough to expense without approval |
| **Pro** | **€1,499/year** | Small SaaS / multi-product creator / small agency | **Hero SKU — every page nudges here** |
| Lifetime (launch only, capped 30) | **€1,999 one-time** | Hype lever, early adopters | Burst cash + early-adopter PR |
| Enterprise | €4,999/year | Agency reselling to N clients; mid-size SaaS | White-label rights; self-serve via Stripe link, no demo |

#### What's actually included in each tier

**Community — €0**
- Full source access under **BSL 1.1** (use, modify, self-host, study)
- All 12+ core plugins (CMS, Shop, Booking, Token, Subscriptions, Auth, etc.)
- Public Discord — peer-to-peer support, no SLA
- Public GitHub Discussions for roadmap input
- All security patches and minor-version updates
- **Permitted use:** evaluation, personal projects, organisations under **€5,000 annual usage / annual revenue (AUG)** per the BSL terms
- **NOT included:** commercial use above €5k AUG; founder support; white-label rights; plugin-marketplace publishing rights

**Starter — €499/year**
- Everything in Community, plus:
- **Commercial use up to €50,000 AUG**
- **One production deployment** (one customer-facing instance; staging/dev instances don't count)
- **Async email support, 48-hour response, business days** (no calls, no Slack DMs, no weekends)
- All point releases and feature releases for the licence year
- Discord member badge ("Starter")
- Cancel anytime; the licence stays valid for the paid year — no proration, no refund

**Pro — €1,499/year (hero)**
- Everything in Starter, plus:
- **Commercial use up to €500,000 AUG**
- **Up to 5 production deployments** — your own use OR client-facing deployments, your call
- **Early access** to new plugins (typically 2–4 weeks ahead of public release)
- **White-label rights** for end-customer-facing surfaces — your logo, your colours, your domain. (Internal/admin surfaces remain VBWD-branded; full white-label requires Enterprise.)
- **Async priority support: 24-hour response, business days, dedicated email queue**
- **Plugin-marketplace publishing rights** — list your own paid plugins, you keep 80%
- Roadmap voting weight (your votes count more in feature prioritisation)
- "Pro Partner" badge in Discord
- Cancel anytime; paid year stays valid

**Lifetime — €1,999 one-time (launch only, capped at 30 sales, 7-day window)**
- **Same scope as Pro** (commercial use up to €500k AUG, 5 deployments, priority support, white-label end-surface, plugin marketplace, early access)
- **Perpetual licence** — never renews, never expires
- **All future updates and new core plugins for life**
- "Founder" badge in Discord (visible forever)
- Goes on sale only during the launch week (Plan §4 weeks 9–10). Closes when 30 are sold OR after 7 days, whichever first. Counter on the page enforces it.
- Why this SKU: launch hype + early-adopter cash. Treat as a one-shot, not a permanent line.

**Enterprise — €4,999/year**
- Everything in Pro, plus:
- **Unlimited commercial use** (no AUG cap)
- **Unlimited production deployments** — for own use OR for unlimited end-customer deployments
- **Full white-label rights** including admin surfaces — your brand top to bottom
- **Reseller rights** — you may package VBWD into your own offering and resell it under your own brand
- **Async priority support: 12-hour response, business days, dedicated email queue, named contact** (named in the sense of an email handle, not a person on call)
- Listed in the public **Certified Partner directory** on `vbwd.io/partners`
- Co-marketing on launches (case studies, mutual blog posts) — async-only, no joint webinars
- **Plugin-marketplace publishing with no platform fee** (you keep 100% instead of 80%)
- **What's NOT included:** founder phone/Zoom calls; SLA on uptime (that's the customer's hosting problem); custom development hours (none — async-only rules out a time bank); on-site work; legal indemnification beyond standard EULA

> **Common pattern across all tiers:** SLA is on **response time to email**, not on uptime, not on resolution. You cannot promise uptime for software the customer hosts themselves. You can promise to read and reply to email within X hours.

**Year 1 target:** 80 paying customers (mix of all tiers, blended ARPC ~€700) = **€56,000**.

### Line 2 — Hosting-platform revenue share (passive, no ops)

You don't run hosting. The platforms below do, and pay you a cut for being listed.

| Platform | Model | Your cut | Y1 estimate |
|---|---|---|---|
| **Elest.io** | Managed hosting catalogue for self-hosted apps; ~$25–$200/mo per customer | ~10–20% rev-share to publishers | €2,000–€3,500 |
| **Cloudron App Store** | Cloudron monetises platform; customer runs VBWD on top free; **distribution-only, no rev-share** | €0 rev-share, but customer buys the VBWD licence directly | (counted in Line 1) |
| **Coolify / Easypanel / CapRover templates** | Free distribution, no rev-share | €0 | Distribution only |
| **Hetzner Cloud Marketplace snapshot** | Pre-configured image, customer self-deploys | €0 | Distribution only |

**What you do:** submit listings (Plan §4 weeks 5–6 below). Total effort across all platforms: ~10 hours one-time, then passive forever.

**What you do NOT do:** answer customer support tickets from Elest.io customers. Elest.io's ops team handles infrastructure. You only fix actual VBWD bugs (which you'd do anyway).

**Year 1 target:** **€2,500.** Compounds to €8–12k by Y2.

### Line 3 — Async priority-support add-on

Sold as an add-on to Starter and Pro tiers (Enterprise already includes priority).

- **€299/year** — async-only, 24h email response, dedicated queue, no calls
- Customers who try to escalate to a call get politely declined: "I'm async-only; if email isn't enough, please refund and use a different vendor"
- Listed alongside the licence at checkout as a "+€299/yr Priority Support" toggle

**Year 1 target:** ~10–15 customers buy the add-on = **~€3,500.**

### Line 4 — Plugin marketplace (other devs do the work)

VBWD already has a plugin architecture. Open a marketplace where third-party devs publish plugins, and you take **20% of every sale**.

**Why this works for the constraint:** you write zero plugin code, do zero customer support on the plugin (the plugin author does), and earn passively. It also attracts the kind of contributor who ships their own marketing.

**Year 1 target:** 6 paid third-party plugins live, average €10 ARPC × 200 sales = €12,000 GMV → **€2,400 your cut**. Small in Y1, compounding.

### Line 5 — Affiliate / payment-provider revenue share

Every VBWD instance configures payment gateways. Sign up for:

| Program | Per activation | Ongoing |
|---|---|---|
| Stripe Partners | ~$2 | 0.05–0.15% of GMV processed via your referral |
| PayPal Partner | $5–$10 referral | Negotiable |
| YooKassa partner | Negotiable | Negotiable (CIS-only) |
| Hetzner referral | €20/signup | One-off |
| Mailgun / Brevo | One-off | Small |
| Cloudron / Coolify / Easypanel app store | Listing fee revenue share | If they monetise |

**Year 1 target:** **€2,000 — €4,000.** Small but pure passive.

### Line 6 — Productized info products (paid content, no live support)

| Product | Price | Effort to make | Replays for years |
|---|---|---|---|
| "Build a vertical SaaS with VBWD" video course | €199 | 30 hrs once | ✓ |
| "VBWD Plugin Cookbook" PDF/code pack | €79 | 20 hrs once | ✓ |
| Pre-built vertical templates ("Coaching" / "Software store" / "Hotel" recipe) | €299 each | 10 hrs each | ✓ |
| Gumroad-migrator script (sold to Gumroad refugees) | €49 | 8 hrs | ✓ |

**Year 1 target:** 2 products live by month 6, 4 by month 12. Combined sales ~150 units × €120 average = **€18,000**.

### Year 1 totals (the realistic stack)

| Line | Y1 Brutto |
|---|---|
| Self-serve licences (Line 1) | €56,000 |
| Lifetime launch burst, one-time capped 30 (Line 1) | €15,000 |
| Hosting-platform revenue share (Line 2) | €2,500 |
| Async priority-support add-on (Line 3) | €3,500 |
| Plugin marketplace cut (Line 4) | €2,400 |
| Affiliate / cashback (Line 5) | €3,000 |
| Info products (Line 6) | €18,000 |
| **Total Y1** | **€100,400** |

**This stack hits €100k.** Lifetime burst is the swing factor. If the launch flops, Y1 lands ~€85k. If the launch hits HN front page or Product Hunt #1, Y1 can clear €125k. **The geo overlay in `02-geo-strategy.md` adds an incremental €15–30k on top of this base.**

### Year 2 trajectory (€300k cumulative)

Y2 inherits ~€42k in renewals (75% of Y1 paying customers renew) + ~€7k recurring add-on baseline + a much fatter top-of-funnel. Y2 is also the year a **white-label hosting partner** can plausibly be signed (revenue line: VBWD-branded hosting *operated by a partner*, you take 20–30% rev-share).

| Line | Y2 Brutto |
|---|---|
| New + renewal licences | €130,000 |
| Hosting-platform rev-share (Elest.io etc., compounding) | €8,000 |
| Async priority-support add-on (renewals + new) | €12,000 |
| Plugin marketplace cut (compounding) | €15,000 |
| Affiliate / cashback | €10,000 |
| Info products (compounding back-catalog) | €30,000 |
| White-label hosting partner rev-share (if signed end Y1) | €15,000 |
| **Total Y2** | **€220,000** |

**24-month cumulative (this plan only, no geo overlay): ~€320k.** Lands the second target. **With the geo overlay (`02-geo-strategy.md`): ~€405–430k cumulative.**

---

## 4. The 90-day execution plan

Working budget: **8–12 hrs/week, 1 burst weekend per month.**

The plan is sequenced so the **revenue-generating SKUs ship before the marketing**, because launching to no audience is wasted oxygen if there's nothing to buy.

### Weeks 1–2 — Productize what already exists (no new code)

Goal: turn the existing platform + decks into something a stranger can buy in 5 minutes.

- [ ] Pick **one** primary positioning for the launch. Recommend: **"Self-hosted Lemon Squeezy / Gumroad alternative"** (Bucket B). Why: clearest pain, biggest top-of-funnel, the math slide already exists, Gumroad refugee migration is a real ongoing wave.
- [ ] Pricing page live on `vbwd.io` (or whatever the production domain is). 4 SKUs (Community / Starter / Pro / Lifetime-launch). Stripe Payment Link per SKU. **No "contact us" button.**
- [ ] License-key delivery webhook tested end-to-end. Buy → email → key.
- [ ] Repurpose `softwarestore` deck into the landing page hero. The decks are already written.
- [ ] One-page comparison table: VBWD vs Gumroad vs Lemon Squeezy vs Paddle vs Polar.sh. Honest. Include where they win.
- [ ] Set up Plausible (or PostHog free tier) on the landing page. You need to see what converts.

**Output:** something a stranger can land on, understand, and pay for, with zero email exchange.

### Weeks 3–4 — Demo and docs (the "shop floor")

Goal: docs do the selling so you don't have to.

- [ ] Public demo instance permanently live at `demo.vbwd.io` (admin login pre-seeded, read-only-ish). Auto-resets daily via cron.
- [ ] One 5-minute YouTube video: "Migrate from Gumroad to your own VBWD store in 10 minutes." Screen recording, no face cam needed.
- [ ] Quickstart docs page: 4 commands from `git clone` to "first license key sold." Time-to-first-sale ≤ 30 minutes.
- [ ] Migration script: read a Gumroad CSV export, create products + customers + (optionally regenerate) license keys in VBWD. **This is the conversion lever for Bucket B** — it removes the migration tax.
- [ ] Set up a Discord server (or use GitHub Discussions). Single channel. Community moderates community. You read it once a day, max.

**Output:** the platform sells itself in async; community catches first-line questions.

### Weeks 5–6 — Distribution: get listed where buyers already shop

Goal: hand the hosting problem to platforms that already do it, while picking up free distribution.

- [ ] **Cloudron app store** submission. Cloudron has 50k+ self-hosters; they look there first. They run the customer's hosting; the customer buys the VBWD licence directly from you.
- [ ] **Coolify / Easypanel / CapRover templates** — submit a one-click deploy template for each. Same source repo, three packagings.
- [ ] **Elest.io app catalog** — reviewed catalog of self-hosted apps with **one-click managed deploy + ongoing managed hosting by Elest.io**. They take the customer's hosting fee; you get a small recurring rev-share. **This is the "managed hosting line" without you running ops.**
- [ ] **Hetzner Cloud Marketplace snapshot** — pre-configured image, customer self-deploys in 2 minutes.
- [ ] **Awesome-selfhosted** GitHub list — PR to add VBWD.

**Output:** 5+ external surfaces where buyers find VBWD without you marketing. None of them require you to run hosting.

### Weeks 7–8 — The Operator Cookbook (replaces "we host it for you")

Goal: a paid product that teaches customers to self-host competently, eliminating the demand for you to do it yourself.

- [ ] **"VBWD Operator Cookbook"** — paid €99 video + PDF: "How to self-host VBWD on a €15 Hetzner VPS, with backups, monitoring, SSL, updates, and recovery." 8–12 short videos (5 min each) + a checklist PDF + a sample `compose.yaml` and `.env`. Cover: provisioning, first-boot, Stripe wiring, daily backup script, restore drill, OS patching cadence, common failure modes.
- [ ] Sells from the same Stripe/landing page. Bundled into Pro and Enterprise tiers free; sold as a €99 add-on to Starter and Community users.
- [ ] **Why this exists:** when a non-technical buyer asks "do you offer hosting?" the answer is "no, but here's the €99 cookbook that walks you through doing it yourself in an afternoon — or pick Elest.io who'll do it managed for $50/mo." Both paths exist; you operate neither.
- [ ] Set up **AlternativeTo.net** listing — claim the page, position as "Gumroad alternative."
- [ ] Set up **Stripe Apps marketplace** submission: small Stripe app that surfaces VBWD subscription metrics in the Stripe dashboard (~24h of work, recoups via Stripe-customer distribution).

**Output:** the "do you host it for me?" question has two non-you answers — Elest.io for managed, Cookbook for DIY. You're never on the hook for ops.

### Weeks 9–10 — Launch

Goal: one big push that creates the lifetime-burst revenue and establishes the SEO inventory.

- [ ] **Product Hunt launch** — Tuesday morning EU time. Pre-line up 20 hunters via Twitter DMs (do this in week 8). Aim: top 5 of the day.
- [ ] **Show HN** the same week (Wednesday or Thursday). Title: "Show HN: Self-hosted Gumroad alternative – BSL 1.1, full source, $499/yr." Be ready to respond in comments for 4–6 hours; this is the one rule-violation-of-no-sync-work day.
- [ ] **r/selfhosted, r/SaaS, r/IndieHackers** posts — different angle each, no copy-paste.
- [ ] Lifetime tier (€1,999, capped 30 sales) live for 7 days only. Counter on the page. Creates urgency.
- [ ] DM 30 newsletter writers in the indie/dev/SaaS space the day before launch. One-paragraph pitch. ~3–5 will mention you.

**Output:** revenue spike from lifetime sales (target: 15+ sold = €30k brutto in one week), inbound from launch traffic (target: 1k+ landing visits, 30+ trial / community signups, 10+ paying conversions in 2 weeks).

### Weeks 11–12 — Plugin marketplace MVP + SEO inventory

Goal: open the plugin marketplace and seed the long-tail SEO that compounds for years.

- [ ] **Plugin marketplace MVP** — a `vbwd.io/plugins` page listing third-party plugins. MVP is a static page with Stripe Payment Links per plugin and a manifest format others can submit. Take 20% cut (0% for Enterprise publishers). No need for a full submission/review pipeline yet — start with manual approvals.
- [ ] **Affiliate program** — Rewardful or PartnerStack free tier. 20–30% recurring commission on referrals. Self-serve signup; no founder approval needed.
- [ ] **Two cornerstone SEO articles** (no fluff):
  - *"Gumroad fees calculator: when does self-hosting break even?"* (with a real interactive calculator embedded — JS, no backend)
  - *"How to export everything from Gumroad before they change ToS again"* (high-intent rescue search)
- [ ] **Comparison pages** — one per competitor: `vbwd.io/vs/gumroad`, `/vs/lemon-squeezy`, `/vs/paddle`, `/vs/polar`. Honest, including where they win. These rank for "[X] alternative" queries forever.
- [ ] **Reach out to one self-hosted-focused newsletter** (e.g., Self-Hosted podcast, Awesome-Selfhosted weekly) async — no call. Offer them a paid sponsorship or a guest article. €0–€500.

**Output:** plugin marketplace live (revenue line opens), 6+ pages of high-intent SEO inventory live, affiliate program available for any visitor to sign up.

### Weeks 13+ (the ongoing rhythm after the 90 days)

| Cadence | Activity | Time |
|---|---|---|
| Weekly | One SEO article OR one demo video (alternate) | 3 hrs |
| Weekly | Read Discord, GitHub issues, triage | 1 hr |
| Weekly | Ship one plugin improvement / fix | 4 hrs |
| Monthly | Submit to one new directory / marketplace | 2 hrs |
| Monthly | Launch a small new product (template, plugin, recipe) | 8 hrs |
| Quarterly | Re-launch (PH again, HN if angle changed, newsletter) | 1 weekend |

---

## 5. What you do NOT do (rules that protect the time budget)

These are non-negotiable for the part-time + no-contact constraint to hold.

1. **No sales calls. Ever.** Pricing page → Stripe → done. Anyone asking for a demo gets the demo URL + the YouTube video.
2. **No bespoke consulting** in Y1. The Owner Business Plan banks $27k from custom dev — it's poison for this plan because it requires meetings. If a customer offers €5k for a custom plugin, either (a) say no, or (b) quote €15k async-only with a 4-week SLA, and only do it on a burst weekend. Don't normalize it.
3. **No founder-led support.** Email autoresponder: "Community support: Discord. Priority support: €299/yr add-on, async, 48h SLA." Buy the priority tier or wait in Discord.
4. **No reseller / partner recruiting that requires meetings.** Affiliate program is fine (self-serve via Rewardful or similar). Active partner sales is Y2 work.
5. **No new vertical decks until the launch nicheconverts.** The repo has decks for `agency`, `core`, `doctor`, `hotel`, `softwarestore` — pick one (recommend `softwarestore`), launch with that, ignore the others until that one prints €5k+/month.
6. **No "we'll think about pricing later."** Pricing on the page from week 2. If you don't know the price, you don't have a product.
7. **No commits to the customer roadmap.** Public roadmap on GitHub Discussions, customer votes, you ship what you want when you want. "Enterprise feature requests" route to "Enterprise tier €4,999/yr or fork it."
8. **No own-brand managed hosting.** No "VBWD Cloud" tier you operate. When customers ask "do you host this?" the only answers are: (a) Elest.io for managed (you collect rev-share, they handle ops), (b) the €99 Operator Cookbook for DIY, (c) "no, but here's our partner directory" once a white-label hosting partner exists in Y2. **Never** spin up a VPS for a customer yourself. Once you do it once, you've set a precedent.
9. **No uptime SLAs.** SLAs in this plan are on **email response time**, not on system uptime. You can't promise uptime for software the customer hosts. Anyone demanding an uptime SLA gets routed to Elest.io.

---

## 6. Risks (honest list)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Launch flops, no PH/HN traction | Medium | -€30k from plan | Re-launch quarterly with new angle; Bucket B isn't the only positioning |
| You burn out on day-job + 12 hrs/week | High over 24mo | Plan dies | Hard cap weekly hours; the plan assumes 10–12, not 25 |
| Lago ships a UI | Medium | -10% conversion | Keep BSL 1.1 / non-AGPL as the headline differentiator for agencies |
| Stripe acquires Lemon Squeezy and changes terms (already happened) | Done | +tailwind | Already a tailwind for VBWD positioning |
| Loud demand for managed hosting from non-technical buyers | Medium | Lost conversions in Bucket B | Operator Cookbook (€99) handles DIY path; Elest.io listing handles managed path. Both exist by week 8. If conversion still suffers in month 6, accelerate the white-label hosting-partner search. |
| Elest.io / Cloudron change publisher terms or de-list VBWD | Low | -€2–8k/yr passive | Multi-platform listing reduces single-point-of-failure; revenue is small enough to absorb |
| EU VAT / OSS filing on your own info-product sales | Certain | Compliance load | Use Lemon Squeezy / Paddle as merchant-of-record for info products only (NOT for the license — that goes direct via Stripe). 5% MoR fee is worth not handling 27 VAT regimes for low-volume sales. |
| You get a customer who needs hand-holding and won't accept "Discord" | Certain | 2–10 hrs lost | Refund them. Cheaper than the time. |
| One key plugin (Stripe / payments) breaks on a Stripe API change while you're at the day job | Medium | Outage | Pin SDK versions; CI runs daily with latest SDKs and emails you on break |
| Day-job employer claims IP on VBWD | Depends on contract | Existential | **Check your employment contract before week 1.** If unclear, ask a lawyer. €200 of legal advice now is cheap. |

---

## 7. The decision points (review these at month 3, 6, 12)

**Month 3 review (after launch):**
- Did the launch produce ≥ €15k revenue (lifetime burst + first licences)? If yes, double down on Bucket B. If no, the positioning is wrong — pivot to one of the other decks (`agency`, `hotel`, `doctor`, `softwarestore`).
- Did Elest.io listing go live and attract ≥ 5 deploys? If no, the listing copy or the deploy template needs work.
- Discord size ≥ 100 members? If no, the launch didn't reach the right audience.
- Operator Cookbook sold ≥ 20 units? If no, either the price is wrong or the cookbook isn't being surfaced on the right pages.

**Month 6 review:**
- MRR equivalent (priority-support add-on + Elest.io rev-share + plugin marketplace + licence renewals coming due) ≥ €1,500? If no, the recurring base isn't compounding — adjust pricing or tiers.
- Cumulative revenue ≥ €40k? On track for €100k.
- Any plugin in the marketplace earning ≥ €500/mo? If no, the marketplace isn't taking off — recruit 2–3 specific plugin authors directly (async DM, no call) or shelve the line.
- Are ≥ 3 customers asking for managed hosting? If yes, **start the white-label hosting-partner search** (Path C from the chat) — sign one by end of Y1.

**Month 12 review:**
- Did you hit €100k? If yes, the model works — go to Y2 and add the agency channel (Bucket C) by hiring a part-time SDR or signing 1–2 reseller deals.
- If €60–€100k: model works but slower. Stay solo, repeat Y1 playbook with Y1's audience as launch fuel.
- If < €60k: the constraint (10 hrs/week + no sync) is incompatible with the target. Either increase hours, or accept a longer trajectory.

---

## 8. Immediate next actions (this week)

In order. Each line is a thing you can finish in one sitting.

1. **Decide the Y1 positioning** — Bucket B (Gumroad alternative) is the recommendation. Spend 1 hour disagreeing with the recommendation if you want; then commit.
2. **Check employment contract** for IP / moonlighting clauses.
3. **Buy/confirm the production domain** (`vbwd.io` or similar).
4. **Create the Stripe products** for Starter / Pro / Lifetime / Enterprise. Generate Payment Links.
5. **Wire the license-key webhook** end-to-end on a staging instance. Buy a test license with your own card. Verify the email arrives with a working key.
6. **Draft the landing page hero** from `decks/softwarestore/en/03-solution.html` + pricing from `06-pricing.html`. One scroll. No demo gating.
7. **Set the launch date** for week 9–10 in your calendar. Tell no one yet.

Anything not on this list waits.
