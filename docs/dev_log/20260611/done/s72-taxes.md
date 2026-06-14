# S72 — Taxes & Countries (umbrella)

**Area:** **core** `vbwd-backend` · `vbwd-fe-admin` · plugins `subscription` / `shop` / `booking` · `vbwd-fe-user`. **Depends on:** core Tax model + `/admin/tax/*` (exist), unified data-exchange (exists, json+csv), core settings store S57 (exists), `DualListSelector` (exists).
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering; core stays agnostic (plugins reference the core Tax catalog, core never imports a plugin). Guard: `bin/pre-commit-check.sh --full` on every touched repo + fe Vitest/ESLint. See `docs/dev_log/20260526/sprints/_engineering-requirements.md`. **Not committed.**

Split into four independently-shippable sub-sprints — recommended order 72.1 → 72.2 → 72.3 → 72.4:

| # | Sub-sprint | Scope |
|---|-----------|-------|
| 72.1 | [Dedicated "Taxes & Countries" page](s72-1-tax-countries-page.md) | New Settings sub-item + route `/admin/settings/tax-and-countries`; move the Countries + Taxes tabs out of `Settings.vue`. (fe-admin only.) |
| 72.2 | [Tax import/export (JSON + CSV)](s72-2-tax-import-export.md) | Add `taxes` + `tax_classes` data-exchange exchangers (json+csv, FK by class `code`); embed import/export controls in the tab + the Import/Export page. |
| 72.3 | [Per-entity tax assignment + pricing](s72-3-entity-tax-assignment.md) | M2M join tables (plan/product/resource → core `vbwd_tax`), a `DualListSelector` "Taxes" block in each edit form, pricing sums applied taxes (net/gross). In-use tax delete blocked (409). |
| 72.4 | [Netto/brutto display](s72-4-netto-brutto-display.md) | Global `prices_display_mode` (core setting, default brutto) + nullable per-entity `price_display_mode` override; fe-user shows net/gross with a "netto price" tag when an item differs. |
| 72.5 *(optional)* | invoice/checkout-time multi-tax line application | Only if it exceeds the S72.3 sum-of-rates read-path. |

## Grounding (shared)
- **Tax is core.** `vbwd/models/tax.py`: `TaxClass` (`vbwd_tax_class`), **`Tax`** (`vbwd_tax`: name, code, `rate`, country_code, region_code, tax_class_id, is_active, `is_inclusive`; `calculate`/`calculate_gross`/`extract_net`/`extract_tax`/`is_applicable`), `TaxRate` (historical). CRUD `vbwd/routes/admin/tax.py` → `/api/v1/admin/tax/rates` (the `Tax` rows) + `/api/v1/admin/tax/classes`, gated `settings.manage`. Stores: `vue/src/stores/taxAdmin.ts`, `vue/src/stores/countries.ts`.
- **Countries** core: `vbwd/models/country.py` + a `countries` exchanger (wraps `country_io`). Tabs are inline in `vue/src/views/Settings.vue` (`countries-content`, `tax-content`).
- **Data-exchange** already supports `supported_formats=frozenset({"json","csv"})` (see `currencies`); registered in `vbwd/services/data_exchange/core_exchangers.py` → `build_core_exchangers`/`register_core_exchangers`. No `taxes` exchanger yet.
- **Entities** lack a tax link: `TarifPlan` (`subscription_tarif_plan`), `Product` (`shop_product`, legacy `tax_class` string only), `BookableResource` (`booking_resource`).
- **Netto/brutto:** none today; global default → `core_settings_store.py` (S57, `DEFAULT_CORE_SETTINGS` whitelist, `GET|PUT /admin/settings`).
- **Picker:** `vue/src/components/DualListSelector.vue`. **Core migration head:** `20260608_inv_admin_idx` (verify); plugin heads verify per plugin.

## Definition of done (umbrella)
All four sub-sprints' DoDs met: Countries+Taxes on their own page; taxes export/import json+csv from both entry points; the three entities carry assignable taxes reflected in pricing; a global netto/brutto switch with per-entity override + "netto price" tag on fe-user. Core stays agnostic; every touched repo green under `--full`. Not committed.
