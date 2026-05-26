# S25 — Trim over-engineered surfaces: `PluginManager` dead methods, `EmailService` named templates

**Source:** review §8.
**Risk:** LOW. Pure deletion / collapse — improves clarity.
**Outcome:** `PluginManager` exposes only the methods it actually needs. `EmailService` exposes one templated send method and lets callers compose; the half-dozen `send_welcome_email` / `send_password_changed_email` etc. helpers are gone.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md). This sprint IS the §8 cleanup pass.

## Baseline (E1)

1. `tests/meta/test_no_unused_public_api.py::test_plugin_manager_public_surface`
   — for each `PluginManager` public method, asserts ≥1 caller exists
   via `rg`. **Today: fails on `initialize_plugin`, `enable_plugin`,
   `disable_plugin` (per review §8) — verify.**
2. `tests/meta/test_email_service_surface.py::test_no_per_template_helper_methods`
   — asserts `EmailService` exposes `send_template(...)` and the
   generic `send(...)` only.

## Touch-points

- `vbwd/plugins/manager.py` (`PluginManager`)
- `vbwd/services/email_service.py:249-324`
- Every caller of the about-to-be-deleted helpers

## Steps (each validated)

### Part A — PluginManager

1. **Run the meta test** — get the list of unused methods.
2. **For each unused method**, decide:
   - **Truly unused** → delete.
   - **Used in tests only** → delete + update tests (the tests were
     testing dead code).
   - **Public API for admin enable/disable** → wire it up to the
     actual admin route (which currently uses something else?) OR
     delete and reroute the admin route to whatever is actually used.
   Verify with `rg` after each decision.
3. **Re-run the meta test** — green.

### Part B — EmailService

4. **Audit callers** of `send_welcome_email`, `send_invoice`,
   `send_password_reset` (and any other per-template named method).
5. **Per caller, replace** with the generic
   `email_service.send_template("welcome", to=..., context=...)`.
6. **Delete the per-template helpers.** Keep `send_template(...)` and
   the underlying `send(...)`.
7. **Move template→subject mapping** out of the service — let callers
   pass `subject=` explicitly, OR put the mapping in
   `vbwd/services/email_templates.py` as a pure data structure (a
   `dict[str, str]`). The service is then free of email-content
   knowledge — §3-S SRP.
8. Re-run all email-related tests.

## Acceptance (oracle)

- Both meta tests green.
- `PluginManager` line count ↓ (no dead methods).
- `EmailService.send_template(...)` and `.send(...)` are the only
  send methods.
- Pre-commit `--full` green.

## Notes

- This is the only sprint in the batch that DELETES code rather than
  adding. Schedule it last in any given week so it doesn't conflict
  with parallel feature work.
- The DRY win from collapsing email-helper methods is small but it
  closes an OCP problem (adding a new email template no longer
  requires modifying `EmailService`).
- §8 no overengineering — and crucially, this sprint DOES NOT include
  removing `dependency_injector` (the audit's first overengineering
  suggestion). Reasoning is documented in
  `../reports/01-backend-pattern-and-agnosticism-review.md` §8: with
  multiple plugins each owning repos that need wiring at runtime, the
  declarative container is the least engineered solution that works.
  The fix is "use it correctly everywhere" ([[s08]], [[s09]], [[s10]]),
  not "remove it".
