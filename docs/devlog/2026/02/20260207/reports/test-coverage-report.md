# Test Coverage Report

**Date:** 2026-02-07
**Method:** Ran all test suites via `make test`, `make test-coverage`, and `pre-commit-check.sh`

---

## Results Summary

| Component | Passed | Failed | Skipped | Total | Result |
|-----------|--------|--------|---------|-------|--------|
| Backend (pytest) | 498 | 7 | 171 | 676 | ⚠️ |
| Admin FE — Unit (Vitest) | 161 | 21 | 0 | 182 | ⚠️ |
| User FE — Unit (Vitest) | 28 | 0 | 0 | 28 | ✅ |
| Core SDK — Unit (Vitest) | 251 | 3 | 1 | 255 | ⚠️ |
| **Total** | **938** | **31** | **172** | **1141** | |

**Pass rate:** 938/970 active tests = **96.8%** (excluding skipped)

---

## Backend — `vbwd-backend/`

### Test Results: 498 passed, 7 failed, 171 skipped

**Code Coverage: 63%** (6071 statements, 2261 missed)

### Failures (7) — All in `test_infrastructure.py`

All 7 failures are PostgreSQL-specific tests running against SQLite (in-memory test DB):
- `test_database_url_configuration` — expects PostgreSQL URL
- `test_database_tables_exist` — queries `information_schema.tables` (PostgreSQL only)
- `test_database_connection_pooling` — PostgreSQL pool settings
- `test_database_isolation_level` — PostgreSQL isolation level
- `test_uuid_support` — queries `information_schema.columns`
- `test_database_enums_created` — queries `pg_type` table
- `test_cross_service_communication_python_to_postgres` — `information_schema.tables`

**Root cause:** These 7 integration tests require a real PostgreSQL instance (`make test-integration`), not the SQLite test runner (`make test`). They should be skipped when running unit tests or moved to the integration test suite.

**Verdict:** All real failures are infrastructure tests that need PostgreSQL. Core application logic tests all pass.

### Coverage by Module

| Module | Coverage | Notes |
|--------|----------|-------|
| **Services** | | |
| auth_service.py | 95% | Excellent |
| user_service.py | 100% | |
| invoice_service.py | 91% | |
| tarif_plan_service.py | 93% | |
| tax_service.py | 100% | |
| currency_service.py | 78% | |
| password_reset_service.py | 98% | |
| rbac_service.py | 91% | |
| feature_guard.py | 97% | |
| email_service.py | 78% | |
| subscription_service.py | 44% | Low — upgrade/downgrade/pause paths untested |
| token_service.py | **0%** | **Zero coverage** |
| activity_logger.py | 59% | |
| **Events & Handlers** | | |
| events/domain.py | 96% | |
| events/dispatcher.py | 100% | |
| events/core/ | 85-100% | |
| handlers/payment_handlers.py | 94% | |
| handlers/subscription_handlers.py | 85% | |
| handlers/user_handlers.py | 83% | |
| handlers/checkout_handler.py | **22%** | Low — main checkout flow untested |
| handlers/payment_handler.py | **16%** | Low — token crediting logic untested |
| **Plugins** | | |
| plugins/manager.py | 100% | |
| plugins/base.py | 93% | |
| plugins/mock_payment_plugin.py | 96% | |
| **Models** | 56-100% | Most models 75-100%, some to_dict() methods uncovered |
| **Routes** | **20-44%** | Consistently low — most route logic untested |
| **Repositories** | **31-57%** | Consistently low — mostly untested |

### Coverage Gaps (Critical)

| File | Coverage | Impact |
|------|----------|--------|
| `src/services/token_service.py` | **0%** | Token balance operations completely untested |
| `src/handlers/payment_handler.py` | **16%** | Token crediting, subscription activation untested |
| `src/handlers/checkout_handler.py` | **22%** | Checkout flow untested |
| `src/routes/admin/subscriptions.py` | **20%** | Admin subscription management |
| `src/routes/subscriptions.py` | **21%** | User subscription endpoints |
| `src/routes/webhooks.py` | **22%** | Payment webhook handling |
| `src/routes/user.py` | **27%** | User endpoints |
| `src/routes/admin/invoices.py` | **28%** | Invoice management |
| `src/repositories/base.py` | **34%** | Base CRUD operations |
| `src/routes/health.py` | **0%** | Health endpoint |

---

## Admin Frontend — `admin/vue/`

### Test Results: 161 passed, 21 failed

### Unit Tests (stores): All pass

### Integration Tests: 21 failures across 9 test files

**Failing test files:**

| File | Passed | Failed | Root Cause |
|------|--------|--------|------------|
| PlanForm.spec.ts | — | 3 | Navigation after creation doesn't redirect; submit-error testid missing; loading state not applied |
| Plans.spec.ts | — | 4 | Price column shows "N/A" instead of "$29.99"; plan data format mismatch |
| Subscriptions.spec.ts | — | 2 | Data format / field naming issues |
| SubscriptionDetails.spec.ts | — | 2 | Component rendering issues |
| SubscriptionCreate.spec.ts | — | 1 | Form submission issues |
| InvoiceDetails.spec.ts | — | 2 | Invoice detail data rendering |
| UserDetails.spec.ts | — | 2 | User detail field mismatches |
| UserEdit.spec.ts | — | 3 | Edit form field population |
| Dashboard.spec.ts | — | 2 | Dashboard metric rendering |

**Common patterns:** API response format mismatches between test mocks and actual component expectations. Tests expect fields that don't exist or use different naming than the actual API response.

### Style/TypeScript: Failed

Admin ESLint and TypeScript checks also fail (run via pre-commit-check with `--admin --unit` which includes style by default).

---

## User Frontend — `user/vue/`

### Test Results: 28 passed, 0 failed ✅

| Test File | Tests | Status |
|-----------|-------|--------|
| stores/invoices.spec.ts | 6 | ✅ |
| stores/subscription.spec.ts | 7 | ✅ |
| stores/profile.spec.ts | 7 | ✅ |
| stores/plans.spec.ts | 8 | ✅ |

### Style/TypeScript: Failed

- **ESLint:** Config file not found (ESLint runs from wrong directory in Docker)
- **TypeScript:** 10 errors:
  - `BillingAddressBlock.vue:155` — emit type mismatch
  - `UserLayout.vue:112` — unused `Ref`, `ComputedRef` imports
  - `Checkout.vue:245` — unused `userId` variable
  - `Checkout.vue:330` — unused `getTokenAmount` function
  - `Subscription.vue:32-33` — `description` property doesn't exist on subscription type
  - `subscription.spec.ts:102,106,134` — spread type errors

---

## Core SDK — `core/`

### Test Results: 251 passed, 3 failed, 1 skipped

### Failures (3) — All in `AuthGuard.spec.ts`

| Test | Issue |
|------|-------|
| redirects unauthenticated to login | `mockNext` called with `[]` instead of `{name: 'auth-login', query: {redirect: '/dashboard'}}` |
| passes redirect query param | Same argument mismatch |
| uses custom login route name | Same pattern |

**Root cause:** AuthGuard implementation calls `next()` with no arguments instead of the expected redirect object. Either the guard implementation changed or the tests are stale.

### Passing areas:
- PluginRegistry (registration, validation) ✅
- Plugin Lifecycle (hooks, status transitions) ✅
- Plugin Dependencies (topological sort, circular detection) ✅
- API Client (requests, interceptors, errors) ✅
- EventBus ✅
- Components (UI, forms, access control) ✅
- Cart store ✅
- RoleGuard ✅
- SDK Integration ✅

---

## Cross-Component Analysis

### Test Distribution

| Component | Unit | Integration | E2E | Total Tests |
|-----------|------|-------------|-----|-------------|
| Backend | ~430 | ~70 | — | ~500 (+171 skipped) |
| Admin FE | ~70 | ~112 | 34 specs | ~216 |
| User FE | 28 | 0 | 18 specs | ~46 |
| Core SDK | ~240 | ~15 | — | ~255 |
| **Total** | **~768** | **~197** | **52 specs** | **~1017** |

### Health by Category

| Category | Status | Details |
|----------|--------|---------|
| Backend unit tests | ✅ Healthy | All pass |
| Backend integration (SQLite) | ⚠️ 7 failures | PostgreSQL-specific tests on SQLite |
| Backend coverage | ⚠️ 63% | Routes/repos low; token_service 0% |
| Admin unit tests | ✅ Healthy | Store tests pass |
| Admin integration tests | ⚠️ 21 failures | API mock format mismatches |
| User unit tests | ✅ Healthy | All 28 pass |
| User TypeScript | ⚠️ 10 errors | Unused vars, type mismatches |
| Core SDK | ⚠️ 3 failures | AuthGuard redirect logic |

### Key Concerns

1. **Backend token_service.py has 0% coverage** — This is the service responsible for token balance operations, directly related to the token crediting bug found earlier today
2. **Backend payment_handler.py at 16%** — The handler that credits tokens when invoices are paid is barely tested
3. **Backend routes average ~30% coverage** — Most API endpoints lack direct test coverage
4. **Admin integration tests have 21 failures** — API response format drift between tests and implementation
5. **Core AuthGuard has broken redirect logic** — 3 test failures indicate the guard doesn't redirect properly

---

## Recommendations

### Immediate (to stabilize green builds)

1. **Mark 7 infra tests as `@pytest.mark.integration`** — or add `skipIf(not postgres)` so they don't fail on SQLite runs
2. **Fix admin integration test mocks** — Update mock API responses to match current API format (price field, status field naming)
3. **Fix Core AuthGuard** — Update redirect logic to pass route name + query params to `next()`
4. **Fix User TypeScript errors** — Remove unused imports/vars, fix BillingAddressBlock emit type

### Coverage Priority

5. **Add token_service.py tests** — 0% → target 80%. Critical for token balance reliability
6. **Add payment_handler.py tests** — 16% → target 80%. Token crediting, subscription activation
7. **Add checkout_handler.py tests** — 22% → target 80%. Checkout flow creating invoices + line items
8. **Add route-level tests for critical paths** — `/user/checkout`, `/admin/invoices/mark-paid`, `/webhooks/payment`
