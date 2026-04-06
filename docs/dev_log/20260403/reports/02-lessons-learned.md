# Lessons Learned — Sprints 12-14: Access Control

**Date:** 2026-04-04

---

## 1. MagicMock Doesn't Behave Like Real Objects

**Problem:** `MagicMock()` returns a truthy `MagicMock` for any attribute access. When `@require_admin` called `g.user.is_admin`, a MagicMock user returned a truthy MagicMock — bypassing the admin check entirely.

**Impact:** Unit tests that mocked users passed even when they shouldn't have. The `test_dashboard_requires_admin` test was green for months with a broken assertion.

**Fix:** Explicitly set `mock_user.is_admin = False` on every mock that represents a non-admin user. For real `User()` instances, the `@property` computes correctly.

**Rule:** When mocking objects that have properties used in auth/security checks, always explicitly set the property value. Never rely on MagicMock's default behavior for security-critical paths.

---

## 2. SQLAlchemy Relationships Are Not Python Lists

**Problem:** `isinstance(user.assigned_roles, (list, tuple))` returned `False` for SQLAlchemy's `InstrumentedList`. The RBAC check fell through to the legacy fallback, which worked — but the RBAC system was silently not used.

**Impact:** After adding RBAC roles and assigning them to users, the system still used the legacy `UserRole.ADMIN` enum for all permission checks. RBAC was a no-op.

**Fix:** Use `try: list(roles)` with exception handling instead of `isinstance` checks. SQLAlchemy relationships are iterable but not `list` instances.

**Rule:** Never use `isinstance` to check SQLAlchemy relationship types. Use `try/except` or `list()` to safely iterate.

---

## 3. Login Response Schema Must Match Frontend Expectations

**Problem:** The backend `UserData` dataclass and `UserDataSchema` didn't include `permissions`. The backend computed permissions correctly, but the login response sent `permissions: null`. The frontend stored null permissions, and `hasPermission()` always returned false.

**Impact:** After login, every route with `requiredPermission` redirected to 403 Forbidden. The admin panel was completely locked out despite the user being a super-admin.

**Fix:** Added `permissions: Optional[list]` to `UserData` dataclass, `permissions` field to `UserDataSchema`, and populated it from `user.to_dict()["permissions"]` in the auth service.

**Rule:** When adding new fields to the user model that affect frontend behavior, trace the full path: model `to_dict()` → service response → schema → API response → frontend store. Missing any step creates silent failures.

---

## 4. fe-core Submodule Must Be Rebuilt AND Copied

**Problem:** After editing `vbwd-fe-core/src/stores/auth.ts` and running `npm run build` in `vbwd-fe-core/`, the fe-admin app still used the old code. The built `dist/` wasn't copied to the submodule directory at `vbwd-fe-admin/vbwd-fe-core/dist/`.

**Impact:** Frontend tests failed because `isAdmin` getter used the old logic (only checking `ADMIN` string) instead of the new logic (checking `super-admin`, `admin`, `ADMIN`).

**Fix:** After building fe-core, explicitly copy `dist/` to both `vbwd-fe-admin/vbwd-fe-core/dist/` and `vbwd-fe-user/vbwd-fe-core/dist/`.

**Rule:** Every fe-core change requires: (1) edit source, (2) `npm run build` in fe-core, (3) copy dist to fe-admin + fe-user submodule dirs. The `make rebuild-core` target should handle this.

---

## 5. User Data Must Persist Across Page Refresh

**Problem:** `initAuth()` restored the JWT token from localStorage but not the user object (roles, permissions). After page refresh, `authStore.user` was null, so `hasPermission()` returned false and all protected routes showed 403.

**Impact:** Users had to log out and back in after every page refresh. The access level system appeared broken.

**Fix:** Save `user` JSON to localStorage alongside the token on login. Restore it in `initAuth()`. Clear it on logout.

**Rule:** Any auth data the frontend needs between page loads must be persisted to localStorage. Token alone is not enough — the frontend needs roles and permissions client-side without an extra API call.

---

## 6. Black Formatter Version/Config Must Match Pre-commit

**Problem:** We ran `black --line-length 120` to format code, but the pre-commit script runs `black --check` without `--line-length` (using the default 88). The pre-commit always reported "would reformat" because the line length didn't match.

**Impact:** Hours spent debugging "why won't black pass" when the code was already formatted — just with the wrong line length.

**Fix:** Run `black` without `--line-length` to match the pre-commit's default. Or update the pre-commit to use `--line-length 120`.

**Rule:** Before formatting, check what flags the pre-commit uses for the formatter. Match them exactly. Consider adding a `pyproject.toml` or `.black.toml` to centralize the config.

---

## 7. Dynamic Imports in Vue `onMounted` Break Test Timing

**Problem:** After refactoring `Dashboard.vue` to lazy-load stores via `await import('../stores/analytics')` inside `onMounted`, unit tests couldn't find rendered widgets. `flushPromises()` didn't wait for the dynamic import to resolve.

**Impact:** Dashboard plugin widget tests failed — the stores weren't loaded by the time assertions ran.

**Fix:** Added `vi.mock('@/stores/analytics', ...)` to the test so the dynamic import resolves synchronously in test environment. Added extra `await flushPromises()` + `await nextTick()` cycles.

**Rule:** When using dynamic `import()` in Vue components, the corresponding test must mock the imported module via `vi.mock()`. `flushPromises()` handles Promises but dynamic imports may need additional flush cycles.

---

## 8. Plugin Toggle at Runtime vs Startup Are Different

**Problem:** When a plugin is disabled in `plugins.json`, it's never registered and its blueprint never exists — routes genuinely 404. But when toggled off via admin UI at runtime, the Flask blueprint is still registered — routes still respond.

**Impact:** Runtime plugin disable doesn't fully isolate the plugin's API. A disabled plugin's routes may still work.

**Fix (partial):** The permission system adds a second layer — even if the route exists, the user needs the plugin's permission. But a true runtime disable needs a `@plugin_required` decorator or before_request check on plugin blueprints.

**Rule:** Don't rely solely on blueprint registration for plugin isolation. Add a middleware check for plugin status on every request to a plugin's routes.

---

## 9. Table Prefix Rename Requires Global Search

**Problem:** Renaming `ecommerce_*` tables to `shop_*` and core tables to `vbwd_*` required updating not just model `__tablename__` values, but also: FK references in other plugins, raw SQL in tests, integration test assertions, junction table names, and enum type names.

**Impact:** Missed references caused `UndefinedTable` errors in tests and migrations. Some were only discovered when running integration tests hours later.

**Fix:** Systematic grep across the entire codebase for each old prefix. Used `sed` for bulk rename.

**Rule:** When renaming table prefixes, create a checklist: (1) model `__tablename__`, (2) ForeignKey strings, (3) association Table() names, (4) raw SQL in tests, (5) migration files, (6) enum type names, (7) integration test assertions. Grep for every instance before declaring done.

---

## 10. Pre-commit Checks Should Run Locally Before Push

**Problem:** Multiple rounds of "fix one lint error, re-run, find another" during Sprint 14e. Each pre-commit run took 2-3 minutes.

**Impact:** The fix-lint-test loop consumed significant time.

**Rule:** Run `flake8` locally (not via docker) for fast iteration. Only run the full docker-based pre-commit as a final validation. Consider installing `black` and `flake8` locally for sub-second feedback.

---

## Summary of Rules

1. **Mock security properties explicitly** — never rely on MagicMock defaults for auth checks
2. **Use `list()` not `isinstance` for SQLAlchemy relationships**
3. **Trace new fields end-to-end** — model → service → schema → API → frontend store
4. **Copy fe-core dist to submodule dirs after build**
5. **Persist auth data to localStorage** — token + user + permissions
6. **Match formatter config with pre-commit config**
7. **Mock dynamic imports in tests**
8. **Plugin isolation needs middleware, not just blueprint registration**
9. **Global search when renaming table prefixes**
10. **Run lint locally for fast feedback, docker for final validation**
