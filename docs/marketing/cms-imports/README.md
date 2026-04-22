# CMS page imports — per-vertical instances

This folder ships ready-to-import CMS content for every VBWD vertical demo
instance. Each vertical gets the same four marketing pages, but the
content — plugin constellation, audience, integrations — is tailored so
the page acts as a worked example of that vertical.

## Verticals

| Instance | Audience | Plugin constellation (flavour) |
|----------|----------|--------------------------------|
| `main`   | Indie devs, agencies, platform teams | cms, chat, landing1, theme-switcher, analytics, stripe, paypal, yookassa |
| `shop`   | Digital creators, subscription boxes, niche marketplaces | cms, theme-switcher, stripe, paypal, mollie, token-bundles, analytics |
| `hotel`  | Boutique hotels, B&Bs, hostels, vacation rentals | cms, theme-switcher, stripe, paypal, mollie, analytics (+ planned booking, calendar-sync, klarna, sepa) |
| `doctor` | Private doctors, dentists, therapists, small clinics | cms, theme-switcher, stripe, mollie, analytics (+ planned booking, calendar-sync, sepa, paddle, consent-forms) |
| `ghrm`   | OSS maintainers, small dev teams monetising repos | cms, ghrm, chat, theme-switcher, token-bundles, stripe, paypal, analytics |

## Pages delivered per vertical

1. `about` — what this instance demonstrates + the plugin constellation.
2. `features` — enabled plugins, planned plugins, core features inherited.
3. `integrations` — third-party systems the vertical typically connects to.
4. `payment-modules` — catalogue of all 23 payment rails (3 implemented, 20 planned).

## Payment rails catalogue (identical on every vertical)

**Implemented (3):** Stripe, PayPal, YooKassa.

**Planned (20):** Adyen, Braintree, Square, Razorpay, Mollie, Klarna,
Paddle, Authorize.Net, 2Checkout (Verifone), Wise Business, Revolut
Business, Coinbase Commerce, BitPay, Apple Pay (direct), Google Pay
(direct), Alipay, WeChat Pay, SEPA Direct Debit, iDEAL, Sofort / Bancontact.

## Import format

`pages.json` is an array of records matching
`CmsPageService.import_pages` — see
`vbwd-backend/plugins/cms/src/services/cms_page_service.py`. Import is
idempotent at the slug level: existing slugs are **skipped**, not updated.
To replace a page, delete it first or bump its slug.

Each record carries:

- `slug`, `name`, `language`, `is_published`, `sort_order`
- `content_json` (TipTap doc — empty shell) and `content_html` (the real content)
- Full SEO fields: `meta_title`, `meta_description`, `meta_keywords`,
  `og_title`, `og_description`, `robots`
- `use_theme_switcher_styles: true` so the page picks up the active theme

## Importing into a running instance

The admin endpoint is `POST /api/v1/admin/cms/pages/import` and accepts the
raw JSON body. Log in as an admin (`admin@example.com` / `AdminPass123@` on
dev), then:

```bash
# Import into the `main` instance
bash docs/marketing/cms-imports/bin/import.sh main https://vbwd.io admin@example.com 'AdminPass123@'

# Import into a specific vertical on localhost
bash docs/marketing/cms-imports/bin/import.sh hotel http://localhost:5000 admin@example.com 'AdminPass123@'
```

The script logs in, grabs the JWT, POSTs `pages.json` to the import
endpoint and prints the server response (`{"created": N, "skipped": N}`).

## Styling

Every page ships with exhibition-grade CSS baked into its `source_css`
field. The stylesheet is scoped under `.vbwd-page` so it will not collide
with admin chrome or the theme-switcher. Each vertical owns an accent
colour and gradient so instances feel distinct at a glance:

| Instance | Accent | Gradient |
|----------|--------|----------|
| `main`   | Blue `#2563eb` | blue → violet |
| `shop`   | Violet `#7c3aed` | violet → pink |
| `hotel`  | Teal `#0d9488` | teal → sky |
| `doctor` | Emerald `#059669` | emerald → cyan |
| `ghrm`   | Orange `#ea580c` | orange → red |

`use_theme_switcher_styles` is set to `false` so the per-page CSS always
wins — you get the designed look with or without the theme plugin.

## Previewing locally

Each vertical gets a `preview.html` that renders all four pages stacked on
a single page. Open any of them directly in a browser:

```bash
open docs/marketing/cms-imports/main/preview.html
```

These previews are throwaway — regenerate them with the snippet below
whenever you change `_generate.py`.

## Regenerating the JSON

Content, colours and CSS all live in `_generate.py`. Edit the `VERTICALS`
dict, the `PAYMENT_METHODS_*` lists or `BASE_CSS_TEMPLATE`, then:

```bash
python3 docs/marketing/cms-imports/_generate.py
```

Every `pages.json` is overwritten. No external dependencies — standard
library only.
