# S72.3 — Assign taxes to plan / product / booking resource (many-to-many) + pricing

**Part of:** [S72 — Taxes & Countries (umbrella)](s72-taxes.md) · **Area:** plugins `subscription` / `shop` / `booking` (backend + their fe-admin forms) + small core read-use of the Tax catalog · **Depends on:** core Tax model + `/admin/tax/rates` (exist), `DualListSelector` (exists).
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering; core stays agnostic (plugins reference the core Tax catalog; core imports no plugin). `--plugin subscription|shop|booking --full` + fe-admin Vitest/ESLint green. **Not committed.**

## Problem
None of the three sellable entities can carry taxes: `TarifPlan` (`subscription_tarif_plan`) and `BookableResource` (`booking_resource`) have **no** tax link; `Product` (`shop_product`) has only a legacy `tax_class` **string**. Admins need to attach **one or more** core `Tax` records per entity, and pricing must reflect them.

## Locked decision — tax↔entity link
Each plugin owns a **join table** to the **core** `vbwd_tax` catalog (plugins may depend on core): `subscription_tarif_plan_tax(tarif_plan_id, tax_id)`, `shop_product_tax(product_id, tax_id)`, `booking_resource_tax(resource_id, tax_id)` — `tax_id` FK → `vbwd_tax.id` **`ON DELETE RESTRICT`** (don't silently drop an applied tax; deleting an in-use tax is blocked with a clean **409**, mirroring S68 Bug B — never a FK 500). M2M. The legacy `shop_product.tax_class` string stays for back-compat but the join is authoritative when present.

## Scope (per plugin: subscription / shop / booking)
1. **Migration** (down_revision = that plugin's current head — verify): create the join table.
2. **Model + repo:** `taxes` relationship (list of core `Tax`); `to_dict()` adds `tax_ids: [<id>]` and resolved `taxes: [{id, code, name, rate}]`.
3. **Admin create/update routes** accept `tax_ids: [uuid]` (validate each exists + active; **replace-set** on update; dedupe). Gated on the entity's existing manage permission.
4. **Pricing reflects applied taxes (read path):** the plan/product/resource pricing response includes the applied taxes and computed `net_amount` / `tax_amount` / `gross_amount` from the **sum of applied tax rates** (reuse `Tax.calculate` / `Tax.calculate_gross`). When taxes are assigned they take precedence; `tarif_plan_service.get_plan_with_pricing`'s country-based breakdown becomes the fallback. *(Invoice/checkout-time multi-tax line splitting beyond a sum-of-rates is deferred to S72.5.)*

## Scope (fe-admin — a "Taxes" block in each edit form)
Reuse `vue/src/components/DualListSelector.vue` (`modelValue=tax_ids`, `options=` active taxes from `GET /admin/tax/rates`), plus a shared `useTaxOptions()` composable (fetch once; DRY):
- `plugins/subscription-admin/src/views/PlanForm.vue` — Taxes section in the Details tab; `tax_ids` in the `planAdmin` save payload.
- `plugins/shop-admin/src/views/ProductForm.vue` — Taxes block in General (beside/replacing the single `tax_class` select); `tax_ids` in the `productAdmin` payload.
- `plugins/booking/booking/views/ResourceForm.vue` — Taxes block after Categories; `tax_ids` in the `resourceAdmin` payload.
- i18n: `*.taxes.*` keys per plugin (all locales).

## TDD
- **Per plugin (backend):** create/update with `tax_ids` persists the M2M (replace-set, dedupe); `to_dict()` exposes `tax_ids`/`taxes`; deleting an in-use tax → **409** (no FK 500); pricing response sums the applied tax rates into net/gross.
- **fe-admin (Vitest):** the Taxes block lists active taxes; edit pre-selects assigned; save sends `tax_ids`.

## Definition of done
Tarif plans, shop products, and booking resources each have a Taxes block to assign ≥1 core tax (M2M, replace-set, in-use delete blocked 409); pricing reflects the summed applied taxes (net/gross); core stays agnostic; all touched repos green under `--full` + fe Vitest/ESLint. Not committed.
