# Sprint 06a — E-commerce Backend: Models + Stock Management

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Create `plugins/ecommerce/` backend plugin with all models, repositories, stock blocking, and Alembic migration.

## Plugin Skeleton

```
plugins/ecommerce/
├── __init__.py                    EcommercePlugin(BasePlugin)
├── admin-config.json
├── config.json (entry in plugins/config.json)
├── populate_db.py
├── ecommerce/
│   ├── __init__.py
│   ├── models/
│   │   ├── __init__.py
│   │   ├── product.py
│   │   ├── product_category.py
│   │   ├── product_image.py
│   │   ├── warehouse.py
│   │   ├── warehouse_stock.py
│   │   ├── stock_block.py
│   │   ├── order.py
│   │   └── order_item.py
│   └── repositories/
│       ├── __init__.py
│       ├── product_repository.py
│       ├── product_category_repository.py
│       ├── warehouse_repository.py
│       ├── warehouse_stock_repository.py
│       ├── stock_block_repository.py
│       ├── order_repository.py
│       └── order_item_repository.py
└── tests/
    ├── __init__.py
    ├── conftest.py
    └── unit/
        ├── __init__.py
        ├── test_product_model.py
        ├── test_order_model.py
        └── test_stock_block_model.py
```

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Plugin skeleton + `__init__.py` + `config.json` + `admin-config.json` | — |
| 2 | Product model + ProductCategory + ProductImage | Model unit tests |
| 3 | Warehouse + WarehouseStock models | Model unit tests |
| 4 | StockBlock model | Model unit tests |
| 5 | Order + OrderItem models + OrderStatus enum | Model unit tests |
| 6 | All repositories | Repository unit tests |
| 7 | Register in `plugins/plugins.json` + `plugins/config.json` | — |
| 8 | Alembic migration | — |
| 9 | `populate_db.py` — demo products, categories, warehouses | — |
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

## Integration Tests

```
- test_product_with_variants_creates_variant_records
- test_product_category_hierarchy_parent_child
- test_warehouse_stock_unique_constraint_product_warehouse
- test_stock_block_created_with_expiry
- test_order_with_order_items_cascade_delete
- test_alembic_migration_creates_all_tables
- test_populate_db_creates_demo_data_idempotent
```

## Playwright E2E

N/A — backend models only. Covered by 06d/06e frontend sprints.

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --lint      # Black + Flake8 + Mypy
cd vbwd-backend && ./bin/pre-commit-check.sh --unit       # Unit tests (core + all plugins)
cd vbwd-backend && ./bin/pre-commit-check.sh --integration # Integration tests (real PostgreSQL)
cd vbwd-backend && ./bin/pre-commit-check.sh --full        # All of the above
```
