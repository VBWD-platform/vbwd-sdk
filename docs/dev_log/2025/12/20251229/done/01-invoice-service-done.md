# Task 1: Invoice Generation Service

**Priority:** HIGH
**Current:** 40% → **Target:** 100%
**Estimated Time:** 3-4 hours

---

## Prerequisites
- [x] UserInvoice model exists
- [x] InvoiceRepository exists
- [ ] InvoiceService - TO CREATE
- [ ] Invoice routes - TO CREATE

---

## TDD Checklist

### Step 1: Create Test File (RED)

Create `tests/unit/services/test_invoice_service.py`:

```bash
docker-compose run --rm python-test pytest tests/unit/services/test_invoice_service.py -v
# Expected: All tests FAIL (no implementation)
```

**Tests to write:**

#### Creation Tests
- [ ] `test_create_invoice_success` - Creates invoice with PENDING status
- [ ] `test_create_invoice_generates_unique_number` - Format: INV-YYYYMMDD-XXXX
- [ ] `test_create_invoice_links_to_subscription` - FK to subscription
- [ ] `test_create_invoice_includes_tax` - Tax calculation correct
- [ ] `test_create_invoice_sets_due_date` - Default 30 days from creation

#### Retrieval Tests
- [ ] `test_get_invoice_by_id` - Returns invoice
- [ ] `test_get_invoice_not_found` - Returns None
- [ ] `test_get_user_invoices` - Returns list for user
- [ ] `test_get_user_invoices_empty` - Returns empty list
- [ ] `test_get_subscription_invoices` - Returns list for subscription

#### Status Transition Tests
- [ ] `test_mark_paid_success` - PENDING → PAID
- [ ] `test_mark_paid_sets_payment_reference` - Stores payment ref
- [ ] `test_mark_paid_already_paid` - Error if already paid
- [ ] `test_mark_failed` - PENDING → FAILED
- [ ] `test_mark_cancelled` - PENDING → CANCELLED
- [ ] `test_mark_refunded` - PAID → REFUNDED
- [ ] `test_mark_refunded_not_paid` - Error if not paid

#### Query Tests
- [ ] `test_get_pending_invoices` - Returns all PENDING
- [ ] `test_get_overdue_invoices` - Returns past due date

---

### Step 2: Implement Service (GREEN)

Create `src/services/invoice_service.py`:

```python
from decimal import Decimal
from datetime import datetime, timedelta
from typing import Optional, List
from src.interfaces.service import IService
from src.repositories.invoice_repository import InvoiceRepository
from src.models.invoice import UserInvoice, InvoiceStatus

class InvoiceResult:
    def __init__(
        self,
        success: bool,
        invoice: Optional[UserInvoice] = None,
        error: Optional[str] = None
    ):
        self.success = success
        self.invoice = invoice
        self.error = error

class InvoiceService(IService):
    def __init__(self, invoice_repository: InvoiceRepository):
        self._repo = invoice_repository

    def create_invoice(
        self,
        user_id: str,
        subscription_id: str,
        amount: Decimal,
        currency: str = 'USD',
        tax_amount: Decimal = Decimal('0'),
        due_days: int = 30
    ) -> InvoiceResult:
        """Create new invoice for subscription."""
        pass  # Implement

    def get_invoice(self, invoice_id: str) -> Optional[UserInvoice]:
        """Get invoice by ID."""
        pass

    def get_user_invoices(self, user_id: str) -> List[UserInvoice]:
        """Get all invoices for user."""
        pass

    def get_subscription_invoices(self, subscription_id: str) -> List[UserInvoice]:
        """Get all invoices for subscription."""
        pass

    def mark_paid(
        self,
        invoice_id: str,
        payment_reference: str,
        payment_method: str
    ) -> InvoiceResult:
        """Mark invoice as paid."""
        pass

    def mark_failed(self, invoice_id: str) -> InvoiceResult:
        """Mark invoice as failed."""
        pass

    def mark_cancelled(self, invoice_id: str) -> InvoiceResult:
        """Cancel invoice."""
        pass

    def mark_refunded(
        self,
        invoice_id: str,
        refund_reference: str
    ) -> InvoiceResult:
        """Mark invoice as refunded."""
        pass

    def get_pending_invoices(self) -> List[UserInvoice]:
        """Get all pending invoices."""
        pass

    def get_overdue_invoices(self) -> List[UserInvoice]:
        """Get invoices past due date."""
        pass
```

Run tests until all pass:
```bash
docker-compose run --rm python-test pytest tests/unit/services/test_invoice_service.py -v
# Expected: All tests PASS
```

---

### Step 3: Create Invoice Routes (RED → GREEN)

Create test `tests/unit/routes/test_invoice_routes.py`:
- [ ] `test_get_invoices_authenticated`
- [ ] `test_get_invoices_unauthenticated`
- [ ] `test_get_invoice_detail`
- [ ] `test_get_invoice_not_found`
- [ ] `test_get_invoice_not_owned`

Create route `src/routes/invoices.py`:
```python
from flask import Blueprint, jsonify, g
from src.middleware.auth import require_auth

invoices_bp = Blueprint('invoices', __name__, url_prefix='/api/v1/user/invoices')

@invoices_bp.route('/', methods=['GET'])
@require_auth
def get_invoices():
    """List user's invoices."""
    pass

@invoices_bp.route('/<invoice_id>', methods=['GET'])
@require_auth
def get_invoice(invoice_id):
    """Get invoice detail."""
    pass
```

Register in `src/app.py`:
```python
from src.routes.invoices import invoices_bp
app.register_blueprint(invoices_bp)
```

---

### Step 4: Verify

```bash
# Run all invoice tests
docker-compose run --rm python-test pytest tests/unit/services/test_invoice_service.py tests/unit/routes/test_invoice_routes.py -v

# Check coverage
docker-compose run --rm python-test pytest tests/ --cov=src/services/invoice_service --cov-report=term-missing
```

---

## Acceptance Criteria

- [ ] InvoiceService created with all methods
- [ ] All 18+ unit tests pass
- [ ] Test coverage ≥ 95%
- [ ] Routes registered and functional
- [ ] No linting errors
- [ ] Type hints on all methods
- [ ] Docstrings present
