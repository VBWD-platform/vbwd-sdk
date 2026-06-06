# CMS page imports — per-vertical instances

This folder ships ready-to-import CMS content for every VBWD vertical demo
instance. Each vertical gets the same four marketing pages, but the
content — plugin constellation, audience, integrations — is tailored so
the page acts as a worked example of that vertical.

## Verticals

| Instance | Audience | Plugin constellation (flavour) |
|----------|----------|--------------------------------|
| `core`          | Indie devs, agencies, platform teams | cms, mainchat, chat, landing1, theme-switcher, analytics, stripe, paypal, yookassa |
| `softwarestore` | Digital creators, subscription boxes, niche marketplaces | cms, theme-switcher, stripe, paypal, mollie, token-bundles, analytics |
| `hotel`         | Boutique hotels, B&Bs, hostels, vacation rentals | cms, mainchat, theme-switcher, stripe, paypal, mollie, analytics (+ planned booking, calendar-sync, klarna, sepa) |
| `doctor`        | Private doctors, dentists, therapists, small clinics | cms, mainchat, theme-switcher, stripe, mollie, analytics (+ planned booking, calendar-sync, sepa, paddle, consent-forms) |
| `ghrm`          | OSS maintainers, small dev teams monetising repos | cms, ghrm, chat, theme-switcher, token-bundles, stripe, paypal, analytics |

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

## Import format (new CMS data structure — `cms_post`)

Pages are now **`cms_post` records of `type: "page"`**. `pages.json` is the
canonical import envelope consumed by `PostImportExportService.import_posts` —
see `vbwd-backend/plugins/cms/src/services/post_import_export_service.py`:

```jsonc
{
  "version": 1,
  "entity": "cms_post",
  "items": [ /* one record per page */ ]
}
```

Import is an **UPSERT keyed on `(type, slug)`**: an existing page is **updated**,
a new one is **created** (the server returns `{"created": N, "updated": N}`).
This replaces the old create-only, skip-by-slug `pages/import` behaviour — you no
longer delete a page to re-import it.

Each item carries:

- `type` (`"page"`), `slug`, `title`, `language`, `status`
  (`"published"` | `"draft"` | `"private"` | `"trash"`), `sort_order`
- `content_json` (TipTap doc — empty shell) and `content_html` (the real content)
- `source_css` — page-scoped CSS (always applied; see *Styling*)
- Full SEO fields: `meta_title`, `meta_description`, `meta_keywords`,
  `og_title`, `og_description`, `robots`
- `terms` — array of `{"term_type": "category"|"tag", "slug": "..."}` (empty on
  these marketing pages)
- Optional slug references resolved on import: `style_slug`, `layout_slug`,
  `parent_slug` (a parent page within the same type)

**Removed legacy fields** (no longer emitted): `name` → now `title`;
`is_published` → now `status`; `use_theme_switcher_styles` (the theme-switcher is
gone — `source_css` always wins); `required_access_level_ids` (not a portable
post field). Terms/categories are now referenced by slug under `terms`, not by
`category_id`.

## Importing into a running instance

The admin endpoint is `POST /api/v1/admin/cms/posts/import` and accepts the
raw JSON envelope as the body. Log in as an admin (`admin@example.com` /
`AdminPass123@` on dev), then:

```bash
# Import into the `core` instance
bash docs/marketing/cms-imports/bin/import.sh core https://vbwd.io admin@example.com 'AdminPass123@'

# Import into a specific vertical on localhost
bash docs/marketing/cms-imports/bin/import.sh hotel http://localhost:5000 admin@example.com 'AdminPass123@'
```

The script logs in, grabs the JWT, POSTs `pages.json` to the import
endpoint and prints the server response (`{"created": N, "updated": N}`).

## Styling

Every page ships with exhibition-grade CSS baked into its `source_css`
field. The stylesheet is scoped under `.vbwd-page` so it will not collide
with admin chrome or the theme-switcher. Each vertical owns an accent
colour and gradient so instances feel distinct at a glance:

| Instance | Accent | Gradient |
|----------|--------|----------|
| `core`          | Blue `#2563eb` | blue → violet |
| `softwarestore` | Violet `#7c3aed` | violet → pink |
| `hotel`         | Teal `#0d9488` | teal → sky |
| `doctor`        | Emerald `#059669` | emerald → cyan |
| `ghrm`          | Orange `#ea580c` | orange → red |

There is no theme-switcher any more: each record's `source_css` is always
applied, so you get the designed look unconditionally.

## Previewing locally

Each vertical gets a `preview.html` that renders all four pages stacked on
a single page. Open any of them directly in a browser:

```bash
open docs/marketing/cms-imports/core/preview.html
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

## `core` (vbwd.cc) — the platform's own site

`core` is special: it is not a flavoured vertical demo, it is the VBWD
platform itself. It therefore ships an extended, deck-sourced information
architecture (content mirrors `pitchmacher-vbwd/dist/deck/core/`) and the
generic `light-clean-narrow` neutral palette instead of a per-vertical
accent. Concretely:

- Page set (in `PAGE_SETS["core"]` in `_generate.py`): `about`,
  `architecture`, `event-architecture`, `features`, `plugins`,
  `integrations`, `billing`, `devops`, `open-source` — **no standalone
  `payment-modules`** (the 23-rail catalogue is folded into `billing`).
- `_generate_ctas.py` emits **only `cta-partner`** for `core` (no
  `cta-contact` / `cta-buy`).
- `core/home.json` is a standalone landing record (deck cover + the
  four "for whom" use-cases) — a one-item `cms_post` envelope. It is **not**
  emitted by `_generate.py`; regenerate it with the snippet in that file's
  header if the core CSS changes (it reuses `gen.build_css(VERTICALS["core"])`
  so it stays in lockstep). It imports through the same `posts/import` endpoint
  (upsert on `(page, home)`); `bin/restore-home.sh` does exactly this.
- Every other vertical's `pages.json` stays byte-for-byte identical —
  the new builders are wired only into `core`.

Regenerate the full core set:

```bash
python3 docs/marketing/cms-imports/_generate.py
python3 docs/marketing/cms-imports/_generate_ctas.py
python3 docs/marketing/cms-imports/_generate_previews.py   # eyeball
bash docs/marketing/cms-imports/bin/import.sh core https://vbwd.cc admin@example.com 'PW'
```

## Menus (header-nav / footer-nav)

Menus are **not** part of the pages-import pipeline. A menu lives on a
`cms_widget` of `type=menu` (slugs `header-nav` / `footer-nav`), not on a
page, so `import.sh` does not touch it. `<vertical>/menu.json` holds the
two menus as **flat arrays** (the `replace_tree` endpoint does NOT recurse
a `children` key — it would be silently dropped). Each item has a
placeholder string `id`, optional `url` / `page_slug` / `target` /
`sort_order`, and sub-items set `parent_id` to their parent's placeholder
`id`. `replace_tree` remaps placeholders to real UUIDs. Apply them with
the sibling helper, which resolves
the widget IDs by slug and PUTs each tree to
`/api/v1/admin/cms/widgets/<id>/menu` (replace-tree — idempotent):

```bash
bash docs/marketing/cms-imports/bin/import-menu.sh core https://vbwd.cc admin@example.com 'PW'
```

The `header-nav` / `footer-nav` widgets must already exist on the
instance (created by the CMS populate step). If a slug is missing the
script skips it with a warning rather than failing the run.
