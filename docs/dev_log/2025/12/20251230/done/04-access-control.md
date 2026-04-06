# Sprint 4: Access Control (Backend)

**Priority:** HIGH
**Duration:** 1 day
**Focus:** Implement backend RBAC and tariff-based feature guards

> **Core Requirements:** See [sprint-plan.md](./sprint-plan.md) for mandatory TDD-first, SOLID, DI, Clean Code, and No Over-Engineering requirements.

> **Note:** Frontend access control (guards, composables, components) has been moved to **Sprint 05-01** which depends on Sprint 05 (View Core Extraction).

---

## 4.1 RBAC Backend Implementation

### Problem
No role-based access control for admin operations.

### Current State
- Admin routes exist but no role checking
- No permission system

### Requirements
- Role model (admin, moderator, support, user)
- Permission model (view_users, edit_users, manage_subscriptions, etc.)
- Role-permission mapping
- User-role assignment

### TDD Tests First

**File:** `tests/unit/services/test_rbac_service.py`
```python
class TestRBACService:
    def test_user_has_permission_returns_true(self):
        """User with role that has permission returns True."""
        pass

    def test_user_without_permission_returns_false(self):
        """User without permission returns False."""
        pass

    def test_admin_has_all_permissions(self):
        """Admin role has all permissions."""
        pass

    def test_assign_role_to_user(self):
        """Role can be assigned to user."""
        pass

    def test_revoke_role_from_user(self):
        """Role can be revoked from user."""
        pass

    def test_get_user_permissions(self):
        """All user permissions returned."""
        pass
```

### Implementation

**File:** `src/models/role.py`
```python
from src.extensions import db
from src.models.base import BaseModel

# Association table for role-permission many-to-many
role_permissions = db.Table(
    'role_permissions',
    db.Column('role_id', db.UUID, db.ForeignKey('role.id'), primary_key=True),
    db.Column('permission_id', db.UUID, db.ForeignKey('permission.id'), primary_key=True)
)

# Association table for user-role many-to-many
user_roles = db.Table(
    'user_roles',
    db.Column('user_id', db.UUID, db.ForeignKey('user.id'), primary_key=True),
    db.Column('role_id', db.UUID, db.ForeignKey('role.id'), primary_key=True)
)

class Role(BaseModel):
    __tablename__ = 'role'

    name = db.Column(db.String(50), unique=True, nullable=False)
    description = db.Column(db.String(255))
    is_system = db.Column(db.Boolean, default=False)  # Prevent deletion

    permissions = db.relationship(
        'Permission',
        secondary=role_permissions,
        backref='roles'
    )

class Permission(BaseModel):
    __tablename__ = 'permission'

    name = db.Column(db.String(100), unique=True, nullable=False)
    description = db.Column(db.String(255))
    resource = db.Column(db.String(50))  # users, subscriptions, payments
    action = db.Column(db.String(50))    # view, create, edit, delete
```

**File:** `src/services/rbac_service.py`
```python
from typing import List, Set
from src.models.role import Role, Permission
from src.repositories.role_repository import RoleRepository

class RBACService:
    def __init__(self, role_repository: RoleRepository):
        self.role_repo = role_repository

    def has_permission(self, user_id: str, permission_name: str) -> bool:
        """Check if user has specific permission."""
        permissions = self.get_user_permissions(user_id)
        return permission_name in permissions

    def has_any_permission(self, user_id: str, permission_names: List[str]) -> bool:
        """Check if user has any of the permissions."""
        permissions = self.get_user_permissions(user_id)
        return bool(permissions & set(permission_names))

    def has_all_permissions(self, user_id: str, permission_names: List[str]) -> bool:
        """Check if user has all permissions."""
        permissions = self.get_user_permissions(user_id)
        return set(permission_names).issubset(permissions)

    def get_user_permissions(self, user_id: str) -> Set[str]:
        """Get all permissions for user."""
        roles = self.role_repo.get_user_roles(user_id)
        permissions = set()
        for role in roles:
            for perm in role.permissions:
                permissions.add(perm.name)
        return permissions

    def assign_role(self, user_id: str, role_name: str) -> bool:
        """Assign role to user."""
        return self.role_repo.assign_role(user_id, role_name)

    def revoke_role(self, user_id: str, role_name: str) -> bool:
        """Revoke role from user."""
        return self.role_repo.revoke_role(user_id, role_name)
```

**Files to create:**
- `src/models/role.py` - CREATE
- `src/services/rbac_service.py` - CREATE
- `src/repositories/role_repository.py` - CREATE

---

## 4.2 Tariff-based Guards

### Problem
No feature gating based on subscription plan.

### Requirements
- Feature flags per tariff plan
- Check user's current plan features
- Graceful degradation for expired subscriptions
- Feature usage limits

### TDD Tests First

**File:** `tests/unit/services/test_feature_guard.py`
```python
class TestFeatureGuard:
    def test_user_with_feature_access_allowed(self):
        """User with plan containing feature can access."""
        pass

    def test_user_without_feature_access_denied(self):
        """User without feature in plan is denied."""
        pass

    def test_expired_subscription_uses_free_tier(self):
        """Expired subscription falls back to free tier."""
        pass

    def test_usage_limit_enforced(self):
        """Feature usage limits enforced."""
        pass

    def test_usage_limit_resets_monthly(self):
        """Usage limits reset each billing cycle."""
        pass
```

### Implementation

**File:** `src/services/feature_guard.py`
```python
from typing import Optional
from datetime import datetime
from src.repositories.subscription_repository import SubscriptionRepository
from src.repositories.feature_usage_repository import FeatureUsageRepository

class FeatureGuard:
    FREE_TIER_FEATURES = {"basic_access", "limited_uploads"}

    def __init__(
        self,
        subscription_repo: SubscriptionRepository,
        usage_repo: FeatureUsageRepository
    ):
        self.subscription_repo = subscription_repo
        self.usage_repo = usage_repo

    def can_access_feature(self, user_id: str, feature_name: str) -> bool:
        """Check if user can access feature."""
        subscription = self.subscription_repo.get_active_subscription(user_id)

        if not subscription or subscription.is_expired:
            # Fall back to free tier
            return feature_name in self.FREE_TIER_FEATURES

        plan_features = subscription.tarif_plan.features or {}
        return feature_name in plan_features

    def check_usage_limit(
        self,
        user_id: str,
        feature_name: str,
        increment: int = 1
    ) -> tuple[bool, Optional[int]]:
        """Check if user is within usage limit."""
        subscription = self.subscription_repo.get_active_subscription(user_id)
        if not subscription:
            return False, None

        limit = subscription.tarif_plan.get_limit(feature_name)
        if limit is None:
            return True, None  # Unlimited

        current_usage = self.usage_repo.get_monthly_usage(
            user_id, feature_name, subscription.current_period_start
        )

        remaining = limit - current_usage
        if remaining >= increment:
            self.usage_repo.increment_usage(user_id, feature_name, increment)
            return True, remaining - increment

        return False, remaining

    def get_feature_limits(self, user_id: str) -> dict:
        """Get all feature limits and current usage."""
        subscription = self.subscription_repo.get_active_subscription(user_id)
        if not subscription:
            return {}

        limits = subscription.tarif_plan.limits or {}
        result = {}

        for feature, limit in limits.items():
            usage = self.usage_repo.get_monthly_usage(
                user_id, feature, subscription.current_period_start
            )
            result[feature] = {
                "limit": limit,
                "used": usage,
                "remaining": max(0, limit - usage)
            }

        return result
```

**File:** `src/models/feature_usage.py`
```python
from src.extensions import db
from src.models.base import BaseModel

class FeatureUsage(BaseModel):
    __tablename__ = 'feature_usage'

    user_id = db.Column(db.UUID, db.ForeignKey('user.id'), nullable=False)
    feature_name = db.Column(db.String(100), nullable=False)
    usage_count = db.Column(db.Integer, default=0)
    period_start = db.Column(db.DateTime, nullable=False)

    __table_args__ = (
        db.UniqueConstraint('user_id', 'feature_name', 'period_start'),
    )
```

---

## 4.3 Permission Decorators

### Problem
No convenient way to protect routes with permissions.

### Implementation

**File:** `src/decorators/permissions.py`
```python
from functools import wraps
from flask import current_app, jsonify
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request

def require_permission(*permissions):
    """Decorator to require specific permissions."""
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            verify_jwt_in_request()
            user_id = get_jwt_identity()

            rbac = current_app.container.rbac_service()

            if not rbac.has_any_permission(user_id, list(permissions)):
                return jsonify({"error": "Insufficient permissions"}), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator

def require_all_permissions(*permissions):
    """Decorator to require all specified permissions."""
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            verify_jwt_in_request()
            user_id = get_jwt_identity()

            rbac = current_app.container.rbac_service()

            if not rbac.has_all_permissions(user_id, list(permissions)):
                return jsonify({"error": "Insufficient permissions"}), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator

def require_feature(feature_name: str):
    """Decorator to require subscription feature."""
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            verify_jwt_in_request()
            user_id = get_jwt_identity()

            guard = current_app.container.feature_guard()

            if not guard.can_access_feature(user_id, feature_name):
                return jsonify({
                    "error": "Feature not available",
                    "feature": feature_name,
                    "upgrade_required": True
                }), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator
```

**Usage:**
```python
from src.decorators.permissions import require_permission, require_feature

@admin_bp.route("/users", methods=["GET"])
@require_permission("view_users")
def list_users():
    # Only users with view_users permission can access
    pass

@api_bp.route("/export", methods=["POST"])
@require_feature("data_export")
def export_data():
    # Only users with data_export feature can access
    pass
```

---

## Checklist

### 4.1 RBAC Backend
- [ ] Tests for RBACService
- [ ] Role model created
- [ ] Permission model created
- [ ] RBACService implemented
- [ ] Role repository created
- [ ] All tests pass

### 4.2 Tariff Guards
- [ ] Tests for FeatureGuard
- [ ] FeatureUsage model created
- [ ] FeatureGuard service implemented
- [ ] Usage tracking repository
- [ ] All tests pass

### 4.3 Permission Decorators
- [ ] require_permission decorator
- [ ] require_all_permissions decorator
- [ ] require_feature decorator
- [ ] Tests for decorators
- [ ] All tests pass

> **Frontend Access Control** → See [Sprint 05-01](./05-01-frontend-access-control.md)

---

## Verification Commands

```bash
# Run RBAC tests
docker-compose --profile test run --rm test pytest tests/unit/services/test_rbac_service.py -v

# Run feature guard tests
docker-compose --profile test run --rm test pytest tests/unit/services/test_feature_guard.py -v

# Check decorator usage
grep -rn "@require_permission" src/routes/
```
