# S64 — Shop → unified import/export

**Plugin:** `shop` · **Depends on:** core data-exchange framework · **Blocks:** S65
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering;
`bin/pre-commit-check.sh --plugin shop --full` green = done. See the overview +
`_engineering-requirements.md`.

> **Reconciliation (2026-06-10, verified):** S46 already shipped **`shop_products`** (in the
> existing `shop_exchangers.py`). **Two gaps:** (1) there is **no `shop_product_categories`
> exchanger** for `ProductCategory`; (2) the existing products exchanger carries **no category
> link** — an imported product is orphaned from its category. ⚠️ `fk_natural_key_map` is
> **export-only** — the link resolves on import only via a thin subclass. So this sprint **adds one
> exchanger and upgrades the existing one**, not greenfield. (Variants/images are also not yet
> exchanged — add if the demo needs them.)

## Problem
A storefront can't be seeded as a connected catalogue: product **categories** aren't exchangeable
at all, and the existing `shop_products` exchanger exports no category link — so an imported product
is orphaned from its category.

## Goal
**Add** a `shop_product_categories` exchanger (`ProductCategory`), and **upgrade** the existing
`shop_products` to carry its category by **slug** (resolved on import via a thin subclass); optional
nested variants/images.

## Scope / exchangers
**Extend the existing** `plugins/shop/shop/services/data_exchange/shop_exchangers.py`
(`build_shop_exchangers(session)` already builds `shop_products`; add the category exchanger and
convert products to a link-carrying subclass).

1. **`shop_product_categories`** (`ProductCategory`) — **NEW** (plain `BaseModelExchanger`, or a
   thin subclass if hierarchical):
   - `natural_key="slug"`, `cluster=CLUSTER_SALES`, label "Shop Categories".
   - `public_fields=[name, slug, description, sort_order, is_active, …]`.
   - `parent_id` (if hierarchical): export-only via `fk_natural_key_map`; **resolve the parent slug
     on import in the subclass** (or keep flat + omit `parent_id`).
2. **`shop_products`** (`Product`) — **UPGRADE the existing exchanger** to a thin subclass (keep the
   `shop_products` entity key) — add the category link (+ optional nested variants/images):
   - `natural_key="slug"`, `cluster=CLUSTER_SALES`, label "Shop Products".
   - `public_fields=[name, slug, description, sku, price, price_float, currency, is_active,
     is_digital, has_variants, sort_order, weight, dimensions, …]` (`dimensions` JSON verbatim).
   - **Category**: serialise the category as a slug (`category_slug`, or `category_slugs` if M2M —
     confirm the model); **resolve it to the local id on import in the subclass** (`fk_natural_key_map`
     only serialises on export — it won't resolve, and would write a slug into the id column).
   - **Variants** (`ProductVariant`, 1:M): serialise a nested `variants: [{sku, name, price,
     attributes, …}]` array; recreate on import (delete-and-replace children by product, mirroring
     the CMS layout-widget-assignment handling). **Images** (`ProductImage`, 1:M): serialise
     `images: [{url, alt, sort_order}]`; binary assets are by URL (no asset bytes this sprint —
     a later ZIP-export can add `export_zip` for image binaries; note it).

Register via `ShopPlugin.on_enable` → `_register_data_exchangers()` calling
`register_shop_exchangers(db.session)`.

## TDD test plan (write first — `plugins/shop/tests/unit/.../test_shop_exchangers.py`)
- **Round-trip**: category + product (in category, with 2 variants + 2 images) → export → import
  into a clean session → category + product recreated, linked by slug, variants + images recreated;
  price, sku, dimensions, is_digital preserved.
- **Category by slug**; unknown category slug → error row, no crash.
- **Variants/images replace** on re-import (no duplicate children; upsert product by slug).
- **dry_run** no writes; **upsert** by slug.
- **Manifest/perms**: appear with shop manage/view perms, hidden otherwise.
- **Liskov**: idempotent export→import on unchanged DB.

## fe-admin
- Confirm `shop_product_categories` + `shop_products` appear in the core `ImportExport.vue`
  (manifest-driven), Sales cluster. No per-plugin import view (retire any bespoke shop import if one
  exists — check `shop-admin`).

## Acceptance
- `--plugin shop --full` green.
- Export a seeded storefront and import into an empty shop instance → products + categories +
  variants + images reproduced; the storefront lists them.

## Risks / notes
- Confirm product↔category cardinality (single FK vs M2M) and pick the matching serialisation.
  Image **binaries** are out of scope (URLs only) — a `export_zip` with assets can follow if the
  demo needs real images. No change to cart/checkout runtime.
