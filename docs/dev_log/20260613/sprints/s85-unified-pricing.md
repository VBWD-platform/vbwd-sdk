# S85 — Unified pricing (one `PriceFactory`, computed `Price` value object, no per-item currency)

**Area:** **core** `vbwd-backend` (new `Price` value object + `PriceFactory` + `Priceable` protocol + one core setting; token-bundle storage) · plugins `subscription` / `shop` / `booking` (storage migration + protocol conformance) · `vbwd-fe-admin` (one new selector on the existing Price-display-mode settings block) · `vbwd-fe-core`/`fe-user` (consume the `Price` shape) · **Depends on:** core `Tax` model + Decimal helpers (S72), tax↔sellable joins (S72.3), per-item `price_display_mode` (S72.4), core settings store (S57), `default_currency` single-source-of-truth (S84), `CurrencyService` (exists), **`UserDetails.account_type` (S74) for the business-viewer netto overlay (S85.4)**.
**Engineering requirements:** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **NO OVERENGINEERING** — **BINDING** per [`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md) and this directory's anchor [`_engineering_requirements.md`](_engineering_requirements.md). Quality guard: `bin/pre-commit-check.sh --full` green on every touched repo (core + each touched plugin) + fe-admin/fe-core Vitest/ESLint/vue-tsc green. **Not committed** without explicit instruction ([[feedback_no_commit_without_ask]]).

## Problem
Money is modelled **differently in every domain** (see [`../reports/02-pricing-model-audit.md`](../reports/02-pricing-model-audit.md)). Each sellable (tarif plan, add-on, shop product, booking resource, token bundle) declares its own `price Numeric(10,2)` + a redundant `currency String(3)` (hardcoded `"EUR"`), some add a lossy `price_float` mirror, and a real core `Price` model (`vbwd_price`) exists but is **dead** — only `tarif_plan.price_id` references it, and even that keeps legacy `price`/`currency` alongside. There is **no single calculation path**: checkout, invoicing, catalog display, and payment each read `.price` and re-derive tax/totals ad hoc. Tax is linked to only 3 of 5 sellables. Net effect: inconsistent field names, dual storage types, currency stored in N places while S84 already made `default_currency` the single source of truth, and no one place that answers "what is the netto / tax / brutto of this thing?".

This sprint introduces **one** answer: `PriceFactory.get_price_from_object(<sellable>) -> Price`.

## Grounding (verified)
- **Sellables & storage today** (all `Numeric(10,2)` major units):
  - `plugins/subscription/.../tarif_plan.py:79` `price` (nullable, legacy) + `:67` `price_float Float` + `:71` `price_id`→`vbwd_price` + `:80` `currency String(3)` default `"EUR"`; `taxes` M2M (`subscription_tarif_plan_tax`, `:123`); `price_display_mode` (S72.4).
  - `plugins/subscription/.../addon.py:45` `price` + `:46` `currency` default `"EUR"`; **no `taxes`**, no display override.
  - `plugins/shop/.../product.py:60` `price` + `:61` `currency` default `"EUR"` + `:62` `price_float Float` + `:76` `price_display_mode`; `taxes` M2M (`shop_product_tax`, `:97`).
  - `plugins/booking/.../resource.py:83` `price` + `:84` `currency` default `"EUR"` + `:95` `price_display_mode`; `taxes` M2M (`booking_resource_tax`, `:113`).
  - `vbwd/models/token_bundle.py:21` `price` (core, "uses system default currency", **no currency column**, **no `taxes`**, no display override).
- **Core `Tax`** `vbwd/models/tax.py`: `rate Numeric(5,2)` (percent), `is_inclusive`, Decimal helpers `calculate(net)→tax`, `calculate_gross(net)→gross`, `extract_net(gross)→net`, `extract_tax(gross)→tax`.
- **Dead core `Price`** `vbwd/models/price.py` (`vbwd_price`): `price_decimal`, `price_float`, `currency_id`, `net_amount`, `gross_amount`, `taxes JSONB`. Referenced only by `tarif_plan.price_id` + demo/ghrm seeders. No service reads it.
- **Settings** `vbwd/services/core_settings_store.py:79` `prices_display_mode` default `"brutto"` (+ validator, `PRICES_DISPLAY_MODES`); `:81` `default_currency` default `"EUR"` (S84, single source of truth). Round-tripped via `GET|PUT /api/v1/admin/settings`.
- **Currency** `CurrencyService.get_default_currency()` resolves the catalog row for `settings.default_currency` (S84).
- **fe display** `vbwd-fe-core/src/utils/money.ts` — `roundToCents` / `formatMoney`. **Rounding happens here, at display — never in the backend calc.**

## The model (decided)

`Price` is a **computed value object** (a dataclass), never persisted:

```
Price:
  netto:   float                 # full precision, NEVER rounded in code
  taxes:   list[PriceTax]        # PriceTax{ code: str, rate: float, amount: float }
  brutto:  float                 # full precision; invariant: netto + Σ(taxes.amount) == brutto
  currency: str                  # ISO-3, the global default (resolved once, not stored per item)
```

Each **sellable stores exactly one number**: `price` as a **double float** (Postgres `double precision`), **never rounded in code**. The global `prices_mode_in_db` setting says how to *interpret* that number:
- `NETTO` (default): stored `price` is the net amount → `brutto = netto + Σ tax_i`, where `tax_i = netto · rate_i/100`.
- `BRUTTO`: stored `price` is the gross amount → `netto = brutto / (1 + Σ rate_i/100)`; `tax_i = netto · rate_i/100` (so `Σ tax_i = brutto − netto` by construction — invariant holds with no rounding).
- No linked taxes → `netto == brutto`, `taxes == []`.

`prices_display_mode` (existing) + the per-item `price_display_mode` override decide which of `netto`/`brutto` the **UI shows** — a display concern, unchanged here. `prices_mode_in_db` is a **storage-interpretation** concern, new here. The two are orthogonal.

| Concern | Setting / field | Owner | Added by |
|---|---|---|---|
| How the stored double is interpreted | `prices_mode_in_db` (global, `NETTO`\|`BRUTTO`, default `NETTO`) | core settings JSON | **S85** |
| Which side is displayed | `prices_display_mode` (global) + per-item `price_display_mode` override + **logged-in `business` viewer ⇒ netto** | core settings + item + viewer | S72.4 / **S85.4 (D9)** |
| Which currency everything is in | `default_currency` (global) | core settings JSON | S84 |
| The numbers themselves | `price` double float + linked `taxes` | each sellable table | **S85** |

## Locked decisions
| # | Decision |
|---|---|
| **D1 — One entry point.** | All price math goes through `PriceFactory.get_price_from_object(priceable) -> Price` (core `vbwd/pricing/`). No caller reads `.price` and re-derives tax/total. The factory is resolved via the DI container; it depends on the core settings store + `CurrencyService` only. |
| **D2 — `Priceable` is a structural protocol (DIP, core-agnostic).** | Core defines `typing.Protocol Priceable` with `raw_price: float`, `taxes: Sequence[Tax]`, and optional `price_display_mode: str \| None` (read via `getattr(obj, "price_display_mode", None)`). The factory dispatches by **protocol, never by concrete type** — so **core never imports a plugin model** ([[project_s01_core_agnosticism_oracle]]). Every sellable (plugin or core) conforms by exposing those attributes. |
| **D3 — `Price` is computed, not stored. Drop the dead `vbwd_price` table.** | The persisted `Price` model (`vbwd/models/price.py`, `vbwd_price`) and `tarif_plan.price_id` are removed (core + plugin migrations). The new `Price` is a `@dataclass` value object with `to_dict()`. One source of truth: the stored double + the global modes. |
| **D4 — Prices are double floats, never rounded in code.** | Migrate every sellable `price` from `Numeric(10,2)` to `db.Float` (PG `double precision`). The factory performs no `round()`/`quantize`; `Price.netto/brutto/taxes[].amount` carry full precision. **Rounding lives only at display** (`fe-core/money.ts`). Internal tax math may use `Decimal` for correctness but must **not quantize** before casting back to `float`. |
| **D5 — No currency in sellable tables.** | Drop the `currency` column from `tarif_plan`, `addon`, `shop_product`, `shop_order`/`order_item`, `booking_resource`. `Price.currency` is the global `default_currency` (resolved via `CurrencyService`) — the single source of truth (S84). Drop the lossy `price_float` mirrors (`tarif_plan`, `shop_product`); the single `price` double is enough. |
| **D6 — Complete the tax linkage so all five sellables are uniform.** | Add `subscription_addon_tax` (plugin) and `token_bundle_tax` (core) M2M join tables mirroring S72.3, so `addon` and `token_bundle` expose a `taxes` relationship like the others. Taxless items resolve to `netto == brutto`. Without this the "unified" goal leaks (two sellables can't carry tax). |
| **D7 — `prices_mode_in_db` is global only (no per-item override).** | One enum in `DEFAULT_CORE_SETTINGS` (`NETTO`\|`BRUTTO`, default `NETTO`), validated like `prices_display_mode`. A per-item storage-mode override is **out of scope** (no requirement; would be overengineering). |
| **D8 — Payment charge amount = `Price.brutto`.** | Checkout/invoice/payment derive the charge from `PriceFactory(...).brutto`. Each payment SDK adapter's existing minor-unit/major-unit conversion (Stripe cents vs PayPal major) is **left as-is** — a shared amount-adapter is a noted follow-up, not this sprint. |
| **D9 — Logged-in `business` viewer ⇒ netto (display only).** | The displayed side is resolved by ONE fe util `resolveDisplaySide(price, { itemMode, globalMode, user })` with strict precedence: **(1)** authenticated user whose `UserDetails.account_type == "business"` ⇒ **netto** — strongest, B2B norm, **wins even over a per-item `brutto` override**; **(2)** else per-item `price_display_mode` (`netto`\|`brutto`); **(3)** else global `prices_display_mode` (default `brutto`). Anonymous / `private` viewers keep today's behaviour. This is a **display concern only** — it never touches the stored price, the computed `Price` VO, or the charged `brutto` (D8). Depends on S74 exposing `account_type` to the fe auth store. |

## Sub-sprints

### S85.0 — Core: `Price` VO + `PriceFactory` + `Priceable` protocol + `prices_mode_in_db` setting
*No behaviour change to existing callers yet — the factory becomes available and tested.*
- `vbwd/pricing/price.py` — `@dataclass(frozen=True) Price` (`netto`, `taxes: list[PriceTax]`, `brutto`, `currency`) + `PriceTax` (`code`, `rate`, `amount`) + `to_dict()`.
- `vbwd/pricing/priceable.py` — `Priceable` `Protocol` (`raw_price`, `taxes`, optional `price_display_mode`).
- `vbwd/pricing/price_factory.py` — `PriceFactory(settings_store, currency_service)` with `get_price_from_object(priceable) -> Price`. Reads `prices_mode_in_db`, the item's `taxes`, the default currency code; computes netto/taxes/brutto per the model above; **no rounding**. Register as a DI provider.
- `core_settings_store.py` — add `prices_mode_in_db` (default `"NETTO"`) to `DEFAULT_CORE_SETTINGS`, a `PRICES_DB_MODES` constant, and a validator (mirrors `_validate_prices_display_mode`). Surfaced through existing `GET|PUT /admin/settings` (no new endpoint).
- **Oracle tests** (`tests/unit/pricing/test_price_factory.py`, MagicMock the settings store + currency service; a `FakePriceable`):
  - NETTO, no tax → `netto == brutto == raw`, `taxes == []`.
  - NETTO, one 19% tax → `brutto == netto*1.19`, one `PriceTax(rate=19, amount=netto*0.19)`.
  - NETTO, two taxes (19% + 7%) → additive; `Σamount == netto*0.26`; invariant `netto + Σ == brutto`.
  - BRUTTO, one 19% tax → `netto == brutto/1.19`; `Σ tax == brutto − netto`; invariant holds.
  - BRUTTO, two taxes → combined divisor `1 + (19+7)/100`; invariant holds.
  - `currency` == the default-currency code from the service.
  - No rounding: a raw value like `9.99` with 19% yields a non-2dp `brutto` (asserts the factory does **not** quantize).

### S85.1a — Remove the dead `vbwd_price` model + table (D3)
*Self-contained teardown of the unused persisted `Price` model — landed before the storage migration so the new computed `Price` value object (S85.0) is unambiguously the only `Price`. No behaviour change: nothing reads `vbwd_price`.*
- **Verify dead first (characterisation):** grep confirms the only references are `tarif_plan.price_id`, `vbwd/models/__init__.py`, the demo seeder (`vbwd/cli/_demo_seeder.py`), and the GHRM populate script (`plugins/ghrm/src/bin/populate_ghrm.py`) — no service/route reads it. A test asserts no runtime read path depends on the `vbwd_price` row.
- **Drop the `tarif_plan.price_id` FK** (plugin migration on `subscription`, before the core drop so the FK is gone first): drop the column + the `price` relationship in `tarif_plan.py`. The legacy `tarif_plan.price` double remains the source until S85.2 routes through the factory.
- **Drop the `vbwd_price` table** (core migration, standalone — must resolve plugin-free) and **delete `vbwd/models/price.py`** + its `vbwd/models/__init__.py` export. Validate up→down→up (down re-creates the table empty; the FK is *not* re-added on down — it lives in the plugin migration's own down).
- **Update seeders:** `_demo_seeder.py` + `populate_ghrm.py` stop creating `Price` rows / setting `price_id` (write the plain `price` double instead). Keep idempotent + cold-CI-safe.
- **Tests:** migration-wiring tests (revision linkage + `vbwd_price` table absence after up, presence after down) for both the plugin FK-drop and the core table-drop; seeder tests green without `vbwd_price`; the agnosticism oracle stays green.

### S85.1 — Storage migration + protocol conformance (core + subscription + shop + booking)
- **Migrations** (each in its own tree — plugin migrations in the plugin, core in `alembic/`; validate up→down→up):
  - `price`: `Numeric(10,2)` → `db.Float` on `tarif_plan`, `addon`, `shop_product` (+ `shop_order`/`order_item` price fields), `booking_resource`, `token_bundle` (+ `token_bundle_purchase`). Down re-narrows to `Numeric(10,2)`.
  - **Drop** `currency` from `tarif_plan`, `addon`, `shop_product`, `shop_order`, `booking_resource`; **drop** `price_float` from `tarif_plan`, `shop_product`.
  - **Add** `subscription_addon_tax` (plugin) + `token_bundle_tax` (core) join tables (S72.3 shape, FK `ondelete="RESTRICT"`).
- **Models** conform to `Priceable`: expose `raw_price` (property → `price`), keep/rename `taxes` uniformly, add `taxes` relationship to `AddOn` + `TokenBundle`. Fix `to_dict()` (drop `currency`/`price_float`; keep raw `price`; optionally embed the computed `Price` via the factory at the route layer, not the model).
- **Tests:** model characterisation (price is float, no currency attr, `taxes` present on all five); migration-wiring tests (revision linkage + table/column presence) mirroring the S72.3 wiring tests; seeders updated (demo + ghrm) to stop writing `vbwd_price`/`currency`.

### S85.2 — Route every calculation through `PriceFactory`
- Grep the call sites that read `.price` / build totals: subscription **checkout** + renewal invoice line items, **shop** cart/order totals, **booking** price, **token-bundle** purchase, catalog/detail **display** endpoints, and the **invoice line-item** builder. Replace ad-hoc math with `PriceFactory.get_price_from_object(item)` and use `Price.netto/brutto/taxes`.
- **Charge amount = `Price.brutto`** (D8). Invoice line items persist netto + tax breakdown from the VO (invoice columns stay `Numeric(10,2)` — invoices are an immutable financial record and *may* round at issue time; that is the one legitimate rounding boundary, documented).
- **fe:** API responses for sellables expose the computed `Price` (`{netto, taxes, brutto, currency}`); fe-core/fe-user pick the displayed side via `price_display_mode` and format via `money.ts`. No bespoke tax math in the frontend.
- **Tests:** service-level — checkout/invoice/catalog now reflect the global `prices_mode_in_db` (flip the setting in a test → same stored double yields different netto/brutto); a guard that no sellable route re-derives tax outside the factory.

### S85.3 — fe-admin: add the `prices_mode_in_db` selector
- Extend the existing **Price display mode** settings block (the `prices-display-mode-section` shown in the request) with a second control: a `prices-mode-in-db-select` (`<option value="NETTO">`, `<option value="BRUTTO">`) + its own save, wired to the `prices_mode_in_db` key through the existing settings store/API. Label + hint: "How stored prices are interpreted (net vs gross). Display mode above is independent."
- **Tests:** Vitest — renders both selects with the correct testids (`prices-display-mode-select`, `prices-mode-in-db-select`), loads the current value, PUTs the new value, shows a saved state.

### S85.4 — fe consumers: render the unified `Price` on every surface + business-viewer overlay + detailed tax UI
*Depends on **S85.2** (every sellable / invoice payload exposes the computed `Price` `{netto, taxes[], brutto, currency}`) + **S74** (`account_type` on the fe auth user). This is the consumer layer the user's requirement targets: every price the user sees carries tax info and obeys the netto/brutto rules.*

- **One shared renderer (DRY).** Extend the existing `PriceDisplay` (fe-core/fe-user) to take the `Price` VO + the resolved side and format via `money.ts` (rounding lives ONLY here, D4). Add the pure util `resolveDisplaySide(price, { itemMode, globalMode, user })` implementing the **D9** precedence. **No tax math in the fe** — it only *chooses a side* and *formats*.
- **fe-core auth store** exposes `account_type` on the user (from S74) so `resolveDisplaySide` can apply the business overlay; anonymous → no overlay.
- **Route EVERY price surface through the shared renderer** (audit — ✓ = already on `PriceDisplay`, **bold** = currently bespoke `formatPrice`/plain text, must be migrated):
  - subscription: `Plans.vue` ✓, `TarifPlanDetail.vue` ✓, **`AddOns.vue`**, **`AddonDetail.vue`**, **`Checkout.vue`** (authenticated), **`PlanCheckoutSummary.vue`**.
  - shop: `ProductCatalog.vue` ✓, `ProductDetail.vue` ✓, **`Cart.vue`**, **`OrderDetail.vue`**, **`ShopCheckoutSummary.vue`**.
  - booking: `BookingCatalogue.vue` ✓, `BookingResourceDetail.vue` ✓, **`BookingForm.vue`**, **`BookingSuccess.vue`**.
  - checkout (generic): **`PublicCheckoutView.vue`**, **`CheckoutConfirmationView.vue`**.
  - invoices: fe-user **`Invoices.vue`** + **`InvoiceDetail.vue`**; fe-admin **`Invoices.vue`** + **`InvoiceDetails.vue`**.
  - cart: fe-core **`CartItem.vue`**.
  - fe-admin catalog: **`subscription-admin/Plans.vue`**, **`shop-admin/OrderDetails.vue`**.
- **Detailed tax-breakdown block** on the financial surfaces — **invoices** (fe-user + fe-admin), **checkout** (private + public), **success / pending / confirmation**: render per-line **net**, the per-rate tax lines straight from `Price.taxes` (e.g. "VAT 19% — €X"), and totals **net / Σtax / gross**. These read the **persisted** per-line tax from S85.2 (invoices) or the live `Price` VO (checkout/catalog) — never recomputed in the fe.
- **Tests (Vitest):** `resolveDisplaySide` precedence matrix (business beats item-`brutto`; item override beats global; global default `brutto`; anonymous = global); each migrated surface renders net vs gross per a mocked `{user, itemMode, globalMode}`; the detailed-tax block's lines sum to gross; a guard asserting no surface performs its own tax arithmetic (all amounts come from the `Price` VO).

## Out of scope (explicit, to avoid overengineering)
- A shared payment-amount adapter (cents-vs-major unification across Stripe/PayPal/YooKassa/MercadoPago) — noted follow-up; adapters keep their current conversions (D8).
- Per-item `prices_mode_in_db` override (D7).
- Multi-currency *display* / conversion at checkout — `default_currency` remains the single operating currency (S84); FX is a separate concern.

## Quality gate / Done = all of
TDD'd · DevOps-clean (local + CI green, schema via Alembic only, up/down/up validated) · SOLID/DI/DRY/Liskov/clean · not over-engineered · core stays plugin-agnostic (the agnosticism oracle stays green — the factory imports no plugin model) · every oracle assertion green · `bin/pre-commit-check.sh --full` green on **core + subscription + shop + booking** and fe-admin/fe-user/fe-core Vitest/ESLint/vue-tsc green (fe-user green is the S85.4 acceptance: every price surface renders the `Price` VO with the D9 overlay) · no commits unless explicitly instructed ([[feedback_no_commit_without_ask]]).
