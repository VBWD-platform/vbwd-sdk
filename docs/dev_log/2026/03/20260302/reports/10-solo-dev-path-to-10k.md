# Path to €10,000/month Net: Solo Developer with Claude Code, Zero Capital

**Date:** 2026-03-08
**Type:** Personal Strategic Memo
**Constraint:** Limited free time. No employees. No investors. No enterprise budget.

---

## The Honest Math First

€10,000/month net after taxes (assume ~30% effective rate in EU) = ~€14,300/month gross.

Three ways to get there with vbwd:

| Model | Price point | Customers needed | Realistic timeline |
|---|---|---|---|
| Managed hosting (SaaS) | €99/mo | 145 | 18–30 months |
| Managed hosting (SaaS) | €199/mo | 72 | 12–24 months |
| Agency installs (one-time) | €2,500/install | 6/month ongoing | 6–10 months to pipeline |
| Hybrid (hosting + agency) | mixed | ~40 hosted + 2 installs/mo | 12–18 months |

The hybrid model is the fastest and most resilient path for a solo developer.

---

## The One Rule That Makes This Possible

**You are not selling vbwd. You are selling the outcome vbwd produces.**

Nobody buys "a self-hosted Flask subscription platform." They buy:
- "A membership billing system for my vet clinic" (€1,500–2,500 setup + €99/mo hosting)
- "A subscription paywall for my news site" (€800–1,500 setup + €79/mo hosting)
- "A WooCommerce subscription backend that works in Ukraine" (€1,200 setup + €99/mo)

Claude Code builds the vertical-specific plugin in hours. You charge for days.

---

## Phase 1 — First €1,000/month (Months 1–3)
*Goal: validate the model, get first paying customers, zero investment*

**Week 1–2: Pick one niche from report 07 or 08.**
Do not generalize yet. Pick the niche where you have the shortest path to a customer.
Best candidates for a solo dev with limited time:

- **Vet/dental wellness subscription** — clinics have money, no tech team, desperate for a solution, €1,500 setup is nothing to a practice
- **WordPress membership plugin installs** — WordPress developers are already looking for this, you can find them on Upwork/Malt in days
- **Ukrainian/Eastern European developer tools** — your own community, trust is instant, payment friction is the exact problem you've solved

**Week 3–4: Build the vertical plugin with Claude Code.**
One plugin for one niche. Not a general platform. Specific. Takes 2–5 days of evenings.
Example: "VetMembership" = vbwd + a plugin that tracks wellness plan credits, generates PDF membership cards, sends renewal reminders.

**Month 2: Land 2–3 paying customers.**
Not through a website. Through direct outreach.
- Post in 3 Facebook groups for veterinary practice managers
- Send 20 cold emails to dental practices in your city
- Post on relevant subreddits (r/smallbusiness, r/dentistry, r/veterinary)

Message template:
> "I built a membership plan billing system for [vet/dental] practices. No monthly platform fees, you own your data, works with [local payment method]. I'm looking for 3 pilot customers at €500 setup (normal price €1,500). In exchange I need your feedback. 10-minute call?"

At 3 customers × €500 pilot = €1,500. Plus €99/mo hosting each = €297/mo recurring from month 2.

---

## Phase 2 — €1,000 to €3,000/month (Months 3–8)
*Goal: establish recurring base, productize the install process*

**Raise prices to real rates after pilots.**
€1,500–2,000 setup + €99–149/month hosting.
The pilots give you testimonials and case studies. One case study ("Clinic X went from manual bank transfer dues to automated monthly billing in 2 weeks") is worth more than any ad.

**Build a second vertical plugin with Claude Code.**
Use the same vbwd core. Different domain plugin. Maybe 3–5 evenings.
Now you have two products reaching two audiences.

**Automate the install.**
Write a setup script (Ansible playbook or bash) that provisions a VPS, deploys vbwd, configures the domain, runs migrations, and seeds demo data — in under 30 minutes.
This is the highest-leverage technical investment you can make. It means you can onboard a customer in an evening, not a week.

**Target: 15–20 hosted customers by month 8.**
15 customers × €129/mo average = €1,935/month recurring.
Plus 1–2 new installs/month at €1,500 = €1,500–3,000/month project income.
Total: €3,435–4,935/month gross.

---

## Phase 3 — €3,000 to €10,000/month (Months 8–18)
*Goal: compounding recurring revenue + one high-value vertical*

**Find the vertical that has the most willingness to pay.**
From the reports: local ISPs (WISPs), compliance-heavy EU businesses, healthcare-adjacent.
These customers pay €200–500/month for hosting and €3,000–8,000 for setup.
5 WISP customers at €299/month = €1,495/month. 1 WISP setup = €3,000–5,000.

**Productize discovery with Claude Code.**
Build a demo environment that deploys in 5 minutes with fake data for each vertical.
Send prospects a live demo link. Close rate multiplies.

**The compounding effect:**
- Month 8:  20 customers × €129 = €2,580 MRR + projects
- Month 12: 40 customers × €139 = €5,560 MRR + projects
- Month 18: 70 customers × €149 = €10,430 MRR

At 70 hosted customers on a single €40/month VPS-per-customer model:
- Revenue: €10,430/month
- Infrastructure cost: ~€2,800/month (70 × €40 VPS)
- Net before tax: €7,630/month
- Net after ~30% tax: ~€5,340/month

Not enough. So you also need projects:
- 2 installs/month at €2,000 average = €4,000/month
- Combined net after tax: ~€8,000–9,000/month

To cross €10k net:
- Either 85+ hosted customers, or
- 70 hosted + 3 installs/month, or
- 50 hosted + 1 high-value WISP/compliance customer at €499/month

All of these are realistic by month 18 with consistent part-time effort.

---

## The Claude Code Multiplier

This is the part that makes the timeline above achievable for one person with limited time.

Every vertical plugin that would take a week takes an evening with Claude Code:
- Describe the domain requirements
- Claude generates the Flask plugin (routes, service, model, tests)
- Claude generates the Vue admin component
- You review, test, adjust in 2–4 hours
- Ship

What this means practically:
- You can serve 5 verticals instead of 1
- Each vertical is a separate marketing channel
- Setup scripts, documentation, email sequences — all Claude-assisted
- Bug fixes take 20 minutes instead of 2 hours

**The solo dev with Claude Code has the output of a 3-person team.**
The constraint shifts from "can I build this" to "can I find and close customers."
That is a sales and distribution problem, not a technical one.

---

## The One Bottleneck: Sales

Everything in this plan breaks down if you cannot consistently talk to potential customers.
Technical skill and Claude Code remove the build bottleneck entirely.
The remaining constraint is: **10 meaningful conversations per week with people who have the problem you solve.**

Ways to generate conversations without a marketing budget:
1. **LinkedIn** — comment substantively on posts by people in your target verticals (vet practice managers, WISP operators, dental office managers). One useful comment per day.
2. **Niche Facebook groups** — not spam, genuine participation. Answer questions about billing, membership management. Become the person people DM.
3. **Cold email** — 20 targeted emails per week. Use Apollo or Hunter.io free tier. One sentence of personalization. One clear offer. One call to action.
4. **Partner with consultants** — find one consultant who serves your target vertical (a vet practice consultant, a WISP consultant). Give them 20% referral. They have the relationship, you have the product. One partner = 2–4 referrals/month.
5. **GitHub/dev community** — open source the vbwd core plugin for your vertical (e.g., open source the WISP plugin). Charge for setup and hosting. Community builds trust.

---

## What to Do This Week

1. **Choose one niche.** Not two. One.
2. **Find 5 real businesses in that niche** in your country or language area.
3. **Send 5 emails today** with the pilot offer.
4. **Build the vertical plugin this weekend** with Claude Code whether or not anyone replied.
5. **Deploy a demo instance** on a €6/month VPS with fake data so you can show a live URL.

The demo URL closes more deals than any pitch deck.

---

## Risk Management

**Biggest risk: building without selling.**
The temptation is to keep building vbwd features. Resist this. The platform is already good enough.
Every hour spent on features before customer 10 is an hour not spent finding customers.

**Second risk: pricing too low.**
€29/month feels "safer" to pitch but requires 500 customers for €10k net. Unachievable solo.
€99–299/month feels "risky" to pitch but requires 50–100 customers. Achievable solo.
Charge real prices from the start.

**Third risk: too many verticals.**
One niche, fully served, is worth more than five niches half-served.
Depth beats breadth until you have recurring revenue to fund breadth.

---

## The Realistic Timeline Summary

| Month | MRR | Project income | Gross/month | Net/month (after tax) |
|---|---|---|---|---|
| 3 | €300 | €1,500 | €1,800 | €1,260 |
| 6 | €1,200 | €2,000 | €3,200 | €2,240 |
| 9 | €2,800 | €3,000 | €5,800 | €4,060 |
| 12 | €5,000 | €3,500 | €8,500 | €5,950 |
| 15 | €7,500 | €4,000 | €11,500 | €8,050 |
| 18 | €10,000 | €4,500 | €14,500 | €10,150 ✓ |

Month 18 is conservative. With one high-value vertical (WISP or EU compliance) or a referral partner, month 14–15 is achievable.

**The path is real. The only question is whether you make 10 sales conversations happen per week consistently for 18 months.**
