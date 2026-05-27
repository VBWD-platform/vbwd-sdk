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

## Outcome — 2026-05-27 (DONE — narrow audit-and-cut)

**Done.** Audit done, 2 truly-dead surfaces removed; 109 tests still green.

### Per-caller audit findings (grep-based)

| Candidate | Production callers | Verdict |
|---|---|---|
| `PluginManager.register_plugin` | many | KEEP |
| `PluginManager.get_plugin` | many | KEEP |
| `PluginManager.get_all_plugins` | many (incl. `app.py`) | KEEP |
| `PluginManager.get_enabled_plugins` | many | KEEP |
| `PluginManager.enable_plugin` | `vbwd/app.py`, CLI, admin routes | KEEP |
| `PluginManager.disable_plugin` | CLI + admin routes | KEEP |
| `PluginManager.initialize_plugin` | analytics plugin test (1) | KEEP (used by tests) |
| `PluginManager.discover` | `vbwd/app.py` | KEEP |
| `PluginManager.load_persisted_state` | `vbwd/app.py` | KEEP |
| **`PluginManager.get_plugin_blueprints`** | **NONE in production** (only own test file) | **DELETE** |
| `EmailService.send_welcome_email` | `vbwd/handlers/user_handlers.py:54` | KEEP |
| **`EmailService.send_invoice`** | **NONE** (zero grep hits) | **DELETE** |

### Patches

- `vbwd/plugins/manager.py:169-176` — deleted `get_plugin_blueprints`
  (production unused; only kept alive by its own test).
- `tests/unit/plugins/test_plugin_blueprints.py` — deleted (4 tests
  that tested the dead method).
- `vbwd/plugins/manager.py:6` — dropped `Tuple` from the typing
  import (unused after the deletion).
- `vbwd/services/email_service.py:278-324` — deleted `send_invoice`
  (47 LOC of dead code).
- `tests/unit/services/test_email_service.py:264-279` — deleted
  `test_send_invoice_email` for the same reason.

### What I did NOT delete (§8 narrow)

- The original sprint planned a sweep of every named-template helper
  (`send_welcome_email` etc.) on `EmailService`. `send_welcome_email`
  has a real caller — leaving it alone.
- `PluginManager` "unused methods" turned out to be mostly USED via
  CLI/admin/tests — only `get_plugin_blueprints` was actually dead.

**LOC removed:** ~60 production LOC + ~50 test LOC of strictly-dead code.
