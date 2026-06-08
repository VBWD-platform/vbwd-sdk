# Report 01 (2026-06-07) — Unified Data Exchange (S46) + persisted core settings (S57)

**Date:** 2026-06-07. **Method:** orchestrated via `vbwd-tdd` subagents (TDD-first, gate-driven), per [[feedback_use_tdd_agent_for_implementation]]. **Nothing committed** — all code on disk (plugins gitignored; core/fe/docs uncommitted).

## Headline

Shipped the whole **S46 Unified Data Exchange** feature (S46.0–S46.7) end-to-end — backend seam, core + CMS + 5-plugin exchangers, CLI, fe-core components, fe-admin UI — plus **S57** (persist core settings), an **asset-storage convention** (`var/assets/<owner>/…`), a **CMS sitemap test-isolation fix**, and two post-integration UI fixes surfaced in the live stack. Each repo's gate is green (only the known, unrelated GHRM env failures remain).

## What shipped

| Item | Area | Gate |
|---|---|---|
| **S57** persist core settings → `var/core/vbwd_settings.json` | core backend | ✅ `--full` A/B + oracles; 7 unit + 8 integ |
| **S46.0** data-exchange seam (registry/port/envelope JSON·CSV·ZIP/`BaseModelExchanger`/routes/perm-catalog/row cap) | core backend | ✅ 50 tests + oracles |
| **S46.1** 7 core exchangers (users+details, invoices-exp, payment_methods, access_levels, email_templates, currencies, countries) | core backend | ✅ 29 tests |
| **email templates → `var/assets/<owner>/email/templates/`** convention (`asset_dir` + EmailService override-first loader) | core backend | ✅ 46 targeted |
| **S46.3** fe-core components (`ImportExportPage`/`ImportExportControls`/`useDataExchange` + `DataExchangeApi` port) | fe-core | ✅ lint+test+build |
| **S46.4** fe-admin wiring (per-list controls + `dataExchangeTabs` slot + R12) | fe-admin | ✅ 513 unit/101 integ |
| **CMS sitemap test-isolation fix** | cms plugin tests | ✅ `--plugin cms --full` 142 integ |
| **S46.5** 6 CMS exchangers (posts carry S55 content_blocks/page_assignments; images base64/ZIP) | cms plugin | ✅ 150 integ |
| **S46.6** 5 plugin exchanger sets (subscription/booking/ghrm/shop/discount) | plugins | ✅ each `--plugin … --full` |
| **S46.2** `flask data-exchange list/export/import` CLI | core backend | ✅ 13 tests |
| **S46.7** architecture doc `docs/architecture/data-exchange.md` | docs | — |
| **Import/Export relocation** → last item in SETTINGS sidebar group (`/admin/import-export`) | fe-admin | ✅ 513/103 |
| **fe-core arbitrary-cluster fix** (page crashed on cms `content` cluster) | fe-core | ✅ +3 tests, dist rebuilt |

## S57 — persist core settings (the S46 unblocker)

Core settings (provider/contact/address + bank IBAN/BIC) were a **module-level in-memory dict** in `vbwd/routes/admin/settings.py` — wiped on restart, inconsistent across gunicorn workers, nothing to export. Replaced with `vbwd/services/core_settings_store.py`: file-backed at `${VBWD_VAR_DIR}/core/vbwd_settings.json` (atomic temp+`os.replace`, defaults-merge, known-key whitelist, corrupt→defaults). Route rewired; API/UI unchanged. `var/core/*.json` git-ignored. Fixes a latent prod bug as a bonus.

## S46 — Unified Data Exchange

**The seam (S46.0):** generic `EntityExchanger` port + `DataExchangeRegistry` (DI singleton) + `envelope` (VBWD JSON / CSV / ZIP bundle with zip-bomb + path-traversal guards) + `BaseModelExchanger` (UUID/secret strip, PII redaction, FK→natural-key, upsert/replace_all/dry-run-rolls-back, row cap) + `/api/v1/admin/data-exchange/*` routes + auto-derivation of permissions into `collect_permission_catalog()`. **Core stays vocabulary-free** (both oracles green); plugins register their exchangers in `on_enable`.

**Entities:** 7 core + 6 cms (`cms_posts` carries S55 `content_blocks`+`page_assignments`; `cms_images` base64/ZIP) + subscription(plans/addons/subscriptions-exp) + booking + ghrm(packages) + shop(products/orders-exp) + discount(rules/coupons). Export-only entities (invoices, subscriptions, shop_orders) raise `UnsupportedOperationError` (Liskov). Plugins reuse their existing permission names.

**CLI (S46.2):** `flask data-exchange list|export|import` — a thin adapter over the same exchangers/envelope the routes use.

**fe (S46.3/4 + relocation):** fe-core `ImportExportPage` (General tab, manifest grouped by cluster) + `ImportExportControls` (per-list Export selected/all/filter + Import) + `useDataExchange` + a host-injected `DataExchangeApi` port. fe-admin: **Import/Export is the last item in the SETTINGS sidebar group** (standalone `/admin/import-export`, R12-gated) — moved out of a Settings tab per the owner — plus per-list controls on Users/Invoices/Payment-methods/Access-levels. Permission gating: no perm ⇒ no nav entry + guarded route.

**Docs (S46.7):** `docs/architecture/data-exchange.md` (envelope, modes, REST, CLI, permissions, per-instance `enabled_entities`, security, how to add a plugin exchanger, follow-ups).

## Cross-cutting

- **Asset-storage convention:** `asset_dir(owner, *parts)` → `${VBWD_VAR_DIR}/assets/<owner>/…`. EmailService loads `var/assets/core/email/templates/` **override-first** (bundled defaults fallback); the `email_templates` exchanger exports bundled∪override and imports into `var/assets/`. `var/assets/` git-ignored. (This convention likely feeds the planned **S58 unified var/filesystem manager**.)
- **CMS sitemap test-isolation:** the cms SEO sitemap integration tests failed only in the *full* cross-plugin run. Root cause: the `_test` DB carried **persisted `sitemap_include_terms`/`exclude_terms` from S56 live-testing**, which filtered out all term-less test posts, layered on a sibling suite unregistering the sitemap provider on teardown. Fixed with a shared `plugins/cms/tests/integration/conftest.py` (forces the no-filter baseline + registers the provider, restores on teardown). Whole-backend integration now `581 passed`; the only failures are the GHRM `GHRM_USE_MOCK_GITHUB` env tests.

## Two live-stack fixes (post-integration)

1. **General tab crashed** with `Cannot read properties of undefined (reading 'push')`: `ImportExportPage` hard-coded `sales`/`settings` cluster buckets, but cms exchangers declare cluster `content`. Fixed to build buckets dynamically + Title-Cased fallback labels (clusters are exchanger-declared, R9).
2. **Export buttons did nothing** (Users + Invoices): the running fe-core `dist` predated the `responseType` addition, so `postForBlob` never received a Blob → silent no-op. Backend export endpoints verified working (`200` + valid envelopes); frontend flow verified correct; dist rebuilt (now contains `responseType` + the cluster fix), fe-admin Vite deps cache cleared, container restarted.

## Gate status

- backend `--full`: Part A/B green; Part C integration green **except the 9–10 GHRM `GHRM_USE_MOCK_GITHUB`/`software_category_slugs` env failures** (pre-existing, config/env, not code — green in CI).
- fe-core: lint 0 errors, dataExchange tests green, dist builds (2 pre-existing unrelated specs fail on baseline).
- fe-admin: `--full` green (eslint 0, vue-tsc clean, 513 unit / 103 integ).
- Core agnosticism + vocabulary oracles green throughout.

## Dev-stack lesson (recurring)

Every "it doesn't render/work" round today traced to the **fe-core `dist` + Vite deps cache being stale** in the local dev stack (the two-checkouts hazard): fe-admin dev resolves `vbwd-view-component` to the **top-level** `vbwd-fe-core` dist via mount+symlink, and Vite pre-bundles it into `.vite/deps`. After any fe-core source change you must **rebuild the top-level dist (in a linux container) AND clear `.vite` AND restart** the dev container — and hard-refresh the browser to drop the cached `?v=hash` module. The durable fix is to commit fe-core and let CI build the dist so the served bundle always matches source. See [[feedback_no_host_npm_install_in_bindmounts]]. Captured as [[project_fe_core_dist_vite_cache_staleness]].

## Not committed — ship-to-prod notes

All on disk. To reach prod: commit core (`vbwd/services/data_exchange/*`, `core_settings_store`, `asset_storage`, settings route, permission_catalog, app.py, CLI) → rebuild backend image; commit each plugin's exchangers to its standalone repo → rebuild backend image (plugins cloned at build); commit fe-core (components + `ApiClient.responseType` + cluster fix) to **`vbwd-fe-core`** → CI builds dist; commit fe-admin (adapter, ImportExport view, sidebar, router) → rebuild fe-admin image. Deploy with `skip_build=false`. The S57 file + `var/assets/` are runtime, git-ignored.

## Follow-ups (flagged, not in scope today)

`core_settings` exchanger (now unblocked by S57) · content-pack recipe wiring (decide replace vs supplement existing seeders) · fe-admin CMS `dataExchangeTabs` tab (entities already on the General tab) · retire bespoke cms/access legacy export routes · land the fe-core `ApiClient.responseType` + cluster fix in the `vbwd-fe-core` repo.
