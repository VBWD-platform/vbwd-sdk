# vbwd Partner & Agency Community: Build a Reseller Network

**Date:** 2026-03-08
**Type:** Strategic Business Plan
**Audience:** Solo developer / founder considering channel partner strategy

---

## The Core Idea

Instead of selling vbwd installations yourself to 70–100 customers, you enable **20–30 digital agencies and freelancers** to sell it to *their* clients. Each partner sells 5–10 installations per year. You collect a license fee per installation or a monthly platform fee per active deployment. You work once to recruit and enable a partner; that partner works continuously to sell.

This is the **channel model** — how Microsoft, Shopware, and WooCommerce actually scaled. You are the product company. They are the salesforce.

---

## Why Agencies Would Adopt vbwd

Digital and integration agencies face a recurring cost that most clients don't see: every project that needs subscription billing requires either:

1. **Custom billing development** (40–80h per project, expensive, error-prone)
2. **Recommending Stripe Billing / Chargebee** (client data on US servers, GDPR issues, ongoing SaaS cost, agency carries integration debt)
3. **Recommending WooCommerce Subscriptions** (PHP plugin chaos, version conflicts, security patches forever)

vbwd solves all three:
- Pre-built backend they can install in 30 minutes (Ansible playbook or Docker Compose)
- Self-hosted, GDPR-clean, client data sovereignty
- Plugin architecture — the agency writes one domain plugin per client type, reuses it across every client in that niche

**The economic argument for an agency:** writing a vet wellness subscription system from scratch costs 80–120h at €80–120/h = €6,400–14,400. Using vbwd as the base, the agency writes a 10–20h plugin and charges the client the same €6,400–14,400. The rest is margin.

---

## Partner Economics Model

### What a Partner Charges Their Client

| Service | Agency Price | Agency Cost (vbwd license + infra) | Agency Margin |
|---|---|---|---|
| Initial setup + domain plugin | €2,500–6,000 | €300–500 (your license) + 20–40h dev | 70–85% |
| Monthly managed hosting | €99–299/month | €40–60/month (VPS + your platform fee) | 50–70% |
| Annual maintenance + updates | €500–1,200/year | €0 if they own the code | 90%+ |

A single client with a setup + managed hosting generates an agency:
- **Year 1:** €5,500–9,000 (setup + 12 months hosting)
- **Year 2+:** €1,200–3,600/year (hosting alone)

For the agency, 10 vbwd clients on managed hosting = €1,200–3,600/month pure recurring after month 12 of operations. That is a compelling reason to push vbwd over alternatives.

### What You Earn from Each Partner

**License Model Option A — Per-Installation Fee:**
- Partner pays you €300–500 per deployment (one-time)
- 20 partners × 5 installs/year = 100 installs/year × €400 average = **€40,000/year**

**License Model Option B — Monthly Platform Fee per Active Deployment:**
- Partner pays you €20–40/month per active client deployment (your "partner wholesale" rate)
- 20 partners × 8 active deployments each = 160 active deployments × €30/month = **€4,800/month = €57,600/year**

**License Model Option C — Hybrid (recommended):**
- One-time onboarding fee per partner: €500–1,000 (pays for your setup time)
- Monthly per-deployment fee: €25/month (low friction, scales automatically)
- Starter tier: first 3 deployments free (removes adoption risk)

At 20 partners with average 8 deployments each:
- **Platform fee revenue:** 20 × 8 × €25 = **€4,000/month**
- **Onboarding fees:** 20 × €750 = €15,000 (first-year, one-time)
- **Combined year 1 gross:** €63,000
- **Combined year 2 gross (no new partners, growth to 12 deployments each):** 20 × 12 × €25 × 12 = **€72,000/year**

This is *in addition to* direct sales from your own installations. Partners handle the sales motion; you handle the platform.

---

## Partner Community Structure

### Tier 1 — Certified Integrator (Entry)
- Completed vbwd developer training (5-hour online course you record once with Claude's help)
- Built one test deployment on their own infrastructure
- Access to: partner portal, private documentation, partner Slack channel, 3 free deployments
- Obligation: 2+ client installations within 6 months or tier revoked
- Your monthly fee: **€0** (first 3 deployments free — no risk to join)

### Tier 2 — Silver Partner (Active)
- 4+ active client deployments
- Access to: co-marketing materials, priority support, your roadmap input, partner directory listing
- Platform fee: **€25/deployment/month** (starting from deployment #4 or at tier upgrade)
- Revenue share on referred licenses you sell directly: **15%**

### Tier 3 — Gold Partner (Growth)
- 15+ active client deployments
- Access to: white-label branding option (their agency name on vbwd UI), co-sales support, quarterly call with you, early access to new plugins
- Platform fee: **€20/deployment/month** (volume discount)
- Revenue share: **20%** on referred licenses

### Tier 4 — Platinum Partner (Strategic)
- 40+ active client deployments
- Built and published at least one plugin to the vbwd plugin registry
- Access to: co-development budget (you fund their plugin if it serves the marketplace), exclusive vertical rights in their country
- Platform fee: **€15/deployment/month**
- Revenue share: **25%**

---

## Who to Recruit: The Right Agency Profile

Not every agency is a good partner. The right profile:

**High-fit agencies:**
- 3–15 person digital agencies in the EU (Germany, Austria, Netherlands, Poland, Czech, Ukraine)
- Specialize in: WordPress/Drupal development, e-commerce (Shopware/OXID/Magento), or custom SaaS development
- Serve clients with recurring subscription needs: fitness studios, professional associations, niche publishers, healthcare
- Use Docker and Linux hosting — they have DevOps capability
- Have GDPR/data-sovereignty conversations with clients regularly

**Low-fit agencies (avoid):**
- Design-only agencies (no backend capability)
- Shopify-only agencies (wrong tech stack)
- US-based agencies (GDPR angle irrelevant; Stripe is easy there)
- Very large agencies (100+ people) — procurement is too slow for your stage

**The ideal first partner:** a 5–10 person agency in Germany, Poland, or Czech Republic that builds custom web applications for mid-market clients and is actively looking for a self-hosted subscription infrastructure to stop reinventing billing from scratch.

---

## Marketing Plan to Recruit Partners

### Phase 1 — First 5 Partners (Months 1–3): Direct Outreach, No Marketing Budget

**Step 1: Build the Partner Case Study.**
Before recruiting, you need one fully documented case study:
- "Agency X built a vet wellness subscription platform for Clinic Y in 3 weeks using vbwd."
- Document: hours spent, client price charged, recurring revenue earned, client outcome.
- One honest case study is worth more than any agency pitch deck.

If you have no agency partner yet, document your own first direct installation as the case study. You are the first integrator.

**Step 2: Find Agencies at the Right Moment.**
Agencies are most receptive when they are actively solving the problem you solve. Search signals:

- Upwork / Malt: Search for agencies posting or applying to jobs that mention "subscription billing", "membership system", "recurring payments", "WooCommerce Subscriptions"
- LinkedIn: `(digital agency OR web agency) AND (subscription OR membership OR Shopware OR OXID) AND (Germany OR Poland OR Netherlands)`
- GitHub: Look for agencies with repos containing WooCommerce Subscriptions, MemberPress, or Stripe Billing integrations — they have the problem

**Step 3: The Agency Outreach Message.**
Keep it to 5 sentences. Do not pitch vbwd. Pitch the problem you know they have:

> Subject: Subscription billing for your client projects (without WooCommerce Subscriptions)
>
> You know the pattern: a client needs subscription billing, you either build it custom or strap WooCommerce Subscriptions on top and debug it for months. I built an open-source self-hosted alternative that gives agencies a clean Flask + Vue subscription platform they can deploy per client in under an hour. GDPR-clean, no per-transaction fees, fully white-labelable. I'm looking for 5 agencies to be founding partners — zero cost to try, permanent volume discount if you stay. 20-minute demo?

Send 30 targeted emails. Expect 3–5 positive responses. One of those becomes your first partner.

**Step 4: Run a Free Pilot.**
First 3 agencies get Partner Tier 1 at zero cost. The only ask: one video call after their first client deployment to record their honest feedback. That feedback becomes:
- Your partner testimonials
- The changelog for rough edges you didn't see
- Case studies for the next wave of recruitment

---

### Phase 2 — 5 to 20 Partners (Months 4–12): Community Building

**Partner Portal (built with vbwd CMS + membership plugin).**
The partner portal is itself a vbwd deployment — the best possible demonstration of the product:
- Private documentation (plugin development guide, Ansible playbooks, client onboarding templates)
- Partner directory (public page where clients can find certified installers)
- Forum / discussion board (Discourse plugin or simple vbwd-backed forum)
- Partner dashboard showing their active deployments and revenue

Building this costs you 2–3 weekends. Every partner who logs in sees a live vbwd deployment.

**Conference Presence (zero-cost version).**
You do not need a booth. Attend (as a regular attendee) or participate virtually in:
- **WordCamp EU** — WordPress community, plugin developers, agencies
- **Shopware Community Days** — DACH agency ecosystem
- **WISPAPALOOZA** — for ISP billing vertical
- **Web Summer Camp** (Croatia) — Central/Eastern EU web agencies
- **MicroConf** — bootstrapped SaaS operators (not agencies, but potential evangelists)

At each: give a 5-minute lightning talk or post in the community forum about the specific problem you solve. Cost: your time + travel if you attend in person. Return: 2–5 warm partner leads per event.

**Content Strategy (Claude-assisted, 2h/week).**
One post per week targeting agency decision-makers:
- "How we built a vet wellness subscription system in 3 weeks instead of 3 months" (dev.to, Medium, LinkedIn)
- "Why German agencies should stop recommending Chargebee for GDPR-sensitive clients" (LinkedIn, Shopware forum)
- "Building a plugin for vbwd: a step-by-step guide" (GitHub, dev.to)

Claude writes the draft, you edit for voice and accuracy. Each post is a recruiment funnel for the next agency partner.

**Plugin Registry (Month 6+).**
Launch a simple public plugin registry (vbwd-backed, naturally):
- Partners publish their plugins (can be paid plugins sold through the registry)
- Registry builds ecosystem proof ("7 agencies have published 14 plugins")
- Agency developers browse it when evaluating adoption — seeing other agencies' work normalizes adoption

---

### Phase 3 — 20+ Partners (Month 12+): Partner-Led Growth

At 20+ active partners with 8+ deployments each, the network effect kicks in:
- Partners refer other agencies ("my peer at this other agency asked me how I solved subscription billing — I sent them to you")
- Client word-of-mouth: "Our digital agency built this on vbwd — you should ask yours to do the same"
- Plugin ecosystem: partners who built plugins for their own clients publish them; new partners see a richer ecosystem and join faster

You invest in:
- Annual partner summit (virtual, free): 2-hour Zoom call, roadmap preview, best case study awards, partner networking
- Partner newsletter (monthly, Claude-assisted): technical updates, new plugin announcements, sales tips
- Dedicated partner Slack or Discord: real-time support, plugin collaboration, deal registration

---

## Cashflow Projection: Partner Model

Assumptions:
- 3 months to first partner cohort (5 partners)
- Partners average 4 deployments at month 6, 8 at month 12, 12 at month 18
- Platform fee: €25/deployment/month starting from deployment #4
- Onboarding fee: €750 per partner (collected at Tier 2 upgrade, after pilot period)
- Churn: 10%/year on deployments (conservative)
- Direct sales continue in parallel (not shown below — this is partner channel only)

| Month | Partners | Avg Deployments | Billable Deployments* | Monthly Revenue | Cumulative Revenue |
|---|---|---|---|---|---|
| 3 | 5 | 2 | 0 (pilot) | €0 | €0 |
| 6 | 10 | 4 | 20 (above free tier) | €500 + €7,500 onboarding | €8,000 |
| 9 | 15 | 6 | 60 | €1,500 | €20,500 |
| 12 | 20 | 8 | 100 | €2,500 + €3,750 onboarding | €48,000 |
| 15 | 22 | 10 | 154 | €3,850 | €63,550 |
| 18 | 25 | 12 | 225 | €5,625 | €90,925 |

*Billable = total deployments minus 3 free per partner

**By month 18: €5,625/month recurring from the partner channel alone**, with zero sales effort on your side for those deployments. This stacks directly on top of your direct-sale MRR.

Combined projection at month 18:
- Direct sales MRR (from report 10): €10,000
- Partner channel MRR: €5,625
- **Total gross MRR: €15,625**
- Infrastructure cost: ~€0 (partners host their own clients)
- Net after 30% tax: **~€10,940/month**

The partner channel is a force multiplier: it reaches customers you would never reach directly (German DACH agencies, Polish WordPress shops, Dutch Shopware specialists), in languages you may not speak, without you doing sales.

---

## What You Must Build to Enable Partners

### 1. Developer Documentation (Month 1–2)
One clear plugin development guide. The CMS plugin is already the reference implementation. Document it:
- "How to write a vbwd plugin: step-by-step guide using the CMS plugin as example"
- Cover: models, services, repositories, routes, Vue admin component, Vue user plugin, Alembic migration, tests
- Host it on the vbwd docs site (a vbwd CMS deployment, naturally)
- Time estimate: 2 weekends with Claude

### 2. One-Click Partner Deployment Script (Month 1–2)
An Ansible playbook or shell script that:
- Provisions a VPS (or accepts an existing one)
- Installs Docker + Docker Compose
- Clones vbwd
- Configures domain, SSL, environment variables
- Runs migrations + populates demo data
- Opens the admin panel at the domain

Partners need to be able to demo vbwd to their client in under 1 hour from first contact. If setup takes a full day, partners will not adopt. Time estimate: 1 weekend.

### 3. White-Label Theme System (Month 3–4)
Allow partners to configure:
- Logo (admin + user app)
- Primary/secondary colors
- Platform name (displayed in UI)

This is critical for agencies who sell under their own brand ("Powered by ClientPortal Pro" not "Powered by vbwd"). The CMS plugin's style system already handles public-facing branding; admin branding is a 1–2 day frontend addition.

### 4. Partner Portal (Month 4–6)
A vbwd deployment with:
- Private plugin documentation
- Partner dashboard (active deployments, links, status)
- Plugin registry (submit/browse plugins)
- Partner directory (public agency listing with specializations)
- Forum or Discord integration

Build cost: 2–3 weekends. Dogfood your own product.

### 5. Partner Training Course (Month 2–3)
A recorded course (Loom or similar), ~5 hours:
- Session 1 (1h): vbwd architecture overview, plugin system, CMS plugin walkthrough
- Session 2 (2h): Building your first domain plugin (live coding a simple plugin from scratch)
- Session 3 (1h): Deployment, infrastructure, client handoff
- Session 4 (1h): Pricing, selling to clients, common objections

Record it once. Share via partner portal. This replaces dozens of 1:1 onboarding calls.

---

## The Freelancer Angle

Individual freelancers (not agencies) are a different and faster channel:
- Lower barrier to join (one person, no procurement)
- Smaller client base per freelancer but faster to activate
- Strong in Eastern Europe, LATAM, Southeast Asia where Stripe is restricted — exactly where YooKassa and other local gateway plugins shine

For freelancers: offer the same Tier 1 (free for first 3 deployments), but pitch differently:
- "Add a subscription billing product to your freelance services without building billing from scratch"
- "Charge clients €2,000 for a membership system that takes you 20 hours to configure instead of 200 hours to build"

Recruit freelancers via:
- Upwork / Malt / Toptal profiles (message developers who list 'subscription billing' or 'membership systems' in their services)
- DOU.ua and local developer communities (Ukraine, Poland, Romania)
- GitHub — developers who forked or starred subscription-related OSS projects

---

## Risk Analysis

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Partners join but never ship a client | Medium | Low revenue | Tier 1 is free; enforce upgrade or remove after 6 months. Low cost to you. |
| Partners go silent after first deployment | Medium | Churn | Monthly partner newsletter + Slack keeps engagement; semi-annual partner call |
| Agency builds competing product using CC0 license | Low | High | CC0 allows this legally; mitigation is network effects and ecosystem. No license can stop a determined fork. Build the community they can't replicate. |
| Stripe/PayPal changes pricing or terms | Low | Medium | YooKassa + local gateways provide backup; platform is gateway-agnostic by design |
| Insufficient partners to hit revenue target | Medium | Revenue delay | Direct sales cover gap; partner program de-risks concentration on one channel |
| Partner charges clients poorly, hurts reputation | Low | Medium | Partner certification requirements; minimum pricing guidelines (optional but recommended) |

---

## Action Plan: Next 90 Days

**Month 1:**
- [ ] Write the plugin development guide (Claude-assisted: 2 evenings)
- [ ] Build the one-click partner deployment script (1 weekend)
- [ ] Identify 30 target agencies using LinkedIn and GitHub search
- [ ] Send 30 cold emails with the 5-sentence pitch above

**Month 2:**
- [ ] First 3–5 partner responses → schedule demos
- [ ] Onboard first 2–3 pilot partners (free)
- [ ] Record Session 1 of partner training (1h, Loom)
- [ ] Build the partner portal MVP (1 weekend: CMS + membership auth + basic docs)

**Month 3:**
- [ ] First partner deployments (their client installations)
- [ ] Debrief call with each pilot partner (record feedback)
- [ ] Publish first case study ("Agency X built Y in Z weeks")
- [ ] Begin Tier 2 upgrades (first paid partners: €25/deployment/month above free tier)
- [ ] Record Sessions 2–4 of partner training

**By end of Month 3:**
- 5 active partners
- 2–3 paying at Tier 2
- €500–1,000/month partner channel revenue
- Case study published, partner portal live, training course complete

Everything from Month 4 onward is leveraging these assets. Every new partner self-onboards via training, portal, and docs — without your time per partner.

---

## The One-Sentence Partner Pitch

> "vbwd is the self-hosted subscription platform that lets your agency add recurring billing to any client project in days instead of months — with Stripe, PayPal, and YooKassa bundled, a CMS, and full GDPR data sovereignty."

That sentence answers: what it does, how fast, what's included, and why EU agencies specifically should care.

---

## Summary

The partner model is not an alternative to direct sales — it is a parallel channel that:
1. Reaches customers you cannot reach yourself
2. Generates recurring platform revenue without your ongoing sales effort
3. Builds an ecosystem (plugins, case studies, community) that increases vbwd's defensibility
4. Enables the €10k/month target faster and with less personal selling

The investment is 3–4 months of part-time infrastructure work (docs, deployment script, portal, training). After that, the channel runs largely on its own with 2h/week of maintenance.

The math is clear: 25 partners × 12 deployments × €25/month = **€7,500/month from zero direct sales effort on those deployments**. Stack that on €8,000/month from direct sales at month 18, and you cross €15,000/month gross — well above the €10,000/month net target even after taxes and infrastructure.
