# Sprint 12a — Backend: Permission Middleware

**Status:** Pending
**Date:** 2026-04-03
**Principles:** TDD · SOLID · DI · Liskov · DRY · Clean Code · No over-engineering
**Parent:** [12 — Admin Access Levels](12-admin-access-levels.md)

---

## Goal

Replace binary `@require_admin` with permission-based `@require_permission()`. Wire existing `Role`/`Permission` models into the auth flow. Remove hardcoded `UserRole` enum — roles become dynamic DB records.

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Remove `UserRole` enum from `enums.py`. Add `is_admin` computed property to User based on assigned roles. | Unit tests for User.is_admin |
| 2 | Update `Role` model: add `is_system`, `is_admin` (grants admin panel access) fields | Model tests |
| 3 | Wire `vbwd_user_roles` junction to `User.roles` relationship | Relationship tests |
| 4 | Create `PermissionService` — `has_permission(user_id, permission_string)`, `get_user_permissions(user_id)` | Service tests (mocked repos) |
| 5 | Create `@require_permission(perm)` decorator in `auth.py` — checks via `PermissionService` | Decorator tests |
| 6 | Update `@require_admin` to use role-based check (`user.is_admin`) instead of enum | Integration tests |
| 7 | Seed default system roles: `super-admin` (wildcard `*`), `admin`, `user` | Seed tests |
| 8 | Migration: existing `ADMIN` users → assigned `super-admin` role | Migration test |
| 9 | Update User `to_dict()` to return `roles` array with permission lists | API response tests |
| 10 | `pre-commit-check.sh --full` | — |

---

## Key Design

### @require_permission decorator
```python
def require_permission(*permissions):
    """Check user has ALL specified permissions (or wildcard *)."""
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            if not hasattr(g, 'user') or not g.user:
                return jsonify({"error": "Authentication required"}), 401
            permission_service = PermissionService(RoleRepository(db.session))
            for perm in permissions:
                if not permission_service.has_permission(g.user.id, perm):
                    return jsonify({"error": "Permission denied", "required": perm}), 403
            return f(*args, **kwargs)
        return wrapper
    return decorator
```

### Wildcard matching
- `*` matches everything (super-admin)
- `shop.*` matches all shop permissions
- `shop.products.manage` matches exactly

### User.is_admin property
```python
@property
def is_admin(self) -> bool:
    return any(role.is_admin for role in self.roles)
```

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
```
