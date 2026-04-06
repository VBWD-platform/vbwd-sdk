# Development Process Lessons

Hard-won lessons from building the VBWD platform. Follow these to avoid repeating costly mistakes.

---

## Table of Contents

1. [Testing & Mocking](#1-testing--mocking)
2. [SQLAlchemy & Database](#2-sqlalchemy--database)
3. [Authentication & Security](#3-authentication--security)
4. [Frontend Architecture](#4-frontend-architecture)
5. [Build System & CI](#5-build-system--ci)
6. [Plugin System](#6-plugin-system)
7. [CMS & Content](#7-cms--content)
8. [Code Quality](#8-code-quality)

---

## 1. Testing & Mocking

### 1.1 Mock Security Properties Explicitly

**Never rely on MagicMock defaults for auth/security checks.**

`MagicMock()` returns a truthy `MagicMock` for any attribute access. If `@require_admin` checks `g.user.is_admin`, a MagicMock user passes the check — silently bypassing auth.

```python
# WRONG — is_admin returns a truthy MagicMock
mock_user = MagicMock()
mock_user.role = UserRole.USER
# is_admin is not set → MagicMock() → truthy → admin check passes!

# CORRECT — explicitly set the security property
mock_user = MagicMock()
mock_user.role = UserRole.USER
mock_user.is_admin = False
```

### 1.2 Dynamic Imports in Vue Break Test Timing

When using `await import(...)` in Vue `onMounted`, unit tests need:
1. `vi.mock()` for the dynamically imported module (so import resolves synchronously)
2. Multiple `await flushPromises()` + `await nextTick()` cycles

```typescript
// In test:
vi.mock('@/stores/analytics', () => ({
  useAnalyticsStore: () => ({ loading: false, fetchDashboard: vi.fn() })
}))

// After mount:
await flushPromises()
await nextTick()
await flushPromises()
```

### 1.3 Check Test Directory Before Running

Plugins without tests cause pytest exit code 4/5, failing CI.

```bash
local has_tests=false
for test_path in $PATHS; do
    if [ -d "$test_path" ] && find "$test_path" -name "*.py" \
        -not -name "__init__.py" 2>/dev/null | head -1 | grep -q .; then
        has_tests=true; break
    fi
done
[ "$has_tests" = false ] && echo "No tests found — skipping"
```

### 1.4 Vitest Path Filtering

`npx vitest run plugins/shop/tests/unit/` may fail if the `include` pattern is shallow. Use `plugins/shop/` as the filter. Include pattern must use `**`: `plugins/*/tests/**/*.spec.{js,ts}`.

---

## 2. SQLAlchemy & Database

### 2.1 Relationships Are Not Python Lists

`isinstance(user.assigned_roles, (list, tuple))` returns `False` for SQLAlchemy's `InstrumentedList`.

```python
# WRONG
if isinstance(roles, (list, tuple)):
    for role in roles: ...

# CORRECT
try:
    role_list = list(roles)
    if role_list:
        for role in role_list: ...
except Exception:
    pass  # Fallback
```

### 2.2 Table Prefix Rename Requires Global Search

When renaming table prefixes (e.g., `ecommerce_*` → `shop_*`, core tables → `vbwd_*`), search everywhere:

- [ ] Model `__tablename__` values
- [ ] `ForeignKey("old_table.id")` strings in models
- [ ] Association `Table()` name strings
- [ ] Raw SQL in integration tests
- [ ] Migration files
- [ ] Enum type names (`name="old_enumname"`)
- [ ] Integration test assertions checking table names

Use `grep -rn "old_prefix" --include="*.py"` to find every instance.

### 2.3 Alembic Multi-Branch Migration Ordering

Plugin migrations that reference core tables (`user`, `user_invoice`) may run before core migrations in multi-branch setups. Solutions:
- Remove cross-schema FK constraints from plugin CREATE TABLE migrations
- Use `depends_on` pointing to the core migration
- Or: use a single consolidated migration for fresh installs

### 2.4 Invoice Amount NOT NULL

Always initialize `amount`, `subtotal`, `total_amount` before flushing an invoice record. Flushing with NULL violates NOT NULL constraints.

```python
invoice = UserInvoice()
invoice.amount = Decimal("0")      # Set BEFORE flush
invoice.subtotal = Decimal("0")
invoice.total_amount = Decimal("0")
db.session.add(invoice)
db.session.flush()  # Now has ID, amount is valid
```

---

## 3. Authentication & Security

### 3.1 Trace New Auth Fields End-to-End

When adding fields to the user model (e.g., `permissions`), trace the full path:

```
Model.to_dict() → AuthService → UserData dataclass → Schema → API response → Frontend store
```

Missing ANY step creates silent failures (e.g., `permissions: null` in login response).

### 3.2 Persist Auth Data to localStorage

Token alone is not enough. The frontend needs roles and permissions client-side without an extra API call.

```typescript
// On login:
localStorage.setItem(`${key}_user`, JSON.stringify(user))

// On init:
const userJson = localStorage.getItem(`${key}_user`)
if (userJson) this.user = JSON.parse(userJson)

// On logout:
localStorage.removeItem(`${key}_user`)
```

### 3.3 Plugin Isolation Needs Middleware

Flask doesn't unregister blueprints at runtime. When a plugin is toggled off via admin UI, its routes still respond. Add a middleware check for plugin status, not just blueprint registration.

### 3.4 Legacy Fallback for RBAC Migration

When migrating from enum-based roles to RBAC, keep the legacy check as fallback:

```python
def has_permission(self, permission_name):
    # Try RBAC first
    roles = list(self.assigned_roles)
    if roles:
        return any(r.has_permission(permission_name) for r in roles)
    # Fallback: legacy ADMIN gets everything
    if self.role == UserRole.ADMIN:
        return True
    return False
```

---

## 4. Frontend Architecture

### 4.1 fe-core Submodule Must Be Rebuilt AND Copied

After editing `vbwd-fe-core/src/`, run:

```bash
cd vbwd-fe-core && npm run build
cp -r dist/* ../vbwd-fe-admin/vbwd-fe-core/dist/
cp -r dist/* ../vbwd-fe-user/vbwd-fe-core/dist/
```

The `make rebuild-core` target should handle this.

### 4.2 CMS Route Catch-All Order

The CMS `/:slug(.+)` catch-all route matches everything. Plugin routes registered AFTER the CMS route will never match. Core routes (registered at router creation) have priority. Plugin routes (added via `router.addRoute()`) are matched in registration order.

### 4.3 Component Rendering as CMS Widget

When a Vue component is rendered as a CMS widget via `CmsWidgetRenderer`, `$t()` may not work if the plugin's translations aren't loaded yet. Use `getCurrentInstance().proxy.$t()` for global i18n access, or `useI18n()` if the plugin `install()` has already run.

### 4.4 Pinia Store Timing

`useStore()` in `<script setup>` can fail if the component is loaded before `app.use(pinia)` completes. Solutions:
- Lazy-load stores in `onMounted` via dynamic `import()`
- Or: ensure routes are registered after Pinia initialization (core router before plugin routes)

---

## 5. Build System & CI

### 5.1 Match Formatter Config with Pre-commit

The pre-commit script may use different flags than your local formatter. Check:

```bash
# What does pre-commit use?
grep "black" bin/pre-commit-check.sh
# → "black --check --diff" (default line-length 88)

# Format with matching flags:
black tests/ vbwd/ plugins/  # No --line-length flag = default 88
```

Consider adding `pyproject.toml` with `[tool.black]` config to centralize.

### 5.2 Bash Script Editing

Always run `bash -n script.sh` after editing shell scripts. A leftover `fi` from a removed `if/else` block breaks ALL CI jobs.

### 5.3 Never Delete package-lock.json on CI

Different package versions cause type mismatches. Only delete in Docker containers that need platform-specific binaries.

### 5.4 ESLint on CI

Never scope ESLint to a subdirectory (`npx eslint "plugins/shop/"`). Always use `npm run lint` (full project).

### 5.5 Populate Scripts Must Run from Backend Directory

Makefile commands: use `cd vbwd-backend && ./plugins/shop/bin/populate-db.sh`, not `cd vbwd-backend/plugins/shop && ./bin/populate-db.sh`. The populate script needs `docker compose` which requires `docker-compose.yaml` in CWD.

### 5.6 run_populate.py Needs sys.path

Populate runner scripts need `sys.path.insert(0, ...)` before importing `vbwd`:

```python
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", ".."
)))
from vbwd.app import create_app
```

---

## 6. Plugin System

### 6.1 Core Is Agnostic, Plugins Are Gnostic

Never modify core files for plugin functionality. Plugins register with core via:
- `LineItemHandlerRegistry` for billing
- `extensionRegistry` for admin sidebar nav
- `checkoutStepRegistry` for checkout flow
- `registerCmsVueComponent` for CMS widgets
- `admin_permissions` for access control

### 6.2 Plugin Email Templates Belong to the Plugin

Each plugin owns its email templates in `docs/imports/email/` and seeds them in its `populate_db.py`. The email plugin only owns core templates (user, invoice, contact).

### 6.3 Plugin Permissions Are Dynamic

`GET /admin/access/permissions` collects from `plugin.admin_permissions` of enabled plugins only. Disabled plugin's permissions disappear from the permission matrix automatically.

### 6.4 CMS Pages for Plugin Routes

Public-facing plugin routes should render through `CmsPage.vue` (not standalone components) to get header/footer/breadcrumbs from CMS layouts. Pattern:

```typescript
sdk.addRoute({
  path: '/shop',
  component: () => import('../cms/src/views/CmsPage.vue'),
  props: { slug: 'shop' },
  meta: { cmsLayout: true },
})
```

### 6.5 Checkout Flow Is Unified

All billing plugins (shop, subscription, booking) end on the same `/checkout/confirmation` page. Never create plugin-specific success pages.

---

## 7. CMS & Content

### 7.1 Multi-Content Blocks

CMS layouts can have multiple `content` type areas. Each page stores content blocks per area in `cms_page_content_block` table. The admin editor shows one tabbed editor per content area.

### 7.2 Preview Tokens for Unpublished Pages

Unpublished CMS pages are accessible via `?preview_token=<token>`. The token is auto-generated on page creation and stored in the `preview_token` field.

### 7.3 Widget Assignments in Populate

Shop/booking/checkout layouts need header-nav, breadcrumbs, and footer-nav widgets assigned via `_assign_widget()` in `populate_db.py`. Missing assignments = pages without header/footer.

---

## 8. Code Quality

### 8.1 No Lint Suppression Without Approval

Never add `# noqa`, `# type: ignore`, or any suppression comment without asking. Fix the root cause.

### 8.2 Full Variable Names

All variables must have full, readable names. No single-letter or cryptic abbreviations (exception: loop variables in list comprehensions where context is clear, but NOT `l` which is ambiguous with `1`).

### 8.3 Alembic Migrations — Plugin Conventions

- Migration revision ID: `{plugin}_001` (e.g., `shop_001`, `discount_001`)
- Branch labels: `("{plugin}",)` (e.g., `("shop",)`)
- No core table FKs in inline CREATE TABLE — add as deferred or omit
- One consolidated migration per plugin (no incremental ALTERs pre-release)

### 8.4 Git Discipline

- Always commit to `main` in standalone repos — no temp branches
- Never work in `/tmp` — always in the SDK's plugin directories
- Never skip hooks (`--no-verify`)
- Never force push to main

---

## Sprint 15–16: Access Level Management Lessons (2026-04-06)

### 1. Permission enforcement must be on BOTH layers
- Backend: `@require_permission` on every admin route (not just `@require_admin`)
- Frontend: `meta.requiredPermission` on routes + `v-if="canManage"` on buttons
- Missing either layer is a security hole — an admin with view-only access could call destructive APIs

### 2. View vs Manage separation on edit pages
- Edit pages should require `view` permission to OPEN (user can read the full detail)
- Save/Delete buttons require `manage` — hidden in the UI, blocked by API
- This avoids creating separate "detail" and "edit" views for the same resource

### 3. ExtensionRegistry must preserve all NavItem fields
- Bug: `_insertItem()` in extensionRegistry.ts stripped `requiredPermission` when copying plugin nav items
- Fix: include all fields from the NavItem interface in the copy
- Lesson: when creating object copies, spread the full object or explicitly list all fields

### 4. User role enum vs RBAC access levels — keep them separate
- User role (SUPER_ADMIN/ADMIN/USER) determines which app the user can access
- Access levels (RBAC roles) define granular permissions within the admin panel
- Don't mix them — `is_admin` flag on RBAC roles was confusing and removed

### 5. Auth store must return structured data
- Login response should include `role` (enum string), `is_admin` (boolean), `access_levels` (objects), `permissions` (strings)
- Frontend `isAdmin` getter should check the `role` field, not look for string matches in an array
- User data must be persisted to localStorage for page-reload survival

### 6. Vite pre-bundled deps cache
- Changes to fe-core dist are NOT picked up until Vite's `.vite` cache is cleared
- Always run `rm -rf node_modules/.vite` in the Docker container after rebuilding fe-core
- Without this, the old code runs even though the dist file is updated
