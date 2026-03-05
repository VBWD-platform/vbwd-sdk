# Model-Table Consistency Requirements

**Requirement:** All models should have migrations and tables, and tests should verify this consistency.

**Status:** ✅ Planned for Sprint

---

## Requirement Breakdown

### 1. All Models Must Have Database Tables

**Current State:**
- ✅ 20 models have corresponding tables
- ❌ 4 models missing tables
  - AddOnSubscription
  - FeatureUsage
  - PasswordResetToken
  - Role/Permission (4 tables)
  - UserTokenBalance (2 tables)

**Sprint Action:**
- Create 5 migrations that generate 9 tables
- All models will then have tables
- Migration files: `alembic/versions/20260215_*.py`

---

### 2. All Models Must Have Migrations

**Current State:**
- ✅ 20 existing tables have migrations
- ❌ 9 missing tables have no migrations

**Sprint Action:**
- Create comprehensive migrations for each missing model
- Follow Alembic best practices
- Include both `upgrade()` and `downgrade()` functions
- Enable full rollback capability

---

### 3. Tests Must Verify Model-Table Consistency

**Current State:**
- ❌ No automated consistency checks
- Tests can pass even with missing tables
- Schema drift not detected

**Sprint Action - Create `tests/integration/test_model_table_consistency.py`**

```python
# Test 1: All models have tables
def test_all_models_have_tables():
    """Verify every model has a corresponding database table."""
    models = get_all_models()
    tables = get_all_tables()
    for model in models:
        assert model.__tablename__ in tables, f"Model {model.__name__} missing table"

# Test 2: All model columns exist in database
def test_model_columns_exist():
    """Verify every model column exists in the database."""
    for model in get_all_models():
        for column in get_model_columns(model):
            assert column_exists(model.__tablename__, column), \
                f"Column {column} missing from {model.__tablename__}"

# Test 3: Enum types match between Python and PostgreSQL
def test_enum_types_match():
    """Verify Python enums match PostgreSQL enum types."""
    for model in get_all_models():
        for column in get_enum_columns(model):
            db_enum = get_db_enum(model.__tablename__, column)
            py_enum = get_model_enum(model, column)
            assert db_enum values == py_enum values

# Test 4: Foreign keys exist
def test_foreign_keys_exist():
    """Verify all model foreign keys are enforced in database."""
    for model in get_all_models():
        for fk in get_foreign_keys(model):
            assert fk_exists_in_db(model.__tablename__, fk)

# Test 5: Indexes are created
def test_indexes_created():
    """Verify all indexed columns have database indexes."""
    for model in get_all_models():
        for column in get_indexed_columns(model):
            assert index_exists(model.__tablename__, column)

# Test 6: Unique constraints enforced
def test_unique_constraints():
    """Verify unique constraints are enforced in database."""
    for model in get_all_models():
        for constraint in get_unique_constraints(model):
            assert constraint_exists_in_db(model.__tablename__, constraint)
```

---

## Why This Matters

### Problem: Schema Drift

Without consistency tests, you can have:
- ✅ Code that compiles
- ✅ Unit tests that pass
- ✅ Integration tests that pass
- ❌ Missing database tables
- ❌ Runtime failures in production

**Example from audit:**
- Password reset endpoints exist ✅
- Password reset service works ✅
- Password reset repository works ✅
- But `password_reset_token` table doesn't exist ❌
- Calling endpoint would fail with: "no such table: password_reset_token"

### Solution: Automated Consistency Tests

These tests run as part of `pre-commit-check.sh`:
- Prevent missing tables from being committed
- Catch schema drift immediately
- Fail CI/CD if consistency broken
- Enforce: "All models must have tables"

---

## Implementation in Sprint

### Phase 1: Create Tests (First)

**File:** `tests/integration/test_model_table_consistency.py`

**Run tests:**
```bash
# Tests should initially FAIL (catch missing tables)
pytest tests/integration/test_model_table_consistency.py -v

# Expected: 6 FAILED (one for each missing model)
# FAILED test_all_models_have_tables[AddOnSubscription]
# FAILED test_all_models_have_tables[FeatureUsage]
# FAILED test_all_models_have_tables[PasswordResetToken]
# FAILED test_all_models_have_tables[Role]
# FAILED test_all_models_have_tables[Permission]
# FAILED test_all_models_have_tables[UserTokenBalance]
```

### Phase 2: Create Migrations (Make Tests Pass)

Create migrations that add missing tables

**Run tests again:**
```bash
pytest tests/integration/test_model_table_consistency.py -v

# Expected: 6 PASSED
# All model-table consistency tests pass
```

### Phase 3: Integration into Pre-Commit

Update `bin/pre-commit-check.sh` to include consistency tests:

```bash
# PART C: Integration Tests
run_integration_tests() {
    echo -e "${YELLOW}Running integration tests including consistency checks...${NC}"

    if $IN_DOCKER; then
        pytest tests/integration/ -q --tb=line 2>&1 || failed=1
    else
        docker-compose run --rm test pytest tests/integration/ -q --tb=line 2>&1 || failed=1
    fi
}
```

**Result:**
```bash
./bin/pre-commit-check.sh --full

Part A: Static Analysis     ✅ PASS
Part B: Unit Tests         ✅ PASS (661 + any new ones)
Part C: Integration Tests  ✅ PASS (14 + 6 consistency tests)

SUCCESS: All checks passed!
```

---

## Ensuring Consistency Going Forward

### Rule 1: New Models Must Have Tests

When adding a new model:
1. Create the Python model class
2. Add consistency tests
3. Create migration
4. Verify tests pass

### Rule 2: Failing Tests Block Commits

Before committing:
```bash
./bin/pre-commit-check.sh --full
```

If any consistency test fails:
- ❌ Cannot commit
- ❌ Cannot push
- ✅ Must fix (create migration)

### Rule 3: Pre-Commit Hooks (Optional Enhancement)

Add git hook that prevents commits with missing tables:
```bash
.git/hooks/pre-commit
```

---

## Test Validation Checklist

### ✅ Tests Verify Models Have Tables
```python
def test_all_models_have_tables():
    for model in all_models:
        assert has_table(model)  # Fails if table missing
```

### ✅ Tests Verify Columns Exist
```python
def test_all_columns_exist():
    for model in all_models:
        for column in model.columns:
            assert column_in_database(model, column)  # Catches schema drift
```

### ✅ Tests Verify Enum Types Match
```python
def test_enum_types_match():
    for model in all_models:
        for enum_column in model.enums:
            assert python_enum == db_enum  # Prevents enum mismatches
```

### ✅ Tests Verify Foreign Keys
```python
def test_foreign_keys_exist():
    for model in all_models:
        for fk in model.foreign_keys:
            assert fk_enforced_in_db(model, fk)  # Ensures referential integrity
```

### ✅ Tests Verify Indexes
```python
def test_indexes_exist():
    for model in all_models:
        for indexed_col in model.indexes:
            assert index_in_db(model, indexed_col)  # Ensures performance
```

### ✅ Tests Verify Constraints
```python
def test_unique_constraints_exist():
    for model in all_models:
        for constraint in model.constraints:
            assert constraint_in_db(model, constraint)  # Prevents duplicates
```

---

## Success Criteria

### All Models Have Tables
```sql
SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public';
-- Result: 29 (20 existing + 9 new)
```

### All Models Have Migrations
```bash
ls alembic/versions/ | grep 20260215
-- Result: 5 new migrations
```

### All Tests Pass
```bash
pytest tests/integration/test_model_table_consistency.py -v
-- Result: 6 passed
```

### Pre-Commit Passes
```bash
./bin/pre-commit-check.sh --full
-- Result: SUCCESS - All checks passed!
```

---

## Examples: What Tests Catch

### Example 1: Missing Table
```python
# Model defined but table missing
class AddOnSubscription(db.Model):
    __tablename__ = "addon_subscription"
    ...

# Test fails:
FAILED test_all_models_have_tables[AddOnSubscription]
AssertionError: Model AddOnSubscription missing table addon_subscription

# Fix: Create migration to add table
```

### Example 2: Missing Column
```python
# Model has column
class User(db.Model):
    stripe_customer_id = db.Column(db.String(255))

# But migration doesn't exist yet
# Test fails:
FAILED test_model_columns_exist[User.stripe_customer_id]
AssertionError: Column stripe_customer_id missing from user table

# Fix: Create migration to add column
```

### Example 3: Enum Type Mismatch
```python
# Python enum
class UserStatus(enum.Enum):
    PENDING = "pending"  # lowercase

# But database has
CREATE TYPE userstatus AS ENUM ('PENDING', 'ACTIVE');  -- uppercase!

# Test fails:
FAILED test_enum_types_match[User.status]
AssertionError: Python enum values != database enum values

# Fix: Recreate enum with correct values
```

### Example 4: Missing Foreign Key
```python
# Model has FK
class Subscription(db.Model):
    user_id = db.Column(UUID, db.ForeignKey("user.id"))

# But migration doesn't create constraint
# Test fails:
FAILED test_foreign_keys_exist[Subscription.user_id]
AssertionError: Foreign key constraint missing in database

# Fix: Add constraint in migration
```

---

## Summary

| Aspect | Requirement | Sprint Action |
|--------|-----------|--------------|
| **Models** | All must be defined | ✅ Already done (24 models) |
| **Tables** | All must exist in DB | 🔄 Create 9 missing tables |
| **Migrations** | All must exist | 🔄 Create 5 new migrations |
| **Tests** | Verify consistency | 🔄 Create test_model_table_consistency.py |
| **Pre-Commit** | All checks pass | 🔄 Update to include consistency tests |
| **Documentation** | Clear requirements | 🔄 This document |

---

## Files to Create

```
tests/integration/test_model_table_consistency.py
├── test_all_models_have_tables()
├── test_model_columns_exist()
├── test_enum_types_match()
├── test_foreign_keys_exist()
├── test_indexes_created()
└── test_unique_constraints_enforced()

alembic/versions/20260215_create_role_permission_tables.py
alembic/versions/20260215_create_token_balance_tables.py
alembic/versions/20260215_create_password_reset_token_table.py
alembic/versions/20260215_create_feature_usage_table.py
alembic/versions/20260215_create_addon_subscription_table.py
```

---

**Requirement:** ✅ Planned for sprint
**Expected Completion:** After Phase 4 of sprint
**Verification:** All tests pass + pre-commit-check.sh --full succeeds
