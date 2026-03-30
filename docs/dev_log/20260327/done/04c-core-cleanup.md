# Sprint 04c — Remove Subscriptions from Core

**Status:** Pending approval
**Date:** 2026-03-27
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Remove all subscription/tarif-plan/add-on code from `vbwd/` core. After this sprint, core is a pure invoicing + token economy + event system.

---

## What Gets Removed from Core

### Models (delete)
- `vbwd/models/subscription.py`
- `vbwd/models/tarif_plan.py`
- `vbwd/models/addon.py`
- `vbwd/models/addon_subscription.py`
- `vbwd/models/tarif_plan_category.py`

### Repositories (delete)
- `vbwd/repositories/subscription_repository.py`
- `vbwd/repositories/tarif_plan_repository.py`
- `vbwd/repositories/addon_repository.py`
- `vbwd/repositories/addon_subscription_repository.py`
- `vbwd/repositories/tarif_plan_category_repository.py`

### Services (delete)
- `vbwd/services/subscription_service.py`
- `vbwd/services/tarif_plan_service.py`
- `vbwd/services/tarif_plan_category_service.py`

### Routes (delete)
- `vbwd/routes/subscriptions.py`
- `vbwd/routes/tarif_plans.py`
- `vbwd/routes/addons.py`
- `vbwd/routes/admin/subscriptions.py`
- `vbwd/routes/admin/plans.py`
- `vbwd/routes/admin/addons.py`

### Handlers (delete)
- `vbwd/handlers/checkout_handler.py`
- `vbwd/handlers/subscription_handlers.py`
- `vbwd/handlers/subscription_cancel_handler.py`

### Events (delete)
- `vbwd/events/subscription_events.py`
- `vbwd/events/checkout_events.py`

### Email templates (delete)
- `vbwd/templates/email/subscription_activated.*`
- `vbwd/templates/email/subscription_cancelled.*`

### Tests (delete — already migrated to plugin in 04b)
- All `tests/unit/services/test_subscription_*`, `test_tarif_*`
- All `tests/unit/handlers/test_subscription_*`, `test_checkout_*`
- All `tests/unit/routes/test_admin_addon_*`, `test_public_addon_*`, `test_user_addon_*`
- All `tests/unit/models/test_subscription*`, `test_addon_*`, `test_tarif_*`
- All `tests/integration/test_checkout_*`, `test_admin_addons*`, `test_user_subscription_*`
- `tests/fixtures/checkout_fixtures.py`

---

## What Gets Updated in Core

### `vbwd/app.py`
- Remove blueprint registrations for subscription/tarif/addon routes
- Remove `CheckoutHandler`, `SubscriptionCancelledHandler` registration
- Remove subscription scheduler start

### `vbwd/container.py`
- Remove DI registrations for subscription, tarif_plan, addon, category repos/services

### `vbwd/scheduler.py`
- Remove subscription expiration, trial expiry, dunning jobs

### `vbwd/handlers/core_line_item_handler.py`
- Remove SUBSCRIPTION and ADD_ON handling
- Only TOKEN_BUNDLE remains

### `vbwd/models/enums.py`
- Keep `LineItemType.SUBSCRIPTION`, `ADD_ON` (enum values stay — they're referenced in DB data)
- Keep `SubscriptionStatus` (same reason — existing DB rows)
- Keep `BillingPeriod` (same reason)

### `vbwd/models/invoice.py`
- Make `subscription_id`, `tarif_plan_id` ForeignKeys nullable (no constraint to deleted tables)
- These columns remain for backward compat with existing invoices

---

## Steps

| # | What | Validate |
|---|------|----------|
| 1 | Update `core_line_item_handler.py` — TOKEN_BUNDLE only | Unit tests |
| 2 | Update `container.py` — remove subscription DI | — |
| 3 | Update `app.py` — remove subscription blueprints, handlers, scheduler | — |
| 4 | Update `scheduler.py` — remove subscription jobs | — |
| 5 | Update `invoice.py` — nullable FKs, remove tarif_plan/subscription imports | — |
| 6 | Delete all files listed above | — |
| 7 | Delete migrated test files | — |
| 8 | Run `pre-commit-check.sh` — all green | Full suite |
| 9 | Verify subscription plugin still works (routes, handlers, events) | Plugin tests |

---

## Acceptance Criteria

- Zero subscription/tarif/addon imports in `vbwd/` (except enums for DB compat)
- `CoreLineItemHandler.can_handle_line_item` returns False for SUBSCRIPTION and ADD_ON
- Core test suite passes with no subscription tests
- Subscription plugin tests pass independently
- `pre-commit-check.sh` passes
