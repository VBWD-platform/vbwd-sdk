# Sprint 14: Profile API 500 Error Fix

## Problem Statement

The `/api/v1/user/profile` endpoint returns HTTP 500 "Internal Server Error" when called. This blocks 3 E2E tests in the Profile Management suite.

## Root Cause Analysis

### Schema/Model Field Mismatch

The `UserDetailsSchema` defines fields that don't exist in the `UserDetails` model:

| Schema Field | Model Field | Status |
|--------------|-------------|--------|
| `address` | `address_line_1`, `address_line_2` | MISMATCH |
| `company` | - | MISSING IN MODEL |
| `vat_number` | - | MISSING IN MODEL |

When Marshmallow tries to serialize the `UserDetails` model, it fails because:
1. `address` attribute doesn't exist (model has `address_line_1`, `address_line_2`)
2. `company` attribute doesn't exist in the model
3. `vat_number` attribute doesn't exist in the model

### Files with Mismatches

**Schema** (`src/schemas/user_schemas.py`):
```python
class UserDetailsSchema(Schema):
    address = fields.Str(...)      # WRONG - doesn't exist in model
    company = fields.Str(...)      # WRONG - doesn't exist in model
    vat_number = fields.Str(...)   # WRONG - doesn't exist in model
```

**Model** (`src/models/user_details.py`):
```python
class UserDetails(BaseModel):
    address_line_1 = db.Column(db.String(255))
    address_line_2 = db.Column(db.String(255))
    # NO company column
    # NO vat_number column
```

## Database Schema

```sql
-- user_details table
Column          | Type                    | Nullable
----------------|-------------------------|----------
id              | uuid                    | NOT NULL
user_id         | uuid                    | NOT NULL
first_name      | character varying(100)  | YES
last_name       | character varying(100)  | YES
address_line_1  | character varying(255)  | YES
address_line_2  | character varying(255)  | YES
city            | character varying(100)  | YES
postal_code     | character varying(20)   | YES
country         | character varying(2)    | YES
phone           | character varying(20)   | YES
created_at      | timestamp               | NOT NULL
updated_at      | timestamp               | NOT NULL
version         | integer                 | NOT NULL
```

## Solution Options

### Option A: Update Schema to Match Model (Recommended)

Update `UserDetailsSchema` to match the actual database columns:

```python
class UserDetailsSchema(Schema):
    id = fields.UUID(dump_only=True)
    user_id = fields.UUID(dump_only=True)
    first_name = fields.Str(allow_none=True)
    last_name = fields.Str(allow_none=True)
    address_line_1 = fields.Str(allow_none=True)  # Changed from 'address'
    address_line_2 = fields.Str(allow_none=True)  # Added
    city = fields.Str(allow_none=True)
    postal_code = fields.Str(allow_none=True)
    country = fields.Str(allow_none=True)
    phone = fields.Str(allow_none=True)
    # Removed: address, company, vat_number
    created_at = fields.DateTime(dump_only=True)
    updated_at = fields.DateTime(dump_only=True)
```

**Pros:**
- Quick fix
- No database migration needed
- Matches current database schema

**Cons:**
- Loses company/vat_number fields if they were planned

### Option B: Add Missing Columns to Model

Add missing columns to the `UserDetails` model and create a migration:

```python
class UserDetails(BaseModel):
    # ... existing fields ...
    company = db.Column(db.String(255))
    vat_number = db.Column(db.String(50))
```

**Pros:**
- Schema and model stay in sync
- Preserves planned functionality

**Cons:**
- Requires database migration
- More complex change

### Option C: Virtual Fields in Schema

Use `@post_dump` to compute `address` from `address_line_1` + `address_line_2`:

```python
class UserDetailsSchema(Schema):
    address_line_1 = fields.Str(allow_none=True)
    address_line_2 = fields.Str(allow_none=True)

    @post_dump
    def compute_address(self, data, **kwargs):
        lines = [data.get('address_line_1'), data.get('address_line_2')]
        data['address'] = '\n'.join(l for l in lines if l)
        return data
```

## Recommended Fix: Option A

The simplest fix is to update the schema to match the model. This is the least disruptive change.

## Implementation Plan (TDD)

### Step 1: Write Failing Test

```python
# tests/unit/test_user_schemas.py
def test_user_details_schema_serializes_model():
    """UserDetailsSchema should serialize UserDetails model without error."""
    user_details = UserDetails(
        user_id=uuid4(),
        first_name='Test',
        last_name='User',
        address_line_1='123 Main St',
        city='New York',
        country='US'
    )

    schema = UserDetailsSchema()
    result = schema.dump(user_details)

    assert result['first_name'] == 'Test'
    assert result['address_line_1'] == '123 Main St'
```

### Step 2: Fix Schema

Update `src/schemas/user_schemas.py` to match model fields.

### Step 3: Update Update Schema

Update `UserDetailsUpdateSchema` similarly.

### Step 4: Run Tests

```bash
make test-unit
make test-e2e
```

## Files to Modify

| File | Action |
|------|--------|
| `src/schemas/user_schemas.py` | Fix field names |
| `tests/unit/test_user_schemas.py` | Add serialization tests |

## Acceptance Criteria

1. `/api/v1/user/profile` returns 200 with valid JSON
2. All 11 E2E tests pass
3. Unit tests for schema serialization pass

## Test Commands

```bash
# Test profile endpoint directly
curl -X POST http://localhost:5000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"TestPass123@"}' \
  | jq -r '.token' > /tmp/token.txt

curl http://localhost:5000/api/v1/user/profile \
  -H "Authorization: Bearer $(cat /tmp/token.txt)"

# Run E2E tests
cd vbwd-frontend && make test-e2e
```

## Related

- Sprint 13: E2E Login Redirect Fix (completed)
- E2E Tests: `profile.spec.ts`
