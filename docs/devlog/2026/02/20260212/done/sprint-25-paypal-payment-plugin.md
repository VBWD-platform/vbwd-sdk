# Sprint 25: PayPal Payment Plugin (Backend + Frontend)

## Goal
Add PayPal payment processing as a plugin, following the exact same architecture established by Stripe in Sprint 24. Reuse all shared payment abstractions — PayPal is a thin wrapper, not a reimplementation.

## Engineering Principles
- **TDD**: Tests first — write tests before implementation, validate against interfaces
- **SOLID**: Single responsibility, Open/closed, Liskov substitution, Interface segregation, Dependency inversion
- **Liskov Substitution**: `PayPalSDKAdapter` is interchangeable with any `ISDKAdapter`; `PayPalPlugin` with any `PaymentProviderPlugin`
- **DI**: Dependencies injected via container/config, never hardcoded
- **Clean Code**: Readable, self-documenting, minimal comments
- **DRY**: Reuse existing shared `payment_route_helpers.py`, `usePaymentRedirect`, `usePaymentStatus` — zero duplication of invoice validation, event emission, polling, or redirect logic
- **No overengineering**: Minimum code needed for the current task, no speculative abstractions
- **No backward compatibility**: Delete/replace freely, no shims or re-exports

## Testing Approach

All tests MUST pass before the sprint is considered complete. Run via:

```bash
# 1. Backend unit tests (Docker)
cd vbwd-backend && ./bin/pre-commit-check.sh --full

# 2. Backend PayPal plugin tests (Docker)
cd vbwd-backend && docker compose run --rm test pytest plugins/paypal/tests/ -v

# 3. User frontend tests
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 4. Admin regression (no admin code changes expected, but verify)
cd vbwd-frontend/admin/vue && npx vitest run

# 5. Core regression
cd vbwd-frontend/core && npx vitest run

# 6. Full pre-commit check
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit
```

---

## What Already Exists (Sprint 24 — NO changes needed)

### Shared Backend (reused as-is)
| File | Provides |
|------|----------|
| `src/plugins/payment_route_helpers.py` | `check_plugin_enabled()`, `validate_invoice_for_payment()`, `emit_payment_captured()` |
| `src/plugins/base.py` | `BasePlugin`, `PluginMetadata`, lifecycle |
| `src/plugins/payment_provider.py` | `PaymentProviderPlugin`, `PaymentResult`, `PaymentStatus` |
| `src/plugins/manager.py` | Discovery, lifecycle, blueprint registration |
| `src/plugins/config_store.py` | `PluginConfigStore` interface (JSON-file impl) |
| `src/sdk/interface.py` | `ISDKAdapter`, `SDKConfig`, `SDKResponse` |
| `src/sdk/base.py` | `BaseSDKAdapter` with `_with_retry()`, `_with_idempotency()` |
| `src/events/payment_events.py` | `PaymentCapturedEvent`, `PaymentFailedEvent`, `PaymentRefundedEvent`, `SubscriptionCancelledEvent`, `RefundReversedEvent` |
| `src/handlers/payment_handler.py` | `PaymentCapturedHandler` (invoice→PAID, subscription→ACTIVE) |
| `src/handlers/subscription_cancel_handler.py` | `SubscriptionCancelledHandler` |

### Shared Frontend (reused as-is)
| File | Provides |
|------|----------|
| `core/src/composables/usePaymentRedirect.ts` | Create-session → redirect flow (loading, error, retry) |
| `core/src/composables/usePaymentStatus.ts` | Poll session status (polling, confirmed, timeout) |
| `core/src/plugins/` | `PluginRegistry`, `PlatformSDK`, `IPlugin`, `IPlatformSDK` |

### DB Fields (already exist from Sprint 24)
| Model | Field | Used By PayPal? |
|-------|-------|-----------------|
| User | `stripe_customer_id` | NO — PayPal has its own customer model |
| Subscription | `stripe_subscription_id` | NO — PayPal uses `paypal_subscription_id` |
| UserInvoice | `stripe_invoice_id` | NO — PayPal uses `paypal_order_id` |

---

## What This Sprint Adds — PayPal-Specific

| Layer | File | Provides |
|-------|------|----------|
| Backend | `plugins/paypal/__init__.py` | `PayPalPlugin(PaymentProviderPlugin)` |
| Backend | `plugins/paypal/sdk_adapter.py` | `PayPalSDKAdapter(BaseSDKAdapter)` |
| Backend | `plugins/paypal/routes.py` | create-order, capture-order, webhook, order-status (uses shared helpers) |
| Backend | `plugins/paypal/config.json` | Config schema |
| Backend | `plugins/paypal/admin-config.json` | Admin UI layout |
| Backend | `plugins/paypal/tests/` | Tests |
| Backend | `alembic/versions/xxxx_add_paypal_fields.py` | DB migration |
| Frontend | `user/plugins/paypal-payment/index.ts` | Plugin with 3 routes |
| Frontend | `user/plugins/paypal-payment/*.vue` | 3 views (use shared composables) |
| Frontend | `user/plugins/paypal-payment/config.json` | Frontend config schema |
| Frontend | `user/plugins/paypal-payment/admin-config.json` | Frontend admin UI |

---

## PayPal vs Stripe — Key Differences

| Aspect | Stripe | PayPal |
|--------|--------|--------|
| SDK | `stripe` Python package | `paypalrestsdk` or PayPal REST API v2 (HTTP client) |
| Session type | Checkout Session | Order (v2/checkout/orders) |
| One-time flow | Session mode="payment" → redirect → webhook | Create Order → Approve (redirect) → Capture |
| Recurring flow | Session mode="subscription" → auto-renewal | Subscription API (v1/billing/subscriptions) → auto-renewal |
| Customer model | `stripe_customer_id` on User | Not needed (PayPal identifies by email) |
| Webhook events | checkout.session.completed, invoice.paid, etc. | CHECKOUT.ORDER.APPROVED, PAYMENT.CAPTURE.COMPLETED, BILLING.SUBSCRIPTION.*, etc. |
| Webhook verification | `stripe.Webhook.construct_event()` | Verify webhook signature via PayPal API or `verify-webhook-signature` endpoint |
| Capture step | Automatic (Checkout Sessions) | Explicit — must call Capture after approval |
| Return params | `?session_id=cs_xxx` | `?token=EC-xxx&PayerID=xxx` |

### PayPal Payment Flow — One-Time

```
1. User completes checkout → PENDING invoice created
2. Frontend detects payment_method_code == "paypal"
3. Frontend redirects to /pay/paypal?invoice=<invoice_id>
4. PayPalPaymentView uses usePaymentRedirect('/api/v1/plugins/paypal')
5. Composable calls POST /api/v1/plugins/paypal/create-order { invoice_id }
6. Route creates PayPal Order via API → gets approval_url
7. Returns { session_url: approval_url } → redirect to PayPal
8. User approves on PayPal → redirected back to /pay/paypal/success?token=<order_id>&PayerID=<id>
9. SuccessView reads token from query → calls POST /api/v1/plugins/paypal/capture-order { order_id }
10. Capture route calls PayPal Capture API → emits PaymentCapturedEvent
11. Handler activates subscription, marks invoice PAID
12. Frontend shows confirmation
```

### PayPal Payment Flow — Recurring (Subscriptions)

```
1. User completes checkout → PENDING invoice + PENDING subscription
2. Frontend redirects to /pay/paypal?invoice=<invoice_id>
3. POST /api/v1/plugins/paypal/create-order { invoice_id }
4. Route detects recurring items → creates PayPal Subscription via Billing API
5. Returns { session_url: approve_url } → redirect to PayPal
6. User approves subscription → redirected back to /pay/paypal/success?subscription_id=<id>&ba_token=<token>
7. SuccessView reads subscription_id → calls GET /api/v1/plugins/paypal/order-status/<subscription_id>
8. Route checks subscription status via PayPal API
9. If ACTIVE → emits PaymentCapturedEvent → handler activates
10. Stores paypal_subscription_id on our Subscription model

--- RENEWAL (automatic, no user action) ---
11. PayPal charges at billing period end → sends webhook: PAYMENT.SALE.COMPLETED
12. Webhook creates renewal invoice, emits PaymentCapturedEvent
13. Handler extends subscription.expires_at, marks invoice PAID

--- CANCELLATION ---
14. PayPal sends webhook: BILLING.SUBSCRIPTION.CANCELLED
15. Webhook emits SubscriptionCancelledEvent → handler marks subscription CANCELLED

--- PAYMENT FAILURE ---
16. PayPal sends webhook: BILLING.SUBSCRIPTION.PAYMENT.FAILED
17. Webhook emits PaymentFailedEvent → handler notifies user
```

---

## Task 1: Backend — DB Migration for PayPal Fields

### Files
| File | Action |
|------|--------|
| `vbwd-backend/src/models/subscription.py` | **MODIFY** — add `paypal_subscription_id` |
| `vbwd-backend/src/models/invoice.py` | **MODIFY** — add `paypal_order_id` |
| `vbwd-backend/alembic/versions/xxxx_add_paypal_fields.py` | **NEW** — Alembic migration |

### Model Changes

**Subscription** — add PayPal subscription linking:
```python
paypal_subscription_id = db.Column(db.String(255), unique=True, nullable=True, index=True)
```

**UserInvoice** — add PayPal order tracking (for deduplication):
```python
paypal_order_id = db.Column(db.String(255), unique=True, nullable=True, index=True)
```

### Repository Changes

**SubscriptionRepository** — add lookup method:
```python
def find_by_paypal_subscription_id(self, paypal_sub_id: str) -> Optional[Subscription]:
    return self.session.query(Subscription).filter_by(
        paypal_subscription_id=paypal_sub_id
    ).first()
```

**InvoiceRepository** — add lookup method:
```python
def find_by_paypal_order_id(self, order_id: str) -> Optional[UserInvoice]:
    return self.session.query(UserInvoice).filter_by(
        paypal_order_id=order_id
    ).first()
```

### Alembic Migration
```python
def upgrade():
    op.add_column('subscriptions', sa.Column('paypal_subscription_id', sa.String(255), unique=True, nullable=True))
    op.add_column('invoices', sa.Column('paypal_order_id', sa.String(255), unique=True, nullable=True))
    op.create_index('ix_subscriptions_paypal_subscription_id', 'subscriptions', ['paypal_subscription_id'])
    op.create_index('ix_invoices_paypal_order_id', 'invoices', ['paypal_order_id'])

def downgrade():
    op.drop_column('invoices', 'paypal_order_id')
    op.drop_column('subscriptions', 'paypal_subscription_id')
```

---

## Task 2: Backend — PayPal SDK Adapter

### Files
| File | Action |
|------|--------|
| `vbwd-backend/requirements.txt` | Add `paypalrestsdk>=1.13.3` or use `requests` for PayPal REST v2 |
| `vbwd-backend/plugins/paypal/sdk_adapter.py` | **NEW** |

### `sdk_adapter.py` — Class Design

**Inheritance chain:** `PayPalSDKAdapter` → `BaseSDKAdapter` → `ISDKAdapter`

```python
class PayPalSDKAdapter(BaseSDKAdapter):
    """PayPal SDK adapter implementing ISDKAdapter.

    Liskov Substitution: interchangeable with any ISDKAdapter.
    Uses PayPal Orders API v2 (redirect-based, PCI-compliant).
    """
```

**Constructor:**
```python
def __init__(self, config: SDKConfig, idempotency_service=None):
    super().__init__(config, idempotency_service)
    self._client_id = config.api_key  # PayPal client ID
    self._client_secret = config.api_secret  # PayPal secret
    self._base_url = "https://api-m.sandbox.paypal.com" if config.sandbox else "https://api-m.paypal.com"
    self._access_token = None
    self._token_expires_at = 0
```

**Property:**
```python
@property
def provider_name(self) -> str:
    return "paypal"
```

**Method: `_get_access_token()`** — OAuth2 client credentials
```python
def _get_access_token(self) -> str:
    """Get or refresh PayPal OAuth2 access token."""
    if self._access_token and time.time() < self._token_expires_at:
        return self._access_token
    response = requests.post(
        f"{self._base_url}/v1/oauth2/token",
        auth=(self._client_id, self._client_secret),
        data={"grant_type": "client_credentials"},
        headers={"Accept": "application/json"}
    )
    response.raise_for_status()
    data = response.json()
    self._access_token = data["access_token"]
    self._token_expires_at = time.time() + data["expires_in"] - 60
    return self._access_token
```

**Method: `create_payment_intent()`** — Create PayPal Order (one-time)
```python
def create_payment_intent(self, amount, currency, metadata, idempotency_key=None) -> SDKResponse:
    """Create PayPal Order for one-time payment."""
    token = self._get_access_token()
    order_data = {
        "intent": "CAPTURE",
        "purchase_units": [{
            "amount": {
                "currency_code": currency.upper(),
                "value": str(amount),
            },
            "custom_id": metadata.get("invoice_id", ""),
        }],
        "application_context": {
            "return_url": metadata.get("success_url", ""),
            "cancel_url": metadata.get("cancel_url", ""),
            "user_action": "PAY_NOW",
        }
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    if idempotency_key:
        headers["PayPal-Request-Id"] = idempotency_key

    resp = requests.post(f"{self._base_url}/v2/checkout/orders", json=order_data, headers=headers)
    if resp.status_code in (200, 201):
        data = resp.json()
        approve_url = next((l["href"] for l in data["links"] if l["rel"] == "approve"), None)
        return SDKResponse(success=True, data={
            "session_id": data["id"],  # PayPal Order ID
            "session_url": approve_url,  # Redirect URL
        })
    return SDKResponse(success=False, error=resp.text, error_code=str(resp.status_code))
```

**Method: `capture_order()`** — Capture after buyer approval (**PayPal-specific**)
```python
def capture_order(self, order_id: str) -> SDKResponse:
    """Capture a previously approved PayPal Order."""
    token = self._get_access_token()
    resp = requests.post(
        f"{self._base_url}/v2/checkout/orders/{order_id}/capture",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    if resp.status_code in (200, 201):
        data = resp.json()
        capture = data["purchase_units"][0]["payments"]["captures"][0]
        return SDKResponse(success=True, data={
            "order_id": data["id"],
            "capture_id": capture["id"],
            "status": data["status"],  # "COMPLETED"
            "amount": capture["amount"]["value"],
            "currency": capture["amount"]["currency_code"],
        })
    return SDKResponse(success=False, error=resp.text, error_code=str(resp.status_code))
```

**Method: `create_subscription()`** — PayPal Billing Subscription (**recurring**)
```python
def create_subscription(self, plan_id: str, metadata: dict, success_url: str, cancel_url: str) -> SDKResponse:
    """Create PayPal Billing Subscription for recurring payments."""
    token = self._get_access_token()
    sub_data = {
        "plan_id": plan_id,
        "custom_id": metadata.get("invoice_id", ""),
        "application_context": {
            "return_url": success_url,
            "cancel_url": cancel_url,
            "user_action": "SUBSCRIBE_NOW",
        }
    }
    resp = requests.post(f"{self._base_url}/v1/billing/subscriptions", json=sub_data,
                         headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    if resp.status_code in (200, 201):
        data = resp.json()
        approve_url = next((l["href"] for l in data["links"] if l["rel"] == "approve"), None)
        return SDKResponse(success=True, data={
            "subscription_id": data["id"],
            "session_url": approve_url,
        })
    return SDKResponse(success=False, error=resp.text, error_code=str(resp.status_code))
```

**Method: `create_billing_plan()`** — Create PayPal Billing Plan (**recurring helper**)
```python
def create_billing_plan(self, name: str, amount: str, currency: str, interval: str, interval_count: int = 1) -> SDKResponse:
    """Create a PayPal Billing Plan for recurring subscriptions.

    PayPal requires a Plan to be created before a Subscription.
    Plans can be reused across subscribers.
    """
    token = self._get_access_token()
    plan_data = {
        "product_id": self._get_or_create_product(name),
        "name": name,
        "billing_cycles": [{
            "frequency": {
                "interval_unit": interval.upper(),  # DAY, WEEK, MONTH, YEAR
                "interval_count": interval_count,
            },
            "tenure_type": "REGULAR",
            "sequence": 1,
            "total_cycles": 0,  # infinite
            "pricing_scheme": {
                "fixed_price": {
                    "value": amount,
                    "currency_code": currency.upper(),
                }
            }
        }],
        "payment_preferences": {
            "auto_bill_outstanding": True,
            "payment_failure_threshold": 3,
        }
    }
    resp = requests.post(f"{self._base_url}/v1/billing/plans", json=plan_data,
                         headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    if resp.status_code in (200, 201):
        data = resp.json()
        return SDKResponse(success=True, data={"plan_id": data["id"]})
    return SDKResponse(success=False, error=resp.text, error_code=str(resp.status_code))
```

**Method: `get_payment_status()`** — Get order/subscription status
```python
def get_payment_status(self, order_id: str) -> SDKResponse:
    """Get PayPal Order status."""
    token = self._get_access_token()
    resp = requests.get(f"{self._base_url}/v2/checkout/orders/{order_id}",
                        headers={"Authorization": f"Bearer {token}"})
    if resp.status_code == 200:
        data = resp.json()
        return SDKResponse(success=True, data={
            "status": data["status"],  # CREATED, APPROVED, COMPLETED
            "amount_total": data["purchase_units"][0]["amount"]["value"],
            "currency": data["purchase_units"][0]["amount"]["currency_code"],
        })
    return SDKResponse(success=False, error=resp.text, error_code=str(resp.status_code))
```

**Method: `verify_webhook_signature()`**
```python
def verify_webhook_signature(self, payload: bytes, headers: dict, webhook_id: str) -> dict:
    """Verify PayPal webhook signature via PayPal API.

    PayPal requires calling their verify-webhook-signature endpoint
    (unlike Stripe which does local verification).
    """
    token = self._get_access_token()
    verify_data = {
        "auth_algo": headers.get("PAYPAL-AUTH-ALGO", ""),
        "cert_url": headers.get("PAYPAL-CERT-URL", ""),
        "transmission_id": headers.get("PAYPAL-TRANSMISSION-ID", ""),
        "transmission_sig": headers.get("PAYPAL-TRANSMISSION-SIG", ""),
        "transmission_time": headers.get("PAYPAL-TRANSMISSION-TIME", ""),
        "webhook_id": webhook_id,
        "webhook_event": json.loads(payload),
    }
    resp = requests.post(f"{self._base_url}/v1/notifications/verify-webhook-signature",
                         json=verify_data, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    if resp.status_code == 200:
        result = resp.json()
        if result.get("verification_status") == "SUCCESS":
            return json.loads(payload)
    raise ValueError("Invalid PayPal webhook signature")
```

**Method: `refund_payment()`**
```python
def refund_payment(self, capture_id: str, amount=None, idempotency_key=None) -> SDKResponse:
    """Refund a captured PayPal payment."""
    token = self._get_access_token()
    refund_data = {}
    if amount is not None:
        refund_data["amount"] = {"value": str(amount), "currency_code": "USD"}
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    if idempotency_key:
        headers["PayPal-Request-Id"] = idempotency_key
    resp = requests.post(f"{self._base_url}/v2/payments/captures/{capture_id}/refund",
                         json=refund_data, headers=headers)
    if resp.status_code in (200, 201):
        data = resp.json()
        return SDKResponse(success=True, data={"refund_id": data["id"], "status": data["status"]})
    return SDKResponse(success=False, error=resp.text, error_code=str(resp.status_code))
```

---

## Task 3: Backend — PayPal Plugin Class + Config

### Files
| File | Action |
|------|--------|
| `vbwd-backend/plugins/paypal/__init__.py` | **NEW** |
| `vbwd-backend/plugins/paypal/config.json` | **NEW** |
| `vbwd-backend/plugins/paypal/admin-config.json` | **NEW** |

### `__init__.py` — Class Design

**Critical**: Class MUST be defined in `__init__.py` (not re-exported) — discovery check `obj.__module__ != full_module` in `manager.py`.

**Inheritance chain:** `PayPalPlugin` → `PaymentProviderPlugin` → `BasePlugin`

```python
from src.plugins.payment_provider import PaymentProviderPlugin, PaymentResult, PaymentStatus
from src.plugins.base import PluginMetadata


class PayPalPlugin(PaymentProviderPlugin):
    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="paypal",
            version="1.0.0",
            author="VBWD Team",
            description="PayPal payment provider — Orders API with webhooks",
            dependencies=[],
        )

    def get_blueprint(self):
        from plugins.paypal.routes import paypal_plugin_bp
        return paypal_plugin_bp

    def get_url_prefix(self):
        return "/api/v1/plugins/paypal"

    def on_enable(self):
        pass  # Stateless — config read per-request from config_store

    def on_disable(self):
        pass

    # Abstract method implementations delegate to PayPalSDKAdapter
    def _get_adapter(self):
        from plugins.paypal.sdk_adapter import PayPalSDKAdapter
        from src.sdk.interface import SDKConfig
        from flask import current_app
        config_store = current_app.config_store
        config = config_store.get_config("paypal")
        return PayPalSDKAdapter(SDKConfig(
            api_key=config.get("client_id", ""),
            api_secret=config.get("client_secret", ""),
            sandbox=config.get("sandbox", True),
        ))

    def create_payment_intent(self, amount, currency, subscription_id, user_id, metadata=None):
        adapter = self._get_adapter()
        resp = adapter.create_payment_intent(amount, currency, metadata or {})
        if resp.success:
            return PaymentResult(success=True, transaction_id=resp.data["session_id"], status=PaymentStatus.PENDING)
        return PaymentResult(success=False, error_message=resp.error, status=PaymentStatus.FAILED)

    def process_payment(self, payment_intent_id, payment_method):
        adapter = self._get_adapter()
        resp = adapter.capture_order(payment_intent_id)
        if resp.success:
            return PaymentResult(success=True, transaction_id=resp.data["capture_id"], status=PaymentStatus.COMPLETED)
        return PaymentResult(success=False, error_message=resp.error, status=PaymentStatus.FAILED)

    def refund_payment(self, transaction_id, amount=None):
        adapter = self._get_adapter()
        resp = adapter.refund_payment(transaction_id, amount)
        if resp.success:
            return PaymentResult(success=True, transaction_id=resp.data["refund_id"], status=PaymentStatus.REFUNDED)
        return PaymentResult(success=False, error_message=resp.error, status=PaymentStatus.FAILED)

    def verify_webhook(self, payload, signature):
        adapter = self._get_adapter()
        from flask import current_app
        config = current_app.config_store.get_config("paypal")
        try:
            adapter.verify_webhook_signature(payload, signature, config.get("webhook_id", ""))
            return True
        except ValueError:
            return False

    def handle_webhook(self, payload):
        pass  # Handled in routes.py
```

### `config.json`
```json
{
  "client_id": { "type": "string", "default": "", "description": "PayPal Client ID (sandbox or live)" },
  "client_secret": { "type": "string", "default": "", "description": "PayPal Client Secret" },
  "webhook_id": { "type": "string", "default": "", "description": "PayPal Webhook ID for signature verification" },
  "sandbox": { "type": "boolean", "default": true, "description": "Use PayPal Sandbox environment" }
}
```

### `admin-config.json`
```json
{
  "tabs": [
    {
      "id": "credentials",
      "label": "Credentials",
      "fields": [
        { "key": "client_id", "label": "Client ID", "component": "input", "inputType": "text" },
        { "key": "client_secret", "label": "Client Secret", "component": "input", "inputType": "password" },
        { "key": "webhook_id", "label": "Webhook ID", "component": "input", "inputType": "text" },
        { "key": "sandbox", "label": "Sandbox Mode", "component": "checkbox" }
      ]
    }
  ]
}
```

---

## Task 4: Backend — PayPal Routes + Webhook

### Files
| File | Action |
|------|--------|
| `vbwd-backend/plugins/paypal/routes.py` | **NEW** |

### Blueprint

```python
paypal_plugin_bp = Blueprint("paypal_plugin", __name__)
```

### Route: `POST /create-order`

**Auth:** `@require_auth`

**Uses shared helpers, determines mode from invoice line items (same logic as Stripe).**

```python
@paypal_plugin_bp.route("/create-order", methods=["POST"])
@require_auth
def create_order():
    # 1. Shared helper: check plugin enabled
    config, err = check_plugin_enabled("paypal")
    if err: return err

    # 2. Shared helper: validate invoice
    data = request.get_json() or {}
    invoice, err = validate_invoice_for_payment(data.get("invoice_id", ""), g.user_id)
    if err: return err

    adapter = PayPalSDKAdapter(SDKConfig(
        api_key=config["client_id"],
        api_secret=config["client_secret"],
        sandbox=config.get("sandbox", True),
    ))
    mode = determine_session_mode(invoice)  # Reuse from Stripe — same function
    base_meta = {"invoice_id": str(invoice.id), "user_id": str(g.user_id)}
    success_url = f"{request.host_url}pay/paypal/success?token={{ORDER_ID}}"
    cancel_url = f"{request.host_url}pay/paypal/cancel"

    if mode == "subscription":
        # Recurring: create PayPal Billing Plan + Subscription
        plan_resp = _get_or_create_paypal_plan(adapter, invoice, config)
        if not plan_resp.success:
            return jsonify({"error": plan_resp.error}), 500
        response = adapter.create_subscription(
            plan_id=plan_resp.data["plan_id"],
            metadata=base_meta,
            success_url=success_url,
            cancel_url=cancel_url,
        )
        if response.success:
            return jsonify({
                "session_id": response.data.get("subscription_id"),
                "session_url": response.data.get("session_url"),
            }), 200
    else:
        # One-time: create PayPal Order
        response = adapter.create_payment_intent(
            amount=Decimal(str(invoice.total)),
            currency=invoice.currency or "USD",
            metadata={**base_meta, "success_url": success_url, "cancel_url": cancel_url},
        )
        if response.success:
            return jsonify(response.data), 200

    return jsonify({"error": response.error}), 500
```

### Route: `POST /capture-order` (**PayPal-specific — Stripe doesn't need this**)

**Auth:** `@require_auth`

PayPal requires explicit capture after buyer approval. Stripe captures automatically.

```python
@paypal_plugin_bp.route("/capture-order", methods=["POST"])
@require_auth
def capture_order():
    config, err = check_plugin_enabled("paypal")
    if err: return err

    data = request.get_json() or {}
    order_id = data.get("order_id")
    if not order_id:
        return jsonify({"error": "order_id required"}), 400

    adapter = PayPalSDKAdapter(SDKConfig(
        api_key=config["client_id"],
        api_secret=config["client_secret"],
        sandbox=config.get("sandbox", True),
    ))

    response = adapter.capture_order(order_id)
    if not response.success:
        return jsonify({"error": response.error}), 500

    # Find invoice from order metadata (custom_id)
    resp_data = response.data
    order_detail = adapter.get_payment_status(order_id)
    if order_detail.success:
        custom_id = _extract_custom_id(order_detail.data)
        if custom_id:
            # Emit PaymentCapturedEvent — event-driven, don't act directly
            emit_payment_captured(
                invoice_id=UUID(custom_id),
                payment_reference=order_id,
                amount=resp_data.get("amount", "0"),
                currency=resp_data.get("currency", "USD"),
                provider="paypal",
                transaction_id=resp_data.get("capture_id", ""),
            )

    return jsonify({
        "status": resp_data.get("status"),
        "order_id": order_id,
        "capture_id": resp_data.get("capture_id"),
    }), 200
```

### Route: `POST /webhook`

**Auth:** None (PayPal calls directly)

**Handles 5 event types:**

| PayPal Event | Our Action | Mode |
|-------------|-----------|------|
| `CHECKOUT.ORDER.APPROVED` | Optional — can skip (we capture explicitly) | One-time |
| `PAYMENT.CAPTURE.COMPLETED` | Emit `PaymentCapturedEvent` (backup if capture route missed) | One-time |
| `BILLING.SUBSCRIPTION.ACTIVATED` | Store `paypal_subscription_id`, emit `PaymentCapturedEvent` | Subscription |
| `PAYMENT.SALE.COMPLETED` | Renewal — create renewal invoice, emit `PaymentCapturedEvent` | Subscription |
| `BILLING.SUBSCRIPTION.CANCELLED` | Emit `SubscriptionCancelledEvent` | Subscription |
| `BILLING.SUBSCRIPTION.PAYMENT.FAILED` | Emit `PaymentFailedEvent` | Subscription |

```python
@paypal_plugin_bp.route("/webhook", methods=["POST"])
def paypal_webhook():
    config, err = check_plugin_enabled("paypal")
    if err: return err

    payload = request.get_data()
    headers = {
        "PAYPAL-AUTH-ALGO": request.headers.get("PAYPAL-AUTH-ALGO", ""),
        "PAYPAL-CERT-URL": request.headers.get("PAYPAL-CERT-URL", ""),
        "PAYPAL-TRANSMISSION-ID": request.headers.get("PAYPAL-TRANSMISSION-ID", ""),
        "PAYPAL-TRANSMISSION-SIG": request.headers.get("PAYPAL-TRANSMISSION-SIG", ""),
        "PAYPAL-TRANSMISSION-TIME": request.headers.get("PAYPAL-TRANSMISSION-TIME", ""),
    }

    adapter = PayPalSDKAdapter(SDKConfig(
        api_key=config["client_id"],
        api_secret=config["client_secret"],
        sandbox=config.get("sandbox", True),
    ))

    try:
        event = adapter.verify_webhook_signature(payload, headers, config.get("webhook_id", ""))
    except ValueError:
        return jsonify({"error": "Invalid signature"}), 400

    event_type = event.get("event_type", "")
    resource = event.get("resource", {})

    if event_type == "PAYMENT.CAPTURE.COMPLETED":
        _handle_capture_completed(resource)
    elif event_type == "BILLING.SUBSCRIPTION.ACTIVATED":
        _handle_subscription_activated(resource)
    elif event_type == "PAYMENT.SALE.COMPLETED":
        _handle_sale_completed(resource)
    elif event_type == "BILLING.SUBSCRIPTION.CANCELLED":
        _handle_subscription_cancelled(resource)
    elif event_type == "BILLING.SUBSCRIPTION.PAYMENT.FAILED":
        _handle_payment_failed(resource)

    return jsonify({"received": True}), 200
```

**Webhook Handlers:**

```python
def _handle_capture_completed(resource):
    """PayPal capture completed — one-time payment confirmed via webhook."""
    custom_id = resource.get("custom_id")
    if not custom_id:
        return
    # Deduplication: check if already processed
    container = current_app.container
    invoice_repo = container.invoice_repository()
    invoice = invoice_repo.find_by_id(UUID(custom_id))
    if not invoice or invoice.status.value != "pending":
        return
    capture_id = resource.get("id", "")
    amount = resource.get("amount", {}).get("value", "0")
    currency = resource.get("amount", {}).get("currency_code", "USD")
    emit_payment_captured(
        invoice_id=UUID(custom_id),
        payment_reference=capture_id,
        amount=amount,
        currency=currency,
        provider="paypal",
        transaction_id=capture_id,
    )

def _handle_subscription_activated(resource):
    """PayPal subscription activated — link subscription_id to our model."""
    paypal_sub_id = resource.get("id")
    custom_id = resource.get("custom_id")
    if not paypal_sub_id or not custom_id:
        return
    _link_paypal_subscription(UUID(custom_id), paypal_sub_id)
    emit_payment_captured(
        invoice_id=UUID(custom_id),
        payment_reference=paypal_sub_id,
        amount=resource.get("billing_info", {}).get("last_payment", {}).get("amount", {}).get("value", "0"),
        currency=resource.get("billing_info", {}).get("last_payment", {}).get("amount", {}).get("currency_code", "USD"),
        provider="paypal",
        transaction_id=paypal_sub_id,
    )

def _handle_sale_completed(resource):
    """PayPal subscription renewal payment completed."""
    billing_agreement_id = resource.get("billing_agreement_id")
    if not billing_agreement_id:
        return
    container = current_app.container
    sub_repo = container.subscription_repository()
    subscription = sub_repo.find_by_paypal_subscription_id(billing_agreement_id)
    if not subscription:
        return
    renewal_invoice = _create_renewal_invoice(subscription, resource)
    emit_payment_captured(
        invoice_id=renewal_invoice.id,
        payment_reference=resource.get("id", ""),
        amount=resource.get("amount", {}).get("total", "0"),
        currency=resource.get("amount", {}).get("currency", "USD"),
        provider="paypal",
        transaction_id=resource.get("id", ""),
    )

def _handle_subscription_cancelled(resource):
    """PayPal subscription cancelled."""
    paypal_sub_id = resource.get("id")
    if not paypal_sub_id:
        return
    sub_repo = current_app.container.subscription_repository()
    subscription = sub_repo.find_by_paypal_subscription_id(paypal_sub_id)
    if not subscription:
        return
    event = SubscriptionCancelledEvent(
        subscription_id=subscription.id,
        user_id=subscription.user_id,
        reason="paypal_subscription_cancelled",
        provider="paypal",
    )
    current_app.container.event_dispatcher().emit(event)

def _handle_payment_failed(resource):
    """PayPal subscription payment failed."""
    paypal_sub_id = resource.get("id")
    if not paypal_sub_id:
        return
    sub_repo = current_app.container.subscription_repository()
    subscription = sub_repo.find_by_paypal_subscription_id(paypal_sub_id)
    if not subscription:
        return
    event = PaymentFailedEvent(
        subscription_id=subscription.id,
        user_id=subscription.user_id,
        error_code="payment_failed",
        error_message="PayPal subscription payment failed",
        provider="paypal",
    )
    current_app.container.event_dispatcher().emit(event)
```

### Route: `GET /order-status/<order_id>`

**Auth:** `@require_auth`

```python
@paypal_plugin_bp.route("/session-status/<order_id>", methods=["GET"])
@require_auth
def order_status(order_id):
    config, err = check_plugin_enabled("paypal")
    if err: return err

    adapter = PayPalSDKAdapter(SDKConfig(
        api_key=config["client_id"],
        api_secret=config["client_secret"],
        sandbox=config.get("sandbox", True),
    ))
    response = adapter.get_payment_status(order_id)
    if not response.success:
        return jsonify({"error": response.error}), 500

    status = response.data.get("status", "")
    # Map PayPal statuses to our status format for composable compatibility
    mapped_status = "paid" if status == "COMPLETED" else status.lower()

    return jsonify({
        "status": mapped_status,
        "amount_total": response.data.get("amount_total"),
        "currency": response.data.get("currency"),
    }), 200
```

### Renewal Invoice Helper

```python
def _create_renewal_invoice(subscription, paypal_sale):
    """Create a renewal invoice from PayPal subscription sale event."""
    container = current_app.container
    invoice_repo = container.invoice_repository()

    # Deduplication
    sale_id = paypal_sale.get("id", "")
    existing = invoice_repo.find_by_paypal_order_id(sale_id)
    if existing:
        return existing

    plan = subscription.tarif_plan
    amount = Decimal(paypal_sale.get("amount", {}).get("total", "0"))
    currency = paypal_sale.get("amount", {}).get("currency", "USD").upper()

    renewal_invoice = UserInvoice(
        user_id=subscription.user_id,
        tarif_plan_id=plan.id if plan else None,
        subscription_id=subscription.id,
        amount=amount,
        total_amount=amount,
        currency=currency,
        status=InvoiceStatus.PENDING,
        payment_method="paypal",
        paypal_order_id=sale_id,
    )
    renewal_invoice.line_items.append(InvoiceLineItem(
        item_type=LineItemType.SUBSCRIPTION,
        item_id=subscription.id,
        description=f"Renewal: {plan.name}" if plan else "Subscription renewal",
        quantity=1,
        unit_price=amount,
        total_price=amount,
    ))
    invoice_repo.save(renewal_invoice)
    return renewal_invoice
```

### PayPal Subscription Linking Helper

```python
def _link_paypal_subscription(invoice_id, paypal_subscription_id):
    """Store paypal_subscription_id on our Subscription after activation."""
    container = current_app.container
    invoice_repo = container.invoice_repository()
    sub_repo = container.subscription_repository()

    invoice = invoice_repo.find_by_id(invoice_id)
    if not invoice:
        return

    for li in invoice.line_items:
        if li.item_type == LineItemType.SUBSCRIPTION:
            subscription = sub_repo.find_by_id(li.item_id)
            if subscription:
                subscription.paypal_subscription_id = paypal_subscription_id
                sub_repo.save(subscription)
                break
```

### Shared Helper: `determine_session_mode()` — Move to shared helpers

**IMPORTANT**: The `determine_session_mode()` function from Stripe's `routes.py` is needed by PayPal too. Move it to `src/plugins/payment_route_helpers.py` to avoid duplication.

```python
# In src/plugins/payment_route_helpers.py — add:
def determine_session_mode(invoice):
    """Check invoice line items to determine payment mode.

    Returns "subscription" if any line item is recurring, "payment" otherwise.
    Used by Stripe AND PayPal (and future providers).
    """
    for item in invoice.line_items:
        if item.item_type == LineItemType.SUBSCRIPTION:
            plan = _resolve_plan(item)
            if plan and plan.is_recurring:
                return "subscription"
        elif item.item_type == LineItemType.ADD_ON:
            addon = _resolve_addon(item)
            if addon and addon.is_recurring:
                return "subscription"
    return "payment"
```

---

## Task 5: Backend — Tests

### Files
| File | Action |
|------|--------|
| `vbwd-backend/plugins/paypal/__init__.py` (tests dir) | Ensure `plugins/paypal/tests/__init__.py` exists |
| `vbwd-backend/plugins/paypal/tests/conftest.py` | **NEW** |
| `vbwd-backend/plugins/paypal/tests/test_plugin.py` | **NEW** |
| `vbwd-backend/plugins/paypal/tests/test_sdk_adapter.py` | **NEW** |
| `vbwd-backend/plugins/paypal/tests/test_routes.py` | **NEW** |
| `vbwd-backend/plugins/paypal/tests/test_webhook.py` | **NEW** |
| `vbwd-backend/plugins/paypal/tests/test_recurring.py` | **NEW** |

### `conftest.py` — Shared Fixtures
```python
@pytest.fixture
def paypal_config():
    return {"client_id": "ATest123", "client_secret": "secret456",
            "webhook_id": "WH-789", "sandbox": True}

@pytest.fixture
def sdk_config():
    return SDKConfig(api_key="ATest123", api_secret="secret456", sandbox=True)

@pytest.fixture
def mock_paypal_api(mocker):
    """Mock requests.post/get for PayPal API calls."""
    mock = mocker.patch("plugins.paypal.sdk_adapter.requests")
    # Default: successful OAuth token
    token_resp = mocker.MagicMock()
    token_resp.status_code = 200
    token_resp.json.return_value = {"access_token": "test-token", "expires_in": 3600}
    mock.post.return_value = token_resp
    return mock

@pytest.fixture
def mock_config_store(mocker):
    store = mocker.MagicMock()
    store.get_by_name.return_value = PluginConfigEntry(plugin_name="paypal", status="enabled")
    store.get_config.return_value = paypal_config()
    return store
```

### `test_plugin.py` — Plugin Metadata & Lifecycle (~10 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_metadata_name` | `plugin.metadata.name == "paypal"` |
| 2 | `test_metadata_version` | `plugin.metadata.version == "1.0.0"` |
| 3 | `test_metadata_author` | `plugin.metadata.author == "VBWD Team"` |
| 4 | `test_inherits_payment_provider` | `isinstance(plugin, PaymentProviderPlugin)` |
| 5 | `test_inherits_base_plugin` | `isinstance(plugin, BasePlugin)` |
| 6 | `test_initial_status_discovered` | `plugin.status == PluginStatus.DISCOVERED` |
| 7 | `test_lifecycle` | DISCOVERED→INITIALIZED→ENABLED→DISABLED |
| 8 | `test_get_blueprint_returns_blueprint` | `isinstance(plugin.get_blueprint(), Blueprint)` |
| 9 | `test_get_url_prefix` | `plugin.get_url_prefix() == "/api/v1/plugins/paypal"` |
| 10 | `test_no_dependencies` | `plugin.metadata.dependencies == []` |

### `test_sdk_adapter.py` — SDK Adapter (~15 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_provider_name` | `adapter.provider_name == "paypal"` |
| 2 | `test_inherits_base_sdk_adapter` | `isinstance(adapter, BaseSDKAdapter)` |
| 3 | `test_get_access_token` | Calls OAuth2 endpoint, caches token |
| 4 | `test_get_access_token_refresh` | Re-fetches when expired |
| 5 | `test_create_payment_intent_success` | Calls Orders API, returns SDKResponse with session_id/url |
| 6 | `test_create_payment_intent_error` | Returns SDKResponse(success=False) |
| 7 | `test_create_payment_intent_amount_format` | `Decimal("29.99")` → `"29.99"` (not cents!) |
| 8 | `test_capture_order_success` | Calls capture endpoint, returns capture_id |
| 9 | `test_capture_order_error` | Returns SDKResponse(success=False) |
| 10 | `test_create_subscription_success` | Calls Billing Subscriptions API |
| 11 | `test_get_payment_status` | Returns status, amount_total, currency |
| 12 | `test_refund_full` | Calls refund endpoint without amount |
| 13 | `test_refund_partial` | Calls refund with specific amount |
| 14 | `test_verify_webhook_valid` | Calls verify endpoint, returns parsed event |
| 15 | `test_verify_webhook_invalid` | Raises ValueError |

### `test_routes.py` — Route Handlers (~15 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_create_order_requires_auth` | 401 without auth |
| 2 | `test_create_order_plugin_disabled` | 404 |
| 3 | `test_create_order_missing_invoice` | 400 |
| 4 | `test_create_order_invoice_not_found` | 404 |
| 5 | `test_create_order_invoice_not_pending` | 400 |
| 6 | `test_create_order_wrong_user` | 403 |
| 7 | `test_create_order_success` | 200 with session_id + session_url |
| 8 | `test_capture_order_requires_auth` | 401 |
| 9 | `test_capture_order_missing_order_id` | 400 |
| 10 | `test_capture_order_success` | 200, PaymentCapturedEvent emitted |
| 11 | `test_webhook_invalid_signature` | 400 |
| 12 | `test_webhook_plugin_disabled` | 404 |
| 13 | `test_webhook_capture_completed` | 200, PaymentCapturedEvent emitted |
| 14 | `test_webhook_ignores_other_events` | 200, no event emitted |
| 15 | `test_order_status_requires_auth` | 401 |
| 16 | `test_order_status_success` | 200 with mapped status |

### `test_webhook.py` — Event-Driven Verification (~6 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_emits_payment_captured_event` | `dispatcher.emit()` called with PaymentCapturedEvent |
| 2 | `test_event_correct_invoice_id` | `event.invoice_id == UUID(custom_id)` |
| 3 | `test_event_correct_amount` | `event.amount == resource.amount.value` |
| 4 | `test_event_correct_provider` | `event.provider == "paypal"` |
| 5 | `test_event_correct_transaction_id` | `event.transaction_id == capture_id` |
| 6 | `test_webhook_no_direct_domain_mutations` | NO calls to invoice_repository.save, subscription_repository.save |

### `test_recurring.py` — Recurring Billing Tests (~12 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_determine_mode_recurring_plan` | Returns `"subscription"` for monthly plan |
| 2 | `test_determine_mode_one_time` | Returns `"payment"` for ONE_TIME |
| 3 | `test_create_order_subscription_mode` | PayPal Subscription created (not Order) |
| 4 | `test_webhook_subscription_activated_links` | `paypal_subscription_id` stored on Subscription |
| 5 | `test_webhook_subscription_activated_emits` | `PaymentCapturedEvent` emitted |
| 6 | `test_webhook_sale_completed_creates_renewal` | Renewal invoice created |
| 7 | `test_webhook_sale_completed_deduplication` | Same sale_id not processed twice |
| 8 | `test_webhook_subscription_cancelled` | `SubscriptionCancelledEvent` emitted |
| 9 | `test_webhook_payment_failed` | `PaymentFailedEvent` emitted |
| 10 | `test_renewal_invoice_has_line_items` | Renewal invoice has subscription line item |
| 11 | `test_link_paypal_subscription` | Subscription.paypal_subscription_id set |
| 12 | `test_capture_order_emits_event` | Capture route emits PaymentCapturedEvent |

**Backend test target: 737 → ~795 (+58: 10 plugin + 15 adapter + 16 routes + 6 webhook + 12 recurring — some overlap with shared helpers already tested)**

---

## Task 6: Frontend — PayPal Payment Plugin Views

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/plugins/paypal-payment/index.ts` | **NEW** |
| `vbwd-frontend/user/plugins/paypal-payment/PayPalPaymentView.vue` | **NEW** |
| `vbwd-frontend/user/plugins/paypal-payment/PayPalSuccessView.vue` | **NEW** |
| `vbwd-frontend/user/plugins/paypal-payment/PayPalCancelView.vue` | **NEW** |
| `vbwd-frontend/user/plugins/paypal-payment/config.json` | **NEW** |
| `vbwd-frontend/user/plugins/paypal-payment/admin-config.json` | **NEW** |

### `index.ts` — Plugin Registration

```typescript
import type { IPlugin, IPlatformSDK } from '@vbwd/view-component';

export const paypalPaymentPlugin: IPlugin = {
  name: 'paypal-payment',
  version: '1.0.0',
  description: 'PayPal payment processing — redirects to PayPal Checkout',
  _active: false,

  install(sdk: IPlatformSDK) {
    sdk.addRoute({
      path: '/pay/paypal',
      name: 'paypal-payment',
      component: () => import('./PayPalPaymentView.vue'),
      meta: { requiresAuth: true }
    });
    sdk.addRoute({
      path: '/pay/paypal/success',
      name: 'paypal-success',
      component: () => import('./PayPalSuccessView.vue'),
      meta: { requiresAuth: true }
    });
    sdk.addRoute({
      path: '/pay/paypal/cancel',
      name: 'paypal-cancel',
      component: () => import('./PayPalCancelView.vue'),
      meta: { requiresAuth: true }
    });
  },

  activate() { this._active = true; },
  deactivate() { this._active = false; }
};
```

### `PayPalPaymentView.vue` — Uses Shared Composable

```html
<template>
  <div class="paypal-payment">
    <div v-if="loading">{{ $t('paypal.payment.redirecting') }}</div>
    <div v-else-if="error">
      <p>{{ error }}</p>
      <button @click="createAndRedirect">{{ $t('paypal.payment.retry') }}</button>
    </div>
    <div v-else-if="!invoiceId">
      <p>{{ $t('paypal.payment.noInvoice') }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { usePaymentRedirect } from '@vbwd/view-component';
import { api } from '@/api';

const { loading, error, invoiceId, readInvoiceFromQuery, createAndRedirect } =
  usePaymentRedirect('/api/v1/plugins/paypal', api);

onMounted(() => {
  readInvoiceFromQuery();
  if (invoiceId.value) {
    createAndRedirect();
  }
});
</script>
```

**PayPal-specific code: zero.** All logic lives in the shared composable. The only difference from Stripe is the API prefix string.

### `PayPalSuccessView.vue` — Uses Shared Composable + PayPal Capture

**Key difference from Stripe**: PayPal requires an explicit capture step after the user returns. The SuccessView must call `POST /capture-order` before polling status.

```html
<template>
  <div class="paypal-success">
    <div v-if="capturing || polling">{{ $t('paypal.success.verifying') }}</div>
    <div v-else-if="confirmed">
      <h2>{{ $t('paypal.success.title') }}</h2>
      <p>{{ $t('paypal.success.message') }}</p>
      <router-link to="/dashboard/invoices">{{ $t('paypal.success.viewInvoices') }}</router-link>
    </div>
    <div v-else-if="timedOut">
      <p>{{ $t('paypal.success.processing') }}</p>
    </div>
    <div v-else-if="error">
      <p>{{ error }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { usePaymentStatus } from '@vbwd/view-component';
import { api } from '@/api';

const route = useRoute();
const capturing = ref(false);
const captureError = ref<string | null>(null);

const { polling, confirmed, timedOut, error, sessionId, readSessionFromQuery, startPolling } =
  usePaymentStatus('/api/v1/plugins/paypal', api);

async function captureAndPoll() {
  // PayPal returns ?token=<order_id> (or ?subscription_id=<id> for recurring)
  const orderId = route.query.token as string || route.query.subscription_id as string;
  if (!orderId) {
    captureError.value = 'No order ID received from PayPal';
    return;
  }

  // For subscriptions (subscription_id param), skip capture — just poll status
  if (route.query.subscription_id) {
    sessionId.value = orderId;
    startPolling();
    return;
  }

  // For one-time orders, capture first
  capturing.value = true;
  try {
    await api.post('/api/v1/plugins/paypal/capture-order', { order_id: orderId });
    // After capture, poll for confirmation
    sessionId.value = orderId;
    capturing.value = false;
    startPolling();
  } catch (e: any) {
    capturing.value = false;
    captureError.value = e?.response?.data?.error || 'Capture failed';
  }
}

onMounted(() => {
  captureAndPoll();
});
</script>
```

### `PayPalCancelView.vue` — Simple Static

```html
<template>
  <div class="paypal-cancel">
    <h2>{{ $t('paypal.cancel.title') }}</h2>
    <p>{{ $t('paypal.cancel.message') }}</p>
    <router-link to="/checkout">{{ $t('paypal.cancel.tryAgain') }}</router-link>
  </div>
</template>
```

### Config Files

**`config.json`:**
```json
{
  "clientId": {
    "type": "string",
    "default": "",
    "description": "PayPal Client ID for frontend SDK (if needed)"
  }
}
```

**`admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "credentials",
      "label": "Credentials",
      "fields": [
        { "key": "clientId", "label": "Client ID", "component": "input", "inputType": "text" }
      ]
    }
  ]
}
```

---

## Task 7: Frontend — Checkout Integration + i18n

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/src/main.ts` | Add paypalPaymentPlugin |
| `vbwd-frontend/user/plugins/plugins.json` | Add paypal-payment entry |
| `vbwd-frontend/user/plugins/checkout/PublicCheckoutView.vue` | Add PayPal redirect |
| `vbwd-frontend/user/vue/src/views/Checkout.vue` | Add PayPal redirect |
| `vbwd-frontend/user/vue/src/i18n/locales/en.json` | Add paypal.* keys |
| `vbwd-frontend/user/vue/src/i18n/locales/de.json` | Add paypal.* keys |

### `main.ts` — Add Plugin
```typescript
import { paypalPaymentPlugin } from '../../plugins/paypal-payment';

const availablePlugins: Record<string, IPlugin> = {
  landing1: landing1Plugin,
  checkout: checkoutPlugin,
  'stripe-payment': stripePaymentPlugin,
  'paypal-payment': paypalPaymentPlugin,
};
```

### `plugins.json` — Add Entry
```json
{
  "paypal-payment": {
    "name": "paypal-payment",
    "version": "1.0.0",
    "description": "PayPal payment processing",
    "enabled": true,
    "installed": true
  }
}
```

### Checkout Redirect Logic

In both `PublicCheckoutView.vue` and `Checkout.vue`, after successful checkout — add alongside existing Stripe check:
```typescript
// Existing Stripe redirect
if (checkoutStore.paymentMethodCode === 'stripe') {
  router.push({ path: '/pay/stripe', query: { invoice: invoiceId } });
  return;
}
// NEW: PayPal redirect
if (checkoutStore.paymentMethodCode === 'paypal') {
  router.push({ path: '/pay/paypal', query: { invoice: invoiceId } });
  return;
}
```

### i18n — English
```json
{
  "paypal": {
    "payment": {
      "redirecting": "Redirecting to PayPal...",
      "retry": "Try Again",
      "error": "Failed to create payment session",
      "noInvoice": "No invoice specified. Please complete checkout first."
    },
    "success": {
      "title": "Payment Successful",
      "message": "Your PayPal payment has been processed. Your subscription is now active.",
      "verifying": "Verifying payment...",
      "processing": "Your payment is being processed. This may take a moment.",
      "viewInvoices": "View Invoices"
    },
    "cancel": {
      "title": "Payment Cancelled",
      "message": "Your PayPal payment was cancelled. Your invoice is still pending.",
      "tryAgain": "Try Again"
    }
  }
}
```

### i18n — German
```json
{
  "paypal": {
    "payment": {
      "redirecting": "Weiterleitung zu PayPal...",
      "retry": "Erneut versuchen",
      "error": "Zahlungssitzung konnte nicht erstellt werden",
      "noInvoice": "Keine Rechnung angegeben. Bitte schließen Sie zuerst den Checkout ab."
    },
    "success": {
      "title": "Zahlung erfolgreich",
      "message": "Ihre PayPal-Zahlung wurde verarbeitet. Ihr Abonnement ist jetzt aktiv.",
      "verifying": "Zahlung wird überprüft...",
      "processing": "Ihre Zahlung wird verarbeitet. Dies kann einen Moment dauern.",
      "viewInvoices": "Rechnungen anzeigen"
    },
    "cancel": {
      "title": "Zahlung abgebrochen",
      "message": "Ihre PayPal-Zahlung wurde abgebrochen. Ihre Rechnung ist noch ausstehend.",
      "tryAgain": "Erneut versuchen"
    }
  }
}
```

---

## Task 8: Frontend — Tests

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/tests/unit/plugins/paypal-payment.spec.ts` | **NEW** |
| `vbwd-frontend/user/vue/tests/unit/plugins/paypal-views.spec.ts` | **NEW** |

### PayPal Plugin Tests (~6 tests)

**`paypal-payment.spec.ts`:**

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_plugin_name` | `'paypal-payment'` |
| 2 | `test_plugin_version` | `'1.0.0'` |
| 3 | `test_install_adds_three_routes` | `sdk.getRoutes().length === 3` |
| 4 | `test_routes_paths` | `/pay/paypal`, `/pay/paypal/success`, `/pay/paypal/cancel` |
| 5 | `test_routes_require_auth` | All `meta.requiresAuth === true` |
| 6 | `test_activate_deactivate` | `_active` toggles |

### PayPal View Tests (~10 tests)

**`paypal-views.spec.ts`:**

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_payment_view_shows_loading` | Loading text on mount |
| 2 | `test_payment_view_error_no_invoice` | Error when no query param |
| 3 | `test_payment_view_calls_api` | POSTs to `/api/v1/plugins/paypal/create-order` |
| 4 | `test_payment_view_error_on_fail` | Shows error + retry on API fail |
| 5 | `test_success_view_shows_verifying` | Verifying text on mount |
| 6 | `test_success_view_captures_order` | POSTs to `/capture-order` for one-time |
| 7 | `test_success_view_skips_capture_for_subscription` | No capture call when `subscription_id` param |
| 8 | `test_success_view_polls_status` | GETs session-status after capture |
| 9 | `test_success_view_shows_confirmation` | Shows success on "paid" |
| 10 | `test_cancel_view_renders` | Cancel message + retry link |

**Frontend test target: 169 → ~185 (+16: 6 plugin + 10 views)**

---

## Task 9: Refactor — Move `determine_session_mode()` to Shared Helpers

### Files
| File | Action |
|------|--------|
| `vbwd-backend/src/plugins/payment_route_helpers.py` | **MODIFY** — add `determine_session_mode()` |
| `vbwd-backend/plugins/stripe/routes.py` | **MODIFY** — import from shared helpers |

This is a small refactoring: extract `determine_session_mode()` from Stripe routes into shared `payment_route_helpers.py` so both Stripe and PayPal use it without duplication.

---

## Implementation Order & Dependencies

```
Task 1: DB Migration — paypal_subscription_id, paypal_order_id (no deps)
Task 9: Refactor — move determine_session_mode() to shared helpers (no deps)
  ↓ (Tasks 1 & 9 can run in parallel)
Task 2: PayPal SDK Adapter (deps: requirements.txt)
  ↓
Task 3: PayPal Plugin Class + Config (deps: Task 2)
  ↓
Task 4: PayPal Routes + Webhook (deps: Tasks 1, 3, 9)
  ↓
Task 5: Backend Tests (deps: Tasks 1, 2, 3, 4, 9)
  ↓
Task 6: Frontend Plugin Views (deps: none — uses existing composables)
  ↓
Task 7: Checkout Integration + i18n (deps: Task 6)
  ↓
Task 8: Frontend Tests (deps: Tasks 6, 7)
```

---

## New Files Summary

**PayPal backend (11 files):**
```
plugins/paypal/
├── __init__.py              ← PayPalPlugin(PaymentProviderPlugin)
├── sdk_adapter.py           ← PayPalSDKAdapter(BaseSDKAdapter)
├── routes.py                ← create-order, capture-order, webhook, session-status
├── config.json              ← Config schema
├── admin-config.json        ← Admin UI layout
└── tests/
    ├── __init__.py
    ├── conftest.py
    ├── test_plugin.py
    ├── test_sdk_adapter.py
    ├── test_routes.py
    ├── test_webhook.py
    └── test_recurring.py
```

**PayPal frontend (8 files):**
```
user/plugins/paypal-payment/
├── index.ts                 ← Plugin with 3 routes
├── PayPalPaymentView.vue    ← Uses usePaymentRedirect (shared)
├── PayPalSuccessView.vue    ← Capture + usePaymentStatus (shared)
├── PayPalCancelView.vue     ← Static cancel page
├── config.json
├── admin-config.json
user/vue/tests/unit/plugins/
├── paypal-payment.spec.ts
├── paypal-views.spec.ts
```

**DB migration (1 file):**
```
vbwd-backend/alembic/versions/xxxx_add_paypal_fields.py
```

**Modified files (8):**
- `vbwd-backend/requirements.txt` — add PayPal SDK dependency
- `vbwd-backend/src/models/subscription.py` — add `paypal_subscription_id`
- `vbwd-backend/src/models/invoice.py` — add `paypal_order_id`
- `vbwd-backend/src/plugins/payment_route_helpers.py` — add `determine_session_mode()`
- `vbwd-backend/plugins/stripe/routes.py` — import `determine_session_mode` from shared
- `vbwd-frontend/user/vue/src/main.ts` — add paypalPaymentPlugin
- `vbwd-frontend/user/plugins/plugins.json` — add paypal-payment entry
- `vbwd-frontend/user/plugins/checkout/PublicCheckoutView.vue` — add PayPal redirect
- `vbwd-frontend/user/vue/src/views/Checkout.vue` — add PayPal redirect
- `vbwd-frontend/user/vue/src/i18n/locales/en.json` — add paypal.* keys
- `vbwd-frontend/user/vue/src/i18n/locales/de.json` — add paypal.* keys

## Test Targets

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| Backend | 737 | ~795 | +58 (PayPal plugin tests) |
| Core | 289 | 289 | 0 (no changes) |
| User | 169 | ~185 | +16 (PayPal plugin + views) |
| Admin | 331 | 331 | 0 (no changes) |
| **Total** | **1526** | **~1600** | **+74** |

## Verification Commands

```bash
# 1. Backend — all tests including PayPal plugin
cd vbwd-backend && make test-unit

# 2. Backend — PayPal plugin tests only
cd vbwd-backend && docker compose run --rm test pytest plugins/paypal/tests/ -v

# 3. User frontend tests
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 4. Admin regression
cd vbwd-frontend/admin/vue && npx vitest run

# 5. Core regression
cd vbwd-frontend/core && npx vitest run

# 6. Full pre-commit check
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit

# 7. Rebuild containers
cd vbwd-frontend && docker compose up -d --build user-app admin-app
```
