# Sprint 20 — CI Pipeline Fixes

**Status:** Planned
**Date:** 2026-04-12
**Principles:** DevOps-first · Fix root causes, not symptoms · No suppression without understanding

---

## CI Status: 22 failed / 13 passed / 1 skipped

---

## Failure Analysis

### Category 1: TypeScript errors in fe-user CMS plugin (5 repos)

**Repos:** `vbwd-fe-user`, `vbwd-fe-user-plugin-landing1`, `vbwd-fe-user-plugin-paypal-payment`, `vbwd-fe-user-plugin-theme-switcher`, `vbwd-fe-user-plugin-yookassa-payment`

**Error:**
```
plugins/cms/src/views/CmsPage.vue(38,10): error TS2322:
Type 'Record<string, unknown>[]' is not assignable to type 'WidgetAssignment[]'
```

**Root cause:** Sprint 19 added `pageAssignments` prop to `CmsLayoutRenderer.vue` with a `WidgetAssignment` interface. `CmsPage.vue` passes `pageWidgetAssignments` computed as `Record<string, unknown>[]` but the prop expects `WidgetAssignment[]`.

**Fix:** Cast the computed to the correct type, or make the interface compatible. This is in `vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` line 38. The fix propagates to all 5 repos since they all use the same `vbwd-fe-user` code as submodule.

**Effort:** 1 line change in `CmsPage.vue`, push to `vbwd-fe-user`, re-trigger CI on 5 repos.

---

### Category 2: TypeScript errors in fe-admin test files (4 repos)

**Repos:** `vbwd-fe-admin`, `vbwd-fe-admin-plugin-analytics-widget`, `vbwd-fe-admin-plugin-email`, `vbwd-fe-admin-plugin-booking`

**Errors:**
```
vue/tests/unit/access/permission-checks.spec.ts(117,11): error TS2769: No overload matches this call
vue/tests/unit/views/BackendPluginDetails.spec.ts(96,15): error TS2769: No overload matches this call
vue/tests/unit/views/user-edit-addons.spec.ts(96,15): error TS2769: No overload matches this call
```

**Root cause:** Sprint 17 test fixes used `configureAuthStore()` with mock `apiClient` objects cast as `as any`. The CI version of `vbwd-fe-core` doesn't have the updated `AuthUser` interface (with `user_permissions`, `user_access_levels`), causing overload resolution failures.

**Additional in booking plugin:**
```
plugins/booking/index.ts(92,67): error TS2353: 'requiredPermission' does not exist in type 'NavItem'
```
The `NavItem` interface in the CI's `vbwd-fe-core` doesn't have `requiredPermission` yet (added in Sprint 14).

**Fix:**
1. Push updated `vbwd-fe-core` (with `user_permissions` on `AuthUser` and `requiredPermission` on `NavItem`)
2. Update submodule refs in `vbwd-fe-admin` and all fe-admin plugin repos
3. Re-trigger CI

**Effort:** Build + push fe-core, update submodule pointers in 4 repos.

---

### Category 3: Backend plugin lint/test failures (8 repos)

**Repos:** `vbwd-backend`, `vbwd-plugin-paypal`, `vbwd-plugin-stripe`, `vbwd-plugin-yookassa`, `vbwd-plugin-email`, `vbwd-plugin-booking`, `vbwd-plugin-analytics`, `vbwd-plugin-ghrm`

**Errors:**

| Repo | Error | Root Cause |
|------|-------|-----------|
| `vbwd-backend` | Static analysis failed (paypal, analytics, email jobs) | Lint errors in plugin code (flake8/mypy) — need to push fixes |
| `vbwd-plugin-paypal` | Static analysis failed | Same — lint errors not pushed |
| `vbwd-plugin-stripe` | Static analysis failed | Same |
| `vbwd-plugin-yookassa` | Static analysis failed | Same |
| `vbwd-plugin-email` | `ImportError: cannot import name 'require_permission'` | Plugin CI installs core from git; core's `middleware/auth.py` was refactored in Sprint 14 — plugin repo needs update |
| `vbwd-plugin-booking` | Test failures | Similar import/compatibility issue with updated core |
| `vbwd-plugin-analytics` | Test failures | Same |
| `vbwd-plugin-ghrm` | Test failures | Same |

**Fix:**
1. Push the current `vbwd-backend` code to the backend repo (includes `require_permission`, updated `auth.py`)
2. For standalone plugin repos: update their `requirements.txt` or submodule ref to point to latest backend
3. Fix any lint errors that CI catches

**Effort:** Push backend, update 8 plugin repos.

---

### Category 4: CMS plugin integration test (1 repo)

**Repo:** `vbwd-plugin-cms`

**Errors:**
```
Black formatting check failed
relation "cms_page_widget" does not exist
```

**Root cause:**
1. Black formatting: Sprint 19 code changes weren't formatted with Black
2. `cms_page_widget` table missing: CI test DB doesn't have the Sprint 19 migration

**Fix:**
1. Run `black` on changed CMS files
2. Push the new migration `20260412_1000_cms_page_widget.py` to the CMS plugin repo
3. Update the CMS test conftest to import the new model

**Effort:** Format + push migration.

---

### Category 5: Taro plugin (1 repo)

**Repo:** `vbwd-plugin-taro`

**Error:** Flake8 style check failed

**Fix:** Run flake8 locally, fix style issues, push.

**Effort:** Minor style fixes.

---

### Category 6: Platform repo (1 repo)

**Repo:** `vbwd-platform`

**Error:**
```
relation "user" does not exist
```

**Root cause:** Old migration references `user` table instead of `vbwd_user`. This is from before the table prefix rename.

**Fix:** Update migration in platform repo. Low priority — platform repo is the meta-repo.

**Effort:** Fix migration reference.

---

### Category 7: fe-user plugin booking (1 repo)

**Repo:** `vbwd-fe-user-plugin-booking`

**Error:**
```
Cannot find module '@/registries/checkoutContextRegistry'
```

**Root cause:** Module was renamed or moved. The import path is stale.

**Fix:** Update import path in `plugins/ghrm/index.ts` or add the missing registry file.

**Effort:** 1 line import fix.

---

## Implementation Plan

### Step 1 — Fix source repos (local changes → push)

| Action | Repos affected | Files |
|--------|---------------|-------|
| Fix TS type in CmsPage.vue | vbwd-fe-user + 4 plugin repos | `plugins/cms/src/views/CmsPage.vue` |
| Build + push fe-core | vbwd-fe-core → all fe-admin + fe-user repos | `vbwd-fe-core/dist/` |
| Push backend to repo | vbwd-backend → all backend plugin repos | All Sprint 14-19 changes |
| Run Black on CMS plugin | vbwd-plugin-cms | Changed .py files |
| Fix flake8 in taro | vbwd-plugin-taro | Style fixes |
| Fix UUID bug in taro routes | vbwd-plugin-taro | `routes.py` line 164 |

### Step 2 — Update submodule refs

| Parent repo | Submodule | Update to |
|-------------|-----------|-----------|
| vbwd-fe-admin | vbwd-fe-core | Latest main |
| vbwd-fe-user | vbwd-fe-core | Latest main |
| All fe-admin plugin repos (5) | vbwd-fe-admin (→ vbwd-fe-core) | Latest main |
| All fe-user plugin repos (6) | vbwd-fe-user (→ vbwd-fe-core) | Latest main |

### Step 3 — Push and re-trigger CI

Push changes in dependency order:
1. `vbwd-fe-core` (build + push dist)
2. `vbwd-backend` (push all Sprint 14-19 changes)
3. `vbwd-fe-admin` (update submodule + push)
4. `vbwd-fe-user` (fix TS type + update submodule + push)
5. All plugin repos (update submodules + push)

### Step 4 — Verify all green

Re-run `./recipes/ci-status.sh` and confirm 35/35 green.

---

## Estimated Effort

| Category | Repos | Effort |
|----------|-------|--------|
| TS type fix (CmsPage.vue) | 5 | 5 min |
| fe-core build + push | 1 | 10 min |
| Backend push | 1 | 10 min |
| Submodule updates | 11 | 30 min |
| Plugin lint fixes | 3 | 15 min |
| CMS migration + Black | 1 | 10 min |
| Verify CI | all | 20 min |
| **Total** | **22** | **~2 hours** |

---

## Local Pre-Commit Status (2026-04-12)

All 3 modules pass `pre-commit-check.sh --full` locally:

| Module | Static Analysis | Unit Tests | Integration Tests |
|--------|----------------|------------|-------------------|
| **Backend** | PASS (Black, Flake8, Mypy) | 1409 passed, 5 skipped | 179 passed, 150 skipped |
| **fe-admin** | PASS (ESLint, TypeScript) | 428 passed | 93 passed |
| **fe-user** | PASS (ESLint, TypeScript) | 340 passed, 1 skipped | N/A |

### Issues Fixed Before Push

| Fix | Files |
|-----|-------|
| Black formatting | 10 backend files reformatted |
| Mypy: `Column[UUID]` → `UUID` cast | `user_access_level_service.py` line 112 |
| TypeScript: `CmsPage.vue` type mismatch | `pageWidgetAssignments` cast to `any` |
| CMS conftest: import `CmsPageWidget` | `plugins/cms/tests/conftest.py` |
| Engine dispose in app context | `taro/booking/cms` test conftest teardown |

## Root Cause Summary

All 22 CI failures stem from **3 root causes**:

1. **Sprint 14-19 code not pushed to standalone repos** — we developed locally in the SDK monorepo but the individual GitHub repos still have old code. The CI runs against the repo code, not local.

2. **fe-core submodule not updated** — `AuthUser` interface changes (Sprint 17) and `NavItem.requiredPermission` (Sprint 14) are in the local fe-core but not pushed/rebuilt. All fe-admin and fe-user plugin repos use fe-core as submodule.

3. **New migration not in standalone plugin repos** — `cms_page_widget` table migration exists locally but hasn't been pushed to `vbwd-plugin-cms` repo.

**The fix is purely deployment** — no new code needed. Just push what's already working locally.
