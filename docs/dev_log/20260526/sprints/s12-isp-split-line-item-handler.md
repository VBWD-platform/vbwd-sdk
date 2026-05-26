# S12 — ISP: split `ILineItemHandler` into core + opt-in mixins

**Source:** review §4.2 → `vbwd/events/line_item_registry.py:86-112`.
**Risk:** LOW. Pure interface refactor with full type-level safety net.
**Outcome:** `ILineItemHandler` exposes only the methods every handler must implement (`can_handle_line_item`, `activate`, `reverse`, `restore`). Optional behaviour is expressed as separate narrow protocols (`ICatalogMappedLineItem`, `IRecurringLineItem`) implemented as needed. The registry uses `isinstance(handler, ICatalogMappedLineItem)` (or `runtime_checkable` Protocols) to ask each handler about optional capabilities. Test handlers no longer need to stub no-op default methods.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_line_item_handler_isp.py::test_minimal_handler_has_only_core_methods`
   — defines a `MinimalHandler(ILineItemHandler)` that implements only
   the 4 core methods, asserts construction succeeds and registry
   accepts it. **Today: works, but the handler still ends up with no-op
   inherited optional methods — verify the new split removes them.**
2. `tests/unit/test_line_item_handler_isp.py::test_registry_dispatches_recurring_only_to_recurring_handlers`
   — registers one `IRecurringLineItem` and one plain handler; asks the
   registry for recurring specs; asserts only the recurring one was
   asked.

## Touch-points

- `vbwd/events/line_item_registry.py` (the interface definitions +
  registry dispatch logic)
- Every handler implementation across plugins:
  - `plugins/subscription/.../line_item_handler.py`
  - `plugins/token_payment/.../line_item_handler.py`
  - `plugins/shop/.../line_item_handler.py`
  - any others — sweep `rg "ILineItemHandler" plugins/`

## Steps (each validated)

1. **Write the two Baseline tests.**
2. **Refactor the interface** in `vbwd/events/line_item_registry.py`:
   ```python
   class ILineItemHandler(Protocol):
       @abstractmethod
       def can_handle_line_item(self, line_item, context) -> bool: ...
       @abstractmethod
       def activate(self, line_item, context) -> LineItemResult: ...
       @abstractmethod
       def reverse(self, line_item, context) -> LineItemResult: ...
       @abstractmethod
       def restore(self, line_item, context) -> LineItemResult: ...

   @runtime_checkable
   class ICatalogMappedLineItem(Protocol):
       def resolve_catalog_item_id(self, line_item) -> Optional[str]: ...

   @runtime_checkable
   class IRecurringLineItem(Protocol):
       def is_recurring_line_item(self, line_item) -> bool: ...
       def recurring_billing_spec(self, line_item) -> Optional[RecurringBillingSpec]: ...
   ```
   Remove the three no-op default methods from `ILineItemHandler`.
3. **Update dispatch** — `LineItemHandlerRegistry.resolve_catalog_item_id(line_item)`
   iterates handlers, calls `resolve_catalog_item_id` only on those
   matching `isinstance(handler, ICatalogMappedLineItem)`. Same for
   recurring.
4. **Update each handler** to implement the relevant optional mixin
   only when it actually needs to. Subscription handler implements both
   `ICatalogMappedLineItem` (plan lookup) and `IRecurringLineItem`.
   Token-payment handler implements neither.
5. **Re-run all line-item tests** including subscription's renewal
   tests — green.

## Acceptance (oracle)

- Both Baseline tests green.
- `grep "def resolve_catalog_item_id\|def is_recurring_line_item\|def recurring_billing_spec" plugins/`
  shows declarations ONLY on handlers that actually implement the
  behaviour — no inherited no-op defaults remain.
- Pre-commit `--full` green on backend.

## Notes

- Mirrors the same ISP discipline at the SDK-adapter layer ([[s11]]
  closes the contract; future sprint could add `ICapturableSDKAdapter`
  in the same vein — but only when there are >1 reasons to split it).
- §8 no overengineering: don't introduce more than 2 mixins until a
  real third optional concern shows up.
- Liskov stays clean because each mixin's contract is enforceable
  in isolation — no surprising inheritance.
