# Sprint 02d: Payment Authorization & Capture (Core + Plugins)

**Date:** 2026-03-18
**Status:** Planned
**Prerequisite for:** [02a-booking-be.md](02a-booking-be.md) (booking payment flow)
**Overview:** [02-booking-overview.md](02-booking-overview.md)

---

## Problem

The booking plugin needs **authorize → capture** (two-step payment):
1. Hold the amount when user books
2. Charge later when booking completes (or release on cancellation)

Current state:

| Provider | `create_payment_intent()` | `capture_payment()` | Real Authorize? |
|----------|--------------------------|---------------------|-----------------|
| Stripe | Checkout Sessions (auto-capture) | Retrieves session status only | NO |
| PayPal | Orders API with `intent: "CAPTURE"` | `capture_order()` — real capture | YES |
| YooKassa | Payments API with `capture: True` | Real capture method | YES (but defaults to immediate) |

**Stripe** needs the most work. **PayPal** and **YooKassa** need config flag changes.

---

## Changes

### 1. Core: PaymentProviderPlugin interface

Add `authorize_payment()` method to the interface:

```python
# vbwd/plugins/payment_provider.py

class PaymentProviderPlugin(BasePlugin):
    @abstractmethod
    def create_payment_intent(self, amount, currency, metadata=None, capture=True):
        """Create payment intent.

        Args:
            capture: If True, charge immediately. If False, authorize only (hold).
        """
        ...

    @abstractmethod
    def capture_payment(self, payment_id, amount=None):
        """Capture a previously authorized payment.

        Args:
            payment_id: Provider-specific payment/intent ID.
            amount: Optional partial capture amount. None = full amount.
        """
        ...

    @abstractmethod
    def release_authorization(self, payment_id):
        """Release/void a previously authorized payment hold."""
        ...
```

### 2. Core: ISDKAdapter interface

Add `release_authorization()`:

```python
# vbwd/sdk/interface.py

class ISDKAdapter:
    def release_authorization(self, payment_id: str) -> dict:
        """Release/void an authorized payment. Returns status dict."""
        ...
```

### 3. Core: InvoiceStatus — add AUTHORIZED

```python
# vbwd/models/enums.py
class InvoiceStatus(enum.Enum):
    PENDING = "PENDING"
    AUTHORIZED = "AUTHORIZED"   # ← NEW: payment hold placed, not yet charged
    PAID = "PAID"
    CANCELLED = "CANCELLED"
    REFUNDED = "REFUNDED"
    FAILED = "FAILED"
```

### 4. Stripe Plugin — Payment Intents (not Checkout Sessions)

For authorize-only, Stripe needs **Payment Intents API** with `capture_method: "manual"` instead of Checkout Sessions:

```python
# plugins/stripe/booking/services/stripe_service.py

def create_payment_intent(self, amount, currency, metadata=None, capture=True):
    intent = stripe.PaymentIntent.create(
        amount=int(amount * 100),  # cents
        currency=currency.lower(),
        metadata=metadata or {},
        capture_method="automatic" if capture else "manual",  # ← key change
    )
    return {"payment_intent_id": intent.id, "client_secret": intent.client_secret}

def capture_payment(self, payment_intent_id, amount=None):
    params = {}
    if amount is not None:
        params["amount_to_capture"] = int(amount * 100)
    intent = stripe.PaymentIntent.capture(payment_intent_id, **params)
    return {"status": intent.status}

def release_authorization(self, payment_intent_id):
    intent = stripe.PaymentIntent.cancel(payment_intent_id)
    return {"status": intent.status}
```

### 5. PayPal Plugin — Already works, add `release_authorization()`

```python
# plugins/paypal/booking/services/paypal_service.py

def create_payment_intent(self, amount, currency, metadata=None, capture=True):
    intent = "CAPTURE" if capture else "AUTHORIZE"
    order = self._create_order(amount, currency, intent=intent, metadata=metadata)
    return {"order_id": order["id"], "approve_url": order["links"][1]["href"]}

def capture_payment(self, order_id, amount=None):
    return self.capture_order(order_id)  # already exists

def release_authorization(self, order_id):
    # PayPal: void the authorized order
    return self._void_authorization(order_id)
```

### 6. YooKassa Plugin — Change default `capture` flag

```python
# plugins/yookassa/booking/services/yookassa_service.py

def create_payment_intent(self, amount, currency, metadata=None, capture=True):
    payment = Payment.create({
        "amount": {"value": str(amount), "currency": currency},
        "capture": capture,  # ← was always True, now configurable
        "metadata": metadata or {},
    })
    return {"payment_id": payment.id, "confirmation_url": payment.confirmation.confirmation_url}

def release_authorization(self, payment_id):
    Payment.cancel(payment_id)
    return {"status": "cancelled"}
```

### 7. Admin Manual Capture

Add admin endpoint to manually capture or release authorized payments:

```python
# In core or booking plugin routes:
@admin_bp.route("/api/v1/admin/invoices/<invoice_id>/capture", methods=["POST"])
def capture_invoice_payment(invoice_id):
    """Manually capture an authorized payment."""
    ...

@admin_bp.route("/api/v1/admin/invoices/<invoice_id>/release", methods=["POST"])
def release_invoice_payment(invoice_id):
    """Release/void an authorized payment hold."""
    ...
```

### 8. Event-Driven Capture

Booking plugin can trigger capture via event:

```python
# Booking plugin subscribes to its own event:
bus.subscribe("booking.completed", self._on_completed)

def _on_completed(self, event_name, data):
    booking = self.booking_repo.find_by_id(data["booking_id"])
    if booking.invoice_id:
        invoice = self.invoice_repo.find_by_id(booking.invoice_id)
        if invoice.status == InvoiceStatus.AUTHORIZED:
            self.payment_service.capture(invoice)
            invoice.status = InvoiceStatus.PAID
```

---

## Capture Policy Config

Configured **globally** in `config.json`, overridable **per category** (NOT per resource).

### Capture Trigger — when the authorized amount gets charged

```json
{
  "capture_policy": {
    "trigger": "before_start",
    "days_before_start": 10
  }
}
```

| Trigger | Behavior |
|---------|----------|
| `immediate` | Charge right after authorization (no hold) |
| `on_booking_completed` | Charge after booking end_at passes |
| `before_start` | Charge X days before booking start_at |

**Authorization expiry handling:** Stripe auths expire after 7 days. If `days_before_start` exceeds the auth window, the system creates a **new charge** (not a capture) at the configured time. The original auth simply expires.

### Timeline example (hotel, 50 days ahead, charge 10 days before):

```
Day 0:   User books → payment AUTHORIZED (hold on card)
Day 7:   Stripe authorization expires (normal, no action)
Day 40:  10 days before check-in → system CHARGES (new payment)
Day 50:  Check-in day
Day 52:  Check-out → booking.completed event
```

### Cancellation Policy — tiered refund rules

```json
{
  "cancellation_policy": {
    "tiers": [
      { "days_before_start": 10, "refund_percent": 100 },
      { "days_before_start": 5,  "refund_percent": 70 },
      { "days_before_start": 3,  "refund_percent": 50 },
      { "days_before_start": 2,  "refund_percent": 0 }
    ]
  }
}
```

**Rules:**
- Tiers are evaluated top-down. First match wins.
- 10+ days before start → 100% refund
- 5-9 days before → 70% refund
- 3-4 days before → 50% refund
- 0-2 days before → 0% refund (no cancellation possible)

**Refund behavior depends on whether payment was captured:**
- If amount NOT yet captured (still authorized) → release authorization (full or partial)
- If amount already captured → issue refund via payment provider's refund API (full or partial)

### Who can cancel

| Actor | Bound by policy? | Refund |
|-------|-----------------|--------|
| **User** | YES — tiers apply | Per cancellation_policy tiers |
| **Admin** | YES — same tiers | Cannot override the policy |
| **Provider** (admin issues `cancelled_by_provider`) | NO — always 100% | Full refund regardless of timing |

**`cancelled_by_provider`** is a special admin action for when the resource provider cancels (doctor sick, room unavailable, etc.). Admin explicitly triggers this event. It bypasses the cancellation policy and always results in 100% refund + a dedicated email template.

### Config hierarchy

```
Global default (config.json)
  ↓ overridden by
Category config (booking_resource_category.config JSON)
  ↓ NOT overridable by
Resource (uses category config, or global if no category config)
```

---

## Testing

### Core tests (~10 tests)
- Test `AUTHORIZED` invoice status lifecycle
- Test `release_authorization()` on interface
- Test existing `PAID`/`PENDING`/`CANCELLED` flows still work

### Stripe plugin tests (~8 tests)
- Test `capture_method: "manual"` in payment intent creation
- Test `capture_payment()` calls `stripe.PaymentIntent.capture()`
- Test `release_authorization()` calls `stripe.PaymentIntent.cancel()`
- Test `capture=True` uses `capture_method: "automatic"` (backward compatible)

### PayPal plugin tests (~5 tests)
- Test `intent: "AUTHORIZE"` when `capture=False`
- Test `release_authorization()` voids order

### YooKassa plugin tests (~5 tests)
- Test `capture: False` in payment creation
- Test `release_authorization()` cancels payment

---

## Migration

```python
# alembic migration: add AUTHORIZED to InvoiceStatus enum
op.execute("ALTER TYPE invoicestatus ADD VALUE IF NOT EXISTS 'AUTHORIZED'")
```

---

## Acceptance Criteria

1. `create_payment_intent(capture=False)` creates a hold (not a charge) on all 3 providers
2. `capture_payment(payment_id)` charges a previously authorized payment
3. `release_authorization(payment_id)` voids/cancels the hold
4. Admin can manually capture or release via API
5. `InvoiceStatus.AUTHORIZED` exists and works in the invoice lifecycle
6. Existing immediate-charge flows (`capture=True`) are NOT affected
7. All existing payment tests pass (no regressions)
8. `bin/pre-commit-check.sh --quick` green on core + all 3 payment plugins

---

## Estimated Effort

| Component | Effort |
|-----------|--------|
| Core interface + enum + migration | 0.5 day |
| Stripe plugin (Payment Intents) | 1 day |
| PayPal plugin (add release) | 0.5 day |
| YooKassa plugin (flag change) | 0.5 day |
| Admin capture/release endpoint | 0.5 day |
| Tests | 1 day |
| **Total** | **4 days** |
