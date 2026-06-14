# Report 02 — Pricing / money model audit (core + plugins)

**Date:** 2026-06-13
**Scope:** how PRICE / MONEY / CURRENCY / TAX is modelled across `vbwd-backend` core and the plugins, and whether it is unified.
**Method:** read-only source audit (models, services, migrations, payment adapters, fe money utils). All claims cite `file:line`.
**Triggers:** S85 (unified pricing). Adjacent: S72 (taxes / netto-brutto), S84 (currency admin / `default_currency` single source of truth).

---

## Verdict

**Fragmented — no enforced unified money model.** A real core `Price` value object exists but is **dead** (referenced only by a half-migrated `tarif_plan` and two seeders). Every sellable instead declares its own `price Numeric(10,2)` + a redundant hardcoded `currency String(3)`, some add a lossy `price_float` mirror, tax is linked to only 3 of 5 sellables, and there is **no single calculation path** — checkout, invoicing, catalog display and payment each read `.price` and re-derive tax/totals independently. The only thing holding it together is an informal convention ("`Numeric(10,2)` major units + a 3-char currency code, default `EUR`").

This is the gap S85 closes with one `PriceFactory.get_price_from_object()` and a computed `Price` value object.

---

## Money representations (mapping table)

| Location | Price field(s) | Type / unit | Currency | Tax link | Uses core `Price`? |
|---|---|---|---|---|---|
| core `UserInvoice` `vbwd/models/invoice.py` | `amount`, `subtotal`, `tax_amount`, `total_amount` | `Numeric(10,2)`, major | `currency String(3)` (per-invoice) | — | ❌ |
| core `InvoiceLineItem` | `unit_price`, `total_price` | `Numeric(10,2)`, major | inherits invoice | — | ❌ |
| core `TokenBundle` `vbwd/models/token_bundle.py:21` | `price` | `Numeric(10,2)`, major | none ("system default") | **none** | ❌ |
| core `TokenBundlePurchase` `…purchase.py:50` | `price` | `Numeric(10,2)`, major | none | — | ❌ |
| core `Price` `vbwd/models/price.py:9` | `price_decimal`, `price_float`, `net_amount`, `gross_amount`, `taxes` JSONB | `Numeric(10,2)`+`Float`+JSONB | `currency_id` FK→`Currency` | JSONB breakdown | **the model itself** (unused) |
| core `Currency` `vbwd/models/currency.py` | `exchange_rate` | `Numeric(18,8)` (S84) | ISO-3 `code`+`symbol` | — | catalog/conversion only |
| core `Tax` `vbwd/models/tax.py:61` | `rate` | `Numeric(5,2)` percent | location-keyed | `calculate`/`extract_*` Decimal helpers | — |
| subscription `TarifPlan` `…/tarif_plan.py` | `price` (`:79`, legacy, nullable) + `price_float` (`:67`) + `price_id`→`vbwd_price` (`:71`) | dual | `currency` (`:80`, legacy) | `taxes` M2M (`:123`) | ⚠️ partial (dual path) |
| subscription `AddOn` `…/addon.py:45` | `price` | `Numeric(10,2)`, major | `currency` (`:46`) default `"EUR"` | **none** | ❌ |
| shop `Product` `…/product.py:60` | `price` + `price_float` (`:62`) | `Numeric(10,2)`+`Float` | `currency` (`:61`) default `"EUR"` | `taxes` M2M (`:97`) | ❌ |
| shop `Order`/`OrderItem` | `subtotal`/`tax_amount`/`total_amount`/`unit_price`/`total_price` | `Numeric(10,2)`, major | `currency` default `"EUR"` | — | ❌ |
| booking `BookableResource` `…/resource.py:83` | `price` | `Numeric(10,2)`, major | `currency` (`:84`) default `"EUR"` | `taxes` M2M (`:113`) | ❌ |

### Payment SDK adapters — amount passed differently per provider
| Adapter | Amount conversion | Unit sent |
|---|---|---|
| Stripe `plugins/stripe/.../sdk_adapter.py` | `int(amount * 100)` | minor units (cents) |
| PayPal `plugins/paypal/.../sdk_adapter.py` | `str(amount)` | major units |
| YooKassa `plugins/yookassa/.../sdk_adapter.py` | `str(amount)` | major units |
| Mercado Pago `plugins/mercado_pago/.../sdk_adapter.py` | `float(amount)` | major units (float — lossy) |

### Frontend
- `vbwd-fe-core/src/utils/money.ts` — `roundToCents`, `formatMoney` (Intl), `isZeroTotal`. Uses IEEE-754 `number`; **rounds at display**. This is the most unified piece and the correct rounding boundary.

---

## Findings

1. **The unified model exists but is bypassed.** `vbwd/models/price.py` (`vbwd_price`: `net_amount`/`gross_amount`/`taxes`/`currency_id`) is exactly the right shape, but only `tarif_plan.price_id` points at it (and `tarif_plan` *also* keeps legacy `price`/`currency`). No service reads `vbwd_price`. It is dead infrastructure → safe to drop in favour of a computed value object.

2. **Currency is stored in N places while S84 made it global.** `default_currency` is the single source of truth (`core_settings_store.py:81`), yet `tarif_plan`, `addon`, `shop_product`, `shop_order`, `booking_resource` each carry a `currency String(3)` defaulting to `"EUR"`. These columns are cosmetic and divergent → remove them.

3. **Dual / lossy storage.** `tarif_plan` and `shop_product` keep both `Numeric(10,2)` `price` and a `Float` `price_float` mirror — two stored representations of one fact.

4. **Tax linkage incomplete.** Tax M2M joins exist for `tarif_plan` (`subscription_tarif_plan_tax`), `shop_product` (`shop_product_tax`), `booking_resource` (`booking_resource_tax`) — but **not** `addon` or `token_bundle`. A "unified" price must cover all five.

5. **No single calculation path.** Field names diverge (`amount` vs `price` vs `unit_price` vs `total_amount`); each of checkout, renewal-invoice, cart, catalog-display and payment reads `.price` and recomputes tax/total inline. No `Price`-returning factory.

6. **Tax math is already centralised and Decimal-correct.** `Tax.calculate`/`calculate_gross`/`extract_net`/`extract_tax` are the right primitives — the missing piece is a factory that *composes* them per sellable.

---

## Recommendation (→ S85)

1. Replace the persisted `vbwd_price` with a **computed `Price` value object** (`netto`, `taxes[]`, `brutto`, `currency`); invariant `netto + Σtax == brutto`.
2. One entry point: `PriceFactory.get_price_from_object(<sellable>) -> Price`, dispatching on a structural `Priceable` protocol (core stays plugin-agnostic).
3. Store each sellable price as **one double float, never rounded in code**; a global `prices_mode_in_db` (`NETTO`|`BRUTTO`) says how to interpret it; rounding stays at display (`money.ts`).
4. **Drop currency columns** from sellables; `Price.currency` = global `default_currency` (S84).
5. Complete tax linkage for `addon` + `token_bundle`.
6. Route all calculation through the factory; charge amount = `Price.brutto`. (A shared payment-amount adapter is a noted follow-up.)

Full plan: [`../sprints/s85-unified-pricing.md`](../sprints/s85-unified-pricing.md).
