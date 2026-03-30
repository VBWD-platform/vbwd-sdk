# Sprint 06d — E-commerce Admin Frontend

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Create `ecommerce-admin` plugin for fe-admin: product/category/order/warehouse management, dashboard widgets, shipping methods settings.

## Plugin Structure

```
plugins/ecommerce-admin/
├── src/views/          Products, ProductForm, Categories, CategoryForm, Orders,
│                       OrderDetails, Warehouses, WarehouseDetail, StockOverview, ShippingMethods
├── src/stores/         productAdmin, orderAdmin, shopCategoryAdmin, warehouseAdmin, stockAdmin
├── src/components/     ProductImageGallery, OrderStatusBadge, OrderRefundModal, StockLevelBadge
├── index.ts            Routes + extensionRegistry (sectionItems.sales + sectionItems.settings)
├── config.json
├── admin-config.json
├── locales/{en,de,es,fr,ja,ru,th,zh}.json
└── tests/unit/
```

## Dashboard Widgets

Registered via `sdk.addComponent()` in `install()`:
- `ShopRevenueWidget` — monthly product revenue
- `TopProductsWidget` — best-selling products

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Plugin skeleton + index.ts + configs + nav registration | — |
| 2 | Product list + form views + productAdmin store | Unit tests |
| 3 | Category views + shopCategoryAdmin store | Unit tests |
| 4 | Order list + detail views + orderAdmin store + refund modal | Unit tests |
| 5 | Warehouse + stock views + stores | Unit tests |
| 6 | ShippingMethods settings view | Unit tests |
| 7 | Dashboard widgets (ShopRevenueWidget, TopProductsWidget) | Unit tests |
| 8 | i18n: all 8 languages | — |
| 9 | `pre-commit-check.sh --full` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | Single responsibility per service/component. Open/Closed for shipping providers. |
| **Liskov** | All `IShippingProvider` and `ILineItemHandler` implementations honour contracts. |
| **DI** | Dependencies injected. Services via container, handlers via registry. |
| **DRY** | No duplicate logic. Shared patterns from booking plugin reused. |
| **Clean Code** | No `console.log`, no `as any`, no bare `except:`. Meaningful variable names. |
| **No over-engineering** | Minimum complexity. Stock blocking is a simple TTL table, not a distributed lock. |
| **DevOps-first** | `pre-commit-check.sh --full` passes. CI-ready from day one. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (Vitest with mocked API)

```
Product management:
- test_product_list_renders_with_data
- test_product_form_create_submits_correct_payload
- test_product_form_edit_loads_existing_data
- test_product_form_variant_editor_adds_removes_variants
- test_product_image_gallery_upload_reorder_delete

Order management:
- test_order_list_filters_by_status
- test_order_detail_shows_items_and_status
- test_order_ship_action_sends_tracking_data
- test_order_refund_modal_partial_selection
- test_order_refund_modal_submits_correct_items

Stock & warehouse:
- test_stock_overview_shows_cross_warehouse_levels
- test_warehouse_detail_shows_product_stock_per_warehouse
```

## Playwright E2E

```
Product CRUD:
- test_admin_create_product_with_images_and_variants
    → fill form → upload image → add variant → save → verify in product list
- test_admin_edit_product_price
    → open product → change price → save → verify updated
- test_admin_deactivate_product
    → toggle active → product disappears from catalog

Order management:
- test_admin_view_order_detail
    → navigate to order → see items, status, customer info
- test_admin_ship_order_with_tracking
    → click "Ship" → enter tracking → status changes to SHIPPED
- test_admin_partial_refund
    → click "Refund" → select 1 item → confirm → status PARTIALLY_REFUNDED

Stock:
- test_admin_stock_overview_page_loads
    → navigate to stock overview → see per-warehouse levels
- test_admin_adjust_warehouse_stock
    → change stock quantity → verify update

Dashboard widgets:
- test_shop_revenue_widget_visible_on_dashboard
- test_top_products_widget_visible_on_dashboard
```

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --style     # ESLint + TypeScript
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --unit      # Vitest unit tests
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --e2e       # Playwright E2E tests
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full      # All of the above
```
