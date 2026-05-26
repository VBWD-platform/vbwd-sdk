# S01 — Remove the two `from plugins.*` imports from core

**Source:** review §1.1 (`vbwd/scheduler.py`) + §1.2 (`vbwd/routes/admin/access.py`) + §1.4 (`vbwd/app.py:323`).
**Risk:** HIGH. Core boot path + an admin route. Tested down path = revert the import re-introduction.
**Outcome:** `grep -rn "from plugins\." vbwd/` returns zero hits. Core boots and serves with the booking and CMS plugins both **enabled** and both **disabled**, with no behaviour change for users.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md). Gate: `bin/pre-commit-check.sh --full` green on `vbwd-backend` before "done".

## Baseline (E1)

Characterisation tests (write FIRST):

1. `tests/unit/test_core_agnosticism.py::test_no_plugin_imports_in_core`
   — walks `vbwd/` with `ast.parse`, asserts no `Import`/`ImportFrom`
   node whose module starts with `plugins.`. **Today: fails on 5 lines.**
2. `tests/integration/test_boot_without_plugins.py::test_app_boots_with_no_plugins_enabled`
   — sets `plugins.json` to `{}`, hits `/api/v1/health`, expects 200,
   and asserts the booking scheduler is silently absent (not crashed).
3. `tests/integration/test_access_user_level_content_without_cms.py`
   — disables CMS plugin, calls `GET /api/v1/admin/access/user-levels/<id>/content`,
   expects 200 with empty list (not 500).

## Touch-points (verified by grep on 2026-05-26)

- `vbwd/scheduler.py:15-22` — `from plugins.booking.booking.repositories.…` ×3
- `vbwd/routes/admin/access.py:440-441` — `from plugins.cms.src.models.…` ×2
- `vbwd/app.py:323-325` — explicit `start_booking_scheduler(app)` import
- All downstream callers of the above

## Steps (each validated)

### Part A — Booking scheduler port

1. **Define the port.** New `vbwd/interfaces/background_job_scheduler.py`:
   ```python
   class IBackgroundJobScheduler(Protocol):
       def start(self, app) -> None: ...
       def shutdown(self) -> None: ...
   ```
   Plus a registry: `vbwd/services/background_job_scheduler.py` with
   `register_background_job_scheduler(impl)` and
   `resolve_background_job_scheduler() -> Optional[IBackgroundJobScheduler]`.
   Null default = no-op.
2. **Move the impl into the booking plugin.** Take everything inside
   `vbwd/scheduler.py` and create `plugins/booking/booking/services/booking_job_scheduler.py`
   implementing `IBackgroundJobScheduler`. Booking plugin's `on_enable`
   calls `register_background_job_scheduler(BookingJobScheduler(...))`;
   `on_disable` shuts it down + unregisters.
3. **Replace core call site.** `vbwd/app.py:323-325` becomes:
   ```python
   if not app.config.get("TESTING"):
       scheduler = resolve_background_job_scheduler()
       if scheduler is not None:
           scheduler.start(app)
   ```
4. **Delete `vbwd/scheduler.py`.** No grace period — it's a violation.

### Part B — CMS access content port

5. **Define the port.** `vbwd/interfaces/access_level_content_provider.py`:
   ```python
   class IAccessLevelContentProvider(Protocol):
       def list_restricted_content(self, level_id: str) -> list[ContentRef]: ...
   ```
   `ContentRef` = a `@dataclass` of `{kind, id, title, slug, plugin}`.
   Registry mirrors the booking one (multi-provider — CMS, shop, taro can
   all register).
6. **Move the query into the CMS plugin.** Implementation lives in
   `plugins/cms/cms/services/access_content_provider.py` (or `src/` for
   the legacy CMS layout). Registers in `on_enable`.
7. **Replace core call site.** `vbwd/routes/admin/access.py:440-441` —
   delete the `from plugins.cms.…` imports; iterate
   `resolve_access_level_content_providers()` and concatenate results.

### Part C — Verify

8. Run characterisation tests from Baseline — all green.
9. `bin/pre-commit-check.sh --full` green on `vbwd-backend`.
10. Manual smoke: app boots with `plugins.json={}`; app boots with the
    full plugin set; admin access-content route returns the same payload
    as before (compare with snapshot).

## Acceptance (oracle)

- `grep -rn "from plugins\." vbwd/` → empty.
- `tests/unit/test_core_agnosticism.py::test_no_plugin_imports_in_core` — green.
- Both integration tests (boot-without-plugins, access-without-CMS) green.
- Booking scheduler still runs the completion job when booking is enabled
  (verify a fixture booking transitions to `completed` after the job fires).

## Notes

- This is the same port/registry pattern Sprint 11 used for
  `ISubscriptionLifecycle` / `IEntitlementProvider`. Reuse the helper
  shape verbatim — DRY (§5).
- Don't introduce a fat `IPluginLifecycle` to bundle scheduler + content
  + future hooks — narrow ports per ISP (§3).
- Leaves `vbwd/app.py:206-228` (`"analytics"` hardcoding) for [[s06]] —
  scoped out to keep this slice narrow (§8 no overengineering).
