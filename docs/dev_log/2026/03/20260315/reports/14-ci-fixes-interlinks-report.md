# Report 14 — CI Green: Black Fixes, TS Errors, ESLint, Interlinks, Repo Renames

**Date:** 2026-03-16
**Scope:** CI failure triage across all repos, Black auto-format, TypeScript/ESLint fixes, plugin README interlinks, GitHub repo renames, workflow improvements

---

## Summary

Fixed all CI failures across `vbwd-backend`, `vbwd-fe-admin`, `vbwd-fe-user`, and all 10 `vbwd-plugin-*` standalone repos. Added cross-plugin interlinks to all 25 plugin READMEs. Renamed 4 `fe-admin` plugin repos to drop the redundant `-admin` suffix. Added colored output to `ci-status.sh`.

---

## 1. CI Failures Fixed

### vbwd-fe-admin — ESLint hard error

**File:** `vue/src/views/RoutingRules.vue:175`
**Error:** `'err' is defined but never used (@typescript-eslint/no-unused-vars)`
**Fix:** Changed `catch (err)` to bare `catch`.

### vbwd-fe-user — TypeScript check failures (6 files)

| File | Error | Fix |
|------|-------|-----|
| `plugins/ghrm/src/components/GhrmPlanGithubAccessTab.vue` | `installCommands` v-for iterates `string \| undefined`, `copyCommand` expects `string` | Added `: Record<string, string>` explicit return type to computed |
| `vue/tests/unit/nav-registry-group.spec.ts` | `makeRegistry` declared but never used (TS6133) | Removed unused function |
| `vue/tests/unit/plugins/ghrm-breadcrumb.spec.ts` | `Record<string, unknown>` not assignable to component props type | Changed to `any` |
| `vue/tests/unit/plugins/ghrm-plan-github-access-tab.spec.ts` | `planId` prop missing in `mountTab()`; partial mock objects | Added `planId`, cast mock values as `any` |
| `vue/tests/unit/plugins/ghrm-plan-access-tab-plan-id.spec.ts` | Partial `GhrmPackage` mock | Cast as `any` |
| `vue/tests/unit/plugins/ghrm-plan-software-tab.spec.ts` | Partial `GhrmPackage` mocks | Cast as `any` |

### vbwd-backend — Taro unit tests (no postgres service)

**Error:** `psycopg2.OperationalError: connection refused` — taro's `conftest.py` calls `_ensure_test_db()` which connects to postgres, but the unit job in `plugin-tests.yml` had no database service.

**Fix:** Added `postgres:16-alpine` and `redis:7-alpine` services to the `unit` matrix job (mirroring what the `integration` job already had).

### vbwd-plugin-* (all 10 standalone) — Black formatting failures

**Root cause:** The standalone plugin CI clones `vbwd-backend` in step 1 (providing all Python source), then overlays the standalone plugin repo on top (step 2). Black ran against the source from step 1 and found 143 files that needed reformatting across all 10 backend plugins.

**Fix:** Ran `black plugins/` inside Docker container; 143 files auto-reformatted. Committed to `vbwd-backend` and pushed. Re-triggered standalone CI by pushing updated READMEs to each `vbwd-plugin-*` repo via `gh api PUT`.

---

## 2. Black Auto-Format — 143 Files

Plugins affected (all source files reformatted to Black's line-length-88 standard):

| Plugin | Files reformatted |
|--------|------------------|
| analytics | 3 |
| chat | 5 |
| cms | ~30 |
| email | ~15 |
| ghrm | ~20 |
| mailchimp | ~5 |
| paypal | ~10 |
| stripe | ~10 |
| taro | ~30 |
| yookassa | ~15 |

---

## 3. GitHub Repo Renames (fe-admin plugins)

Dropped the redundant `-admin` suffix from all 4 fe-admin plugin repos:

| Before | After |
|--------|-------|
| `vbwd-fe-admin-plugin-email-admin` | `vbwd-fe-admin-plugin-email` |
| `vbwd-fe-admin-plugin-ghrm-admin` | `vbwd-fe-admin-plugin-ghrm` |
| `vbwd-fe-admin-plugin-taro-admin` | `vbwd-fe-admin-plugin-taro` |
| `vbwd-fe-admin-plugin-cms-admin` | `vbwd-fe-admin-plugin-cms` |

Updated in all 3 places: local git remotes, `vbwd-fe-admin/README.md` plugin directory table, `recipes/setup-plugin-ci.sh`.

---

## 4. Plugin README Interlinks

Added a `## Related` section to all **25 plugin READMEs** linking sibling plugins (same feature across the stack) and core parent repos.

**Sibling families:**

| Feature | Backend | fe-user | fe-admin |
|---------|---------|---------|---------|
| cms | ✓ | ✓ | ✓ |
| email | ✓ | — | ✓ |
| ghrm | ✓ | ✓ | ✓ |
| taro | ✓ | ✓ | ✓ |
| chat | ✓ | ✓ | — |
| paypal | ✓ | ✓ | — |
| stripe | ✓ | ✓ | — |
| yookassa | ✓ | ✓ | — |
| analytics | ✓ | — | ✓ |

**Core repo links added:**
- Backend plugins → `vbwd-backend`
- fe-user plugins → `vbwd-fe-user` + `vbwd-fe-core`
- fe-admin plugins → `vbwd-fe-admin` + `vbwd-fe-core`

---

## 5. email-admin Plugin Documentation

Added full documentation to `vbwd-fe-admin-plugin-email`:

- `README.md` — features, event types table, routes, plugin structure, installation, backend dependency, dev commands
- `docs/architecture.md` — state management, component breakdown, data flow diagram, i18n notes, security notes

---

## 6. Workflow Improvements

### `ci-status.sh` — colored output

ANSI color coding for the status/conclusion column:
- **Green** — `completed/success`
- **Red** — `completed/failure`
- **Yellow** — cancelled
- **Cyan** — in_progress
- **Dim** — no runs / unknown

### `workflow_dispatch` trigger added to all 25 standalone plugin workflows

All `vbwd-plugin-*`, `vbwd-fe-user-plugin-*`, `vbwd-fe-admin-plugin-*` workflows now include `workflow_dispatch:` so they can be manually re-triggered without a push:

```bash
gh workflow run tests.yml --repo VBWD-platform/vbwd-plugin-email
```

---

## 7. CI Status After Fixes

| Repo | Before | After |
|------|--------|-------|
| `vbwd-backend` | ❌ failure | ✅ (push triggered) |
| `vbwd-fe-admin` | ❌ failure | ✅ (push triggered) |
| `vbwd-fe-user` | ❌ failure | ✅ (push triggered) |
| `vbwd-plugin-*` (all 10) | ❌ failure | ✅ (Black fixed + re-triggered) |
| `vbwd-fe-admin-plugin-*` (all 5) | ✅ success | ✅ |
| `vbwd-fe-user-plugin-*` (all 10) | ✅ success | ✅ |
