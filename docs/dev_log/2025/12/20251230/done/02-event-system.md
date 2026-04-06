# Sprint 2: Event System Completion

**Priority:** HIGH
**Duration:** 1-2 days
**Focus:** Complete event handlers and implement frontend Event Bus

> **Core Requirements:** See [sprint-plan.md](./sprint-plan.md) for mandatory TDD-first, SOLID, DI, Clean Code, and No Over-Engineering requirements.

---

## Event-Driven Architecture Overview

The entire system uses **event-driven architecture**. Routes emit events, handlers process them and call services.

### Event Flow Pattern
```
┌─────────┐     ┌─────────────────┐     ┌────────────────┐     ┌─────────┐     ┌──────────┐
│ Route   │ ──▶ │ EventDispatcher │ ──▶ │ Handler 1      │ ──▶ │ Service │ ──▶ │ Database │
│ (emit)  │     │                 │     │ (orchestrate)  │     │ (logic) │     │          │
└─────────┘     │                 │ ──▶ ├────────────────┤     └─────────┘     └──────────┘
                │                 │     │ Handler 2      │
                │                 │ ──▶ │ (side effects) │
                └─────────────────┘     └────────────────┘
```

### Key Principles
1. **Routes emit events** - Routes do NOT call services directly
2. **Handlers orchestrate** - Handlers call services and perform side effects
3. **Services are pure** - Services contain business logic, no event emission
4. **Decoupled** - Each layer only knows about the next layer

### Event Categories

| Category | Events | Handlers |
|----------|--------|----------|
| **User** | UserRegistered, UserUpdated, UserDeleted | Email, Subscription, Activity |
| **Security** | PasswordResetRequested/Completed/Failed, LoginFailed | Email, Activity, Alerting |
| **Subscription** | Created, Updated, Cancelled, Expired | Email, Billing, Analytics |
| **Payment** | Created, Succeeded, Failed, Refunded | Email, Subscription, Accounting |
| **Plugin** | Registered, Initialized, Error, Stopped | Logging, Monitoring |

### Dependencies
- **Sprint 1** defines security events (PasswordResetRequested, etc.)
- **Sprint 3** defines payment/plugin events (PaymentSucceeded, etc.)
- **This Sprint** completes all handlers

---

## 2.0 Security Event Handlers

> **Note:** Security events are defined in Sprint 1. This section implements the handlers.

### TDD Tests First

**File:** `tests/unit/services/events/handlers/test_security_handlers.py`
```python
class TestSecurityEventHandler:
    def test_handles_password_reset_requested_sends_email(self):
        """Reset email sent when PasswordResetRequestedEvent received."""
        pass

    def test_handles_password_reset_completed_logs_activity(self):
        """Activity logged when password reset succeeds."""
        pass

    def test_handles_password_reset_failed_logs_attempt(self):
        """Failed attempt logged for security monitoring."""
        pass

    def test_handles_login_failed_increments_counter(self):
        """Failed login tracked for rate limiting."""
        pass

    def test_handles_login_failed_sends_alert_after_threshold(self):
        """Alert sent after multiple failed logins."""
        pass
```

### Implementation

**File:** `src/services/events/handlers/security_handlers.py`
```python
from src.services.events.security_events import (
    PasswordResetRequestedEvent,
    PasswordResetCompletedEvent,
    PasswordResetFailedEvent,
    LoginFailedEvent,
)
from src.services.email_service import EmailService
from src.services.activity_logger import ActivityLogger
from src.services.security_monitor import SecurityMonitor

class SecurityEventHandler:
    """Handles security-related events."""

    def __init__(
        self,
        email_service: EmailService,
        activity_logger: ActivityLogger,
        security_monitor: SecurityMonitor,
        reset_url_base: str,
    ):
        self.email_service = email_service
        self.activity_logger = activity_logger
        self.security_monitor = security_monitor
        self.reset_url_base = reset_url_base

    def handle_password_reset_requested(self, event: PasswordResetRequestedEvent) -> None:
        """Send password reset email."""
        reset_url = f"{self.reset_url_base}?token={event.token}"

        self.email_service.send_template(
            to=event.email,
            template="password_reset",
            context={"reset_url": reset_url, "expires_in": "1 hour"}
        )

        self.activity_logger.log(
            action="password_reset_requested",
            user_id=event.user_id,
            metadata={"ip": event.request_ip}
        )

    def handle_password_reset_completed(self, event: PasswordResetCompletedEvent) -> None:
        """Log and notify on successful password reset."""
        self.activity_logger.log(
            action="password_reset_completed",
            user_id=event.user_id,
            metadata={"ip": event.reset_ip}
        )

        self.email_service.send_template(
            to=event.email,
            template="password_changed",
            context={}
        )

    def handle_password_reset_failed(self, event: PasswordResetFailedEvent) -> None:
        """Log failed reset attempt."""
        self.activity_logger.log(
            action="password_reset_failed",
            metadata={"reason": event.reason, "ip": event.attempt_ip}
        )

    def handle_login_failed(self, event: LoginFailedEvent) -> None:
        """Track failed login for security monitoring."""
        self.security_monitor.record_failed_login(
            email=event.email,
            ip=event.ip,
            reason=event.reason
        )

        # Alert after threshold
        if self.security_monitor.should_alert(event.email):
            self.email_service.send_template(
                to=event.email,
                template="suspicious_login_activity",
                context={"ip": event.ip}
            )
```

### Handler Registration

**File:** `src/services/events/handlers/__init__.py`
```python
from src.services.events.dispatcher import EventDispatcher
from src.services.events.security_events import (
    PasswordResetRequestedEvent,
    PasswordResetCompletedEvent,
    PasswordResetFailedEvent,
    LoginFailedEvent,
)
from .security_handlers import SecurityEventHandler

def register_security_handlers(dispatcher: EventDispatcher, container) -> None:
    """Register all security event handlers."""
    handler = SecurityEventHandler(
        email_service=container.email_service(),
        activity_logger=container.activity_logger(),
        security_monitor=container.security_monitor(),
        reset_url_base=container.config.RESET_URL_BASE,
    )

    dispatcher.register(PasswordResetRequestedEvent, handler.handle_password_reset_requested)
    dispatcher.register(PasswordResetCompletedEvent, handler.handle_password_reset_completed)
    dispatcher.register(PasswordResetFailedEvent, handler.handle_password_reset_failed)
    dispatcher.register(LoginFailedEvent, handler.handle_login_failed)
```

---

## 2.1 Complete User Event Handlers

### Problem
User event handlers are stubbed - they log but don't perform actions.

### Architecture
```
Route (register) → emit UserRegisterEvent → Dispatcher → UserHandler → Services → DB
```

### Current State
```python
# src/handlers/user_handlers.py
class UserEventHandler:
    def handle_user_registered(self, event: UserRegisteredEvent):
        logger.info(f"User registered: {event.user_id}")
        # TODO: Call services to do actual work
```

### Requirements
- Handler calls UserService to create user
- Handler calls EmailService to send welcome email
- Handler calls SubscriptionService to create free tier
- Handler logs activity

### TDD Tests First

**File:** `tests/unit/handlers/test_user_handlers.py`
```python
class TestUserEventHandler:
    def test_handle_user_register_creates_user(self):
        """User created via UserService when event received."""
        pass

    def test_handle_user_register_sends_welcome_email(self):
        """Welcome email sent after user created."""
        pass

    def test_handle_user_register_creates_default_subscription(self):
        """Free tier subscription created for new user."""
        pass

    def test_handle_user_register_returns_result(self):
        """Handler returns EventResult with user_id."""
        pass
```

### Implementation

**Files to modify:**
- `src/handlers/user_handlers.py` - COMPLETE implementation

**Handler Logic:**
```python
from src.events.domain import EventResult

class UserEventHandler:
    """
    Handles user events.

    Flow: Route emits event → This handler → Calls services → Returns result
    """

    def __init__(self, user_service, email_service, subscription_service, activity_logger):
        self.user_service = user_service
        self.email_service = email_service
        self.subscription_service = subscription_service
        self.activity_logger = activity_logger

    def handle_user_register(self, event: UserRegisterEvent) -> EventResult:
        # 1. Call service to create user
        result = self.user_service.create_user(event.email, event.password)

        if not result.success:
            return EventResult.error_result(result.error)

        # 2. Send welcome email
        self.email_service.send_welcome(result.user.email)

        # 3. Create free tier subscription
        self.subscription_service.create_free_subscription(result.user.id)

        # 4. Log activity
        self.activity_logger.log("user_registered", user_id=result.user.id)

        return EventResult.success_result({
            "user_id": str(result.user.id),
            "token": result.token
        })
```

---

## 2.2 Complete Subscription Event Handlers

### Problem
Subscription handlers are stubbed without actual business logic.

### Requirements
- Email notifications on subscription changes
- Invoice generation on subscription creation
- Proration calculation on plan changes
- Grace period handling on cancellation

### TDD Tests First

**File:** `tests/unit/services/events/handlers/test_subscription_handlers.py`
```python
class TestSubscriptionEventHandler:
    def test_handle_subscription_created_sends_confirmation(self):
        """Confirmation email on new subscription."""
        pass

    def test_handle_subscription_created_generates_invoice(self):
        """Invoice generated for paid subscriptions."""
        pass

    def test_handle_plan_changed_calculates_proration(self):
        """Proration calculated on plan upgrade/downgrade."""
        pass

    def test_handle_subscription_cancelled_starts_grace_period(self):
        """Grace period started on cancellation."""
        pass

    def test_handle_subscription_expired_downgrades_to_free(self):
        """User downgraded to free tier on expiration."""
        pass
```

### Implementation

**Files to modify:**
- `src/services/events/handlers/subscription_handlers.py` - COMPLETE implementation

---

## 2.3 Complete Payment Event Handlers

### Problem
Payment handlers are stubbed without webhook processing.

### Requirements
- Payment success confirmation emails
- Payment failure retry notifications
- Refund processing
- Invoice PDF generation

### TDD Tests First

**File:** `tests/unit/services/events/handlers/test_payment_handlers.py`
```python
class TestPaymentEventHandler:
    def test_handle_payment_succeeded_sends_receipt(self):
        """Receipt email sent on successful payment."""
        pass

    def test_handle_payment_succeeded_activates_subscription(self):
        """Subscription activated after payment."""
        pass

    def test_handle_payment_failed_notifies_user(self):
        """User notified of payment failure."""
        pass

    def test_handle_payment_failed_schedules_retry(self):
        """Failed payment scheduled for retry."""
        pass

    def test_handle_refund_processed_updates_subscription(self):
        """Subscription updated after refund."""
        pass
```

### Implementation

**Files to modify:**
- `src/services/events/handlers/payment_handlers.py` - COMPLETE implementation

---

## 2.4 Frontend Event Bus

### Problem
Frontend apps lack decoupled event communication.

### Requirements
- Typed event bus for Vue apps
- Cross-component communication
- WebSocket event integration
- Event history for debugging

### Implementation

**File:** `vbwd-frontend/core/src/events/EventBus.ts`
```typescript
type EventCallback<T = any> = (payload: T) => void;

interface EventBusOptions {
  debug?: boolean;
  maxHistory?: number;
}

export class EventBus {
  private listeners: Map<string, Set<EventCallback>> = new Map();
  private history: Array<{ event: string; payload: any; timestamp: Date }> = [];
  private options: EventBusOptions;

  constructor(options: EventBusOptions = {}) {
    this.options = { debug: false, maxHistory: 100, ...options };
  }

  emit<T>(event: string, payload?: T): void {
    if (this.options.debug) {
      console.log(`[EventBus] ${event}`, payload);
    }

    this.history.push({ event, payload, timestamp: new Date() });
    if (this.history.length > this.options.maxHistory!) {
      this.history.shift();
    }

    const callbacks = this.listeners.get(event);
    if (callbacks) {
      callbacks.forEach(cb => cb(payload));
    }
  }

  on<T>(event: string, callback: EventCallback<T>): () => void {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    this.listeners.get(event)!.add(callback);

    // Return unsubscribe function
    return () => this.off(event, callback);
  }

  off(event: string, callback: EventCallback): void {
    this.listeners.get(event)?.delete(callback);
  }

  once<T>(event: string, callback: EventCallback<T>): void {
    const wrapper = (payload: T) => {
      callback(payload);
      this.off(event, wrapper);
    };
    this.on(event, wrapper);
  }

  getHistory(): Array<{ event: string; payload: any; timestamp: Date }> {
    return [...this.history];
  }

  clear(): void {
    this.listeners.clear();
    this.history = [];
  }
}

// Singleton instance
export const eventBus = new EventBus({ debug: process.env.NODE_ENV === 'development' });
```

**File:** `vbwd-frontend/core/src/events/events.ts`
```typescript
// Typed event definitions
export const AppEvents = {
  // Auth events
  AUTH_LOGIN: 'auth:login',
  AUTH_LOGOUT: 'auth:logout',
  AUTH_TOKEN_REFRESHED: 'auth:token-refreshed',

  // Subscription events
  SUBSCRIPTION_CREATED: 'subscription:created',
  SUBSCRIPTION_UPGRADED: 'subscription:upgraded',
  SUBSCRIPTION_CANCELLED: 'subscription:cancelled',

  // Payment events
  PAYMENT_SUCCEEDED: 'payment:succeeded',
  PAYMENT_FAILED: 'payment:failed',

  // UI events
  NOTIFICATION_SHOW: 'notification:show',
  MODAL_OPEN: 'modal:open',
  MODAL_CLOSE: 'modal:close',
} as const;

// Event payload types
export interface AuthLoginPayload {
  userId: string;
  email: string;
}

export interface SubscriptionPayload {
  subscriptionId: string;
  planName: string;
}

export interface NotificationPayload {
  type: 'success' | 'error' | 'warning' | 'info';
  message: string;
  duration?: number;
}
```

**Files to create:**
- `vbwd-frontend/core/src/events/EventBus.ts` - CREATE
- `vbwd-frontend/core/src/events/events.ts` - CREATE
- `vbwd-frontend/core/src/events/index.ts` - CREATE (exports)

---

## Checklist

### 2.0 Security Handlers
- [ ] Tests written for SecurityEventHandler
- [ ] Password reset requested handler (sends email)
- [ ] Password reset completed handler (logs activity)
- [ ] Password reset failed handler (logs attempt)
- [ ] Login failed handler (tracks attempts, alerts)
- [ ] Handler registration with EventDispatcher
- [ ] All tests pass

### 2.1 User Handlers
- [ ] Tests written for UserEventHandler
- [ ] Welcome email implementation
- [ ] Default subscription creation
- [ ] Activity logging
- [ ] All tests pass

### 2.2 Subscription Handlers
- [ ] Tests written for SubscriptionEventHandler
- [ ] Confirmation emails
- [ ] Invoice generation
- [ ] Proration logic
- [ ] Grace period handling
- [ ] All tests pass

### 2.3 Payment Handlers
- [ ] Tests written for PaymentEventHandler
- [ ] Receipt emails
- [ ] Failure notifications
- [ ] Retry scheduling
- [ ] Refund processing
- [ ] All tests pass

### 2.4 Frontend Event Bus
- [ ] EventBus class implemented
- [ ] Typed events defined
- [ ] Tests for EventBus
- [ ] Integrated into Core SDK exports
- [ ] Documentation added

---

## Verification Commands

```bash
# Run event handler tests
docker-compose --profile test run --rm test pytest tests/unit/services/events/handlers/ -v

# Run Core SDK tests
cd vbwd-frontend/core
npm test

# Check event bus exports
grep -r "EventBus" vbwd-frontend/core/src/index.ts
```
