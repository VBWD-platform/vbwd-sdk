# VBWD — Geo Strategy: SE Asia + Gulf, Hospitality/Wellness/Travel

**Companion to** `01-next-90-days-plan.md`. Same constraints apply: solo dev, day-job, **8–12 hrs/week**, **no synchronous sales**, no founder-led demos, no merchant calls. The Y1 base plan (Bucket B / Gumroad-alternative wedge) stays intact. This document layers an **incremental geo channel** on top.

**The question this document answers.** Can VBWD earn meaningful revenue from agencies and hospitality/wellness/travel vendors in Thailand, Vietnam, and the Arab world (UAE + KSA + Bahrain/Qatar/Kuwait), under the same constraints as plan 01? Short answer: **yes, but only via local reseller agencies and only on top of one product investment** (RTL + local payment rails + translations). Realistic incremental contribution: **€15–30k Y1, €60–100k Y2.**

**What this document is NOT proposing.** Not a Booking.com / Agoda / Klook / Trip.com alternative. VBWD does not compete with **inventory aggregators** (the marketplace OTAs that bring guests via their own demand-generation). VBWD competes with **single-property and small-chain direct-booking infrastructure**: Cloudbeds, Hotelogix, RoomRaccoon, Resly, ezCloud — and the bespoke "Bangkok web-agency built it from scratch" stack that small hotels and spa chains run today. The honest framing in `decks/hotel/en/06-honest-gaps.html` already says this — VBWD is the **guest-facing surface**, not a full PMS, not a channel manager.

---

## 1. TL;DR

| | Thailand | Vietnam | GCC (UAE + KSA core) |
|---|---|---|---|
| Tourist arrivals 2024 (intl, public stats) | ~35M | ~17.5M intl + ~110M domestic | UAE ~30M; KSA ~30M (Vision 2030 target 100M by 2030) |
| Accommodation establishments (broad) | ~30k–40k formal hotels + 100k+ informal | ~36k licensed accommodation properties | UAE ~1,200 hotels + serviced apartments; KSA ~5k+ hotels |
| Spa/wellness establishments (estimates) | ~30k massage/spa | ~5k formal spa | UAE ~700+ wellness/spa; growing fast under Saudi Vision |
| OTA dependency (industry-reported range) | 60–80% of bookings via OTAs for SME hotels | 65–80% | 50–70% (luxury skews lower; budget skews higher) |
| Booking.com / Agoda commission | 15–25% | 15–25% | 15–25% |
| Local agencies that build hotel websites | Hundreds; well-organised dev scene in Bangkok / Chiang Mai / Phuket | Hundreds; HCMC + Hanoi tech hubs | Dubai, Riyadh, Jeddah — strong but expensive |
| Stripe availability | Yes (Stripe Thailand) | Limited (workaround via SG/MY entity) | Yes (UAE + KSA, since 2024–25) |
| Critical local payment rails | PromptPay, TrueMoney, Rabbit LinePay | VNPay, MoMo, ZaloPay, Napas | Mada (KSA), Tabby, Tamara, Apple Pay, Network Intl |
| Language burden | Thai (i18n only) | Vietnamese (i18n only) | Arabic (i18n **+ RTL CSS**) |

**The bet:** sign **8–15 local agencies as resellers** across the three geos in 12 months, give them a localised VBWD package, take Pro/Enterprise license fees from them, let **them** do all the merchant-facing work. You never speak to a hotel or spa owner.

---

## 2. The framing — what we are and aren't selling

### We are NOT selling

| Category | Examples | Why we don't go here |
|---|---|---|
| Inventory aggregators / OTAs | Booking.com, Agoda, Trip.com, Klook, Expedia | Two-sided marketplace = needs supply *and* demand. VBWD has neither. |
| Mass-market metasearch | Trivago, KAYAK, Skyscanner | Same reason |
| Property management systems (PMS) for ops | Opera, Mews, Cloudbeds (PMS layer), Hotelogix (PMS layer) | VBWD is guest-facing only. Honest gap is documented. |
| Channel managers | SiteMinder, HotelRunner, DerbySoft, Cloudbeds Channel Manager | Roadmap, not shipped. Plugin opportunity for a partner. |
| Restaurant POS | TouchBistro, Toast, Square, Loyverse, StoreHub (SE Asia) | Different problem space; VBWD has no POS hardware story. |
| Tour-operator OTAs | Viator, GetYourGuide, Klook | Same as Booking.com — aggregators with their own demand engine. |

### We ARE selling — the four shapes that fit

| Shape | Who | Pain VBWD solves | Vertical fit (1–5) |
|---|---|---|---|
| **Independent boutique hotel direct-booking** | 5–80 room hotels, often family-owned, with a PMS already | OTA tax + non-converting English-only checkout + no loyalty system | 5/5 (matches the hotel deck) |
| **Small hotel group / chain (3–15 properties)** | Regional groups, wellness resorts, eco-lodges | Same as above + multi-property routing on one VBWD instance | 5/5 |
| **Wellness / spa chain (3–30 locations)** | Day spas, medical wellness, yoga retreat chains | Appointment booking + prepaid token packages + membership tiers + multilingual marketing | **5/5 — best fit of all** |
| **DMC / tour operator (B2C-side)** | Destination Management Companies selling multi-day packages, Umrah operators, halal-tourism specialists, dive-shop chains | Multi-pax bookings, voucher delivery, package builder, partner referral commissions | 4/5 (needs minor extension) |
| HORECA chains (restaurants, bars, café chains) | 3+ outlet operators | Loyalty + booking (table reservation, pre-order pickup) | **2/5 — skip in Y1.** No POS = wrong stack. Re-evaluate Y3. |

**The product surface that sells across all four shapes** already exists in the platform: Booking plugin (`decks/core/en/16-booking.html`), Token economy, CMS, Shop plugin (used here for vouchers/license-keys), multi-payment gateway, multi-tenant per VPS.

---

## 3. Why an aggregator-replacement pitch would fail (and we'd waste two years)

It's worth stating this explicitly because the question comes up every time:

| Reason | Detail |
|---|---|
| **Two-sided market problem** | An aggregator needs both inventory (hotels) and demand (travellers). VBWD has neither. Bootstrapping both, solo, part-time, in three foreign markets = ~zero probability. |
| **Capital intensity** | Booking Holdings spent **$5.9B on marketing in 2023**. Even regional players (Traveloka raised $200M+ in single rounds). We have a part-time dev. |
| **Network effect already won** | Booking.com + Agoda dominance in SE Asia is structural. Hotels list because travellers go there; travellers go there because hotels list. |
| **The leaky-bucket pitch beats the replacement pitch** | "Reduce your OTA dependency by 5–10%" is achievable and quantifiable. "Replace Booking.com" is not credible to any hotel owner who's been in business >2 years. |
| **VBWD's actual winning frame** | "You keep your PMS. You keep your OTA distribution. You add a direct-booking surface that converts your *returning* guests on your domain at 0% commission." This is the existing hotel deck — we don't change it. |

---

## 4. Market 1 — Thailand

### Why it matters

- ~35M international tourists in 2024 (Tourism Authority of Thailand reporting), back near pre-COVID peak.
- Hospitality contributes ~12–18% of GDP depending on year.
- **30k+ formal hotels and 100k+ informal accommodation** (homestays, condotels, hostels).
- **~30k spa/massage establishments** — Thai spa industry roughly **$1.5B+ annually** per industry trade reporting; one of the densest spa markets per capita on earth.
- Boutique hotel scene (Phuket, Koh Samui, Chiang Mai, Hua Hin, Krabi) is full of 10–60 room independent properties — **exactly the VBWD sweet spot**.

### Real competitors in market

| Vendor | What they sell | Pricing | Where they're weak |
|---|---|---|---|
| **Cloudbeds** | All-in-one PMS + booking engine + channel manager | ~$20–$200/room/month | Cloud-only, USD pricing, no token/loyalty primitive |
| **Hotelogix** | Cloud PMS + booking | ~$3.99/room/month + add-ons | Older UI; integrated channel manager limited |
| **RoomRaccoon** | PMS + booking + channel | ~€200+/month per property | EU-priced, strong but premium |
| **eZee Absolute (Yanolja Cloud)** | PMS + booking | $39+/month | Limited customisation |
| **Resly** | Local Thai PMS | THB-priced | Domestic-only marketing; no plugin ecosystem |
| **Hotelinvo, Bukin, Hotelogie** | Local Thai SaaS | THB-priced | Small footprint |
| **Bespoke web agency builds** | Custom on WordPress/Webflow + manual Stripe/Omise | $5k–$15k one-time | No ongoing platform; brittle |

**The wedge.** None of the cloud PMS vendors have a **token economy** or **multi-method local payment** architecture. Wellness chains and resort properties that want prepaid packages (very common in Thailand: "10-massage card", "weekly yoga unlimited") cannot get this from Cloudbeds without custom dev. VBWD ships it.

### Local payment rails (must support)

- **PromptPay** (QR-based bank transfer, dominant for under-THB-5,000 payments)
- **TrueMoney Wallet** (e-wallet, common with younger Thai buyers)
- **Rabbit LinePay** (LINE-integrated wallet)
- Visa/MasterCard via Stripe Thailand (live), Omise (popular Thai gateway), 2C2P (regional)
- PayPal (low usage but expected for international guests)

**Plugin status today:** Stripe + PayPal + YooKassa in core. **PromptPay + TrueMoney = a plugin to ship**, ~30 hrs of work, sellable at €99–199 one-time.

### Local agency landscape (the channel)

The reseller play depends on convincing 3–5 Thai dev/web agencies to add VBWD to their offering. Real candidates (publicly visible, well-known in BKK tech scene):

- **Pomelo Software** — Bangkok, hospitality-tech focused
- **Seven Peaks Software** — Bangkok, larger consultancy with hotel clients
- **Codium / Codigo** — boutique Thai dev shops
- **Tigerbay** — Phuket-based, digital agency with hotel clients
- **Fastwork-listed mid-tier dev shops** (~50 active hotel-website builders on the platform)

Initial outreach to ~30 agencies via cold email (one-shot, async — no call required). Conversion expected: **2–4 reseller signups in 90 days** at this volume.

### Y1 Thailand revenue model

| Revenue line | Y1 estimate |
|---|---|
| 3 reseller agencies × €1,499 Pro license | €4,500 |
| 1 reseller agency × €4,999 Enterprise (white-label rights) | €5,000 |
| Direct boutique-hotel licenses sold via the agencies (Starter): 10 × €499 | €5,000 |
| Spa/wellness chain Enterprise: 1 × €4,999 | €5,000 |
| PromptPay/TrueMoney plugin sales: 30 × €149 | €4,500 |
| **Y1 Thailand total** | **~€24,000** |

**About half the geo-incremental revenue.**

> **Money model — who runs hosting (applies to all three geos).** Consistent with plan 01's no-own-hosting rule: **you never run or bill hosting for any venue.** The reseller agency hosts the venue's instance on its own infrastructure (Hetzner / OVH / Vultr / a local Thai/VN/GCC cloud) and folds that cost into the monthly fee it charges the venue (the THB/VND/AED 3,000–8,000/mo). **None of that hosting margin flows to you** — it is the agency's, and is part of *why* the agency signs (recurring margin it keeps). Your revenue from the geo channel is strictly: (a) the Pro/Enterprise licence the agency buys from you, (b) one-shot local payment-rail plugin sales, (c) trickle payment-processor cashback. The revenue tables above already reflect this — there is deliberately **no hosting line in any geo table**. If a venue insists on managed hosting and the agency won't provide it, the fallback is the Elest.io listing from plan 01 (Elest.io operates it, you collect a small rev-share), never you.

---

## 5. Market 2 — Vietnam

### Why it matters

- 2024: **~17.5M international + ~110M domestic** tourist arrivals (Vietnam National Authority of Tourism). Domestic tourism is the secret weapon — far less OTA-saturated than international flow.
- ~36k licensed accommodation establishments (statistics published by VNAT; the long tail of unlicensed mini-hotels is much larger).
- Wellness market: **growing 12–15% annually** per industry estimates; Vietnamese middle class adopting spa/wellness rapidly.
- **HORECA (cafés especially)**: Vietnam's coffee chain density is world-class (Highlands, The Coffee House, Phuc Long, Trung Nguyen) — but as flagged earlier, no POS in VBWD = wrong stack for this segment.

### Real competitors in market

| Vendor | Notes |
|---|---|
| **ezCloud / ezFolio** | Dominant local cloud PMS. SME-focused. Strong Vietnamese-language UI. Reasonably entrenched. |
| **ChannelManager.com.vn** | Local channel manager + booking engine combos |
| **Cuckoo PMS** | Local SaaS, mid-market |
| **iVMS / Vinotel** | Local players |
| **Hotelogix** | Indian SaaS with growing Vietnam footprint |
| **Cloudbeds** | Premium segment (4–5 star) |
| **Manual WordPress + VNPay** | Genuinely common at sub-30-room properties |

**The wedge.** Same as Thailand but harder — local players (ezCloud) have language and price advantage. **VBWD wins only via local agencies** who bundle a custom-branded portal + token loyalty + multi-language i18n, none of which ezCloud ships natively.

### Local payment rails

- **VNPay** (most universal; QR + card + bank transfer)
- **MoMo** (largest e-wallet, ~30M+ users)
- **ZaloPay** (Zalo super-app integrated)
- **ShopeePay** (e-commerce-tied, growing)
- **Napas 247** (interbank instant transfer)
- Visa/Master via local processors (OnePay, NganLuong)
- Stripe **not directly available** for Vietnamese-registered entities (Stripe currently does not list VN as a supported country for Atlas/Stripe accounts). Workaround: Singapore/Malaysia/Hong Kong holding entity. **This is a constraint on direct-customer outreach in Vietnam.** For the reseller play, the agency handles entity / payments — not your problem.

### Vietnam channel partner candidates

- **KMS Technology** — large dev house (HCMC), occasional hospitality work
- **Saigon Technology** — boutique, English-friendly
- **Mona Media** — strong WordPress/Web design footprint, hotel clients
- **FPT Software** — too big, but their solution-architect freelancers moonlight
- **Scuti** — boutique, Vietnamese SME focus
- Long-tail: **TopDev** and **ITviec** marketplaces list ~hundreds of agencies; ~10–20 with real hotel/F&B portfolio

### Y1 Vietnam revenue model

| Revenue line | Y1 estimate |
|---|---|
| 2 reseller agencies × €1,499 Pro | €3,000 |
| 1 reseller agency × €4,999 Enterprise | €5,000 |
| Direct hotel licenses via agencies: 6 × €499 Starter | €3,000 |
| **Y1 Vietnam total** | **~€11,000** |

Smaller than Thailand because (a) Stripe friction limits direct-customer flow, (b) ezCloud is entrenched at the SME level, (c) language localisation is more isolating (less English in admin role at small properties).

---

## 6. Market 3 — GCC (UAE + KSA + Bahrain/Qatar/Kuwait)

### Why it matters

- UAE: **~30M international tourists in 2024** (Dubai alone ~18M); hospitality sector revenue ~AED 200B+ annually.
- **Saudi Vision 2030**: explicit public targets of **100M visitors by 2030**, ~$800B in tourism investment, 250k+ hotel rooms added. NEOM, AlUla, Diriyah, Red Sea Project. **Largest greenfield hospitality opportunity in the world right now.**
- Wellness market in UAE alone: **$5B+** per industry estimates, double-digit annual growth.
- Religious tourism (Umrah, Hajj) — Saudi government opening up year-round Umrah; ~20M Umrah pilgrims/year, growing toward Vision 2030 target of 30M.
- DMC (destination management) sector is mature and well-capitalised — many independent operators serve halal-tourism, luxury desert, dive (Red Sea), yacht charter.

### Real competitors in market

| Vendor | Notes |
|---|---|
| **Mews** | Strong in UAE 4–5 star. Cloud PMS, polished UI. |
| **Cloudbeds** | Mid-market dominance |
| **Opera (Oracle Hospitality)** | Enterprise standard; expensive |
| **Quore, ALICE (Actabl)** | Operations layer; not a competitor (different layer) |
| **Hotelogix** | Lower-end, Arabic UI partial |
| **D-Edge, SiteMinder** | Booking engine + channel mgr, premium |
| **Local UAE/Saudi web agencies** | Dozens; charge AED 30k–100k for custom hotel sites |

**The wedge.** Three structural openings:
1. **EU/Saudi data residency concerns** — same theme as plan 01's GoHighLevel pitch, but here the regulator is NCA / SDAIA in Saudi and TDRA in UAE. Self-hosted on Tier-3 datacentre **inside the country** (e.g., Khazna, STC, G42) is increasingly required for tourism / wellness data tied to government programs.
2. **Arabic + RTL is uneven across competitors.** Cloudbeds Arabic UI is partial. Most local agencies build Arabic frontends manually. A polished VBWD Arabic + RTL package becomes a real differentiator.
3. **Halal-tourism / Umrah-package operators** are underserved by Western SaaS. They want package builder, voucher delivery, group bookings, prayer-time integrations — niche but profitable.

### Local payment rails

- **Stripe** — live in both UAE and KSA (Stripe MENA launched 2024)
- **Mada** (Saudi national debit network) — handled via Hyperpay, Checkout.com, PayTabs, Network International
- **Tabby, Tamara** (BNPL, dominant in GCC e-commerce)
- **Apple Pay, Google Pay** (very high penetration in UAE/KSA)
- **STC Pay, urpay** (KSA wallets)
- **Network International, Telr** (regional gateways)
- **Cash on arrival** — still common for hotels in KSA secondary cities

**Plugin status today:** Stripe ✅. Mada/Tabby/Tamara via Checkout.com or Hyperpay = a plugin to ship, ~40 hrs work, sellable at €299 one-time given the higher local willingness-to-pay.

### Arabic + RTL — the must-fix gap

This is the **single biggest product investment** to make the GCC opening real.

- All current FE-admin and FE-user surfaces are LTR.
- Vue + Vite app needs RTL CSS strategy: either logical properties (margin-inline-start etc.) or a `[dir=rtl]` override sheet.
- Effort estimate: **40–60 hrs** for fe-user (customer-facing), **30 hrs** for fe-admin (lower priority — admin can stay English in Y1).
- Translation: English → Arabic ~3,000 strings; budget €500–1,000 to a freelance translator.
- Without this: **the GCC channel does not open.** A reseller agency in Riyadh will not pitch a non-RTL platform to a Saudi hotel.

### GCC channel partner candidates

- **GCG Enterprise Solutions** (Dubai) — broader IT, occasional hospitality
- **Apex Hosting / Apex Hotel Tech** (UAE)
- **Magnetic, Bayanat, Wunderman Thompson MENA** — full-service agencies with hotel clients
- **Local Riyadh + Jeddah dev studios** — surge of new shops post-Vision 2030; identifiable via LinkedIn / ArabNet / STEP Conference attendee lists
- **Halal-tourism niche specialists** — Umrah app/portal builders (a specialised sub-segment)

### Y1 GCC revenue model

Lower volume but higher per-deal value due to local willingness-to-pay.

| Revenue line | Y1 estimate |
|---|---|
| 2 reseller agencies × €1,499 Pro | €3,000 |
| 1 reseller agency × €4,999 Enterprise | €5,000 |
| Direct boutique-hotel/spa licenses via agencies: 4 × €1,499 Pro | €6,000 |
| Halal-tourism/Umrah DMC: 1 Enterprise × €4,999 | €5,000 |
| Mada/Tabby plugin sales: 15 × €299 | €4,500 |
| **Y1 GCC total** | **~€23,500** |

GCC is a **slow-burn, high-value** market. Y2 is where it really compounds — Vision 2030 hotel openings ramp through 2026–2030.

---

## 7. The wellness/spa angle (best fit, deserves its own section)

Wellness is **a better fit than hotels** for VBWD's existing primitives, and worth pitching independently across all three geos.

### Why wellness fits VBWD better than hotels

| VBWD primitive | Why a spa chain needs it more than a hotel |
|---|---|
| **Token economy** | Spa packages are *naturally* prepaid: "10-massage package", "monthly unlimited yoga". Hotels rarely sell room nights as bundled prepaid units. |
| **Booking plugin (slot-based)** | Spa appointments are slot bookings (60-min, 90-min, room-as-resource). This is the plugin's primary use case. Hotel night-bookings are more inventory-style. |
| **Subscriptions** | "Wellness club membership" with recurring billing — plug-and-play. Hotels don't subscribe. |
| **CMS** | Spa marketing (treatment menu, therapist bios, package promos) is content-heavy. Hotels have it too but their PMS rarely owns the website. |
| **No PMS gap** | Spas don't need a hotel PMS, so the "missing channel manager / housekeeping" gap is irrelevant. **VBWD is feature-complete for a spa.** |

### The wellness segments worth targeting

| Segment | Geos | Estimated count | Why they buy |
|---|---|---|---|
| Boutique day-spa chains (3–15 locations) | Thailand (huge), UAE (growing), Vietnam (emerging) | Hundreds across the three geos | Need centralised booking + loyalty across locations |
| Yoga / pilates / fitness studio chains | All three | Hundreds | Membership management + class booking |
| Medical wellness (IV drips, aesthetic clinics) | UAE especially | Hundreds in Dubai/Abu Dhabi alone | Premium pricing, strong willingness-to-pay |
| Retreat operators (week-long packages) | Thailand (Koh Phangan, Chiang Mai), UAE, Bali-adjacent | Hundreds | Multi-day package builder + voucher delivery |
| Halal-friendly wellness (gender-segregated, prayer-time-aware) | KSA, UAE | Growing | Underserved by Western SaaS |

### Wellness pitch one-liner

> "Your spa, your bookings, your loyalty cards — on your domain, in your customers' language and currency, with prepaid packages and memberships. No per-booking commission. €499/year."

Reuse the existing hotel deck (`decks/hotel/`) as the structural template, swap "rooms" for "treatments" and "OTAs" for "third-party booking apps". One designer-hour of work. Ship as `decks/wellness/`.

### Wellness Y1 revenue inside the geo numbers

Already counted in the per-geo tables above. The reason wellness numbers are conservative: **the agencies are the bottleneck**, not the demand. With 8–15 agencies recruited in Y1, they each onboard 3–8 wellness clients in Y1 — that ceiling is what caps the number.

---

## 8. Channel-led distribution (no founder calls — the "respect the constraint" section)

The entire geo plan dies if you take a single Zoom call. Every channel below is async-by-design.

### Channel A — Cold email to local agencies (one-shot, no call)

- 30 agencies per geo (90 total), pulled from LinkedIn + Tech in Asia + ArabNet + local dev directories.
- One-paragraph pitch, **personalised by name + agency website + one specific hotel/spa client they shipped**.
- Pitch shape: "I've built a self-hosted hospitality platform that you can resell to your hotel/spa clients under your own brand. Pro license €1,499/yr, Enterprise €4,999/yr with white-label. You charge the client €200–500/mo. Demo + docs + reseller pack: [link]. No call needed — everything is in the link."
- **Hard rule**: if the agency replies asking for a call, send the demo URL + the YouTube walkthrough + a Calendly-free async-feedback form. If they insist on a call, decline politely: "I'm solo and async-only; if the docs and demo aren't enough I'm probably the wrong vendor."
- Expected conversion: 2–5 reseller signups per geo from a 30-email batch.
- Time cost: 4 hrs research + 4 hrs writing per geo = 24 hrs total. One burst weekend.

### Channel B — Hire one local part-time freelancer per geo

This is the single biggest unlock for the geo plan and the only paid expense.

- **Per geo**: hire 1 freelancer for **€300–€500/month** (rates are realistic in TH/VN; closer to €700 in UAE/KSA).
- Their job (async-only, async-reporting, monthly Loom updates):
  - Translate landing page + key admin strings to local language
  - Be the local face on local forums (Pantip Thailand, Vietnamese tech FB groups, Saudi Telegram)
  - Triage local-language inbound to Discord
  - Write 1 blog post/month in local language targeting local search terms
  - Optionally: build the local payment rail plugin (paid as one-shot project on top of retainer)
- **Where to find them**: Upwork (still works for this), local marketplaces (Fastwork TH, Freelancer.vn, Bawabba SA), Twitter/X dev community, Discord
- Total monthly cost across 3 geos: **€1,000–€1,500**
- **Important: this is the *only* place the plan trades cash for time.** It's worth it because each freelancer-hour replaces a founder-hour you don't have.

### Channel C — Self-hosted directory / marketplace listings (already in plan 01)

- Cloudron, Coolify, Easypanel, Awesome-selfhosted listings cover the global self-hoster audience including SE Asia tinkerers and Saudi engineers. **Already in plan 01 weeks 11–12. No change.**

### Channel D — Regional content SEO (long-tail compounder)

- 1 article per month in English targeting:
  - "Cloudbeds alternative Thailand"
  - "self-hosted hotel booking engine"
  - "Hotelogix vs [X]"
  - "ezCloud alternative Vietnam English"
  - "spa management software UAE Arabic"
- Plus 1 article per month in **local language** written by the local freelancer (Channel B)
- 12-month outcome: 24 articles total, 3–6 of which rank top-10 on long-tail keywords → 50–200 monthly organic visits on each = compounding inbound that **never asks you for a call**

### Channel E — Local conferences (no attendance, content only)

- Skip physical attendance (time + travel = blows the constraint).
- BUT: write a content piece per major regional event ("3 things missing from this year's HITEC Asia / Future Hospitality Riyadh / VITM Hanoi"). Tag the speakers/exhibitors. Some will reply. Async ROI.

### What you do NOT do

| Forbidden | Why |
|---|---|
| Travel to Bangkok/Dubai/HCMC for "intro meetings" | Day job + family + the math says it doesn't pay back |
| Take Zoom calls with hotel/spa owners | They want sync support; you can't supply it; channel partner takes the call instead |
| Send sales reps / hire a BDR | Burns cash, requires management overhead you don't have |
| Localise to all 3 languages before validating any geo | Each language is a 60+ hour commitment; do them sequentially as resellers sign |
| Promise compliance certifications (PCI L1, ISO 27001, NCA Saudi) you haven't earned | Stay honest; let agencies handle "their hosting, their cert" |
| Run or bill hosting for any venue yourself | The agency hosts on its own infra and bills the venue; none of that margin is yours. Managed-hosting fallback is Elest.io (per plan 01), never you. Spinning up one VPS for one venue sets a precedent that breaks the constraint. |
| Offer an uptime SLA to a venue or agency | SLAs in this plan are response-time only. You cannot promise uptime for software someone else hosts. |

---

## 9. Revenue overlay on top of plan 01

| | Plan 01 base (revised, post-hosting-cut) | Geo overlay (this doc) | Combined |
|---|---|---|---|
| **Y1 brutto** | ~€100k | +€15–30k (mid: €25k) | **€115–130k** |
| **Y2 brutto** | ~€220k | +€60–100k (mid: €80k) | **€280–320k** |
| **24-month cumulative** | ~€320k | +€85–120k | **€405–440k** |

The plan 01 base figures here match the revised `01-next-90-days-plan.md` after the own-brand managed-hosting line was cut and replaced with hosting-platform rev-share + the async priority-support add-on. The geo overlay numbers are unchanged because the per-geo tables never contained a hosting line in the first place.

**The geo overlay is not the path to €100k Y1 — plan 01 is.** The geo overlay is the **insurance** against plan 01 underperforming, AND the lever that makes the €300k 24-month target comfortable rather than tight.

### Cost overlay

| Item | Monthly | Annual |
|---|---|---|
| 3 local freelancers @ ~€450 avg | €1,350 | €16,200 |
| RTL + Arabic translation (one-shot, Y1 Q3) | – | €1,500 |
| PromptPay + TrueMoney plugin dev (one-shot, by TH freelancer) | – | €800 |
| Mada + Tabby plugin dev (one-shot, by GCC freelancer) | – | €1,200 |
| Vietnam payment rail plugin (one-shot) | – | €800 |
| **Y1 total geo cost** | – | **~€20,500** |

**Net Y1 geo contribution: €25k – €20.5k = ~€4.5k.** That's intentional. Y1 funds the geo build-out; **Y2 is where it pays back hard**: €80k revenue – €18k cost = **€62k net incremental in Y2**.

If Y1 freelancer costs feel too high: **start with one geo (Thailand)**, prove the reseller model with 2 agencies, then layer the others in Y1 H2.

---

## 10. 90-day execution overlay (on top of plan 01's 90-day plan)

Plan 01 takes priority. The geo work below fits in the **slack hours** of those weeks (~2–3 hrs/week of the 10–12 total) and the **monthly burst weekend**.

| Week | Geo task | Hours |
|---|---|---|
| 1–2 | Decide: which 1 geo do you start in? **Recommend Thailand** (largest TAM, Stripe live, dense agency scene, wellness fit). | 1 |
| 3–4 | Pull and qualify list of 30 Thai agencies (LinkedIn + Fastwork + agency directory sites) | 3 |
| 5 | Hire ONE Thailand freelancer (€350–500/mo). Brief them: localise landing page hero + Stripe Checkout + 5 key admin labels to Thai. | 2 |
| 6 | Send the 30 cold emails to Thai agencies. One paragraph each, personalised. **Include reseller pack PDF** (single page: pricing, white-label rights, link to demo + docs). | 4 |
| 7–8 | (Slack hours) Reply to inbound from cold emails async. Refer any "let's call" requests to the docs + demo. **Hard no on calls.** | 2 |
| 9–10 | Plan 01's launch week — geo work pauses except Thai freelancer continues. | 0 |
| 11 | Pull Vietnam agency list (15 agencies — smaller market). Hire VN freelancer. | 3 |
| 12 | Send Vietnam outreach. Begin scoping RTL + Arabic translation (post the gig on Upwork; quotes only). | 3 |

**90-day output (geo-specific):**
- 1–2 Thai reseller agency signups (€1,500–€10,000 in license fees)
- Thai-localised landing page live
- Vietnam outreach in progress
- GCC RTL plan scoped, vendor selected, ready to start Q2

**90-day revenue from geo overlay: €1,500 – €10,000.** Realistic.

---

## 11. Risks (geo-specific)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Local agencies say "we already use [Cloudbeds / ezCloud], why switch?" | High | Lost reseller deal | Don't pitch as switch — pitch as *additional* white-label revenue stream. Their existing PMS clients don't need to change. |
| Reseller agency wants exclusivity in geo | Medium | Limits market | Decline exclusivity; offer "preferred partner" badge instead. Multiple agencies > one exclusive. |
| Currency volatility (THB, VND especially) | Medium | -10–20% on local-currency revenue | Price licenses in EUR/USD; agencies handle local-currency markup |
| Stripe pulls Vietnam workaround / changes Saudi terms | Low–Med | One geo crippled | Multi-payment-gateway architecture is the mitigation; YooKassa for sanctions-resilient backup |
| RTL implementation has hidden Vue/Vite gotchas | Medium | +30 hrs of unplanned work | Budget +50% on Arabic ETA; ship admin LTR-only in Y1 |
| Freelancer ghosts you / quality drops | Medium | Lost month per geo | Standard freelancer hygiene: monthly Loom check-ins, milestone-based payments, replaceable in 2 weeks |
| Saudi NCA cybersecurity rules require local datacentre | Becoming binding | Forces VBWD to be hosted on Saudi soil for KSA hotel data | This is a *feature* — VBWD self-hosted on Khazna/STC = fully compliant. Position as advantage. |
| Your day-job employer notices you have foreign income | Geo-specific | Tax + employment-contract issue | Sole proprietorship / SRL / proper invoicing infrastructure must exist before first foreign reseller signs. **Resolve before week 6.** |
| Halal-tourism segment requires religious advisory you can't provide | Certain | Lost deals if pitched directly | Channel through Saudi/UAE freelancer + agency; you stay one step removed |
| Cultural mismatch: SE Asian / Gulf buyers expect relationship-driven sales | Certain | Direct pitch fails | Channel-only — agency is the relationship; you are the vendor behind the agency |
| You learn that one geo is dead-end at month 6 | Likely (1 of 3 geos won't work) | -€5k freelancer cost | Cut the freelancer in that geo, redeploy the budget to the working ones |

---

## 12. Decision points

**Month 3 (after first geo outreach wave):**
- Did Thailand produce ≥ 1 reseller signup? If no, the cold-email pitch is wrong (revise) OR Thailand isn't the right starter geo (try Vietnam or skip to GCC).
- Is the Thai freelancer producing? If no, replace within 30 days.

**Month 6:**
- ≥ 3 active reseller agencies across all geos? If yes, on track. If no, the channel model isn't taking — consider going direct in 1 geo with just the localised landing page + freelancer-supported Discord, accept slower ramp.
- Has any reseller actually onboarded a paying hotel/spa? If no after 90 days, the agencies aren't really resellers — they're sitting on the license. Audit and prune.

**Month 9:**
- Is RTL shipped? If no, kill the GCC plan, refund any GCC reseller deposits, refocus on TH+VN.

**Month 12:**
- Geo overlay net contribution to Y1 revenue ≥ €15k? If yes, double the freelancer budget for Y2 and add a 4th geo (recommend Indonesia or Malaysia — lower TAM but lower competition). If no, geo overlay is a bust; cancel freelancers, refund any goodwill, refocus on plan 01 base.

---

## 13. Immediate next actions (this week, geo-specific)

In order, additive to plan 01's "this week" list:

1. **Confirm the geo starter:** Thailand (recommended) — or override with reasoning.
2. **Draft the agency reseller one-pager** (PDF): pricing tiers, white-label rights, what they get, what you don't do (no support, no calls, no SLA without Enterprise tier). 1 hour.
3. **Set up business entity invoicing** capable of receiving foreign B2B payments (Stripe Connect, Wise Business, or local equivalent in your jurisdiction). Confirm employer contract permits this.
4. **Post the freelancer gig** for Thailand (Upwork or Fastwork). Spec: Thai-native, web-dev background, will translate landing page + key strings, ~10 hrs/week, €350–500/mo. 30 min to write the post.
5. **Pull the first 30 Thai agency contacts** from LinkedIn (filter: Bangkok + 10–50 employees + "hospitality" or "hotel" in case studies). 2 hours.

That's it for the geo overlay this week. Plan 01's "this week" list still takes priority.
