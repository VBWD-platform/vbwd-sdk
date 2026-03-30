# Sprint 06b — E-commerce Backend: Services + Line Item Handler

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Implement product service, stock service (with blocking), order service, cart service, invoice creation, `EcommerceLineItemHandler`, events, and scheduler.

## Files

```
plugins/ecommerce/ecommerce/
├── services/
│   ├── __init__.py
│   ├── product_service.py          CRUD, search, filtering
│   ├── category_service.py         Category tree, product assignment
│   ├── stock_service.py            Block/commit/release/restore, multi-warehouse
│   ├── order_service.py            Create from invoice, status lifecycle, partial refund
│   ├── cart_service.py             Guest/user cart management
│   └── ecommerce_invoice_service.py  Create invoices with product line items + stock blocks
├── handlers/
│   ├── __init__.py
│   ├── line_item_handler.py        EcommerceLineItemHandler
│   └── order_handlers.py           Email events on order status changes
├── events.py                       Stock + order events
└── scheduler.py                    Expired stock block cleanup
```

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | `StockService` — block, commit, release, restore, cleanup | `tests/unit/services/test_stock_service.py` |
| 2 | `ProductService` — CRUD, search, filtering | `tests/unit/services/test_product_service.py` |
| 3 | `CategoryService` — tree, product assignment | `tests/unit/services/test_category_service.py` |
| 4 | `OrderService` — create from invoice, status transitions, partial refund | `tests/unit/services/test_order_service.py` |
| 5 | `CartService` — guest + user cart management | `tests/unit/services/test_cart_service.py` |
| 6 | `EcommerceInvoiceService` — create invoice + block stock | `tests/unit/services/test_ecommerce_invoice_service.py` |
| 7 | `EcommerceLineItemHandler` — activate (commit stock + create order), reverse, restore | `tests/unit/handlers/test_line_item_handler.py` |
| 8 | `OrderHandlers` — email event subscriptions | `tests/unit/handlers/test_order_handlers.py` |
| 9 | Events + Scheduler (stock block cleanup) | — |
| 10 | Wire in `__init__.py`: `register_line_item_handlers()`, `register_event_handlers()` | — |
| 11 | `pre-commit-check.sh` | — |

## Key Test Cases — Stock Blocking

```
- block_stock succeeds when sufficient
- block_stock raises InsufficientStockError when not enough
- block_stock across multiple warehouses picks best warehouse
- commit_stock converts blocks to permanent decrement
- release_stock restores quantity on timeout
- cleanup_expired_blocks releases blocks past TTL
- concurrent blocks don't over-commit (total blocked <= available)
- partial_refund restores stock for refunded items only
```

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

## Integration Tests (real PostgreSQL)

```
Stock blocking:
- test_block_stock_decrements_available_quantity
- test_block_stock_insufficient_raises_error
- test_commit_stock_makes_block_permanent
- test_release_stock_restores_quantity
- test_concurrent_blocks_dont_overcommit (race condition)
- test_cleanup_expired_blocks_releases_past_ttl
- test_multi_warehouse_block_picks_best_warehouse

Order lifecycle:
- test_create_order_from_paid_invoice_end_to_end
- test_partial_refund_restores_stock_for_refunded_items
- test_full_refund_cancels_order_and_restores_all_stock
- test_order_status_transitions_enforced

Line item handler:
- test_payment_captured_creates_order_and_commits_stock
- test_payment_refunded_cancels_order_and_restores_stock
- test_refund_reversed_reconfirms_order
```

## Playwright E2E

N/A — backend services only. End-to-end flow covered in 06e (user frontend) and 06g (full E2E).

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --lint      # Black + Flake8 + Mypy
cd vbwd-backend && ./bin/pre-commit-check.sh --unit       # Unit tests (core + all plugins)
cd vbwd-backend && ./bin/pre-commit-check.sh --integration # Integration tests (real PostgreSQL)
cd vbwd-backend && ./bin/pre-commit-check.sh --full        # All of the above
```
