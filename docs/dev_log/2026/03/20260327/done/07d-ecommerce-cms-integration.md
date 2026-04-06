# Sprint 07d — CMS Integration: Pages + Layouts + Widgets

**Status:** Pending approval
**Date:** 2026-03-29
**Repos:** `vbwd-backend`, `vbwd-fe-user`
**Parent:** [07-ecommerce-completion.md](07-ecommerce-completion.md)
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Shop is a CMS page (public, not dashboard)

The `/shop` URL should render as a CMS page with the `shop-catalogue` layout, not as a Vue router page behind authentication. The ecommerce plugin registers a CMS page at slug `shop` with:
- Layout: `shop-catalogue` (header + category nav + product grid + footer)
- The `ProductGrid` and `CategoryNav` are CMS vue-component widgets

## Widget Consistency

Ensure all ecommerce widgets work as CMS vue-components:
- `ProductGrid` — configurable: category filter, items per page
- `ProductCard` — single product by slug
- `ProductCarousel` — featured/related products
- `CategoryNav` — category tree sidebar
- `CartSummary` — mini cart (item count + total)
- `AddToCartButton` — by product slug

## Product Detail Page Layout

CMS layout `shop-product-detail`:
- Areas: header, breadcrumbs, product-detail (vue component), related-products (carousel), footer
- The `/shop/product/:slug` route renders this layout

## Import Files Update

Update `docs/imports/cms/` JSON files + `populate_db.py` to create functional CMS pages that actually render the widgets.

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Register ecommerce widgets in CMS vue-component registry | — |
| 2 | Update populate_db to create functional CMS pages with widget assignments | — |
| 3 | Ensure `/shop` renders as CMS page (public, no auth) | Integration test |
| 4 | Ensure `/shop/product/:slug` renders product detail via CMS layout | Integration test |
| 5 | Test all widgets render correctly in CMS context | Unit tests |
| 6 | `pre-commit-check.sh --full` | — |

---

## Integration Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_shop_page_registered_as_cms_page` | Verify CMS page with slug `shop` exists after populate_db |
| 2 | `test_shop_page_uses_catalogue_layout` | Verify shop page has `shop-catalogue` layout assigned |
| 3 | `test_product_grid_widget_registered` | Verify ProductGrid widget in CMS vue-component registry |
| 4 | `test_category_nav_widget_registered` | Verify CategoryNav widget in CMS vue-component registry |
| 5 | `test_shop_page_public_no_auth` | GET `/shop` without auth token, verify 200 response |
| 6 | `test_product_detail_layout_renders` | GET `/shop/product/:slug`, verify layout areas present |
| 7 | `test_all_widgets_render_in_cms_context` | Mount each widget in CMS layout, verify render |

## Playwright E2E Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_shop_page_loads_as_cms_page_no_auth` | Navigate to /shop without login, verify products visible |
| 2 | `test_product_detail_via_cms_layout` | Click product, verify CMS layout with breadcrumbs + related |
| 3 | `test_cart_summary_widget_updates` | Add to cart, verify CartSummary widget shows count |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | Product tabs are Open/Closed — plugins extend without modifying core. |
| **Liskov** | All tab components honour the tab interface. |
| **DI** | Services via container, handlers via registry. |
| **DRY** | CMS image gallery reused (not duplicated). Booking M2M pattern reused. |
| **Clean Code** | Meaningful names. No stubs left. |
| **No over-engineering** | Two-sided selector is a simple component, not a drag-and-drop framework. |
| **DevOps-first** | `pre-commit-check.sh --full` passes on all repos. |
| **i18n** | All new UI text in 8 languages. |

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
