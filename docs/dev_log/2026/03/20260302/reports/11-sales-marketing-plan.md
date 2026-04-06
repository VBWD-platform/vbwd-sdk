# Sales & Marketing Plan: Solo Dev, vbwd, €10k/month
## Concrete answers to: plugin, pricing, hosting costs, prospecting with Claude, niches

**Date:** 2026-03-08

---

## 1. What "Build the Vertical Plugin This Weekend" Actually Means

A vertical plugin is a small Flask Blueprint + Vue component that makes vbwd
feel like it was built specifically for one industry.

**Concrete example — Vet Clinic Wellness Plans:**

Without plugin: vbwd is a generic subscription platform.
With plugin: vbwd becomes "VetMembership" — a wellness plan billing system for vet clinics.

What the plugin adds (2–3 evenings with Claude Code):

```
Backend (Flask Blueprint, ~200 lines):
  POST /api/v1/admin/cms/wellness/plans          create plan tier
  GET  /api/v1/admin/cms/wellness/plans          list plan tiers
  POST /api/v1/admin/cms/wellness/enrollments    enroll a pet
  GET  /api/v1/admin/cms/wellness/enrollments    list enrollments
  POST /api/v1/admin/cms/wellness/usage          log service used

Frontend (Vue component, ~150 lines):
  Admin page: /admin/wellness
    - Table of enrolled pets + plan tier + renewal date
    - "Log service" button (tracks what's been used this period)
    - "Generate membership card" (PDF via reportlab or WeasyPrint)
```

That is the entire plugin. The rest — billing, invoicing, user accounts,
email reminders, admin dashboard, the whole site — vbwd already does.

**The pitch becomes:** "We built a wellness plan system specifically for vet clinics.
You get member billing, renewal reminders, a client portal, and service tracking.
Setup takes 2 weeks. You own everything."

Claude Code workflow for a new vertical plugin:
1. Describe the domain to Claude: "Build a Flask plugin for vet wellness plans with these routes..."
2. Claude generates models, routes, service, tests (~1 hour of back-and-forth)
3. Describe the Vue admin page: "Build a dashboard showing enrolled pets..."
4. Claude generates the Vue component (~30 minutes)
5. You test, adjust, deploy

Time investment: 6–12 hours total per new vertical.
This means you can have 3 verticals ready in one weekend.

---

## 2. Real Hosting Costs — AWS, Azure, and Better Alternatives

### The problem with AWS/Azure for €99/month pricing

For a single small customer on AWS (dedicated infra):
```
EC2 t3.small (backend):          $17/mo
RDS db.t3.micro (PostgreSQL):    $15/mo
ElastiCache t3.micro (Redis):    $13/mo
ALB (Application Load Balancer): $18/mo
S3 + CloudFront:                 $3/mo
Route 53:                        $1/mo
─────────────────────────────────────
Total per customer:              $67/mo (~€62/mo)
```

At €99/month charge: margin = €37/month per customer. Acceptable but thin.
At €49/month charge: you lose money. Not viable.

Azure is similar: €55–70/month per customer on dedicated infra.

### The Real Answer: Use Hetzner for the first 50 customers

Hetzner (German datacenter, GDPR by default, excellent for EU market):

```
Per-customer dedicated VPS (all services on one machine):
  Hetzner CX22 (2 vCPU, 4GB RAM, 40GB SSD):    €4.51/mo
  Hetzner volume (20GB extra for uploads):       €1.00/mo
  Hetzner Floating IP (static IP):               €0.50/mo
  ─────────────────────────────────────────────────────
  Total per customer:                            €6.01/mo
```

One VPS per customer. vbwd + PostgreSQL + Redis + Nginx all on it.
For a vet clinic with 200 member subscriptions: completely sufficient.

**Pricing tiers that make sense:**

| Tier | Infrastructure | Your cost | Charge | Margin | Who buys it |
|---|---|---|---|---|---|
| Starter | Hetzner CX22 | €6/mo | €49/mo | 88% | Solopreneurs, small clubs |
| Standard | Hetzner CX32 (4 vCPU 8GB) | €12/mo | €89/mo | 87% | SMB, clinics, associations |
| Professional | Hetzner CCX23 (4 vCPU dedicated) | €28/mo | €149/mo | 81% | Larger SMB, compliance needs |
| EU Compliance | AWS/Azure EU region, dedicated | €65/mo | €249/mo | 74% | Healthcare, legal, fintech |
| Enterprise | AWS/Azure multi-AZ, SLA | €180/mo | €499/mo | 64% | Enterprise, government |

**Start with Hetzner Standard at €89/month.**
Margin is 87%. €10k net requires 70 customers × €89 = €6,230 MRR from hosting alone.
Add project installs and you cross €10k much faster.

**When to move to AWS/Azure:**
- Customer explicitly requires EU compliance documentation → charge €249/mo on Azure
- Customer requires SLA, uptime guarantee, multi-AZ → charge €499/mo on AWS
- Default for everyone else: Hetzner

**Automated provisioning (Claude Code builds this once, saves forever):**
```bash
# new_customer.sh <domain> <customer_name> <plan>
# Provisions Hetzner VPS, deploys vbwd, configures domain, sends welcome email
# Time: 8 minutes. Your involvement: 0 minutes after initial setup.
hetzner-cli server create --name "vbwd-${customer_name}" --type cx22 --image ubuntu-24.04
# ... ansible playbook runs, vbwd deployed, SSL configured, admin account created
```

---

## 3. Sales & Marketing Plan with Claude as the Engine

### The Funnel

```
Claude finds 500 prospects/week
    → Claude writes 500 personalized emails
        → You send 500 emails/week (automated)
            → 2–5% reply = 10–25 replies
                → You personally handle 10 conversations
                    → Close 1–2 customers/week
                        → €89–2,000 per close
```

Your time investment: 3–5 hours/week on conversations and closes.
Claude + automation handles everything else.

---

### Step 1: Prospect Finding with Claude Code

Build a prospecting script once. Claude writes it in an evening.

**Google Maps API prospecting (free tier: 200 calls/month, paid: $2/1000):**
```python
# prospect_finder.py
# Usage: python prospect_finder.py --niche "veterinary clinic" --city "Berlin" --radius 50km
# Output: prospects.csv with name, address, phone, website, google_rating, review_count

import googlemaps
import csv

gmaps = googlemaps.Client(key=GOOGLE_MAPS_API_KEY)

def find_prospects(niche: str, city: str, radius_km: int):
    results = []
    places = gmaps.places(query=f"{niche} in {city}", type="establishment")
    for place in places["results"]:
        details = gmaps.place(place["place_id"], fields=[
            "name", "formatted_address", "formatted_phone_number",
            "website", "rating", "user_ratings_total", "email"
        ])
        results.append({
            "name": details["result"].get("name"),
            "address": details["result"].get("formatted_address"),
            "phone": details["result"].get("formatted_phone_number"),
            "website": details["result"].get("website"),
            "rating": details["result"].get("rating"),
            "reviews": details["result"].get("user_ratings_total"),
        })
    return results
```

**LinkedIn Sales Navigator alternative (free, Claude-assisted):**
```
Prompt to Claude:
"Search LinkedIn for 'practice manager' OR 'office manager' at veterinary clinics
in Germany with 2–20 employees. Give me a list of 50 search queries I can run
manually on LinkedIn free tier to find these people, and the exact URL pattern
for each search."
```

**Apollo.io free tier (50 exports/month):**
- Search: "veterinary clinic" + "owner" OR "manager" + Germany/Austria/Switzerland
- Export email + LinkedIn URL
- Feed into Claude for personalization

**Hunter.io (free: 25 searches/month):**
- Find email patterns for any domain (e.g., vet clinic website → find manager email)

---

### Step 2: Claude Writes Personalized Emails

Not mail-merge. Actual personalization based on what Claude finds about each prospect.

**The research + write prompt:**
```
You are a sales assistant. I am selling a membership billing system for vet clinics.

For each prospect below, write a personalized cold email (max 100 words) that:
1. References something specific about their clinic (location, specialty, review count, any detail from their website)
2. States the problem we solve in one sentence
3. Makes a specific low-commitment offer (15-minute call OR live demo link)
4. Sounds like it was written by a person, not a robot

Clinic: Tierarztpraxis Müller, Munich, 4.8★ 127 reviews, website mentions "Hunde und Katzen Spezialisten"
From: [your name]

Write the email.
```

**Output example:**
> Subject: Mitgliedschaftspläne für Tierarztpraxen — kurze Frage
>
> Hallo Frau/Herr Müller,
>
> Ihre Praxis hat 127 Bewertungen — offensichtlich haben Sie eine treue Stammkundschaft.
> Viele Praxen in Ihrer Situation verlieren Geld, weil Wellness-Abonnements noch per
> Überweisung und Excel verwaltet werden.
>
> Ich habe ein System gebaut, das das automatisiert — Abrechnung, Erinnerungen,
> Kundenportal. Setup in 2 Wochen, keine laufenden Plattformgebühren.
>
> Darf ich Ihnen 15 Minuten zeigen, wie es für Ihre Praxis aussehen würde?
>
> [Ihr Name]

**Scale this:** Claude processes 100 prospects → 100 personalized emails in 20 minutes.
You review, approve, send.

---

### Step 3: Sending Infrastructure (Zero to Low Cost)

**For 500 emails/week:**
- **Instantly.ai** ($37/month) — cold email sending, auto-warmup, inbox rotation, tracking
- **Lemlist** ($59/month) — same but with image personalization
- **Free alternative:** Google Workspace ($6/month) + manually scheduled send

**Domain setup for cold email (critical — use a separate domain):**
- Buy a variant domain: `yourbrand-wellness.de` or `vetmembership.de`
- Configure SPF, DKIM, DMARC (Claude writes the DNS records)
- Warm up for 2 weeks before sending (Instantly handles this automatically)

**Weekly workflow (3 hours total):**
```
Monday (30 min):
  - Run prospect_finder.py for this week's batch
  - Export to CSV

Tuesday (45 min):
  - Feed CSV to Claude → get 100 personalized emails
  - Review + approve batch
  - Schedule in Instantly

Wednesday–Friday:
  - Replies come in
  - Claude drafts responses (you review + send)
  - Book calls for the following week

Weekend (1 hour):
  - Take calls / demos booked this week
  - Close or follow up
```

---

### Step 4: The Demo That Closes

Never pitch from slides. Always show a live running instance.

**Demo infrastructure (one-time setup, €6/month):**
- One Hetzner VPS
- vbwd deployed with the vertical plugin
- Seeded with realistic fake data (Claude generates this)
- Custom domain: `demo.vetmembership.de`

During a call:
> "Let me show you what your dashboard would look like. Here's a live system running
> right now. This is the wellness plan dashboard — see, these are your enrolled pets,
> renewal dates, what services they've used this month..."

A live demo on a call closes 3× better than any pitch.
Build one demo per vertical. Reuse it for every prospect in that vertical.

---

### Step 5: Follow-Up Sequences (Claude Writes These Once)

Most sales close on follow-up 3–5, not the first email.

**5-email sequence (Claude writes all of them in one session):**
```
Day 0:  Initial personalized email
Day 3:  Short follow-up ("Did you get a chance to see my note?")
Day 7:  Value-add ("Here's a 2-minute video showing exactly how the billing works")
Day 14: Social proof ("One of our clients — a clinic in Hamburg — reduced billing time by 4 hours/week")
Day 21: Break-up email ("I'll stop reaching out after this — but wanted to leave the door open")
```

Load all 5 into Instantly as a sequence. Runs automatically.
Your only job: respond to the 2–5% who reply.

---

## 4. The 10 Best Niches — Ranked for a Solo Dev

Ranked by: speed to first sale × willingness to pay × technical simplicity × Claude Code buildability

**Tier A — Start Here (fastest to first €)**

**#1 — Vet Clinic Wellness Plans (EU/DACH)**
- Problem: practices run wellness plans on Excel and bank transfers
- Willingness to pay: HIGH (€1,500–3,000 setup + €89/mo, clinic spends €300k/year on overhead)
- Plugin complexity: LOW (plan tiers, pet enrollment, service logging, PDF card)
- Prospect finding: Google Maps "Tierarztpraxis" → find 500 clinics in Germany in 1 hour
- Sales cycle: 1–3 weeks
- Competition: ZERO self-hostable competitors

**#2 — WordPress Membership Plugin Installs for EU Publishers**
- Problem: MemberPress/WooCommerce Subscriptions don't support local EU payments; data on US servers
- Willingness to pay: MEDIUM (€800–1,500 setup + €79/mo)
- Plugin complexity: NONE (vbwd + WP bridge = the product)
- Prospect finding: search "WordPress membership site" + country on Google, LinkedIn
- Sales cycle: 1–2 weeks
- Competition: MemberPress (but expensive, no local payments)

**#3 — Dental In-House Membership Plans (EU)**
- Same dynamic as vet. Dentists charge €25–60/month for an uninsured patient plan.
- They currently use paper forms and manual bank debits.
- Willingness to pay: HIGH (dental practice revenue: €400k–1.5M/year)
- Plugin complexity: LOW (similar to vet plugin, different domain terminology)
- Competition: ZERO in EU self-hosted space

**#4 — Amateur Sports League Subscription Management**
- Football clubs, padel clubs, volleyball associations charging €10–30/month dues
- Prospect finding: search national sports federation directories (all public)
- Willingness to pay: MEDIUM (€500–1,200 setup + €49/mo)
- Plugin complexity: LOW (member roster, dues tracking, match schedule)
- Volume opportunity: thousands of clubs per country

**Tier B — Second Wave (slightly longer sales cycle, higher ACV)**

**#5 — Local ISP / WISP Billing**
- 2,000+ WISPs in the US, hundreds in EU
- Current billing software: $300–800/month (Powercode, VISP)
- Your price: €299–499/month (still cheaper, self-hosted, GDPR)
- Plugin complexity: MEDIUM (subscriber management, data plan quotas, invoicing)
- Prospect finding: WISP forum directories, WISPA.org member list
- ACV: €3,588–5,988/year per customer — one WISP = one month of salary

**#6 — Professional Association Membership (EU/DACH)**
- Regional engineering chapters, medical societies, bar associations
- Annual dues €50–300/member, 100–1,000 members
- Willingness to pay: MEDIUM-HIGH (they currently use Wild Apricot at €600+/year)
- Plugin complexity: LOW-MEDIUM (member directory, dues billing, document library)
- Sales cycle: SLOW (committee decisions) — get one, get referrals to sister chapters

**#7 — Ukrainian/Eastern European Developer SaaS Tools**
- You understand the market, speak the language, know the payment problem
- Developers who cannot use Stripe need exactly what vbwd offers
- Prospect finding: DOU.ua, Djinni.co, Ukrainian dev Facebook/Telegram groups
- Willingness to pay: MEDIUM (developers but lower income than EU)
- Unique angle: you are the solution AND the community member

**#8 — Makerspace / Coworking Membership Billing**
- Subscription access to equipment (laser cutter, 3D printer, etc.)
- Currently: manual invoices or Eventbrite hacks
- Willingness to pay: MEDIUM (€800–1,500 setup + €69/mo)
- Prospect finding: makerspace directories (hackspace.org, fablabs.io — all public lists)
- Plugin complexity: LOW-MEDIUM (equipment booking credits, membership tiers)

**Tier C — High Value, Longer Cycle**

**#9 — EU Compliance SaaS (NIS2/GDPR for mid-size companies)**
- Mid-size EU companies needing self-hosted subscription management for compliance
- Sales cycle: 6–12 weeks (legal/IT procurement)
- ACV: €5,000–15,000/year
- Requires: compliance documentation package, SLA, support contract
- Best approached via IT consultancy partners (they bring deals, you implement)

**#10 — Subscription Journalism / Niche Media (EU language markets)**
- Independent news sites in Czech, Polish, Hungarian, Romanian, Ukrainian
- Substack/Patreon don't support local payments well
- Willingness to pay: MEDIUM (€800–1,500 setup + €79/mo)
- Prospect finding: look for "podpořte nás" / "підтримайте нас" on news sites
  (these are "support us" calls to action = they want subscription billing)

---

## 5. Revenue Model Reality Check

**Why €89/month is the right default price (not €49, not €199):**

€49/month:
- Feels safe to pitch
- Requires 200+ customers for €10k net
- Attracts price-sensitive customers who churn
- Your support burden: HIGH (price-sensitive = high-maintenance)
- Verdict: too low

€89/month:
- Still cheaper than any alternative (Wild Apricot: €600/year = €50/mo but limited)
- Requires 70 customers for €6,230 MRR (achievable)
- Customer perception: "professional tool, not a toy"
- Verdict: correct starting price

€199/month:
- Requires proof, case studies, compliance documentation
- Appropriate AFTER you have 20+ customers and testimonials
- Good for WISP, healthcare-adjacent, legal
- Verdict: correct SECOND pricing tier, wrong starting price

**The setup fee is not optional:**
- €1,500–2,500 setup fee does three things:
  1. Filters out time-wasters (someone who pays €1,500 upfront is committed)
  2. Covers your 8–15 hours of configuration work at a reasonable rate
  3. Creates psychological investment ("I paid for this, I'll actually use it")
- Never do free setup "to get the customer." It attracts the wrong customer.

---

## Questions to Identify Your Niche

*(Asked one by one in the next message)*

These answers will determine which of the 10 niches above fits you specifically:

1. What country are you based in, and what language(s) do you speak natively?
2. Do you have any professional contacts or personal connections outside software — in any industry?
3. Have you ever built anything (even freelance) for a specific non-tech industry?
4. How many hours per week realistically can you dedicate to this?
5. Are you comfortable with sales calls / video demos, or does that feel like a hard barrier?
6. What payment methods are standard where you live (Stripe available? Local gateway needed?)
7. Do you have any existing audience — newsletter, GitHub followers, LinkedIn connections, community membership?

The answers collapse the 10 niches to 1–2. That is the starting point.
