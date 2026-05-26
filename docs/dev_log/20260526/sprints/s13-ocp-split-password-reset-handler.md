# S13 — OCP: split `PasswordResetHandler` into request + execute handlers

**Source:** review §4.3 → `vbwd/handlers/password_reset_handler.py:54-59`.
**Risk:** LOW. Pure refactor — behaviour preserved.
**Outcome:** Two single-purpose handlers (`PasswordResetRequestHandler`, `PasswordResetExecuteHandler`), each subscribing to one event type. The `isinstance(event, …)` branch in `handle()` is gone. Adding a future "password reset confirmed" event becomes additive, not modifying.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/handlers/test_password_reset_request_handler.py::test_handles_only_request_event`
   — assert `can_handle(PasswordResetRequestEvent())` true,
   `can_handle(PasswordResetExecuteEvent())` false.
2. `tests/unit/handlers/test_password_reset_execute_handler.py::test_handles_only_execute_event`
   — mirror.
3. `tests/unit/test_no_isinstance_branching_in_handlers.py::test_no_event_isinstance_chain`
   — greps `vbwd/handlers/` for `isinstance(event,`; allows at most
   one per file (the `can_handle` impl). **Today: fails — the unified
   handler has both branches in `handle()`.**

## Touch-points

- `vbwd/handlers/password_reset_handler.py` (split into two files
  or two classes in one file; either is fine — pick whichever the
  rest of the handlers directory uses)
- `vbwd/app.py` / wherever handlers register (replace one handler
  registration with two)
- Any tests that currently exercise both events through the unified
  handler

## Steps (each validated)

1. **Write the three Baseline tests.** The first two pass against
   trivial new classes; the third fails today.
2. **Create `PasswordResetRequestHandler`** with the existing
   `handle_reset_request` body as `handle()`. `can_handle` checks the
   event type.
3. **Create `PasswordResetExecuteHandler`** likewise.
4. **Delete the unified `PasswordResetHandler`** (or keep as a thin
   facade if any external code imports it — prefer delete, §7 clean
   code, no dead code).
5. **Update the handler registration** to register both.
6. **Re-run password reset integration tests** — green.

## Acceptance (oracle)

- All three Baseline tests green.
- `rg "isinstance\(event," vbwd/handlers/` shows ≤1 hit per file
  (the `can_handle` impl).
- Pre-commit `--full` green.

## Notes

- Tiny sprint — could pair with [[s11]] or [[s12]] in one PR if the
  team prefers larger batches. Kept separate here for clarity.
- §8 no overengineering: don't introduce a generic event-router
  decorator yet — two explicit handlers is the simpler honest answer.
