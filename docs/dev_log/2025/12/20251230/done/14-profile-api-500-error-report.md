# Sprint 14 Completion Report: Profile API 500 Error Fix

**Status**: COMPLETED
**Date**: 2025-12-30

---

## Executive Summary

Fixed the `/api/v1/user/profile` endpoint that was returning HTTP 500 "Internal Server Error". The root cause was twofold:
1. Schema/Model field mismatch in `UserDetailsSchema`
2. Repository argument order bug in `UserDetailsRepository`

---

## Results

### Before
| Test Suite | Passed | Failed |
|------------|--------|--------|
| Authentication | 4 | 0 |
| Profile | 0 | 3 |
| Subscription | 4 | 0 |
| **Total** | **8** | **3** |

### After
| Test Suite | Passed | Failed |
|------------|--------|--------|
| Authentication | 4 | 0 |
| Profile | 1 | 2* |
| Subscription | 4 | 0 |
| **Total** | **9** | **2** |

**Improvement: +1 test passing (82% pass rate)**

*Note: 2 remaining failures are due to rate limiting in test infrastructure, not the profile API.

---

## Root Causes Found

### Issue 1: Schema/Model Field Mismatch

`UserDetailsSchema` had fields that don't exist in `UserDetails` model:

| Schema Field | Model Field | Issue |
|--------------|-------------|-------|
| `address` | `address_line_1`, `address_line_2` | Mismatch |
| `company` | - | Missing in model |
| `vat_number` | - | Missing in model |
| `country` (max=100) | `country` (String(2)) | Length mismatch |

### Issue 2: Repository Argument Order Bug

```python
# BEFORE (WRONG):
super().__init__(UserDetails, session)

# AFTER (CORRECT):
super().__init__(session=session, model=UserDetails)
```

This caused `self._session` to be the model class instead of the SQLAlchemy session, resulting in:
```
TypeError: 'Query' object is not callable
```

---

## Solution

### 1. Fixed UserDetailsSchema

Updated to match the `UserDetails` model:

```python
class UserDetailsSchema(Schema):
    id = fields.UUID(dump_only=True)
    user_id = fields.UUID(dump_only=True)
    first_name = fields.Str(allow_none=True, validate=validate.Length(max=100))
    last_name = fields.Str(allow_none=True, validate=validate.Length(max=100))
    phone = fields.Str(allow_none=True, validate=validate.Length(max=20))
    address_line_1 = fields.Str(allow_none=True, validate=validate.Length(max=255))  # Changed
    address_line_2 = fields.Str(allow_none=True, validate=validate.Length(max=255))  # Added
    city = fields.Str(allow_none=True, validate=validate.Length(max=100))
    postal_code = fields.Str(allow_none=True, validate=validate.Length(max=20))
    country = fields.Str(allow_none=True, validate=validate.Length(max=2))  # Changed to 2
    created_at = fields.DateTime(dump_only=True)
    updated_at = fields.DateTime(dump_only=True)
    # Removed: address, company, vat_number
```

### 2. Fixed UserDetailsRepository

```python
def __init__(self, session: Session):
    super().__init__(session=session, model=UserDetails)  # Fixed argument order
```

### 3. Added Unit Tests

Created `tests/unit/schemas/test_user_schemas.py` with 8 tests for schema serialization.

---

## Files Modified

| File | Action |
|------|--------|
| `src/schemas/user_schemas.py` | Fixed field names in UserDetailsSchema and UserDetailsUpdateSchema |
| `src/repositories/user_details_repository.py` | Fixed super().__init__() argument order |
| `src/routes/user.py` | Updated docstring to reflect correct field names |
| `tests/unit/schemas/__init__.py` | Created - new test package |
| `tests/unit/schemas/test_user_schemas.py` | Created - 8 unit tests |

---

## Verification

### Profile API Response

```bash
curl http://localhost:5000/api/v1/user/profile -H "Authorization: Bearer $TOKEN"
```

**Before:**
```html
<html><head><title>Internal Server Error</title></head>...
```

**After:**
```json
{
  "details": null,
  "user": {
    "created_at": "2025-12-30T09:17:05.641869",
    "email": "test@example.com",
    "id": "bc98225d-ce41-4e37-84c8-9c8386204735",
    "role": "UserRole.USER",
    "status": "UserStatus.ACTIVE",
    "updated_at": "2025-12-30T09:17:05.641871"
  }
}
```

### Unit Tests

```bash
docker-compose --profile test run --rm test pytest tests/unit/schemas/ -v
# Result: 8 passed
```

### E2E Tests

```bash
make test-e2e
# Result: 9 passed, 2 failed (rate limit)
```

---

## Remaining Issues

2 profile tests still fail due to **rate limiting** (5 per minute on login endpoint):
- `can update profile name` - rate limit exceeded on beforeEach login
- `can change password` - rate limit exceeded on beforeEach login

This is a test infrastructure issue, not a profile API issue. Suggested fix: implement shared auth state across tests or increase rate limits for testing.

---

## Lessons Learned

1. **Always use named arguments** for `super().__init__()` to avoid argument order bugs
2. **Schema/Model alignment** - Marshmallow schemas must exactly match SQLAlchemy models
3. **Check multiple error sources** - The 500 error had two distinct causes

---

## Related

- Sprint 13: E2E Login Redirect Fix (completed)
- Sprint 15 (suggested): Test Authentication Rate Limit Fix
