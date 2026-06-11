# S76 — Shop catalog parity: manufacturer, product number/EAN, SEO

**Area:** plugin `shop` (`vbwd-backend/plugins/shop` + `vbwd-fe-admin/plugins/shop-admin` + `vbwd-fe-user/plugins/shop`) · **Depends on:** shop Product/category (exist), CMS SEO mechanism (S56, for reuse) · **Part of:** Shopware-parity follow-ups ([report 01](../reports/01-shopware-vs-vbwd-user-product-comparison.md)).
**Engineering requirements:** TDD-first, SOLID/DI/DRY, no overengineering; `--plugin shop --full` + fe Vitest/ESLint green. **Not committed.**

## Problem
The shop product lacks three standard catalog facets present in Shopware: a **manufacturer** (brand), a distinct **product number** + **EAN/GTIN** (today only `sku`), and **SEO** metadata for the product detail page (today only an opaque `product_metadata` JSONB). (Tax is handled separately by [S72.3](s72-3-entity-tax-assignment.md); this sprint is identity + brand + SEO.)

## Scope
**Shop backend (`plugins/shop/shop/`):**
1. **Manufacturer** — new `Manufacturer` model (`shop_manufacturer`: name, slug unique, description, logo_url, website, sort_order) + repo/service + admin CRUD routes (`/api/v1/admin/shop/manufacturers`, gated `shop.products.manage`). Add nullable `manufacturer_id` FK on `Product` (`ON DELETE SET NULL`); `to_dict()` includes `manufacturer` (`{id,name,slug}`).
2. **Product number + EAN** — add `product_number` (String, unique, indexed; auto-assigned from a sequence/seed if omitted, distinct from `sku`) and `ean` (String(14), nullable) to `Product`; create/update accept them; `to_dict()` includes them.
3. **SEO** — add SEO fields to `Product` mirroring the CMS S56 shape (`seo_title`, `meta_description`, `og_title`, `og_description`, `og_image_url`, `canonical_url`, `robots`) — **reuse the CMS SEO field names/serialization** so tooling is shared and the fe-user product page emits the same meta tags as CMS pages. (Reuse a shared SEO helper if S56 exposes one; otherwise mirror the columns.)
4. One additive migration (`down_revision` = shop head — verify): `manufacturer` table + the new `Product` columns + backfill `product_number` for existing rows.

**fe-admin (`shop-admin`):**
- `ProductForm.vue` General tab: a **Manufacturer** select (from the manufacturer list) + **Product number** + **EAN** fields.
- A new **SEO** tab/section on `ProductForm.vue` (title, meta description, OG fields, canonical, robots) — reuse the CMS SEO editor component if one exists (S56), else a simple form.
- A **Manufacturers** admin list/manager (under the Shop nav) — list + create/edit/delete.
- i18n keys (all locales).

**fe-user (`shop`):**
- `ProductDetail.vue` renders the SEO meta (title/description/OG/canonical/robots) — reuse the CMS SEO head mechanism — and shows the manufacturer (brand) + product number where appropriate.

## TDD
- **Backend:** create/update a product with `manufacturer_id` (resolves), `product_number` (auto-assigned when omitted, unique), `ean`, and SEO fields persisted + in `to_dict()`; deleting a manufacturer nulls the product FK (no cascade-delete of products); migration up/down/up backfills `product_number`.
- **fe-admin (Vitest):** manufacturer select + number/EAN fields render and save; the SEO tab saves SEO fields; manufacturer manager CRUD.
- **fe-user (Vitest):** product detail emits the SEO meta and shows the manufacturer.

## Definition of done
Products have a manufacturer, a distinct product number + EAN, and SEO metadata reusing the CMS SEO shape; the product detail page emits proper meta tags; admin can manage manufacturers and edit all three facets; `--plugin shop --full` + fe Vitest/ESLint green. Not committed ([[feedback_no_commit_without_ask]]).
