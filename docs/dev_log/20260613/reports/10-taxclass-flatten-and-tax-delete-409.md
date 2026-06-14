# Report 10 — TaxClass flattened into a `tax_class` field + in-use tax-delete 409 fix

**Date:** 2026-06-13 · **Area:** core `vbwd-backend` (`Tax` model, admin tax routes, `taxes` data-exchange exchanger) + `vbwd-fe-admin` (Taxes tab) · **Status:** 🟢 DONE on disk, gate-green; **not committed.**

## Origin

A design question during the S84 currency work: *"Is `TaxClass` redundant or not wired? It isn't used overall, and the info could live on the Tax model — why another model?"* The answer turned out to be: **wired but functionally inert.**

## Assessment

`TaxClass` (`vbwd_tax_class`: name, code, description, default_rate, is_default) is *referenced* — `Tax.tax_class_id` FK, class CRUD routes, the `tax_classes` exchanger, a fe-admin "Tax Classes" CRUD section, a tax-list filter — but **nothing reads the class to make a decision**:
- **Pricing** (`Tax.calculate` / `is_applicable`) uses `rate` + `country_code`/`region`, never the class.
- **Entity assignment (S72.3)** links plans/products/resources M2M to specific **`Tax`** rows, not to a class.
- **Netto/brutto (S72.4)** operates on the applied `Tax` rows.

The class is the standard accounting concept ("product carries a tax *class*; resolve the rate by class + country"), but S72.3 wired entities to specific taxes directly — so the class-resolution path was never built. With the team confirming "entity → specific taxes," `TaxClass` is removable. **Decision: flatten** to a denormalized `tax_class` string on `Tax` (consistent with the existing legacy `shop_product.tax_class` string), preserving the label + filter, removing the model.

## What changed

### Backend (core)
- **Migration `20260613_1100_flatten_tax_cls`** (down_revision `20260613_1000_curr_flags`): add `tax_class VARCHAR(50)` to `vbwd_tax`, data-migrate each tax's old class → its `code`, **drop `tax_class_id`**, **drop the `vbwd_tax_class` table**. Validated up→down→up on real PG.
- **Model:** deleted `TaxClass`; `Tax` drops the FK/relationship, gains `tax_class` (string, nullable); `to_dict()` updated. `calculate`/`is_applicable` untouched.
- **Routes** (`vbwd/routes/admin/tax.py`): removed all four TaxClass routes (now 404); tax create/update accept/return `tax_class` (string); tax-list filter is `?tax_class=<code>`.
- **Exchanger** (`core_exchangers.py`): removed the `tax_classes` exchanger + the `TaxesExchanger` FK-by-code subclass; `taxes` is now a plain `BaseModelExchanger` carrying `tax_class` as a field — `public_fields = [name, code, description, rate, country_code, region_code, is_active, is_inclusive, tax_class]`, natural key `code`.
- 67 scoped tests + 1532 core unit green (the handful of failures are pre-existing in-flight S67 APNs / S85 `vbwd_price` items, zero tax involvement).

### fe-admin
- Removed the entire "Tax Classes" CRUD section + its import/export control; replaced the class picker on the rate form with a `tax_class` text field (standard/reduced/zero datalist, optional); one `taxes` import/export remains. **855 Vitest** (full suite, 96 files) + lint + `vue-tsc` clean; `nav.taxesAndCountries` + `currencies.*` preserved.

### Bonus fix — in-use tax delete returned 500 (pre-existing S72.3 gap)
Bulk-deleting taxes 500'd. Root cause: a tax referenced by an entity (e.g. `shop_product_tax`, `ON DELETE RESTRICT` from S72.3) raised a `ForeignKeyViolation` on commit that the core delete route never caught. S72.3 specified a **409** here but it was never wired into the core route. **Fix:** the delete route now catches `IntegrityError` → rolls back → returns **409 "Tax rate is in use and cannot be deleted."** Added a regression test (`test_delete_in_use_rate_returns_409_not_500`). Verified live: in-use → 409, free tax → 200. (The fe-admin bulk-delete already handles 409 per-row, so bulk delete now reports "some in use" instead of erroring.)

## Net effect
Removed **one model, one table, one FK + its on-delete handling, four CRUD routes, and one exchanger** — with tax categorization preserved as a simple label, and the in-use-delete guard finally returning the intended 409.

## Caveats
- **Two alembic heads — since merged (2026-06-14).** `20260613_1100_flatten_tax_cls` was a sibling of the parallel S85 `…_drop_price` migration (same parent `…_curr_flags`). The S77 merge revision `20260613_1200_tags_custom_fields` (`down_revision = ("20260611_1000_user_groups", "20260613_1100_drop_price")`) unified them — and since `user_groups` chains off `flatten_tax_cls`, the flatten is in that ancestry. The core chain is now single-headed at `20260614_1000_inv_line_tax_bd`; `alembic upgrade heads` resolves cleanly. (The other alembic heads are the by-design per-plugin branches.)
- **Down-migration is best-effort** — `down()` recreates `vbwd_tax_class` + re-adds the FK column but cannot restore class rows/links (documented in the migration).
- Nothing committed.
