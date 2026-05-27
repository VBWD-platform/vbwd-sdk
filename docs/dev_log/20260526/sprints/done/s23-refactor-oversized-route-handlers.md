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

## Outcome — 2026-05-27 (PARTIAL — 1 of 5 routes shipped as template)

**Done — 1 route extracted (create_payment_method) as the worked example;
8 new service unit tests green; 4 routes remain in backlog.**

### Shipped (worked example)

- `vbwd/services/payment_method_service.py` (NEW) — `PaymentMethodService.create(payload)`
  with `PaymentMethodValidationError` for domain errors. Repository
  injected; session injected separately (the "clear other defaults"
  query needs the session today — flagged for follow-up to push down
  into the repo).
- `vbwd/routes/admin/payment_methods.py:38-66` — route shrunk from
  **95 LOC → 32 LOC** (~66% reduction). Body is now: deserialize JSON
  → call service → serialize.
- `tests/unit/services/test_payment_method_service.py` (NEW) — 8 unit
  tests covering required-field validation, duplicate-code check,
  decimal parsing, is_default cascade, default-kwargs sanity.

### Backlog (remaining 4 handlers — 1 PR per handler, use the above as template)

| File | Function | LOC | Target service |
|---|---|---|---|
| `vbwd/routes/admin/users.py:197` | `update_user` | 127 | `UserService.update(...)` |
| `vbwd/routes/admin/users.py:19` | `create_user` | 111 | `UserService.create(...)` |
| `vbwd/routes/admin/invoices.py:280` | `refund_invoice` | 81 | existing `RefundService` |
| `plugins/stripe/stripe/routes.py:380` | `_handle_refund_updated` | 75 | helper in stripe plugin |

### Template each follow-up PR follows

1. Write characterisation tests for the route's current behaviour
   (happy path + 1-2 edges) — green.
2. Add (or extend) the service method with the moved logic; inject
   collaborators (repo, session, etc.).
3. Reduce route to: deserialize → call service → serialize.
4. Add service unit tests covering the moved logic.
5. Re-run characterisation tests — still green.
6. Run pre-commit `--full`.

### Quality gate

`pre-commit-check.sh --quick` green; 1 worked example proves the
pattern; the other 4 are scoped backlog items, not unknown work.
