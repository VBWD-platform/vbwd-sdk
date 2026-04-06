# Sprint 15 Report: E2E Test Fixes

**Status**: COMPLETED
**Date**: 2025-12-30
**Result**: 11/11 E2E tests passing

## Summary

Sprint 15 was initially scoped for frontend toast notifications, but investigation revealed the frontend already had toast functionality. The actual issues were backend bugs and test infrastructure configuration problems.

## Root Causes Identified

### 1. TestDataSeeder Password Not Reset
**File**: `vbwd-backend/src/testing/test_data_seeder.py:137-162`

The `_create_test_user()` method returned existing users without resetting their password. When the "can change password" test modified the password, subsequent test runs failed with "Invalid credentials" because the seeder didn't restore the original password.

**Fix**: Reset password when user already exists:
```python
existing = self.session.query(User).filter_by(email=email).first()
if existing:
    # Reset password to known state for test consistency
    existing.password_hash = self._hash_password(password)
    self.session.flush()
    return existing
```

### 2. Vite Proxy DNS Resolution
**File**: `vbwd-frontend/user/playwright.config.ts:25-32`

The Vite dev server proxy defaulted to `host.docker.internal:5000`, which doesn't resolve on Linux hosts (only inside Docker containers on macOS).

**Fix**: Set `VITE_BACKEND_URL` environment variable in Playwright webServer config:
```typescript
webServer: {
  command: 'npm run dev',
  url: 'http://localhost:5173',
  reuseExistingServer: !process.env.CI,
  env: {
    VITE_BACKEND_URL: 'http://localhost:5000',
  },
},
```

### 3. UserService Repository Method (from earlier)
**File**: `vbwd-backend/src/services/user_service.py:82`

Called non-existent `.create()` method instead of `.save()`.

### 4. Missing Change Password Endpoint (from earlier)
**File**: `vbwd-backend/src/routes/user.py:151-194`

POST `/api/v1/user/change-password` endpoint didn't exist.

## Files Modified

| File | Change |
|------|--------|
| `vbwd-backend/src/testing/test_data_seeder.py` | Reset password for existing users |
| `vbwd-frontend/user/playwright.config.ts` | Add `VITE_BACKEND_URL` env var |
| `vbwd-backend/src/services/user_service.py` | `.create()` → `.save()` |
| `vbwd-backend/src/routes/user.py` | Add `/change-password` endpoint |
| `vbwd-frontend/user/vue/tests/e2e/profile.spec.ts` | Restore password after test |

## Important Notes for Future Iterations

### Test Data Management
- **Always reset mutable state**: When seeding test data, don't assume existing data is in correct state
- **Password changes persist**: The "can change password" test now restores the original password after testing
- **Consider test isolation**: Tests that modify shared state (like passwords) can break other tests

### Environment Configuration
- **`host.docker.internal`**: Only works inside Docker containers on macOS; on Linux it requires `--add-host` flag or doesn't work from host
- **Vite proxy**: Always set `VITE_BACKEND_URL` explicitly for E2E tests running on host
- **Check network errors first**: `getaddrinfo ENOTFOUND` errors indicate DNS/network issues, not application bugs

### Backend Repository Pattern
- **BaseRepository methods**: `save()`, `update()`, `delete()`, `find_by_id()` - no `create()` method
- **Check method existence**: When adding new service code, verify repository methods exist

### Rate Limiting
- Rate limits were increased to 1000/min for testing (in `vbwd-backend/src/routes/auth.py`)
- Consider environment-based rate limits: strict in production, relaxed in testing

## Test Results

```
Running 11 tests using 1 worker

✓ [chromium] auth.spec.ts › redirects to login when not authenticated
✓ [chromium] auth.spec.ts › can login with valid credentials
✓ [chromium] auth.spec.ts › shows error with invalid credentials
✓ [chromium] auth.spec.ts › can logout
✓ [chromium] profile.spec.ts › displays profile information
✓ [chromium] profile.spec.ts › can update profile name
✓ [chromium] profile.spec.ts › can change password
✓ [chromium] subscription.spec.ts › displays current subscription
✓ [chromium] subscription.spec.ts › shows usage statistics
✓ [chromium] subscription.spec.ts › can navigate to plan selection
✓ [chromium] subscription.spec.ts › can cancel subscription with confirmation

11 passed (11.3s)
```

## Related Sprints

- Sprint 14: Profile API 500 Error Fix (completed)
- Sprint 15: Frontend Success Toast (misdiagnosed - actual issues were backend/infra)
