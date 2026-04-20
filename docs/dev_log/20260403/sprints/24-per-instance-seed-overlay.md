# Sprint 24 — Per-instance seed overlay

**Status:** Decisions locked — awaiting final go-ahead to start coding.
**Date:** 2026-04-20
**Scope:** `vbwd-demo-instances` only. Plugin repos (`vbwd-plugin-*`,
`vbwd-fe-*-plugin-*`, fe-core, fe-user, fe-admin core) are **NOT** modified.

## Goal

Each deployed vertical currently runs the same plugin-level `populate_db.py`
scripts and ends up with the **same** generic menu / pages. We want each
vertical to present a **vertical-specific** header menu and home-page hero,
driven by declarative per-instance JSON that lives in `vbwd-demo-instances`.

The shared footer stays the same across every instance.

## Non-goals — explicit

- **Do not modify any plugin repo** (`vbwd-plugin-cms`,
  `vbwd-plugin-subscription`, etc.). The CMS plugin's own `populate_cms.py`
  keeps seeding its generic demo content.
- Do not modify `vbwd-backend`, `vbwd-fe-core`, `vbwd-fe-user`, or
  `vbwd-fe-admin` core repos.
- No schema migrations. Any menu/page changes go through existing public
  CMS models via the existing admin REST API.
- **Blog archive / category view / paged search** is **out of scope** —
  it needs its own CMS data model work and is captured as sprint 25.
  This sprint's `/blog` link is a stub URL that will resolve once sprint 25
  lands.

## Decisions from review (2026-04-20)

| # | Question | Decision |
|---|---|---|
| 1 | Menu note/subtitle? | **No** — plain labels only. |
| 2 | Home-page hero copy per vertical? | **Yes**, included this sprint. |
| 3 | Shop's third menu slot? | **"Shop"** (not "Software"). |
| 4 | `Blog` link target? | **`/blog`** — admin-assigned CMS category renders as the blog home. Requires **sprint 25**; link is a stub until then. |
| 5 | `saas` plugin set? | **All backend plugins except `shop` and `booking`** — explicitly includes `taro` and `chat` (LLM chat). |

## Architecture — one-paragraph summary

After `deploy.sh --seed` has run every plugin's own `populate_db` (unchanged),
it runs a **new overlay step**: `bin/apply-instance-seed.py` reads
`instances/<name>/backend/instance-seed.json` and uses the CMS plugin's
existing admin REST API to overwrite the header menu, upsert the home-page
hero content, and ensure the shared footer is present. The overlay is
idempotent — safe to re-run any number of times.

## Instances — current + new

| Instance | Domain | Redis DB | fe-user port | fe-admin port |
|---|---|---|---|---|
| main | vbwd.cc | 0 | 8001 | 8101 |
| shop | shop.vbwd.cc | 1 | 8002 | 8102 |
| hotel | hotel.vbwd.cc | 2 | 8003 | 8103 |
| doctor | doctor.vbwd.cc | 3 | 8004 | 8104 |
| ghrm | ghrm.vbwd.cc | 4 | 8005 | 8105 |
| **saas (new)** | **saas.vbwd.cc** | **5** | **8006** | **8106** |

## Per-vertical menu content (source of truth)

### main (`vbwd.cc`) — portfolio showcase

Header: `Home | Features | Demo (submenu) | About | Pricing | Blog`

Demo submenu — plain labels, link to respective demo subdomains:

| Label | URL |
|---|---|
| Software store | https://ghrm.vbwd.cc |
| Hotel | https://hotel.vbwd.cc |
| Clinic | https://doctor.vbwd.cc |
| Shop | https://shop.vbwd.cc |
| Blog | https://vbwd.cc/blog |
| SaaS | https://saas.vbwd.cc |

### Verticals — third-slot CTA pattern

Full header: `Home | Features | <cta> | About | Pricing | Blog`

| Instance | Third menu item | Links to |
|---|---|---|
| doctor | Book Doctor | /booking |
| hotel | Book a Room | /booking |
| ghrm | Software | /software |
| shop | **Shop** | /shop |
| saas | Tarif plans | /pricing |

### Footer (shared across all instances)

Copied verbatim into each `instance-seed.json` (no cross-reference) so each
file is self-contained and diffable.

## `saas` plugin set (final)

Per decision 5: **all backend plugins except `shop` and `booking`**.

### Backend (`instances/saas/backend/plugins.json`)
```
analytics, chat, cms, discount, email, ghrm, mailchimp, paypal,
shipping_flat_rate, stripe, subscription, taro, yookassa
```

### FE-user (`instances/saas/fe-user/plugins.json`)
```
taro, cms, chat, checkout, ghrm, landing1, stripe-payment,
paypal-payment, yookassa-payment, theme-switcher, subscription
```
(fe-user has no `shop` or `booking` plugin included.)

### FE-admin (`instances/saas/fe-admin/plugins.json`)
```
analytics-widget, cms-admin, email-admin, ghrm-admin,
taro-admin, subscription-admin
```

## `instance-seed.json` schema

```json
{
  "version": 1,
  "header_menu": {
    "slug": "header",
    "items": [
      {"label": "Home",     "url": "/"},
      {"label": "Features", "url": "/features"},
      {
        "label": "Demo",
        "url": "#",
        "children": [
          {"label": "Software store", "url": "https://ghrm.vbwd.cc"}
        ]
      },
      {"label": "About",   "url": "/about"},
      {"label": "Pricing", "url": "/pricing"},
      {"label": "Blog",    "url": "/blog"}
    ]
  },
  "footer_menu": {
    "slug": "footer",
    "items": [
      {"label": "Privacy", "url": "/privacy"},
      {"label": "Terms",   "url": "/terms"},
      {"label": "Contact", "url": "/contact"}
    ]
  },
  "home_hero": {
    "title": "Book a doctor in two clicks",
    "subtitle": "Transparent pricing. Real availability. No call centres.",
    "cta_label": "Book now",
    "cta_url": "/booking"
  }
}
```

- `items[*]` is a simple tree: `label` (required), `url` (required),
  optional `children` for one level of submenu (matches what the CMS
  menu-widget schema already supports).
- `home_hero` is applied to the `home` CMS page — the script PUTs the
  fields into the existing hero widget (or adds one if missing), without
  touching the rest of the home page.
- Script validates the JSON against a schema file checked into the repo
  (`bin/instance-seed.schema.json`) before doing any HTTP.

## New / changed files

All under `vbwd-demo-instances/`:

```
bin/apply-instance-seed.py                NEW  — seed overlay applier
bin/instance-seed.schema.json             NEW  — JSON schema
instances/main/backend/instance-seed.json        NEW
instances/shop/backend/instance-seed.json        NEW
instances/hotel/backend/instance-seed.json       NEW
instances/doctor/backend/instance-seed.json      NEW
instances/ghrm/backend/instance-seed.json        NEW
instances/saas/                                  NEW (whole dir)
├── backend/plugins.json                         NEW  (13 plugins)
├── backend/config.json                          NEW  (empty defaults)
├── backend/instance-seed.json                   NEW
├── fe-user/plugins.json                         NEW  (11 plugins)
├── fe-user/config.json                          NEW
├── fe-admin/plugins.json                        NEW  (6 plugins)
└── fe-admin/config.json                         NEW
deploy.sh                                        MOD  — call apply-instance-seed.py at end of --seed
setup.sh                                         MOD  — add saas entry to INSTANCES array
init-databases.sql                               MOD  — CREATE DATABASE vbwd_saas
.github/workflows/deploy.yml                     MOD  — add deploy_saas input; include in list
docs/dev_log/20260403/sprints/24-*.md            NEW  — this document
docs/dev_log/20260403/sprints/25-cms-blog-*.md   NEW  — stub sprint doc for follow-up
```

## `apply-instance-seed.py` — behaviour

```
Usage:
  python bin/apply-instance-seed.py --instance <name>
                                    [--api-url http://localhost:5000]
                                    [--admin-email admin@example.com]
                                    [--admin-password ...]

1. Load instances/<name>/backend/instance-seed.json (skip if missing).
2. Validate against bin/instance-seed.schema.json.
3. Login via POST /api/v1/auth/login → bearer token.
4. For header/footer menu:
     a. GET /api/v1/admin/cms/widgets  →  find widget with slug "header"/"footer".
        If missing, POST to create.
     b. PUT /api/v1/admin/cms/widgets/<id>/menu  with the full items tree
        (fully replaces the menu — that's what this endpoint does).
5. For home_hero:
     a. GET /api/v1/admin/cms/pages/home  → if missing, POST a minimal page.
     b. Merge hero fields into the page's widget config (no raw HTML rewrite).
6. Exits 0 on success, non-zero with body logged on any HTTP failure.
```

Runs via `docker compose exec -T api python /opt/vbwd/bin/apply-instance-seed.py …`
(script scp'd to `/opt/vbwd/bin/`, container has `requests` already).

## `deploy.sh` change — concrete diff

```diff
   if [ "$SEED" = true ]; then
     echo "  seeding base data..."
     docker compose exec -T api python bin/install_demo_data.py ...
     echo "  seeding per-plugin data..."
     for plugin in $enabled_plugins; do ... done

+    echo "  applying instance overlay seed..."
+    docker compose exec -T -e PYTHONPATH=/app -v /opt/vbwd/bin:/opt/vbwd/bin:ro \
+      api python /opt/vbwd/bin/apply-instance-seed.py --instance "$instance" \
+      || echo "  WARN: instance overlay failed"
   fi
```

Note: `-v` in `docker compose exec` isn't supported (different from `docker run`).
Implementation will instead copy the script into the container via
`docker cp` before `exec`, or mount it via the compose file. Final choice
made during implementation — outcome is the same.

## Sprint 25 (blog archive view) — follow-up stub

`docs/dev_log/20260403/sprints/25-cms-blog-category-view.md` will be
created in this sprint with scope:

- `CmsCategory.is_blog_home: bool` flag (and admin-UI toggle)
- `/blog` public route serves the category assigned as blog home, with
  paged list + archive by month + search query param
- Category detail page `/blog/<category-slug>` with same paging/search
- fe-user CMS plugin route additions
- Migration `20260420_cms_category_blog_home.py`

No code for sprint 25 is written in this sprint — just the doc, so the
`Blog` menu link has a tracked follow-up and isn't a silent TODO.

## Test plan

1. **Local dry-run**: run overlay against `instances/local` — inspect
   via `GET /api/v1/cms/widgets` that header has the main-vertical items.
2. **Playwright**: extend `prod-admin-plugin-config-diag.spec.ts` (or a
   new spec) to assert the header `<nav>` renders the expected items per
   vertical URL. Runs against both `localhost` and `vbwd.cc`.
3. **Idempotency**: run overlay twice, assert widget/page counts and
   menu-item ordering identical on second run.

## Rollout

1. Land changes in `vbwd-demo-instances` and bump the submodule pointer in
   `vbwd-sdk`.
2. Ask user to provision DNS + Hestia for `saas.vbwd.cc`.
3. Trigger deploy workflow with `seed_data: true` — existing verticals
   get their overlay applied, `saas` gets first-time setup.
4. Verify menus via Playwright specs against prod.
5. Rollback is automatic: not ticking the seed box leaves prod untouched.

## Effort estimate

- `apply-instance-seed.py` + schema: ~2h
- Six `instance-seed.json` files: ~1h
- `saas` instance scaffolding + workflow wiring: ~1h
- Playwright menu-assertion specs: ~1h
- CI sanity run + tweaks: ~1h

Total: **~6 hours** of coding + one deploy cycle for verification.

## Approval gate

Sprint ready for implementation. Reply "go" to start — I'll open a
working branch only on `vbwd-demo-instances` (plugin repos untouched
per non-goal #1) and push commits as each section lands.
