# Sprint 18: Payment Routes & Service Integration

**Priority:** HIGH
**Estimated Tests:** 25-30
**Dependencies:** Sprint 13-17

---

## Objective

Implement payment API routes and integrate all payment components: routes emit events, events dispatch to handlers, handlers use services and SDK adapters, webhooks trigger domain events.

---

## Core Requirements Checklist

- [ ] **TDD**: Write tests FIRST, then implement
- [ ] **SOLID**: Routes only handle HTTP, delegate to services via events
- [ ] **Liskov Interface**: Services use interfaces, not concrete implementations
- [ ] **Clean Code**: Thin routes, business logic in handlers/services
- [ ] **No Over-Engineering**: Essential endpoints only
- [ ] **Dockerized Tests**: All tests run via `make test`

---

## Deliverables

### 1. Payment Routes (TDD)

**Test First:**
```python
# tests/unit/routes/test_payment_routes.py
def test_checkout_requires_auth():
    """POST /checkout requires authentication."""

def test_checkout_validates_plan_id():
    """Checkout validates tarif_plan_id exists."""

def test_checkout_returns_checkout_url():
    """Successful checkout returns provider URL."""

def test_checkout_emits_event():
    """Checkout emits CheckoutInitiatedEvent."""

def test_payment_status_returns_status():
    """GET /payment/{id}/status returns payment status."""

def test_webhook_stripe_verifies_signature():
    """POST /webhook/stripe verifies Stripe signature."""

def test_webhook_paypal_verifies_signature():
    """POST /webhook/paypal verifies PayPal signature."""

def test_webhook_returns_200_on_success():
    """Successful webhook processing returns 200."""

def test_webhook_returns_400_on_invalid_signature():
    """Invalid signature returns 400."""
```

**Implementation:**
```python
# src/routes/payment.py
from flask import Blueprint, request, jsonify
from src.middleware.auth import require_auth
from src.events.payment_events import CheckoutInitiatedEvent
from src.events.domain import DomainEventDispatcher

payment_bp = Blueprint('payment', __name__, url_prefix='/api/v1/payment')

@payment_bp.route('/checkout', methods=['POST'])
@require_auth
def checkout():
    """Initiate checkout for a tariff plan."""
    data = request.get_json()
    tarif_plan_id = data.get('tarif_plan_id')
    provider = data.get('provider', 'stripe')

    if not tarif_plan_id:
        return jsonify({"error": "tarif_plan_id required"}), 400

    # Emit event - handler does the work
    event = CheckoutInitiatedEvent(
        user_id=request.current_user.id,
        tarif_plan_id=UUID(tarif_plan_id),
        provider=provider,
        return_url=data.get('return_url'),
        cancel_url=data.get('cancel_url')
    )

    dispatcher = current_app.extensions['event_dispatcher']
    result = dispatcher.emit(event)

    if result.success:
        return jsonify(result.data), 200
    else:
        return jsonify({"error": result.error}), 400


@payment_bp.route('/status/<payment_id>', methods=['GET'])
@require_auth
def payment_status(payment_id: str):
    """Get payment status."""
    # Query via service
    pass


@payment_bp.route('/webhook/<provider>', methods=['POST'])
def webhook(provider: str):
    """Handle payment provider webhook."""
    webhook_service = current_app.extensions['webhook_service']

    signature = request.headers.get('Stripe-Signature') or \
                request.headers.get('Paypal-Transmission-Sig', '')

    result = webhook_service.process(
        provider=provider,
        payload=request.data,
        signature=signature,
        headers=dict(request.headers)
    )

    if result.success:
        return jsonify({"status": "ok"}), 200
    else:
        return jsonify({"error": result.error}), 400
```

**File:** `src/routes/payment.py`
**Tests:** `tests/unit/routes/test_payment_routes.py` (12 tests)

---

### 2. Payment Domain Events (TDD)

**Test First:**
```python
# tests/unit/events/test_payment_events.py
def test_checkout_initiated_event():
    """CheckoutInitiatedEvent has required fields."""

def test_payment_captured_event():
    """PaymentCapturedEvent has transaction data."""

def test_payment_failed_event():
    """PaymentFailedEvent has error info."""

def test_refund_requested_event():
    """RefundRequestedEvent has amount and reason."""
```

**Implementation:**
```python
# src/events/payment_events.py
from dataclasses import dataclass
from decimal import Decimal
from uuid import UUID
from typing import Optional
from src.events.domain import DomainEvent

@dataclass
class CheckoutInitiatedEvent(DomainEvent):
    """User initiated checkout for a plan."""
    user_id: UUID = None
    tarif_plan_id: UUID = None
    provider: str = None
    return_url: Optional[str] = None
    cancel_url: Optional[str] = None

    def __post_init__(self):
        super().__post_init__()
        self.name = 'checkout.initiated'

@dataclass
class PaymentCapturedEvent(DomainEvent):
    """Payment successfully captured."""
    subscription_id: UUID = None
    user_id: UUID = None
    transaction_id: str = None
    amount: Decimal = None
    currency: str = None
    provider: str = None

    def __post_init__(self):
        super().__post_init__()
        self.name = 'payment.captured'

@dataclass
class PaymentFailedEvent(DomainEvent):
    """Payment failed."""
    subscription_id: UUID = None
    user_id: UUID = None
    error_code: str = None
    error_message: str = None
    provider: str = None

    def __post_init__(self):
        super().__post_init__()
        self.name = 'payment.failed'

@dataclass
class RefundRequestedEvent(DomainEvent):
    """Refund requested."""
    transaction_id: str = None
    subscription_id: UUID = None
    amount: Optional[Decimal] = None
    reason: str = None

    def __post_init__(self):
        super().__post_init__()
        self.name = 'refund.requested'
```

**File:** `src/events/payment_events.py`
**Tests:** `tests/unit/events/test_payment_events.py` (5 tests)

---

### 3. Payment Event Handlers (TDD)

**Test First:**
```python
# tests/unit/handlers/test_payment_handlers.py
def test_checkout_handler_creates_subscription():
    """CheckoutInitiatedHandler creates pending subscription."""

def test_checkout_handler_creates_invoice():
    """CheckoutInitiatedHandler creates invoice."""

def test_checkout_handler_calls_sdk():
    """CheckoutInitiatedHandler uses SDK adapter."""

def test_checkout_handler_returns_checkout_url():
    """Handler returns provider checkout URL."""

def test_payment_captured_handler_activates_subscription():
    """PaymentCapturedHandler activates subscription."""

def test_payment_captured_handler_marks_invoice_paid():
    """PaymentCapturedHandler marks invoice as paid."""

def test_payment_failed_handler_updates_subscription():
    """PaymentFailedHandler updates subscription status."""

def test_refund_handler_calls_sdk():
    """RefundRequestedHandler calls SDK refund."""
```

**Implementation:**
```python
# src/handlers/payment_handlers.py
from src.events.domain import IEventHandler, EventResult
from src.events.payment_events import CheckoutInitiatedEvent, PaymentCapturedEvent

class CheckoutInitiatedHandler(IEventHandler):
    """Handle checkout initiation."""

    def __init__(
        self,
        subscription_service: SubscriptionService,
        invoice_service: InvoiceService,
        tarif_plan_service: TarifPlanService,
        sdk_registry: SDKAdapterRegistry
    ):
        self._subscription_service = subscription_service
        self._invoice_service = invoice_service
        self._tarif_plan_service = tarif_plan_service
        self._sdk_registry = sdk_registry

    @staticmethod
    def get_handled_event_class() -> str:
        return 'checkout.initiated'

    def can_handle(self, event) -> bool:
        return isinstance(event, CheckoutInitiatedEvent)

    def handle(self, event: CheckoutInitiatedEvent) -> EventResult:
        # 1. Get tariff plan
        plan = self._tarif_plan_service.get_by_id(event.tarif_plan_id)
        if not plan:
            return EventResult.error_result("Plan not found")

        # 2. Create pending subscription
        subscription = self._subscription_service.create_subscription(
            user_id=event.user_id,
            tarif_plan_id=event.tarif_plan_id,
            status=SubscriptionStatus.PENDING
        )

        # 3. Create invoice
        invoice = self._invoice_service.create_invoice(
            user_id=event.user_id,
            subscription_id=subscription.id,
            amount=plan.price_float,
            currency='USD'
        )

        # 4. Call payment provider SDK
        adapter = self._sdk_registry.get(event.provider)
        sdk_result = adapter.create_payment_intent(
            amount=Decimal(str(plan.price_float)),
            currency='USD',
            metadata={
                'subscription_id': str(subscription.id),
                'invoice_id': str(invoice.id),
                'user_id': str(event.user_id)
            }
        )

        if sdk_result.success:
            return EventResult.success_result({
                'subscription_id': str(subscription.id),
                'checkout_url': sdk_result.data.get('client_secret') or sdk_result.data.get('approval_url')
            })
        else:
            return EventResult.error_result(sdk_result.error)


class PaymentCapturedHandler(IEventHandler):
    """Handle successful payment capture."""

    def __init__(
        self,
        subscription_service: SubscriptionService,
        invoice_service: InvoiceService
    ):
        self._subscription_service = subscription_service
        self._invoice_service = invoice_service

    @staticmethod
    def get_handled_event_class() -> str:
        return 'payment.captured'

    def can_handle(self, event) -> bool:
        return isinstance(event, PaymentCapturedEvent)

    def handle(self, event: PaymentCapturedEvent) -> EventResult:
        # 1. Activate subscription
        self._subscription_service.activate_subscription(event.subscription_id)

        # 2. Mark invoice as paid
        # (invoice lookup by subscription_id)

        return EventResult.success_result({
            'subscription_id': str(event.subscription_id),
            'activated': True
        })
```

**File:** `src/handlers/payment_handlers.py`
**Tests:** `tests/unit/handlers/test_payment_handlers.py` (10 tests)

---

### 4. Application Wiring (TDD)

**Test First:**
```python
# tests/integration/test_payment_integration.py
def test_full_checkout_flow():
    """Complete checkout: route → event → handler → SDK."""

def test_full_webhook_flow():
    """Complete webhook: route → service → handler → event."""

def test_subscription_activation_on_payment():
    """Payment webhook activates subscription."""
```

**Implementation:**
```python
# src/app.py (add to create_app)
def create_app(config_class=Config):
    app = Flask(__name__)
    # ... existing setup ...

    # Register event dispatcher
    from src.events.domain import DomainEventDispatcher
    dispatcher = DomainEventDispatcher()
    app.extensions['event_dispatcher'] = dispatcher

    # Register payment handlers
    from src.handlers.payment_handlers import CheckoutInitiatedHandler, PaymentCapturedHandler
    # ... inject dependencies ...
    dispatcher.register('checkout.initiated', checkout_handler)
    dispatcher.register('payment.captured', payment_captured_handler)

    # Register webhook service
    from src.webhooks.service import WebhookService
    from src.webhooks.handlers.stripe import StripeWebhookHandler
    webhook_service = WebhookService(
        repository=webhook_repo,
        event_dispatcher=dispatcher,
        handlers={'stripe': StripeWebhookHandler(dispatcher)}
    )
    app.extensions['webhook_service'] = webhook_service

    # Register payment routes
    from src.routes.payment import payment_bp
    app.register_blueprint(payment_bp)

    return app
```

**File:** `src/app.py`
**Tests:** `tests/integration/test_payment_integration.py` (5 tests)

---

## Complete Flow Diagram

```
User clicks "Subscribe"
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ POST /api/v1/payment/checkout                               │
│   → @require_auth validates JWT                             │
│   → Emits CheckoutInitiatedEvent                           │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ EventDispatcher.emit(CheckoutInitiatedEvent)                │
│   → Routes to CheckoutInitiatedHandler                      │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ CheckoutInitiatedHandler.handle()                           │
│   → SubscriptionService.create_subscription(PENDING)       │
│   → InvoiceService.create_invoice()                        │
│   → SDKAdapter.create_payment_intent()                     │
│   → Returns checkout_url                                    │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
User redirected to Stripe/PayPal
        │
        ▼
User completes payment
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ POST /api/v1/payment/webhook/stripe                         │
│   → WebhookService.process()                               │
│   → StripeWebhookHandler.verify_signature()                │
│   → StripeWebhookHandler.handle()                          │
│   → Emits PaymentCapturedEvent                             │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ PaymentCapturedHandler.handle()                             │
│   → SubscriptionService.activate_subscription()            │
│   → InvoiceService.mark_paid()                             │
│   → NotificationService.send_confirmation()                │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
User has active subscription
```

---

## File Structure

```
src/
├── routes/
│   └── payment.py              # Payment routes
├── events/
│   └── payment_events.py       # Payment domain events
├── handlers/
│   └── payment_handlers.py     # Payment event handlers
└── app.py                      # Wiring (updated)

tests/
├── unit/
│   ├── routes/
│   │   └── test_payment_routes.py
│   ├── events/
│   │   └── test_payment_events.py
│   └── handlers/
│       └── test_payment_handlers.py
└── integration/
    └── test_payment_integration.py
```

---

## TDD Workflow

```bash
# Run route tests
docker-compose run --rm python-test pytest tests/unit/routes/test_payment_routes.py -v

# Run handler tests
docker-compose run --rm python-test pytest tests/unit/handlers/test_payment_handlers.py -v

# Run integration tests
docker-compose run --rm python-test pytest tests/integration/test_payment_integration.py -v

# Run all payment tests
docker-compose run --rm python-test pytest -k "payment" -v
```

---

## Acceptance Criteria

- [ ] All tests pass: `make test`
- [ ] Checkout creates pending subscription
- [ ] Checkout returns provider URL
- [ ] Webhook activates subscription
- [ ] Full flow works end-to-end
- [ ] Routes are thin (only HTTP handling)
- [ ] Business logic in handlers/services
- [ ] Test coverage > 90%

---

## API Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/v1/payment/checkout` | Yes | Initiate checkout |
| GET | `/api/v1/payment/status/{id}` | Yes | Get payment status |
| POST | `/api/v1/payment/webhook/stripe` | No | Stripe webhook |
| POST | `/api/v1/payment/webhook/paypal` | No | PayPal webhook |

---

**Estimated Duration:** 3-4 hours
**Test Count Target:** 25-30 tests
