# Sprint: Create Missing Database Tables & Implement Model-Table Consistency Tests

**Date:** 2026-02-15
**Duration:** TBD (based on implementation complexity)
**Priority:** 🔴 **CRITICAL** - Features depend on these tables
**Status:** Planning

---

## Sprint Goal

Create all 9 missing database tables by implementing database migrations that fully support the existing Python models, repositories, and services. Implement automated tests to prevent future model-table drift.

---

## Core Development Requirements

This sprint adheres to strict development standards:

- **TDD (Test-Driven Development):** Tests written first, implementation follows
- **SOLID Principles:** Single responsibility, Open/closed, Liskov, Interface segregation, Dependency inversion
- **Clean Code:** Self-documenting, no premature optimization, simple solutions
- **KISS (Keep It Simple, Stupid):** Minimum code, no over-engineering, direct implementations
- **No Code Interference:** Only add what's needed, don't refactor existing working code
- **Verification:** All changes verified with `./bin/pre-commit-check.sh --full`

---

## Deliverables by Priority

### Phase 1: Test Infrastructure (Foundation)

**Objective:** Create automated tests that verify model-table consistency

**Files to Create:**
```
tests/integration/test_model_table_consistency.py
```

**What to Test:**
1. ✅ Every model has a corresponding database table
2. ✅ Every model column exists in the database
3. ✅ Enum types match between Python and PostgreSQL
4. ✅ Foreign key relationships exist
5. ✅ Indexes are created correctly
6. ✅ Unique constraints are enforced

**Test Structure (TDD):**
```python
def test_all_models_have_tables()
def test_model_columns_exist_in_database()
def test_enum_types_match()
def test_foreign_keys_exist()
def test_indexes_created()
def test_unique_constraints_enforced()
```

**Acceptance Criteria:**
- Tests run with `pytest tests/integration/test_model_table_consistency.py`
- Tests pass with exit code 0
- Tests fail if any model lacks a table
- Tests fail if any column is missing
- Part of `pre-commit-check.sh --full`

---

### Phase 2: Create Missing Table Migrations

Create migrations in dependency order (respecting foreign keys):

#### 2.1 Role & Permission Tables (No external dependencies except self-references)

**Migration File:** `alembic/versions/20260215_create_role_permission_tables.py`

**Tables to Create:**
- `role` table
- `permission` table
- `role_permissions` association table
- `user_roles` association table

**Model:** `src/models/role.py` (Role, Permission)

**Acceptance Criteria:**
- ✅ Migration up/down works without errors
- ✅ Tables exist in database
- ✅ Constraints enforced (unique, indexed columns)
- ✅ Associations work (many-to-many)
- ✅ `pre-commit-check.sh` passes

---

#### 2.2 Token Balance Tables (Depends on User table)

**Migration File:** `alembic/versions/20260215_create_token_balance_tables.py`

**Tables to Create:**
- `user_token_balance` table
- `token_transaction` table

**Model:** `src/models/user_token_balance.py` (UserTokenBalance, TokenTransaction)

**Dependencies:** User table ✅ (exists)

**Acceptance Criteria:**
- ✅ Migration up/down works without errors
- ✅ Tables exist in database
- ✅ Foreign keys to User enforced
- ✅ Cascade delete works
- ✅ Enums created correctly
- ✅ `pre-commit-check.sh` passes

---

#### 2.3 Password Reset Token Table (Depends on User table)

**Migration File:** `alembic/versions/20260215_create_password_reset_token_table.py`

**Tables to Create:**
- `password_reset_token` table

**Model:** `src/models/password_reset_token.py` (PasswordResetToken)

**Dependencies:** User table ✅ (exists)

**Acceptance Criteria:**
- ✅ Migration up/down works without errors
- ✅ Table exists in database
- ✅ Token uniqueness enforced
- ✅ Cascade delete works
- ✅ Indexes created on frequently-queried columns
- ✅ `pre-commit-check.sh` passes

---

#### 2.4 Feature Usage Table (Depends on User table)

**Migration File:** `alembic/versions/20260215_create_feature_usage_table.py`

**Tables to Create:**
- `feature_usage` table

**Model:** `src/models/feature_usage.py` (FeatureUsage)

**Dependencies:** User table ✅ (exists)

**Acceptance Criteria:**
- ✅ Migration up/down works without errors
- ✅ Table exists in database
- ✅ Composite unique constraint on (user_id, feature_name, period_start)
- ✅ Indexes for query performance
- ✅ `pre-commit-check.sh` passes

---

#### 2.5 Add-On Subscription Table (Depends on User, AddOn, Subscription, UserInvoice)

**Migration File:** `alembic/versions/20260215_create_addon_subscription_table.py`

**Tables to Create:**
- `addon_subscription` table

**Model:** `src/models/addon_subscription.py` (AddOnSubscription)

**Dependencies:**
- User table ✅ (exists)
- Addon table ✅ (exists)
- Subscription table ✅ (exists)
- UserInvoice table ✅ (exists)

**Acceptance Criteria:**
- ✅ Migration up/down works without errors
- ✅ Table exists in database
- ✅ All foreign keys enforced
- ✅ Status enum created correctly
- ✅ Indexes created on foreign keys and status
- ✅ `pre-commit-check.sh` passes

---

### Phase 3: Fix Migration Blockers

**Objective:** Uncomment code in existing migrations that was blocked by missing tables

**Files to Update:**
1. `alembic/versions/20260211_add_stripe_customer_id_to_user.py` (lines 58-66)
   - Uncomment: `addon_subscription.stripe_subscription_id` addition

2. `alembic/versions/20260212_rename_provider_columns.py` (lines 48-53, 57-62)
   - Uncomment: `addon_subscription.provider_subscription_id` rename

**Implementation:**
- Simply uncomment the blocked code after `addon_subscription` table is created
- No logic changes needed

**Acceptance Criteria:**
- ✅ Code uncommented
- ✅ Migration re-runs successfully
- ✅ No duplicate columns created
- ✅ `pre-commit-check.sh` passes

---

### Phase 4: Verify End-to-End

**Objective:** Ensure all tables exist and code works

**Steps:**
1. Run `./bin/reset-database.sh` from vbwd-backend
2. Run `pytest tests/integration/test_model_table_consistency.py -v`
3. Verify all tables exist:
   ```sql
   SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
   ```
4. Test critical paths:
   - Create user with password reset token
   - Create token balance entry
   - Create feature usage entry
   - Create role/permission and assign to user
   - Create add-on subscription during checkout

**Acceptance Criteria:**
- ✅ All 9 tables exist in database
- ✅ All consistency tests pass
- ✅ `./bin/pre-commit-check.sh --full` passes (all 3 parts)
- ✅ Integration tests pass

---

## Implementation Order

Follow this sequence to respect dependencies:

1. **Create test infrastructure** → Phase 1
2. **Create role/permission tables** → Phase 2.1
3. **Create token balance tables** → Phase 2.2
4. **Create password reset token table** → Phase 2.3
5. **Create feature usage table** → Phase 2.4
6. **Create add-on subscription table** → Phase 2.5
7. **Fix migration blockers** → Phase 3
8. **Verify end-to-end** → Phase 4

---

## Testing Strategy (TDD)

### Unit Tests
- Each model's repository methods work correctly
- Each model's to_dict() method works
- Enum conversions work (Python → PostgreSQL)

### Integration Tests
- Tables created with correct schema
- Foreign keys enforced
- Cascade delete works
- Unique constraints enforced
- Model-table consistency verified

### End-to-End Tests
- Full database reset works
- All migrations apply successfully
- Critical user journeys work:
  - User password reset
  - Token balance operations
  - Feature usage tracking
  - Role-based access control
  - Add-on subscription checkout

### Validation
- `./bin/pre-commit-check.sh --full` passes all 3 parts:
  - ✅ Part A: Static Analysis (Black, Flake8, Mypy)
  - ✅ Part B: Unit Tests (661+ tests)
  - ✅ Part C: Integration Tests (14+ tests)

---

## Code Quality Standards

### No Over-Engineering
- ❌ Don't add extra features
- ❌ Don't refactor existing code
- ❌ Don't add multiple approaches
- ✅ Simple migrations following existing patterns
- ✅ Straightforward test code

### Minimum Code Interference
- Only create migration files
- Only create test files
- Only uncomment blocked code
- Don't touch working models
- Don't modify repositories or services
- Don't change routes or handlers

### SOLID in Practice
- **S**ingle Responsibility: Each migration handles one set of related tables
- **O**pen/Closed: Tests extensible for new models
- **L**iskov: All migrations follow same pattern
- **I**nterface Segregation: Tests separated by concern
- **D**ependency Inversion: Tests depend on database interface, not implementation

---

## Success Criteria

### All 9 Tables Created
- ✅ `role`
- ✅ `permission`
- ✅ `role_permissions`
- ✅ `user_roles`
- ✅ `user_token_balance`
- ✅ `token_transaction`
- ✅ `password_reset_token`
- ✅ `feature_usage`
- ✅ `addon_subscription`

### Tests Added
- ✅ `tests/integration/test_model_table_consistency.py` created
- ✅ All model-table consistency checks pass
- ✅ Tests run as part of `pre-commit-check.sh`

### Code Quality
- ✅ `./bin/pre-commit-check.sh --full` passes all 3 parts
- ✅ No warnings or errors
- ✅ No over-engineering
- ✅ No existing code modified

### Verification
- ✅ Database reset works
- ✅ All migrations apply successfully
- ✅ All tables exist with correct schema
- ✅ Foreign keys enforced
- ✅ Enums created correctly

---

## Rollback Plan

If something breaks:

1. Downgrade migrations:
   ```bash
   docker compose exec api alembic downgrade -1
   ```

2. Fix migration file

3. Re-run:
   ```bash
   docker compose exec api alembic upgrade head
   ```

4. Re-run tests

5. All changes are reversible because all migrations have `downgrade()` functions

---

## Files & Locations

### New Migrations to Create
```
alembic/versions/20260215_create_role_permission_tables.py
alembic/versions/20260215_create_token_balance_tables.py
alembic/versions/20260215_create_password_reset_token_table.py
alembic/versions/20260215_create_feature_usage_table.py
alembic/versions/20260215_create_addon_subscription_table.py
```

### New Tests to Create
```
tests/integration/test_model_table_consistency.py
```

### Migrations to Update
```
alembic/versions/20260211_add_stripe_customer_id_to_user.py
alembic/versions/20260212_rename_provider_columns.py
```

### Reference Documentation
```
docs/devlog/20260215/MODELS_AUDIT_REPORT.md (existing model analysis)
```

---

## Quick Reference: Missing Models

For detailed analysis, see: [MODELS_AUDIT_REPORT.md](./MODELS_AUDIT_REPORT.md)

| Model | Repository | Service | Routes | Table Status |
|-------|-----------|---------|--------|--------------|
| AddOnSubscription | ✅ | ❌ | ❌ | ❌ Missing |
| FeatureUsage | ✅ | ✅ | ❌ | ❌ Missing |
| PasswordResetToken | ✅ | ✅ | ✅ | ❌ Missing |
| Role/Permission | ✅ | ✅ | ⚠️ | ❌ Missing (4 tables) |
| UserTokenBalance | ✅ | ✅ | ✅ | ❌ Missing (2 tables) |

---

## Notes

- This sprint is **blocking** for production deployment
- All models must have corresponding database tables
- Tests ensure future consistency
- Following all SOLID + TDD principles
- Minimum code changes (migrations + tests only)
- Full validation with pre-commit-check.sh

---

## Next Steps After Sprint Completion

1. Update User model to support multi-role (optional enhancement)
2. Add migration tests to CI/CD pipeline
3. Document model-migration workflow for team
4. Add pre-commit hook to check for unmigrated model changes
5. Consider adding model-to-table diff report to CI

---

**Sprint Lead:** Architecture Review
**Created:** 2026-02-15
**Target Start:** Immediately (critical issues)
**Estimated Duration:** 2-3 hours for implementation and testing
