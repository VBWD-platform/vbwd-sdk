# S84 — Currency admin tab (active/available, default, cross-rate base, editable rate sheet)

**Area:** **core** `vbwd-backend` (admin currency routes + `CurrencyService` + one core setting) · `vbwd-fe-admin` (new "Currency" sub-tab on the Taxes & Countries page) · **Depends on:** core `Currency` model + `CurrencyService` (exist), `currencies` data-exchange exchanger (exists), core settings store S57 (exists), the `TaxAndCountriesSettings` sub-tab shell (S72.1).
**Engineering requirements:** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **NO OVERENGINEERING** — **BINDING** per [`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md) (most recent restatement: [`../../20260611/sprints/_engineering_requirements.md`](../../20260611/sprints/_engineering_requirements.md)). Quality guard: `bin/pre-commit-check.sh --full` green on core + fe-admin Vitest/ESLint/vue-tsc green. **Not committed** without explicit instruction.

## Problem
Currencies exist in core (`vbwd_currency`: EUR default, USD) but there is **no admin UI** to manage them — only a data-exchange export/import. The admin needs, on `/admin/settings/tax-and-countries`, a **Currency** tab with four blocks: (1) pick which currencies are active, (2) pick the **default** currency (the one prices are stored in), (3) choose whether cross-rates are expressed against the **default** currency or against **USD**, and (4) an **editable rate sheet** that recomputes when the base flips.

## Grounding (verified)
- **Model** `vbwd/models/currency.py` → `Currency` (`vbwd_currency`): `code` (ISO-3, unique), `name`, `symbol`, **`exchange_rate`** (`Numeric(10,6)`, **= units of THIS currency per 1 unit of the DEFAULT currency**; the default's own rate is `1.0`), `is_default` (bool), `is_active` (bool), `decimal_places` (int). Helpers: `convert_from_default`/`convert_to_default`/`convert_to`/`format`. Today: EUR `1.000000` default+active; USD `1.080000` active (1 EUR = 1.08 USD).
- **Service** `vbwd/services/currency_service.py` → `CurrencyService` (+ `CurrencyRepository`): `get_default_currency`, `get_active_currencies`, `get_currency_by_code`, `convert`, `update_exchange_rate(code, rate)` (raises on default / unknown). **No** `set_default`/`set_active` yet.
- **No admin routes** for currencies (only the `currencies` exchanger, `core_exchangers.py`, natural key `code`). No `default_currency` key in `core_settings_store.py` — the default is the `is_default=True` row.
- **fe-admin** Taxes&Countries shell: `vue/src/views/TaxAndCountriesSettings.vue` (button-toggle sub-tabs `countries|tax`, lazy-mount) mounting `vue/src/views/tax-countries/{CountriesTab,TaxesTab}.vue`. Countries use a **custom two-panel active/available selector + search** (`useCountriesStore`); `DualListSelector.vue` is the reusable two-panel `+`/`×` picker. `ImportExportControls` is embedded per tab via `useDataExchangeManifest` + `createDataExchangeApi`. **No** currencies store/UI exists.

## Storage model (decided)
| Tab data | Stored as | Where |
|---|---|---|
| Active / available set (block 1) | `active_currencies: [<code>]` | **core settings JSON** |
| Default currency (block 2) | `default_currency: <code>` | **core settings JSON** |
| Cross-rate base (block 3) | `cross_rate_base: "default"\|"usd"` | **core settings JSON** |
| Rates (block 4) + catalog | `exchange_rate` (per default) + `code/name/symbol/decimal_places` | `vbwd_currency` (DB) |

So **settings JSON is the source of truth for active/default/base**; `vbwd_currency` is the **catalog + rates** only. The `is_active`/`is_default` columns are removed (one source of truth). The tab's single import/export operates on the `currencies` table (catalog + rates); active/default/base travel with the general settings file.

## Locked decisions
| # | Decision |
|---|---|
| **D1 — Config in core settings JSON; catalog+rates on the table.** | `default_currency`, `active_currencies`, and `cross_rate_base` are keys in `DEFAULT_CORE_SETTINGS` (file-backed, round-tripped via `GET\|PUT /api/v1/admin/settings`). `vbwd_currency` holds the selectable catalog (`code/name/symbol/decimal_places`) + each currency's `exchange_rate`. **Drop the `is_active`/`is_default` columns** (they'd be a second source of truth). `CurrencyService` reads the default/active set **from settings** and resolves the rows from the catalog. |
| **D2 — Rates stay default-relative; USD-base is a VIEW transform.** | `Currency.exchange_rate` = currency-per-default (default = 1.0). "cross-rate base = USD" is a **frontend presentation/edit transform** crossed via the default — no rate-table, no per-pair rows, no provider/fetcher. USD-base requires USD ∈ `active_currencies`; else the FE disables the USD option. |
| **D3 — Setting default re-bases the stored rates.** | `set_default(code)` writes `settings.default_currency = code`, sets that catalog row's `exchange_rate = 1.0`, and **re-bases every other currency**: `new_rate_X = old_rate_X / old_rate_<newdefault>`. Only a currency in `active_currencies` may become default. `convert` is behaviour-preserving across the switch (just re-based). |
| **D4 — Narrow admin routes mirroring `tax.py`.** | New core blueprint `vbwd/routes/admin/currency.py` under `/api/v1/admin/currencies`, gated `settings.view`/`settings.manage`, registered in `app.py`. `GET` composes the catalog with `is_active`/`is_default` **derived from settings** (not columns). activate/deactivate/set-default **write settings**; rate `PUT` writes the table. Nothing speculative. |
| **D5 — Deactivate is non-destructive; the default is protected.** | Deactivating removes the code from `active_currencies` (the catalog row + historical invoices referencing the `code` are untouched); the **default cannot be deactivated** (400), and its rate is fixed at `1.0` (rate edits on it → 400). |
| **D6 — Exactly one bulk import/export on the tab.** | A **single** `ImportExportControls` scoped to the `currencies` entity (the catalog + rates table — unlike the Taxes tab's two controls). Active/default/base are settings, surfaced through the tab's own controls and carried by the general settings file, so no second control is needed on the tab. |

## Core changes (backend)

### Model + migration
- **Migration** (core, standalone): **drop `is_active` and `is_default`** from `vbwd_currency`, and **widen `exchange_rate` from `Numeric(10,6)` to `Numeric(18,8)`** so a stored rate holds ≥1e-8 (needed for the 1e-7 conversion-accuracy guarantee, esp. after a USD-base edit re-bases a rate to >6 dp). Validate up→down→up (down re-adds the columns nullable + narrows the rate back).
- **Model** `Currency`: remove the two columns + their `to_dict()` entries; widen the `exchange_rate` column type; keep `convert_*`/`format`. **All conversion math uses `Decimal` end-to-end (never `float`)** so accuracy never drifts.

### Core settings (`core_settings_store.py`)
Add to `DEFAULT_CORE_SETTINGS` + validators, surfaced through the existing `GET|PUT /admin/settings` (no new endpoint):
- `default_currency` (string ISO-3, default `"EUR"`) — validate it exists in the catalog and is in `active_currencies`.
- `active_currencies` (list of ISO-3, default `["EUR"]`) — validate each exists in the catalog; the default must be a member.
- `cross_rate_base` (`"default"|"usd"`, default `"default"`).

### `CurrencyService` (settings-sourced; DI gains the settings store)
- `get_default_currency()` → resolve `settings.default_currency` against the catalog (raise if missing).
- `get_active_currencies()` → resolve `settings.active_currencies` against the catalog.
- `set_active(code, active)` → add/remove `code` in `settings.active_currencies`; **raise** when removing the default.
- `set_default(code)` → D3: write `settings.default_currency` + re-base the catalog rows in one transaction; raise if `code` is unknown or not active.
- `update_exchange_rate(code, rate)` → table write; raise on default or `rate ≤ 0`.
- `find_default`/`find_active` on the repo (column queries) are removed.

### `currencies` exchanger
Drop `is_active`/`is_default` from `public_fields` → `code/name/symbol/exchange_rate/decimal_places`. (One import/export = catalog + rates; active/default/base are settings.)

### Routes — `vbwd/routes/admin/currency.py` (blueprint `admin_currencies_bp`, registered in `app.py`)
| Method · path | Body | Returns | Perm | Errors |
|---|---|---|---|---|
| `GET /api/v1/admin/currencies` | — | `{"currencies":[{code,name,symbol,exchange_rate,decimal_places,is_active,is_default}]}` — `is_active`/`is_default` **derived from settings**; sorted active-first then code | `settings.view` | — |
| `POST /api/v1/admin/currencies/<code>/activate` | — | `{"currencies":[…]}` | `settings.manage` | 404 unknown |
| `POST /api/v1/admin/currencies/<code>/deactivate` | — | `{"currencies":[…]}` | `settings.manage` | 400 if default · 404 |
| `POST /api/v1/admin/currencies/<code>/set-default` | — | `{"currencies":[…]}` (re-based) | `settings.manage` | 400 if not active · 404 |
| `PUT /api/v1/admin/currencies/<code>/rate` | `{"exchange_rate": <number>}` | `{"currency":{…}}` | `settings.manage` | 400 if default / `≤0` · 404 |

**Consumers:** grep for direct `is_default`/`is_active`/`find_default`/`find_active` currency reads (demo seed, pricing, invoices) and route them through `CurrencyService` so settings stays the single source of truth.

## fe-admin changes
- **`vue/src/stores/currencies.ts`** (new) — `fetchCurrencies()` (GET), `activate(code)`/`deactivate(code)`, `setDefault(code)`, `updateRate(code, exchange_rate)`; getters `active`, `available` (inactive), `defaultCurrency`. Reuses the `api` singleton (no bespoke service), mirroring `countries.ts`/`taxAdmin.ts`.
- **`vue/src/views/tax-countries/CurrenciesTab.vue`** (new) — the four blocks (below).
- **`vue/src/views/TaxAndCountriesSettings.vue`** — extend the sub-tab union to `'countries' | 'tax' | 'currencies'`, add the **Currency** button + lazy-mount `CurrenciesTab` (same pattern as `TaxesTab`).
- **i18n** `currencies.*` keys in all 8 shipped locales.
- **One bulk import/export** (D6) — a single `ImportExportControls entity-key="currencies"` on the tab (JSON+CSV), wired via `useDataExchangeManifest` + `createDataExchangeApi` exactly like the other tabs. Because the `currencies` exchanger already carries `code/name/symbol/exchange_rate/is_default/is_active/decimal_places`, this one control round-trips the **entire** tab state (active set, default, and all rates) — no second control.

### The four blocks (FE behaviour)
1. **Active / Available selector (+ quick search).** Two-panel picker (reuse `DualListSelector` or the CountriesTab two-panel idiom) over all currencies; moving right→active calls `activate(code)`, left→available calls `deactivate(code)`. Search filters both panels. The **default currency is pinned active** (cannot be moved to available).
2. **Default currency selector.** A `<select>` of **active** currencies bound to the current default; changing it calls `setDefault(code)` (confirm dialog — it re-bases rates), then refetches. Label: "Prices are stored in this currency."
3. **Cross-rate base switcher** (`default` | `USD`) bound to the `cross_rate_base` setting (load/save via `/admin/settings`). USD option **disabled** unless USD is active. When `usd`, the rate sheet (block 4) adds the **default-currency forex row** `<DEFAULT>USD` (e.g. `EURUSD`).
4. **Editable rate sheet.** Rows = active currencies (excluding the row that would be 1.0 in the current base). Each row: pair label + an editable number + the inverse shown read-only. **Math (D1):**
   - **base = default:** row per active non-default currency `X` → pair `${X.code}${default.code}`, value = `X.exchange_rate` (X per default). Save → `updateRate(X.code, value)`.
   - **base = USD** (USD active): row per active currency `X` where `X ≠ USD` → pair `${X.code}USD`, value = `X.exchange_rate / USD.exchange_rate` (X per USD). Save → `updateRate(X.code, value * USD.exchange_rate)`. The **default** currency gets a row too (`${default.code}USD`, value = `USD.exchange_rate` = USD per default; save → `updateRate('USD', value)`). Editing the `<DEFAULT>USD` row re-bases the whole USD view (it changes USD's stored rate). USD's own `USD`-vs-`USD` row is omitted (always 1).
   - All displayed values rounded to 6 dp; client-side validation `> 0`.

## TDD
**Backend (core; house pattern — unit MagicMock, integration real PG):**
- migration: up→down→up; after upgrade `vbwd_currency` has no `is_active`/`is_default` columns.
- settings validators: `default_currency` rejected if not in the catalog or not in `active_currencies`; `active_currencies` rejected if a code isn't in the catalog or omits the default; `cross_rate_base` rejects anything not in `{"default","usd"}` — all via `PUT /admin/settings`.
- `get_default_currency`/`get_active_currencies`: resolved from settings against the catalog.
- `set_active`: adds/removes the code in `settings.active_currencies`; removing the default → error (→ 400 at route).
- `set_default`: writes `settings.default_currency` + re-bases catalog rows by `old_rate / old_rate_<newdefault>` (assert exact values, e.g. EUR→USD: USD `1.08`→`1.0`, EUR `1.0`→`1/1.08`); non-active target → error (→ 400).
- `update_exchange_rate`: updates a non-default rate; default or `≤0` → error (→ 400).
- routes: GET lists the catalog with `is_active`/`is_default` **derived from settings** (active-first); activate/deactivate/set-default/rate happy paths + the 400/404 cases; all gated (`settings.view`/`settings.manage`).
- exchanger: `currencies` export no longer includes `is_active`/`is_default`; round-trips `code/name/symbol/exchange_rate/decimal_places` by `code`.

**Conversion accuracy — ≤ 1e-7 abs error, every base, `Decimal`-only (no float drift):**
- `CurrencyService.convert(amount, A, B)` crosses via the default (`A → default → B`); against a representative grid with hand-computed expected values (EUR default; e.g. 100 GBP→JPY, 250 USD→GBP, 1 default→X) assert `abs(result - expected) ≤ 1e-7`.
- **Base-invariance:** the real-world result is independent of which currency is default — `convert(x, A, B)` after `set_default('USD')` re-bases matches the pre-switch value within `1e-7` (e.g. GBP→JPY identical with EUR-base vs USD-base). Run the same grid for ≥2 different defaults (EUR and USD) and a non-USD third base.
- **Round-trip:** `convert(convert(x, A, B), B, A)` returns `x` within `1e-7` for a sweep of amounts and pairs.
- **No float drift:** conversions return `Decimal` (assert the type) and a known float-fragile case (e.g. `0.1+0.2`-style rate products) stays exact to 1e-7.
- **set_default re-base preserves cross-rates:** after re-basing, every pairwise `convert` matches its pre-switch value within `1e-7` (the re-base is value-preserving).

**fe-admin (Vitest):**
- store: each action hits the right endpoint with the right payload; getters split active/available; default getter.
- block 1: search filters; moving a currency calls activate/deactivate; the default cannot be deactivated.
- block 2: changing the select calls `setDefault`.
- block 3: switcher loads/saves `cross_rate_base`; USD disabled when USD inactive; flipping to USD adds the `<DEFAULT>USD` row.
- block 4 (the core math): with EUR default + USD `1.08` + GBP `0.85` (per EUR) — base=default shows `GBPEUR=0.85`, editing → `updateRate('GBP',0.85)`; **base=USD** shows `GBPUSD=0.85/1.08` and `EURUSD=1.08`, editing `GBPUSD=v` → `updateRate('GBP', v*1.08)`, editing `EURUSD=v` → `updateRate('USD', v)`.
- block 4 accuracy (≤ 1e-7): the view↔store transform is lossless — flipping base default→USD→default reproduces every original stored rate within `1e-7`; displaying then saving an unchanged USD-base value writes back the same default-relative `exchange_rate` within `1e-7`; the FE computes with full precision (string/`Number` carrying ≥8 dp, not rounded to 2) and only rounds for display.
- import/export (D6): exactly one `ImportExportControls` renders, scoped to `currencies`, exposing JSON+CSV; export routes through `POST /admin/data-exchange/currencies/export`; hidden when the manifest denies it.

## Walkthrough proof (part of DoD)
An HTML confirmation report **`docs/dev_log/20260613/walkthrough/s84-WALK-REPORT-currency.html`** (screenshots in `s84-currency-shots/`, Playwright-driven against the local stack, admin login per [[project_fe_admin_e2e_auth_harness]]) with screenshots, in order:
1. The **Currency** sub-tab on `http://localhost:8081/admin/settings/tax-and-countries` showing all four blocks + the single import/export control.
2. **Block 1** — active/available two-panel selector with the quick-search filtering; one currency moved active (e.g. activate GBP).
3. **Block 2** — the default-currency selector.
4. **Block 3 + 4, base = default** — the rate sheet showing default-relative pairs (e.g. `GBPEUR`, `USDEUR`), one rate edited + saved.
5. **Block 3 + 4, base = USD** — after flipping the switcher: the recomputed sheet showing `…USD` pairs **plus** the editable `EURUSD` default-currency row.
6. A **default-change re-base**: switch the default (e.g. EUR→USD) and show the rate sheet re-based (the same screenshot evidence the `set_default` re-basing produced correct values).

## Definition of done
The Taxes & Countries page has a **Currency** sub-tab with the four blocks: active/available picker with search; a default-currency selector that re-bases rates; a default-vs-USD cross-rate switcher persisted as `cross_rate_base`; an editable rate sheet that recomputes correctly between bases and saves back to the default-relative `exchange_rate`; and exactly one `currencies` bulk import/export (D6). **Active set + default + base live in the core settings JSON** (single source of truth); `vbwd_currency` is catalog + rates only (the `is_active`/`is_default` columns dropped via a core migration). Core stays agnostic (currency is core); `bin/pre-commit-check.sh --full` green on core + fe-admin Vitest/ESLint/vue-tsc green; the **walkthrough report above produced and reviewed** (screenshots of all four blocks in both rate bases). Not committed.
