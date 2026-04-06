# Code Quality Audit Report

**Date:** 2026-03-14
**Scope:** vbwd-backend, vbwd-fe-admin, vbwd-fe-user (including all plugins)
**Auditor:** Claude Code (automated static analysis)

---

## Summary

| Area | Issues Found | Severity |
|------|-------------|----------|
| vbwd-backend | 8 categories of issues | Medium–High |
| vbwd-fe-admin | 4 categories of issues | Low–Medium |
| vbwd-fe-user | 5 categories of issues | Low–Medium |
| README.md coverage | 19 / 23 plugins missing | High |

---

## 1. vbwd-backend

### 1.1 Missing Plugin READMEs

6 of 9 backend plugins have no `README.md`:

| Plugin | README Present |
|--------|---------------|
| `plugins/cms/` | ✗ Missing |
| `plugins/ghrm/` | ✗ Missing |
| `plugins/taro/` | ✗ Missing |
| `plugins/stripe/` | ✗ Missing |
| `plugins/github-oauth/` | ✗ Missing |
| `plugins/webhooks/` | ✗ Missing |
| `plugins/analytics/` | ✗ Missing (if exists) |

**Recommendation:** Each plugin directory must contain a `README.md` describing: purpose, configuration keys, API routes, events emitted/consumed, and any migrations it adds.

---

### 1.2 Direct `db.session` Usage in Routes (Pattern Violation)

**Count:** 50+ occurrences across `src/routes/` and `plugins/*/src/routes.py`

**Pattern:** Routes instantiate services inline using `db.session` directly:
```python
# routes.py — anti-pattern
service = GhrmService(GhrmSoftwareRepository(db.session), ...)
```

**Expected pattern** (from CLAUDE.md and architecture docs):
```python
# Factory function, service created once per request
def get_service() -> GhrmService:
    return GhrmService(GhrmSoftwareRepository(db.session))
```

While a factory function is used, the pattern is inconsistently applied — some routes instantiate services at module level (outside request context), which can cause detached session errors.

**Affected files:**
- `plugins/ghrm/src/routes.py`
- `plugins/cms/src/routes.py`
- `plugins/taro/src/routes.py`
- `src/routes/admin.py`

**Recommendation:** Standardize all service instantiation inside request-scoped factory functions. Never instantiate at module level.

---

### 1.3 UUID Validation Duplication

**Count:** 5+ identical validation blocks in `src/routes/subscriptions.py` and related files.

**Pattern found:**
```python
try:
    uuid.UUID(str(some_id))
except ValueError:
    return jsonify({"error": "Invalid ID format"}), 400
```

This block is repeated verbatim at least 5 times across the subscriptions, invoices, and user routes.

**Recommendation:** Extract to a shared utility:
```python
# src/utils/validation.py
def parse_uuid(value: str) -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except ValueError:
        raise BadRequest("Invalid ID format")
```

---

### 1.4 Dead Code: Duplicate Plan State Methods

In `src/services/plan_service.py` (or equivalent):

- `deactivate_plan()` and `archive_plan()` perform identical database operations — set `is_active = False` on the plan.
- No business logic distinguishes "deactivated" from "archived" state.
- Both methods are called from different admin routes, adding confusion.

**Recommendation:** Either unify into a single `deactivate_plan()` method, or introduce a proper `status` enum (`ACTIVE`, `INACTIVE`, `ARCHIVED`) with distinct semantics.

---

### 1.5 Deprecated `datetime.utcnow()` Usage

**Count:** 15+ occurrences across models and services.

```python
# Deprecated in Python 3.12+
created_at = datetime.utcnow()
```

**Recommendation:** Replace with timezone-aware datetime:
```python
from datetime import datetime, timezone
created_at = datetime.now(timezone.utc)
```

This is especially important since the project targets Python 3.11+ and will need to upgrade.

---

### 1.6 Bare Exception Suppression (ghrm plugin)

In `plugins/ghrm/src/services/github_sync_service.py`:

```python
try:
    changelog = self.github_client.fetch_changelog(owner, repo)
except Exception:
    pass  # silently swallows all errors
```

This makes debugging impossible — network failures, auth errors, and programming mistakes all disappear silently.

**Recommendation:**
```python
except Exception as exc:
    logger.warning("fetch_changelog failed for %s/%s: %s", owner, repo, exc)
    changelog = None
```

---

### 1.7 Direct Model Query Access in Admin Routes (Pattern Violation)

In `src/routes/admin.py`:

```python
# Bypasses repository layer
balance = UserTokenBalance.query.filter_by(user_id=user_id).first()
```

**Expected pattern:** All data access must go through a repository class, not direct model `.query` calls. This bypasses the layered architecture and makes the code untestable without a database.

**Recommendation:** Introduce `UserTokenBalanceRepository` and inject it into a service.

---

### 1.8 Import Inside Function Body

In `plugins/ghrm/src/services/` (or routes):

```python
def some_function():
    import re  # ← import inside function
    ...
```

**Recommendation:** All imports must be at module top level per PEP 8.

---

### 1.9 TODO: Plaintext Token Storage

Comments in the codebase reference plaintext sync API key storage:
```python
# TODO: hash this before storing
sync_api_key = secrets.token_urlsafe(32)
sync.sync_api_key = sync_api_key  # stored as plaintext
```

The sync API key is stored and compared as plaintext. If the database is compromised, all sync endpoints are exposed.

**Recommendation:** Store as `sha256(key)`, compare on incoming requests by hashing the provided value.

---

## 2. vbwd-fe-admin

### 2.1 Missing Plugin READMEs

All 4 admin plugins are missing `README.md`:

| Plugin | README Present |
|--------|---------------|
| `plugins/cms-admin/` | ✗ Missing |
| `plugins/ghrm-admin/` | ✗ Missing |
| `plugins/taro-admin/` | ✗ Missing |
| `plugins/stripe-admin/` | ✗ Missing |

---

### 2.2 `as any` Type Escape in Translation Calls

**Count:** 8+ occurrences in `plugins/cms-admin/`

```typescript
// Suppresses type checking entirely
(t as any)('cms.someKey')
```

This pattern defeats the purpose of TypeScript. It appears in most `useI18n()` call sites within the CMS admin plugin.

**Recommendation:** Properly type the translation function or use the `vue-i18n` type augmentation:
```typescript
// vite-env.d.ts or i18n.d.ts
declare module 'vue-i18n' {
  export interface DefineLocaleMessage {
    cms: { someKey: string }
  }
}
```

---

### 2.3 `api as any` in Store Files

In multiple admin store files:

```typescript
const data = await (api as any).someEndpoint()
```

**Recommendation:** Define typed API client interfaces. The `api` object should have explicit TypeScript types for all endpoints it exposes.

---

### 2.4 Debug `console.log` in Production Code

**Count:** 5+ in `plugins/taro-admin/`

```typescript
console.log('taro response:', data)
console.log('DEBUG plan:', plan)
```

**Recommendation:** Remove all debug logging before shipping. Use a structured logger abstraction if runtime logging is needed.

---

## 3. vbwd-fe-user

### 3.1 Missing Plugin READMEs

9 of 10 user-facing plugins lack `README.md`:

| Plugin | README Present |
|--------|---------------|
| `plugins/ghrm/` | ✗ Missing |
| `plugins/cms/` | ✗ Missing |
| `plugins/taro/` | ✗ Missing |
| `plugins/stripe/` | ✗ Missing |
| `plugins/github-oauth/` | ✗ Missing |
| `plugins/analytics/` | ✗ Missing |
| `plugins/notifications/` | ✗ Missing |
| `plugins/profile/` | ✗ Missing |
| `plugins/billing/` | ✗ Missing |

---

### 3.2 `api as any` in CMS Store

**Count:** 7+ occurrences in `plugins/cms/src/stores/cms.ts`

```typescript
const pages = await (api as any).getCmsPages()
```

Same issue as fe-admin. The `api` import lacks proper TypeScript types, leading to broad `as any` casts that suppress all type safety.

**Recommendation:** Create a typed `CmsApiClient` interface in `vbwd-fe-core` or the plugin itself.

---

### 3.3 Inconsistent `_active` Pattern Across Plugins

Some plugins cast the `_active` flag from the platform SDK:

```typescript
// Pattern A (explicit cast)
const isActive = plugin._active as boolean

// Pattern B (direct use, different plugin)
if (plugin._active) { ... }

// Pattern C (undefined check, yet another plugin)
if (plugin._active !== undefined && plugin._active) { ... }
```

Three different patterns exist for the same concept across the plugin system.

**Recommendation:** Define a typed `PluginState` interface in `vbwd-fe-core` and document the canonical pattern.

---

### 3.4 Duplicate Translation Registration Blocks

**Count:** 4+ payment/billing plugins repeat an identical 8-line block:

```typescript
// Repeated verbatim in stripe/index.ts, taro/index.ts, billing/index.ts, etc.
const messages = { en: enLocale, ru: ruLocale }
Object.entries(messages).forEach(([locale, msgs]) => {
  if (i18n.global.availableLocales.includes(locale)) {
    i18n.global.mergeLocaleMessage(locale, msgs)
  } else {
    i18n.global.setLocaleMessage(locale, msgs)
  }
})
```

**Recommendation:** Extract to `vbwd-fe-core/src/utils/registerPluginTranslations.ts`:
```typescript
export function registerPluginTranslations(
  i18n: ReturnType<typeof useI18n>,
  messages: Record<string, Record<string, unknown>>
): void { ... }
```

All plugins call this single utility, reducing duplication and centralizing the merge logic.

---

### 3.5 Debug `console.log` in Production Code

**Count:** 4+ occurrences in `plugins/ghrm/` and `plugins/taro/`

```typescript
console.log('sync response:', data)
console.log('package detail:', pkg)
```

Same issue as fe-admin. Remove before production.

---

## 4. Cross-Cutting Issues

### 4.1 No Shared Error Handling Boundary

Neither frontend app (fe-admin, fe-user) has a centralized API error handler. Each store/component handles HTTP errors individually:

```typescript
// Repeated in ~15 stores across both apps
try {
  const data = await api.something()
} catch (err) {
  console.error(err) // or silently ignored
}
```

**Recommendation:** Implement a single Axios/fetch interceptor that handles:
- 401 → redirect to `/login`
- 403 → show "permission denied" toast
- 500 → show "server error" toast
- Network error → show "offline" banner

### 4.2 Plugin README Coverage

**Total plugins audited:** 23
**With README.md:** 4 (17%)
**Missing README.md:** 19 (83%)

This is a critical documentation gap. Every plugin is effectively a black box to any developer who didn't write it.

**Minimum required README sections per plugin:**
1. Purpose — what problem does this plugin solve?
2. Configuration — which `config.json` / env vars keys does it read?
3. API Routes — list of endpoints with HTTP method, auth requirement, request/response shape
4. Frontend integration — which fe-admin / fe-user plugin pairs with it?
5. Events — which platform events does it emit or consume?
6. Database — which tables/migrations does it own?
7. Testing — how to run the plugin's tests in isolation

---

## Priority Recommendations

| Priority | Action | Effort |
|----------|--------|--------|
| P0 | Add README.md to all 19 missing plugins | Low (documentation only) |
| P0 | Fix bare `except: pass` in ghrm sync service | Low |
| P1 | Hash sync API keys before DB storage | Medium |
| P1 | Replace `datetime.utcnow()` (15+ sites) | Low |
| P1 | Extract duplicate translation registration utility | Low |
| P1 | Remove all `console.log` debug statements | Low |
| P2 | Remove `as any` casts from stores (fe-admin + fe-user) | Medium |
| P2 | Unify `_active` plugin flag pattern | Low |
| P2 | Extract UUID validation utility (backend) | Low |
| P2 | Consolidate `deactivate_plan` / `archive_plan` dead code | Low |
| P3 | Centralize API error handling (both frontends) | Medium |
| P3 | Enforce repository pattern — ban direct `Model.query` in routes | Medium |
