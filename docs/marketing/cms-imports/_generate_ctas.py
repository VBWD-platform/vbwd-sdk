#!/usr/bin/env python3
"""Append CTA pages to each vertical's pages.json.

Three CTA pages per vertical, written to match the existing page format
emitted by _generate.py (same shared CSS surface, same vbwd-page classes,
same per-vertical accent colour):

    cta-contact   "Talk to us"  — calendar / email / GitHub-issue paths
    cta-buy       "Buy now"     — four-tier pricing (Community / Starter / Pro / Enterprise)
    cta-partner   "Become a partner" — Registered / Certified / Premier tiers

The CTAs are vertical-flavoured: copy is light-touched per vertical so the
same prospect lands somewhere coherent whether they came in via /hotel,
/doctor, /shop, /ghrm or /main.

Run:
    python docs/marketing/cms-imports/_generate_ctas.py

Idempotent — re-running replaces previous CTA pages without touching the
existing about / features / integrations / payment-modules pages.
"""
import json
from pathlib import Path

OUTPUT_ROOT = Path(__file__).parent


# ── Vertical configs (mirrored from _generate.py) ────────────────────────────

VERTICALS = {
    "core": {
        "title": "VBWD",
        "emoji": "⚡",
        "accent": "#2563eb", "accent_soft": "#dbeafe", "accent_dark": "#1d4ed8",
        "gradient": "linear-gradient(135deg, #1d4ed8 0%, #5b21b6 100%)",
        "audience": "software engineers, SaaS builders and digital agencies",
        "contact_lead":  "Where the conversation starts. Bring your stack, your billing question, your timeline.",
        "buy_lead":      "Self-hosted, annual licence, no usage limits, no per-transaction fees.",
        "partner_lead":  "If you build digital products for clients, VBWD is a product you can resell.",
        "demo_path":     "/demo",
        "partner_label": "digital agency",
    },
    "softwarestore": {
        "title": "VBWD Software Store",
        "emoji": "\U0001f6cd",
        "accent": "#7c3aed", "accent_soft": "#ede9fe", "accent_dark": "#5b21b6",
        "gradient": "linear-gradient(135deg, #7c3aed 0%, #db2777 100%)",
        "audience": "digital creators, subscription boxes, niche marketplaces",
        "contact_lead":  "Pitch your store stack in a 30-minute call. We'll show your fees-vs-VBWD math live.",
        "buy_lead":      "Sell software, downloads, license keys. Keep the 5–10% Gumroad / LemonSqueezy would take.",
        "partner_lead":  "Build VBWD stores for your creator clients. Keep 20–30% of every license.",
        "demo_path":     "/shop/demo",
        "partner_label": "creator-economy agency",
    },
    "hotel": {
        "title": "VBWD Hotel",
        "emoji": "\U0001f3e8",
        "accent": "#0d9488", "accent_soft": "#ccfbf1", "accent_dark": "#115e59",
        "gradient": "linear-gradient(135deg, #0d9488 0%, #0284c7 100%)",
        "audience": "independent hotels and boutique chains",
        "contact_lead":  "Thirty minutes. Live on your property's website. Multilingual checkout, regional payments, the OTA-savings math on your numbers.",
        "buy_lead":      "One licence per property. No per-booking fee. Hosts on your VPS, on your data, on your brand.",
        "partner_lead":  "Hotel-tech agencies: resell VBWD to your portfolio. Build the channel-manager adapter and own that gap.",
        "demo_path":     "/hotel/demo",
        "partner_label": "hotel-tech agency",
    },
    "doctor": {
        "title": "VBWD Doctor",
        "emoji": "⚕️",
        "accent": "#059669", "accent_soft": "#d1fae5", "accent_dark": "#047857",
        "gradient": "linear-gradient(135deg, #059669 0%, #0891b2 100%)",
        "audience": "clinic networks and lab networks (B2B2B)",
        "contact_lead":  "Network-level briefing. We're sold to clinic groups and lab networks, not individual practitioners.",
        "buy_lead":      "Per-network licensing. Multi-site routing built in. Compliance work is partner-led — we ship the platform.",
        "partner_lead":  "Healthcare-IT agencies: VBWD is a billing + patient-portal platform you can layer your HIPAA / GDPR work on.",
        "demo_path":     "/doctor/demo",
        "partner_label": "healthcare-IT agency",
    },
    "ghrm": {
        "title": "VBWD GHRM",
        "emoji": "\U0001f9ed",
        "accent": "#ea580c", "accent_soft": "#ffedd5", "accent_dark": "#c2410c",
        "gradient": "linear-gradient(135deg, #ea580c 0%, #dc2626 100%)",
        "audience": "OSS maintainers and small dev teams monetising repos",
        "contact_lead":  "Show us your repo. We'll walk through how access grants + token billing wire together in a 30-minute call.",
        "buy_lead":      "Sell access to your private repos. Tokens for downloads, gates for trial users, automated GitHub role grants on payment.",
        "partner_lead":  "Build VBWD-GHRM deployments for OSS-monetisation clients. Niche but high-velocity.",
        "demo_path":     "/ghrm/demo",
        "partner_label": "dev-tools agency",
    },
}


# ── Shared CSS (matches the surface emitted by _generate.py) ────────────────

CSS_TEMPLATE = """\
.vbwd-page{--vbwd-accent:%ACCENT%;--vbwd-accent-soft:%ACCENT_SOFT%;--vbwd-accent-dark:%ACCENT_DARK%;\
--vbwd-gradient:%GRADIENT%;--vbwd-text:#0f172a;--vbwd-text-muted:#475569;--vbwd-surface:#fff;\
--vbwd-surface-soft:#f8fafc;--vbwd-border:#e2e8f0;--vbwd-radius:14px;--vbwd-radius-lg:22px;\
font-family:'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;\
color:var(--vbwd-text);line-height:1.65;font-size:17px;-webkit-font-smoothing:antialiased}\
.vbwd-page *,.vbwd-page *::before,.vbwd-page *::after{box-sizing:border-box}\
.vbwd-page h1,.vbwd-page h2,.vbwd-page h3,.vbwd-page h4{color:#0b1220;line-height:1.2;\
letter-spacing:-0.02em;margin:0 0 .65em;font-weight:700}\
.vbwd-page h1{font-size:clamp(2.2rem,4vw,3.25rem);font-weight:800}\
.vbwd-page h2{font-size:clamp(1.5rem,2.4vw,2rem);margin-top:.4em}\
.vbwd-page h3{font-size:1.2rem}.vbwd-page p{margin:0 0 1em;color:var(--vbwd-text)}\
.vbwd-page a{color:var(--vbwd-accent-dark);text-decoration:none;font-weight:600}\
.vbwd-page a:hover{text-decoration:underline;text-underline-offset:3px}\
.vbwd-page code{font-family:'JetBrains Mono',ui-monospace,SFMono-Regular,Menlo,monospace;\
background:var(--vbwd-accent-soft);color:var(--vbwd-accent-dark);padding:.15em .45em;border-radius:6px;\
font-size:.9em;font-weight:500}\
.vbwd-page .vbwd-container{max-width:1080px;margin:0 auto;padding:0 1.5rem}\
.vbwd-page .vbwd-hero{background:var(--vbwd-gradient);color:#fff;padding:clamp(3.5rem,8vw,6rem) 1.5rem;\
text-align:center;position:relative;overflow:hidden;border-radius:var(--vbwd-radius-lg);margin:0 1rem 3rem}\
.vbwd-page .vbwd-hero__eyebrow{display:inline-block;padding:.35rem .9rem;border-radius:999px;\
background:rgba(255,255,255,.18);color:#fff;font-size:.78rem;font-weight:600;letter-spacing:.1em;\
text-transform:uppercase;margin-bottom:1.25rem;backdrop-filter:blur(4px)}\
.vbwd-page .vbwd-hero h1{color:#fff;margin-bottom:.65rem;text-shadow:0 2px 8px rgba(0,0,0,.18)}\
.vbwd-page .vbwd-hero__lead{color:rgba(255,255,255,.95);font-size:clamp(1.05rem,1.6vw,1.25rem);\
max-width:720px;margin:0 auto}\
.vbwd-page section{padding:2.5rem 0}\
.vbwd-page section+section{border-top:1px solid var(--vbwd-border)}\
.vbwd-page .vbwd-eyebrow{display:inline-block;color:var(--vbwd-accent-dark);background:var(--vbwd-accent-soft);\
padding:.25rem .7rem;border-radius:999px;font-size:.78rem;font-weight:700;letter-spacing:.08em;\
text-transform:uppercase;margin-bottom:.9rem}\
.vbwd-page .vbwd-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:1rem;margin:1.25rem 0 0}\
.vbwd-page .vbwd-card{background:var(--vbwd-surface);border:1px solid var(--vbwd-border);\
border-radius:var(--vbwd-radius);padding:1.25rem 1.35rem;position:relative;overflow:hidden;\
box-shadow:0 1px 2px rgba(15,23,42,.06),0 1px 3px rgba(15,23,42,.08)}\
.vbwd-page .vbwd-card::before{content:'';position:absolute;left:0;top:0;bottom:0;width:3px;\
background:var(--vbwd-accent);opacity:.7}\
.vbwd-page .vbwd-card__title{font-weight:700;color:var(--vbwd-text);margin-bottom:.35rem;font-size:1.02rem}\
.vbwd-page .vbwd-card__desc{color:var(--vbwd-text-muted);font-size:.94rem;line-height:1.55;margin:0}\
.vbwd-page .vbwd-tier{background:var(--vbwd-surface);border:1px solid var(--vbwd-border);\
border-radius:var(--vbwd-radius);padding:1.5rem;margin-bottom:1rem;position:relative}\
.vbwd-page .vbwd-tier__name{font-weight:800;font-size:1.15rem;color:var(--vbwd-accent-dark);margin-bottom:.25rem}\
.vbwd-page .vbwd-tier__price{font-size:1.6rem;font-weight:800;color:#0b1220;margin-bottom:.5rem;line-height:1}\
.vbwd-page .vbwd-tier__desc{color:var(--vbwd-text-muted);margin-bottom:.75rem}\
.vbwd-page .vbwd-tier--featured{border-color:var(--vbwd-accent);border-width:2px;\
box-shadow:0 8px 16px -4px rgba(15,23,42,.10)}\
.vbwd-page .vbwd-tier--featured::after{content:'Most popular';position:absolute;top:-12px;right:16px;\
background:var(--vbwd-accent);color:#fff;font-size:.7rem;font-weight:700;letter-spacing:.08em;\
text-transform:uppercase;padding:.3rem .75rem;border-radius:999px}\
.vbwd-page .vbwd-callout{background:var(--vbwd-accent-soft);border-left:4px solid var(--vbwd-accent);\
border-radius:var(--vbwd-radius);padding:1.1rem 1.35rem;margin:1.5rem 0 0;color:var(--vbwd-text)}\
.vbwd-page .vbwd-callout p{margin:0}\
.vbwd-page .vbwd-btn{display:inline-flex;align-items:center;gap:.5rem;padding:.75rem 1.35rem;\
background:var(--vbwd-accent);color:#fff;border-radius:10px;font-weight:700;font-size:.95rem;\
box-shadow:0 4px 6px -1px rgba(15,23,42,.08)}\
.vbwd-page .vbwd-btn:hover{filter:brightness(1.08);text-decoration:none}\
.vbwd-page .vbwd-btn--ghost{background:transparent;color:var(--vbwd-accent-dark);\
border:1.5px solid var(--vbwd-accent)}\
.cms-layout .cms-widget--header-nav,.cms-layout .cms-widget--footer-nav,\
.cms-layout .cms-area--vue .cms-breadcrumb{max-width:1100px;margin-left:auto;margin-right:auto}\
.cms-layout .cms-area--vue .cms-breadcrumb{padding-left:16px}\
@media(max-width:640px){.vbwd-page{font-size:16px}\
.vbwd-page .vbwd-hero{margin:0 .5rem 2rem;padding:2.75rem 1rem}\
.vbwd-page .vbwd-container{padding:0 1.1rem}}
"""


# ── Page template wrappers ──────────────────────────────────────────────────

def hero(cfg, eyebrow, h1, lead):
    return (
        f'<header class="vbwd-hero">'
        f'<span class="vbwd-hero__eyebrow">{eyebrow}</span>'
        f'<h1>{cfg["emoji"]} {h1}</h1>'
        f'<p class="vbwd-hero__lead">{lead}</p>'
        f'</header>'
    )


# ── Page 1: cta-contact ─────────────────────────────────────────────────────

def page_cta_contact(cfg):
    title = cfg["title"]
    html = (
        f'<article class="vbwd-page vbwd-page--cta-contact">'
        + hero(cfg, "Talk to us", title, cfg["contact_lead"]) +
        f'<div class="vbwd-container">'
        f'<section>'
        f'<span class="vbwd-eyebrow">Bring this to the call</span>'
        f'<h2>Thirty minutes, real answers</h2>'
        f'<p>We are a small team. The fastest path from "interesting" to "we can do this" '
        f'is a single call — your stack, your billing problem, our take, your decision. '
        f'No sales engineering, no deck-driven demo.</p>'
        f'<ul style="margin-top:1rem;padding-left:1.25rem">'
        f'<li><strong>Your stack.</strong> Where does identity live? Current payment provider? Legacy billing tool we need to migrate from?</li>'
        f'<li><strong>Your customer.</strong> Consumer or business? ACV? Annual / monthly / usage-billed?</li>'
        f'<li><strong>Your timeline.</strong> "Ship in 6 weeks" and "scoping next year" both work — just say which.</li>'
        f'<li><strong>Your hardest objection.</strong> Self-hosted? Open source? Compliance? Plugin maintenance? Lead with the scariest part.</li>'
        f'</ul>'
        f'</section>'
        f'<section>'
        f'<span class="vbwd-eyebrow">Three ways to book</span>'
        f'<h2>Pick the channel that fits</h2>'
        f'<div class="vbwd-grid">'
        f'<div class="vbwd-card"><div class="vbwd-card__title">Calendar &mdash; instant slot</div>'
        f'<p class="vbwd-card__desc"><a href="https://vbwd.cc{cfg["demo_path"]}">vbwd.cc{cfg["demo_path"]}</a> &mdash; pick a 30-min slot in the next two weeks.</p></div>'
        f'<div class="vbwd-card"><div class="vbwd-card__title">Email &mdash; async first</div>'
        f'<p class="vbwd-card__desc"><a href="mailto:hello@vbwd.cc">hello@vbwd.cc</a> &mdash; three lines: your stack, your billing question, your timeline.</p></div>'
        f'<div class="vbwd-card"><div class="vbwd-card__title">GitHub Issue &mdash; public</div>'
        f'<p class="vbwd-card__desc">Open an issue in the public repo. Public, citeable, helpful to other readers in your shoes.</p></div>'
        f'</div>'
        f'</section>'
        f'<section>'
        f'<div class="vbwd-callout">'
        f'<p><strong>What we will not do.</strong> Drip sequences. Sales engineers. "Let me loop my AE in." '
        f'You will talk to a builder. If we are not a fit, we will say so and point you at the tool that is. '
        f'<a class="vbwd-btn" href="https://vbwd.cc{cfg["demo_path"]}" style="margin-left:1rem">Book a call &rarr;</a></p>'
        f'</div>'
        f'</section>'
        f'</div>'
        f'</article>'
    )
    return {
        "slug": "cta-contact",
        "name": f"Get in touch — {title}",
        "language": "en",
        "content_json": {"type": "doc", "content": []},
        "content_html": html,
        "source_css": render_css(cfg),
        "is_published": True,
        "sort_order": 100,
        "meta_title":       f"Get in touch — {title}",
        "meta_description": f"Talk to the {title} team. 30-min call. Bring your stack, your billing problem, your timeline.",
        "meta_keywords":    f"vbwd, {cfg['title'].split()[-1].lower()}, contact, demo, sales",
        "og_title":         f"Get in touch — {title}",
        "og_description":   f"Talk to the {title} team. 30-min call. No sales engineering, no scripted demo.",
        "robots": "index,follow",
        "use_theme_switcher_styles": False,
        "required_access_level_ids": [],
    }


# ── Page 2: cta-buy ─────────────────────────────────────────────────────────

def page_cta_buy(cfg):
    title = cfg["title"]
    html = (
        f'<article class="vbwd-page vbwd-page--cta-buy">'
        + hero(cfg, "Buy a license", title, cfg["buy_lead"]) +
        f'<div class="vbwd-container">'
        f'<section>'
        f'<span class="vbwd-eyebrow">Four tiers</span>'
        f'<h2>Annual licence. Self-hosted. No usage limits.</h2>'
        f'<p>The licence is annual and the price is a single number &mdash; no per-seat, '
        f'no per-transaction, no API counters. You self-host on your infrastructure '
        f'(or use our managed hosting). Updates included for the year.</p>'
        f'<div class="vbwd-tier"><div class="vbwd-tier__name">Community</div>'
        f'<div class="vbwd-tier__price">$0 / forever</div>'
        f'<p class="vbwd-tier__desc">Under 5K EUR annual revenue OR fewer than 24 active users. '
        f'All plugins, all payment providers. Community Discord, 48h email support. '
        f'Perfect for solo builders and proofs-of-concept.</p>'
        f'</div>'
        f'<div class="vbwd-tier"><div class="vbwd-tier__name">Starter</div>'
        f'<div class="vbwd-tier__price">$499 / year</div>'
        f'<p class="vbwd-tier__desc">Solo founders and small businesses past the Community thresholds. '
        f'Same code, licensed for commercial scale. 48h email SLA, monthly platform-updates webinar.</p>'
        f'</div>'
        f'<div class="vbwd-tier vbwd-tier--featured"><div class="vbwd-tier__name">Professional</div>'
        f'<div class="vbwd-tier__price">$1,499 / year</div>'
        f'<p class="vbwd-tier__desc">Growing businesses. Multiple plugins activated, '
        f'priority support (8h SLA, Slack channel), monthly architecture check-in, '
        f'early access to new plugins. The right tier for most funded startups.</p>'
        f'</div>'
        f'<div class="vbwd-tier"><div class="vbwd-tier__name">Enterprise</div>'
        f'<div class="vbwd-tier__price">$4,999 / year</div>'
        f'<p class="vbwd-tier__desc">White-label rights, multi-deployment licence, 4h SLA, '
        f'dedicated engineer, weekly check-in, custom plugin development included (40h / year). '
        f'For agencies and platform-of-platforms operators.</p>'
        f'</div>'
        f'</section>'
        f'<section>'
        f'<div class="vbwd-callout">'
        f'<p><strong>Buy now.</strong> '
        f'<a class="vbwd-btn" href="https://vbwd.cc/buy">vbwd.cc/buy &rarr;</a> '
        f'Card payment, instant licence-key delivery, 30-day money-back. Tier upgrades pro-rate.</p>'
        f'</div>'
        f'</section>'
        f'</div>'
        f'</article>'
    )
    return {
        "slug": "cta-buy",
        "name": f"Buy a license — {title}",
        "language": "en",
        "content_json": {"type": "doc", "content": []},
        "content_html": html,
        "source_css": render_css(cfg),
        "is_published": True,
        "sort_order": 110,
        "meta_title":       f"Buy a license — {title}",
        "meta_description": f"{title} licences. Four tiers, annual, self-hosted. Community free, Starter $499/yr, Pro $1,499/yr, Enterprise $4,999/yr.",
        "meta_keywords":    f"vbwd, {cfg['title'].split()[-1].lower()}, buy, license, pricing",
        "og_title":         f"Buy a license — {title}",
        "og_description":   f"{title} licences from $0 (Community) to $4,999 / year (Enterprise). Self-hosted, no usage limits.",
        "robots": "index,follow",
        "use_theme_switcher_styles": False,
        "required_access_level_ids": [],
    }


# ── Page 3: cta-partner ─────────────────────────────────────────────────────

def page_cta_partner(cfg):
    title = cfg["title"]
    html = (
        f'<article class="vbwd-page vbwd-page--cta-partner">'
        + hero(cfg, "Become a partner", title, cfg["partner_lead"]) +
        f'<div class="vbwd-container">'
        f'<section>'
        f'<span class="vbwd-eyebrow">Three tiers</span>'
        f'<h2>Sell {title} to your clients. Keep 20–30%.</h2>'
        f'<p>If you run a {cfg["partner_label"]}, VBWD is a product you can resell. '
        f'You sell the licence and the implementation; we provide the platform, the updates, '
        f'and tier-3 support. Your name on the contract, the client logo on the dashboard.</p>'
        f'<div class="vbwd-tier"><div class="vbwd-tier__name">Registered</div>'
        f'<div class="vbwd-tier__price">Free / year &middot; 20% commission</div>'
        f'<p class="vbwd-tier__desc">Listed in the public partner directory. 20% commission on every licence you sell. '
        f'Partner Slack. Quarterly partner-update webinar. No annual fee. Good for "let us see if this works."</p>'
        f'</div>'
        f'<div class="vbwd-tier vbwd-tier--featured"><div class="vbwd-tier__name">Certified</div>'
        f'<div class="vbwd-tier__price">$999 / year &middot; 25% commission</div>'
        f'<p class="vbwd-tier__desc">Trained and featured. 25% commission, early access to new plugins '
        f'(test with clients before GA), co-marketing budget (case studies, conference talks), '
        f'VBWD-Certified badge on your site, one annual architecture review with our team.</p>'
        f'</div>'
        f'<div class="vbwd-tier"><div class="vbwd-tier__name">Premier</div>'
        f'<div class="vbwd-tier__price">$2,499 / year &middot; 30% commission</div>'
        f'<p class="vbwd-tier__desc">Inbound leads from vbwd.cc routed by geography and specialty. '
        f'Featured listing above all Certified partners. Monthly strategy call. First look at large RFPs. Path to white-label.</p>'
        f'</div>'
        f'</section>'
        f'<section>'
        f'<span class="vbwd-eyebrow">Partner economics</span>'
        f'<h2>One engaged partner, one year</h2>'
        f'<div class="vbwd-grid">'
        f'<div class="vbwd-card"><div class="vbwd-card__title">8 licenses sold (Pro tier)</div>'
        f'<p class="vbwd-card__desc">~$3,000 in commission to you. Your client pays the licence; you keep the implementation revenue on top.</p></div>'
        f'<div class="vbwd-card"><div class="vbwd-card__title">3 clients on managed hosting</div>'
        f'<p class="vbwd-card__desc">~$5,000 / year recurring as a managed-services kicker.</p></div>'
        f'<div class="vbwd-card"><div class="vbwd-card__title">2 clients need custom plugin work</div>'
        f'<p class="vbwd-card__desc">~$15,000–30,000 billed by you at your rate, on top of the licence revenue.</p></div>'
        f'<div class="vbwd-card"><div class="vbwd-card__title">Regional VBWD expert</div>'
        f'<p class="vbwd-card__desc">Become the {cfg["audience"]} go-to in your market. Compounds over years.</p></div>'
        f'</div>'
        f'</section>'
        f'<section>'
        f'<div class="vbwd-callout">'
        f'<p><strong>Apply.</strong> '
        f'<a class="vbwd-btn" href="https://vbwd.cc/partner">vbwd.cc/partner &rarr;</a> '
        f'Review in 5 business days. We look at portfolio and fit, not headcount. We co-sell your first licence with you.</p>'
        f'</div>'
        f'</section>'
        f'</div>'
        f'</article>'
    )
    return {
        "slug": "cta-partner",
        "name": f"Become a partner — {title}",
        "language": "en",
        "content_json": {"type": "doc", "content": []},
        "content_html": html,
        "source_css": render_css(cfg),
        "is_published": True,
        "sort_order": 120,
        "meta_title":       f"Become a partner — {title}",
        "meta_description": f"Resell {title} to your {cfg['partner_label']} clients. Three tiers, 20–30% commission, inbound leads.",
        "meta_keywords":    f"vbwd, {cfg['title'].split()[-1].lower()}, partner, agency, reseller, commission",
        "og_title":         f"Become a partner — {title}",
        "og_description":   f"Sell {title} to your clients. Three tiers — Registered (free), Certified ($999/yr), Premier ($2,499/yr).",
        "robots": "index,follow",
        "use_theme_switcher_styles": False,
        "required_access_level_ids": [],
    }


def render_css(cfg):
    return (
        CSS_TEMPLATE
        .replace("%ACCENT%",      cfg["accent"])
        .replace("%ACCENT_SOFT%", cfg["accent_soft"])
        .replace("%ACCENT_DARK%", cfg["accent_dark"])
        .replace("%GRADIENT%",    cfg["gradient"])
    )


# ── Driver ──────────────────────────────────────────────────────────────────

def append_ctas(vertical_key, cfg):
    target = OUTPUT_ROOT / vertical_key / "pages.json"
    if not target.exists():
        print(f"  skip {vertical_key} — no pages.json")
        return
    existing = json.loads(target.read_text())

    # Drop any previous CTA pages so re-runs stay idempotent.
    cta_slugs = {"cta-contact", "cta-buy", "cta-partner"}
    existing = [p for p in existing if p.get("slug") not in cta_slugs]

    # `core` (vbwd.cc — the platform itself) only ships the partner CTA; the
    # contact/buy funnels are handled elsewhere on the platform site. Every
    # other vertical keeps all three CTAs unchanged.
    if vertical_key == "core":
        cta_pages = [page_cta_partner(cfg)]
    else:
        cta_pages = [page_cta_contact(cfg), page_cta_buy(cfg), page_cta_partner(cfg)]
    target.write_text(json.dumps(existing + cta_pages, indent=2, ensure_ascii=False) + "\n")
    print(f"  + {vertical_key}/pages.json — {len(existing)} existing "
          f"+ {len(cta_pages)} CTA(s) = {len(existing) + len(cta_pages)}")


if __name__ == "__main__":
    print("Appending 3 CTA pages to each vertical's pages.json:")
    for key, cfg in VERTICALS.items():
        append_ctas(key, cfg)
    print("Done.")