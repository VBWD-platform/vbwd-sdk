# Report 01 — Sprint 04a: Line Item Handler Registry

**Date:** 2026-03-27
**Status:** Done
**Duration:** ~1 session

---

## What Was Done

Created a plugin-extensible line item handler system so `PaymentCapturedHandler`, `RefundService`, and `RestoreService` delegate line item processing to registered handlers instead of hardcoding `SUBSCRIPTION`/`TOKEN_BUNDLE`/`ADD_ON` logic.

### New Files

| File | Lines | Purpose |
|------|-------|---------|
| `vbwd/events/line_item_registry.py` | 130 | `ILineItemHandler` ABC, `LineItemContext`, `LineItemResult`, `LineItemHandlerRegistry` singleton |
| `vbwd/handlers/core_line_item_handler.py` | 290 | Handles TOKEN_BUNDLE + SUBSCRIPTION + ADD_ON (temporary until 04b) |
| `tests/unit/events/test_line_item_registry.py` | 130 | 13 tests for registry behavior |
| `tests/unit/handlers/test_core_line_item_handler.py` | 180 | 15 tests for core handler (activate, reverse, restore) |

### Modified Files

| File | Change |
|------|--------|
| `vbwd/handlers/payment_handler.py` | 289→155 lines. Removed all `LineItemType` switch logic, delegates to registry |
| `vbwd/services/refund_service.py` | 198→142 lines. Removed `_reverse_subscription`, `_reverse_token_bundle`, `_reverse_addon` |
| `vbwd/services/restore_service.py` | 155→80 lines. Removed `_restore_subscription`, `_restore_token_bundle`, `_restore_addon` |
| `vbwd/plugins/base.py` | Added `register_line_item_handlers(registry)` hook |
| `vbwd/plugins/manager.py` | Calls `register_line_item_handlers` in `enable_plugin()` + `load_persisted_state()` |
| `vbwd/app.py` | Wires `CoreLineItemHandler` in registry before plugin init |
| `tests/unit/services/test_refund_service.py` | Updated to inject registry via DI (10 tests) |
| `tests/unit/services/test_restore_service.py` | Updated to inject registry via DI (8 tests) |

### Test Results

- 28 new tests (13 registry + 15 core handler)
- 18 existing tests updated (refund + restore)
- **790 total passed, 0 failed, 4 skipped**

---

## Lessons Learned

### 1. Module-level singletons break test isolation

The `line_item_registry` singleton at module level caused test failures because existing tests didn't register a handler. Tests that construct `RefundService` or `RestoreService` directly had no handler in the registry.

**Fix:** Made `RefundService` and `RestoreService` accept an optional `registry` parameter (DI), falling back to the singleton for production. Tests inject a fresh registry with `CoreLineItemHandler`. Added `clear()` method to registry for future test cleanup.

**Rule:** When introducing a module-level singleton that other code depends on, always provide a DI override parameter in the consumers. Never force tests to mutate global state.

### 2. `flush()` vs `commit()` — the deeper pattern

The booking `flush()` bug (fixed earlier today) is symptomatic of a deeper issue: when code runs inside an event handler chain, each handler assumes someone else will commit. The `CoreLineItemHandler` now uses repos that call `commit()` (via base repo), but the registry pattern makes the transaction boundary clearer — each handler's `save()` commits its own work.

**Rule:** Event handler callbacks must be self-contained with their own commits. Never rely on a parent handler to commit your changes.

### 3. Extract before you refactor

The `CoreLineItemHandler` was extracted as a verbatim copy of the existing logic from 3 different files. This made the refactor safe — each existing test continued to pass with identical behavior, just routed through the registry. Only after extraction did we slim down the callers.

**Rule:** Copy first, delete second. Never refactor and move simultaneously.

### 4. PaymentCapturedHandler still knows about subscriptions (temporarily)

The `_publish_subscription_activated` method in `PaymentCapturedHandler` still imports `subscription_repository` to publish the `subscription.activated` bus event. This is acceptable for Phase 1 but must move to the subscription plugin in 04b (the plugin's handler should publish its own events).

### 5. `_calculate_tokens_to_debit` stays in RefundService

This pre-validation needs cross-line-item aggregation before any reversal starts. It can't move to individual handlers because it needs the total across ALL line items. In Phase 2, this could become `ILineItemHandler.estimate_reversal_cost()` with aggregation in the registry.

---

## Architecture After This Sprint

```
Payment webhook → PaymentCapturedEvent → PaymentCapturedHandler:
  1. Mark invoice PAID
  2. for line_item: line_item_registry.process_activation(line_item, context)
     → CoreLineItemHandler handles SUBSCRIPTION, TOKEN_BUNDLE, ADD_ON
     → BookingLineItemHandler would handle CUSTOM+booking (not yet wired)
  3. Publish invoice.paid + subscription.activated bus events

Refund → RefundService:
  1. Pre-check token balance
  2. Mark invoice REFUNDED
  3. for line_item: registry.process_reversal(line_item, context)

Restore → RestoreService:
  1. Mark invoice PAID
  2. for line_item: registry.process_restoration(line_item, context)
```

---

## Next

Sprint 04b: Create `plugins/subscription/` backend plugin — move SUBSCRIPTION + ADD_ON handling out of `CoreLineItemHandler` into `SubscriptionLineItemHandler`.
