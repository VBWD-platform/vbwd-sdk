# Sprint: Plugin Architecture Audit & Migration (Detailed Specification)

**Sprint Name**: Plugin Architecture Compliance
**Sprint Goal**: Audit all 9 plugins and migrate plugin-specific code from core to plugin directories. Core remains agnostic, plugins are self-contained.
**Duration**: Estimated 5-7 days
**Difficulty**: Medium (code review, refactoring, migration)
**Priority**: P0 - Critical for maintainability and plugin isolation

---

## Context

The audit agent completed preliminary findings identifying **2 HIGH PRIORITY items** and **3 MEDIUM items** to fix:

1. **Finding #1 (MEDIUM)** — Analytics route duplication: `/src/routes/admin/analytics.py` duplicates `/plugins/analytics/src/routes.py`
2. **Finding #2 (MEDIUM)** — Taro enums in core: `ArcanaType`, `CardOrientation`, `CardPosition`, `TaroSessionStatus` in `/src/models/enums.py` should be in `/plugins/taro/src/enums.py`
3. **Finding #6 (LOW-MEDIUM)** — SDK organization: Payment adapters are `src/sdk/` but payment-specific

All other findings indicate the architecture is well-structured. This sprint fixes the identified violations.

---

## Core Requirements (enforced across all tasks)

| Principle | How it applies in this sprint |
|-----------|-------------------------------|
| **TDD-First** | Before moving code, write failing tests that expect the NEW location. Tests pass after migration. Zero regressions on existing tests (1335 must stay passing). |
| **DRY** | Each plugin moved exactly once. No duplicate code. Shared helpers extracted to framework layer (`src/plugins/`). |
| **SOLID — SRP** | Core `/src/` has ONE job: provide abstractions. Plugins each have ONE job: implement a feature. No overlap. |
| **SOLID — OCP** | After migrations, adding a new plugin requires ZERO changes to core — plugin structure is closed for modification, open for extension. |
| **SOLID — LSP** | All payment plugins (`stripe`, `paypal`, `yookassa`) remain interchangeable with `PaymentProviderPlugin` interface. Moving code doesn't break contract. |
| **SOLID — ISP** | Core models and services offer only what plugins need. Taro enums moved → core doesn't force enum knowledge on non-taro code. |
| **SOLID — DIP** | Core depends on plugin interfaces/abstractions, never on concrete plugin implementations. Plugins depend on core abstractions, never vice-versa. |
| **Clean Code** | No magic strings. All file paths self-documenting. Imports organized by layer (core → plugin is OK; plugin → core is NOT). |
| **Type Safety** | All imports verified after moves. `from plugins.* import` statements updated throughout. Type checkers run successfully. |
| **Coverage** | All existing 632 backend tests + 709 frontend tests must pass unchanged. New tests verify migrations don't break functionality. |
| **No Backward Compatibility** | Old import paths deleted completely. Code using old paths will fail immediately, forcing fixes before deployment. No deprecation warnings or shims. |
| **Minimal Change** | Move ONLY the identified plugin-specific code. Leave framework code where it is. No refactoring side-projects. |

---

## Audit Findings Summary

### Finding #1: Analytics Route Duplication (MEDIUM RISK)

**Location**: `/vbwd-backend/src/routes/admin/analytics.py` (76 lines)

**Issue**: Analytics dashboard endpoint lives in CORE instead of plugin. Two places implement analytics:
- Core route: `/api/v1/admin/analytics/dashboard` — always available, uncontrolled
- Plugin route: `/api/v1/plugins/analytics/active-sessions` — plugin-aware, can be disabled

**Impact**: Admin dashboard couples to core, violating plugin isolation

**Migration**: Move core route to plugin, update admin to call plugin API

**Liskov Substitution**: After moving, admin code depends on "analytics API contract" (same interface) whether served from core or plugin

---

### Finding #2: Taro Enums in Core (MEDIUM RISK)

**Location**: `/vbwd-backend/src/models/enums.py` lines 88-118

**Enums to move**:
```python
class ArcanaType(enum.Enum):           # Lines 88-95
class CardOrientation(enum.Enum):      # Lines 98-102
class CardPosition(enum.Enum):         # Lines 105-110
class TaroSessionStatus(enum.Enum):    # Lines 113-118
```

**Issue**: Core defines Taro-specific enumeration types. If taro is disabled, these unused enums remain in core.

**Impact**: Core namespace polluted; implicit taro knowledge in core layer

**Migration**: Create `/plugins/taro/src/enums.py`, move 4 enums, update imports in taro models

**Liskov Substitution**: Taro models still use same enum interface after move; other plugins unchanged

---

### Finding #6: SDK Organization (LOW-MEDIUM RISK)

**Location**: `/vbwd-backend/src/sdk/`

**Files**:
- `interface.py` — `ISDKAdapter` interface (payment-specific)
- `base.py` — `BaseSDKAdapter` (payment-specific)
- `registry.py` — `SDKAdapterRegistry` (payment-specific)
- `mock_adapter.py` — test utilities

**Issue**: Named `sdk/` (generic), but only payment adapters exist. No other SDK types planned.

**Impact**: Naming misleading; future developers expect generic SDK but find payment-only

**Migration**: Rename to `/vbwd-backend/src/payment_sdk/` to indicate payment-specific purpose (optional; can defer to later sprint)

**For this sprint**: Defer — low priority, no breakage. Focus on Findings #1 and #2.

---

## Testing Approach

All existing tests MUST pass after migrations. Run via:

```bash
# 1. Backend unit tests (before and after each migration)
cd vbwd-backend && make test-unit

# 2. Backend integration tests
cd vbwd-backend && make test-integration

# 3. Frontend unit tests (to verify no frontend code affected)
cd vbwd-frontend && make test

# 4. Full pre-commit check (after all migrations)
cd vbwd-backend && make pre-commit
cd vbwd-frontend && make pre-commit
```

**Test categories for this sprint**:

| Category | Command | Baseline | Target |
|----------|---------|----------|--------|
| Backend unit | `make test-unit` | 626 | 626 (unchanged) |
| Backend integration | `make test-integration` | 6 | 6 (unchanged) |
| Frontend unit | All suites | 709 | 709 (unchanged) |
| **Total** | | **1341** | **1341** |

---

## Task 1: Backend — Create Taro Enums File

**Create** `/vbwd-backend/plugins/taro/src/enums.py`

### Purpose

Move taro-specific enums from core to plugin namespace. Taro models will import locally.

### Implementation

```python
# File: /vbwd-backend/plugins/taro/src/enums.py

import enum

class ArcanaType(enum.Enum):
    """Tarot card type: Major (0-21) or Minor (22-77) arcana."""
    MAJOR = "major"
    MINOR = "minor"

class CardOrientation(enum.Enum):
    """Card drawn upright or reversed."""
    UPRIGHT = "upright"
    REVERSED = "reversed"

class CardPosition(enum.Enum):
    """Position in a spread: past, present, or future."""
    PAST = "past"
    PRESENT = "present"
    FUTURE = "future"

class TaroSessionStatus(enum.Enum):
    """Taro reading session lifecycle."""
    ACTIVE = "active"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
```

### Files

- **NEW**: `plugins/taro/src/enums.py`

---

## Task 2: Backend — Update Taro Models to Import from Plugin

**Edit** `/vbwd-backend/plugins/taro/src/models/` imports

### Purpose

Update 3 model files to import enums from plugin location instead of core.

### Implementation

**Before (WRONG)**:
```python
# plugins/taro/src/models/arcana.py
from src.models.enums import ArcanaType  # ❌ Imports from core
```

**After (CORRECT)**:
```python
# plugins/taro/src/models/arcana.py
from plugins.taro.src.enums import ArcanaType  # ✅ Imports from plugin
```

### Affected Files

1. `plugins/taro/src/models/arcana.py` — Line 4, import `ArcanaType`
2. `plugins/taro/src/models/taro_session.py` — Line 5, import `TaroSessionStatus`
3. `plugins/taro/src/models/taro_card_draw.py` — Line 4, imports `CardOrientation`, `CardPosition`

### Files

- **EDIT**: `plugins/taro/src/models/arcana.py`
- **EDIT**: `plugins/taro/src/models/taro_session.py`
- **EDIT**: `plugins/taro/src/models/taro_card_draw.py`

---

## Task 3: Backend — Remove Taro Enums from Core

**Edit** `/vbwd-backend/src/models/enums.py`

### Purpose

Delete taro-specific enum classes from core. Core remains agnostic.

### Implementation

**Remove these lines**:

```python
# DELETE: lines 88-95
class ArcanaType(enum.Enum):
    MAJOR = "major"
    MINOR = "minor"

# DELETE: lines 98-102
class CardOrientation(enum.Enum):
    UPRIGHT = "upright"
    REVERSED = "reversed"

# DELETE: lines 105-110
class CardPosition(enum.Enum):
    PAST = "past"
    PRESENT = "present"
    FUTURE = "future"

# DELETE: lines 113-118
class TaroSessionStatus(enum.Enum):
    ACTIVE = "active"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
```

**Verify**: No other files in `/src/` reference these enums. If they do, that's a violation needing fixing.

### Files

- **EDIT**: `src/models/enums.py` (delete 4 enum classes)

---

## Task 4: Backend — Verify No Other Core Code Uses Taro Enums

**Audit** `/vbwd-backend/src/`

### Purpose

Ensure no core code directly references the taro enums we just moved.

### Implementation

Search for enum references:

```bash
cd /vbwd-backend

# Search for enum usage in core
grep -r "ArcanaType\|CardOrientation\|CardPosition\|TaroSessionStatus" src/

# Expected: 0 matches (if not, we have a violation to fix)
```

If matches found:
- If in `/src/plugins/` — that's framework code, acceptable to keep
- If in `/src/models/`, `/src/services/`, `/src/routes/` — violation, needs refactoring

### Files

- No file changes; audit only

---

## Task 5: Backend — Verify Taro Models Still Work

**Test** Taro model loading

### Purpose

Ensure models import correctly from new enum location.

### Implementation

Run in Python interpreter:

```python
# In vbwd-backend docker container
from plugins.taro.src.models.arcana import Arcana
from plugins.taro.src.models.taro_session import TaroSession
from plugins.taro.src.models.taro_card_draw import TaroCardDraw

# All should load without ImportError
print("✓ Arcana model loads")
print("✓ TaroSession model loads")
print("✓ TaroCardDraw model loads")

# Verify enums accessible from models
print(f"✓ ArcanaType: {Arcana.__dict__.get('ArcanaType', 'N/A')}")
```

### Files

- No file changes; verification only

---

## Task 6: Backend — Taro Tests Pass After Enum Migration

**Run** Taro plugin tests

### Purpose

Verify all taro functionality works with enums in new location.

### Implementation

```bash
cd /vbwd-backend

# Run taro-specific tests (unit + integration)
pytest plugins/taro/tests/ -v

# Check for any ImportError or AttributeError
# Expected: all tests pass unchanged
```

**If tests fail**:
- ImportError → import path wrong, fix in Task 2
- AttributeError → enum not available, check enum.py is complete

### Files

- No file changes; testing only

---

## Task 7: Backend — Analytics Route Migration (Core → Plugin)

**Move and Update** analytics routes

### Purpose

Move `/src/routes/admin/analytics.py` to plugin, consolidate with plugin routes.

### Implementation Strategy

**Before (WRONG)**:
- `/src/routes/admin/analytics.py` — core route at `/api/v1/admin/analytics/dashboard`
- `/plugins/analytics/src/routes.py` — plugin route at `/api/v1/plugins/analytics/active-sessions`

**After (CORRECT)**:
- `/plugins/analytics/src/routes.py` — ONLY location, includes all analytics endpoints
- Admin calls plugin API via HTTP (cross-plugin communication pattern)

### Step 1: Copy core route logic to plugin

**From** `/src/routes/admin/analytics.py`:
```python
@analytics_bp.route('/dashboard', methods=['GET'])
@require_auth
@require_admin
def get_analytics_dashboard():
    """Return analytics dashboard data."""
    # ... implementation ...
    return jsonify(dashboard_data), 200
```

**To** `/plugins/analytics/src/routes.py` (append to existing routes):
```python
@analytics_plugin_bp.route('/dashboard', methods=['GET'])
@require_auth
@require_admin
def get_analytics_dashboard():
    """Return analytics dashboard data."""
    # ... implementation (same as before) ...
    return jsonify(dashboard_data), 200
```

### Step 2: Update admin code to call plugin

**Before**:
```python
# admin/vue/src/api/analyticsApi.ts
const response = await api.get('/api/v1/admin/analytics/dashboard')
```

**After**:
```python
# admin/vue/src/api/analyticsApi.ts
// Call plugin API instead of core
const response = await api.get('/api/v1/plugins/analytics/dashboard')
```

### Step 3: Delete core route file

Remove `/src/routes/admin/analytics.py` entirely.

### Step 4: Update admin route registration

**In** `/src/routes/admin/__init__.py`:

**Before**:
```python
from .analytics import admin_analytics_bp

__all__ = ['admin_users_bp', 'admin_payments_bp', 'admin_analytics_bp']  # ❌
```

**After**:
```python
# Remove analytics import
__all__ = ['admin_users_bp', 'admin_payments_bp']  # ✅
```

**In** `/src/app.py`:

**Before**:
```python
from src.routes.admin import admin_analytics_bp
app.register_blueprint(admin_analytics_bp)
app.route('/api/v1/admin/analytics/dashboard')  # ❌ CSRF exempt
```

**After**:
```python
# Remove analytics blueprint registration (plugin now serves it)
# ✅ CSRF rules handled by plugin
```

### Files

- **EDIT**: `plugins/analytics/src/routes.py` (add dashboard endpoint)
- **EDIT**: `src/routes/admin/__init__.py` (remove analytics import)
- **EDIT**: `src/app.py` (remove analytics blueprint + CSRF rules)
- **DELETE**: `src/routes/admin/analytics.py`
- **EDIT**: `admin/vue/src/api/analyticsApi.ts` (update endpoint path)

---

## Task 8: Backend — Analytics Tests Pass After Migration

**Run** analytics plugin tests

### Purpose

Verify analytics functionality unchanged after route move.

### Implementation

```bash
cd /vbwd-backend

# Run analytics-specific tests
pytest plugins/analytics/tests/ -v

# Verify admin API still calls analytics correctly
# Expected: all tests pass, no 404s on plugin routes
```

### Files

- No file changes; testing only

---

## Task 9: Frontend — Analytics API Update

**Update** admin frontend to call plugin API

### Purpose

Point analytics dashboard to new plugin route location.

### Implementation

**File**: `vbwd-frontend/admin/vue/src/api/analyticsApi.ts`

**Before**:
```typescript
const BASE_URL = '/api/v1/admin/analytics';

export const analyticsApi = {
  async getDashboard() {
    return api.get(`${BASE_URL}/dashboard`);  // ❌ core route
  }
};
```

**After**:
```typescript
const BASE_URL = '/api/v1/plugins/analytics';  // ✅ plugin route

export const analyticsApi = {
  async getDashboard() {
    return api.get(`${BASE_URL}/dashboard`);  // ✅ plugin route
  }
};
```

**If Analytics Tab Component references the old path**, update there too:

```typescript
// admin/vue/src/views/Settings.vue
// OLD (if it exists):
// import { analyticsApi } from '@/api/analyticsApi';
// await analyticsApi.getDashboard();

// NEW:
const loadAnalytics = async () => {
  try {
    const { data } = await analyticsApi.getDashboard();  // Now calls plugin
    analyticsData.value = data;
  } catch (e) {
    analyticsError.value = e.message;
  }
};
```

### Files

- **EDIT**: `admin/vue/src/api/analyticsApi.ts`
- **EDIT**: `admin/vue/src/views/Settings.vue` (if it calls analyticsApi)
- **EDIT**: Any store that calls `analyticsApi` (search for references)

---

## Task 10: Frontend — Test Analytics in Admin After Migration

**Verify** admin analytics still works

### Purpose

Ensure admin dashboard calls plugin API correctly.

### Implementation

```bash
cd vbwd-frontend/admin/vue

# Run admin unit tests
npx vitest run

# Check for test failures related to analytics API
# Expected: all tests pass (no regressions)

# If tests mock analyticsApi, verify mock paths match new endpoint
```

### Files

- No file changes; testing only

---

## Task 11: Backend — Full Regression Test Suite

**Run** complete backend test suite

### Purpose

Ensure all migrations haven't broken anything.

### Implementation

```bash
cd vbwd-backend

# Run ALL tests
make test

# Expected output:
# ✓ 626 unit tests pass
# ✓ 6 integration tests pass
# ✓ 0 failures

# If any fail:
# - Identify which test failed
# - Check if it's related to migrations (enums, analytics)
# - Fix import or logic error
# - Rerun
```

### Files

- No file changes; testing only

---

## Task 12: Frontend — Full Regression Test Suite

**Run** complete frontend test suite

### Purpose

Ensure analytics API changes haven't broken UI tests.

### Implementation

```bash
cd vbwd-frontend

# Run ALL frontend tests
make test

# Expected: 709 unit tests pass (unchanged from baseline)
```

### Files

- No file changes; testing only

---

## Task 13: Documentation — Update Architecture Docs

**Update** architecture guidelines with migration results

### Purpose

Record what was moved and why, for future reference.

### Implementation

Create file: `/docs/devlog/20260216/reports/4-migration-results.md`

**Content**:

```markdown
# Plugin Architecture Migration Results

## Completed Migrations

### Migration 1: Taro Enums (Finding #2)

**Status**: ✅ COMPLETED

**Moved**:
- `/src/models/enums.py` lines 88-118
- Moved to: `/plugins/taro/src/enums.py`

**Enums**:
- `ArcanaType` — taro-specific
- `CardOrientation` — taro-specific
- `CardPosition` — taro-specific
- `TaroSessionStatus` — taro-specific

**Imports Updated**:
- `plugins/taro/src/models/arcana.py`
- `plugins/taro/src/models/taro_session.py`
- `plugins/taro/src/models/taro_card_draw.py`

**Tests**: ✅ All pass
**Impact**: Zero changes to non-taro code. Core now plugin-agnostic on enums.

---

### Migration 2: Analytics Routes (Finding #1)

**Status**: ✅ COMPLETED

**Moved**:
- `/src/routes/admin/analytics.py` → `/plugins/analytics/src/routes.py`

**Endpoints**:
- `/api/v1/admin/analytics/dashboard` → `/api/v1/plugins/analytics/dashboard`

**Deletions**:
- `/src/routes/admin/analytics.py` (dead code after consolidation)
- Analytics blueprint registration from `/src/app.py`

**Updated**:
- `admin/vue/src/api/analyticsApi.ts` — new endpoint paths
- `src/routes/admin/__init__.py` — removed analytics import

**Tests**: ✅ All pass
**Impact**: Admin now depends on plugin contract; core not tied to analytics.

---

## Test Results

| Category | Before | After | Status |
|----------|--------|-------|--------|
| Backend unit | 626 | 626 | ✅ Pass |
| Backend integration | 6 | 6 | ✅ Pass |
| Frontend unit | 709 | 709 | ✅ Pass |
| **Total** | **1341** | **1341** | ✅ **All Pass** |

## Core Agnosticism Verified

✅ Core `/src/models/enums.py` no longer contains taro-specific types
✅ Core `/src/routes/admin/` no longer contains analytics-specific code
✅ All plugin-specific code now in `/plugins/{name}/`
✅ Admin code calls plugin APIs (cross-plugin pattern established)

## Deferred Items

**Finding #6** (SDK organization) — LOW PRIORITY, deferred to future sprint:
- Rename `/src/sdk/` → `/src/payment_sdk/`
- Justification: low risk, no functional impact, semantic improvement only

## Architecture Enforcement Going Forward

1. **Code Review Checklist** — plugins reviewer must verify:
   - [ ] No new code in `/src/services/{plugin}_*`
   - [ ] No new code in `/src/repositories/{plugin}_*`
   - [ ] No new code in `/src/models/{plugin}*`
   - [ ] No new code in `/src/routes/{plugin}*`
   - [ ] All plugin code in `/plugins/{name}/src/`

2. **CI/CD Validation** — pre-commit hook should:
   - Grep for plugin-specific code in core (fail if found)
   - Verify all plugins have required structure (`/src`, `/tests`, `/config.json`, etc.)
   - Check that no core imports from plugins

3. **Documentation** — maintain architecture guidelines:
   - Link to `/docs/architecture_guidelines.md`
   - Add new plugins must read this first
   - Architecture reviews check these rules

---

**Migration Completed**: Feb 16, 2026
**Tested**: All 1341 tests passing
**Status**: Ready for deployment
```

### Files

- **NEW**: `docs/devlog/20260216/reports/4-migration-results.md`

---

## Task 14: Create CI/CD Validation Script

**Create** plugin structure validator

### Purpose

Prevent future plugin architecture violations in CI/CD.

### Implementation

**File**: `/vbwd-backend/bin/validate-plugin-architecture.sh`

```bash
#!/bin/bash

set -e

echo "🔍 Validating plugin architecture..."

ERRORS=0

# 1. Check: No plugin-specific code in core /src/
echo "  Checking: No plugin code in /src/services/..."
if grep -r "^class.*Service" src/services/ | grep -iE "chat_|taro_|stripe|paypal|yookassa|analytics" > /dev/null 2>&1; then
    echo "  ❌ Found plugin-specific code in /src/services/"
    ERRORS=$((ERRORS + 1))
fi

echo "  Checking: No plugin code in /src/models/..."
if grep -r "class.*Enum\|class.*Model" src/models/enums.py | grep -iE "Arcana|Card|Taro|Chat" > /dev/null 2>&1; then
    echo "  ❌ Found plugin-specific enums in /src/models/enums.py"
    ERRORS=$((ERRORS + 1))
fi

echo "  Checking: No plugin code in /src/routes/..."
if ls src/routes/admin/ | grep -iE "^(chat|taro|stripe|paypal|yookassa|analytics)" > /dev/null 2>&1; then
    echo "  ❌ Found plugin-specific routes in /src/routes/admin/"
    ERRORS=$((ERRORS + 1))
fi

# 2. Check: Each plugin has required structure
echo "  Checking: Plugin structures..."
for plugin_dir in plugins/*/; do
    plugin_name=$(basename "$plugin_dir")
    if [ ! -d "$plugin_dir/src" ]; then
        echo "  ❌ $plugin_name missing /src/ directory"
        ERRORS=$((ERRORS + 1))
    fi
    if [ ! -d "$plugin_dir/tests" ]; then
        echo "  ❌ $plugin_name missing /tests/ directory"
        ERRORS=$((ERRORS + 1))
    fi
    if [ ! -f "$plugin_dir/config.json" ]; then
        echo "  ❌ $plugin_name missing config.json"
        ERRORS=$((ERRORS + 1))
    fi
done

# 3. Check: No core imports from plugins
echo "  Checking: No circular imports (core → plugin)..."
if grep -r "from plugins\." src/ --include="*.py" > /dev/null 2>&1; then
    echo "  ❌ Found imports from plugins in /src/ (core should not import from plugins)"
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
    echo "✅ Plugin architecture validation PASSED"
    exit 0
else
    echo "❌ Plugin architecture validation FAILED ($ERRORS errors)"
    exit 1
fi
```

### Files

- **NEW**: `bin/validate-plugin-architecture.sh`

---

## Task 15: Update Pre-Commit Hook

**Add** validation to pre-commit checks

### Purpose

Run architecture validator before commits.

### Implementation

**File**: `/vbwd-backend/bin/pre-commit-check.sh`

**Add** at beginning of script:

```bash
echo "🔍 Running architecture validation..."
./bin/validate-plugin-architecture.sh
if [ $? -ne 0 ]; then
    echo "❌ Architecture validation failed. Fix violations before committing."
    exit 1
fi
echo "✅ Architecture validation passed"
```

### Files

- **EDIT**: `bin/pre-commit-check.sh`

---

## Implementation Order

```
Task 1: Create Taro Enums File
  ↓ (no deps)
Task 2: Update Taro Model Imports
Task 3: Remove Taro Enums from Core
Task 4: Verify No Other Core Uses Taro Enums
Task 5: Verify Taro Models Still Load
Task 6: Taro Tests Pass
  ↓ (Taro enums migration complete)
Task 7: Analytics Route Migration
Task 8: Analytics Tests Pass
Task 9: Frontend Analytics API Update
Task 10: Frontend Analytics Tests
  ↓ (All migrations complete)
Task 11: Backend Full Regression Tests
Task 12: Frontend Full Regression Tests
Task 13: Documentation
Task 14: CI/CD Validation Script
Task 15: Update Pre-Commit Hook
  ↓
SPRINT COMPLETE: All code migrated, tests passing, validation enabled
```

---

## File Summary

| Action | File |
|--------|------|
| NEW | `plugins/taro/src/enums.py` |
| EDIT | `plugins/taro/src/models/arcana.py` |
| EDIT | `plugins/taro/src/models/taro_session.py` |
| EDIT | `plugins/taro/src/models/taro_card_draw.py` |
| EDIT | `src/models/enums.py` (delete 4 enums) |
| EDIT | `plugins/analytics/src/routes.py` (add dashboard endpoint) |
| EDIT | `src/routes/admin/__init__.py` (remove analytics) |
| EDIT | `src/app.py` (remove analytics registration) |
| DELETE | `src/routes/admin/analytics.py` |
| EDIT | `admin/vue/src/api/analyticsApi.ts` |
| NEW | `docs/devlog/20260216/reports/4-migration-results.md` |
| NEW | `bin/validate-plugin-architecture.sh` |
| EDIT | `bin/pre-commit-check.sh` |

---

## Success Criteria

### ✅ Code Migrations Complete
- [ ] Taro enums moved from `/src/models/enums.py` to `/plugins/taro/src/enums.py`
- [ ] All taro models updated to import enums from plugin
- [ ] Core `/src/models/enums.py` no longer contains taro-specific types
- [ ] Analytics dashboard route moved from `/src/routes/admin/analytics.py` to `/plugins/analytics/src/routes.py`
- [ ] Admin frontend updated to call plugin API endpoints
- [ ] Dead code removed (old analytics route, old enums)

### ✅ Tests All Pass
- [ ] 626 backend unit tests pass
- [ ] 6 backend integration tests pass
- [ ] 709 frontend unit tests pass
- [ ] **Total: 1341 tests passing, zero regressions**

### ✅ Core Agnosticism Verified
- [ ] No plugin-specific imports in `/src/`
- [ ] No plugin-specific enums in core models
- [ ] No plugin-specific routes in core routes
- [ ] All plugin code in plugin directories
- [ ] Admin code calls plugin APIs (cross-plugin pattern)

### ✅ Enforcement Enabled
- [ ] Architecture validation script created
- [ ] Pre-commit hook includes validation
- [ ] Documentation updated with migration results
- [ ] Code review checklist added to guidelines

---

## Risk Assessment

### Finding #2 Migration (Taro Enums) — MEDIUM RISK

**Risks**:
1. Database enum constraints may be affected
2. Serialization/deserialization may break

**Mitigation**:
- Database enums remain unchanged (PostgreSQL ENUM values unchanged)
- Python enum references changed only in imports, not in usage
- Tests verify all 6 taro tests still pass

**Rollback**: Revert 3 import statements, move enums back to core

**Estimated Effort**: 2-3 hours

---

### Finding #1 Migration (Analytics Routes) — MEDIUM RISK

**Risks**:
1. Admin dashboard breaks if API path changes
2. CSRF configuration lost if not properly migrated

**Mitigation**:
- Update admin API client before deleting old route
- Test admin dashboard loads and renders analytics
- Plugin handles CSRF via shared flask-wtf

**Rollback**: Recreate `/src/routes/admin/analytics.py`, revert API paths

**Estimated Effort**: 3-4 hours

---

## Verification

### Automated

```bash
# Run complete test suite
cd vbwd-backend && make test          # 632 tests
cd vbwd-frontend && make test         # 709 tests

# Run architecture validator
cd vbwd-backend && ./bin/validate-plugin-architecture.sh

# Run pre-commit checks
cd vbwd-backend && ./bin/pre-commit-check.sh
cd vbwd-frontend && ./bin/pre-commit-check.sh
```

### Manual

1. **Admin Dashboard**
   - Navigate to Admin > Settings > Analytics tab
   - Dashboard loads without errors
   - Data displays correctly

2. **Taro Plugin**
   - Create taro session
   - Draw cards
   - Verify no enum-related errors in logs

3. **API Calls**
   - `curl -H "Authorization: Bearer <token>" http://localhost:5000/api/v1/admin/analytics/dashboard`
   - Returns 200 with analytics data (redirected to plugin)

---

## Deferred Work

**Finding #6** (SDK organization) — Optional optimization:
- Rename `/src/sdk/` → `/src/payment_sdk/`
- Justification: semantic improvement only, zero functional impact
- Priority: LOW (can be done in future sprint or as polish)

---

**Sprint Created**: February 16, 2026
**Sprint Status**: Ready to Execute
**Target Completion**: February 20-21, 2026 (5-7 days)
**Owner**: Architecture Review Team
