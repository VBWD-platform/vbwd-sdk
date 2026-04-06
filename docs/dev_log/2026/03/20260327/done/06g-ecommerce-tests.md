# Sprint 06g — E-commerce Tests & Compatibility

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Full test coverage across all ecommerce plugins + verify all existing plugins still green.

## Backend Tests

- Stock blocking: block → commit, block → timeout release, insufficient stock, concurrent blocks
- EcommerceLineItemHandler: activate → order + stock commit, reverse → cancel + stock restore
- Order lifecycle: all status transitions, partial refund
- Product/category CRUD
- Cart service: guest + user
- Shipping rate calculation (both providers)
- Invoice creation with stock blocks

## Frontend Tests (Unit)

- Product catalog: filtering, search, pagination, grid/list toggle
- Product detail: gallery, stock badge, add-to-cart
- Cart: add/remove/quantity, localStorage, guest→login sync
- Checkout extension: shipping address, shipping method
- Order history + detail + status timeline
- Admin: product CRUD, order management, stock overview, refund modal
- Dashboard widgets

## Playwright E2E

- Browse catalog → filter by category → view product → add to cart
- Cart → update quantity → remove item → proceed to checkout
- Checkout: shipping address → shipping method → payment (mocked) → order confirmation
- Admin: create product → set stock → verify in catalog
- Admin: view order → change status → ship → complete
- Stock blocking: add to cart → stock decremented → timeout → stock restored
- Partial refund: admin refunds 1 item → stock restored → order shows partial refund

## Compatibility

- All existing plugins pass: booking, subscription, cms, email, stripe, paypal, yookassa, taro, ghrm, analytics, chat
- Checkout plugin extended (not broken)
- CMS layouts render ecommerce widgets correctly

## Steps

| # | What |
|---|------|
| 1 | Backend integration tests (stock blocking end-to-end) |
| 2 | Backend integration tests (order lifecycle) |
| 3 | Frontend unit test gaps (all stores, views, widgets) |
| 4 | Playwright E2E: catalog → cart → checkout → order |
| 5 | Playwright E2E: admin product + order management |
| 6 | Compatibility: run all existing plugin tests |
| 7 | `pre-commit-check.sh --full` on all 3 repos |

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
