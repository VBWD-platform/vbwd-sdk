# Sprint 16: Stripe Integration

**Priority:** HIGH
**Estimated Tests:** 20-25
**Dependencies:** Sprint 14, Sprint 15

---

## Objective

Implement complete Stripe integration: webhook handler with signature verification, payment event mapping, and integration with existing event system.

---

## Core Requirements Checklist

- [ ] **TDD**: Write tests FIRST, then implement
- [ ] **SOLID**: StripeWebhookHandler implements IWebhookHandler
- [ ] **Liskov Interface**: Fully substitutable with other webhook handlers
- [ ] **Clean Code**: Clear event mapping, readable code
- [ ] **No Over-Engineering**: Only handle essential Stripe events
- [ ] **Dockerized Tests**: All tests run via `make test`

---

## Deliverables

### 1. StripeWebhookHandler (TDD)

**Test First:**
```python
# tests/unit/webhooks/handlers/test_stripe_handler.py
def test_provider_is_stripe():
    """Provider property returns 'stripe'."""

def test_verify_signature_valid():
    """Valid signature returns True."""

def test_verify_signature_invalid():
    """Invalid signature returns False."""

def test_verify_signature_expired():
    """Expired timestamp returns False."""

def test_parse_payment_intent_succeeded():
    """payment_intent.succeeded mapped to PAYMENT_SUCCEEDED."""

def test_parse_payment_intent_failed():
    """payment_intent.payment_failed mapped to PAYMENT_FAILED."""

def test_parse_invoice_paid():
    """invoice.paid mapped to PAYMENT_SUCCEEDED."""

def test_parse_customer_subscription_deleted():
    """customer.subscription.deleted mapped to SUBSCRIPTION_CANCELLED."""

def test_parse_unknown_event():
    """Unknown events mapped to UNKNOWN type."""

def test_handle_payment_succeeded_emits_event():
    """Successful payment emits PaymentCompletedEvent."""

def test_handle_payment_failed_emits_event():
    """Failed payment emits PaymentFailedEvent."""
```

**Implementation:**
```python
# src/webhooks/handlers/stripe.py
import stripe
from src.webhooks.handlers.base import IWebhookHandler, WebhookResult
from src.webhooks.dto import NormalizedWebhookEvent, WebhookEventType

class StripeWebhookHandler(IWebhookHandler):
    """Stripe webhook handler."""

    EVENT_TYPE_MAP = {
        'payment_intent.succeeded': WebhookEventType.PAYMENT_SUCCEEDED,
        'payment_intent.payment_failed': WebhookEventType.PAYMENT_FAILED,
        'invoice.paid': WebhookEventType.PAYMENT_SUCCEEDED,
        'invoice.payment_failed': WebhookEventType.PAYMENT_FAILED,
        'customer.subscription.created': WebhookEventType.SUBSCRIPTION_CREATED,
        'customer.subscription.updated': WebhookEventType.SUBSCRIPTION_UPDATED,
        'customer.subscription.deleted': WebhookEventType.SUBSCRIPTION_CANCELLED,
        'charge.refunded': WebhookEventType.REFUND_CREATED,
        'charge.dispute.created': WebhookEventType.DISPUTE_CREATED,
    }

    def __init__(self, event_dispatcher: DomainEventDispatcher):
        self._dispatcher = event_dispatcher

    @property
    def provider(self) -> str:
        return "stripe"

    def verify_signature(self, payload: bytes, signature: str, secret: str) -> bool:
        """Verify Stripe webhook signature."""
        try:
            stripe.Webhook.construct_event(payload, signature, secret)
            return True
        except stripe.error.SignatureVerificationError:
            return False

    def parse_event(self, payload: Dict[str, Any]) -> NormalizedWebhookEvent:
        """Parse Stripe webhook payload."""
        stripe_type = payload.get('type', '')
        event_type = self.EVENT_TYPE_MAP.get(stripe_type, WebhookEventType.UNKNOWN)

        obj = payload.get('data', {}).get('object', {})

        return NormalizedWebhookEvent(
            provider='stripe',
            event_id=payload.get('id', ''),
            event_type=event_type,
            payment_intent_id=obj.get('payment_intent') or obj.get('id'),
            amount=Decimal(obj.get('amount', 0)) / 100,
            currency=obj.get('currency', '').upper(),
            metadata=obj.get('metadata', {}),
            raw_payload=payload
        )

    def handle(self, event: NormalizedWebhookEvent) -> WebhookResult:
        """Process normalized Stripe event."""
        if event.event_type == WebhookEventType.PAYMENT_SUCCEEDED:
            return self._handle_payment_succeeded(event)
        elif event.event_type == WebhookEventType.PAYMENT_FAILED:
            return self._handle_payment_failed(event)
        elif event.event_type == WebhookEventType.SUBSCRIPTION_CANCELLED:
            return self._handle_subscription_cancelled(event)
        else:
            return WebhookResult(success=True, message=f"Unhandled event: {event.event_type}")

    def _handle_payment_succeeded(self, event: NormalizedWebhookEvent) -> WebhookResult:
        """Handle successful payment."""
        domain_event = PaymentCompletedEvent(
            subscription_id=event.subscription_id,
            user_id=event.user_id,
            transaction_id=event.payment_intent_id,
            amount=event.amount,
            currency=event.currency
        )
        result = self._dispatcher.emit(domain_event)
        return WebhookResult(success=result.success, error=result.error)
```

**File:** `src/webhooks/handlers/stripe.py`
**Tests:** `tests/unit/webhooks/handlers/test_stripe_handler.py` (15 tests)

---

### 2. Stripe Signature Verification Tests (TDD)

**Test First:**
```python
# tests/unit/webhooks/handlers/test_stripe_signature.py
def test_construct_signed_payload():
    """Helper creates valid signed payload for testing."""

def test_signature_with_wrong_secret():
    """Wrong secret fails verification."""

def test_signature_with_modified_payload():
    """Modified payload fails verification."""

def test_signature_with_replay_attack():
    """Old timestamp fails verification (> 5 min)."""
```

**Implementation:** Use `stripe.Webhook.construct_event` with test fixtures

**File:** `tests/unit/webhooks/handlers/test_stripe_signature.py`
**Tests:** 5 tests

---

### 3. Stripe Event Fixtures (Testing)

```python
# tests/fixtures/stripe_webhooks.py
def payment_intent_succeeded_payload():
    """Fixture for payment_intent.succeeded event."""
    return {
        "id": "evt_test_123",
        "type": "payment_intent.succeeded",
        "data": {
            "object": {
                "id": "pi_test_123",
                "amount": 2999,
                "currency": "usd",
                "status": "succeeded",
                "metadata": {
                    "subscription_id": "sub_uuid_here",
                    "user_id": "user_uuid_here"
                }
            }
        }
    }

def payment_intent_failed_payload():
    """Fixture for payment_intent.payment_failed event."""
    return {
        "id": "evt_test_456",
        "type": "payment_intent.payment_failed",
        "data": {
            "object": {
                "id": "pi_test_456",
                "amount": 2999,
                "currency": "usd",
                "status": "requires_payment_method",
                "last_payment_error": {
                    "message": "Your card was declined."
                }
            }
        }
    }
```

**File:** `tests/fixtures/stripe_webhooks.py`

---

### 4. Integration with Payment Events (TDD)

**Test First:**
```python
# tests/integration/test_stripe_webhook_flow.py
def test_webhook_to_subscription_activation():
    """Webhook triggers subscription activation."""
    # 1. Create pending subscription
    # 2. Process payment_intent.succeeded webhook
    # 3. Verify subscription is now ACTIVE

def test_webhook_to_payment_failure_notification():
    """Failed payment triggers notification."""
    # 1. Create pending subscription
    # 2. Process payment_intent.payment_failed webhook
    # 3. Verify PaymentFailedEvent was dispatched
```

**File:** `tests/integration/test_stripe_webhook_flow.py` (5 tests)

---

## Stripe Events to Handle

**Essential (implement now):**
- `payment_intent.succeeded` - Payment completed
- `payment_intent.payment_failed` - Payment failed
- `invoice.paid` - Recurring payment successful
- `invoice.payment_failed` - Recurring payment failed
- `customer.subscription.deleted` - Subscription cancelled

**Optional (future):**
- `customer.subscription.updated` - Subscription changed
- `charge.refunded` - Refund processed
- `charge.dispute.created` - Dispute opened

---

## File Structure

```
src/webhooks/handlers/
├── __init__.py
├── base.py            # IWebhookHandler (Sprint 15)
└── stripe.py          # StripeWebhookHandler

tests/
├── unit/webhooks/handlers/
│   ├── test_stripe_handler.py
│   └── test_stripe_signature.py
├── integration/
│   └── test_stripe_webhook_flow.py
└── fixtures/
    └── stripe_webhooks.py
```

---

## TDD Workflow

```bash
# Run Stripe handler tests
docker-compose run --rm python-test pytest tests/unit/webhooks/handlers/test_stripe_handler.py -v

# Run signature tests
docker-compose run --rm python-test pytest tests/unit/webhooks/handlers/test_stripe_signature.py -v

# Run integration tests
docker-compose run --rm python-test pytest tests/integration/test_stripe_webhook_flow.py -v
```

---

## Acceptance Criteria

- [ ] All tests pass: `make test`
- [ ] Signature verification works with Stripe library
- [ ] All essential events parsed correctly
- [ ] PaymentCompletedEvent emitted on success
- [ ] PaymentFailedEvent emitted on failure
- [ ] Implements IWebhookHandler (Liskov)
- [ ] Test coverage > 90%

---

## Dependencies

```
# requirements.txt
stripe>=7.0.0
```

---

**Estimated Duration:** 2-3 hours
**Test Count Target:** 20-25 tests
