# Task 2: Email Notification Service

**Priority:** HIGH
**Current:** 0% → **Target:** 100%
**Estimated Time:** 3-4 hours

---

## Prerequisites
- [ ] EmailService - TO CREATE
- [ ] Email templates - TO CREATE
- [x] Event handlers exist (need wiring)
- [x] SMTP config in .env

---

## TDD Checklist

### Step 1: Create Test File (RED)

Create `tests/unit/services/test_email_service.py`:

```bash
docker-compose run --rm python-test pytest tests/unit/services/test_email_service.py -v
# Expected: All tests FAIL
```

**Tests to write:**

#### Configuration Tests
- [ ] `test_service_initializes_with_smtp_config`
- [ ] `test_service_validates_smtp_config`
- [ ] `test_service_handles_missing_config`

#### Core Send Tests
- [ ] `test_send_email_success`
- [ ] `test_send_email_with_html`
- [ ] `test_send_email_with_attachment`
- [ ] `test_send_email_failure_logged`
- [ ] `test_send_email_invalid_recipient`

#### Template Tests
- [ ] `test_render_template_success`
- [ ] `test_render_template_not_found`
- [ ] `test_render_template_with_context`

#### Specific Email Tests
- [ ] `test_send_welcome_email`
- [ ] `test_send_subscription_activated_email`
- [ ] `test_send_subscription_cancelled_email`
- [ ] `test_send_payment_receipt_email`
- [ ] `test_send_payment_failed_email`
- [ ] `test_send_invoice_email`
- [ ] `test_send_renewal_reminder_email`

---

### Step 2: Implement Service (GREEN)

Create `src/services/email_service.py`:

```python
import smtplib
import logging
from typing import Optional, List, Dict, Any, Tuple
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.application import MIMEApplication
from datetime import datetime
from jinja2 import Environment, FileSystemLoader, TemplateNotFound

logger = logging.getLogger(__name__)

class EmailResult:
    def __init__(self, success: bool, error: Optional[str] = None):
        self.success = success
        self.error = error

class EmailService:
    """Service for sending emails via SMTP."""

    def __init__(
        self,
        smtp_host: str,
        smtp_port: int,
        smtp_user: str,
        smtp_password: str,
        from_email: str,
        from_name: str = 'VBWD',
        template_dir: str = 'src/templates/email'
    ):
        self._smtp_host = smtp_host
        self._smtp_port = smtp_port
        self._smtp_user = smtp_user
        self._smtp_password = smtp_password
        self._from_email = from_email
        self._from_name = from_name

        self._template_env = Environment(
            loader=FileSystemLoader(template_dir),
            autoescape=True
        )

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
        attachments: Optional[List[Tuple[str, bytes, str]]] = None
    ) -> EmailResult:
        """
        Send email via SMTP.

        Args:
            to_email: Recipient email address
            subject: Email subject
            body_text: Plain text body
            body_html: Optional HTML body
            attachments: List of (filename, data, mime_type) tuples

        Returns:
            EmailResult with success status
        """
        pass  # Implement

    def render_template(
        self,
        template_name: str,
        context: Dict[str, Any]
    ) -> Tuple[str, str]:
        """
        Render email template.

        Returns:
            Tuple of (plain_text, html)
        """
        pass  # Implement

    # Convenience methods
    def send_welcome_email(
        self,
        to_email: str,
        first_name: str
    ) -> EmailResult:
        """Send welcome email to new user."""
        pass

    def send_subscription_activated(
        self,
        to_email: str,
        first_name: str,
        plan_name: str,
        expires_at: datetime
    ) -> EmailResult:
        """Send subscription activation confirmation."""
        pass

    def send_subscription_cancelled(
        self,
        to_email: str,
        first_name: str,
        plan_name: str
    ) -> EmailResult:
        """Send subscription cancellation confirmation."""
        pass

    def send_payment_receipt(
        self,
        to_email: str,
        first_name: str,
        invoice_number: str,
        amount: str,
        pdf_bytes: Optional[bytes] = None
    ) -> EmailResult:
        """Send payment receipt with optional PDF."""
        pass

    def send_payment_failed(
        self,
        to_email: str,
        first_name: str,
        plan_name: str,
        retry_url: str
    ) -> EmailResult:
        """Send payment failure notification."""
        pass

    def send_invoice(
        self,
        to_email: str,
        first_name: str,
        invoice_number: str,
        amount: str,
        due_date: str,
        pdf_bytes: Optional[bytes] = None
    ) -> EmailResult:
        """Send invoice with optional PDF attachment."""
        pass

    def send_renewal_reminder(
        self,
        to_email: str,
        first_name: str,
        plan_name: str,
        days_until_renewal: int
    ) -> EmailResult:
        """Send renewal reminder."""
        pass
```

---

### Step 3: Create Email Templates

Create directory structure:
```bash
mkdir -p src/templates/email
```

Create `src/templates/email/base.html`:
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #007bff; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; background: #f9f9f9; }
        .footer { padding: 20px; text-align: center; font-size: 12px; color: #666; }
        .button { display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>VBWD</h1>
        </div>
        <div class="content">
            {% block content %}{% endblock %}
        </div>
        <div class="footer">
            <p>&copy; {{ year }} VBWD. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
```

Create `src/templates/email/welcome.html`:
```html
{% extends "base.html" %}
{% block content %}
<h2>Welcome, {{ first_name }}!</h2>
<p>Thank you for joining VBWD. We're excited to have you on board.</p>
<p>You can now access all the features of your account.</p>
<p><a href="{{ login_url }}" class="button">Go to Dashboard</a></p>
{% endblock %}
```

Create `src/templates/email/welcome.txt`:
```
Welcome, {{ first_name }}!

Thank you for joining VBWD. We're excited to have you on board.

You can now access all the features of your account.

Go to Dashboard: {{ login_url }}
```

**(Create similar templates for all email types)**

---

### Step 4: Wire to Event Handlers

Update `src/handlers/user_handlers.py`:
```python
class UserCreatedHandler(EventHandler):
    def __init__(self, email_service: EmailService):
        self._email_service = email_service

    def handle(self, event: UserCreatedEvent) -> HandlerResult:
        result = self._email_service.send_welcome_email(
            to_email=event.data['email'],
            first_name=event.data.get('first_name', 'User')
        )
        return HandlerResult(
            success=result.success,
            data={'email_sent': result.success}
        )
```

Create handler tests `tests/unit/handlers/test_email_handlers.py`:
- [ ] `test_user_created_sends_welcome_email`
- [ ] `test_subscription_activated_sends_email`
- [ ] `test_subscription_cancelled_sends_email`
- [ ] `test_payment_completed_sends_receipt`
- [ ] `test_payment_failed_sends_notification`

---

### Step 5: Verify

```bash
# Run all email tests
docker-compose run --rm python-test pytest tests/unit/services/test_email_service.py tests/unit/handlers/test_email_handlers.py -v

# Check coverage
docker-compose run --rm python-test pytest tests/ --cov=src/services/email_service --cov-report=term-missing
```

---

## Acceptance Criteria

- [ ] EmailService created with all methods
- [ ] All 15+ unit tests pass
- [ ] Test coverage ≥ 95%
- [ ] 8 email templates created (html + txt)
- [ ] Event handlers wired to email service
- [ ] No linting errors
- [ ] Type hints on all methods
- [ ] Docstrings present
