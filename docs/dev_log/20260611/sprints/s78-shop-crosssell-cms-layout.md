# S78 — Shop cross-selling + product CMS layout

**Area:** plugin `shop` (`vbwd-backend/plugins/shop` + `vbwd-fe-admin/plugins/shop-admin` + `vbwd-fe-user/plugins/shop`) · **Depends on:** shop Product (exists), CMS plugin layouts (`cms_layout`, `CmsLayoutRenderer`) · **Part of:** Shopware-parity follow-ups ([report 01](../reports/01-shopware-vs-vbwd-user-product-comparison.md)).
**Engineering requirements:** TDD-first, SOLID/DI/DRY, no overengineering; `--plugin shop --full` + fe Vitest/ESLint green. Shop depends on CMS only through its declared plugin dependency. **Not committed.**

## Problem
Two Shopware product features are absent: **cross-selling** (related/up-sell products on the detail page) and **per-product CMS layout** (rendering the product detail page inside a chosen CMS layout, like the GHRM catalogue does via a layout slug). The CMS plugin already provides layouts + `CmsLayoutRenderer`; the shop should reuse them.

## Locked decisions
| # | Decision |
|---|---|
| **D1 — Cross-sell as typed product↔product links.** | New `shop_product_crosssell` (`product_id` FK, `related_product_id` FK, `type` ∈ {cross, up, related}, `sort_order`, unique `(product_id, related_product_id, type)`, both FKs `ON DELETE CASCADE`). Directional (A→B); not auto-reciprocal. |
| **D2 — Product CMS layout by slug.** | Add nullable `cms_layout_slug` to `Product` (references a `cms_layout.slug`; null = default product template). Stored as slug (portable for import/export, mirrors GHRM's `software_detail_cms_layout_slug`). |
| **D3 — Graceful CMS-absent.** | If the CMS plugin is disabled or the slug doesn't resolve, the product page falls back to the default template (no error). Layout selection in admin is only offered when CMS is available. |

## Scope
**Shop backend:**
- `CrossSell` model + repo/service; admin routes to set/list a product's cross-sells (`GET|PUT /api/v1/admin/shop/products/<id>/cross-sells`, gated `shop.products.manage`); product `to_dict()` (or a detail endpoint) exposes resolved cross-sell groups (`{type: [{id,name,slug,price,primary_image_url}]}`, active products only).
- Add `cms_layout_slug` to `Product` (create/update accept it; `to_dict()` includes it). Resolve the layout via the CMS plugin **through its plugin dependency / a port** (no hard import); expose `resolved_layout` on the public product detail response (like the CMS page resolution).
- One additive migration (`down_revision` = shop head — verify): `shop_product_crosssell` + `Product.cms_layout_slug`.

**fe-admin (`shop-admin`):**
- `ProductForm.vue`: a **Cross-selling** tab/section — pick related products per type (reuse `DualListSelector`, options = other active products); save via the cross-sells endpoint.
- A **Layout** select (list of CMS layout slugs from the CMS admin API) bound to `cms_layout_slug`, shown only when CMS is enabled.
- i18n keys (all locales).

**fe-user (`shop`):**
- `ProductDetail.vue`: render the page inside the product's `resolved_layout` via `CmsLayoutRenderer` when set (else default); show a **"Related products" / "You may also like"** section from the cross-sell groups.

## TDD
- **Backend:** set/list cross-sells (typed, ordered, dedup, no self-link); deleting a product cascades its cross-sell rows (and rows referencing it); `cms_layout_slug` persists; public detail resolves the layout when CMS present and **falls back** when absent/unresolved.
- **fe-admin (Vitest):** cross-sell picker adds/removes per type and saves; layout select lists CMS layouts and saves the slug (hidden when CMS disabled).
- **fe-user (Vitest):** product detail renders within the chosen layout when set; related-products section lists the cross-sell products; graceful default when no layout.

## Definition of done
Products can declare typed cross-sell relations (shown as related/up-sell on the detail page) and an optional CMS layout (rendering the detail page via `CmsLayoutRenderer`, with graceful fallback when CMS is absent); admin manages both from the product form; shop reaches CMS only via its declared dependency/port; `--plugin shop --full` + fe Vitest/ESLint green. Not committed ([[feedback_no_commit_without_ask]]).
