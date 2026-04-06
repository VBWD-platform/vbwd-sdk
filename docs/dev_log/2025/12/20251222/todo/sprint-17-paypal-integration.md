# Sprint 17: PayPal Integration

**Priority:** MEDIUM
**Estimated Tests:** 20-25
**Dependencies:** Sprint 14, Sprint 15

---

## Objective

Implement PayPal integration: SDK adapter and webhook handler. Follow the same patterns established in Stripe integration (Sprint 16).

---

## Core Requirements Checklist

- [ ] **TDD**: Write tests FIRST, then implement
- [ ] **SOLID**: PayPalSDKAdapter implements ISDKAdapter, PayPalWebhookHandler implements IWebhookHandler
- [ ] **Liskov Interface**: Fully substitutable with Stripe implementations
- [ ] **Clean Code**: Consistent with Stripe patterns
- [ ] **No Over-Engineering**: Only essential PayPal events
- [ ] **Dockerized Tests**: All tests run via `make test`

---

## Deliverables

### 1. PayPalSDKAdapter (TDD)

**Test First:**
```python
# tests/unit/sdk/test_paypal_adapter.py
def test_create_payment_intent_calls_paypal():
    """create_payment_intent creates PayPal order."""

def test_create_payment_intent_with_idempotency():
    """Idempotency key used for duplicate prevention."""

def test_capture_payment_captures_order():
    """capture_payment captures authorized order."""

def test_refund_payment_creates_refund():
    """refund_payment creates PayPal refund."""

def test_handles_paypal_errors():
    """PayPal errors mapped to SDKResponse."""

def test_sandbox_uses_sandbox_api():
    """Sandbox mode uses PayPal sandbox."""
```

**Implementation:**
```python
# src/sdk/paypal_adapter.py
from paypalserversdk import PaypalServerSdk
from src.sdk.base import BaseSDKAdapter
from src.sdk.interface import SDKConfig, SDKResponse

class PayPalSDKAdapter(BaseSDKAdapter):
    """PayPal SDK adapter."""

    PROVIDER_NAME = "paypal"

    def __init__(
        self,
        config: SDKConfig,
        idempotency_service: IdempotencyService
    ):
        super().__init__(config, idempotency_service)
        self._client = PaypalServerSdk(
            client_id=config.api_key,
            client_secret=config.api_secret,
            environment='sandbox' if config.sandbox else 'live'
        )

    def create_payment_intent(
        self,
        amount: Decimal,
        currency: str,
        metadata: Dict[str, Any],
        idempotency_key: Optional[str] = None
    ) -> SDKResponse:
        """Create PayPal order (equivalent to payment intent)."""
        def _create():
            order = self._client.orders.create({
                "intent": "CAPTURE",
                "purchase_units": [{
                    "amount": {
                        "currency_code": currency.upper(),
                        "value": str(amount)
                    },
                    "custom_id": metadata.get("subscription_id"),
                }],
                "payment_source": {
                    "paypal": {
                        "experience_context": {
                            "return_url": metadata.get("return_url"),
                            "cancel_url": metadata.get("cancel_url")
                        }
                    }
                }
            })
            return SDKResponse(
                success=True,
                data={
                    "payment_intent_id": order.id,
                    "approval_url": self._get_approval_url(order)
                }
            )

        return self._with_idempotency(idempotency_key, _create)

    def capture_payment(
        self,
        payment_intent_id: str,
        idempotency_key: Optional[str] = None
    ) -> SDKResponse:
        """Capture PayPal order."""
        def _capture():
            capture = self._client.orders.capture(payment_intent_id)
            return SDKResponse(
                success=capture.status == "COMPLETED",
                data={"transaction_id": capture.id}
            )

        return self._with_idempotency(idempotency_key, _capture)
```

**File:** `src/sdk/paypal_adapter.py`
**Tests:** `tests/unit/sdk/test_paypal_adapter.py` (10 tests)

---

### 2. PayPalWebhookHandler (TDD)

**Test First:**
```python
# tests/unit/webhooks/handlers/test_paypal_handler.py
def test_provider_is_paypal():
    """Provider property returns 'paypal'."""

def test_verify_signature_valid():
    """Valid PayPal signature returns True."""

def test_verify_signature_invalid():
    """Invalid signature returns False."""

def test_parse_payment_capture_completed():
    """PAYMENT.CAPTURE.COMPLETED mapped to PAYMENT_SUCCEEDED."""

def test_parse_payment_capture_denied():
    """PAYMENT.CAPTURE.DENIED mapped to PAYMENT_FAILED."""

def test_parse_billing_subscription_cancelled():
    """BILLING.SUBSCRIPTION.CANCELLED mapped to SUBSCRIPTION_CANCELLED."""

def test_handle_payment_completed_emits_event():
    """Successful payment emits PaymentCompletedEvent."""
```

**Implementation:**
```python
# src/webhooks/handlers/paypal.py
import hashlib
import base64
from src.webhooks.handlers.base import IWebhookHandler, WebhookResult
from src.webhooks.dto import NormalizedWebhookEvent, WebhookEventType

class PayPalWebhookHandler(IWebhookHandler):
    """PayPal webhook handler."""

    EVENT_TYPE_MAP = {
        'PAYMENT.CAPTURE.COMPLETED': WebhookEventType.PAYMENT_SUCCEEDED,
        'PAYMENT.CAPTURE.DENIED': WebhookEventType.PAYMENT_FAILED,
        'PAYMENT.CAPTURE.REFUNDED': WebhookEventType.REFUND_CREATED,
        'BILLING.SUBSCRIPTION.CREATED': WebhookEventType.SUBSCRIPTION_CREATED,
        'BILLING.SUBSCRIPTION.UPDATED': WebhookEventType.SUBSCRIPTION_UPDATED,
        'BILLING.SUBSCRIPTION.CANCELLED': WebhookEventType.SUBSCRIPTION_CANCELLED,
    }

    def __init__(self, event_dispatcher: DomainEventDispatcher):
        self._dispatcher = event_dispatcher

    @property
    def provider(self) -> str:
        return "paypal"

    def verify_signature(self, payload: bytes, signature: str, secret: str) -> bool:
        """Verify PayPal webhook signature."""
        # PayPal uses certificate-based verification
        # Simplified for development - full implementation uses PayPal SDK
        try:
            # Parse headers from signature string (transmission_id|timestamp|webhook_id|crc32)
            # Verify against PayPal certificate
            return True  # Placeholder - implement with PayPal verification API
        except Exception:
            return False

    def parse_event(self, payload: Dict[str, Any]) -> NormalizedWebhookEvent:
        """Parse PayPal webhook payload."""
        event_type_str = payload.get('event_type', '')
        event_type = self.EVENT_TYPE_MAP.get(event_type_str, WebhookEventType.UNKNOWN)

        resource = payload.get('resource', {})

        return NormalizedWebhookEvent(
            provider='paypal',
            event_id=payload.get('id', ''),
            event_type=event_type,
            payment_intent_id=resource.get('id'),
            amount=self._parse_amount(resource),
            currency=self._parse_currency(resource),
            metadata=resource.get('custom_id', {}),
            raw_payload=payload
        )

    def _parse_amount(self, resource: Dict) -> Optional[Decimal]:
        """Extract amount from PayPal resource."""
        amount_obj = resource.get('amount') or resource.get('seller_receivable_breakdown', {}).get('gross_amount')
        if amount_obj:
            return Decimal(amount_obj.get('value', '0'))
        return None

    def _parse_currency(self, resource: Dict) -> Optional[str]:
        """Extract currency from PayPal resource."""
        amount_obj = resource.get('amount') or resource.get('seller_receivable_breakdown', {}).get('gross_amount')
        if amount_obj:
            return amount_obj.get('currency_code')
        return None
```

**File:** `src/webhooks/handlers/paypal.py`
**Tests:** `tests/unit/webhooks/handlers/test_paypal_handler.py` (12 tests)

---

### 3. PayPal Event Fixtures (Testing)

```python
# tests/fixtures/paypal_webhooks.py
def payment_capture_completed_payload():
    """Fixture for PAYMENT.CAPTURE.COMPLETED event."""
    return {
        "id": "WH-TEST-123",
        "event_type": "PAYMENT.CAPTURE.COMPLETED",
        "resource": {
            "id": "CAP-123",
            "status": "COMPLETED",
            "amount": {
                "currency_code": "USD",
                "value": "29.99"
            },
            "custom_id": "sub_uuid_here"
        }
    }

def payment_capture_denied_payload():
    """Fixture for PAYMENT.CAPTURE.DENIED event."""
    return {
        "id": "WH-TEST-456",
        "event_type": "PAYMENT.CAPTURE.DENIED",
        "resource": {
            "id": "CAP-456",
            "status": "DENIED"
        }
    }
```

**File:** `tests/fixtures/paypal_webhooks.py`

---

## PayPal Events to Handle

**Essential (implement now):**
- `PAYMENT.CAPTURE.COMPLETED` - Payment captured successfully
- `PAYMENT.CAPTURE.DENIED` - Payment capture failed
- `BILLING.SUBSCRIPTION.CANCELLED` - Subscription cancelled

**Optional (future):**
- `BILLING.SUBSCRIPTION.CREATED` - New subscription
- `BILLING.SUBSCRIPTION.UPDATED` - Subscription modified
- `PAYMENT.CAPTURE.REFUNDED` - Refund processed

---

## File Structure

```
src/
├── sdk/
│   └── paypal_adapter.py      # PayPalSDKAdapter
└── webhooks/handlers/
    └── paypal.py              # PayPalWebhookHandler

tests/
├── unit/
│   ├── sdk/
│   │   └── test_paypal_adapter.py
│   └── webhooks/handlers/
│       └── test_paypal_handler.py
└── fixtures/
    └── paypal_webhooks.py
```

---

## TDD Workflow

```bash
# Run PayPal SDK adapter tests
docker-compose run --rm python-test pytest tests/unit/sdk/test_paypal_adapter.py -v

# Run PayPal webhook handler tests
docker-compose run --rm python-test pytest tests/unit/webhooks/handlers/test_paypal_handler.py -v

# Run all PayPal tests
docker-compose run --rm python-test pytest -k "paypal" -v
```

---

## Acceptance Criteria

- [ ] All tests pass: `make test`
- [ ] PayPalSDKAdapter creates orders and captures payments
- [ ] PayPalWebhookHandler verifies signatures
- [ ] All essential events parsed correctly
- [ ] Implements ISDKAdapter and IWebhookHandler (Liskov)
- [ ] Consistent patterns with Stripe implementation
- [ ] Test coverage > 90%

---

## Dependencies

```
# requirements.txt
paypal-server-sdk>=0.5.0
```

---

## Notes

**Liskov Compliance:**
Both Stripe and PayPal implementations must be interchangeable:
```python
# Either adapter can be used
adapter: ISDKAdapter = StripeSDKAdapter(config, idempotency)
adapter: ISDKAdapter = PayPalSDKAdapter(config, idempotency)

# Same method signature, same behavior contract
result = adapter.create_payment_intent(amount, currency, metadata)
```

---

**Estimated Duration:** 2-3 hours
**Test Count Target:** 20-25 tests
