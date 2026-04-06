# Sprint 1: Security Fixes

**Priority:** CRITICAL
**Duration:** 1 day
**Focus:** Address high-severity security vulnerabilities

> **Core Requirements:** See [sprint-plan.md](./sprint-plan.md) for mandatory TDD-first, SOLID, DI, Clean Code, and No Over-Engineering requirements.

---

## Event-Driven Architecture Note

All security operations use the **event-driven pattern**:
- Routes emit events (e.g., `PasswordResetRequestedEvent`)
- Event Dispatcher routes to Handler(s)
- Handlers call Services to perform business logic
- Services interact with Database
- Decoupled, testable, extensible

```
Request → Route (emit event) → Event Dispatcher → Handler(s) → Services → Database
```

---

## 1.1 Password Reset Flow (Event-Driven)

### Problem
Users cannot recover their accounts if they forget their password.

### Architecture
```
┌─────────────┐      ┌─────────────────────┐      ┌─────────────────────────┐      ┌──────────────────────┐
│   Route     │ ───▶ │   EventDispatcher   │ ───▶ │ PasswordResetHandler    │ ───▶ │ PasswordResetService │
│ /forgot-pwd │      │                     │      │                         │      │                      │
│             │      │ emit:               │      │ 1. Validate request     │      │ 1. Generate token    │
│ emit event  │      │ PasswordResetReq    │      │ 2. Call service         │      │ 2. Store token       │
└─────────────┘      └─────────────────────┘      │ 3. Send reset email     │      │ 3. Return result     │
                                                   │ 4. Log activity         │      └──────────┬───────────┘
                                                   └─────────────────────────┘                 │
                                                                                               ▼
                                                                                          Database
```

### Events

**File:** `src/events/security_events.py`

> **Note:** Events carry request data from routes to handlers. They are simple data containers.

```python
from dataclasses import dataclass
from src.events.core.base import BaseEvent

@dataclass
class PasswordResetRequestEvent(BaseEvent):
    """
    Emitted by route when user requests password reset.

    Route emits → Handler receives → Handler calls service → Service creates token
    """
    name: str = "security.password_reset.request"
    email: str = ""
    request_ip: str = None

@dataclass
class PasswordResetExecuteEvent(BaseEvent):
    """
    Emitted by route when user submits new password with token.

    Route emits → Handler receives → Handler calls service → Service resets password
    """
    name: str = "security.password_reset.execute"
    token: str = ""
    new_password: str = ""
    reset_ip: str = None
```

### TDD Tests First

**File:** `tests/unit/services/test_password_reset_service.py`
```python
class TestPasswordResetService:
    def test_request_reset_creates_token(self):
        """Token created and stored for valid email."""
        pass

    def test_request_reset_emits_event(self):
        """PasswordResetRequestedEvent emitted with token."""
        pass

    def test_request_reset_invalid_email_no_event(self):
        """No event emitted for unknown email (security)."""
        pass

    def test_reset_token_expires_after_one_hour(self):
        """Token should be invalid after 1 hour."""
        pass

    def test_reset_password_with_valid_token(self):
        """Password reset succeeds with valid token."""
        pass

    def test_reset_password_emits_completed_event(self):
        """PasswordResetCompletedEvent emitted on success."""
        pass

    def test_reset_password_with_expired_token_emits_failed(self):
        """PasswordResetFailedEvent emitted with reason=expired."""
        pass

    def test_reset_password_with_invalid_token_emits_failed(self):
        """PasswordResetFailedEvent emitted with reason=invalid."""
        pass

    def test_token_is_single_use(self):
        """Token cannot be reused after password reset."""
        pass
```

**File:** `tests/unit/services/events/handlers/test_password_reset_handler.py`
```python
class TestPasswordResetHandler:
    def test_handles_reset_requested_sends_email(self):
        """Email sent when PasswordResetRequestedEvent received."""
        pass

    def test_handles_reset_completed_logs_activity(self):
        """Activity logged when PasswordResetCompletedEvent received."""
        pass

    def test_handles_reset_failed_logs_attempt(self):
        """Failed attempt logged for security monitoring."""
        pass
```

### Service Implementation

**File:** `src/services/password_reset_service.py`

> **Note:** Service contains pure business logic. It does NOT emit events - that's the route's job.

```python
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional
import secrets

from src.repositories.user_repository import UserRepository
from src.repositories.password_reset_repository import PasswordResetRepository

@dataclass
class ResetRequestResult:
    success: bool
    user_id: Optional[str] = None
    email: Optional[str] = None
    token: Optional[str] = None
    expires_at: Optional[datetime] = None
    error: Optional[str] = None

@dataclass
class ResetResult:
    success: bool
    user_id: Optional[str] = None
    email: Optional[str] = None
    error: Optional[str] = None
    failure_reason: Optional[str] = None  # "invalid", "expired", "already_used"

class PasswordResetService:
    """Pure business logic for password reset. Does NOT emit events."""

    TOKEN_EXPIRY_HOURS = 1

    def __init__(
        self,
        user_repository: UserRepository,
        reset_repository: PasswordResetRepository,
    ):
        self.user_repo = user_repository
        self.reset_repo = reset_repository

    def create_reset_token(self, email: str) -> ResetRequestResult:
        """Create password reset token. Returns data for event emission."""
        user = self.user_repo.get_by_email(email)

        if not user:
            # Don't reveal if email exists - return success but no data
            return ResetRequestResult(success=True)

        # Invalidate any existing tokens
        self.reset_repo.invalidate_tokens_for_user(user.id)

        # Generate secure token
        token = secrets.token_urlsafe(32)
        expires_at = datetime.utcnow() + timedelta(hours=self.TOKEN_EXPIRY_HOURS)

        # Store token
        self.reset_repo.create_token(
            user_id=user.id,
            token=token,
            expires_at=expires_at
        )

        return ResetRequestResult(
            success=True,
            user_id=str(user.id),
            email=user.email,
            token=token,
            expires_at=expires_at
        )

    def reset_password(self, token: str, new_password: str) -> ResetResult:
        """Reset password using token. Returns data for event emission."""
        reset_token = self.reset_repo.get_by_token(token)

        if not reset_token:
            return ResetResult(
                success=False,
                error="Invalid token",
                failure_reason="invalid"
            )

        if reset_token.expires_at < datetime.utcnow():
            return ResetResult(
                success=False,
                error="Token expired",
                failure_reason="expired"
            )

        if reset_token.used_at is not None:
            return ResetResult(
                success=False,
                error="Token already used",
                failure_reason="already_used"
            )

        # Get user and update password
        user = self.user_repo.get_by_id(reset_token.user_id)
        user.set_password(new_password)
        self.user_repo.update(user)

        # Mark token as used
        self.reset_repo.mark_used(reset_token.id)

        return ResetResult(
            success=True,
            user_id=str(user.id),
            email=user.email
        )
```

### Event Handler Implementation

**File:** `src/handlers/password_reset_handler.py`

> **Note:** Handler receives events from route, calls services, and performs side effects.

```python
from src.events.security_events import (
    PasswordResetRequestEvent,
    PasswordResetExecuteEvent,
)
from src.events.domain import EventResult
from src.services.password_reset_service import PasswordResetService
from src.services.email_service import EmailService
from src.services.activity_logger import ActivityLogger

class PasswordResetHandler:
    """
    Handles password reset events.

    Flow:
    1. Route emits event → 2. This handler receives it → 3. Calls service → 4. Side effects
    """

    def __init__(
        self,
        password_reset_service: PasswordResetService,
        email_service: EmailService,
        activity_logger: ActivityLogger,
        reset_url_base: str = "https://app.example.com/reset-password"
    ):
        self.reset_service = password_reset_service
        self.email_service = email_service
        self.activity_logger = activity_logger
        self.reset_url_base = reset_url_base

    def handle_reset_request(self, event: PasswordResetRequestEvent) -> EventResult:
        """
        Handle password reset request.

        1. Call service to create token
        2. Send email if user exists
        3. Log activity
        """
        # Call service
        result = self.reset_service.create_reset_token(event.email)

        if result.success and result.token:
            # User exists - send email
            reset_url = f"{self.reset_url_base}?token={result.token}"

            self.email_service.send_template(
                to=result.email,
                template="password_reset",
                context={
                    "reset_url": reset_url,
                    "expires_in": "1 hour",
                }
            )

            self.activity_logger.log(
                action="password_reset_requested",
                user_id=result.user_id,
                metadata={"ip": event.request_ip}
            )

        # Always return success (don't reveal if email exists)
        return EventResult.success_result({"message": "If email exists, reset link sent"})

    def handle_reset_execute(self, event: PasswordResetExecuteEvent) -> EventResult:
        """
        Handle password reset execution.

        1. Call service to reset password
        2. Send confirmation or log failure
        """
        result = self.reset_service.reset_password(event.token, event.new_password)

        if result.success:
            # Send confirmation email
            self.email_service.send_template(
                to=result.email,
                template="password_changed",
                context={}
            )

            self.activity_logger.log(
                action="password_reset_completed",
                user_id=result.user_id,
                metadata={"ip": event.reset_ip}
            )

            return EventResult.success_result({"message": "Password reset successful"})
        else:
            # Log failed attempt
            self.activity_logger.log(
                action="password_reset_failed",
                metadata={
                    "reason": result.failure_reason,
                    "ip": event.reset_ip,
                    "token_prefix": event.token[:8] + "..."
                }
            )

            return EventResult.error_result(
                error=result.error,
                error_type=result.failure_reason
            )
```

### Handler Registration

**File:** `src/handlers/__init__.py` (addition)
```python
from src.events.core.dispatcher import EnhancedEventDispatcher
from src.events.security_events import (
    PasswordResetRequestEvent,
    PasswordResetExecuteEvent,
)
from src.handlers.password_reset_handler import PasswordResetHandler

def register_security_handlers(dispatcher: EnhancedEventDispatcher, container):
    """Register security-related event handlers."""
    handler = PasswordResetHandler(
        password_reset_service=container.password_reset_service(),
        email_service=container.email_service(),
        activity_logger=container.activity_logger(),
        reset_url_base=container.config.RESET_URL_BASE
    )

    dispatcher.register(handler)  # Handler declares which events it handles
```

### Routes

**File:** `src/routes/auth.py` (additions)

> **Note:** Routes emit events and return dispatcher results. They do NOT call services directly.

```python
from flask import current_app
from src.events.security_events import (
    PasswordResetRequestEvent,
    PasswordResetExecuteEvent,
)

@auth_bp.route("/forgot-password", methods=["POST"])
def forgot_password():
    """
    Request password reset.

    Flow: Route → emit event → Dispatcher → Handler → Service → DB
    """
    data = request.get_json()
    email = data.get("email")

    if not email:
        return jsonify({"error": "Email required"}), 400

    # Emit event - handler will do the work
    dispatcher = current_app.container.event_dispatcher()
    result = dispatcher.dispatch(
        PasswordResetRequestEvent(
            email=email,
            request_ip=request.remote_addr
        )
    )

    # Always return success (don't reveal if email exists)
    return jsonify(result.data or {"message": "If email exists, reset link sent"})

@auth_bp.route("/reset-password", methods=["POST"])
def reset_password():
    """
    Execute password reset with token.

    Flow: Route → emit event → Dispatcher → Handler → Service → DB
    """
    data = request.get_json()
    token = data.get("token")
    new_password = data.get("new_password")

    if not token or not new_password:
        return jsonify({"error": "Token and new password required"}), 400

    # Emit event - handler will do the work
    dispatcher = current_app.container.event_dispatcher()
    result = dispatcher.dispatch(
        PasswordResetExecuteEvent(
            token=token,
            new_password=new_password,
            reset_ip=request.remote_addr
        )
    )

    if result.success:
        return jsonify(result.data or {"message": "Password reset successful"})
    return jsonify({"error": result.error}), 400
```

### Model

**File:** `src/models/password_reset_token.py`
```python
from src.extensions import db
from src.models.base import BaseModel

class PasswordResetToken(BaseModel):
    __tablename__ = "password_reset_token"

    user_id = db.Column(db.UUID, db.ForeignKey("user.id"), nullable=False)
    token = db.Column(db.String(64), unique=True, nullable=False, index=True)
    expires_at = db.Column(db.DateTime, nullable=False)
    used_at = db.Column(db.DateTime, nullable=True)

    user = db.relationship("User", backref="reset_tokens")
```

---

## 1.2 CSRF Protection

### Problem
Forms are vulnerable to Cross-Site Request Forgery attacks.

### Requirements
- CSRF token generation
- Token validation on state-changing requests
- Integration with Flask-WTF or custom implementation

### Implementation

**Option A: Flask-WTF (Recommended)**
```bash
# Add to requirements.txt
Flask-WTF==1.2.1
```

**Files to modify:**
- `requirements.txt` - ADD Flask-WTF
- `src/app.py` - CONFIGURE CSRFProtect
- `src/routes/*.py` - EXEMPT API routes (JWT auth instead)

**Configuration:**
```python
from flask_wtf.csrf import CSRFProtect

csrf = CSRFProtect()

def create_app():
    # ...
    csrf.init_app(app)

    # Exempt API routes (they use JWT)
    csrf.exempt(auth_bp)
    csrf.exempt(user_bp)
    # etc.
```

**Option B: Double-Submit Cookie (for SPAs)**
- Generate CSRF token in cookie
- Require token in X-CSRF-Token header
- Compare values on server

---

## 1.3 Remove Hardcoded Admin Hint

### Problem
Login.vue contains hardcoded admin credentials hint.

### Location
`vbwd-frontend/admin/vue/src/views/Login.vue`

### Fix
```vue
<!-- REMOVE THIS -->
<p class="hint">Demo: admin@example.com / admin123</p>
```

### Verification
```bash
grep -r "admin@example.com" vbwd-frontend/
grep -r "admin123" vbwd-frontend/
# Should return no results
```

---

## 1.4 HttpOnly Cookie Option (Optional)

### Problem
JWT stored in localStorage is vulnerable to XSS.

### Current State
```javascript
// admin/vue/src/stores/auth.js
localStorage.setItem('admin_token', this.token)
```

### Recommended Solution
Use httpOnly cookies for token storage:

**Backend changes:**
```python
@auth_bp.route('/login', methods=['POST'])
def login():
    # ... validate credentials ...

    response = jsonify({"success": True, "user": user_data})
    response.set_cookie(
        'access_token',
        token,
        httponly=True,
        secure=True,  # HTTPS only
        samesite='Lax',
        max_age=3600
    )
    return response
```

**Frontend changes:**
```javascript
// No token handling needed - browser sends cookie automatically
// Just remove localStorage logic
```

### Trade-offs
- **Pro:** More secure against XSS
- **Con:** Requires CSRF protection (added in 1.2)
- **Con:** More complex logout (need endpoint to clear cookie)

---

## Checklist

### 1.1 Password Reset (Event-Driven)
- [ ] Security events defined (PasswordResetRequested/Completed/Failed)
- [ ] Tests written for PasswordResetService
- [ ] Tests written for PasswordResetHandler
- [ ] PasswordResetToken model created
- [ ] PasswordResetService implemented (emits events)
- [ ] PasswordResetHandler implemented (sends emails)
- [ ] Handler registered with EventDispatcher
- [ ] Auth routes updated
- [ ] Email templates created
- [ ] Integration tested

### 1.2 CSRF Protection
- [ ] Flask-WTF added to requirements
- [ ] CSRFProtect configured
- [ ] API routes exempted (JWT auth)
- [ ] Tested with form submissions

### 1.3 Admin Hint Removal
- [ ] Hardcoded hint removed from Login.vue
- [ ] Grep verification passed

### 1.4 HttpOnly Cookies (Optional)
- [ ] Cookie-based auth endpoint created
- [ ] Frontend updated to not use localStorage
- [ ] Logout endpoint clears cookie
- [ ] CSRF integration verified

---

## Verification Commands

```bash
# Run security-related tests
docker-compose --profile test run --rm test pytest tests/unit/services/test_password_reset_service.py -v
docker-compose --profile test run --rm test pytest tests/unit/services/events/handlers/test_password_reset_handler.py -v

# Check for hardcoded credentials
grep -rn "admin123\|demo\|password" vbwd-frontend/ --include="*.vue" --include="*.js"

# Verify CSRF is active
curl -X POST http://localhost:5000/api/v1/auth/login -H "Content-Type: application/json" -d '{"email":"test","password":"test"}'
# Should work (API exempt from CSRF)
```
