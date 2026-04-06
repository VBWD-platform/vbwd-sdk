# Sprint 14a — Backend: Permission Enforcement Tests

**Status:** Planned
**Date:** 2026-04-04
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [14 — Access Control Bulletproof Tests](14-access-bulletproof-tests.md)

---

## Goal

Unit + integration tests proving the `@require_permission` decorator and RBAC system work correctly in all edge cases.

---

## Test Cases

### Unit Tests (mocked repos)

| # | Test | Expected |
|---|------|----------|
| 1 | `@require_permission("shop.products.view")` with user who has `shop.products.view` | 200 OK |
| 2 | `@require_permission("shop.products.view")` with user who lacks it | 403 `{"error":"Permission denied","required":"shop.products.view"}` |
| 3 | `@require_permission("shop.products.view")` with unauthenticated request | 401 |
| 4 | User with wildcard `*` permission passes any `@require_permission` | 200 OK |
| 5 | User with `shop.*` wildcard passes `@require_permission("shop.products.view")` | 200 OK |
| 6 | User with `shop.*` wildcard fails `@require_permission("cms.pages.view")` | 403 |
| 7 | Multi-role user: role A has `shop.products.view`, role B has `cms.pages.view` — user can access both | 200 OK for both |
| 8 | `@require_permission("a", "b")` — user has `a` but not `b` | 403 (ALL required) |
| 9 | Legacy `ADMIN` user (no RBAC roles assigned) passes any permission check | 200 OK |
| 10 | Legacy `USER` user (no RBAC roles) fails permission check | 403 |

### Role CRUD Protection

| # | Test | Expected |
|---|------|----------|
| 11 | Delete system role (`super-admin`) | 400 "System roles cannot be deleted" |
| 12 | Create role with duplicate slug | 400 |
| 13 | Assign non-existent role to user | 404 |
| 14 | Revoke role from user | Role removed, user loses permissions |
| 15 | Export roles → import → data matches | Round-trip preserves all fields |

### Permission Listing

| # | Test | Expected |
|---|------|----------|
| 16 | `GET /admin/access/permissions` returns core permissions | Contains `users.view`, `settings.system` |
| 17 | Enabled plugin's permissions appear in listing | Shop permissions present when shop enabled |
| 18 | Disabled plugin's permissions absent from listing | Shop permissions gone when shop disabled |

---

## Test Utilities (shared fixtures)

```python
# tests/fixtures/access.py

def make_user_with_permissions(*permissions) -> MagicMock:
    """Create a mock user with specific RBAC permissions."""

def make_user_with_role(role_slug, is_admin=True, permissions=None) -> MagicMock:
    """Create a mock user with a specific role."""

def assert_forbidden(response, required_permission):
    """Assert 403 with correct error body."""
    assert response.status_code == 403
    data = response.get_json()
    assert data["error"] == "Permission denied"
    assert data["required"] == required_permission
```

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Create `tests/fixtures/access.py` with shared test utilities | — |
| 2 | Unit tests for `@require_permission` decorator (cases 1-10) | TDD |
| 3 | Unit tests for role CRUD protection (cases 11-15) | TDD |
| 4 | Integration tests for permission listing (cases 16-18) | TDD |
| 5 | `pre-commit-check.sh --full` (backend) | — |

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
```
