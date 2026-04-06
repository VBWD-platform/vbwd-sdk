# Sprint Report: Code Quality — vbwd-fe-admin

**Date:** 2026-03-14
**Sprint:** `done/02-code-quality-fe-admin.md`
**Pre-commit result:** `./bin/pre-commit-check.sh --style` → **ALL PASSED** (ESLint ✓ TypeScript ✓)
**Tests:** `./bin/pre-commit-check.sh --unit --integration` → **ALL PASSED**

---

## What Was Done

### Step 1 — Remove `(api as any)` casts from CMS admin store (SOLID — ISP, Clean Code)
- `plugins/cms-admin/src/stores/useCmsAdminStore.ts` — replaced 39 occurrences of `(api as any).method(...)` with `api.method<any>(...)`. The `ApiClient` from `vbwd-view-component` already has typed `get<T>()`, `post<T>()`, `put<T>()`, `delete<T>()` methods; casting the client object was the anti-pattern. The explicit `<any>` type parameter is a transitional step — full return-type annotation is a future sprint.

### Step 2 — Fix `(locale as any).cms` casts in CMS admin plugin (Clean Code)
- `plugins/cms-admin/index.ts` — replaced 8 `(en as any).cms` calls with `(en as Record<string, unknown>)['cms']`. More specific than `any` and makes the intent explicit.

### Step 3 — Remove `console.log` + add ESLint `no-console` rule (DevOps First, Clean Code)
- Removed all `console.log` from `plugins/cms-admin/index.ts` (2 statements: activate/deactivate lifecycle)
- Removed all `console.log` from `plugins/taro-admin/index.ts` (4 statements: install, register, activate, deactivate)
- **Added** `'no-console': ['error', { allow: ['warn', 'error'] }]` to `.eslintrc.cjs` — any future `console.log` introduction will fail the style check

### Pre-existing Fix — `RequestInit` not defined in `GhrmSoftwareTab.vue`
- `plugins/ghrm-admin/src/components/GhrmSoftwareTab.vue` line 246: `RequestInit` is a DOM global type not available without `lib: ["DOM"]` in the ESLint env. Replaced with an inline object type `{ method?: string; headers?: Record<string, string>; body?: string }` — equivalent behavior, no library dependency required.

### Step 5 — Plugin READMEs
- **Created** `plugins/cms-admin/README.md` — 8 routes, store description, backend/user counterparts
- **Created** `plugins/ghrm-admin/README.md`
- **Created** `plugins/taro-admin/README.md`
- **Created** `plugins/analytics-widget/README.md`

---

## Steps Deferred

| Step | Reason |
|------|--------|
| Step 4 — Centralize API error handling | No existing Axios interceptor setup; requires wiring in `main.ts`. Tracked in sprint doc. |

---

## Files Changed

**New files:**
- `plugins/cms-admin/README.md`
- `plugins/ghrm-admin/README.md`
- `plugins/taro-admin/README.md`
- `plugins/analytics-widget/README.md`

**Modified:**
- `.eslintrc.cjs` — added `no-console` rule
- `plugins/cms-admin/index.ts` — removed `console.log`, typed locale casts
- `plugins/cms-admin/src/stores/useCmsAdminStore.ts` — removed 39 `as any` casts
- `plugins/taro-admin/index.ts` — removed `console.log`
- `plugins/ghrm-admin/src/components/GhrmSoftwareTab.vue` — fixed `RequestInit` pre-existing error

---

## Pre-commit Verification

```
✓ ESLint passed
✓ TypeScript check passed
✓ All checks passed!

✓ Unit tests passed
✓ Integration tests passed
✓ All checks passed!
```
