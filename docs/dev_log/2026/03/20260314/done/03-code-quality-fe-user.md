# Sprint: Code Quality — vbwd-fe-user

**Date:** 2026-03-14
**Ref:** `docs/dev_log/20260314/reports/01-code-quality-audit.md`

## Context

The code quality audit identified 5 categories of issues in `vbwd-fe-user` and its plugins. This sprint addresses all of them. No new features — only internal quality, type safety, and consistency.

## Core Requirements

TDD, SOLID, DI, DRY, LSP, DevOps First, clean code, no overengineering.

---

## Steps

### Step 1: Type the API Client — Eliminate `api as any` in CMS Store (SOLID — ISP, Clean Code)

**Scope:** `plugins/cms/src/stores/cms.ts` — 7+ `(api as any).getCmsPages()` style calls

Same root cause as fe-admin: the API object imported from `vbwd-view-component` or the plugin's own api layer has no TypeScript signatures for CMS endpoints.

**Option A — Define types in the plugin:**

```typescript
// plugins/cms/src/api/cmsApi.ts
export interface CmsApi {
  getCmsPages(params?: CmsPageQueryParams): Promise<CmsPage[]>
  getCmsPage(slug: string): Promise<CmsPage>
  getCmsCategories(): Promise<CmsCategory[]>
}

export function createCmsApi(baseUrl: string): CmsApi {
  return {
    getCmsPages: (params) => fetch(`${baseUrl}/cms/pages`, ...).then(r => r.json()),
    // ...
  }
}
```

**Option B — Add CMS methods to core API type:**
If the core `api` object already has these methods, add their signatures to the core type declaration in `vbwd-fe-core`.

Prefer Option A (plugin owns its API client) — it keeps the plugin self-contained (SOLID — ISP, no core changes for plugin functionality).

**Remove** every `(api as any)` call. Compiler errors surface mismatches — fix them.

**Tests:** `./bin/pre-commit-check.sh --style` must pass with zero `vue-tsc` errors.

---

### Step 2: Extract Translation Registration Utility (DRY, SOLID — SRP)

**Scope:** `plugins/stripe/`, `plugins/taro/`, `plugins/billing/`, `plugins/github-oauth/` — each repeats an identical 8-line translation registration block

**Create:** `src/utils/registerPluginTranslations.ts`

```typescript
import type { Composer } from 'vue-i18n'

type LocaleMessages = Record<string, Record<string, unknown>>

/**
 * Merges plugin locale messages into the global i18n instance.
 * Safe to call multiple times — uses mergeLocaleMessage for existing locales.
 */
export function registerPluginTranslations(
  i18n: Composer,
  messages: LocaleMessages
): void {
  Object.entries(messages).forEach(([locale, msgs]) => {
    if (i18n.availableLocales.includes(locale)) {
      i18n.mergeLocaleMessage(locale, msgs)
    } else {
      i18n.setLocaleMessage(locale, msgs)
    }
  })
}
```

**Replace** all inline blocks:

```typescript
// Before (repeated in every payment plugin)
const messages = { en: enLocale, ru: ruLocale }
Object.entries(messages).forEach(([locale, msgs]) => {
  if (i18n.global.availableLocales.includes(locale)) {
    i18n.global.mergeLocaleMessage(locale, msgs)
  } else {
    i18n.global.setLocaleMessage(locale, msgs)
  }
})

// After (one line)
registerPluginTranslations(i18n.global, { en: enLocale, ru: ruLocale })
```

**Tests:** `tests/unit/utils/registerPluginTranslations.spec.ts`
- First call with new locale → `setLocaleMessage` path taken
- Second call with existing locale → `mergeLocaleMessage` path taken (messages merged, not overwritten)
- Multiple locales in one call → all registered

---

### Step 3: Standardize `_active` Plugin Flag Pattern (SOLID — LSP, Clean Code)

**Scope:** All plugin `index.ts` files using `plugin._active`

Three inconsistent patterns exist across plugins. Standardize to the one defined in `vbwd-fe-core`'s `IPlugin` interface.

**Canonical pattern** (check what `IPlugin` declares in `vbwd-fe-core/src/types/`):

```typescript
// Correct: use the interface as defined, no casting
if (plugin._active) {
  // ...
}
```

**Fix:** Scan all plugin files for non-standard patterns and align them:

```bash
grep -rn "_active" plugins/ src/
```

If `IPlugin._active` is typed as `boolean | undefined`, update the check to:
```typescript
if (plugin._active === true) { ... }
```
Pick one form and apply it everywhere. If `IPlugin` needs a type fix, fix it in `vbwd-fe-core` first (then rebuild `dist/`).

Do NOT add new abstraction for this — it is a one-line read property. Three lines of code in three files is better than a new abstraction.

**Tests:** `./bin/pre-commit-check.sh --style` — `vue-tsc` will catch type mismatches after casts are removed.

---

### Step 4: Remove `console.log` Debug Statements (DevOps First, Clean Code)

**Scope:** `plugins/ghrm/`, `plugins/taro/` — 4+ debug log statements; scan all plugins

```bash
grep -rn "console\.log" plugins/ src/
```

Delete every `console.log`. Convert any meaningful diagnostic output to `console.warn` or `console.error`.

**ESLint rule** to prevent regressions (add to `.eslintrc.cjs` or `eslint.config.js`):
```javascript
rules: {
  'no-console': ['error', { allow: ['warn', 'error'] }],
}
```

`./bin/pre-commit-check.sh --style` will then block any reintroduction of `console.log`.

---

### Step 5: Centralize API Error Handling (SOLID — SRP, DevOps First)

**Scope:** `src/` — currently each component/store handles HTTP errors individually

Same pattern as fe-admin Step 4 but for the user-facing app.

**Create:** `src/api/errorHandler.ts`

```typescript
export function setupApiErrorInterceptor(apiClient: AxiosInstance): void {
  apiClient.interceptors.response.use(
    response => response,
    error => {
      const status = error.response?.status

      if (status === 401) {
        router.push('/login')
      } else if (status === 402) {
        // Payment required — redirect to upgrade page
        router.push('/plans')
      } else if (status >= 500) {
        showToast('Something went wrong — please try again', 'error')
      } else if (!error.response) {
        showToast('Network error', 'error')
      }

      return Promise.reject(error)
    }
  )
}
```

Note the 402 case: plugin API calls debit tokens; a 402 means the user is out of tokens. Centralizing this means every plugin gets the upgrade redirect for free.

**Wire in** during app bootstrap.

**Tests:** `tests/unit/api/errorHandler.spec.ts`
- 401 → redirect to `/login`
- 402 → redirect to `/plans`
- 500 → toast shown
- No response → offline toast

---

### Step 6: Add README.md to All User-Facing Plugins

**Scope:** 9 plugins missing README — `ghrm`, `cms`, `taro`, `stripe`, `github-oauth`, `analytics`, `notifications`, `profile`, `billing`

Each `plugins/<name>/README.md`:

```markdown
# Plugin Name (User)

## Purpose
What user-facing functionality this plugin provides.

## Backend Counterpart
Links to `plugins/<name>/` in vbwd-backend.

## Admin Counterpart
Links to `plugins/<name>-admin/` in vbwd-fe-admin (if exists).

## Routes / Views
| Path | View Component | Description |
|------|---------------|-------------|

## Stores
Pinia stores this plugin registers.

## Translations
Locale keys namespace (e.g., `ghrm.*`, `cms.*`).

## Events
Platform events this plugin emits or subscribes to.

## Testing
```bash
cd vbwd-fe-user
./bin/pre-commit-check.sh --unit
```
```

---

## Verification

```bash
# In vbwd-fe-user/
./bin/pre-commit-check.sh              # style checks (ESLint + vue-tsc)
./bin/pre-commit-check.sh --unit       # style + Vitest unit tests
./bin/pre-commit-check.sh --all        # everything including e2e
```

All checks must be green before merging. Specifically:
1. `vue-tsc` — zero type errors; no `as any` in CMS store or any plugin store
2. `ESLint` — zero `no-console` violations across all plugins
3. `Vitest` — `registerPluginTranslations` tests pass; error handler tests pass
4. Manual: as unauthenticated user, trigger any auth-gated action → redirected to `/login`
5. Manual: trigger a 402 (e.g., run out of tokens) → redirected to `/plans`
6. Manual: trigger a 500 → toast appears, user is not stuck on a blank page
