# Sprint 04a — Line Item Handler Registry

**Status:** Pending approval
**Date:** 2026-03-27
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Create `ILineItemHandler` interface + `LineItemHandlerRegistry` in core. Plugins register handlers for their own line item types. Core's `PaymentCapturedHandler`, `RefundService`, and `RestoreService` delegate to registry instead of hardcoding.

After this sprint, core only handles `TOKEN_BUNDLE` via `CoreLineItemHandler`. `SUBSCRIPTION` and `ADD_ON` handling remains temporarily in `CoreLineItemHandler` until Sprint 04b creates the subscription plugin.

---

## Steps

| # | Where | What | Tests first |
|---|-------|------|-------------|
| 1 | `vbwd/events/line_item_registry.py` | Create `ILineItemHandler`, `LineItemContext`, `LineItemResult`, `LineItemHandlerRegistry` | `tests/unit/events/test_line_item_registry.py` |
| 2 | `vbwd/handlers/core_line_item_handler.py` | Extract `CoreLineItemHandler` from `PaymentCapturedHandler` — handles TOKEN_BUNDLE + SUBSCRIPTION + ADD_ON (temporary) | `tests/unit/handlers/test_core_line_item_handler.py` |
| 3 | `vbwd/handlers/payment_handler.py` | Slim down — delegate to registry | Update `tests/unit/handlers/test_payment_handlers.py` |
| 4 | `vbwd/services/refund_service.py` | Slim down — delegate reversals to registry | Update `tests/unit/services/test_refund_service.py` |
| 5 | `vbwd/services/restore_service.py` | Slim down — delegate restorations to registry | Update `tests/unit/services/test_restore_service.py` |
| 6 | `vbwd/plugins/base.py` | Add `register_line_item_handlers(registry)` to `BasePlugin` | — |
| 7 | `vbwd/plugins/manager.py` | Call `register_line_item_handlers` in `enable_plugin()` and `load_persisted_state()` | — |
| 8 | `vbwd/app.py` | Wire `CoreLineItemHandler` before plugin init | — |
| 9 | `plugins/booking/__init__.py` + `plugins/booking/booking/handlers/line_item_handler.py` | Create `BookingLineItemHandler`, remove EventBus workaround | `plugins/booking/tests/unit/handlers/test_line_item_handler.py` |
| 10 | All | Run `pre-commit-check.sh` — all green | — |

---

## Interface Design

```python
class ILineItemHandler(ABC):
    def can_handle_line_item(self, line_item, context: LineItemContext) -> bool
    def activate_line_item(self, line_item, context: LineItemContext) -> LineItemResult
    def reverse_line_item(self, line_item, context: LineItemContext) -> LineItemResult
    def restore_line_item(self, line_item, context: LineItemContext) -> LineItemResult

@dataclass
class LineItemContext:
    invoice: Any
    user_id: UUID
    container: Any

@dataclass
class LineItemResult:
    success: bool
    data: dict
    error: Optional[str] = None
    skipped: bool = False
```

---

## Test Cases (TDD)

### Registry (`tests/unit/events/test_line_item_registry.py`)
- register adds handler
- process_activation calls first matching handler
- process_activation skips non-matching
- returns skip result when no handler matches
- handler exception returns error result
- process_reversal delegates correctly
- process_restoration delegates correctly

### CoreLineItemHandler (`tests/unit/handlers/test_core_line_item_handler.py`)
- can_handle: SUBSCRIPTION → True, TOKEN_BUNDLE → True, ADD_ON → True, CUSTOM → False
- activate: pending subscription → active, trial → paid, conflicting single-category cancel
- activate: token bundle → completed, tokens credited
- activate: addon → active
- reverse: subscription → cancelled, tokens debited
- reverse: token bundle → refunded, tokens debited
- reverse: addon → cancelled
- restore: subscription → reactivated, expiry recalculated
- restore: token bundle → completed, tokens re-credited
- restore: addon → reactivated

### BookingLineItemHandler (`plugins/booking/tests/unit/handlers/test_line_item_handler.py`)
- can_handle: CUSTOM + plugin=booking → True, CUSTOM + plugin=other → False, SUBSCRIPTION → False
- activate: creates confirmed booking, writes booking_id to metadata, publishes booking.created
- reverse: cancels booking, publishes booking.cancelled
- restore: returns no-op

---

## Acceptance Criteria

- `PaymentCapturedHandler` has zero `LineItemType` imports
- `RefundService` has no `_reverse_*` methods
- `RestoreService` has no `_restore_*` methods
- All existing tests green (292 backend)
- Booking plugin uses `register_line_item_handlers` instead of EventBus workaround
- `pre-commit-check.sh` passes
