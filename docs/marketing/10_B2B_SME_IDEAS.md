# 10 B2B Business Ideas for SMEs on VBWD

**Date:** March 2026
**License:** BSL 1.1 — free under 5K EUR / 24 users, commercial license above
**Audience:** Businesses selling to other businesses. Not consumer apps — enterprise-grade tools that SMEs actually pay for because they directly affect revenue, compliance, or operational efficiency.

---

## 1. Vendor Compliance & Onboarding Portal

**The Problem:** Every mid-size company (50-500 employees) onboards 20-100 new vendors per year. Each vendor must submit: tax ID, insurance certificates, bank details, signed contracts, data processing agreements (GDPR), quality certifications. Currently this is done through email chains, shared drives, and spreadsheets. One missing document = payment delay = angry vendor = supply chain risk.

**What You Build:** A self-service portal where vendors register, upload required documents, sign agreements, and maintain their compliance profile. The buying company's admin dashboard shows compliance status at a glance.

**VBWD core used:** User management (vendor accounts), CMS (document requirements, guides), Email (reminders, status updates), Analytics (compliance dashboard), Subscriptions (annual vendor portal fee)

**New plugin: `vendor-portal`**
- Document checklist engine: configurable per vendor category (supplier, contractor, consultant)
- Document upload + expiry tracking: "Insurance expires 2026-09-01 — auto-remind 30 days before"
- Digital signature: DocuSign/HelloSign API integration for contracts
- Approval workflow: document uploaded → reviewer notified → approved/rejected with comments
- Compliance score: vendor rated 0-100% based on complete/valid documents
- Bulk operations: "Email all vendors with expired insurance certificates"
- API: ERP integration (push approved vendor data to SAP, NetSuite, Xero)

**Target clients:**
- Manufacturing companies with large supplier networks
- Construction firms managing subcontractor compliance
- Healthcare organizations (vendor qualification is regulatory requirement)
- Government contractors (compliance is non-negotiable)
- Any company subject to supply chain due diligence laws (EU CSDDD, German LkSG)

**Pricing:** $1,499/year for up to 200 vendors. $4,999/year unlimited. Managed hosting: $149/mo.

**Revenue at scale:** 20 companies x $2,500 avg license = $50,000/year. This is sticky — once 200 vendors are onboarded, switching cost is massive.

---

## 2. White-Label Client Training Academy

**The Problem:** B2B companies (software vendors, equipment manufacturers, professional services firms) need to train their clients' employees. Example: a POS system vendor sells to 200 restaurants — each restaurant has 5-15 staff who need to learn the system. Currently: PDF manuals nobody reads, Zoom calls that don't scale, or Docebo/TalentLMS at $300-$1,500/month.

**What You Build:** A branded training platform that the B2B company deploys under their own domain. Their clients' employees log in, complete training modules, pass assessments, receive certificates.

**VBWD core used:** CMS (training content, modules), User management (multi-tenant: company → employees), Subscriptions (per-seat or per-company billing), Email (course reminders, completion notifications), Analytics (completion rates), Token economy (credits for advanced courses)

**New plugin: `academy`**
- Course builder: modules → lessons → quizzes → certificate
- Multi-tenant: Company A's employees see only Company A's courses
- Progress tracking: "Restaurant staff: 12/15 completed onboarding module"
- Assessment engine: multiple choice, practical checklists, pass/fail with retake
- Certificate generation: PDF with QR verification code
- Manager dashboard: "Your team's training completion: 78%"
- SCORM import: bring existing e-learning content
- Gamification: badges, leaderboards, completion streaks

**Target clients:**
- SaaS companies training their customers' teams
- Equipment manufacturers (medical devices, industrial machinery — training is often legally required)
- Franchise networks (standardized training across 50-500 locations)
- Compliance training vendors (GDPR, safety, anti-money laundering)
- Professional associations offering continuing education credits

**Pricing:** $499/year per company (up to 100 learners). $1,499/year per company (unlimited). The B2B company typically deploys one instance and onboards all their clients.

**Revenue at scale:** 15 B2B companies x $1,499/year = $22,485 in licenses. But the real play: each B2B company charges their clients $10-50/user/month for the training portal — and you get the license fee regardless. 5 large deployments (500+ learners each) at Enterprise tier ($4,999/year) = $24,995.

---

## 3. Subscription-Based Equipment Monitoring & Maintenance SaaS

**The Problem:** SMEs that operate equipment (HVAC companies, elevator services, fleet operators, industrial laundries, restaurant chains with commercial kitchens) need to track: maintenance schedules, service history, warranty expiry, parts inventory, technician dispatch. They use spreadsheets or pay $200-$800/mo for platforms like UpKeep, Fiix, or Limble CMMS.

**What You Build:** A self-hosted CMMS (Computerized Maintenance Management System) where equipment operators track assets, schedule maintenance, and manage work orders. Subscription-tiered by number of assets tracked.

**VBWD core used:** User management (technicians, managers, clients), Subscriptions (tiered by asset count), Booking (schedule maintenance visits), Email (maintenance reminders, work order notifications), Invoicing (bill clients for maintenance contracts), Analytics (equipment uptime, cost tracking), CMS (knowledge base, maintenance procedures)

**New plugin: `cmms`**
- Asset registry: equipment type, serial number, location, warranty, maintenance schedule
- Work order system: create → assign to technician → in progress → complete → invoice
- Preventive maintenance calendar: "Elevator #3: quarterly inspection due 2026-04-15"
- Parts inventory: track spare parts, reorder alerts, cost per repair
- Mobile-friendly: technician opens phone, scans QR on equipment, sees full history + open work orders
- Client portal: equipment owner sees their assets, upcoming maintenance, invoice history
- IoT-ready: webhook endpoint for sensor data (temperature, vibration, runtime hours)

**Target clients:**
- HVAC service companies managing maintenance contracts
- Elevator/escalator service companies
- Commercial kitchen equipment service providers
- Fleet management companies (vehicle maintenance)
- Facility management companies
- Any B2B service company that sells maintenance contracts

**Pricing:** $499/year (up to 100 assets). $1,499/year (up to 1,000 assets). $4,999/year (unlimited + IoT). Managed hosting: $99/mo.

**Revenue at scale:** 25 service companies x $1,499/year = $37,475. The subscription model aligns perfectly — they already sell subscriptions to THEIR clients (maintenance contracts), and VBWD bills them for the platform.

---

## 4. B2B Referral & Commission Tracking Platform

**The Problem:** SMEs rely on referral partners (accountants referring clients to lawyers, real estate agents referring to mortgage brokers, IT consultants referring to SaaS vendors). Tracking who referred whom, what commission is owed, and when to pay is a manual nightmare. Existing affiliate/referral software (PartnerStack, FirstPromoter) costs $500-$2,500/month and is designed for SaaS companies, not service businesses.

**What You Build:** A platform where businesses manage their referral partner network — track referrals, calculate commissions, automate payouts, and give partners a self-service dashboard.

**VBWD core used:** User management (partners + referred clients), Subscriptions (partner tiers with different commission rates), Invoicing (commission invoices), Stripe Connect (automated payouts), Email (referral notifications, payout confirmations), Analytics (partner performance), Token economy (bonus credits)

**New plugin: `referral-network`**
- Partner registration: apply, get approved, receive unique referral link/code
- Referral tracking: link click → signup → qualified lead → closed deal → commission triggered
- Commission rules engine: flat fee ($200 per referral), percentage (10% of first year), recurring (5% ongoing), tiered (10% first 5, 15% next 10, 20% after)
- Attribution window: "Referral valid for 90 days after first click"
- Payout automation: monthly commission calculation → Stripe Connect payout → invoice generated
- Partner dashboard: "Your referrals: 12 leads, 7 closed, $3,400 earned this quarter"
- Leaderboard + tiers: Bronze/Silver/Gold partners with escalating commission rates
- Two-sided: both referrer and referred client get benefits (e.g., referrer gets commission, client gets 10% discount)

**Target clients:**
- Accounting firms with referral networks (lawyers, financial advisors, insurance brokers)
- Real estate agencies with referral partnerships
- IT service companies with vendor referral programs
- Marketing agencies with white-label partner programs
- SaaS companies with channel partner programs (but too small for PartnerStack)
- Recruitment agencies with referral bonus programs

**Pricing:** $499/year (up to 50 partners). $1,499/year (up to 500 partners). $4,999/year (unlimited + API + white-label).

**Revenue at scale:** 30 companies x $999 avg = $29,970/year. Upsell: 1% platform fee on tracked commissions. $500K in annual commissions tracked x 1% = $5,000. Combined: $34,970/year.

---

## 5. Multi-Location Franchise Management Platform

**The Problem:** Small franchise networks (10-200 locations) — think pizza chains, fitness studios, cleaning companies, tutoring centers — need a central platform for: location performance tracking, royalty fee billing, brand compliance auditing, training distribution, and local marketing materials. Enterprise franchise software (FranConnect, FranDev) costs $50K-$200K/year. Small networks use shared Google Sheets.

**What You Build:** A franchise HQ platform. Franchisors manage their network, bill royalties, distribute training, and monitor compliance. Each franchisee has a self-service portal.

**VBWD core used:** User management (franchisor HQ, franchisee accounts, franchisee staff), Subscriptions (monthly royalty billing per location), Invoicing (royalty invoices + fee breakdowns), Email (network communications, compliance alerts), Analytics (network-wide performance), CMS (brand guidelines, marketing materials, operations manual), Booking (field audit scheduling)

**New plugin: `franchise`**
- Location registry: address, territory, franchisee, open date, agreement expiry
- Royalty engine: percentage of revenue (5-8%) or flat fee, auto-billed monthly via subscription
- Revenue reporting: franchisee self-reports or connects POS/Stripe for auto-reporting
- Brand compliance: checklist audits ("storefront signage: compliant?", "uniform policy: compliant?"), photo uploads
- Field audit scheduling: HQ books audit visits via booking plugin, franchisee confirms
- Document distribution: operations manual, marketing templates, menu updates — versioned, read-receipts
- Performance benchmarking: "Your location ranks #8 of 45 in revenue per seat"
- Communication hub: HQ announcements, franchisee Q&A, best practice sharing

**Target clients:**
- Restaurant franchises (10-200 locations)
- Fitness/gym franchises (CrossFit affiliates, yoga chains, boutique studios)
- Home services franchises (cleaning, handyman, pest control)
- Education franchises (tutoring, language schools, coding academies)
- Retail franchises (specialty stores, convenience chains)

**Pricing:** $4,999/year (up to 50 locations). $9,999/year (up to 200 locations). $149/mo managed hosting.

**Revenue at scale:** Even 5 franchise networks at an average of $7,500/year = $37,500/year. These are extremely sticky clients — a franchise network will never switch platforms once 50 franchisees are onboarded.

---

## 6. Procurement Marketplace for Industry Verticals

**The Problem:** SME buyers in niche industries (restaurants buying food supplies, dentists buying dental supplies, construction firms buying building materials) have 3 options: call 5 suppliers for quotes (slow), use Amazon Business (generic, no industry pricing), or use industry-specific platforms that charge suppliers 15-25% commission (e.g., Grubmarket for food). Small suppliers can't afford the commission, small buyers don't get volume discounts.

**What You Build:** A vertical procurement marketplace where verified industry suppliers list products with volume pricing, and buyers subscribe for access to negotiated group rates. The platform earns from supplier subscriptions (listing fees), not commissions on transactions.

**VBWD core used:** User management (buyers + suppliers, dual roles), Subscriptions (supplier listing fee + buyer membership), CMS (product catalog), Invoicing (purchase orders + invoices), Email (order notifications, restock alerts), Analytics (spend analytics, supplier performance), Token economy (buyer credits / volume discount tokens)

**New plugin: `procurement`**
- Product catalog: SKU, description, unit price, volume breaks, minimum order, lead time
- RFQ (Request for Quote): buyer posts need → multiple suppliers respond with quotes
- Group purchasing: aggregate demand across buyers for better pricing ("23 restaurants need 500kg flour this month")
- Order management: PO creation → supplier confirmation → delivery tracking → receipt → invoice matching
- Approved supplier lists: buyer maintains preferred suppliers with pre-negotiated rates
- Spend analytics: "You spent $45K on paper goods last quarter across 8 suppliers — consolidating to 2 would save $6K"
- Recurring orders: "Auto-order 50 boxes of gloves every 2 weeks from Supplier X"

**Target verticals (pick ONE to start):**
- Restaurant supplies (food, disposables, equipment)
- Dental/medical supplies
- Construction materials
- Automotive parts (independent repair shops)
- Salon/beauty supplies
- Office supplies for SME clusters (co-working spaces, business parks)

**Pricing:**
- Supplier listing: $99-$499/mo depending on catalog size
- Buyer membership: free (basic) or $49/mo (premium — group purchasing, spend analytics)
- Platform fee: 0-2% on transactions (far below marketplace competitors at 15-25%)

**Revenue at scale:** 50 suppliers at $199/mo average = $119,400/year in listing fees. 200 buyers at $49/mo = $117,600/year. Transaction fees on $5M annual GMV at 1% = $50,000/year. Total potential: $287,000/year at scale. Even at 10% of that in Year 1: $28,700.

---

## 7. SLA-Tracked IT Support Portal for MSPs

**The Problem:** Managed Service Providers (MSPs) — small IT companies managing infrastructure for 10-100 client businesses — need a client-facing portal for: ticket submission, SLA tracking, knowledge base, monthly reporting, and subscription billing. ConnectWise/Datto charge $100-$300/seat/month. A 5-person MSP pays $6,000-$18,000/year just for the PSA platform. That's often their largest cost after salaries.

**What You Build:** A self-hosted IT support portal with SLA tracking, ticketing, knowledge base, and client billing — all integrated. The MSP deploys it under their own brand.

**VBWD core used:** User management (MSP technicians + client contacts), Subscriptions (monthly IT support contracts per client), Invoicing (monthly service invoices + ad-hoc billing for out-of-scope work), Email (ticket notifications, SLA warnings), Analytics (SLA performance, response times), CMS (knowledge base, FAQs), Booking (scheduled maintenance windows), Token economy (support hours bank)

**New plugin: `msp-portal`**
- Ticket system: create, assign, prioritize (P1-P4), track time spent, attach screenshots
- SLA engine: per-client SLA rules ("P1: respond in 15 min, resolve in 4 hours. P2: respond in 1 hour, resolve in 8 hours")
- SLA dashboard: green/yellow/red per client, breach alerts, monthly compliance percentage
- Hours bank: client buys 20 support hours/month (token bundles). Usage tracked automatically. Overage billed at $150/hr.
- Asset tracking: link tickets to client's devices/servers/services
- Monthly report generator: "Client XYZ — March 2026: 14 tickets, 100% SLA compliance, 12.5 hours used of 20"
- Client portal: client logs in, sees their tickets, SLA status, hours remaining, invoices
- Remote access integration: webhook to launch remote session (TeamViewer, AnyDesk, RustDesk)

**Target clients:**
- MSPs with 10-100 client businesses (there are 40,000+ MSPs in the US alone)
- IT freelancers managing multiple clients
- Internal IT departments in mid-size companies (100-500 employees)
- Telecom providers with SME support contracts

**Pricing:** $499/year (up to 20 clients). $1,499/year (up to 100 clients). $4,999/year (unlimited + API + white-label).

**Revenue at scale:** 40 MSPs x $1,499/year = $59,960/year. MSPs are the perfect customer — they understand self-hosting, they value cost savings over incumbent platforms, and they evangelize to other MSPs in their communities.

---

## 8. Subscription Licensing Platform for Industrial IP

**The Problem:** Companies that own industrial intellectual property — proprietary formulas, manufacturing processes, patented designs, specialized software algorithms, testing protocols — license them to other companies. Currently managed through PDF contracts, manual invoicing, and zero usage tracking. Enterprise license management (Flexera, Revenera) costs $100K+/year. SMEs with 5-50 licensees use email and spreadsheets.

**What You Build:** A platform where IP owners manage licensees, track usage/compliance, bill subscription fees, and distribute updated IP materials — all in one place.

**VBWD core used:** User management (IP owner + licensees), Subscriptions (license fees — monthly/annual), Invoicing (license invoices + usage-based overages), Email (license renewal reminders, update notifications), CMS (IP documentation, specifications, manuals), Analytics (usage tracking, revenue per licensee), Token economy (usage credits for metered licenses)

**New plugin: `ip-licensing`**
- License model: type (exclusive/non-exclusive/limited territory), duration, renewal terms, usage limits
- License key system: generate, activate, validate, revoke (for software IP)
- Usage metering: API calls, units produced, seats used — depending on license type
- Compliance monitoring: licensee self-reports usage quarterly, system flags anomalies
- Update distribution: new version of formula/process/design → push to all active licensees
- Territory management: map showing which licensees cover which regions (non-compete enforcement)
- Renewal automation: 90-day, 60-day, 30-day warnings → auto-generate renewal invoice
- Audit trail: immutable log of all license changes, access events, document downloads

**Target clients:**
- Chemical/pharma companies licensing formulations
- Manufacturing companies licensing production processes
- Engineering firms licensing patented designs
- Testing/certification bodies licensing testing protocols
- Universities licensing research patents to industry
- Franchise-adjacent businesses licensing proprietary methods (not full franchise, just IP)

**Pricing:** $1,499/year (up to 20 licensees). $4,999/year (up to 100 licensees). $9,999/year (unlimited + API + audit compliance features).

**Revenue at scale:** 15 IP owners x $4,999/year = $74,985/year. These are high-value, extremely sticky clients — their entire licensing revenue depends on the platform.

---

## 9. Subcontractor Marketplace for Overbooked Service Companies

**The Problem:** Specialized B2B service companies (IT consulting, engineering firms, marketing agencies, translation agencies, accounting firms) frequently get more work than they can handle. They subcontract to trusted peers — but finding, vetting, and managing subcontractors is ad-hoc. Currently: "Hey do you have capacity?" messages in WhatsApp groups. No pricing transparency, no quality tracking, no automated billing.

**What You Build:** A private marketplace where service companies post overflow work and vetted subcontractors bid on it. The platform handles matching, pricing, quality tracking, and payment splitting.

**VBWD core used:** User management (companies + subcontractors), Booking (project scheduling, availability calendar), Invoicing (client → company → subcontractor chain), Stripe Connect (automatic payment splitting), Subscriptions (platform membership for companies), Email (new opportunity alerts), Analytics (subcontractor performance), Token economy (reputation credits)

**New plugin: `subcontract`**
- Capacity board: subcontractors post availability ("Available: 40hrs/week in April, skills: React, Node, AWS")
- Opportunity posting: company posts overflow project with scope, budget, timeline, required skills
- Bidding: qualified subcontractors bid (rate, timeline, relevant experience)
- Matching algorithm: auto-suggest subcontractors based on skills, past performance, availability, rate
- Quality tracking: after project, both parties rate each other (NPS-style + specific criteria)
- NDAs/contracts: auto-generated, digitally signed before project starts
- Invoicing chain: subcontractor invoices platform → platform invoices company → company invoices end client
- Margin management: company sets markup (subcontractor at $100/hr, bills client $150/hr, platform tracks both)

**Target verticals (each is a separate marketplace):**
- IT consulting / software development (massive subcontracting market)
- Translation / localization agencies
- Engineering / architectural firms
- Marketing / creative agencies
- Accounting / bookkeeping firms
- Legal firms (contract work overflow)

**Pricing:**
- Company membership: $149/mo (post unlimited opportunities)
- Subcontractor membership: free (you want supply-side liquidity)
- Platform fee: 3-5% on payments processed through the platform
- Premium: $499/mo for companies wanting dedicated account manager + priority matching

**Revenue at scale:** 30 companies at $149/mo = $53,640/year in subscriptions. $2M in annual subcontracted work at 4% platform fee = $80,000/year. Total: $133,640/year. Start with ONE vertical (IT consulting is the largest and most willing to pay).

---

## 10. Regulatory Change Alert & Compliance Tracker

**The Problem:** SMEs in regulated industries (food production, medical devices, financial services, construction, chemicals, waste management) must comply with hundreds of regulations that change constantly. A new EU directive, a national implementation, a local ordinance — each requires action. Large companies have compliance departments. SMEs have one overwhelmed person who checks government websites weekly and hopes nothing slips through. One missed regulation = fines, shutdowns, lawsuits.

**What You Build:** A subscription service that monitors regulatory changes for specific industries/jurisdictions, alerts affected businesses, and tracks their compliance response. Think "Google Alerts meets Jira, but for regulations."

**VBWD core used:** Subscriptions (tiered by number of regulations tracked), CMS (regulation database, summaries, action guides), Email (alert notifications, digest), Analytics (compliance status dashboard), Token economy (credits for AI-powered regulation summaries), Chat (AI assistant for regulation Q&A), Booking (compliance consultation appointments)

**New plugin: `compliance-tracker`**
- Regulation database: structured entries (title, jurisdiction, effective date, affected industries, summary, full text link)
- Alert engine: new/changed regulation → match to subscriber's industry + jurisdiction → notify
- Impact assessment: AI-generated summary "What this means for your business" + action checklist
- Compliance task tracker: regulation → required actions → assigned to team member → deadline → status
- Audit-ready reports: "Here's everything we did to comply with Regulation X, with timestamps and evidence"
- Calendar view: "Upcoming compliance deadlines for your industry"
- Regulation feed: curated by human experts + AI monitoring of official gazettes, EUR-Lex, national registers

**How it works:**
- Food manufacturer subscribes: €99/mo, tracks EU food safety regulations + German national implementation
- New regulation published: "Commission Regulation (EU) 2026/XXX — new labeling requirements for allergens"
- Platform alerts: "Action required by 2027-01-01. Affects: all packaged food products. Key changes: [summary]. Action checklist: [5 items]."
- Manufacturer assigns tasks to team: update labels, retrain staff, update website, notify distributors
- Dashboard shows: "4 of 5 actions complete. Deadline in 74 days. Status: on track."

**Target industries (start with ONE):**
- Food production / food service (HACCP, allergens, labeling — constantly changing)
- Medical devices (MDR/IVDR — EU regulations are a compliance nightmare for SMEs)
- Financial services (AML, PSD2, MiCA — never stops changing)
- Construction (building codes, safety, environmental)
- Chemicals (REACH, CLP — substance restrictions updated quarterly)
- Data protection (GDPR enforcement actions, new guidance, national DPA decisions)

**Pricing:**
- Starter: €99/mo (1 jurisdiction, 1 industry vertical)
- Professional: €299/mo (3 jurisdictions, 2 verticals, AI summaries)
- Enterprise: €799/mo (unlimited, API, custom alerts, dedicated analyst)

**Revenue at scale:** 50 SMEs at €199/mo average = €119,400/year. This is extremely sticky — no company cancels their compliance alert system. Churn rate <5%/year because the risk of missing a regulation is existential.

**The content moat:** The regulatory database is the real asset. Every month of monitoring builds a more comprehensive database that competitors can't replicate without the same effort. AI helps but human curation of jurisdiction-specific nuances is the differentiator.

---

## Revenue Comparison

| # | Business | Year 1 Realistic | Stickiness | Build Effort |
|---|----------|-----------------|------------|--------------|
| 1 | Vendor Compliance Portal | $30-50K | Very High | 4-5 weeks |
| 2 | Client Training Academy | $20-35K | High | 5-6 weeks |
| 3 | Equipment Maintenance (CMMS) | $25-40K | Very High | 6-8 weeks |
| 4 | Referral & Commission Tracking | $25-35K | High | 3-4 weeks |
| 5 | Franchise Management | $30-50K | Extreme | 6-8 weeks |
| 6 | Procurement Marketplace | $20-30K | High | 8-10 weeks |
| 7 | MSP Support Portal | $40-60K | Very High | 5-6 weeks |
| 8 | IP Licensing Platform | $50-75K | Extreme | 4-5 weeks |
| 9 | Subcontractor Marketplace | $30-50K | High | 6-8 weeks |
| 10 | Regulatory Compliance Tracker | $40-80K | Extreme | 6-8 weeks (+ ongoing content) |

---

## B2B Buying Patterns That Favor VBWD

**Why SMEs buy self-hosted B2B tools:**

1. **Data sovereignty** — "Our vendor list / client data / IP catalog is NOT going to a US cloud service"
2. **Compliance** — "Our auditor requires data residency in the EU" (GDPR, Schrems II, DORA)
3. **Total cost** — "We calculated: $500/mo SaaS x 5 years = $30,000. VBWD license + hosting = $6,000 over 5 years"
4. **Customization** — "We need the tool to match OUR process, not reshape our process around the tool"
5. **No vendor dependency** — "If the SaaS vendor shuts down, we keep running"

**The VBWD pitch to B2B SMEs:**

> "You're paying $300-$1,500/month for a cloud tool that holds your business data hostage. For a one-time license + $25/month hosting, you own everything — your data, your customizations, your uptime. And the source code is right there on GitHub if you ever want to verify what it does."

---

## Which to Build First?

**Fastest to market (least new plugin code needed):**
- #4 Referral Tracking — VBWD's subscription + invoicing + Stripe Connect covers 70% of the need
- #1 Vendor Portal — CMS + user management + email covers the foundation

**Highest revenue per client:**
- #8 IP Licensing — $5K-$10K/year per client, small number of clients needed
- #5 Franchise Management — $5K-$10K/year per client, extreme lock-in

**Largest addressable market:**
- #7 MSP Portal — 40,000+ MSPs in the US alone, all actively looking for cheaper ConnectWise alternatives
- #10 Regulatory Compliance — every regulated SME is a potential customer

**Best for partner resale (agencies deploy for their clients):**
- #2 Training Academy — agencies build training portals for their B2B clients
- #1 Vendor Portal — consultants deploy for their procurement clients
