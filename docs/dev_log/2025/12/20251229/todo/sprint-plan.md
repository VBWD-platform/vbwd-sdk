# Sprint Plan: Backend Completion
**Date:** 2025-12-29
**Goal:** Complete Subscription (70%→100%), Invoice (40%→100%), Admin API (20%→100%), Email (0%→100%)

---

## Core Requirements

### Development Principles (MANDATORY)

1. **TDD-First**
   - Write failing test BEFORE any production code
   - RED → GREEN → REFACTOR cycle
   - No production code without a corresponding test
   - Target: 95%+ test coverage for new code

2. **SOLID Principles**
   - **S**ingle Responsibility: One class = one reason to change
   - **O**pen/Closed: Extend via interfaces, don't modify existing code
   - **L**iskov Substitution: Subclasses must be substitutable for base classes
   - **I**nterface Segregation: Small, focused interfaces
   - **D**ependency Inversion: Depend on abstractions, inject dependencies

3. **Clean Code**
   - Meaningful names (no abbreviations)
   - Small functions (< 20 lines preferred)
   - No magic numbers (use constants)
   - No code duplication (DRY)
   - Comments explain WHY, not WHAT

4. **Dockerized Development**
   - All code runs in containers
   - Tests run via `docker-compose run --rm python-test`
   - No local Python dependencies

5. **No Over-Engineering**
   - Implement only what's needed NOW
   - YAGNI (You Aren't Gonna Need It)
   - Simplest solution that works
   - Refactor only when tests pass

---

## Task 1: Subscription Management Enhancement (70% → 100%)

### Current State
- Basic CRUD operations: DONE
- Status transitions: DONE
- User routes: DONE
- Tests: ~70% coverage

### Missing Features
- [ ] Pause/Resume functionality
- [ ] Upgrade/Downgrade between plans
- [ ] Refund calculation on cancellation
- [ ] Additional test coverage

### TDD Tasks

#### 1.1 Subscription Pause/Resume

**Test First:** `tests/unit/services/test_subscription_service.py`
```python
# RED: Write these tests first
def test_pause_subscription_success():
    """Active subscription can be paused"""

def test_pause_subscription_already_paused():
    """Pausing already paused subscription raises error"""

def test_pause_subscription_not_active():
    """Only active subscriptions can be paused"""

def test_resume_subscription_success():
    """Paused subscription can be resumed"""

def test_resume_subscription_not_paused():
    """Only paused subscriptions can be resumed"""

def test_resume_extends_expiration():
    """Resuming subscription extends expiration by paused duration"""
```

**Then Implement:** `src/services/subscription_service.py`
```python
def pause_subscription(self, subscription_id: str) -> SubscriptionResult
def resume_subscription(self, subscription_id: str) -> SubscriptionResult
```

**Then Route:** `src/routes/subscriptions.py`
```python
POST /api/v1/user/subscriptions/<id>/pause
POST /api/v1/user/subscriptions/<id>/resume
```

#### 1.2 Subscription Upgrade/Downgrade

**Test First:**
```python
def test_upgrade_subscription_success():
    """User can upgrade to higher tier plan"""

def test_upgrade_calculates_prorated_amount():
    """Upgrade calculates prorated amount correctly"""

def test_downgrade_subscription_success():
    """User can downgrade to lower tier plan"""

def test_downgrade_takes_effect_at_renewal():
    """Downgrade takes effect at next billing cycle"""

def test_cannot_change_to_same_plan():
    """Changing to current plan raises error"""
```

**Then Implement:**
```python
def upgrade_subscription(self, subscription_id: str, new_plan_id: str) -> SubscriptionResult
def downgrade_subscription(self, subscription_id: str, new_plan_id: str) -> SubscriptionResult
def calculate_proration(self, subscription_id: str, new_plan_id: str) -> Decimal
```

#### 1.3 Refund on Cancellation

**Test First:**
```python
def test_cancel_with_refund_calculation():
    """Cancellation calculates refund for unused days"""

def test_cancel_no_refund_for_monthly():
    """Monthly subscriptions have no prorated refund"""

def test_cancel_prorated_refund_for_yearly():
    """Yearly subscriptions get prorated refund"""
```

**Then Implement:**
```python
def cancel_with_refund(self, subscription_id: str) -> Tuple[SubscriptionResult, Decimal]
```

---

## Task 2: Invoice Generation Service (40% → 100%)

### Current State
- Model exists with status transitions: DONE
- Repository with queries: DONE
- **NO InvoiceService**
- **NO Invoice routes**
- **NO Tests**

### TDD Tasks

#### 2.1 Create InvoiceService

**Test First:** `tests/unit/services/test_invoice_service.py`
```python
class TestInvoiceService:

    # Creation tests
    def test_create_invoice_success(self):
        """Creates invoice with correct amount and status PENDING"""

    def test_create_invoice_generates_unique_number(self):
        """Invoice number follows format INV-YYYYMMDD-XXXX"""

    def test_create_invoice_links_to_subscription(self):
        """Invoice is linked to subscription"""

    def test_create_invoice_includes_tax(self):
        """Invoice amount includes applicable tax"""

    # Retrieval tests
    def test_get_invoice_by_id(self):
        """Returns invoice by ID"""

    def test_get_invoice_not_found(self):
        """Returns None for non-existent invoice"""

    def test_get_user_invoices(self):
        """Returns all invoices for user"""

    def test_get_user_invoices_empty(self):
        """Returns empty list for user with no invoices"""

    def test_get_subscription_invoices(self):
        """Returns all invoices for subscription"""

    # Status transition tests
    def test_mark_paid_success(self):
        """Marks pending invoice as paid"""

    def test_mark_paid_already_paid(self):
        """Cannot mark already paid invoice as paid"""

    def test_mark_failed(self):
        """Marks invoice as failed after payment failure"""

    def test_mark_cancelled(self):
        """Cancels pending invoice"""

    def test_mark_refunded(self):
        """Marks paid invoice as refunded"""

    def test_mark_refunded_not_paid(self):
        """Cannot refund unpaid invoice"""

    # Query tests
    def test_get_pending_invoices(self):
        """Returns all pending invoices"""

    def test_get_overdue_invoices(self):
        """Returns invoices past due date"""
```

**Then Implement:** `src/services/invoice_service.py`
```python
from src.interfaces.service import IService
from src.repositories.invoice_repository import InvoiceRepository
from src.models.invoice import UserInvoice, InvoiceStatus

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
        due_date: datetime = None
    ) -> InvoiceResult

    def get_invoice(self, invoice_id: str) -> Optional[UserInvoice]

    def get_user_invoices(self, user_id: str) -> List[UserInvoice]

    def get_subscription_invoices(self, subscription_id: str) -> List[UserInvoice]

    def mark_paid(
        self,
        invoice_id: str,
        payment_reference: str,
        payment_method: str
    ) -> InvoiceResult

    def mark_failed(self, invoice_id: str) -> InvoiceResult

    def mark_cancelled(self, invoice_id: str) -> InvoiceResult

    def mark_refunded(self, invoice_id: str, refund_reference: str) -> InvoiceResult

    def get_pending_invoices(self) -> List[UserInvoice]

    def get_overdue_invoices(self) -> List[UserInvoice]
```

#### 2.2 Create Invoice Routes (User)

**Test First:** `tests/unit/routes/test_invoice_routes.py`
```python
class TestInvoiceRoutes:

    def test_get_invoices_authenticated(self):
        """Returns user's invoices when authenticated"""

    def test_get_invoices_unauthenticated(self):
        """Returns 401 when not authenticated"""

    def test_get_invoice_detail(self):
        """Returns invoice detail by ID"""

    def test_get_invoice_not_found(self):
        """Returns 404 for non-existent invoice"""

    def test_get_invoice_not_owned(self):
        """Returns 403 for invoice not owned by user"""

    def test_download_invoice_pdf(self):
        """Returns PDF file for invoice"""
```

**Then Implement:** `src/routes/invoices.py`
```python
invoices_bp = Blueprint('invoices', __name__, url_prefix='/api/v1/user/invoices')

@invoices_bp.route('/', methods=['GET'])
@require_auth
def get_invoices():
    """GET /api/v1/user/invoices - List user's invoices"""

@invoices_bp.route('/<invoice_id>', methods=['GET'])
@require_auth
def get_invoice(invoice_id):
    """GET /api/v1/user/invoices/<id> - Get invoice detail"""

@invoices_bp.route('/<invoice_id>/pdf', methods=['GET'])
@require_auth
def download_invoice_pdf(invoice_id):
    """GET /api/v1/user/invoices/<id>/pdf - Download PDF"""
```

#### 2.3 PDF Generation

**Test First:** `tests/unit/services/test_pdf_service.py`
```python
class TestPDFService:

    def test_generate_invoice_pdf(self):
        """Generates PDF bytes for invoice"""

    def test_pdf_contains_invoice_number(self):
        """PDF contains invoice number"""

    def test_pdf_contains_line_items(self):
        """PDF contains subscription details"""

    def test_pdf_contains_totals(self):
        """PDF contains subtotal, tax, total"""
```

**Then Implement:** `src/services/pdf_service.py`
```python
class PDFService:
    def generate_invoice_pdf(self, invoice: UserInvoice) -> bytes
```

---

## Task 3: Admin API (20% → 100%)

### Current State
- `@require_admin` decorator: EXISTS
- **NO admin routes**
- **NO admin services**
- **NO tests**

### TDD Tasks

#### 3.1 Admin User Management

**Test First:** `tests/unit/routes/test_admin_users.py`
```python
class TestAdminUserRoutes:

    # List users
    def test_list_users_as_admin(self):
        """Admin can list all users"""

    def test_list_users_with_pagination(self):
        """List users supports limit/offset"""

    def test_list_users_with_status_filter(self):
        """List users can filter by status"""

    def test_list_users_with_search(self):
        """List users can search by email"""

    def test_list_users_as_regular_user(self):
        """Regular user gets 403"""

    def test_list_users_unauthenticated(self):
        """Unauthenticated gets 401"""

    # Get user detail
    def test_get_user_detail(self):
        """Admin can get user detail with subscriptions and invoices"""

    def test_get_user_not_found(self):
        """Returns 404 for non-existent user"""

    # Update user
    def test_update_user_status(self):
        """Admin can change user status"""

    def test_update_user_role(self):
        """Admin can change user role"""

    def test_suspend_user(self):
        """Admin can suspend user"""

    def test_activate_user(self):
        """Admin can activate suspended user"""
```

**Then Implement:** `src/routes/admin/users.py`
```python
admin_users_bp = Blueprint('admin_users', __name__, url_prefix='/api/v1/admin/users')

@admin_users_bp.route('/', methods=['GET'])
@require_admin
def list_users():
    """GET /api/v1/admin/users - List all users"""

@admin_users_bp.route('/<user_id>', methods=['GET'])
@require_admin
def get_user(user_id):
    """GET /api/v1/admin/users/<id> - Get user detail"""

@admin_users_bp.route('/<user_id>', methods=['PUT'])
@require_admin
def update_user(user_id):
    """PUT /api/v1/admin/users/<id> - Update user"""

@admin_users_bp.route('/<user_id>/suspend', methods=['POST'])
@require_admin
def suspend_user(user_id):
    """POST /api/v1/admin/users/<id>/suspend - Suspend user"""

@admin_users_bp.route('/<user_id>/activate', methods=['POST'])
@require_admin
def activate_user(user_id):
    """POST /api/v1/admin/users/<id>/activate - Activate user"""
```

#### 3.2 Admin Subscription Management

**Test First:** `tests/unit/routes/test_admin_subscriptions.py`
```python
class TestAdminSubscriptionRoutes:

    def test_list_subscriptions(self):
        """Admin can list all subscriptions"""

    def test_list_subscriptions_filter_by_status(self):
        """Admin can filter subscriptions by status"""

    def test_list_subscriptions_filter_by_user(self):
        """Admin can filter subscriptions by user_id"""

    def test_get_subscription_detail(self):
        """Admin can get subscription with user and plan details"""

    def test_extend_subscription(self):
        """Admin can extend subscription expiration"""

    def test_cancel_subscription_admin(self):
        """Admin can cancel any subscription"""

    def test_force_activate_subscription(self):
        """Admin can force activate subscription"""

    def test_refund_subscription(self):
        """Admin can process refund"""
```

**Then Implement:** `src/routes/admin/subscriptions.py`
```python
admin_subs_bp = Blueprint('admin_subscriptions', __name__, url_prefix='/api/v1/admin/subscriptions')

@admin_subs_bp.route('/', methods=['GET'])
@require_admin
def list_subscriptions():
    """GET /api/v1/admin/subscriptions"""

@admin_subs_bp.route('/<subscription_id>', methods=['GET'])
@require_admin
def get_subscription(subscription_id):
    """GET /api/v1/admin/subscriptions/<id>"""

@admin_subs_bp.route('/<subscription_id>/extend', methods=['POST'])
@require_admin
def extend_subscription(subscription_id):
    """POST /api/v1/admin/subscriptions/<id>/extend"""

@admin_subs_bp.route('/<subscription_id>/cancel', methods=['POST'])
@require_admin
def cancel_subscription(subscription_id):
    """POST /api/v1/admin/subscriptions/<id>/cancel"""

@admin_subs_bp.route('/<subscription_id>/refund', methods=['POST'])
@require_admin
def refund_subscription(subscription_id):
    """POST /api/v1/admin/subscriptions/<id>/refund"""
```

#### 3.3 Admin Invoice Management

**Test First:** `tests/unit/routes/test_admin_invoices.py`
```python
class TestAdminInvoiceRoutes:

    def test_list_invoices(self):
        """Admin can list all invoices"""

    def test_list_invoices_filter_by_status(self):
        """Admin can filter by invoice status"""

    def test_list_invoices_filter_by_date_range(self):
        """Admin can filter by date range"""

    def test_get_invoice_detail(self):
        """Admin can get invoice with user and subscription"""

    def test_mark_invoice_paid_manually(self):
        """Admin can manually mark invoice as paid"""

    def test_void_invoice(self):
        """Admin can void/cancel invoice"""

    def test_refund_invoice(self):
        """Admin can refund paid invoice"""

    def test_download_any_invoice_pdf(self):
        """Admin can download any user's invoice PDF"""
```

**Then Implement:** `src/routes/admin/invoices.py`

#### 3.4 Admin Tariff Plan Management

**Test First:** `tests/unit/routes/test_admin_plans.py`
```python
class TestAdminPlanRoutes:

    def test_list_all_plans(self):
        """Admin can list all plans including inactive"""

    def test_create_plan(self):
        """Admin can create new tariff plan"""

    def test_create_plan_validation(self):
        """Plan creation validates required fields"""

    def test_update_plan(self):
        """Admin can update plan details"""

    def test_deactivate_plan(self):
        """Admin can deactivate plan"""

    def test_cannot_delete_plan_with_subscriptions(self):
        """Cannot delete plan with active subscriptions"""
```

**Then Implement:** `src/routes/admin/plans.py`

---

## Task 4: Email Notification Service (0% → 100%)

### Current State
- **NO EmailService**
- **NO email templates**
- Event handlers exist but don't send emails
- **NO tests**

### TDD Tasks

#### 4.1 Create EmailService

**Test First:** `tests/unit/services/test_email_service.py`
```python
class TestEmailService:

    # Configuration tests
    def test_service_initializes_with_smtp_config(self):
        """EmailService initializes with SMTP configuration"""

    def test_service_validates_smtp_config(self):
        """Raises error if SMTP config is invalid"""

    # Send email tests
    def test_send_email_success(self):
        """Sends email via SMTP"""

    def test_send_email_with_html(self):
        """Sends email with HTML body"""

    def test_send_email_with_attachment(self):
        """Sends email with PDF attachment"""

    def test_send_email_failure_logged(self):
        """Failed email send is logged"""

    def test_send_email_retry_on_failure(self):
        """Retries sending on temporary failure"""

    # Template tests
    def test_render_template(self):
        """Renders email template with context"""

    def test_render_template_not_found(self):
        """Raises error for missing template"""

    # Specific email type tests
    def test_send_welcome_email(self):
        """Sends welcome email with correct template"""

    def test_send_subscription_activated_email(self):
        """Sends subscription activated email"""

    def test_send_subscription_cancelled_email(self):
        """Sends subscription cancelled email"""

    def test_send_payment_receipt_email(self):
        """Sends payment receipt with invoice PDF"""

    def test_send_payment_failed_email(self):
        """Sends payment failed notification"""

    def test_send_invoice_email(self):
        """Sends invoice with PDF attachment"""

    def test_send_renewal_reminder_email(self):
        """Sends renewal reminder X days before expiration"""
```

**Then Implement:** `src/services/email_service.py`
```python
from typing import Optional, Dict, Any
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.application import MIMEApplication
from jinja2 import Environment, FileSystemLoader

class EmailService:
    def __init__(
        self,
        smtp_host: str,
        smtp_port: int,
        smtp_user: str,
        smtp_password: str,
        from_email: str,
        from_name: str = 'VBWD'
    ):
        self._smtp_host = smtp_host
        self._smtp_port = smtp_port
        self._smtp_user = smtp_user
        self._smtp_password = smtp_password
        self._from_email = from_email
        self._from_name = from_name
        self._template_env = Environment(
            loader=FileSystemLoader('src/templates/email')
        )

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
        attachments: Optional[List[tuple]] = None
    ) -> bool

    def render_template(
        self,
        template_name: str,
        context: Dict[str, Any]
    ) -> tuple[str, str]  # Returns (text, html)

    # Convenience methods
    def send_welcome_email(self, user_email: str, first_name: str) -> bool

    def send_subscription_activated(
        self,
        user_email: str,
        first_name: str,
        plan_name: str,
        expires_at: datetime
    ) -> bool

    def send_subscription_cancelled(
        self,
        user_email: str,
        first_name: str,
        plan_name: str
    ) -> bool

    def send_payment_receipt(
        self,
        user_email: str,
        first_name: str,
        invoice: UserInvoice,
        pdf_bytes: bytes
    ) -> bool

    def send_payment_failed(
        self,
        user_email: str,
        first_name: str,
        plan_name: str,
        retry_url: str
    ) -> bool

    def send_invoice(
        self,
        user_email: str,
        first_name: str,
        invoice: UserInvoice,
        pdf_bytes: bytes
    ) -> bool

    def send_renewal_reminder(
        self,
        user_email: str,
        first_name: str,
        plan_name: str,
        days_until_renewal: int
    ) -> bool
```

#### 4.2 Create Email Templates

**Create directory:** `src/templates/email/`

**Templates to create:**
```
src/templates/email/
├── base.html                    # Base template with header/footer
├── base.txt                     # Plain text base
├── welcome.html                 # Welcome email
├── welcome.txt
├── subscription_activated.html  # Subscription activated
├── subscription_activated.txt
├── subscription_cancelled.html  # Subscription cancelled
├── subscription_cancelled.txt
├── payment_receipt.html         # Payment receipt
├── payment_receipt.txt
├── payment_failed.html          # Payment failed
├── payment_failed.txt
├── invoice.html                 # Invoice email
├── invoice.txt
├── renewal_reminder.html        # Renewal reminder
└── renewal_reminder.txt
```

#### 4.3 Wire Email to Event Handlers

**Test First:** `tests/unit/handlers/test_email_handlers.py`
```python
class TestEmailEventHandlers:

    def test_user_created_sends_welcome_email(self):
        """UserCreatedEvent triggers welcome email"""

    def test_subscription_activated_sends_email(self):
        """SubscriptionActivatedEvent triggers confirmation email"""

    def test_subscription_cancelled_sends_email(self):
        """SubscriptionCancelledEvent triggers cancellation email"""

    def test_payment_completed_sends_receipt(self):
        """PaymentCompletedEvent triggers receipt email"""

    def test_payment_failed_sends_notification(self):
        """PaymentFailedEvent triggers failure notification"""

    def test_invoice_created_sends_invoice(self):
        """InvoiceCreatedEvent triggers invoice email"""
```

**Then Update Handlers:** `src/handlers/`
```python
# In user_handlers.py
class UserCreatedHandler(EventHandler):
    def __init__(self, email_service: EmailService):
        self._email_service = email_service

    def handle(self, event: UserCreatedEvent) -> HandlerResult:
        self._email_service.send_welcome_email(
            event.user_email,
            event.user_name
        )
        return HandlerResult(success=True)
```

---

## Execution Order

### Phase 1: Invoice Service (Foundation)
```
1. Write test_invoice_service.py (all tests)
2. Run tests (should fail - RED)
3. Implement InvoiceService (make tests pass - GREEN)
4. Refactor if needed
5. Run all tests to verify
```

### Phase 2: Invoice Routes
```
1. Write test_invoice_routes.py
2. Run tests (RED)
3. Implement invoices.py routes (GREEN)
4. Refactor
5. Verify all tests pass
```

### Phase 3: Email Service
```
1. Write test_email_service.py
2. Run tests (RED)
3. Implement EmailService (GREEN)
4. Create email templates
5. Refactor and verify
```

### Phase 4: Admin API
```
1. Write test_admin_users.py
2. Implement admin/users.py
3. Write test_admin_subscriptions.py
4. Implement admin/subscriptions.py
5. Write test_admin_invoices.py
6. Implement admin/invoices.py
7. Write test_admin_plans.py
8. Implement admin/plans.py
```

### Phase 5: Wire Everything
```
1. Update event handlers to use EmailService
2. Write integration tests
3. Run full test suite
4. Verify in Docker
```

---

## Test Commands

```bash
# Run all tests
cd /home/dtkachev/dantweb/vbwd-sdk/vbwd-backend
docker-compose run --rm python-test pytest tests/ -v

# Run specific test file
docker-compose run --rm python-test pytest tests/unit/services/test_invoice_service.py -v

# Run with coverage
docker-compose run --rm python-test pytest tests/ --cov=src --cov-report=html

# Run single test
docker-compose run --rm python-test pytest tests/unit/services/test_invoice_service.py::TestInvoiceService::test_create_invoice_success -v
```

---

## Definition of Done

Each task is DONE when:

- [ ] All tests written BEFORE implementation
- [ ] All tests pass (GREEN)
- [ ] Test coverage ≥ 95% for new code
- [ ] No linting errors (`flake8 src/`)
- [ ] Type hints present on all public methods
- [ ] Docstrings on all public classes/methods
- [ ] Code reviewed against SOLID principles
- [ ] Runs in Docker without errors
- [ ] Integration tested with real database

---

## Files to Create

### Services
- [ ] `src/services/invoice_service.py`
- [ ] `src/services/email_service.py`
- [ ] `src/services/pdf_service.py`

### Routes
- [ ] `src/routes/invoices.py`
- [ ] `src/routes/admin/__init__.py`
- [ ] `src/routes/admin/users.py`
- [ ] `src/routes/admin/subscriptions.py`
- [ ] `src/routes/admin/invoices.py`
- [ ] `src/routes/admin/plans.py`

### Templates
- [ ] `src/templates/email/base.html`
- [ ] `src/templates/email/welcome.html`
- [ ] `src/templates/email/subscription_activated.html`
- [ ] `src/templates/email/subscription_cancelled.html`
- [ ] `src/templates/email/payment_receipt.html`
- [ ] `src/templates/email/payment_failed.html`
- [ ] `src/templates/email/invoice.html`
- [ ] `src/templates/email/renewal_reminder.html`

### Tests
- [ ] `tests/unit/services/test_invoice_service.py`
- [ ] `tests/unit/services/test_email_service.py`
- [ ] `tests/unit/services/test_pdf_service.py`
- [ ] `tests/unit/routes/test_invoice_routes.py`
- [ ] `tests/unit/routes/test_admin_users.py`
- [ ] `tests/unit/routes/test_admin_subscriptions.py`
- [ ] `tests/unit/routes/test_admin_invoices.py`
- [ ] `tests/unit/routes/test_admin_plans.py`
- [ ] `tests/unit/handlers/test_email_handlers.py`

---

## Estimated Time

| Task | Estimate |
|------|----------|
| Invoice Service + Tests | 2-3 hours |
| Invoice Routes + Tests | 1-2 hours |
| Email Service + Tests | 2-3 hours |
| Email Templates | 1 hour |
| Admin Users API | 1-2 hours |
| Admin Subscriptions API | 1-2 hours |
| Admin Invoices API | 1-2 hours |
| Admin Plans API | 1 hour |
| Integration & Wiring | 1-2 hours |
| **Total** | **12-18 hours** |
