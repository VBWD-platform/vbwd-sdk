# S23 — Refactor oversized route handlers into service methods

**Source:** review §7.1 → 5 route handlers exceed 75 LOC; two exceed 100 LOC.
**Risk:** MEDIUM. Touches admin user/invoice management.
**Outcome:** Every route handler is <50 LOC. Business logic lives in services. Routes do: deserialize → call service → serialize response.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/meta/test_route_size.py::test_no_route_handler_over_50_loc`
   — parses `vbwd/routes/` with `ast`, computes body LOC of each
   `@route`-decorated function; asserts ≤50. **Today: fails on 5.**
2. Behaviour-preserving characterisation tests for each route (write
   FIRST, before refactor — capture the current response payload and
   side-effects on representative inputs).

## Touch-points (from review)

| File | Function | LOC |
|---|---|---|
| `vbwd/routes/admin/users.py:197` | `update_user` | 127 |
| `vbwd/routes/admin/users.py:19` | `create_user` | 111 |
| `vbwd/routes/admin/payment_methods.py:38` | `create_payment_method` | 95 |
| `vbwd/routes/admin/invoices.py:280` | `refund_invoice` | 81 |
| `plugins/stripe/stripe/routes.py:380` | `_handle_refund_updated` | 75 |

## Steps (each validated; one route at a time)

For each row above:

1. **Write the characterisation tests.** Snapshot the response body +
   DB delta for a happy path + 1-2 edge cases. Green.
2. **Add the service method** (e.g.
   `UserService.update(...)`, `PaymentMethodService.create(...)`,
   `InvoiceService.refund(...)`, `StripeRefundHandler.handle(...)`).
   Move the route body into the service. The service receives all
   dependencies via DI (per [[s08]]/[[s09]] discipline).
3. **Reduce the route** to:
   ```python
   def update_user(user_id):
       data = UpdateUserSchema().load(request.get_json())
       user = current_app.container.user_service().update(user_id, data)
       return jsonify(user.to_dict()), 200
   ```
4. **Re-run characterisation tests** — green (no behaviour change).
5. **Re-run the meta test for that file** — green.

## Acceptance (oracle)

- Meta test green for all 5 files.
- Characterisation tests for each route green.
- Pre-commit `--full` green.

## Notes

- Sequence these one PR per route so reverts are scoped.
- The service methods should NOT be a 100-LOC blob either — extract
  private helpers internally where the logic naturally splits.
- §7 clean code: remove any dead branches that surfaced during the
  extraction.
- §8 no overengineering: don't introduce a Mediator / CommandBus
  pattern — a plain service method is enough.
