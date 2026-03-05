# Sprint 25a: Frontend Static Analysis & Test Fixes

## Goal
Fix all ESLint errors, TypeScript errors, and pre-existing test failures across user, admin, and core frontends. Zero suppression — remove dead code, fix types properly, split complex code into helpers/services where needed.

## Engineering Principles
- **TDD**: Fix failing tests by correcting test mocks and expectations to match actual implementation
- **SOLID — SRP**: If a class/component is too long or complex, split into helpers/services
- **SOLID — LSP**: Fix `IPlugin` interface to properly support `_active` field (Liskov: all plugins must be substitutable)
- **DI**: No hardcoded types — fix typing by extending interfaces, not by suppressing
- **Clean Code**: Remove dead imports, unused variables, unreachable code
- **DRY**: No duplicate type assertions — fix at the interface level
- **No suppression**: Do NOT add `// @ts-ignore`, `// eslint-disable`, or `as any` to hide problems
- **No overengineering**: Minimal changes to fix each issue — don't refactor surrounding code

## Testing Approach

All checks MUST pass green:

```bash
# 1. User ESLint (target: 0 errors, 0 suppressible warnings)
cd vbwd-frontend/user/vue && npx eslint . --ext .ts,.vue

# 2. Admin ESLint (target: 0 errors, 0 suppressible warnings)
cd vbwd-frontend/admin/vue && npx eslint . --ext .ts,.vue

# 3. User TypeScript (target: 0 errors)
cd vbwd-frontend/user/vue && npx vue-tsc --noEmit

# 4. Admin TypeScript (target: 0 errors — already clean, must stay clean)
cd vbwd-frontend/admin/vue && npx vue-tsc --noEmit

# 5. User unit tests (target: 169 passed)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 6. Admin unit tests (target: 195 passed)
cd vbwd-frontend/admin/vue && npx vitest run tests/unit/

# 7. Admin integration tests (target: 136 passed)
cd vbwd-frontend/admin/vue && npx vitest run tests/integration/

# 8. Core unit tests (target: 301 passed, 0 failed — fix 3 AuthGuard failures)
cd vbwd-frontend/core && npx vitest run

# 9. Full pre-commit
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit --integration
```

---

## Error Inventory

### User ESLint: 8 errors, 6 warnings

| # | File | Line | Rule | Severity | Issue |
|---|------|------|------|----------|-------|
| 1 | `views/AddonDetail.vue` | 180 | `no-unused-vars` | ERROR | `t` assigned but never used |
| 2 | `views/AddonInfoView.vue` | 95 | `no-unused-vars` | ERROR | `router` assigned but never used |
| 3 | `views/PlanDetailView.vue` | 112 | `no-unused-vars` | ERROR | `router` assigned but never used |
| 4 | `views/TokenBundleDetailView.vue` | 86 | `no-unused-vars` | ERROR | `router` assigned but never used |
| 5 | `tests/unit/plugins/checkout-public.spec.ts` | 66 | `ban-types` | ERROR | `Function` type used (unsafe) |
| 6 | `tests/unit/plugins/checkout-public.spec.ts` | 159 | `no-unused-vars` | ERROR | `wrapper` assigned but never used |
| 7 | `tests/unit/plugins/landing1.spec.ts` | 5 | `no-unused-vars` | ERROR | `IPlatformSDK` imported but never used |
| 8 | `tests/unit/plugins/plugin-routes.spec.ts` | 1 | `no-unused-vars` | ERROR | `beforeEach` imported but never used |
| 9 | `components/checkout/TermsCheckbox.vue` | 52 | `vue/no-v-html` | WARN | XSS risk with v-html |
| 10 | `views/AddonDetail.vue` | 187 | `no-explicit-any` | WARN | `any` type |
| 11 | `tests/.../addon-detail.spec.ts` | 73 | `no-explicit-any` | WARN | `any` type |
| 12 | `tests/.../addons-plan-filter.spec.ts` | 73 | `no-explicit-any` | WARN | `any` type |
| 13 | `tests/.../dashboard-addons.spec.ts` | 38 | `no-explicit-any` | WARN | `any` type |
| 14 | `tests/.../dashboard-token-history.spec.ts` | 38 | `no-explicit-any` | WARN | `any` type |

### User vue-tsc: 17 errors

| # | File | Line | Code | Issue |
|---|------|------|------|-------|
| 1 | `plugins/stripe-payment/index.ts` | 7 | TS2353 | `_active` not in `IPlugin` |
| 2 | `plugins/stripe-payment/index.ts` | 30 | TS2339 | `_active` not in `IPlugin` |
| 3 | `plugins/stripe-payment/index.ts` | 31 | TS2339 | `_active` not in `IPlugin` |
| 4 | `server/services/plugin-config.ts` | 5 | TS6196 | `PluginRegistryEntry` unused import |
| 5 | `views/AddonDetail.vue` | 180 | TS6133 | `t` declared but never read |
| 6 | `views/AddonInfoView.vue` | 95 | TS6133 | `router` declared but never read |
| 7 | `views/PlanDetailView.vue` | 112 | TS6133 | `router` declared but never read |
| 8 | `views/TokenBundleDetailView.vue` | 86 | TS6133 | `router` declared but never read |
| 9 | `tests/.../checkout-public.spec.ts` | 159 | TS6133 | `wrapper` declared but never read |
| 10 | `tests/.../landing1.spec.ts` | 5 | TS6133 | `IPlatformSDK` declared but never read |
| 11 | `tests/.../landing1.spec.ts` | 62 | TS2552 | Cannot find name `IPlugin` |
| 12 | `tests/.../landing1.spec.ts` | 69 | TS2552 | Cannot find name `IPlugin` |
| 13 | `tests/.../plugin-routes.spec.ts` | 1 | TS6133 | `beforeEach` declared but never read |
| 14 | `tests/.../stripe-payment.spec.ts` | 39 | TS2339 | `requiresAuth` not in `{}` |
| 15 | `tests/.../stripe-payment.spec.ts` | 44 | TS2339 | `_active` not in `IPlugin` |
| 16 | `tests/.../stripe-payment.spec.ts` | 46 | TS2339 | `_active` not in `IPlugin` |
| 17 | `tests/.../stripe-payment.spec.ts` | 48 | TS2339 | `_active` not in `IPlugin` |

### Admin ESLint: 0 errors, 7 warnings

| # | File | Line | Rule | Severity | Issue |
|---|------|------|------|----------|-------|
| 1 | `tests/.../route-injection.spec.ts` | 7,14 | `vue/one-component-per-file` | WARN | Multiple components in test file |
| 2 | `tests/.../dashboard-plugins.spec.ts` | 49,56 | `vue/one-component-per-file` | WARN | Multiple components in test file |
| 3 | `tests/.../invoices.spec.ts` | 162 | `no-explicit-any` | WARN | `any` type |
| 4 | `tests/.../webhooks.spec.ts` | 143 | `no-explicit-any` | WARN | `any` type |
| 5 | `tests/.../user-edit-addons.spec.ts` | 61 | `no-explicit-any` | WARN | `any` type |

### Admin vue-tsc: 0 errors (clean)

### Core Tests: 3 failures (AuthGuard)

| # | Test | Expected | Got | Root Cause |
|---|------|----------|-----|------------|
| 1 | `should redirect away from guest routes when authenticated` | `next({ name: 'dashboard' })` | `next()` | Mock returns `isAuthenticated: { value: true }` — guard sees object (truthy) but Pinia getter returns boolean |
| 2 | `should allow guest routes when not authenticated` | `next()` | `next({ name: 'dashboard' })` | Mock returns `isAuthenticated: { value: false }` — object `{ value: false }` is truthy |
| 3 | `should use custom route names from options` | `next({ name: 'auth-login', ... })` | `next()` | Same mock incompatibility |

**Root cause**: Test mocks `useAuthStore` returning `{ isAuthenticated: { value: bool } }` but Pinia getters expose `isAuthenticated` as a direct boolean (not a ref). The guard checks `!auth.isAuthenticated` — the object `{ value: false }` is truthy, so the guard logic is inverted.

### Admin Integration: i18n warnings

`[intlify] Not found 'users.roles' key` — The key exists in `en.json` but test i18n setup may not load nested structures correctly. Investigate and fix if needed.

---

## Task 1: Fix IPlugin Interface — Add `_active` Field

### Root Cause
`IPlugin` in `core/src/plugins/types.ts` has no `_active` field, but `stripe-payment/index.ts` (and `landing1/index.ts`) use it. This causes TS2353/TS2339 errors.

### Fix
Add optional `_active` field to `IPlugin` interface. This is the correct fix (not suppression) because:
- All payment plugins need lifecycle state tracking
- The interface should support it (OCP — open for extension)

### Files
| File | Action |
|------|--------|
| `core/src/plugins/types.ts` | **MODIFY** — add `_active?: boolean` to `IPlugin` |

### Change
```typescript
export interface IPlugin {
  // ... existing fields ...

  /** Internal active state for plugin lifecycle tracking */
  _active?: boolean;
}
```

This also fixes:
- `stripe-payment/index.ts` TS2353 (line 7), TS2339 (lines 30, 31)
- `stripe-payment.spec.ts` TS2339 (lines 44, 46, 48)
- `landing1.spec.ts` — the cast `as IPlugin & { _active: boolean }` becomes unnecessary (but harmless)

---

## Task 2: Fix IRouteConfig — Add `meta` Field

### Root Cause
`IRouteConfig` in `core/src/plugins/types.ts` uses `[key: string]: unknown` index signature, but `route.meta?.requiresAuth` fails because `meta` is typed as `unknown`. The TS2339 error at `stripe-payment.spec.ts:39` is because accessing `.requiresAuth` on `unknown` is not allowed.

### Fix
Add explicit `meta` field to `IRouteConfig`.

### Files
| File | Action |
|------|--------|
| `core/src/plugins/types.ts` | **MODIFY** — add `meta?: Record<string, unknown>` to `IRouteConfig` |

### Change
```typescript
export interface IRouteConfig {
  path: string;
  name: string;
  component: () => Promise<{ default: unknown }>;
  meta?: Record<string, unknown>;
  [key: string]: unknown;
}
```

This fixes:
- `stripe-payment.spec.ts:39` TS2339 (`requiresAuth` not in type `{}`)

---

## Task 3: Remove Dead Code — User Views

### Root Cause
Four views have unused `router` or `t` imports — dead code from copy-paste or refactoring.

### Files & Changes
| File | Line | Fix |
|------|------|-----|
| `user/vue/src/views/AddonDetail.vue` | 180 | Remove `const { t } = useI18n()` — component uses `$t()` in template instead |
| `user/vue/src/views/AddonInfoView.vue` | 95 | Remove `const router = useRouter()` — not used |
| `user/vue/src/views/PlanDetailView.vue` | 112 | Remove `const router = useRouter()` — not used |
| `user/vue/src/views/TokenBundleDetailView.vue` | 86 | Remove `const router = useRouter()` — not used |

Also remove the corresponding `import { useRouter } from 'vue-router'` if `useRouter` is no longer used in the file (but keep `useRoute` if still used).

Fixes ESLint errors #1-4 and vue-tsc errors #5-8.

---

## Task 4: Remove Dead Code — User Tests

### Files & Changes
| File | Line | Fix |
|------|------|-----|
| `tests/.../checkout-public.spec.ts` | 66 | Replace `(fn: Function) => fn` with `(fn: (...args: unknown[]) => unknown) => fn` |
| `tests/.../checkout-public.spec.ts` | 159 | Remove `const wrapper = mountView()` or use it (if test is incomplete, add assertion) |
| `tests/.../landing1.spec.ts` | 5 | Remove unused `import type { IPlatformSDK }` |
| `tests/.../landing1.spec.ts` | 62, 69 | Add `import type { IPlugin } from '@vbwd/view-component'` (name is used but not imported) |
| `tests/.../plugin-routes.spec.ts` | 1 | Remove `beforeEach` from import |

Fixes ESLint errors #5-8 and vue-tsc errors #9-13.

---

## Task 5: Remove Dead Import — Server Plugin Config

### Files & Changes
| File | Line | Fix |
|------|------|-----|
| `user/server/services/plugin-config.ts` | 5 | Remove `PluginRegistryEntry` from import statement |

Fixes vue-tsc error #4.

---

## Task 6: Fix Admin ESLint Warnings — `any` Types in Tests

### Root Cause
Test files use `any` type for mock data, violating `@typescript-eslint/no-explicit-any`.

### Files & Changes
| File | Line | Fix |
|------|------|-----|
| `admin/vue/tests/unit/stores/invoices.spec.ts` | 162 | Replace `any` with specific type or `unknown` |
| `admin/vue/tests/unit/stores/webhooks.spec.ts` | 143 | Replace `any` with specific type or `unknown` |
| `admin/vue/tests/unit/views/user-edit-addons.spec.ts` | 61 | Replace `any` with specific type or `unknown` |

### Note on `vue/one-component-per-file` Warnings
The warnings in `route-injection.spec.ts` and `dashboard-plugins.spec.ts` are for **test stub components** defined inline (e.g., `{ template: '<div/>' }`). This is standard Vue testing practice — add `// eslint-disable-next-line vue/one-component-per-file` only for these specific test helper definitions, or configure the rule to exclude test files in `.eslintrc`.

---

## Task 7: Fix User ESLint Warnings — `any` Types in Tests

### Files & Changes
| File | Line | Fix |
|------|------|-----|
| `user/vue/tests/unit/views/addon-detail.spec.ts` | 73 | Replace `any` with proper type |
| `user/vue/tests/unit/views/addons-plan-filter.spec.ts` | 73 | Replace `any` with proper type |
| `user/vue/tests/unit/views/dashboard-addons.spec.ts` | 38 | Replace `any` with proper type |
| `user/vue/tests/unit/views/dashboard-token-history.spec.ts` | 38 | Replace `any` with proper type |
| `user/vue/src/views/AddonDetail.vue` | 187 | Replace `any` with proper type for `addonSub` ref |

---

## Task 8: Fix Core AuthGuard Test Failures

### Root Cause
The test mocks `useAuthStore` as returning:
```typescript
{
  isAuthenticated: { value: false },  // ← WRONG: Pinia getter is boolean, not Ref
  user: { value: null }
}
```

But `AuthGuard.ts` accesses `auth.isAuthenticated` directly (Pinia getter returns `boolean`). The mock object `{ value: false }` is truthy in JavaScript, so `!auth.isAuthenticated` is always `false`, inverting the guard logic.

### Fix
Change mock to match Pinia getter behavior:
```typescript
// BEFORE (broken)
mockAuthStore = {
  isAuthenticated: { value: false },
  user: { value: null },
};

// AFTER (correct)
mockAuthStore = {
  isAuthenticated: false,
  user: null,
};
```

And update test setup to set values directly:
```typescript
// BEFORE
mockAuthStore.isAuthenticated.value = true;

// AFTER
mockAuthStore.isAuthenticated = true;
```

### Files
| File | Action |
|------|--------|
| `core/tests/unit/guards/AuthGuard.spec.ts` | **MODIFY** — fix mock shape to match Pinia getter |

This fixes all 3 pre-existing AuthGuard failures.

---

## Task 9: Address TermsCheckbox v-html Warning

### Root Cause
`TermsCheckbox.vue:52` uses `v-html="renderedContent"` to render markdown content. ESLint warns about XSS risk.

### Assessment
The content comes from terms/privacy markdown files, not user input. The warning is valid but the usage is intentional for rendering rich text content.

### Fix Options (pick one)
1. **Sanitize**: Add DOMPurify to sanitize `renderedContent` before passing to `v-html`
2. **Suppress with comment**: `<!-- eslint-disable-next-line vue/no-v-html -->` — only if content is guaranteed safe
3. **Use a markdown component**: Replace `v-html` with a safe markdown renderer component

**Recommended**: Option 1 (DOMPurify) — sanitize the content. This is the proper fix, not suppression.

### Files
| File | Action |
|------|--------|
| `user/vue/src/components/checkout/TermsCheckbox.vue` | **MODIFY** — sanitize content or add DOMPurify |

---

## Task 10: Verify Admin Integration i18n Warnings

### Issue
`[intlify] Not found 'users.roles' key` appears during integration tests. The key exists in `en.json` at line 96.

### Investigation
The test setup likely loads a partial i18n mock. Check if integration test helper creates i18n with full locale messages or a subset. If subset, add the missing nested `users.roles` structure.

### Files
| File | Action |
|------|--------|
| `admin/vue/tests/integration/*.spec.ts` | **INVESTIGATE** — check i18n setup helper |
| Test helper / setup file | **MODIFY** if i18n messages are incomplete |

---

## Implementation Order & Dependencies

```
Task 1: Fix IPlugin interface (core)
Task 2: Fix IRouteConfig interface (core)
  ↓ (Tasks 1 & 2 can run in parallel — both in core/src/plugins/types.ts)
Task 3: Remove dead code — user views (no deps)
Task 4: Remove dead code — user tests (deps: Tasks 1, 2 — need correct IPlugin type)
Task 5: Remove dead import — server (no deps)
Task 6: Fix admin test warnings (no deps)
Task 7: Fix user test warnings (no deps)
  ↓ (Tasks 3-7 can run in parallel)
Task 8: Fix AuthGuard test mocks (core — no deps)
Task 9: Fix TermsCheckbox v-html (no deps)
Task 10: Investigate i18n warnings (no deps)
  ↓ (Tasks 8-10 can run in parallel)
```

---

## File Summary

| Action | File |
|--------|------|
| MODIFY | `core/src/plugins/types.ts` (add `_active`, `meta` to interfaces) |
| MODIFY | `core/tests/unit/guards/AuthGuard.spec.ts` (fix mock shape) |
| MODIFY | `user/vue/src/views/AddonDetail.vue` (remove unused `t`) |
| MODIFY | `user/vue/src/views/AddonInfoView.vue` (remove unused `router`) |
| MODIFY | `user/vue/src/views/PlanDetailView.vue` (remove unused `router`) |
| MODIFY | `user/vue/src/views/TokenBundleDetailView.vue` (remove unused `router`) |
| MODIFY | `user/vue/src/views/AddonDetail.vue` (fix `any` type) |
| MODIFY | `user/vue/src/components/checkout/TermsCheckbox.vue` (sanitize v-html) |
| MODIFY | `user/vue/tests/unit/plugins/checkout-public.spec.ts` (fix Function type, remove unused var) |
| MODIFY | `user/vue/tests/unit/plugins/landing1.spec.ts` (fix imports) |
| MODIFY | `user/vue/tests/unit/plugins/plugin-routes.spec.ts` (remove unused import) |
| MODIFY | `user/vue/tests/unit/plugins/stripe-payment.spec.ts` (types fixed by Task 1/2) |
| MODIFY | `user/vue/tests/unit/views/addon-detail.spec.ts` (fix `any`) |
| MODIFY | `user/vue/tests/unit/views/addons-plan-filter.spec.ts` (fix `any`) |
| MODIFY | `user/vue/tests/unit/views/dashboard-addons.spec.ts` (fix `any`) |
| MODIFY | `user/vue/tests/unit/views/dashboard-token-history.spec.ts` (fix `any`) |
| MODIFY | `user/server/services/plugin-config.ts` (remove unused import) |
| MODIFY | `admin/vue/tests/unit/stores/invoices.spec.ts` (fix `any`) |
| MODIFY | `admin/vue/tests/unit/stores/webhooks.spec.ts` (fix `any`) |
| MODIFY | `admin/vue/tests/unit/views/user-edit-addons.spec.ts` (fix `any`) |
| CONFIG | `admin/vue/.eslintrc.*` or test files (handle `vue/one-component-per-file` for test stubs) |
| INVESTIGATE | `admin/vue/tests/integration/` (i18n setup for `users.roles`) |

## Test Targets

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| User ESLint | 8 errors, 6 warnings | 0 errors, 0 warnings | -8 errors, -6 warnings |
| User vue-tsc | 17 errors | 0 errors | -17 errors |
| Admin ESLint | 0 errors, 7 warnings | 0 errors, 0 warnings | -7 warnings |
| Admin vue-tsc | 0 errors | 0 errors | maintained |
| User unit tests | 169 passed | 169 passed | maintained |
| Admin unit tests | 195 passed | 195 passed | maintained |
| Admin integration | 136 passed | 136 passed | maintained |
| Core tests | 297 passed, 3 failed | 300 passed, 0 failed | +3 fixed |
| **Total** | **797 passed, 3 failed** | **800 passed, 0 failed** | **all green** |

## Verification

```bash
# Run everything — all must be green
cd vbwd-frontend/user/vue && npx eslint . --ext .ts,.vue       # 0 errors, 0 warnings
cd vbwd-frontend/user/vue && npx vue-tsc --noEmit              # 0 errors
cd vbwd-frontend/admin/vue && npx eslint . --ext .ts,.vue      # 0 errors, 0 warnings
cd vbwd-frontend/admin/vue && npx vue-tsc --noEmit             # 0 errors
cd vbwd-frontend/user && npx vitest run --config vitest.config.js   # 169 passed
cd vbwd-frontend/admin/vue && npx vitest run tests/unit/       # 195 passed
cd vbwd-frontend/admin/vue && npx vitest run tests/integration/ # 136 passed
cd vbwd-frontend/core && npx vitest run                        # 300+ passed, 0 failed
```
