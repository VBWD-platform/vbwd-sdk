# Task 3: Admin API

**Priority:** HIGH
**Current:** 20% → **Target:** 100%
**Estimated Time:** 4-5 hours

---

## Prerequisites
- [x] `@require_admin` decorator exists
- [x] UserService exists
- [x] SubscriptionService exists
- [ ] InvoiceService - from Task 1
- [ ] Admin routes - TO CREATE

---

## TDD Checklist

### Step 1: Create Admin Route Package

```bash
mkdir -p src/routes/admin
touch src/routes/admin/__init__.py
```

---

### Step 2: Admin User Management (RED → GREEN)

Create `tests/unit/routes/test_admin_users.py`:

**Tests to write:**

#### List Users
- [ ] `test_list_users_as_admin` - Returns paginated user list
- [ ] `test_list_users_with_pagination` - limit/offset work
- [ ] `test_list_users_with_status_filter` - Filter by status
- [ ] `test_list_users_with_search` - Search by email
- [ ] `test_list_users_as_regular_user` - 403 Forbidden
- [ ] `test_list_users_unauthenticated` - 401 Unauthorized

#### Get User Detail
- [ ] `test_get_user_detail` - Returns user with subscriptions/invoices
- [ ] `test_get_user_not_found` - 404 Not Found

#### Update User
- [ ] `test_update_user_status` - Change status
- [ ] `test_update_user_role` - Change role
- [ ] `test_suspend_user` - Suspend user
- [ ] `test_activate_user` - Activate suspended user
- [ ] `test_update_user_not_found` - 404

Create `src/routes/admin/users.py`:

```python
from flask import Blueprint, jsonify, request, g
from src.middleware.auth import require_admin
from src.services.user_service import UserService
from src.repositories.user_repository import UserRepository
from src.extensions import db

admin_users_bp = Blueprint('admin_users', __name__, url_prefix='/api/v1/admin/users')

@admin_users_bp.route('/', methods=['GET'])
@require_admin
def list_users():
    """
    GET /api/v1/admin/users

    Query params:
        - limit: int (default 20, max 100)
        - offset: int (default 0)
        - status: str (active, pending, suspended, deleted)
        - search: str (email search)
    """
    limit = min(int(request.args.get('limit', 20)), 100)
    offset = int(request.args.get('offset', 0))
    status = request.args.get('status')
    search = request.args.get('search')

    user_repo = UserRepository(db.session)
    # Implement query logic
    pass

@admin_users_bp.route('/<user_id>', methods=['GET'])
@require_admin
def get_user(user_id):
    """GET /api/v1/admin/users/<id> - Get user with subscriptions and invoices"""
    pass

@admin_users_bp.route('/<user_id>', methods=['PUT'])
@require_admin
def update_user(user_id):
    """PUT /api/v1/admin/users/<id> - Update user status/role"""
    pass

@admin_users_bp.route('/<user_id>/suspend', methods=['POST'])
@require_admin
def suspend_user(user_id):
    """POST /api/v1/admin/users/<id>/suspend"""
    pass

@admin_users_bp.route('/<user_id>/activate', methods=['POST'])
@require_admin
def activate_user(user_id):
    """POST /api/v1/admin/users/<id>/activate"""
    pass
```

---

### Step 3: Admin Subscription Management (RED → GREEN)

Create `tests/unit/routes/test_admin_subscriptions.py`:

**Tests to write:**

#### List Subscriptions
- [ ] `test_list_subscriptions` - Returns all subscriptions
- [ ] `test_list_subscriptions_filter_by_status` - Filter by status
- [ ] `test_list_subscriptions_filter_by_user` - Filter by user_id
- [ ] `test_list_subscriptions_filter_by_plan` - Filter by plan
- [ ] `test_list_subscriptions_pagination` - limit/offset

#### Get Subscription Detail
- [ ] `test_get_subscription_detail` - With user and plan

#### Subscription Actions
- [ ] `test_extend_subscription` - Extend expiration date
- [ ] `test_cancel_subscription_admin` - Admin can cancel any
- [ ] `test_force_activate_subscription` - Force activate
- [ ] `test_refund_subscription` - Process refund

Create `src/routes/admin/subscriptions.py`:

```python
from flask import Blueprint, jsonify, request
from src.middleware.auth import require_admin

admin_subs_bp = Blueprint('admin_subscriptions', __name__, url_prefix='/api/v1/admin/subscriptions')

@admin_subs_bp.route('/', methods=['GET'])
@require_admin
def list_subscriptions():
    """
    GET /api/v1/admin/subscriptions

    Query params:
        - limit, offset: pagination
        - status: subscription status filter
        - user_id: filter by user
        - plan_id: filter by plan
    """
    pass

@admin_subs_bp.route('/<subscription_id>', methods=['GET'])
@require_admin
def get_subscription(subscription_id):
    """GET /api/v1/admin/subscriptions/<id>"""
    pass

@admin_subs_bp.route('/<subscription_id>/extend', methods=['POST'])
@require_admin
def extend_subscription(subscription_id):
    """
    POST /api/v1/admin/subscriptions/<id>/extend

    Body: { "days": 30 }
    """
    pass

@admin_subs_bp.route('/<subscription_id>/cancel', methods=['POST'])
@require_admin
def cancel_subscription(subscription_id):
    """POST /api/v1/admin/subscriptions/<id>/cancel"""
    pass

@admin_subs_bp.route('/<subscription_id>/activate', methods=['POST'])
@require_admin
def activate_subscription(subscription_id):
    """POST /api/v1/admin/subscriptions/<id>/activate"""
    pass

@admin_subs_bp.route('/<subscription_id>/refund', methods=['POST'])
@require_admin
def refund_subscription(subscription_id):
    """
    POST /api/v1/admin/subscriptions/<id>/refund

    Body: { "amount": 50.00, "reason": "Customer request" }
    """
    pass
```

---

### Step 4: Admin Invoice Management (RED → GREEN)

Create `tests/unit/routes/test_admin_invoices.py`:

**Tests to write:**
- [ ] `test_list_invoices` - All invoices
- [ ] `test_list_invoices_filter_by_status` - Filter by status
- [ ] `test_list_invoices_filter_by_date_range` - Date filtering
- [ ] `test_get_invoice_detail` - Full invoice detail
- [ ] `test_mark_invoice_paid_manually` - Manual payment
- [ ] `test_void_invoice` - Cancel/void invoice
- [ ] `test_refund_invoice` - Refund paid invoice
- [ ] `test_download_any_invoice_pdf` - Download PDF

Create `src/routes/admin/invoices.py`:

```python
from flask import Blueprint, jsonify, request, send_file
from src.middleware.auth import require_admin

admin_invoices_bp = Blueprint('admin_invoices', __name__, url_prefix='/api/v1/admin/invoices')

@admin_invoices_bp.route('/', methods=['GET'])
@require_admin
def list_invoices():
    """GET /api/v1/admin/invoices"""
    pass

@admin_invoices_bp.route('/<invoice_id>', methods=['GET'])
@require_admin
def get_invoice(invoice_id):
    """GET /api/v1/admin/invoices/<id>"""
    pass

@admin_invoices_bp.route('/<invoice_id>/mark-paid', methods=['POST'])
@require_admin
def mark_paid(invoice_id):
    """
    POST /api/v1/admin/invoices/<id>/mark-paid

    Body: { "payment_reference": "...", "payment_method": "manual" }
    """
    pass

@admin_invoices_bp.route('/<invoice_id>/void', methods=['POST'])
@require_admin
def void_invoice(invoice_id):
    """POST /api/v1/admin/invoices/<id>/void"""
    pass

@admin_invoices_bp.route('/<invoice_id>/refund', methods=['POST'])
@require_admin
def refund_invoice(invoice_id):
    """POST /api/v1/admin/invoices/<id>/refund"""
    pass

@admin_invoices_bp.route('/<invoice_id>/pdf', methods=['GET'])
@require_admin
def download_pdf(invoice_id):
    """GET /api/v1/admin/invoices/<id>/pdf"""
    pass
```

---

### Step 5: Admin Plan Management (RED → GREEN)

Create `tests/unit/routes/test_admin_plans.py`:

**Tests to write:**
- [ ] `test_list_all_plans` - Including inactive
- [ ] `test_create_plan` - Create new plan
- [ ] `test_create_plan_validation` - Validation errors
- [ ] `test_update_plan` - Update plan details
- [ ] `test_deactivate_plan` - Deactivate plan
- [ ] `test_cannot_delete_plan_with_subscriptions` - Protection

Create `src/routes/admin/plans.py`:

```python
from flask import Blueprint, jsonify, request
from src.middleware.auth import require_admin

admin_plans_bp = Blueprint('admin_plans', __name__, url_prefix='/api/v1/admin/tariff-plans')

@admin_plans_bp.route('/', methods=['GET'])
@require_admin
def list_plans():
    """GET /api/v1/admin/tariff-plans - All plans including inactive"""
    pass

@admin_plans_bp.route('/', methods=['POST'])
@require_admin
def create_plan():
    """POST /api/v1/admin/tariff-plans"""
    pass

@admin_plans_bp.route('/<plan_id>', methods=['PUT'])
@require_admin
def update_plan(plan_id):
    """PUT /api/v1/admin/tariff-plans/<id>"""
    pass

@admin_plans_bp.route('/<plan_id>', methods=['DELETE'])
@require_admin
def delete_plan(plan_id):
    """DELETE /api/v1/admin/tariff-plans/<id>"""
    pass

@admin_plans_bp.route('/<plan_id>/deactivate', methods=['POST'])
@require_admin
def deactivate_plan(plan_id):
    """POST /api/v1/admin/tariff-plans/<id>/deactivate"""
    pass
```

---

### Step 6: Register All Admin Blueprints

Update `src/routes/admin/__init__.py`:
```python
from src.routes.admin.users import admin_users_bp
from src.routes.admin.subscriptions import admin_subs_bp
from src.routes.admin.invoices import admin_invoices_bp
from src.routes.admin.plans import admin_plans_bp

__all__ = [
    'admin_users_bp',
    'admin_subs_bp',
    'admin_invoices_bp',
    'admin_plans_bp'
]
```

Update `src/app.py`:
```python
from src.routes.admin import (
    admin_users_bp,
    admin_subs_bp,
    admin_invoices_bp,
    admin_plans_bp
)

def create_app():
    # ... existing code ...

    # Register admin blueprints
    app.register_blueprint(admin_users_bp)
    app.register_blueprint(admin_subs_bp)
    app.register_blueprint(admin_invoices_bp)
    app.register_blueprint(admin_plans_bp)

    return app
```

---

### Step 7: Verify

```bash
# Run all admin tests
docker-compose run --rm python-test pytest tests/unit/routes/test_admin_*.py -v

# Check coverage
docker-compose run --rm python-test pytest tests/ --cov=src/routes/admin --cov-report=term-missing
```

---

## API Summary

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/admin/users` | List users |
| GET | `/api/v1/admin/users/<id>` | Get user detail |
| PUT | `/api/v1/admin/users/<id>` | Update user |
| POST | `/api/v1/admin/users/<id>/suspend` | Suspend user |
| POST | `/api/v1/admin/users/<id>/activate` | Activate user |
| GET | `/api/v1/admin/subscriptions` | List subscriptions |
| GET | `/api/v1/admin/subscriptions/<id>` | Get subscription |
| POST | `/api/v1/admin/subscriptions/<id>/extend` | Extend subscription |
| POST | `/api/v1/admin/subscriptions/<id>/cancel` | Cancel subscription |
| POST | `/api/v1/admin/subscriptions/<id>/activate` | Activate subscription |
| POST | `/api/v1/admin/subscriptions/<id>/refund` | Refund subscription |
| GET | `/api/v1/admin/invoices` | List invoices |
| GET | `/api/v1/admin/invoices/<id>` | Get invoice |
| POST | `/api/v1/admin/invoices/<id>/mark-paid` | Mark paid |
| POST | `/api/v1/admin/invoices/<id>/void` | Void invoice |
| POST | `/api/v1/admin/invoices/<id>/refund` | Refund invoice |
| GET | `/api/v1/admin/invoices/<id>/pdf` | Download PDF |
| GET | `/api/v1/admin/tariff-plans` | List plans |
| POST | `/api/v1/admin/tariff-plans` | Create plan |
| PUT | `/api/v1/admin/tariff-plans/<id>` | Update plan |
| DELETE | `/api/v1/admin/tariff-plans/<id>` | Delete plan |
| POST | `/api/v1/admin/tariff-plans/<id>/deactivate` | Deactivate plan |

---

## Acceptance Criteria

- [ ] 4 admin route files created
- [ ] 22+ API endpoints implemented
- [ ] All 30+ unit tests pass
- [ ] Test coverage ≥ 95%
- [ ] All routes protected with @require_admin
- [ ] Pagination works correctly
- [ ] Filters work correctly
- [ ] No linting errors
- [ ] Type hints on all methods
