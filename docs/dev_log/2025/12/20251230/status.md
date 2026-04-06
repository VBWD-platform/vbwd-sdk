# Sprint Status - 2025-12-30

This file tracks the status of all sprints in the 20251230 devlog.

## Test Summary (Dec 30)

| App | Passed | Failed | Total |
|-----|--------|--------|-------|
| User App | 28 | 0 | 28 ✅ |
| Admin App | 38 | 0 | 38 ✅ |
| Core SDK | 230 | 2 | 232 ⚠️ |
| **Total** | **296** | **2** | **298** |

*Core SDK failures are pre-existing structure tests expecting integration test directories.

## Completed Sprints

Completed sprints are moved to `/done` folder.

| Sprint | Name | Status | Completion Date |
|--------|------|--------|-----------------|
| 1.1 | Password Reset Flow (TDD) | DONE | 2025-12-29 |
| 1.2 | CSRF Protection | DONE | 2025-12-29 |
| 1.3 | Remove Hardcoded Admin Hint | DONE | 2025-12-29 |
| 2.1-2.3 | Backend Event Handlers | DONE (Already implemented) | 2025-12-29 |
| 2.4 | Frontend Event Bus | DONE | 2025-12-29 |
| **04** | **Access Control (Backend)** | **DONE** | **2025-12-29** |
| **05** | **View Core Extraction & UI Components** | **DONE** | **2025-12-29** |
| **05-01** | **Frontend Access Control** | **DONE** | **2025-12-29** |
| **09** | **Frontend Restructure** | **DONE** | **2025-12-30** |
| **06** | **User Cabinet (TDD)** | **DONE** | **2025-12-30** |
| **07** | **Admin Management (TDD - Stores)** | **DONE** | **2025-12-30** |
| **08** | **Analytics Dashboard (TDD - Store)** | **DONE** | **2025-12-30** |
| **10** | **API Alignment (Frontend URLs)** | **DONE** | **2025-12-30** |

## In Progress

| Sprint | Name | Status | Notes |
|--------|------|--------|-------|
| - | None | - | All planned sprints complete |

## Pending Sprints

| Sprint | Name | Priority | Est. Duration | Dependencies |
|--------|------|----------|---------------|--------------|
| **10-BE** | **Missing Backend Endpoints** | **HIGH** | 1-2 days | Sprint 10 ✓ |
| **11** | **Analytics Backend** | **HIGH** | 2-3 days | Sprint 10 ✓ |
| 1.4 | HttpOnly Cookie Option | LOW (Optional) | 0.5 day | - |
| 07-UI | Admin Views (Vue components) | LOW | 1-2 days | Sprint 07 ✓ |
| 08-UI | Analytics Dashboard Views | LOW | 1-2 days | Sprint 08 ✓ |

---

## Sprint 09 - Frontend Restructure (DONE - Dec 30)

**Goal:** Set up proper frontend structure before implementing User Cabinet

### Completed Tasks
1. **Package Naming Alignment** ✅
   - Updated user/admin to use `@vbwd/view-component`
   - Fixed all import statements across codebase

2. **User App Main Structure** ✅
   - Created `user/vue/src/` with TypeScript:
     - `main.ts` - Entry point
     - `App.vue` - Root component
     - `router/index.ts` - Vue Router with auth guards
     - `layouts/UserLayout.vue` - Sidebar layout
     - `views/` - Login, Dashboard, Profile, Subscription, Invoices, Plans

3. **Playwright E2E Setup** ✅
   - Created `playwright.config.ts`
   - Created e2e tests: auth.spec.ts, profile.spec.ts, subscription.spec.ts
   - Tests pass when backend is running (2/11 pass without backend)

4. **Docker Configuration** ✅
   - Updated `docker-compose.yaml` with test services
   - Added `user-test`, `admin-test`, `core-test` services

---

## Sprint 06 - User Cabinet TDD (DONE - Dec 30)

**Goal:** Implement user-facing cabinet stores with full TDD

### Completed Tasks
Created 4 Pinia stores with 28 tests:

| Store | Tests | Features |
|-------|-------|----------|
| `profile.ts` | 7 | fetch, update, changePassword, reset |
| `subscription.ts` | 7 | fetch, usage, cancel, changePlan |
| `invoices.ts` | 6 | fetch, download, error handling |
| `plans.ts` | 8 | fetch, select, subscribe, getPlanById |

### Files Created
```
vbwd-frontend/user/vue/src/stores/
├── index.ts
├── profile.ts
├── subscription.ts
├── invoices.ts
└── plans.ts

vbwd-frontend/user/vue/tests/unit/stores/
├── profile.spec.ts
├── subscription.spec.ts
├── invoices.spec.ts
└── plans.spec.ts
```

---

## Sprint 07 - Admin Management TDD (DONE - Dec 30)

**Goal:** Implement admin stores for user/plan management

### Completed Tasks
Created 3 Pinia stores with 31 tests:

| Store | Tests | Features |
|-------|-------|----------|
| `auth.js` | 7 | (pre-existing) login, logout, token management |
| `userAdmin.ts` | 11 | fetchUsers, fetchUser, update, suspend, activate, updateRoles, impersonate |
| `planAdmin.ts` | 9 | fetchPlans, create, update, archive, getSubscriberCount |

### Files Created
```
vbwd-frontend/admin/vue/src/stores/
├── index.ts
├── userAdmin.ts
├── planAdmin.ts
└── analytics.ts

vbwd-frontend/admin/vue/tests/unit/stores/
├── userAdmin.spec.ts
├── planAdmin.spec.ts
└── analytics.spec.ts
```

---

## Sprint 08 - Analytics Dashboard TDD (DONE - Dec 30)

**Goal:** Implement analytics store for admin dashboard

### Completed Tasks
Created analytics store with 11 tests:

| Store | Tests | Features |
|-------|-------|----------|
| `analytics.ts` | 11 | fetchDashboard, fetchMRR, fetchRevenue, fetchChurn, fetchUserGrowth, fetchPlanDistribution, fetchRecentActivity |

### Interfaces Created
- `MetricPoint` - date/value pair for charts
- `MetricData` - total, change_percent, data array
- `DashboardData` - MRR, revenue, churn, user_growth, conversion, ARPU
- `ActivityItem` - type, user, timestamp for activity feed

---

## Sprint 10 - API Alignment (Frontend URLs) - DONE (Dec 30)

**Goal:** Align frontend stores with existing backend API patterns

**Approach:** Frontend adapts to backend (not vice versa)

### Completed Tasks (Frontend)
1. **Environment Configuration** ✅
   - Updated `docker-compose.yaml` with `VITE_API_URL=/api/v1`

2. **URL Corrections (TDD)** ✅
   | Store | Old Path | New Path |
   |-------|----------|----------|
   | `plans.ts` | `/plans` | `/tarif-plans` |
   | `plans.ts` | `/plans/subscribe` | `/tarif-plans/subscribe` |
   | `planAdmin.ts` | `/admin/plans/*` | `/admin/tarif-plans/*` |
   | `profile.ts` | `PUT /user/profile` | `PUT /user/details` |
   | `subscription.ts` | `/user/subscription` | `/user/subscriptions/active` |
   | `subscription.ts` | `/user/subscription/cancel` | `/user/subscriptions/{id}/cancel` |
   | `subscription.ts` | `/user/subscription/change` | `/user/subscriptions/{id}/upgrade` |

3. **Tests Updated & Passing** ✅
   - All 28 user tests pass
   - All 38 admin tests pass

### Backend Endpoints Still Missing (Sprint 10-BE)
| Endpoint | Priority |
|----------|----------|
| `POST /user/change-password` | HIGH |
| `GET /user/usage` | MEDIUM |
| `GET /user/invoices/{id}/download` | MEDIUM |
| `PUT /admin/users/{id}/roles` | HIGH |
| `/admin/analytics/*` | HIGH (Sprint 11) |

---

## Sprint 11 - Analytics Backend (PENDING)

**Goal:** Implement complete analytics API for admin dashboard

### Required Endpoints
| Endpoint | Purpose |
|----------|---------|
| `GET /admin/analytics/dashboard` | MRR, revenue, churn, user_growth, conversion, ARPU |
| `GET /admin/analytics/mrr` | Monthly Recurring Revenue |
| `GET /admin/analytics/revenue` | Revenue time series |
| `GET /admin/analytics/churn` | Churn rate |
| `GET /admin/analytics/users/growth` | User growth time series |
| `GET /admin/analytics/plans/distribution` | Subscriptions per plan |
| `GET /admin/analytics/activity` | Recent activity feed |

### Required Implementation
- 11.1: Data models (MetricPoint, MetricData, DashboardData, ActivityItem)
- 11.2-11.7: Service methods for each metric
- 11.8: Dashboard aggregate endpoint
- 11.9: Analytics routes blueprint
- 11.10: Repository extensions (subscription, user, payment)
- 11.11: DI container registration

---

## Docker Commands

```bash
# Run all tests
cd vbwd-frontend
docker-compose --profile test run --rm user-test   # 28 tests
docker-compose --profile test run --rm admin-test  # 38 tests
docker-compose --profile test run --rm core-test   # 230 tests

# Development servers
docker-compose --profile dev up user-dev   # http://localhost:5173
docker-compose --profile dev up admin-dev  # http://localhost:5174

# E2E tests (requires backend running)
docker-compose --profile dev up user-dev
cd user && npx playwright test
```

---

## Implementation Notes

### Sprint 04 - Access Control (Backend)
- Created Role and Permission models with many-to-many relationships
- Created FeatureUsage model for tracking feature usage limits
- Implemented RBACService with permission checking, role assignment
- Implemented FeatureGuard service for tariff-based access control
- Created permission decorators:
  - `@require_permission(*permissions)` - Any permission required
  - `@require_all_permissions(*permissions)` - All permissions required
  - `@require_role(*roles)` - Role-based access
  - `@require_feature(feature_name)` - Feature gating
  - `@check_usage_limit(feature, amount)` - Usage limit tracking
- 28 unit tests for RBAC and FeatureGuard services

### Sprint 05 - View Core Extraction & UI Components
- Renamed package from `@vbwd/core-sdk` to `@vbwd/view-component`
- Created 16 UI components:
  - **UI:** Spinner, Button, Input, Modal, Card, Alert, Badge, Table, Pagination, Dropdown
  - **Forms:** FormField, FormGroup, FormError
  - **Layout:** Container, Row, Col
- Created CSS variables system with dark mode support
- 67 component unit tests
- Build output: index.mjs (69KB), index.cjs (71KB), style.css (28KB)

### Sprint 05-01 - Frontend Access Control
- Created auth store (`useAuthStore`) with user/token/roles management
- Created subscription store (`useSubscriptionStore`) for features/usage
- Created route guards:
  - `authGuard` / `createAuthGuard()` - Authentication + guest route protection
  - `roleGuard` / `createRoleGuard()` - Role-based route access
- Created `useFeatureAccess` composable for feature/usage checking
- Created access control components:
  - `FeatureGate.vue` - Conditional render based on feature access
  - `UsageLimit.vue` - Visual usage/limit progress bar with warning states
- 40 unit tests for guards, composables, and components

### Sprint 1.1 - Password Reset (TDD)
- Created security events (`PasswordResetRequestEvent`, `PasswordResetExecuteEvent`)
- Created PasswordResetToken model with UUID, expiration, usage tracking
- Created PasswordResetRepository with token CRUD operations
- Created PasswordResetService with pure business logic
- Created PasswordResetHandler that calls services and sends emails
- Updated auth routes to emit events (event-driven architecture)
- 23 unit tests - all passing

### Sprint 1.2 - CSRF Protection
- Added Flask-WTF==1.2.1 to requirements
- Configured CSRFProtect in extensions.py
- Exempted all API routes (they use JWT authentication)

### Sprint 1.3 - Remove Hardcoded Admin Hint
- Removed dev-mode credential hint from admin Login.vue
- Verified no other hardcoded credentials exist

### Sprint 2.1-2.3 - Backend Handlers
- User handlers already implemented (welcome email, status updates)
- Subscription handlers already implemented (activation, cancellation)
- Payment handlers already implemented (receipts, failure notifications)
- All handlers have unit tests

### Sprint 2.4 - Frontend Event Bus
- Created EventBus.ts with emit/on/off/once methods
- Created typed events in events.ts with AppEvents constants
- Created payload types for all event categories
- Comprehensive unit tests (20+ test cases)
- Exported from core SDK

---

## Architecture Corrections Made

The original sprint docs had an incorrect event flow:
- **WRONG**: `Request → Service → Event Dispatcher → Handler(s)`
- **CORRECT**: `Request → Route (emit event) → Event Dispatcher → Handler(s) → Services → DB`

All sprint documentation has been updated to reflect the correct event-driven architecture where:
1. Routes emit events (not call services directly)
2. Handlers orchestrate and call services
3. Services contain pure business logic (no event emission)

---

## Files Structure

```
docs/devlog/20251230/
├── status.md                    # This file
├── done/
│   ├── 01-security-fixes.md     # Sprint 01 (DONE)
│   ├── 02-event-system.md       # Sprint 02 (DONE)
│   ├── 04-access-control.md     # Sprint 04 (DONE)
│   ├── 05-ui-components.md      # Sprint 05 (DONE)
│   ├── 05-01-frontend-access-control.md  # Sprint 05-01 (DONE)
│   ├── 06-user-cabinet.md       # Sprint 06 (DONE - Dec 30)
│   ├── 07-admin-management.md   # Sprint 07 (DONE - Dec 30)
│   ├── 08-analytics-dashboard.md # Sprint 08 (DONE - Dec 30)
│   └── 09-frontend-restructure.md # Sprint 09 (DONE - Dec 30)
└── sprints/
    ├── sprint-plan.md                        # Master sprint plan
    ├── sprint-10-backend-frontend-alignment.md # Sprint 10 (Frontend DONE)
    └── sprint-11-analytics-backend.md        # Sprint 11 (PENDING)

vbwd-frontend/
├── core/                        # @vbwd/view-component SDK
├── user/                        # User app (28 tests)
│   ├── package.json
│   ├── tsconfig.json
│   ├── playwright.config.ts
│   └── vue/
│       ├── src/
│       │   ├── main.ts
│       │   ├── App.vue
│       │   ├── router/
│       │   ├── stores/          # profile, subscription, invoices, plans
│       │   ├── views/           # Login, Dashboard, Profile, etc.
│       │   └── layouts/
│       └── tests/
│           ├── unit/stores/     # 28 unit tests
│           └── e2e/             # Playwright tests
├── admin/vue/                   # Admin app (38 tests)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       └── stores/              # auth, userAdmin, planAdmin, analytics
└── docker-compose.yaml          # VITE_API_URL=/api/v1 configured
```
