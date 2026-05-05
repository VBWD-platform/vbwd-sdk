# 2026-05-05 — checkout-confirmation 404 fix, meinchat rollout, plugin baseline-config rule

**Date:** 2026-05-05
**Author:** dantweb (with Claude Code, Opus 4.7)
**Scope:** production hotel.vbwd.cc 404 incident → architectural fix → universal coverage → admin UI styling sweep → vbwd.cc plugin enablement → standalone-repo backfill

---

## 1. Incident

User reported a 404 after booking and paying:

```
https://hotel.vbwd.cc/checkout/confirmation?invoice_id=80e67bf1-c449-4063-8667-8b5959f3bd5b
```

The fe-user `checkout` plugin registers `/checkout/confirmation` and
loads `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` with
`{ slug: 'checkout-confirmation' }` (`vbwd-fe-user/plugins/checkout/index.ts:25`).
On the hotel instance the CMS had no row with that slug, so
`CmsPage.vue` rendered its built-in 404 fragment.

The page seeding existed only in `vbwd-backend/plugins/shop/populate_db.py:929-1024`
(layout + `CheckoutConfirmation` vue-component widget + page +
content-below support HTML), and the `shop` plugin is not enabled on
hotel — so hotel never got the row.

## 2. Architectural fix

Extracted a shared, idempotent seeder so every billing-completing
plugin can call it.

**New backend plugin:** `vbwd-backend/plugins/checkout/`

- `__init__.py` (empty marker)
- `populate_db.py` — exposes `populate_checkout_cms()`
- `.gitignore`
- Pushed as new public repo: `VBWD-platform/vbwd-plugin-checkout`
  (commit `6973794`)

The seeder creates:

- `CmsLayout` slug `checkout-confirmation` with header / confirmation /
  content-below / footer areas
- `CmsWidget` slug `checkout-confirmation`, type `vue-component`,
  pointing at the registered `CheckoutConfirmation` widget
- `CmsLayoutWidget` rows wiring the widget into the `confirmation` area,
  plus header/footer if those widgets exist on the instance
- `CmsPage` slug `checkout-confirmation`, attached to the layout
- `CmsPageContentBlock` for the `content-below` area with the canonical
  support / FAQ HTML

All inserts go through a `_get_or_create` helper, so re-running is a
no-op. Safe to call from multiple seeders.

**Callers wired up (in their standalone repos):**

| Plugin | Repo | Commit | Notes |
|---|---|---|---|
| shop | `vbwd-plugin-shop` | `ec0c98c` | replaced ~70 lines of inline seeding with a call to `populate_checkout_cms()` |
| booking | `vbwd-plugin-booking` | `2bee58e` | added the call after its own CMS seeding section |
| subscription | `vbwd-plugin-subscription` | `54ac821` | added the call to guarantee universal coverage — subscription is enabled on every vertical |

## 3. Universal coverage

Per-instance backend plugin manifest (from
`vbwd-demo-instances/instances/<inst>/backend/plugins.json`):

| Instance | Backend plugins enabled | Seeder path that fires `populate_checkout_cms()` |
|---|---|---|
| main | cms, email, stripe, **subscription**, taro | subscription |
| shop | cms, discount, email, **shop**, stripe, **subscription** | shop + subscription |
| hotel | **booking**, cms, email, stripe, **subscription** | booking + subscription |
| doctor | **booking**, cms, email, stripe, **subscription** | booking + subscription |
| ghrm | cms, email, ghrm, stripe, **subscription** | subscription |

`subscription` is on every vertical, so the page is now seeded
everywhere on next deploy with `seed_data=true`.

## 4. CI plumbing

`vbwd-demo-instances/.github/workflows/deploy.yml:109` clones a fixed
list of standalone backend plugin repos. Added `checkout` to that list
(commit `78ba6fe` on `vbwd-demo-instances/main`). Without it the
backend Docker image wouldn't have the `plugins/checkout/` directory
and the cross-plugin import `from plugins.checkout.populate_db import
populate_checkout_cms` would crash the booking / shop / subscription
populates.

`recipes/push-plugins.sh` updated locally to include `checkout` in the
backend push loop (uncommitted in the SDK monorepo).

**Side note discovered & fixed:** `instances/local/fe-user/plugins.json`
had a stray `vbwd-demo-instances` paste on line 9 making the file
invalid JSON. Cleaned up.

## 5. Verification — local Playwright

Before any prod push, ran the booking populate locally inside the api
container, then verified end-to-end through the SPA:

`vbwd-fe-user/vue/tests/e2e/checkout/checkout-confirmation-page-exists.spec.ts`

- `[data-testid="checkout-confirmation"]` mounts at
  `/checkout/confirmation?invoice_id=…`
- `.cms-page__not-found` is never rendered
- `[data-testid="confirmation-banner"]` is visible
- `GET /api/v1/cms/pages/checkout-confirmation` returns 200 with
  `is_published=true` and a `layout_id`

All passing against `localhost:8080`.

User confirmed prod hotel.vbwd.cc fixed after deploy.

## 6. Plugin config-files baseline rule

Established (and saved to memory): every plugin (backend, fe-admin,
fe-user) MUST ship `config.json` + `admin-config.json` at the plugin
root, even when it has no real config. The minimum baseline is a
`debug_mode` boolean toggle (debug = on, live = off).

Why:
- `vbwd-fe-admin/vue/src/views/PluginDetails.vue:128-291` always tries
  to render the plugin's settings page; missing files leave it blank.
- Ops needs a uniform way to flip a plugin into debug mode without code
  changes.

**Schema verified against the actual parser** at
`PluginDetails.vue:148-217`:

`admin-config.json` must use `field.key` + `field.component` (NOT
`field.name`/`field.type`). Allowed `component` values: `checkbox`,
`input` (with `inputType` text|number), `select` (with `options`),
`textarea`. Anything else won't render.

**Memory saved:**
`~/.claude/projects/-Users-dantweb-dantweb-vbwd-sdk-2/memory/feedback_plugin_baseline_config_files.md`

## 7. meinchat — config files added + admin styling

| Plugin | Files changed | Result |
|---|---|---|
| backend `meinchat` | `config.json` + `admin-config.json` created | new debug_mode + max_message_length + image_max_size_bytes |
| fe-admin `meinchat-admin` | `config.json` + `admin-config.json` updated | added debug_mode toggle, kept default_per_page + show_system_messages |
| fe-user `meinchat` | `config.json` + `admin-config.json` updated | added debug_mode toggle in new "General" tab, kept showTokenButton |

**Standard table styling rolled out** to all three meinchat-admin
moderation views (matching `vbwd-fe-admin/plugins/cms-admin/src/views/CmsLayoutList.vue:226-256`):

- `MeinchatNicknamesList.vue` — added the canonical `.cms-table` /
  `.cms-list__header` / `.cms-list__pagination` / `.cms-list__search` /
  `.btn` style block. Tables now render full-width with proper header
  background and row borders.
- `MeinchatConversationInspector.vue` — converted the `<ol><li>` message
  list into a `<table class="cms-table">` with Sender / Time / Kind /
  Message columns. Multi-line bodies + image attachments render inline
  in the Message cell. Same canonical style block.
- `MeinchatTransfersList.vue` — added the canonical block, plus
  specificity fix (`.cms-table th.cms-table__num, .cms-table
  td.cms-table__num`) so the right-aligned + tabular-nums Amount column
  beats the default `.cms-table th, td { text-align: left }`.

All five files committed + pushed to `VBWD-platform/vbwd-fe-admin-plugin-meinchat`
as commit `7145dc0`.

## 8. meinchat — user dashboard nav

The fe-user `meinchat/index.ts` already registers a top-level sidebar
nav item via `userNavRegistry.register({ pluginName: 'meinchat', to:
'/dashboard/messages', labelKey: 'meinchat.nav.messages', testId:
'nav-messages' })` — same pattern as `taro` and `chat`. The plugin just
wasn't enabled in the local runtime manifest, so it didn't show up.
Enabled it in `var/plugins/fe-user-plugins.json`.

## 9. Verification — Playwright tests added

**fe-user — `vbwd-fe-user/vue/tests/e2e/meinchat-nav.spec.ts` (3/3 ✓):**

- top-level `[data-testid="nav-messages"]` rendered in the sidebar
- clicking it navigates to `/dashboard/messages`
- coexists with `[data-testid="nav-taro"]` and `[data-testid="nav-chat"]`

**fe-admin — `vbwd-fe-admin/vue/tests/e2e/meinchat-admin-assets.spec.ts` (7/7 ✓):**

- "Meinchat" sidebar section is rendered
- 3 routes resolve and don't render the 404 fragment:
  `/admin/meinchat/{nicknames,conversations,transfers}`
- Nicknames `.cms-table` is `> 400px` wide
- Header `<th>` has non-transparent background and ≥ 10px top padding
  (proves canonical style block applied)
- Conversations page `.cms-list__header h1` font-size ≥ 18px
- Transfers `.cms-table` width + header bg
- Transfers Amount column resolves to `text-align: right` with
  `tabular-nums` (catches future specificity regressions)

## 10. vbwd.cc (main instance) plugin enablement

Edited `vbwd-demo-instances` (uncommitted, ready for user's commit):

| File | Change |
|---|---|
| `instances/main/backend/plugins.json` | + `chat`, + `meinchat` (enabled) |
| `instances/main/fe-user/plugins.json` | + `chat`, + `meinchat` (enabled) |
| `instances/main/fe-admin/plugins.json` | + `meinchat-admin` (enabled) |
| `.github/workflows/deploy.yml:109` | `meinchat` added to backend clone list |
| `.github/workflows/deploy.yml:160` | `meinchat:vbwd-fe-user-plugin-meinchat` added |
| `.github/workflows/deploy.yml:232` | `meinchat-admin:vbwd-fe-admin-plugin-meinchat` added (using existing short-form repo, matching cms/email/ghrm/taro/subscription convention) |

## 11. Standalone-repo audit + backfill

Swept all plugin directories in `vbwd-backend/plugins/`,
`vbwd-fe-user/plugins/`, `vbwd-fe-admin/plugins/` against
`VBWD-platform/vbwd-plugin-*`, `vbwd-fe-user-plugin-*`,
`vbwd-fe-admin-plugin-*` repos via `gh repo view`.

**Genuinely missing repos created (public) + initial source pushed:**

| Repo | Source dir |
|---|---|
| `VBWD-platform/vbwd-fe-user-plugin-shop` | `vbwd-fe-user/plugins/shop` |
| `VBWD-platform/vbwd-fe-admin-plugin-discount` | `vbwd-fe-admin/plugins/discount-admin` |
| `VBWD-platform/vbwd-fe-admin-plugin-shop` | `vbwd-fe-admin/plugins/shop-admin` |

(Each got a `.gitignore` with `node_modules/`, `dist/`, `__pycache__/`,
mypy + pytest cache, and `.DS_Store`.)

**False positives in the initial audit, no action needed:**

- `vbwd-plugin-shipping_flat_rate` — exists with the **underscored**
  GitHub name (matches deploy.yml's `${plugin}` substitution); my first
  pass only checked the dashed variant.
- `vbwd-fe-admin-plugin-meinchat-admin` — never needed; the canonical
  repo is the short-form `vbwd-fe-admin-plugin-meinchat` (already
  exists, already wired to the local `meinchat-admin/.git`).

## 12. Open / handed back

- **User to commit + push** the staged changes in
  `vbwd-demo-instances/main` (manifest + deploy.yml).
- **Re-run deploy** for the `main` instance with `seed_data=true` —
  triggers `populate_checkout_cms()` via subscription, ships meinchat +
  chat + checkout-confirmation page on vbwd.cc.
- **Convention drift to clean up later (out of scope):**
  - `recipes/push-plugins.sh` and `deploy.yml` use inconsistent fe-admin
    repo naming — push-plugins.sh writes to `vbwd-fe-admin-plugin-<name>-admin`
    while deploy.yml clones from the short form `vbwd-fe-admin-plugin-<name>`.
    Result: some plugins have both forms public, with one stale.
  - `.cms-table` / `.cms-list*` style block is now duplicated across at
    least 7 view files (cms-admin × 3, email-admin × 2, meinchat-admin × 3).
    Per the planned fe-core design system, those should move to
    `vbwd-fe-core` and be consumed via shared CSS.

## 13. Files changed in this session — summary

**SDK monorepo (uncommitted unless noted):**

- `vbwd-backend/plugins/checkout/{__init__.py, populate_db.py, .gitignore}` — new (pushed standalone)
- `vbwd-backend/plugins/shop/populate_db.py` — pushed standalone (`ec0c98c`)
- `vbwd-backend/plugins/booking/populate_db.py` — pushed standalone (`2bee58e`)
- `vbwd-backend/plugins/subscription/populate_db.py` — pushed standalone (`54ac821`)
- `vbwd-backend/plugins/meinchat/{config.json, admin-config.json}` — new (uncommitted)
- `vbwd-fe-admin/plugins/meinchat-admin/{config.json, admin-config.json, src/views/*.vue}` — pushed standalone (`7145dc0`)
- `vbwd-fe-user/plugins/meinchat/{config.json, admin-config.json}` — uncommitted
- `vbwd-fe-user/vue/tests/e2e/checkout/checkout-confirmation-page-exists.spec.ts` — new
- `vbwd-fe-user/vue/tests/e2e/meinchat-nav.spec.ts` — new
- `vbwd-fe-admin/vue/tests/e2e/meinchat-admin-assets.spec.ts` — new
- `vbwd-demo-instances/instances/main/{backend,fe-user,fe-admin}/plugins.json` — uncommitted
- `vbwd-demo-instances/.github/workflows/deploy.yml` — uncommitted
- `recipes/push-plugins.sh` — uncommitted

**External (committed + pushed):**

- `VBWD-platform/vbwd-plugin-checkout` — created + initial commit
- `VBWD-platform/vbwd-fe-user-plugin-shop` — created + initial commit
- `VBWD-platform/vbwd-fe-admin-plugin-discount` — created + initial commit
- `VBWD-platform/vbwd-fe-admin-plugin-shop` — created + initial commit
- `VBWD-platform/vbwd-fe-admin-plugin-meinchat` — `7145dc0`
- `VBWD-platform/vbwd-plugin-shop` — `ec0c98c`
- `VBWD-platform/vbwd-plugin-booking` — `2bee58e`
- `VBWD-platform/vbwd-plugin-subscription` — `54ac821`
- `VBWD-platform/vbwd-demo-instances` — `78ba6fe` (deploy.yml `checkout` clone)
