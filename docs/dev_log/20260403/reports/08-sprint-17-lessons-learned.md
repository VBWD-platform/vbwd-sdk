# Lessons Learned — Sprint 17: User Access Levels

**Date:** 2026-04-07

---

## 1. Consolidated Migrations Cause Silent Gaps on Existing Databases

**Problem:** Sprint 17a added the `vbwd_user_access_level` tables to the consolidated `vbwd_001` "create all tables" migration. Databases already past that revision never got the new tables. The API returned 500 on every request that touched the User model because SQLAlchemy tried to JOIN on a non-existent table.

**Impact:** The entire API was broken — login, user listing, everything. The error was `ProgrammingError: relation "vbwd_user_user_access_levels" does not exist`. No test caught this because tests create tables from scratch.

**Fix:** Created a separate incremental migration `20260406_1800_add_user_access_levels.py` that adds the tables independently.

**Rule:** Never add new tables to an existing "consolidated" migration. Always create an incremental migration with `down_revision` pointing to the latest revision. The consolidated migration is for fresh installs only.

---

## 2. EventBus Events Must Be Published — Not Just Defined

**Problem:** Sprint 17b needed to listen to `subscription.activated` and `subscription.cancelled` events via EventBus. The DomainEvent classes existed (`SubscriptionActivatedEvent`, `SubscriptionCancelledEvent`) but the `LineItemHandler` — which actually activates and cancels subscriptions — never published these events to the EventBus. The `DomainEventDispatcher.emit()` bridges to EventBus, but nobody called `emit()` from the activation flow.

**Impact:** The access level handler was registered correctly but never triggered. The GHRM plugin had the same silent failure — it subscribed to `subscription.activated` but the event was never published.

**Fix:** Added `event_bus.publish()` calls directly in `LineItemHandler._activate_subscription()` and `_reverse_subscription()` with proper payloads (`user_id`, `plan_slug`, `plan_id`, `subscription_id`).

**Rule:** When adding an event handler, verify the event is actually published somewhere in the flow. Trace: who creates the entity → who changes its state → who publishes the event. If nobody publishes, the handler is dead code.

---

## 3. Mock Patch Path Must Match Import Location, Not Definition

**Problem:** Unit tests for `SubscriptionAccessLevelHandler` tried to patch `plugins.subscription.subscription.handlers.access_level_handler.UserAccessLevelService`. But the handler uses a lazy import (`from vbwd.services.user_access_level_service import UserAccessLevelService`), so the class isn't an attribute of the handler module at patch time.

**Impact:** All 11 handler tests errored with `AttributeError: module does not have the attribute 'UserAccessLevelService'`.

**Fix:** Changed the patch target to `vbwd.services.user_access_level_service.UserAccessLevelService` — the module where the class is defined, which is where the lazy import resolves.

**Rule:** When patching a class that's imported lazily inside a function, patch it at its definition module, not at the importer's module. The importer doesn't have the attribute until the function runs.

---

## 4. fe-user Uses localStorage, Not Pinia Auth Store

**Problem:** The fe-admin app uses `configureAuthStore()` from fe-core (Pinia-based auth). The fe-user app does NOT — it uses raw `localStorage` for `auth_token` and `user_id`. Adding `hasUserPermission()` to the Pinia auth store was necessary for fe-core/fe-admin, but fe-user needed its own helper reading from localStorage.

**Impact:** If we'd only added the Pinia getter and assumed fe-user would use it, the router guard would never have worked.

**Fix:** Added `hasUserPermission()` and `getUserPermissions()` as standalone functions in `fe-user/vue/src/api/index.ts` that read from `localStorage.getItem('user_permissions')`. The Login.vue stores `user_permissions` in localStorage alongside `auth_token`.

**Rule:** Before adding a feature to a shared library, check if the consuming app actually uses that library for the relevant concern. fe-user and fe-admin have different auth architectures — changes must be made in both.

---

## 5. Docker Dev Containers Serve HMR, Not Static Builds

**Problem:** E2E tests run against Docker containers (port 8081/8080). After modifying Vue components, the Vite HMR server inside the container picks up changes automatically — but only if the container was already watching the files when they changed. If the container started before the changes, a restart is needed.

**Impact:** E2E tests couldn't find the new "Admin Access Levels" / "User Access Levels" tabs because the container was serving the old version. Tests appeared to fail at login, but the real issue was that the page after login didn't have the new UI.

**Fix:** Restarted the Docker dev container (`docker compose restart dev`) to force HMR to process all pending file changes.

**Rule:** After making significant Vue component changes, restart the Docker dev container before running E2E tests. HMR works for incremental changes during development, but accumulated changes after container startup may not all apply.

---

## 6. E2E Login: Use SPA Navigation, Not Direct URL

**Problem:** E2E tests tried to login via UI, then navigate to `/admin/settings/access` with `page.goto()`. The direct URL navigation caused a full page reload, which lost the in-memory Pinia auth state. The page redirected back to login.

**Impact:** UI tests for the two-tab view always failed — the page showed the login form instead of the access levels page.

**Fix:** After login, navigate via sidebar link clicks (`page.locator('a[href*="settings/access"]').click()`) instead of `page.goto()`. SPA navigation preserves the Pinia auth state. The existing passing tests already used this pattern.

**Rule:** In SPA E2E tests, always prefer clicking internal links over `page.goto()` for authenticated pages. Direct URL navigation resets the SPA state. If direct navigation is needed, set the auth token in localStorage before navigating.

---

## 7. Test User Passwords Drift From Seeder Expectations

**Problem:** The test user `test@example.com` existed in the database but with a different password than what the seeder and tests expected (`TestPass123@`). The seeder only creates users if they don't exist — it doesn't update passwords for existing users.

**Impact:** All 47 fe-user E2E tests failed at login with "Invalid credentials". The admin tests passed because `admin@example.com` had the correct password.

**Fix:** Reset the password via a one-off Python script: `bcrypt.hashpw(b'TestPass123@', bcrypt.gensalt())`.

**Rule:** The seeder's "skip if exists" pattern is safe for production but dangerous for test environments. Consider adding a `--reset-passwords` flag to the seeder that updates passwords for existing demo users, or validate passwords in a health check.

---

## 8. Core Agnostic / Plugin Gnostic — Applied Successfully

**Validation:** Sprint 17 strictly followed the "core agnostic, plugins gnostic" principle:
- Core provides `UserAccessLevelService` (assign/revoke) — knows nothing about plans
- Core provides `@require_user_permission` — knows nothing about what permissions exist
- Core provides `BasePlugin.user_permissions` — empty list by default
- Subscription plugin declares its own user permissions and handles its own events
- The admin API collects permissions dynamically from enabled plugins

**Result:** Adding a new plugin with user permissions requires zero core changes. The plugin declares `user_permissions`, and they automatically appear in the admin permission matrix and are available for access level assignment.

---

## 9. Two Permission Systems — Clean Separation Matters

**Observation:** The project now has two parallel permission systems:
- **Admin permissions** → `vbwd_role` → `@require_permission` → `hasPermission()` → fe-admin
- **User permissions** → `vbwd_user_access_level` → `@require_user_permission` → `hasUserPermission()` → fe-user

**Risk:** Naming confusion. The word "permission" appears in both systems. The admin system uses `permissions`, `hasPermission()`, `requiredPermission`. The user system uses `user_permissions`, `hasUserPermission()`, `requiredUserPermission`.

**Mitigation:** Consistent prefix `user_` on everything in the user system. The documentation explicitly calls out the difference. The database uses separate tables. The API uses separate endpoints (`/permissions` vs `/user-permissions`).

**Rule:** When building parallel systems, establish a naming convention upfront and enforce it consistently across backend, frontend, API, and documentation.

---

## 10. Sub-Sprint Granularity Enables Incremental Delivery

**Observation:** Sprint 17 was split into 7 sub-sprints (17a–17g). This allowed:
- 17a–17b were completed in one session (backend + plugin)
- 17c–17d were completed in the next session (admin API + frontend)
- 17e–17g were completed after a gap analysis revealed they were missing

**Benefit:** Each sub-sprint was independently testable. Backend tests passed before frontend work started. Admin UI tests passed before fe-user work started. No "big bang" integration risk.

**Contrast:** Without sub-sprints, the entire sprint would have been one large PR with backend + frontend + tests all mixed together. Any failure would require debugging across all layers.

**Rule:** For cross-cutting features (backend + multiple frontends), always split into sub-sprints by layer. Verify each layer independently before moving to the next.
