# Database Models & Migrations Audit Report

**Date:** 2026-02-15
**Scope:** vbwd-backend Python models, database schema, and Alembic migrations
**Status:** ⚠️ **CRITICAL ISSUES FOUND**

---

## Executive Summary

The backend has **5 models completely missing database tables** despite having full supporting infrastructure (repositories, services, handlers, routes). All 5 missing tables must be created via migrations before these features can function.

Additionally, 2 migrations have commented-out code that references these missing tables, creating technical debt.

---

## Critical Issues

### 1. Missing Database Tables (5 Models)

All the following models are fully defined with supporting code but **have no database tables**:

| Model | Purpose | Repository | Service | Routes | Status |
|-------|---------|-----------|---------|--------|--------|
| **AddOnSubscription** | Track user add-on subscriptions | ✅ Yes | ❌ No | ❌ No | **MISSING TABLE** |
| **FeatureUsage** | Track feature usage for rate limiting | ✅ Yes | ✅ Yes | ❌ No | **MISSING TABLE** |
| **PasswordResetToken** | Password reset request tokens | ✅ Yes | ✅ Yes | ✅ Yes | **MISSING TABLE** |
| **Role/Permission** | RBAC system (4 tables) | ✅ Yes | ✅ Yes | ✅ Partial | **MISSING TABLES** |
| **UserTokenBalance** | User token balance & transactions | ✅ Yes | ✅ Yes | ✅ Yes | **MISSING TABLES** |

**Total Missing Tables:** 9 tables across 5 models

---

## Detailed Findings

### 1. AddOnSubscription Model

**File:** `src/models/addon_subscription.py`
**Table Name:** `addon_subscription`
**Status:** ⚠️ Model exists, table missing

**Model Attributes:**
```python
- user_id (FK -> User, cascade delete, indexed)
- addon_id (FK -> AddOn, indexed)
- subscription_id (FK -> Subscription, nullable, indexed)
- invoice_id (FK -> UserInvoice, nullable, indexed)
- status (Enum: PENDING, ACTIVE, CANCELLED, EXPIRED, indexed)
- starts_at (DateTime, nullable)
- expires_at (DateTime, nullable, indexed)
- cancelled_at (DateTime, nullable)
- provider_subscription_id (String, nullable, indexed)
```

**Implementation Status:**
- ✅ Model: Fully defined with methods (`is_valid`, `activate()`, `cancel()`, `expire()`, `to_dict()`)
- ✅ Repository: `src/repositories/addon_subscription_repository.py` (complete CRUD operations)
- ❌ Service: No dedicated service layer
- ✅ Usage: Created in checkout handler during payment processing
- ❌ Routes: No public routes

**Where It's Used:**
- `src/handlers/checkout_handler.py` (lines 167-175) - Creates PENDING addon subscriptions
- `src/repositories/addon_subscription_repository.py` - Full repository with find/create methods

**Migration Blockers:**
- `alembic/versions/20260211_add_stripe_customer_id_to_user.py` (lines 58-66)
  - Comment: "addon_subscription table doesn't exist yet"
  - Blocked: Adding stripe_subscription_id column
- `alembic/versions/20260212_rename_provider_columns.py` (lines 48-53)
  - Comment: "addon_subscription table doesn't exist yet"
  - Blocked: Renaming provider columns

---

### 2. FeatureUsage Model

**File:** `src/models/feature_usage.py`
**Table Name:** `feature_usage`
**Status:** ⚠️ Model exists, table missing

**Model Attributes:**
```python
- user_id (FK -> User, cascade delete, indexed)
- feature_name (String, indexed)
- usage_count (Integer, default 0)
- period_start (DateTime, indexed)
- UNIQUE constraint: (user_id, feature_name, period_start)
```

**Implementation Status:**
- ✅ Model: Fully defined with methods (`increment()`, `to_dict()`)
- ✅ Repository: `src/repositories/feature_usage_repository.py`
  - Methods: `get_usage()`, `get_monthly_usage()`, `increment_usage()`, `reset_usage()`, `get_all_usage_for_user()`
- ✅ Service: `src/services/feature_guard.py` (FeatureGuard service)
  - Uses feature_usage for rate limiting and feature gating
  - Methods: `check_usage_limit()`, `get_feature_limits()`

**Where It's Used:**
- `src/services/feature_guard.py` - Feature usage tracking and limit enforcement
- Used for subscription feature limits

**Why It Matters:**
- Prevents abuse through usage-based feature limits
- Required for feature gating on subscription plans

---

### 3. PasswordResetToken Model

**File:** `src/models/password_reset_token.py`
**Table Name:** `password_reset_token`
**Status:** ⚠️ Model exists, table missing

**Model Attributes:**
```python
- user_id (FK -> User, cascade delete)
- token (String(64), unique, indexed)
- expires_at (DateTime)
- used_at (DateTime, nullable)
- Properties: is_expired, is_used, is_valid
```

**Implementation Status:**
- ✅ Model: Fully defined with properties (`is_expired`, `is_used`, `is_valid`)
- ✅ Repository: `src/repositories/password_reset_repository.py`
  - Methods: `find_by_token()`, `create_token()`, `invalidate_tokens_for_user()`, `mark_used()`, `cleanup_expired()`
- ✅ Service: `src/services/password_reset_service.py`
  - Methods: `create_reset_token()`, `reset_password()`
  - Token expiry: 1 hour
- ✅ Routes: `/api/v1/auth/` endpoints
  - `POST /forgot-password` (lines 136-180)
  - `POST /reset-password` (lines 183-225)
- ✅ Handlers: `src/handlers/password_reset_handler.py`

**Where It's Used:**
- `src/routes/auth.py` - Password reset endpoints
- `src/handlers/password_reset_handler.py` - Event-driven password reset handling
- `src/services/password_reset_service.py` - Business logic

**Critical Issue:**
Password reset endpoints are fully implemented and accessible, but will fail at runtime when the table is missing.

---

### 4. Role & Permission Models (RBAC System)

**File:** `src/models/role.py`
**Tables:** `role`, `permission`, `role_permissions`, `user_roles`
**Status:** ⚠️ Models exist, tables missing

**Role Model:**
```python
- name (String(50), unique, indexed)
- description (String(255))
- is_system (Boolean, default False - prevents deletion)
- permissions (Many-to-many via role_permissions)
- users (Many-to-many via user_roles)
```

**Permission Model:**
```python
- name (String(100), unique, indexed)
- description (String(255))
- resource (String(50), indexed)
- action (String(50))
- Format: "resource.action" (e.g., "users.view", "subscriptions.manage")
```

**Association Tables:**
- `role_permissions` (role_id <-> permission_id)
- `user_roles` (user_id <-> role_id)

**Implementation Status:**
- ✅ Models: Fully defined
- ✅ Repository: `src/repositories/role_repository.py`
  - RoleRepository: `find_by_name()`, `get_user_roles()`, `get_user_permissions()`, `assign_role()`, `revoke_role()`, `user_has_role()`
  - PermissionRepository: `find_by_name()`, `find_by_resource()`
- ✅ Service: `src/services/rbac_service.py` (RBACService)
  - Methods: `has_permission()`, `has_any_permission()`, `has_all_permissions()`, `get_user_permissions()`, `get_user_roles()`, `assign_role()`, `revoke_role()`, `has_role()`, `is_admin()`
- ⚠️ Routes: Partial implementation in `/api/v1/admin/users.py`
  - Comment (line 39): "TODO: Implement multi-role support in User model"

**Where It's Used:**
- `src/services/rbac_service.py` - Permission checking for authorization
- `src/routes/admin/users.py` - User role management (partial)

**Current Workaround:**
Users currently have a single `role` field (Enum) rather than multi-role support via the RBAC system.

---

### 5. UserTokenBalance & TokenTransaction Models

**File:** `src/models/user_token_balance.py`
**Tables:** `user_token_balance`, `token_transaction`
**Status:** ⚠️ Models exist, tables missing

**UserTokenBalance Model:**
```python
- user_id (FK -> User, cascade delete, unique, indexed)
- balance (Integer, default 0)
- One-to-one relationship with User
```

**TokenTransaction Model:**
```python
- user_id (FK -> User, cascade delete, indexed)
- amount (Integer: positive=credit, negative=debit)
- transaction_type (Enum: PURCHASE, USAGE, REFUND, BONUS, ADJUSTMENT)
- reference_id (UUID, nullable, indexed)
- description (String(255), nullable)
```

**Implementation Status:**
- ✅ Models: Fully defined
- ✅ Repository: `src/repositories/token_repository.py`
  - TokenBalanceRepository: `find_by_user_id()`, `get_or_create()`
  - TokenTransactionRepository: `find_by_user_id()`, `find_by_reference_id()`, `create()`
- ✅ Service: `src/services/token_service.py`
  - Methods: `get_balance()`, `get_balance_object()`, `credit_tokens()`, `debit_tokens()`, `complete_purchase()`, `refund_tokens()`, `get_transactions()`
- ✅ Handlers:
  - `src/handlers/payment_handler.py` - Creates balance during payment
  - `src/handlers/checkout_handler.py` - References token purchases
- ✅ Routes: `/api/v1/admin/users.py` (token balance updates)
- ✅ Services: `src/services/restore_service.py` - Creates balance/transaction

**Where It's Used:**
- Token purchase flows (token bundles)
- User balance tracking
- Audit trail via transactions
- Admin user management

---

## Database Schema Issues

### Missing vs. Existing Tables

**Existing Tables (20):**
- ✅ `alembic_version`
- ✅ `currency`
- ✅ `price`
- ✅ `tax`
- ✅ `tax_rate`
- ✅ `user_case`
- ✅ `tarif_plan`
- ✅ `token_bundle`
- ✅ `user_details`
- ✅ `payment_method`
- ✅ `payment_method_translation`
- ✅ `country`
- ✅ `plugin_config`
- ✅ `addon`
- ✅ `addon_tarif_plans` (association table)
- ✅ `user`
- ✅ `subscription`
- ✅ `user_invoice`
- ✅ `invoice_line_item`
- ✅ `token_bundle_purchase`

**Missing Tables (9):**
- ❌ `addon_subscription`
- ❌ `feature_usage`
- ❌ `password_reset_token`
- ❌ `role`
- ❌ `permission`
- ❌ `role_permissions` (association)
- ❌ `user_roles` (association)
- ❌ `user_token_balance`
- ❌ `token_transaction`

---

## Migration Issues

### Commented-Out Code (Technical Debt)

**File:** `alembic/versions/20260211_add_stripe_customer_id_to_user.py`
- **Lines 58-66:** Commented out `addon_subscription.stripe_subscription_id` addition
- **Reason:** addon_subscription table doesn't exist
- **Impact:** Cannot add provider-specific columns until table is created

**File:** `alembic/versions/20260212_rename_provider_columns.py`
- **Lines 48-53:** Commented out renaming `addon_subscription.stripe_subscription_id` to `provider_subscription_id`
- **Lines 57-62 (downgrade):** Commented out reverse operation
- **Reason:** addon_subscription table doesn't exist
- **Impact:** Incomplete provider column standardization

---

## Dead Code Analysis

### No obvious dead code found

**Summary:**
- All defined models have corresponding repositories
- All repositories are used by services or handlers
- All services are used by routes or handlers
- The code is complete - just missing database tables

---

## Recommendations

### Priority 1: Create Missing Table Migrations

Create migrations in this order (respecting foreign key dependencies):

1. **Role & Permission tables** (no FK dependencies except self-references)
   ```
   - role
   - permission
   - role_permissions (association)
   - user_roles (association)
   ```

2. **UserTokenBalance** (depends on User)
   ```
   - user_token_balance
   - token_transaction (depends on User)
   ```

3. **PasswordResetToken** (depends on User)
   ```
   - password_reset_token
   ```

4. **FeatureUsage** (depends on User)
   ```
   - feature_usage
   ```

5. **AddOnSubscription** (depends on User, AddOn, Subscription, UserInvoice)
   ```
   - addon_subscription
   ```

### Priority 2: Fix Migration Blockers

Remove commented-out code from:
- `20260211_add_stripe_customer_id_to_user.py`
- `20260212_rename_provider_columns.py`

Once `addon_subscription` table is created, uncomment these operations.

### Priority 3: Update User Model

**Current Status:** User uses single `role` enum field
**Needed:** Multi-role support via RBAC system
**Change:** User should reference `user_roles` association instead of single role field
**Note:** See TODO comment in `src/routes/admin/users.py` line 39

---

## Implementation Checklist

- [ ] Create `role` table migration
- [ ] Create `permission` table migration
- [ ] Create `role_permissions` association table migration
- [ ] Create `user_roles` association table migration
- [ ] Create `user_token_balance` table migration
- [ ] Create `token_transaction` table migration
- [ ] Create `password_reset_token` table migration
- [ ] Create `feature_usage` table migration
- [ ] Create `addon_subscription` table migration
- [ ] Uncomment `addon_subscription` columns in `20260211_add_stripe_customer_id_to_user.py`
- [ ] Uncomment `addon_subscription` columns in `20260212_rename_provider_columns.py`
- [ ] Update User model to support multi-role (optional, current single-role works)
- [ ] Run all migrations and verify
- [ ] Test all affected features end-to-end
- [ ] Run pre-commit checks
- [ ] Commit with migration summary

---

## Files Affected

### Models (9 missing table models)
- `src/models/addon_subscription.py`
- `src/models/feature_usage.py`
- `src/models/password_reset_token.py`
- `src/models/role.py`
- `src/models/user_token_balance.py`

### Repositories (matching models)
- `src/repositories/addon_subscription_repository.py`
- `src/repositories/feature_usage_repository.py`
- `src/repositories/password_reset_repository.py`
- `src/repositories/role_repository.py`
- `src/repositories/token_repository.py`

### Services (matching models)
- `src/services/feature_guard.py`
- `src/services/password_reset_service.py`
- `src/services/rbac_service.py`
- `src/services/token_service.py`

### Routes (partial implementation)
- `src/routes/auth.py` (password reset endpoints)
- `src/routes/admin/users.py` (role management - partial, token management)

### Handlers
- `src/handlers/checkout_handler.py` (addon subscriptions)
- `src/handlers/password_reset_handler.py` (password reset events)
- `src/handlers/payment_handler.py` (token balance)
- `src/services/restore_service.py` (token balance restore)

### Migrations (with blockers)
- `alembic/versions/20260211_add_stripe_customer_id_to_user.py` (commented code)
- `alembic/versions/20260212_rename_provider_columns.py` (commented code)

---

## Next Steps

This audit should be followed by:
1. Creating the 9 missing migrations
2. Testing the migrations in dev environment
3. Verifying all features work end-to-end
4. Running full test suite
5. Committing with audit findings

---

**Report Generated:** 2026-02-15 07:00 UTC
**Audit Status:** Complete
**Severity:** 🔴 **CRITICAL** - Features will fail at runtime without database tables
