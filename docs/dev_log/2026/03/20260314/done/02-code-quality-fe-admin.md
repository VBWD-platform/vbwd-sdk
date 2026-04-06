# Sprint: Code Quality — vbwd-fe-admin

**Date:** 2026-03-14
**Ref:** `docs/dev_log/20260314/reports/01-code-quality-audit.md`

## Context

The code quality audit identified 4 categories of issues in `vbwd-fe-admin` and its plugins. This sprint addresses all of them. No new features — only internal quality, type safety, and consistency.

## Core Requirements

TDD, SOLID, DI, DRY, LSP, DevOps First, clean code, no overengineering.

---

## Steps

### Step 1: Type the API Client — Eliminate `api as any` (SOLID — ISP, Clean Code)

**Scope:** All store files using `(api as any).someEndpoint()`

The root cause is that the `api` import lacks TypeScript method signatures. Define explicit interfaces so the compiler can check call sites.

**Create:** `src/api/types.ts` (or extend existing api client type file)

Define one interface per API domain:

```typescript
// src/api/types.ts
export interface AdminPlansApi {
  getPlans(): Promise<TarifPlan[]>
  getPlan(id: string): Promise<TarifPlan>
  createPlan(data: CreatePlanDto): Promise<TarifPlan>
  updatePlan(id: string, data: UpdatePlanDto): Promise<TarifPlan>
  deletePlan(id: string): Promise<void>
}

export interface AdminUsersApi { /* ... */ }
export interface AdminInvoicesApi { /* ... */ }
// etc.
```

**Remove** all `as any` casts from store files and replace with the typed interface. The compiler will surface any mismatches — fix those call sites, do not suppress them.

**Affected stores:** Any store using `(api as any)`:
```bash
grep -rn "api as any" src/ plugins/
```

**Tests:** `./bin/pre-commit-check.sh --style` (runs `vue-tsc`) must pass with zero type errors after this step.

---

### Step 2: Fix `as any` Translation Casts in CMS Admin Plugin (DRY, Clean Code)

**Scope:** `plugins/cms-admin/` — 8+ `(t as any)(...)` call sites

**Root cause:** `vue-i18n` requires type augmentation to know the shape of your locale messages.

**Create:** `plugins/cms-admin/src/i18n.d.ts`

```typescript
import 'vue-i18n'

declare module 'vue-i18n' {
  export interface DefineLocaleMessage {
    cms: {
      title: string
      pages: string
      categories: string
      images: string
      // add all keys used in this plugin
      [key: string]: string
    }
  }
}
```

After adding this declaration, remove every `(t as any)` cast — use `t('cms.someKey')` directly.

If the type augmentation approach causes conflicts with other plugins, use a scoped helper instead:

```typescript
// plugins/cms-admin/src/utils/i18n.ts
import { useI18n } from 'vue-i18n'

export function useCmsI18n() {
  const { t } = useI18n()
  return {
    t: (key: string) => t(`cms.${key}` as any),  // cast isolated to one place
  }
}
```

This isolates the single unavoidable cast, instead of repeating it at every call site.

**Tests:** `./bin/pre-commit-check.sh --style` must pass. If `vue-tsc` previously ignored these (because `as any` suppressed errors), add a `// @ts-expect-error` guard removal test to confirm zero suppressions.

---

### Step 3: Remove `console.log` Debug Statements (DevOps First, Clean Code)

**Scope:** `plugins/taro-admin/` — 5+ debug log statements; scan all plugins

```bash
grep -rn "console\.log" plugins/ src/
```

Delete every `console.log` call in production code. If runtime observability is needed, the project should add a structured logger (out of scope for this sprint — just remove the logs).

If any `console.log` is actually meaningful (e.g., during a critical init step), convert to `console.warn` or `console.error` with a clear message and file a follow-up task for a proper logger.

**Tests:** Add an ESLint rule to prevent regressions:

In `.eslintrc.cjs` or `eslint.config.js`:
```javascript
rules: {
  'no-console': ['error', { allow: ['warn', 'error'] }],
}
```

`./bin/pre-commit-check.sh --style` (runs ESLint) will then fail if any `console.log` is reintroduced.

---

### Step 4: Centralize API Error Handling (SOLID — SRP, DevOps First)

**Scope:** `src/api/` — currently each store handles HTTP errors individually

**Create:** `src/api/errorHandler.ts`

```typescript
import { useRouter } from 'vue-router'
import { useToast } from '...'  // project toast utility

export function setupApiErrorInterceptor(apiClient: AxiosInstance): void {
  apiClient.interceptors.response.use(
    response => response,
    error => {
      const status = error.response?.status

      if (status === 401) {
        const router = useRouter()
        router.push('/login')
      } else if (status === 403) {
        showToast('Permission denied', 'error')
      } else if (status >= 500) {
        showToast('Server error — please try again', 'error')
      } else if (!error.response) {
        showToast('Network error — check your connection', 'error')
      }

      return Promise.reject(error)
    }
  )
}
```

**Wire in** `src/main.ts` or wherever the API client is created.

**Remove** redundant per-store catch blocks that only `console.error` or silently swallow errors. Stores should only catch errors when they have specific recovery logic (e.g., showing a field-level validation message).

**Tests:** `tests/unit/api/test_errorHandler.spec.ts`
- 401 response → `router.push('/login')` called
- 403 response → toast shown with "Permission denied"
- 500 response → toast shown with "Server error"
- Network error (no response) → offline toast

---

### Step 5: Add README.md to All Admin Plugins

**Scope:** `plugins/cms-admin/`, `plugins/ghrm-admin/`, `plugins/taro-admin/`, `plugins/stripe-admin/`

Each `plugins/<name>/README.md`:

```markdown
# Plugin Name (Admin)

## Purpose
What admin capability this plugin adds to vbwd-fe-admin.

## Backend Counterpart
Links to `plugins/<name>/` in vbwd-backend.

## Routes / Views
| Path | View Component | Description |
|------|---------------|-------------|

## Stores
List of Pinia stores this plugin registers.

## Configuration
Any env vars or config keys read by this plugin.

## Testing
```bash
cd vbwd-fe-admin
./bin/pre-commit-check.sh --unit
```
```

---

## Verification

```bash
# In vbwd-fe-admin/
./bin/pre-commit-check.sh              # style checks (ESLint + vue-tsc)
./bin/pre-commit-check.sh --unit       # style + Vitest unit tests
./bin/pre-commit-check.sh --all        # everything including e2e
```

All checks must be green before merging. Specifically:
1. `vue-tsc` — zero type errors; no `as any` except the one isolated in `useCmsI18n` helper
2. `ESLint` — zero `no-console` violations across all plugins
3. `Vitest` — error handler tests pass
4. Manual: trigger a 401 response in the admin UI → redirected to `/login`
5. Manual: trigger a 500 response → toast appears
