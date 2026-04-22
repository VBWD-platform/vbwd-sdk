#!/usr/bin/env python3
"""Generate CMS pages.json import files for each vertical instance.

For every vertical (main/shop/hotel/doctor/ghrm) emits four pages:
    about / features / integrations / payment-modules

Output shape matches CmsPageService.import_pages — see
vbwd-backend/plugins/cms/src/services/cms_page_service.py (_apply_data).

Pages ship with exhibition-grade styling baked into `source_css` so they
render polished with or without the theme-switcher plugin.

Run:
    python docs/marketing/cms-imports/_generate.py
"""
import json
from pathlib import Path
from textwrap import dedent

OUTPUT_ROOT = Path(__file__).parent


# ── Payment methods catalogue (3 implemented + 20 planned = 23 total) ────────

PAYMENT_METHODS_IMPLEMENTED = [
    ("Stripe", "Cards, Apple/Google Pay, SCA-compliant checkout, webhooks, plan sync.",
     "stripe", "global"),
    ("PayPal", "Orders API, capture flow, webhooks — trusted buyer-protection brand.",
     "paypal", "global"),
    ("YooKassa", "Russian-market payments (Yandex). Bank cards, SberPay, SBP QR.",
     "yookassa", "ru"),
]

PAYMENT_METHODS_PLANNED = [
    ("Adyen", "Unified enterprise gateway — cards, local methods, tokenisation.",
     "adyen", "global"),
    ("Braintree", "PayPal-owned gateway, vault support, Venmo in the US.",
     "braintree", "global"),
    ("Square", "In-person + online, strong for retail and food-service verticals.",
     "square", "us/ca/uk/au"),
    ("Razorpay", "Indian-market gateway — UPI, Netbanking, EMI, RuPay.",
     "razorpay", "in"),
    ("Mollie", "European gateway — iDEAL, Bancontact, SEPA, SOFORT, credit cards.",
     "mollie", "eu"),
    ("Klarna", "Buy-now-pay-later instalments and pay-in-30 plans.",
     "klarna", "eu/us"),
    ("Paddle", "Merchant-of-record handling EU/UK VAT and US sales tax automatically.",
     "paddle", "global"),
    ("Authorize.Net", "Long-standing US gateway, Visa-owned, strong for B2B card-not-present.",
     "authorizenet", "us/ca"),
    ("2Checkout (Verifone)", "Global checkout with 200+ payment methods and 45 currencies.",
     "twocheckout", "global"),
    ("Wise Business", "International payouts at mid-market rates, multi-currency accounts.",
     "wise", "global"),
    ("Revolut Business", "EU/UK business accounts, card acquiring, crypto on-ramp.",
     "revolut", "eu/uk"),
    ("Coinbase Commerce", "Accept BTC, ETH, USDC — non-custodial with instant settlement.",
     "coinbase", "global"),
    ("BitPay", "Crypto invoicing with auto-conversion to fiat for accounting.",
     "bitpay", "global"),
    ("Apple Pay (direct)", "Merchant-of-record Apple Pay without a gateway intermediary.",
     "apple-pay", "global"),
    ("Google Pay (direct)", "Direct Google Pay tokenisation; pairs with any processor.",
     "google-pay", "global"),
    ("Alipay", "China's leading wallet — QR and web checkout.",
     "alipay", "cn/apac"),
    ("WeChat Pay", "Tencent's dominant mobile wallet for the Chinese market.",
     "wechat-pay", "cn/apac"),
    ("SEPA Direct Debit", "Low-cost recurring euro pulls under the SEPA mandate scheme.",
     "sepa", "eu"),
    ("iDEAL", "Dutch bank-transfer standard — near-zero fees, instant confirmation.",
     "ideal", "nl"),
    ("Sofort / Bancontact", "DACH and Belgian online-banking rails, popular for one-off purchases.",
     "sofort", "de/at/be"),
]


# ── Vertical definitions ────────────────────────────────────────────────────
#
# Each vertical has its own accent colour (`accent` + `accent_soft`) so the
# pages feel distinct at a glance in an exhibition setting.

VERTICALS = {
    "main": {
        "title": "VBWD",
        "tagline": "The open-source SaaS billing platform, on your own server.",
        "hero": "The open-source SaaS billing platform, run on your own server.",
        "audience": "indie developers, agencies and internal platform teams",
        "accent": "#2563eb",        # blue-600
        "accent_soft": "#dbeafe",   # blue-100
        "accent_dark": "#1d4ed8",   # blue-700
        "gradient": "linear-gradient(135deg, #2563eb 0%, #7c3aed 100%)",
        "emoji": "\u26a1",  # lightning
        "plugins_enabled": [
            ("landing1", "Embeddable marketing landing with pricing widget."),
            ("cms", "Pages, categories, image uploads, slug routing."),
            ("chat", "LLM chat with token metering (OpenAI-compatible)."),
            ("theme-switcher", "Five CSS-var presets with zero regressions when off."),
            ("analytics", "Active sessions, revenue snapshots, domain-event log."),
            ("stripe", "Cards, Apple/Google Pay, webhooks, plan sync."),
            ("paypal", "Orders + capture + webhook flow."),
            ("yookassa", "Russian-market payment rail."),
        ],
        "plugins_planned": [
            ("ghrm", "GitHub Repo Manager — turn any repo into a paid product."),
            ("pdf-invoice", "Server-side PDF invoice generation."),
            ("celery", "Async task queue for long-running jobs."),
        ],
        "integrations": [
            ("SMTP / Postmark / SendGrid", "Transactional email — password resets, invoices, webhook notifications."),
            ("Mailchimp", "Newsletter sync for onboarded users."),
            ("OpenAI-compatible LLMs", "OpenAI, Azure OpenAI, local Ollama, LM Studio, vLLM."),
            ("S3-compatible storage", "Future-proof swap-in for the CMS image store."),
            ("GitHub / GitLab", "GHRM plugin for OSS publishing, releases, issue tracking."),
            ("Zapier / n8n via webhooks", "Outbound webhooks on every subscription lifecycle event."),
        ],
    },
    "shop": {
        "title": "VBWD Shop",
        "tagline": "Self-hosted subscription commerce and a digital-goods storefront.",
        "hero": "A self-hosted subscription commerce and digital-goods storefront.",
        "audience": "digital creators, subscription box operators, niche marketplaces",
        "accent": "#7c3aed",        # violet-600
        "accent_soft": "#ede9fe",
        "accent_dark": "#5b21b6",
        "gradient": "linear-gradient(135deg, #7c3aed 0%, #db2777 100%)",
        "emoji": "\U0001f6cd",  # shopping bags
        "plugins_enabled": [
            ("cms", "Product pages, categories, blog, landing."),
            ("theme-switcher", "White-label branding per merchant."),
            ("stripe", "Primary card acquirer."),
            ("paypal", "Buyer-protection rail."),
            ("mollie", "EU checkout — iDEAL, Bancontact, SEPA, SOFORT."),
            ("token-bundles", "Credit packs for metered digital-asset downloads."),
            ("analytics", "Conversion, churn, LTV dashboards."),
        ],
        "plugins_planned": [
            ("shipping-labels", "EasyPost / Shippo integration for physical subscription boxes."),
            ("marketplace", "Multi-vendor + Stripe Connect payouts."),
            ("reviews", "Star ratings and written reviews on product pages."),
            ("license-keys", "Per-purchase license key generation."),
        ],
        "integrations": [
            ("EasyPost / Shippo", "Shipping label generation and tracking webhooks (planned)."),
            ("Stripe Connect", "Multi-vendor payout splits (planned marketplace mode)."),
            ("Mailchimp / Klaviyo", "Abandoned-cart and lifecycle email."),
            ("Google / Facebook Pixel", "Conversion tracking on checkout events."),
            ("Algolia / Typesense", "Search over product catalogues (planned)."),
            ("Bunny.net / Cloudflare R2", "Digital-asset delivery for paid downloads."),
        ],
    },
    "hotel": {
        "title": "VBWD Hotel",
        "tagline": "Bookings, rooms and guest billing from a single self-hosted stack.",
        "hero": "Run bookings, rooms and guest billing from a single self-hosted stack.",
        "audience": "boutique hotels, B&Bs, hostels and vacation-rental operators",
        "accent": "#0d9488",        # teal-600
        "accent_soft": "#ccfbf1",
        "accent_dark": "#115e59",
        "gradient": "linear-gradient(135deg, #0d9488 0%, #0284c7 100%)",
        "emoji": "\U0001f3e8",  # hotel
        "plugins_enabled": [
            ("cms", "Rooms, amenities, house rules, blog, landing."),
            ("theme-switcher", "On-brand light/dark across the guest portal."),
            ("stripe", "Card payments and holds."),
            ("paypal", "International guest preference."),
            ("mollie", "iDEAL / Bancontact for EU guests."),
            ("analytics", "Occupancy, ADR, revenue-per-available-room."),
        ],
        "plugins_planned": [
            ("booking", "Rooms, availability calendar, rate plans, minimum-stay rules."),
            ("calendar-sync", "Two-way iCal sync with Airbnb, Booking.com, VRBO."),
            ("sms-reminders", "Twilio check-in reminders and late-check-in codes."),
            ("klarna", "BNPL for longer stays and package deals."),
            ("sepa", "Low-cost euro deposits."),
        ],
        "integrations": [
            ("Airbnb / Booking.com / VRBO", "iCal two-way sync through the booking plugin (planned)."),
            ("Twilio", "SMS confirmations and check-in reminders."),
            ("Google Calendar", "Staff rota and housekeeping schedule."),
            ("Stripe Terminal", "Front-desk card-present payments."),
            ("SMTP / Postmark", "Booking confirmations, invoices and pre-arrival emails."),
            ("Zapier / n8n via webhooks", "Connect to PMS, channel managers, door-lock systems."),
        ],
    },
    "doctor": {
        "title": "VBWD Doctor",
        "tagline": "Appointments, billing and a patient portal for private practice.",
        "hero": "An appointment, billing and patient-portal platform for private practice.",
        "audience": "private doctors, dentists, physiotherapists, therapists and small clinics",
        "accent": "#059669",        # emerald-600
        "accent_soft": "#d1fae5",
        "accent_dark": "#047857",
        "gradient": "linear-gradient(135deg, #059669 0%, #0891b2 100%)",
        "emoji": "\u2695\ufe0f",  # medical symbol
        "plugins_enabled": [
            ("cms", "Services, staff bios, consent forms, blog."),
            ("theme-switcher", "Clinic-branded patient portal."),
            ("stripe", "Card payments for consultations and products."),
            ("mollie", "Local EU rails — iDEAL, Bancontact, SEPA."),
            ("analytics", "Appointment no-show rate, revenue per clinician."),
        ],
        "plugins_planned": [
            ("booking", "Per-clinician calendars, service durations, buffer times."),
            ("calendar-sync", "Google / Outlook two-way sync for each clinician."),
            ("sms-reminders", "Twilio appointment reminders — reduces no-shows."),
            ("sepa", "Recurring direct debit for care plans and retainers."),
            ("paddle", "Automatic VAT handling across EU jurisdictions."),
            ("consent-forms", "Versioned consent, e-signature, per-visit audit log."),
        ],
        "integrations": [
            ("Twilio", "SMS reminders — material no-show reduction in every study."),
            ("Google Calendar / Outlook", "Each clinician keeps their own calendar."),
            ("SMTP / Postmark", "Appointment confirmations and pre-visit intake forms."),
            ("Zoom / Jitsi", "Telehealth link auto-generated per online appointment."),
            ("DATEV / Lexoffice (DE)", "Invoice export for German tax accountants (planned)."),
            ("Webhooks", "Push appointment events into any PMS or EHR."),
        ],
    },
    "ghrm": {
        "title": "VBWD GHRM",
        "tagline": "Turn any GitHub repository into a paid, supported product.",
        "hero": "GitHub Repo Manager — turn any open-source repo into a paid product.",
        "audience": "open-source maintainers and small development teams monetising repos",
        "accent": "#ea580c",        # orange-600
        "accent_soft": "#ffedd5",
        "accent_dark": "#c2410c",
        "gradient": "linear-gradient(135deg, #ea580c 0%, #dc2626 100%)",
        "emoji": "\U0001f9ed",  # compass (maintainer)
        "plugins_enabled": [
            ("cms", "Product pages, docs, changelog, blog."),
            ("ghrm", "GitHub-repo browsing, gated downloads, license-key issuance."),
            ("chat", "Token-metered support chat backed by an LLM."),
            ("theme-switcher", "Branded docs for every repo you sell."),
            ("token-bundles", "Credits for support questions or gated downloads."),
            ("stripe", "Primary card processor."),
            ("paypal", "International fallback."),
            ("analytics", "Paid-download funnel and repo-level revenue."),
        ],
        "plugins_planned": [
            ("license-keys", "Per-seat license key issuance and revocation."),
            ("docs-sync", "Auto-sync repo README / docs into CMS pages."),
            ("releases-webhook", "New GitHub release → auto-publish on VBWD."),
            ("coinbase", "Crypto payments for international OSS buyers."),
        ],
        "integrations": [
            ("GitHub API", "Repo metadata, releases, issues, Sponsors cross-link."),
            ("GitLab / Bitbucket", "Parallel adapters planned for non-GitHub repos."),
            ("Zapier / n8n via webhooks", "Fire downstream automation on every purchase."),
            ("OpenAI-compatible LLMs", "Power the support chat plugin with any model."),
            ("SMTP / Postmark", "License-key delivery and renewal notices."),
            ("Discord / Slack", "Post new paid-download events to your team channel."),
        ],
    },
}


# ── Shared exhibition-grade CSS ─────────────────────────────────────────────
#
# Every CSS rule is scoped under `.vbwd-page` so the page is safe to drop into
# a shell that already has global styles (admin chrome, theme-switcher vars).

BASE_CSS_TEMPLATE = dedent("""
    .vbwd-page {
      --vbwd-accent: %ACCENT%;
      --vbwd-accent-soft: %ACCENT_SOFT%;
      --vbwd-accent-dark: %ACCENT_DARK%;
      --vbwd-gradient: %GRADIENT%;
      --vbwd-text: #0f172a;
      --vbwd-text-muted: #475569;
      --vbwd-surface: #ffffff;
      --vbwd-surface-soft: #f8fafc;
      --vbwd-border: #e2e8f0;
      --vbwd-radius: 14px;
      --vbwd-radius-lg: 22px;
      --vbwd-shadow-sm: 0 1px 2px rgba(15,23,42,0.06), 0 1px 3px rgba(15,23,42,0.08);
      --vbwd-shadow-md: 0 4px 6px -1px rgba(15,23,42,0.08), 0 2px 4px -2px rgba(15,23,42,0.06);
      --vbwd-shadow-lg: 0 20px 25px -5px rgba(15,23,42,0.10), 0 8px 10px -6px rgba(15,23,42,0.08);
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
      color: var(--vbwd-text);
      line-height: 1.65;
      font-size: 17px;
      -webkit-font-smoothing: antialiased;
    }
    .vbwd-page *, .vbwd-page *::before, .vbwd-page *::after { box-sizing: border-box; }
    .vbwd-page h1, .vbwd-page h2, .vbwd-page h3, .vbwd-page h4 {
      color: #0b1220;
      line-height: 1.2;
      letter-spacing: -0.02em;
      margin: 0 0 0.65em;
      font-weight: 700;
    }
    .vbwd-page h1 { font-size: clamp(2.2rem, 4vw, 3.25rem); font-weight: 800; }
    .vbwd-page h2 { font-size: clamp(1.5rem, 2.4vw, 2rem); margin-top: 0.4em; }
    .vbwd-page h3 { font-size: 1.2rem; }
    .vbwd-page p  { margin: 0 0 1em; color: var(--vbwd-text); }
    .vbwd-page a  { color: var(--vbwd-accent-dark); text-decoration: none; font-weight: 600; }
    .vbwd-page a:hover { text-decoration: underline; text-underline-offset: 3px; }
    .vbwd-page code {
      font-family: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
      background: var(--vbwd-accent-soft);
      color: var(--vbwd-accent-dark);
      padding: 0.15em 0.45em;
      border-radius: 6px;
      font-size: 0.9em;
      font-weight: 500;
    }

    .vbwd-page .vbwd-container {
      max-width: 1080px;
      margin: 0 auto;
      padding: 0 1.5rem;
    }

    /* ── Hero ─────────────────────────────────────────────────────────── */
    .vbwd-page .vbwd-hero {
      background: var(--vbwd-gradient);
      color: #ffffff;
      padding: clamp(3.5rem, 8vw, 6rem) 1.5rem;
      text-align: center;
      position: relative;
      overflow: hidden;
      border-radius: var(--vbwd-radius-lg);
      margin: 0 1rem 3rem;
    }
    .vbwd-page .vbwd-hero::before {
      content: "";
      position: absolute;
      inset: 0;
      background:
        radial-gradient(circle at 20% 10%, rgba(255,255,255,0.25), transparent 40%),
        radial-gradient(circle at 80% 90%, rgba(255,255,255,0.18), transparent 45%);
      pointer-events: none;
    }
    .vbwd-page .vbwd-hero__eyebrow {
      display: inline-block;
      padding: 0.35rem 0.9rem;
      border-radius: 999px;
      background: rgba(255,255,255,0.18);
      color: #fff;
      font-size: 0.78rem;
      font-weight: 600;
      letter-spacing: 0.1em;
      text-transform: uppercase;
      margin-bottom: 1.25rem;
      backdrop-filter: blur(4px);
    }
    .vbwd-page .vbwd-hero h1 {
      color: #fff;
      margin-bottom: 0.65rem;
      text-shadow: 0 2px 8px rgba(0,0,0,0.18);
      position: relative;
    }
    .vbwd-page .vbwd-hero__lead {
      color: rgba(255,255,255,0.95);
      font-size: clamp(1.05rem, 1.6vw, 1.25rem);
      max-width: 720px;
      margin: 0 auto;
      position: relative;
    }
    .vbwd-page .vbwd-hero__badge-row {
      display: flex;
      flex-wrap: wrap;
      gap: 0.5rem;
      justify-content: center;
      margin-top: 1.75rem;
      position: relative;
    }
    .vbwd-page .vbwd-hero__badge {
      background: rgba(255,255,255,0.18);
      border: 1px solid rgba(255,255,255,0.25);
      color: #fff;
      padding: 0.35rem 0.85rem;
      border-radius: 999px;
      font-size: 0.82rem;
      font-weight: 500;
      backdrop-filter: blur(4px);
    }

    /* ── Sections ─────────────────────────────────────────────────────── */
    .vbwd-page section { padding: 2.5rem 0; }
    .vbwd-page section + section { border-top: 1px solid var(--vbwd-border); }
    .vbwd-page .vbwd-eyebrow {
      display: inline-block;
      color: var(--vbwd-accent-dark);
      background: var(--vbwd-accent-soft);
      padding: 0.25rem 0.7rem;
      border-radius: 999px;
      font-size: 0.78rem;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      margin-bottom: 0.9rem;
    }

    /* ── Plugin grid ─────────────────────────────────────────────────── */
    .vbwd-page .vbwd-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 1rem;
      margin: 1.25rem 0 0;
    }
    .vbwd-page .vbwd-card {
      background: var(--vbwd-surface);
      border: 1px solid var(--vbwd-border);
      border-radius: var(--vbwd-radius);
      padding: 1.25rem 1.35rem;
      box-shadow: var(--vbwd-shadow-sm);
      transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
      position: relative;
      overflow: hidden;
    }
    .vbwd-page .vbwd-card::before {
      content: "";
      position: absolute;
      left: 0; top: 0; bottom: 0;
      width: 3px;
      background: var(--vbwd-accent);
      opacity: 0.7;
    }
    .vbwd-page .vbwd-card:hover {
      transform: translateY(-2px);
      box-shadow: var(--vbwd-shadow-md);
      border-color: var(--vbwd-accent);
    }
    .vbwd-page .vbwd-card__title {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-weight: 700;
      color: var(--vbwd-text);
      margin-bottom: 0.35rem;
      font-size: 1.02rem;
    }
    .vbwd-page .vbwd-card__title code {
      background: var(--vbwd-accent-soft);
      color: var(--vbwd-accent-dark);
      font-size: 0.88rem;
    }
    .vbwd-page .vbwd-card__desc {
      color: var(--vbwd-text-muted);
      font-size: 0.94rem;
      line-height: 1.55;
      margin: 0;
    }
    .vbwd-page .vbwd-card--muted { opacity: 0.95; background: var(--vbwd-surface-soft); }
    .vbwd-page .vbwd-card--muted::before { background: #94a3b8; opacity: 0.6; }

    /* ── Feature list ────────────────────────────────────────────────── */
    .vbwd-page ul.vbwd-list {
      list-style: none;
      padding: 0;
      margin: 1rem 0 0;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 0.5rem 1.5rem;
    }
    .vbwd-page ul.vbwd-list li {
      position: relative;
      padding: 0.35rem 0 0.35rem 1.75rem;
      color: var(--vbwd-text);
    }
    .vbwd-page ul.vbwd-list li::before {
      content: "";
      position: absolute;
      left: 0; top: 0.75rem;
      width: 0.7rem; height: 0.7rem;
      border-radius: 3px;
      background: var(--vbwd-accent);
      box-shadow: 0 0 0 3px var(--vbwd-accent-soft);
    }

    /* ── Payment table ───────────────────────────────────────────────── */
    .vbwd-page .vbwd-table-wrap {
      overflow-x: auto;
      border-radius: var(--vbwd-radius);
      border: 1px solid var(--vbwd-border);
      margin: 1rem 0 0;
      background: var(--vbwd-surface);
      box-shadow: var(--vbwd-shadow-sm);
    }
    .vbwd-page table.vbwd-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.95rem;
    }
    .vbwd-page table.vbwd-table th {
      text-align: left;
      padding: 0.85rem 1rem;
      background: var(--vbwd-surface-soft);
      color: var(--vbwd-text-muted);
      font-size: 0.78rem;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      border-bottom: 1px solid var(--vbwd-border);
    }
    .vbwd-page table.vbwd-table td {
      padding: 0.85rem 1rem;
      border-bottom: 1px solid var(--vbwd-border);
      vertical-align: top;
    }
    .vbwd-page table.vbwd-table tr:last-child td { border-bottom: none; }
    .vbwd-page table.vbwd-table tr:hover td { background: var(--vbwd-accent-soft); }
    .vbwd-page table.vbwd-table .vbwd-method-name {
      font-weight: 700;
      color: var(--vbwd-text);
      display: block;
      margin-bottom: 0.15rem;
    }
    .vbwd-page table.vbwd-table code { font-size: 0.8rem; }

    .vbwd-page .vbwd-badge {
      display: inline-block;
      padding: 0.2rem 0.65rem;
      border-radius: 999px;
      font-size: 0.74rem;
      font-weight: 700;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      white-space: nowrap;
    }
    .vbwd-page .vbwd-badge--ok {
      background: #dcfce7;
      color: #166534;
    }
    .vbwd-page .vbwd-badge--planned {
      background: #fef3c7;
      color: #92400e;
    }
    .vbwd-page .vbwd-badge--region {
      background: var(--vbwd-accent-soft);
      color: var(--vbwd-accent-dark);
    }

    /* ── Stat row ────────────────────────────────────────────────────── */
    .vbwd-page .vbwd-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 1rem;
      margin: 1.5rem 0;
    }
    .vbwd-page .vbwd-stat {
      text-align: center;
      padding: 1.25rem 1rem;
      background: var(--vbwd-surface);
      border: 1px solid var(--vbwd-border);
      border-radius: var(--vbwd-radius);
      box-shadow: var(--vbwd-shadow-sm);
    }
    .vbwd-page .vbwd-stat__number {
      display: block;
      font-size: 2.25rem;
      font-weight: 800;
      color: var(--vbwd-accent-dark);
      line-height: 1.1;
      letter-spacing: -0.02em;
    }
    .vbwd-page .vbwd-stat__label {
      display: block;
      margin-top: 0.35rem;
      color: var(--vbwd-text-muted);
      font-size: 0.82rem;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }

    /* ── Callout / CTA ──────────────────────────────────────────────── */
    .vbwd-page .vbwd-callout {
      background: var(--vbwd-accent-soft);
      border-left: 4px solid var(--vbwd-accent);
      border-radius: var(--vbwd-radius);
      padding: 1.1rem 1.35rem;
      margin: 1.5rem 0 0;
      color: var(--vbwd-text);
    }
    .vbwd-page .vbwd-callout p { margin: 0; }
    .vbwd-page .vbwd-btn {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      padding: 0.75rem 1.35rem;
      background: var(--vbwd-accent);
      color: #fff;
      border-radius: 10px;
      font-weight: 700;
      font-size: 0.95rem;
      box-shadow: var(--vbwd-shadow-md);
      transition: filter 0.15s ease, transform 0.15s ease;
    }
    .vbwd-page .vbwd-btn:hover {
      filter: brightness(1.08);
      transform: translateY(-1px);
      text-decoration: none;
    }

    /* ── Responsive ──────────────────────────────────────────────────── */
    @media (max-width: 640px) {
      .vbwd-page { font-size: 16px; }
      .vbwd-page .vbwd-hero { margin: 0 0.5rem 2rem; padding: 2.75rem 1rem; }
      .vbwd-page .vbwd-container { padding: 0 1.1rem; }
      .vbwd-page ul.vbwd-list { grid-template-columns: 1fr; }
    }
""").strip()


def build_css(config):
    return (
        BASE_CSS_TEMPLATE
        .replace("%ACCENT%", config["accent"])
        .replace("%ACCENT_SOFT%", config["accent_soft"])
        .replace("%ACCENT_DARK%", config["accent_dark"])
        .replace("%GRADIENT%", config["gradient"])
    )


# ── HTML builders ────────────────────────────────────────────────────────────

def _plugin_grid(plugins, muted=False):
    muted_class = " vbwd-card--muted" if muted else ""
    cards = "".join(
        f'<div class="vbwd-card{muted_class}">'
        f'<div class="vbwd-card__title"><code>{slug}</code></div>'
        f'<p class="vbwd-card__desc">{desc}</p>'
        f'</div>'
        for slug, desc in plugins
    )
    return f'<div class="vbwd-grid">{cards}</div>'


def _integrations_grid(integrations):
    cards = "".join(
        f'<div class="vbwd-card">'
        f'<div class="vbwd-card__title">{name}</div>'
        f'<p class="vbwd-card__desc">{desc}</p>'
        f'</div>'
        for name, desc in integrations
    )
    return f'<div class="vbwd-grid">{cards}</div>'


def _payments_table(rows, status_badge):
    body = ""
    for name, desc, slug, region in rows:
        body += (
            f'<tr>'
            f'<td><span class="vbwd-method-name">{name}</span><code>{slug}</code></td>'
            f'<td><span class="vbwd-badge vbwd-badge--region">{region}</span></td>'
            f'<td>{desc}</td>'
            f'<td>{status_badge}</td>'
            f'</tr>'
        )
    return (
        '<div class="vbwd-table-wrap"><table class="vbwd-table">'
        '<thead><tr>'
        '<th>Method</th><th>Region</th><th>What it adds</th><th>Status</th>'
        '</tr></thead>'
        f'<tbody>{body}</tbody></table></div>'
    )


def _hero(config, eyebrow):
    plugin_badges = "".join(
        f'<span class="vbwd-hero__badge">{slug}</span>'
        for slug, _ in config["plugins_enabled"][:6]
    )
    return dedent(f"""
        <header class="vbwd-hero">
          <span class="vbwd-hero__eyebrow">{eyebrow}</span>
          <h1>{config['emoji']} {config['title']}</h1>
          <p class="vbwd-hero__lead">{config['tagline']}</p>
          <div class="vbwd-hero__badge-row">{plugin_badges}</div>
        </header>
    """).strip()


# ── Page content per vertical ────────────────────────────────────────────────

def build_about(vertical_key, config):
    title = config["title"]
    audience = config["audience"]
    hero = _hero(config, "About")
    plugins = _plugin_grid(config["plugins_enabled"])
    return dedent(f"""
        <article class="vbwd-page vbwd-page--about">
          {hero}
          <div class="vbwd-container">

            <section>
              <span class="vbwd-eyebrow">The pitch</span>
              <h2>What this instance demonstrates</h2>
              <p>
                <strong>{title}</strong> is a worked example of running the VBWD
                platform for {audience}. VBWD core is intentionally agnostic —
                all domain behaviour is delivered by plugins. This instance is
                nothing more than a chosen constellation of plugins on top of
                the same core codebase that every other instance runs.
              </p>
              <div class="vbwd-stats">
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">{len(config['plugins_enabled'])}</span>
                  <span class="vbwd-stat__label">Plugins enabled</span>
                </div>
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">{len(config['plugins_planned'])}</span>
                  <span class="vbwd-stat__label">On the roadmap</span>
                </div>
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">1,851+</span>
                  <span class="vbwd-stat__label">Passing tests</span>
                </div>
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">65+</span>
                  <span class="vbwd-stat__label">REST endpoints</span>
                </div>
              </div>
            </section>

            <section>
              <span class="vbwd-eyebrow">Constellation</span>
              <h2>Plugin constellation in this instance</h2>
              <p>Every row below is a real plugin — switch it off in
              <code>/admin/settings/plugins</code> and the corresponding
              behaviour disappears cleanly.</p>
              {plugins}
            </section>

            <section>
              <span class="vbwd-eyebrow">Free with core</span>
              <h2>Guarantees you inherit</h2>
              <ul class="vbwd-list">
                <li>Subscription lifecycle — <code>PENDING → ACTIVE → CANCELLED → EXPIRED</code>.</li>
                <li>Multi-currency pricing, regional tax, line-item invoicing.</li>
                <li>Token economy for any metered feature — AI, exports, downloads, bookings.</li>
                <li>JWT auth with access + refresh, bcrypt hashing, RBAC.</li>
                <li>Outbound webhooks with retry and delivery logs.</li>
                <li>Enable / disable plugins without a server restart.</li>
                <li>1,851+ passing tests, TDD as the development standard.</li>
                <li>BSL 1.1 — self-host for yourself free; production use needs a licence.</li>
              </ul>
              <div class="vbwd-callout">
                <p>Want the pricing? <a href="/pricing-native" class="vbwd-btn">See plans →</a></p>
              </div>
            </section>

          </div>
        </article>
    """).strip()


def build_features(vertical_key, config):
    title = config["title"]
    hero = _hero(config, "Features")
    plugins_on = _plugin_grid(config["plugins_enabled"])
    plugins_planned = _plugin_grid(config["plugins_planned"], muted=True)
    return dedent(f"""
        <article class="vbwd-page vbwd-page--features">
          {hero}
          <div class="vbwd-container">

            <section>
              <span class="vbwd-eyebrow">Composable</span>
              <h2>Every feature is a plugin</h2>
              <p>
                Toggle any of these from the admin panel at
                <code>/admin/settings/plugins</code>. No server restart, no
                code change. Turn a plugin off and every route, menu item,
                table and webhook it owns disappears cleanly.
              </p>
            </section>

            <section>
              <span class="vbwd-eyebrow">Live</span>
              <h2>Enabled out of the box</h2>
              {plugins_on}
            </section>

            <section>
              <span class="vbwd-eyebrow">Roadmap</span>
              <h2>Planned for {title}</h2>
              {plugins_planned}
            </section>

            <section>
              <span class="vbwd-eyebrow">Core</span>
              <h2>Features inherited from VBWD core</h2>
              <ul class="vbwd-list">
                <li>Tariff plans with monthly / annual / custom periods and multi-currency pricing.</li>
                <li>Add-ons — purchasable extras on top of base subscriptions, bound to specific plans.</li>
                <li>Invoicing with line items per subscription, token bundle and add-on charge.</li>
                <li>Token economy — credit packs, per-plan daily limits, admin quota reset.</li>
                <li>User management — register, login, password reset, billing address, RBAC.</li>
                <li>Admin backoffice — users, plans, subscriptions, invoices, analytics, webhooks.</li>
                <li>Embeddable pricing widget — drop a <code>&lt;script&gt;</code> tag on any site.</li>
                <li>Plugin i18n — every plugin owns its own <code>locales/{{en,de}}.json</code>.</li>
              </ul>
            </section>

            <section>
              <span class="vbwd-eyebrow">Stack</span>
              <h2>Tech stack</h2>
              <div class="vbwd-grid">
                <div class="vbwd-card">
                  <div class="vbwd-card__title">Backend</div>
                  <p class="vbwd-card__desc">Python 3.11, Flask 3.0, SQLAlchemy 2.0, PostgreSQL 16, Redis 7.</p>
                </div>
                <div class="vbwd-card">
                  <div class="vbwd-card__title">Frontend</div>
                  <p class="vbwd-card__desc">Vue 3, TypeScript, Vite, Pinia, Vue Router 4.</p>
                </div>
                <div class="vbwd-card">
                  <div class="vbwd-card__title">Infra</div>
                  <p class="vbwd-card__desc">Docker, Docker Compose, Nginx, Gunicorn.</p>
                </div>
                <div class="vbwd-card">
                  <div class="vbwd-card__title">Testing</div>
                  <p class="vbwd-card__desc">pytest, Vitest, Playwright — 1,851+ passing tests.</p>
                </div>
              </div>
            </section>

          </div>
        </article>
    """).strip()


def build_integrations(vertical_key, config):
    title = config["title"]
    hero = _hero(config, "Integrations")
    integrations = _integrations_grid(config["integrations"])
    return dedent(f"""
        <article class="vbwd-page vbwd-page--integrations">
          {hero}
          <div class="vbwd-container">

            <section>
              <span class="vbwd-eyebrow">Philosophy</span>
              <h2>Plug-and-play at the boundary</h2>
              <p>
                VBWD is deliberately open at the edges: any third-party system
                can be reached through a plugin adapter, outbound webhooks or
                the REST API. The list below is what <strong>{title}</strong>
                typically connects to.
              </p>
            </section>

            <section>
              <span class="vbwd-eyebrow">Ecosystem</span>
              <h2>Integrations for this vertical</h2>
              {integrations}
            </section>

            <section>
              <span class="vbwd-eyebrow">Generic</span>
              <h2>Integration surfaces available everywhere</h2>
              <div class="vbwd-grid">
                <div class="vbwd-card">
                  <div class="vbwd-card__title">REST API</div>
                  <p class="vbwd-card__desc">
                    65+ endpoints under <code>/api/v1/*</code>. Auth via JWT,
                    machine-to-machine via API keys (planned).
                  </p>
                </div>
                <div class="vbwd-card">
                  <div class="vbwd-card__title">Outbound webhooks</div>
                  <p class="vbwd-card__desc">
                    Fire on every subscription and payment event. Configurable
                    endpoints per event type, retry with backoff, delivery log.
                  </p>
                </div>
                <div class="vbwd-card">
                  <div class="vbwd-card__title">Plugin adapters</div>
                  <p class="vbwd-card__desc">
                    Wrap any third party as a backend plugin under
                    <code>plugins/&lt;name&gt;/</code>. Follows the
                    <code>stripe</code> or <code>mollie</code> reference.
                  </p>
                </div>
                <div class="vbwd-card">
                  <div class="vbwd-card__title">Zapier / n8n / Make</div>
                  <p class="vbwd-card__desc">
                    Consume webhooks and drive inbound actions through the REST
                    API without writing code.
                  </p>
                </div>
              </div>
            </section>

          </div>
        </article>
    """).strip()


def build_payment_modules(vertical_key, config):
    title = config["title"]
    hero = _hero(config, "Payment Modules")
    badge_ok = '<span class="vbwd-badge vbwd-badge--ok">Implemented</span>'
    badge_planned = '<span class="vbwd-badge vbwd-badge--planned">Planned</span>'
    implemented_table = _payments_table(PAYMENT_METHODS_IMPLEMENTED, badge_ok)
    planned_table = _payments_table(PAYMENT_METHODS_PLANNED, badge_planned)
    n_impl = len(PAYMENT_METHODS_IMPLEMENTED)
    n_plan = len(PAYMENT_METHODS_PLANNED)
    n_total = n_impl + n_plan
    return dedent(f"""
        <article class="vbwd-page vbwd-page--payments">
          {hero}
          <div class="vbwd-container">

            <section>
              <span class="vbwd-eyebrow">Overview</span>
              <h2>Every rail is a plugin</h2>
              <p>
                Enable several at once; the user picks their preferred method
                at checkout. No code change, no server restart — just toggle
                the plugin in the admin panel.
              </p>
              <div class="vbwd-stats">
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">{n_impl}</span>
                  <span class="vbwd-stat__label">Rails live today</span>
                </div>
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">{n_plan}</span>
                  <span class="vbwd-stat__label">On the roadmap</span>
                </div>
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">{n_total}</span>
                  <span class="vbwd-stat__label">Total catalogue</span>
                </div>
                <div class="vbwd-stat">
                  <span class="vbwd-stat__number">6</span>
                  <span class="vbwd-stat__label">Continents covered</span>
                </div>
              </div>
            </section>

            <section>
              <span class="vbwd-eyebrow">Ready today</span>
              <h2>Implemented ({n_impl})</h2>
              {implemented_table}
            </section>

            <section>
              <span class="vbwd-eyebrow">Roadmap</span>
              <h2>Planned ({n_plan})</h2>
              {planned_table}
            </section>

            <section>
              <span class="vbwd-eyebrow">Architecture</span>
              <h2>How a payment plugin is structured</h2>
              <p>
                Each provider lives under <code>plugins/&lt;provider&gt;/</code>
                with its own config schema, models, service layer, routes and
                tests. They all register against the same
                <code>IPaymentAdapter</code> interface — switch providers and
                nothing else in the codebase needs to move.
              </p>
              <div class="vbwd-callout">
                <p>
                  Need a rail we don't cover yet? Payment plugins are standalone
                  repos; build your own using <code>plugins/stripe/</code> as a
                  reference or
                  <a href="mailto:partners@vbwd.io" class="vbwd-btn">commission us →</a>
                </p>
              </div>
            </section>

          </div>
        </article>
    """).strip()


BUILDERS = {
    "about": build_about,
    "features": build_features,
    "integrations": build_integrations,
    "payment-modules": build_payment_modules,
}

SORT_ORDER = {
    "about": 10,
    "features": 20,
    "integrations": 30,
    "payment-modules": 40,
}

NAMES = {
    "about": "About",
    "features": "Features",
    "integrations": "Integrations",
    "payment-modules": "Payment Modules",
}


def build_page_record(vertical_key, slug, config, css):
    html = BUILDERS[slug](vertical_key, config).strip()
    name = f"{NAMES[slug]} — {config['title']}"
    meta_desc = {
        "about": f"{config['title']}: a worked example of running the VBWD "
                 f"platform for {config['audience']}.",
        "features": f"Every feature in {config['title']} is a composable "
                    f"plugin. Toggle from the admin panel, no restart.",
        "integrations": f"Third-party systems {config['title']} typically "
                        f"connects to: payment rails, email, calendars, "
                        f"AI, shipping, analytics.",
        "payment-modules": f"{config['title']} supports 23 payment rails "
                           f"(3 implemented, 20 planned) covering every "
                           f"major region.",
    }[slug]
    return {
        "slug": slug,
        "name": name,
        "language": "en",
        "content_json": {"type": "doc", "content": []},
        "content_html": html,
        "source_css": css,
        "is_published": True,
        "sort_order": SORT_ORDER[slug],
        "meta_title": name,
        "meta_description": meta_desc,
        "meta_keywords": f"vbwd, {vertical_key}, {slug.replace('-', ' ')}, "
                         f"self-hosted saas, open source",
        "og_title": name,
        "og_description": meta_desc,
        "robots": "index,follow",
        "use_theme_switcher_styles": False,
        "required_access_level_ids": [],
    }


def main():
    for vertical_key, config in VERTICALS.items():
        css = build_css(config)
        pages = [
            build_page_record(vertical_key, slug, config, css)
            for slug in ("about", "features", "integrations", "payment-modules")
        ]
        out_dir = OUTPUT_ROOT / vertical_key
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / "pages.json"
        out_file.write_text(
            json.dumps(pages, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {out_file} ({len(pages)} pages, "
              f"accent={config['accent']})")


if __name__ == "__main__":
    main()
