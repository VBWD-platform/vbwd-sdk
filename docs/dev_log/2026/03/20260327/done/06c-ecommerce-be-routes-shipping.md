# Sprint 06c — E-commerce Backend: Routes + Shipping Interface

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Create all public + admin API routes and define the `IShippingProvider` interface in core.

## Routes

**Public:** catalog, product detail, categories, cart checkout, orders, shipping methods
**Admin:** product CRUD, category CRUD, order management, warehouse/stock management

See [parent sprint](06-ecommerce-plugin-bundle.md#06c) for full route list.

## IShippingProvider (Core Addition)

```python
# vbwd/plugins/shipping_interface.py (NEW — core file)
class IShippingProvider(ABC):
    slug: str
    name: str
    def calculate_rate(self, items, address, currency) -> ShippingRate
    def create_shipment(self, order) -> ShipmentResult
    def get_tracking(self, tracking_number) -> TrackingInfo
```

**Note:** This is ONE new core file — defines the interface only. No implementation in core.

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | `IShippingProvider` interface in core | — |
| 2 | `BasePlugin.register_shipping_providers(registry)` hook in core | — |
| 3 | Public routes: catalog, product detail, categories | Route unit tests |
| 4 | Public routes: cart checkout (block stock + create invoice) | Route unit tests |
| 5 | Public routes: orders, shipping methods | Route unit tests |
| 6 | Admin routes: product CRUD + image upload | Route unit tests |
| 7 | Admin routes: category CRUD | Route unit tests |
| 8 | Admin routes: order management (list, detail, ship, complete, refund) | Route unit tests |
| 9 | Admin routes: warehouse + stock management | Route unit tests |
| 10 | `pre-commit-check.sh` | — |

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

## Integration Tests (real PostgreSQL + Flask test client)

```
Public routes:
- test_catalog_returns_active_products_paginated
- test_catalog_filter_by_category_slug
- test_catalog_search_by_name
- test_product_detail_returns_images_and_stock
- test_product_detail_shows_per_warehouse_stock
- test_cart_checkout_blocks_stock_and_creates_invoice
- test_cart_checkout_insufficient_stock_returns_400
- test_shipping_methods_returns_available_providers
- test_user_orders_returns_only_own_orders

Admin routes:
- test_admin_create_product_with_variants
- test_admin_update_product_price
- test_admin_upload_product_image
- test_admin_create_category_with_parent
- test_admin_order_list_filter_by_status
- test_admin_ship_order_sets_tracking
- test_admin_partial_refund_updates_order_status
- test_admin_warehouse_stock_levels
```

## Playwright E2E

N/A — backend routes only. Tested via frontend E2E in 06d/06e.

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --lint      # Black + Flake8 + Mypy
cd vbwd-backend && ./bin/pre-commit-check.sh --unit       # Unit tests (core + all plugins)
cd vbwd-backend && ./bin/pre-commit-check.sh --integration # Integration tests (real PostgreSQL)
cd vbwd-backend && ./bin/pre-commit-check.sh --full        # All of the above
```
