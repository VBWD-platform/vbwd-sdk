# Sprint 24: Stripe Payment Plugin (Backend + Frontend)

## Goal
Add Stripe payment processing as a plugin. Extract reusable payment abstractions into shared layers (`@vbwd/view-component` and `src/plugins/`) so future providers (PayPal, Amazon Pay, AliPay) implement thin wrappers, not duplicate code.

## Engineering Principles
- **TDD**: Tests first — write tests before implementation, validate against interfaces
- **SOLID**: Single responsibility, Open/closed, Liskov substitution, Interface segregation, Dependency inversion
- **Liskov Substitution**: `StripeSDKAdapter` is interchangeable with any `ISDKAdapter`; `StripePlugin` with any `PaymentProviderPlugin`
- **DI**: Dependencies injected via container/config, never hardcoded
- **Clean Code**: Readable, self-documenting, minimal comments
- **DRY**: Reuse existing base classes, events, handlers — no duplication. Extract shared payment route helpers + frontend composables so the next payment provider is a thin wrapper
- **No overengineering**: Minimum code needed for the current task, no speculative abstractions
- **No backward compatibility**: Delete/replace freely, no shims or re-exports

## Testing Approach

All tests MUST pass before the sprint is considered complete. Run via:

```bash
# 1. Quick local validation (user unit tests)
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Admin regression (no admin code changes, but verify)
cd vbwd-frontend/admin/vue && npx vitest run

# 3. Full pre-commit check (admin + user)
cd vbwd-frontend && ./bin/pre-commit-check.sh --admin --user --unit

# 4. Core regression
cd vbwd-frontend/core && npx vitest run
```


## Feature Requirements
1. **Event-driven**: Stripe plugin emits `PaymentCapturedEvent` on webhook — NEVER acts directly on invoices/subscriptions. Existing `PaymentCapturedHandler` does all activation.
2. **Backend plugin** extends `PaymentProviderPlugin`, uses `StripeSDKAdapter(BaseSDKAdapter)` with Stripe SDK v18
3. **Frontend plugin** extends checkout — redirects to `/pay/stripe?invoice=<id>` when Stripe is selected as payment method
4. **Stripe Checkout Session flow** (redirect-based, PCI-compliant) — no card data touches our servers
5. **Admin configurable** via plugin config (publishable_key, secret_key, webhook_secret, sandbox mode)
6. **Multi-worker safe** — routes read config from `config_store` per-request, not in-memory
7. **Shared abstractions**: Backend route helpers in `src/plugins/payment_route_helpers.py`, frontend composables in `@vbwd/view-component`

## Architecture: Shared vs. Provider-Specific

### What Already Exists (no changes needed)
| Layer | File | Provides |
|-------|------|----------|
| SDK interface | `src/sdk/interface.py` | `ISDKAdapter`, `SDKConfig`, `SDKResponse` |
| SDK base | `src/sdk/base.py` | `BaseSDKAdapter` with `_with_retry()`, `_with_idempotency()` |
| Idempotency | `src/sdk/idempotency_service.py` | Redis-backed idempotency caching |
| SDK registry | `src/sdk/registry.py` | `SDKAdapterRegistry` central lookup |
| Plugin base | `src/plugins/base.py` | `BasePlugin`, `PluginMetadata`, lifecycle |
| Payment base | `src/plugins/payment_provider.py` | `PaymentProviderPlugin`, `PaymentResult`, `PaymentStatus` |
| Plugin manager | `src/plugins/manager.py` | Discovery, lifecycle, blueprint registration |
| Config store | `src/plugins/config_store.py` | `PluginConfigStore` interface (JSON-file impl) |
| Events | `src/events/payment_events.py` | `PaymentCapturedEvent`, `PaymentFailedEvent`, `PaymentRefundedEvent` |
| Handler | `src/handlers/payment_handler.py` | `PaymentCapturedHandler` (invoice→PAID, subscription→ACTIVE, tokens credited) |
| FE plugin system | `core/src/plugins/` | `PluginRegistry`, `PlatformSDK`, `IPlugin`, `IPlatformSDK` |
| FE API client | `core/src/api/` | `ApiClient` with auth, interceptors |
| FE event bus | `core/src/events/` | `EventBus` with payment event types already defined |

### What This Sprint Adds — Shared (reused by all future providers)
| Layer | File | Provides |
|-------|------|----------|
| **Backend** | `src/plugins/payment_route_helpers.py` | `check_plugin_enabled()`, `validate_invoice_for_payment()`, `emit_payment_captured()` |
| **Frontend** | `core/src/composables/usePaymentRedirect.ts` | Create-session → redirect flow (loading, error, retry) |
| **Frontend** | `core/src/composables/usePaymentStatus.ts` | Poll session status (polling, confirmed, timeout) |
| **Frontend** | `core/src/composables/index.ts` | Re-export new composables |
| **Frontend** | `core/src/index.ts` | Already re-exports `composables` |

### What This Sprint Adds — Stripe-Specific
| Layer | File | Provides |
|-------|------|----------|
| Backend | `plugins/stripe/sdk_adapter.py` | `StripeSDKAdapter(BaseSDKAdapter)` |
| Backend | `plugins/stripe/__init__.py` | `StripePlugin(PaymentProviderPlugin)` |
| Backend | `plugins/stripe/routes.py` | create-session, webhook, session-status (uses shared helpers) |
| Backend | `plugins/stripe/config.json` | Config schema |
| Backend | `plugins/stripe/admin-config.json` | Admin UI layout |
| Backend | `plugins/stripe/tests/` | 42 tests |
| Frontend | `user/plugins/stripe-payment/index.ts` | Plugin with 3 routes |
| Frontend | `user/plugins/stripe-payment/*.vue` | 3 views (use shared composables) |
| Frontend | `user/plugins/stripe-payment/config.json` | Frontend config schema |
| Frontend | `user/plugins/stripe-payment/admin-config.json` | Frontend admin UI |

### How Future Providers Benefit
A PayPal plugin would only need:
```
# Backend (5 files)
plugins/paypal/__init__.py          ← PayPalPlugin(PaymentProviderPlugin)
plugins/paypal/sdk_adapter.py       ← PayPalSDKAdapter(BaseSDKAdapter)
plugins/paypal/routes.py            ← Uses same payment_route_helpers
plugins/paypal/config.json
plugins/paypal/admin-config.json

# Frontend (5 files)
user/plugins/paypal-payment/index.ts           ← 3 routes
user/plugins/paypal-payment/PayPalPaymentView.vue  ← Uses usePaymentRedirect()
user/plugins/paypal-payment/PayPalSuccessView.vue  ← Uses usePaymentStatus()
user/plugins/paypal-payment/PayPalCancelView.vue
```
No duplication of invoice validation, event emission, polling, or redirect logic.

## Payment Flows

### Flow A: One-Time Payment (token bundles, ONE_TIME plans, one-time add-ons)
```
1. User completes checkout → POST /user/checkout → PENDING invoice created
2. Frontend detects payment_method_code == "stripe" in checkout result
3. Frontend redirects to /pay/stripe?invoice=<invoice_id>
4. StripePaymentView uses usePaymentRedirect('/api/v1/plugins/stripe')
5. Composable calls POST /api/v1/plugins/stripe/create-session { invoice_id }
6. Route detects: invoice has NO recurring items → mode="payment"
7. Route creates Stripe Checkout Session (one-time)
8. Returns { session_url } → redirect to Stripe
9. User pays → Stripe sends webhook: checkout.session.completed
10. Webhook emits PaymentCapturedEvent → handler activates items, marks invoice PAID
11. User returns to /pay/stripe/success → confirmation
```

### Flow B: Recurring Payment (recurring plans, recurring add-ons)
```
1. User completes checkout → POST /user/checkout → PENDING invoice + PENDING subscription
2. Frontend redirects to /pay/stripe?invoice=<invoice_id>
3. POST /api/v1/plugins/stripe/create-session { invoice_id }
4. Route detects: invoice has recurring items (plan.is_recurring or addon.is_recurring)
5. Route creates/retrieves Stripe Customer (linked to User.stripe_customer_id)
6. Route creates Stripe Checkout Session with mode="subscription"
   - Recurring plan → Stripe Price (recurring interval from billing_period)
   - Recurring add-ons → additional Stripe Price items
   - One-time items on same invoice (token bundles) → NOT included (separate payment)
7. Returns { session_url } → redirect to Stripe
8. User pays → Stripe sends webhook: checkout.session.completed
9. Webhook: stores stripe_subscription_id on Subscription + AddOnSubscription
10. Webhook emits PaymentCapturedEvent → handler activates subscription, marks invoice PAID
11. User returns to /pay/stripe/success → confirmation

--- RENEWAL (automatic, no user action) ---
12. Stripe auto-charges at billing_period end → sends webhook: invoice.paid
13. Webhook: creates renewal invoice in our system, emits PaymentCapturedEvent
14. Handler extends subscription.expires_at by billing_period days, marks invoice PAID

--- CANCELLATION ---
15. Stripe sends webhook: customer.subscription.deleted
16. Webhook emits SubscriptionCancelledEvent → handler marks subscription CANCELLED

--- PAYMENT FAILURE ---
17. Stripe sends webhook: invoice.payment_failed
18. Webhook emits PaymentFailedEvent → handler can notify user / mark subscription past_due
```

### Mode Selection Logic (create-session route)
```python
def determine_session_mode(invoice):
    """Check invoice line items to determine Stripe Checkout mode."""
    for item in invoice.line_items:
        if item.item_type == LineItemType.SUBSCRIPTION:
            plan = get_plan(item)  # resolve tarif_plan
            if plan and plan.is_recurring:
                return "subscription"
        elif item.item_type == LineItemType.ADD_ON:
            addon = get_addon(item)  # resolve add-on
            if addon and addon.is_recurring:
                return "subscription"
    return "payment"  # default: one-time
```

---

## Task 1: Shared — Backend Payment Route Helpers

### Files
| File | Action |
|------|--------|
| `vbwd-backend/src/plugins/payment_route_helpers.py` | **NEW** |

### Purpose
Three helper functions that every payment plugin route will call. Eliminates the need for each provider to duplicate config_store checks, invoice validation, and event emission.

### `check_plugin_enabled(plugin_name: str) -> Tuple[dict, None] | Tuple[None, Response]`

Returns `(config, None)` on success or `(None, error_response)` on failure.

```python
def check_plugin_enabled(plugin_name: str):
    """Check plugin is enabled via config_store and return its config.

    Every payment route calls this first. Reads from shared JSON config_store
    (multi-worker safe — no in-memory state).

    Returns:
        (config_dict, None) if plugin is enabled
        (None, (json_response, status_code)) if plugin disabled or unavailable
    """
    config_store = getattr(current_app, "config_store", None)
    if not config_store:
        return None, (jsonify({"error": "Plugin system not available"}), 503)

    entry = config_store.get_by_name(plugin_name)
    if not entry or entry.status != "enabled":
        return None, (jsonify({"error": "Plugin not enabled"}), 404)

    config = config_store.get_config(plugin_name)
    return config, None
```

### `validate_invoice_for_payment(invoice_id_str: str, user_id: UUID) -> Tuple[Invoice, None] | Tuple[None, Response]`

Returns `(invoice, None)` on success or `(None, error_response)` on failure.

```python
def validate_invoice_for_payment(invoice_id_str, user_id):
    """Validate invoice exists, is PENDING, and belongs to user.

    Every payment create-session route calls this after parsing request body.
    Uses DI container from current_app for request-scoped repository.

    Validates:
        - invoice_id is a valid UUID
        - Invoice exists in database
        - Invoice status is PENDING
        - Invoice belongs to the requesting user

    Returns:
        (invoice, None) if valid
        (None, (json_response, status_code)) if invalid
    """
    # Parse UUID
    try:
        invoice_uuid = UUID(invoice_id_str) if isinstance(invoice_id_str, str) else invoice_id_str
    except (ValueError, TypeError):
        return None, (jsonify({"error": "Invalid invoice_id format"}), 400)

    # Load invoice
    container = current_app.container
    invoice_repo = container.invoice_repository()
    invoice = invoice_repo.find_by_id(invoice_uuid)

    if not invoice:
        return None, (jsonify({"error": "Invoice not found"}), 404)
    if invoice.status.value != "pending":
        return None, (jsonify({"error": f"Invoice is {invoice.status.value}, expected pending"}), 400)
    if str(invoice.user_id) != str(user_id):
        return None, (jsonify({"error": "Invoice does not belong to this user"}), 403)

    return invoice, None
```

### `emit_payment_captured(invoice_id, payment_reference, amount, currency, provider, transaction_id="") -> EventResult`

Emits `PaymentCapturedEvent` via `DomainEventDispatcher.emit()`. Every webhook handler calls this.

```python
def emit_payment_captured(invoice_id, payment_reference, amount, currency, provider, transaction_id=""):
    """Emit PaymentCapturedEvent — the ONLY action a webhook handler should take.

    Event-driven: the webhook route emits this event and returns 200.
    PaymentCapturedHandler handles all activation (invoice→PAID, subscription→ACTIVE, etc.)
    The payment plugin NEVER acts directly on domain objects.

    Args:
        invoice_id: UUID of the invoice
        payment_reference: Provider session/order ID
        amount: Payment amount as string (e.g. "29.99")
        currency: ISO currency code (e.g. "usd")
        provider: Provider name (e.g. "stripe")
        transaction_id: Provider transaction/payment_intent ID

    Returns:
        EventResult from the handler chain
    """
    event = PaymentCapturedEvent(
        invoice_id=invoice_id,
        payment_reference=payment_reference,
        amount=amount,
        currency=currency,
        provider=provider,
        transaction_id=transaction_id,
    )
    container = current_app.container
    return container.event_dispatcher().emit(event)  # .emit() NOT .dispatch()
```

---

## Task 2: Shared — Frontend Payment Composables

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/core/src/composables/usePaymentRedirect.ts` | **NEW** |
| `vbwd-frontend/core/src/composables/usePaymentStatus.ts` | **NEW** |
| `vbwd-frontend/core/src/composables/index.ts` | **MODIFY** — add exports |

### `usePaymentRedirect(apiPrefix: string)`

Encapsulates the create-session → redirect flow. Every payment provider's PaymentView uses this.

```typescript
import { ref } from 'vue';
import { useRoute } from 'vue-router';
import api from '../api';

/**
 * Composable for payment redirect flow.
 *
 * Handles: read invoice from query → POST create-session → redirect to provider.
 * Reused by Stripe, PayPal, Amazon Pay, AliPay, etc.
 *
 * @param apiPrefix - Provider's API prefix (e.g. '/api/v1/plugins/stripe')
 */
export function usePaymentRedirect(apiPrefix: string) {
  const route = useRoute();
  const loading = ref(false);
  const error = ref<string | null>(null);
  const invoiceId = ref<string | null>(null);

  // Read invoice ID from route query
  function readInvoiceFromQuery(): string | null {
    const id = route.query.invoice as string | undefined;
    invoiceId.value = id || null;
    return invoiceId.value;
  }

  // Call create-session and redirect
  async function createAndRedirect(): Promise<void> {
    const id = invoiceId.value || readInvoiceFromQuery();
    if (!id) {
      error.value = 'No invoice specified';
      return;
    }

    loading.value = true;
    error.value = null;

    try {
      const response = await api.post(`${apiPrefix}/create-session`, {
        invoice_id: id
      });
      const { session_url } = response.data;
      if (session_url) {
        window.location.href = session_url;
      } else {
        error.value = 'No redirect URL received';
      }
    } catch (e: any) {
      error.value = e?.response?.data?.error || e?.message || 'Payment session failed';
      loading.value = false;
    }
  }

  return {
    loading,      // Ref<boolean> — true while creating session
    error,        // Ref<string | null> — error message
    invoiceId,    // Ref<string | null> — parsed from query
    readInvoiceFromQuery,
    createAndRedirect,
  };
}
```

### `usePaymentStatus(apiPrefix: string)`

Encapsulates polling session status. Every payment provider's SuccessView uses this.

```typescript
import { ref, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import api from '../api';

/**
 * Composable for polling payment status.
 *
 * Handles: read session_id from query → poll status endpoint → determine completion.
 * Reused by Stripe, PayPal, Amazon Pay, AliPay, etc.
 *
 * @param apiPrefix - Provider's API prefix (e.g. '/api/v1/plugins/stripe')
 * @param options - Polling options
 */
export function usePaymentStatus(
  apiPrefix: string,
  options: { intervalMs?: number; maxAttempts?: number } = {}
) {
  const { intervalMs = 2000, maxAttempts = 15 } = options;
  const route = useRoute();

  const polling = ref(false);
  const confirmed = ref(false);
  const timedOut = ref(false);
  const error = ref<string | null>(null);
  const statusData = ref<Record<string, any> | null>(null);
  const sessionId = ref<string | null>(null);

  let timer: ReturnType<typeof setInterval> | null = null;
  let attempts = 0;

  function readSessionFromQuery(): string | null {
    const id = route.query.session_id as string | undefined;
    sessionId.value = id || null;
    return sessionId.value;
  }

  function stopPolling() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    polling.value = false;
  }

  async function pollOnce(): Promise<boolean> {
    const id = sessionId.value;
    if (!id) return false;

    try {
      const response = await api.get(`${apiPrefix}/session-status/${id}`);
      statusData.value = response.data;
      const status = response.data?.status;
      if (status === 'complete' || status === 'paid') {
        confirmed.value = true;
        stopPolling();
        return true;
      }
    } catch (e: any) {
      error.value = e?.response?.data?.error || e?.message || 'Status check failed';
      stopPolling();
      return true; // stop on error
    }
    return false;
  }

  async function startPolling(): Promise<void> {
    const id = sessionId.value || readSessionFromQuery();
    if (!id) {
      error.value = 'No session ID';
      return;
    }

    polling.value = true;
    attempts = 0;

    // Check once immediately
    if (await pollOnce()) return;

    timer = setInterval(async () => {
      attempts++;
      if (attempts >= maxAttempts) {
        timedOut.value = true;
        stopPolling();
        return;
      }
      await pollOnce();
    }, intervalMs);
  }

  onUnmounted(stopPolling);

  return {
    polling,           // Ref<boolean>
    confirmed,         // Ref<boolean> — true when payment complete
    timedOut,          // Ref<boolean> — true when max attempts reached
    error,             // Ref<string | null>
    statusData,        // Ref<Record | null> — raw response
    sessionId,         // Ref<string | null>
    readSessionFromQuery,
    startPolling,
    stopPolling,
  };
}
```

### `composables/index.ts` — Update Exports

```typescript
export { useFeatureAccess } from './useFeatureAccess';
export { usePaymentRedirect } from './usePaymentRedirect';  // NEW
export { usePaymentStatus } from './usePaymentStatus';      // NEW
```

---

## Task 3: Backend — Stripe SDK Adapter

### Files
| File | Action |
|------|--------|
| `vbwd-backend/requirements.txt` | Add `stripe>=18.0.0` |
| `vbwd-backend/plugins/stripe/sdk_adapter.py` | **NEW** |

### `requirements.txt` Change
```
# Payment Providers
stripe>=18.0.0
```

### `sdk_adapter.py` — Class Design

**Inheritance chain:** `StripeSDKAdapter` → `BaseSDKAdapter` → `ISDKAdapter`

```python
class StripeSDKAdapter(BaseSDKAdapter):
    """Stripe SDK adapter implementing ISDKAdapter.

    Liskov Substitution: interchangeable with any ISDKAdapter.
    Uses Stripe Checkout Sessions (redirect-based, PCI-compliant).
    """
```

**Constructor:**
```python
def __init__(self, config: SDKConfig, idempotency_service=None):
    super().__init__(config, idempotency_service)
    import stripe
    stripe.api_key = config.api_key
    self._stripe = stripe
```

**Property:**
```python
@property
def provider_name(self) -> str:
    return "stripe"
```

**Method: `create_payment_intent()`** — one-time payments
```python
def create_payment_intent(self, amount, currency, metadata, idempotency_key=None) -> SDKResponse:
```
- Converts `amount` to cents: `int(amount * 100)`
- Calls `stripe.checkout.Session.create(mode="payment", line_items=[...], metadata=metadata, ...)`
- Uses `_with_idempotency()` and `_with_retry()` from BaseSDKAdapter
- Returns `SDKResponse(success=True, data={"session_id": session.id, "session_url": session.url})`
- On `stripe.error.StripeError`: `SDKResponse(success=False, error=str(e), error_code=e.code)`

**Method: `create_subscription_session()`** — recurring billing (**NEW**)
```python
def create_subscription_session(
    self, customer_id: str, line_items: list, metadata: dict, success_url: str, cancel_url: str
) -> SDKResponse:
```
- Calls `stripe.checkout.Session.create(mode="subscription", customer=customer_id, line_items=line_items, metadata=metadata, ...)`
- Each line_item has `price_data` with `recurring: {"interval": "month"|"quarter"|"year"}`
- Returns `SDKResponse(success=True, data={"session_id": session.id, "session_url": session.url})`

**Method: `create_or_get_customer()`** — Stripe Customer management (**NEW**)
```python
def create_or_get_customer(self, email: str, name: str = None, metadata: dict = None) -> SDKResponse:
```
- Calls `stripe.Customer.create(email=email, name=name, metadata=metadata)`
- Returns `SDKResponse(success=True, data={"customer_id": customer.id})`

**Method: `cancel_subscription()`** — cancel Stripe subscription (**NEW**)
```python
def cancel_subscription(self, stripe_subscription_id: str) -> SDKResponse:
```
- Calls `stripe.Subscription.cancel(stripe_subscription_id)`
- Returns `SDKResponse(success=True, data={"status": "canceled"})`

**Method: `capture_payment()`** — implicit with Checkout Sessions, retrieves session status

**Method: `refund_payment()`** — retrieves session → gets `payment_intent` → calls `stripe.Refund.create()`

**Method: `get_payment_status()`** — retrieves session, returns `payment_status`, `amount_total`, `currency`

**Method: `verify_webhook_signature()`** — calls `stripe.Webhook.construct_event(payload, signature, webhook_secret)`, returns parsed event dict or raises `SignatureVerificationError`

---

## Task 4: Backend — Stripe Plugin Class + Config

### Files
| File | Action |
|------|--------|
| `vbwd-backend/plugins/stripe/__init__.py` | **NEW** |
| `vbwd-backend/plugins/stripe/config.json` | **NEW** |
| `vbwd-backend/plugins/stripe/admin-config.json` | **NEW** |

### `__init__.py` — Class Design

**Critical**: Class MUST be defined in `__init__.py` (not re-exported) — discovery check `obj.__module__ != full_module` in `manager.py`.

**Inheritance chain:** `StripePlugin` → `PaymentProviderPlugin` → `BasePlugin`

```python
class StripePlugin(PaymentProviderPlugin):
    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="stripe",
            version="1.0.0",
            author="VBWD Team",
            description="Stripe payment provider — Checkout Sessions with webhooks",
            dependencies=[],
        )

    def get_blueprint(self) -> Optional["Blueprint"]:
        from plugins.stripe.routes import stripe_plugin_bp
        return stripe_plugin_bp

    def get_url_prefix(self) -> Optional[str]:
        return "/api/v1/plugins/stripe"

    def on_enable(self) -> None:
        pass  # Stateless — config read per-request from config_store

    def on_disable(self) -> None:
        pass
```

**Abstract method implementations** delegate to `StripeSDKAdapter`:

| Method | Delegation |
|--------|-----------|
| `create_payment_intent(amount, currency, subscription_id, user_id, metadata)` | Instantiates adapter from config, calls `adapter.create_payment_intent()`, wraps `SDKResponse` → `PaymentResult` |
| `process_payment(payment_intent_id, payment_method)` | `adapter.capture_payment()` → `PaymentResult` |
| `refund_payment(transaction_id, amount)` | `adapter.refund_payment()` → `PaymentResult` |
| `verify_webhook(payload, signature)` | `adapter.verify_webhook_signature(payload, signature, config["webhook_secret"])` → `bool` |
| `handle_webhook(payload)` | Parse event, call `emit_payment_captured()` from shared helpers |

### `config.json`
```json
{
  "publishable_key": { "type": "string", "default": "", "description": "Stripe publishable key (pk_test_... or pk_live_...)" },
  "secret_key": { "type": "string", "default": "", "description": "Stripe secret key (sk_test_... or sk_live_...)" },
  "webhook_secret": { "type": "string", "default": "", "description": "Stripe webhook signing secret (whsec_...)" },
  "sandbox": { "type": "boolean", "default": true, "description": "Use Stripe test mode" }
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
        { "key": "publishable_key", "label": "Publishable Key", "component": "input", "inputType": "text" },
        { "key": "secret_key", "label": "Secret Key", "component": "input", "inputType": "password" },
        { "key": "webhook_secret", "label": "Webhook Secret", "component": "input", "inputType": "password" },
        { "key": "sandbox", "label": "Test Mode", "component": "checkbox" }
      ]
    }
  ]
}
```

---

## Task 5: Backend — Stripe Routes + Webhook

### Files
| File | Action |
|------|--------|
| `vbwd-backend/plugins/stripe/routes.py` | **NEW** |

### Blueprint

```python
stripe_plugin_bp = Blueprint("stripe_plugin", __name__)
```

### Route: `POST /create-session`

**Auth:** `@require_auth`

**Logic (uses shared helpers, determines mode from invoice line items):**
```python
@stripe_plugin_bp.route("/create-session", methods=["POST"])
@require_auth
def create_session():
    # 1. Shared helper: check plugin enabled
    config, err = check_plugin_enabled("stripe")
    if err: return err

    # 2. Shared helper: validate invoice
    data = request.get_json() or {}
    invoice, err = validate_invoice_for_payment(data.get("invoice_id", ""), g.user_id)
    if err: return err

    adapter = StripeSDKAdapter(SDKConfig(api_key=config["secret_key"]))
    mode = determine_session_mode(invoice)  # "payment" or "subscription"
    base_meta = {"invoice_id": str(invoice.id), "user_id": str(g.user_id)}
    success_url = f"{request.host_url}pay/stripe/success?session_id={{CHECKOUT_SESSION_ID}}"
    cancel_url = f"{request.host_url}pay/stripe/cancel"

    if mode == "subscription":
        # 3a. Recurring: get/create Stripe Customer, create subscription session
        user = container.user_repository().find_by_id(g.user_id)
        customer_id = user.stripe_customer_id
        if not customer_id:
            cust_resp = adapter.create_or_get_customer(email=user.email)
            if not cust_resp.success:
                return jsonify({"error": cust_resp.error}), 500
            customer_id = cust_resp.data["customer_id"]
            user.stripe_customer_id = customer_id
            container.user_repository().save(user)

        # Build recurring line items from invoice
        line_items = build_stripe_subscription_items(invoice)
        response = adapter.create_subscription_session(
            customer_id=customer_id, line_items=line_items,
            metadata=base_meta, success_url=success_url, cancel_url=cancel_url
        )
    else:
        # 3b. One-time: standard payment session
        response = adapter.create_payment_intent(
            amount=Decimal(str(invoice.total)),
            currency=invoice.currency or "USD",
            metadata={**base_meta, "success_url": success_url, "cancel_url": cancel_url}
        )

    if not response.success:
        return jsonify({"error": response.error}), 500
    return jsonify(response.data), 200
```

**Helper: `build_stripe_subscription_items(invoice)`**
```python
BILLING_PERIOD_TO_STRIPE = {
    "monthly": {"interval": "month"},
    "quarterly": {"interval": "month", "interval_count": 3},
    "yearly": {"interval": "year"},
    "weekly": {"interval": "week"},
}

def build_stripe_subscription_items(invoice):
    """Convert invoice line items to Stripe subscription line_items."""
    items = []
    for li in invoice.line_items:
        if li.item_type == LineItemType.SUBSCRIPTION:
            plan = resolve_plan(li)
            if plan and plan.is_recurring:
                items.append({
                    "price_data": {
                        "currency": invoice.currency or "USD",
                        "unit_amount": int(li.unit_price * 100),
                        "recurring": BILLING_PERIOD_TO_STRIPE[plan.billing_period.value],
                        "product_data": {"name": plan.name},
                    },
                    "quantity": 1,
                })
        elif li.item_type == LineItemType.ADD_ON:
            addon = resolve_addon(li)
            if addon and addon.is_recurring:
                items.append({
                    "price_data": {
                        "currency": invoice.currency or "USD",
                        "unit_amount": int(li.unit_price * 100),
                        "recurring": BILLING_PERIOD_TO_STRIPE[addon.billing_period],
                        "product_data": {"name": addon.name},
                    },
                    "quantity": li.quantity,
                })
    return items
```

### Route: `POST /webhook`

**Auth:** None (Stripe calls directly)

**Handles 4 event types:**

| Stripe Event | Our Action | Mode |
|-------------|-----------|------|
| `checkout.session.completed` | Initial payment — emit `PaymentCapturedEvent`, store `stripe_subscription_id` | Both |
| `invoice.paid` | Renewal payment — create renewal invoice, emit `PaymentCapturedEvent` | Subscription only |
| `customer.subscription.deleted` | Cancellation — emit `SubscriptionCancelledEvent` | Subscription only |
| `invoice.payment_failed` | Failed renewal — emit `PaymentFailedEvent` | Subscription only |

**Logic:**
```python
@stripe_plugin_bp.route("/webhook", methods=["POST"])
def stripe_webhook():
    config, err = check_plugin_enabled("stripe")
    if err: return err

    payload = request.get_data()
    signature = request.headers.get("Stripe-Signature")
    try:
        event = stripe.Webhook.construct_event(payload, signature, config["webhook_secret"])
    except stripe.error.SignatureVerificationError:
        return jsonify({"error": "Invalid signature"}), 400

    event_type = event["type"]
    obj = event["data"]["object"]

    if event_type == "checkout.session.completed":
        _handle_checkout_completed(obj)
    elif event_type == "invoice.paid":
        _handle_invoice_paid(obj)
    elif event_type == "customer.subscription.deleted":
        _handle_subscription_deleted(obj)
    elif event_type == "invoice.payment_failed":
        _handle_payment_failed(obj)

    return jsonify({"received": true}), 200
```

**`_handle_checkout_completed(session)`** — initial payment (same as before + store subscription ID)
```python
def _handle_checkout_completed(session):
    metadata = session.get("metadata", {})
    invoice_id = metadata.get("invoice_id")
    if not invoice_id:
        return

    # If subscription mode, store stripe_subscription_id on our Subscription
    stripe_sub_id = session.get("subscription")
    if stripe_sub_id:
        _link_stripe_subscription(UUID(invoice_id), stripe_sub_id)

    # Event-driven: emit, don't act
    emit_payment_captured(
        invoice_id=UUID(invoice_id),
        payment_reference=session["id"],
        amount=str(session["amount_total"] / 100),
        currency=session["currency"],
        provider="stripe",
        transaction_id=session.get("payment_intent", ""),
    )
```

**`_handle_invoice_paid(stripe_invoice)`** — recurring renewal
```python
def _handle_invoice_paid(stripe_invoice):
    """Handle Stripe auto-generated invoice for subscription renewal.

    This is the RENEWAL path — Stripe charged the customer automatically.
    We create a renewal invoice in our system and emit PaymentCapturedEvent.
    """
    # Skip the first invoice (already handled by checkout.session.completed)
    if stripe_invoice.get("billing_reason") == "subscription_create":
        return

    stripe_sub_id = stripe_invoice.get("subscription")
    if not stripe_sub_id:
        return

    # Find our subscription by stripe_subscription_id
    container = current_app.container
    sub_repo = container.subscription_repository()
    subscription = sub_repo.find_by_stripe_subscription_id(stripe_sub_id)
    if not subscription:
        return

    # Create renewal invoice in our system
    renewal_invoice = _create_renewal_invoice(subscription, stripe_invoice)

    # Event-driven: emit to activate/extend subscription
    emit_payment_captured(
        invoice_id=renewal_invoice.id,
        payment_reference=stripe_invoice["id"],
        amount=str(stripe_invoice["amount_paid"] / 100),
        currency=stripe_invoice["currency"],
        provider="stripe",
        transaction_id=stripe_invoice.get("payment_intent", ""),
    )
```

**`_handle_subscription_deleted(stripe_sub)`** — cancellation
```python
def _handle_subscription_deleted(stripe_sub):
    """Stripe subscription cancelled (by user, admin, or payment failure)."""
    sub_repo = current_app.container.subscription_repository()
    subscription = sub_repo.find_by_stripe_subscription_id(stripe_sub["id"])
    if not subscription:
        return

    # Emit cancellation event — handler marks subscription CANCELLED
    event = SubscriptionCancelledEvent(
        subscription_id=subscription.id,
        user_id=subscription.user_id,
        reason="stripe_subscription_deleted",
        provider="stripe",
    )
    current_app.container.event_dispatcher().emit(event)
```

**`_handle_payment_failed(stripe_invoice)`** — failed renewal
```python
def _handle_payment_failed(stripe_invoice):
    """Stripe failed to charge for renewal."""
    stripe_sub_id = stripe_invoice.get("subscription")
    if not stripe_sub_id:
        return

    sub_repo = current_app.container.subscription_repository()
    subscription = sub_repo.find_by_stripe_subscription_id(stripe_sub_id)
    if not subscription:
        return

    # Emit failure event — handler can notify user
    event = PaymentFailedEvent(
        subscription_id=subscription.id,
        user_id=subscription.user_id,
        error_code="payment_failed",
        error_message=stripe_invoice.get("last_payment_error", {}).get("message", "Payment failed"),
        provider="stripe",
    )
    current_app.container.event_dispatcher().emit(event)
```

### Route: `GET /session-status/<session_id>`

**Auth:** `@require_auth`

Uses `check_plugin_enabled()`, instantiates adapter, calls `get_payment_status()`.

---

## Task 6: Backend — Tests

### Files
| File | Action |
|------|--------|
| `vbwd-backend/plugins/stripe/tests/__init__.py` | **NEW** (empty) |
| `vbwd-backend/plugins/stripe/tests/conftest.py` | **NEW** |
| `vbwd-backend/plugins/stripe/tests/test_plugin.py` | **NEW** |
| `vbwd-backend/plugins/stripe/tests/test_sdk_adapter.py` | **NEW** |
| `vbwd-backend/plugins/stripe/tests/test_routes.py` | **NEW** |
| `vbwd-backend/plugins/stripe/tests/test_webhook_event.py` | **NEW** |
| `vbwd-backend/tests/unit/plugins/test_payment_route_helpers.py` | **NEW** |

### `conftest.py` — Shared Fixtures
```python
@pytest.fixture
def stripe_config():
    return {"publishable_key": "pk_test_123", "secret_key": "sk_test_456",
            "webhook_secret": "whsec_789", "sandbox": True}

@pytest.fixture
def sdk_config():
    return SDKConfig(api_key="sk_test_456", sandbox=True)

@pytest.fixture
def mock_stripe(mocker):
    mock = mocker.MagicMock()
    mocker.patch.dict("sys.modules", {"stripe": mock})
    return mock

@pytest.fixture
def mock_config_store(mocker):
    store = mocker.MagicMock()
    store.get_by_name.return_value = PluginConfigEntry(plugin_name="stripe", status="enabled")
    store.get_config.return_value = stripe_config()
    return store
```

### `test_payment_route_helpers.py` — Shared Helper Tests (~8 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_check_enabled_returns_config` | Returns `(config, None)` when plugin enabled |
| 2 | `test_check_enabled_returns_404_disabled` | Returns `(None, 404)` when plugin disabled |
| 3 | `test_check_enabled_returns_503_no_store` | Returns `(None, 503)` when config_store missing |
| 4 | `test_validate_invoice_valid` | Returns `(invoice, None)` for valid PENDING invoice |
| 5 | `test_validate_invoice_bad_uuid` | Returns `(None, 400)` for invalid UUID |
| 6 | `test_validate_invoice_not_found` | Returns `(None, 404)` for missing invoice |
| 7 | `test_validate_invoice_not_pending` | Returns `(None, 400)` for PAID invoice |
| 8 | `test_validate_invoice_wrong_user` | Returns `(None, 403)` for another user's invoice |
| 9 | `test_emit_payment_captured_calls_emit` | `dispatcher.emit()` called with PaymentCapturedEvent |
| 10 | `test_emit_payment_captured_event_fields` | Event has correct invoice_id, amount, provider fields |

### `test_plugin.py` — Plugin Metadata & Lifecycle (~10 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_metadata_name` | `plugin.metadata.name == "stripe"` |
| 2 | `test_metadata_version` | `plugin.metadata.version == "1.0.0"` |
| 3 | `test_metadata_author` | `plugin.metadata.author == "VBWD Team"` |
| 4 | `test_inherits_payment_provider` | `isinstance(plugin, PaymentProviderPlugin)` |
| 5 | `test_inherits_base_plugin` | `isinstance(plugin, BasePlugin)` |
| 6 | `test_initial_status_discovered` | `plugin.status == PluginStatus.DISCOVERED` |
| 7 | `test_lifecycle` | DISCOVERED→INITIALIZED→ENABLED→DISABLED |
| 8 | `test_get_blueprint_returns_blueprint` | `isinstance(plugin.get_blueprint(), Blueprint)` |
| 9 | `test_get_url_prefix` | `plugin.get_url_prefix() == "/api/v1/plugins/stripe"` |
| 10 | `test_no_dependencies` | `plugin.metadata.dependencies == []` |

### `test_sdk_adapter.py` — SDK Adapter (~13 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_provider_name` | `adapter.provider_name == "stripe"` |
| 2 | `test_inherits_base_sdk_adapter` | `isinstance(adapter, BaseSDKAdapter)` |
| 3 | `test_implements_isdk_adapter` | `isinstance(adapter, ISDKAdapter)` |
| 4 | `test_create_payment_intent_success` | Calls `Session.create()`, returns SDKResponse with session_id/url |
| 5 | `test_create_payment_intent_stripe_error` | Returns SDKResponse(success=False) |
| 6 | `test_create_payment_intent_amount_cents` | `Decimal("29.99")` → `unit_amount=2999` |
| 7 | `test_create_payment_intent_metadata` | Metadata dict forwarded to Session.create() |
| 8 | `test_capture_payment` | Calls `Session.retrieve()`, returns status |
| 9 | `test_refund_full` | Calls `Refund.create()` with no amount |
| 10 | `test_refund_partial` | `Refund.create(amount=1500)` for `Decimal("15.00")` |
| 11 | `test_get_payment_status` | Returns payment_status, amount_total, currency |
| 12 | `test_webhook_signature_valid` | `construct_event()` returns parsed event |
| 13 | `test_webhook_signature_invalid` | Raises `SignatureVerificationError` |

### `test_routes.py` — Route Handlers (~13 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_create_session_requires_auth` | 401 without auth |
| 2 | `test_create_session_plugin_disabled` | 404 |
| 3 | `test_create_session_missing_invoice` | 400 |
| 4 | `test_create_session_invoice_not_found` | 404 |
| 5 | `test_create_session_invoice_not_pending` | 400 |
| 6 | `test_create_session_wrong_user` | 403 |
| 7 | `test_create_session_success` | 200 with session_id + session_url |
| 8 | `test_webhook_invalid_signature` | 400 |
| 9 | `test_webhook_plugin_disabled` | 404 |
| 10 | `test_webhook_success` | 200, event emitted |
| 11 | `test_webhook_ignores_other_events` | 200, no event emitted |
| 12 | `test_session_status_requires_auth` | 401 |
| 13 | `test_session_status_success` | 200 with status data |

### `test_webhook_event.py` — Event-Driven Verification (~6 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_emits_payment_captured_event` | `dispatcher.emit()` called with PaymentCapturedEvent |
| 2 | `test_event_correct_invoice_id` | `event.invoice_id == UUID(invoice_id)` |
| 3 | `test_event_correct_amount` | `event.amount == str(amount_total / 100)` |
| 4 | `test_event_correct_provider` | `event.provider == "stripe"` |
| 5 | `test_event_correct_transaction_id` | `event.transaction_id == session["payment_intent"]` |
| 6 | `test_webhook_no_direct_domain_mutations` | NO calls to invoice_repository, subscription_repository |

**Backend total: +52 tests (632 → ~684)** — includes 10 shared helper tests + 42 Stripe tests

---

## Task 7: Frontend — Stripe Payment Plugin Views

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/package.json` | Add `@stripe/stripe-js` |
| `vbwd-frontend/user/plugins/stripe-payment/index.ts` | **NEW** |
| `vbwd-frontend/user/plugins/stripe-payment/StripePaymentView.vue` | **NEW** |
| `vbwd-frontend/user/plugins/stripe-payment/StripeSuccessView.vue` | **NEW** |
| `vbwd-frontend/user/plugins/stripe-payment/StripeCancelView.vue` | **NEW** |
| `vbwd-frontend/user/plugins/stripe-payment/config.json` | **NEW** |
| `vbwd-frontend/user/plugins/stripe-payment/admin-config.json` | **NEW** |

### `index.ts` — Plugin Registration

```typescript
import type { IPlugin, IPlatformSDK } from '@vbwd/view-component';

export const stripePaymentPlugin: IPlugin = {
  name: 'stripe-payment',
  version: '1.0.0',
  description: 'Stripe payment processing — redirects to Stripe Checkout',
  _active: false,

  install(sdk: IPlatformSDK) {
    sdk.addRoute({
      path: '/pay/stripe',
      name: 'stripe-payment',
      component: () => import('./StripePaymentView.vue'),
      meta: { requiresAuth: true }
    });
    sdk.addRoute({
      path: '/pay/stripe/success',
      name: 'stripe-success',
      component: () => import('./StripeSuccessView.vue'),
      meta: { requiresAuth: true }
    });
    sdk.addRoute({
      path: '/pay/stripe/cancel',
      name: 'stripe-cancel',
      component: () => import('./StripeCancelView.vue'),
      meta: { requiresAuth: true }
    });
  },

  activate() { this._active = true; },
  deactivate() { this._active = false; }
};
```

### `StripePaymentView.vue` — Uses Shared Composable

```html
<template>
  <div class="stripe-payment">
    <div v-if="loading">{{ $t('stripe.payment.redirecting') }}</div>
    <div v-else-if="error">
      <p>{{ error }}</p>
      <button @click="createAndRedirect">{{ $t('stripe.payment.retry') }}</button>
    </div>
    <div v-else-if="!invoiceId">
      <p>{{ $t('stripe.payment.noInvoice') }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { usePaymentRedirect } from '@vbwd/view-component'; // SHARED composable

const { loading, error, invoiceId, readInvoiceFromQuery, createAndRedirect } =
  usePaymentRedirect('/api/v1/plugins/stripe');

onMounted(() => {
  readInvoiceFromQuery();
  if (invoiceId.value) {
    createAndRedirect();
  }
});
</script>
```

**Stripe-specific code: zero.** All logic lives in the shared composable.

### `StripeSuccessView.vue` — Uses Shared Composable

```html
<template>
  <div class="stripe-success">
    <div v-if="polling">{{ $t('stripe.success.verifying') }}</div>
    <div v-else-if="confirmed">
      <h2>{{ $t('stripe.success.title') }}</h2>
      <p>{{ $t('stripe.success.message') }}</p>
      <router-link to="/dashboard/invoices">{{ $t('stripe.success.viewInvoices') }}</router-link>
    </div>
    <div v-else-if="timedOut">
      <p>{{ $t('stripe.success.processing') }}</p>
    </div>
    <div v-else-if="error">
      <p>{{ error }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { usePaymentStatus } from '@vbwd/view-component'; // SHARED composable

const { polling, confirmed, timedOut, error, readSessionFromQuery, startPolling } =
  usePaymentStatus('/api/v1/plugins/stripe');

onMounted(() => {
  readSessionFromQuery();
  startPolling();
});
</script>
```

### `StripeCancelView.vue` — Simple Static

```html
<template>
  <div class="stripe-cancel">
    <h2>{{ $t('stripe.cancel.title') }}</h2>
    <p>{{ $t('stripe.cancel.message') }}</p>
    <router-link to="/checkout">{{ $t('stripe.cancel.tryAgain') }}</router-link>
  </div>
</template>
```

### Config Files

**`config.json`:**
```json
{ "publishableKey": { "type": "string", "default": "", "description": "Stripe publishable key" } }
```

**`admin-config.json`:**
```json
{ "tabs": [{ "id": "credentials", "label": "Credentials", "fields": [
  { "key": "publishableKey", "label": "Publishable Key", "component": "input", "inputType": "text" }
] }] }
```

---

## Task 8: Frontend — Checkout Integration + i18n

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/user/vue/src/main.ts` | Add stripePaymentPlugin |
| `vbwd-frontend/user/plugins/plugins.json` | Add stripe-payment entry |
| `vbwd-frontend/user/plugins/checkout/PublicCheckoutView.vue` | Redirect when stripe |
| `vbwd-frontend/user/vue/src/views/Checkout.vue` | Redirect when stripe |
| `vbwd-frontend/user/vue/src/i18n/locales/en.json` | Add stripe.* keys |
| `vbwd-frontend/user/vue/src/i18n/locales/de.json` | Add stripe.* keys |

### `main.ts` — Add Plugin
```typescript
import { stripePaymentPlugin } from '../../plugins/stripe-payment';

const availablePlugins: Record<string, IPlugin> = {
  landing1: landing1Plugin,
  checkout: checkoutPlugin,
  'stripe-payment': stripePaymentPlugin,
};
```

### Checkout Redirect Logic

In both `PublicCheckoutView.vue` and `Checkout.vue`, after successful checkout:
```typescript
if (checkoutStore.checkoutResult && checkoutStore.paymentMethodCode === 'stripe') {
  const invoiceId = checkoutStore.checkoutResult.invoice?.id;
  if (invoiceId) {
    router.push({ path: '/pay/stripe', query: { invoice: invoiceId } });
    return;
  }
}
```

### i18n — English
```json
{
  "stripe": {
    "payment": {
      "redirecting": "Redirecting to Stripe...",
      "retry": "Try Again",
      "error": "Failed to create payment session",
      "noInvoice": "No invoice specified. Please complete checkout first."
    },
    "success": {
      "title": "Payment Successful",
      "message": "Your payment has been processed. Your subscription is now active.",
      "verifying": "Verifying payment...",
      "processing": "Your payment is being processed. This may take a moment.",
      "viewInvoices": "View Invoices"
    },
    "cancel": {
      "title": "Payment Cancelled",
      "message": "Your payment was cancelled. Your invoice is still pending.",
      "tryAgain": "Try Again"
    }
  }
}
```

### i18n — German
```json
{
  "stripe": {
    "payment": {
      "redirecting": "Weiterleitung zu Stripe...",
      "retry": "Erneut versuchen",
      "error": "Zahlungssitzung konnte nicht erstellt werden",
      "noInvoice": "Keine Rechnung angegeben. Bitte schließen Sie zuerst den Checkout ab."
    },
    "success": {
      "title": "Zahlung erfolgreich",
      "message": "Ihre Zahlung wurde verarbeitet. Ihr Abonnement ist jetzt aktiv.",
      "verifying": "Zahlung wird überprüft...",
      "processing": "Ihre Zahlung wird verarbeitet. Dies kann einen Moment dauern.",
      "viewInvoices": "Rechnungen anzeigen"
    },
    "cancel": {
      "title": "Zahlung abgebrochen",
      "message": "Ihre Zahlung wurde abgebrochen. Ihre Rechnung ist noch ausstehend.",
      "tryAgain": "Erneut versuchen"
    }
  }
}
```

---

## Task 9: Frontend — Tests + Build Verification

### Files
| File | Action |
|------|--------|
| `vbwd-frontend/core/tests/composables/usePaymentRedirect.spec.ts` | **NEW** |
| `vbwd-frontend/core/tests/composables/usePaymentStatus.spec.ts` | **NEW** |
| `vbwd-frontend/user/vue/tests/unit/plugins/stripe-payment.spec.ts` | **NEW** |
| `vbwd-frontend/user/vue/tests/unit/plugins/stripe-views.spec.ts` | **NEW** |

### Core Composable Tests (~8 tests)

**`usePaymentRedirect.spec.ts`:**

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_reads_invoice_from_query` | `invoiceId.value === route.query.invoice` |
| 2 | `test_sets_error_when_no_invoice` | `error.value` set when no query param |
| 3 | `test_calls_api_post` | POSTs to `${apiPrefix}/create-session` |
| 4 | `test_sets_loading_true` | `loading.value === true` during request |

**`usePaymentStatus.spec.ts`:**

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_reads_session_from_query` | `sessionId.value === route.query.session_id` |
| 2 | `test_polls_status_endpoint` | GETs `${apiPrefix}/session-status/<id>` |
| 3 | `test_confirmed_on_complete` | `confirmed.value === true` when status "complete" |
| 4 | `test_timeout_after_max_attempts` | `timedOut.value === true` after maxAttempts |

### Stripe Plugin Tests (~6 tests)

**`stripe-payment.spec.ts`:**

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_plugin_name` | `'stripe-payment'` |
| 2 | `test_plugin_version` | `'1.0.0'` |
| 3 | `test_install_adds_three_routes` | `sdk.getRoutes().length === 3` |
| 4 | `test_routes_paths` | `/pay/stripe`, `/pay/stripe/success`, `/pay/stripe/cancel` |
| 5 | `test_routes_require_auth` | All `meta.requiresAuth === true` |
| 6 | `test_activate_deactivate` | `_active` toggles |

### Stripe View Tests (~8 tests)

**`stripe-views.spec.ts`:**

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_payment_view_shows_loading` | Loading text on mount |
| 2 | `test_payment_view_error_no_invoice` | Error when no query param |
| 3 | `test_payment_view_calls_api` | POSTs create-session |
| 4 | `test_payment_view_error_on_fail` | Shows error + retry on API fail |
| 5 | `test_success_view_shows_verifying` | Verifying text on mount |
| 6 | `test_success_view_polls_status` | GETs session-status |
| 7 | `test_success_view_shows_confirmation` | Shows success on "complete" |
| 8 | `test_cancel_view_renders` | Cancel message + retry link |

### Build Verification
```bash
# Backend (Docker)
cd vbwd-backend && make test-unit           # Target: ~684

# Core composable tests
cd vbwd-frontend/core && npx vitest run     # Target: 289 + 8 = ~297

# User frontend tests
cd vbwd-frontend/user && npx vitest run     # Target: 154 + 14 = ~168

# Admin (unaffected)
cd vbwd-frontend/admin/vue && npx vitest run  # Target: 331

# Rebuild containers
cd vbwd-frontend && docker compose up -d --build user-app admin-app
```

---

## Task 10: Backend — DB Migration for Recurring Billing

### Files
| File | Action |
|------|--------|
| `vbwd-backend/src/models/user.py` | **MODIFY** — add `stripe_customer_id` |
| `vbwd-backend/src/models/subscription.py` | **MODIFY** — add `stripe_subscription_id` |
| `vbwd-backend/src/models/addon_subscription.py` | **MODIFY** — add `stripe_subscription_id` |
| `vbwd-backend/src/models/invoice.py` | **MODIFY** — add `stripe_invoice_id` |
| `vbwd-backend/alembic/versions/xxxx_add_stripe_fields.py` | **NEW** — Alembic migration |

### Model Changes

**User** — add Stripe customer linking:
```python
stripe_customer_id = db.Column(db.String(255), unique=True, nullable=True, index=True)
```

**Subscription** — add Stripe subscription linking:
```python
stripe_subscription_id = db.Column(db.String(255), unique=True, nullable=True, index=True)
```

**AddOnSubscription** — add Stripe subscription linking:
```python
stripe_subscription_id = db.Column(db.String(255), nullable=True, index=True)
```

**UserInvoice** — add Stripe invoice tracking (for deduplication):
```python
stripe_invoice_id = db.Column(db.String(255), unique=True, nullable=True, index=True)
```

### Repository Changes

**SubscriptionRepository** — add lookup method:
```python
def find_by_stripe_subscription_id(self, stripe_sub_id: str) -> Optional[Subscription]:
    return self.session.query(Subscription).filter_by(
        stripe_subscription_id=stripe_sub_id
    ).first()
```

**AddOnSubscriptionRepository** — add lookup method:
```python
def find_by_stripe_subscription_id(self, stripe_sub_id: str) -> List[AddOnSubscription]:
    return self.session.query(AddOnSubscription).filter_by(
        stripe_subscription_id=stripe_sub_id
    ).all()
```

### Alembic Migration
```python
def upgrade():
    op.add_column('users', sa.Column('stripe_customer_id', sa.String(255), unique=True, nullable=True))
    op.add_column('subscriptions', sa.Column('stripe_subscription_id', sa.String(255), unique=True, nullable=True))
    op.add_column('addon_subscriptions', sa.Column('stripe_subscription_id', sa.String(255), nullable=True))
    op.add_column('invoices', sa.Column('stripe_invoice_id', sa.String(255), unique=True, nullable=True))
    op.create_index('ix_users_stripe_customer_id', 'users', ['stripe_customer_id'])
    op.create_index('ix_subscriptions_stripe_subscription_id', 'subscriptions', ['stripe_subscription_id'])
    op.create_index('ix_invoices_stripe_invoice_id', 'invoices', ['stripe_invoice_id'])

def downgrade():
    op.drop_column('invoices', 'stripe_invoice_id')
    op.drop_column('addon_subscriptions', 'stripe_subscription_id')
    op.drop_column('subscriptions', 'stripe_subscription_id')
    op.drop_column('users', 'stripe_customer_id')
```

---

## Task 11: Backend — Recurring Events + Handlers

### Files
| File | Action |
|------|--------|
| `vbwd-backend/src/events/payment_events.py` | **MODIFY** — add `SubscriptionCancelledEvent` |
| `vbwd-backend/src/handlers/subscription_cancel_handler.py` | **NEW** |
| `vbwd-backend/src/app.py` | **MODIFY** — register new handler |
| `vbwd-backend/plugins/stripe/routes.py` | **MODIFY** — add renewal helper functions |

### New Event: `SubscriptionCancelledEvent`

Add to `src/events/payment_events.py`:
```python
@dataclass
class SubscriptionCancelledEvent(DomainEvent):
    """Subscription cancelled by provider (webhook) or admin action.

    Handler marks subscription as CANCELLED.
    """
    subscription_id: UUID = None
    user_id: UUID = None
    reason: str = ""
    provider: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self):
        self.name = "subscription.cancelled"
        super().__post_init__()
```

### New Handler: `SubscriptionCancelledHandler`

```python
class SubscriptionCancelledHandler(IEventHandler):
    """Handles subscription.cancelled events.

    Marks subscription as CANCELLED. Does NOT refund — that's a separate flow.
    Also cancels linked add-on subscriptions.
    """
    def __init__(self, container):
        self._container = container

    def can_handle(self, event):
        return isinstance(event, SubscriptionCancelledEvent)

    def handle(self, event):
        repos = self._get_services()
        subscription = repos["subscription"].find_by_id(event.subscription_id)
        if not subscription or subscription.status == SubscriptionStatus.CANCELLED:
            return EventResult.success_result()

        subscription.status = SubscriptionStatus.CANCELLED
        subscription.cancelled_at = datetime.utcnow()
        repos["subscription"].save(subscription)

        # Cancel linked add-on subscriptions
        addon_subs = repos["addon_subscription"].find_by_subscription_id(event.subscription_id)
        for addon_sub in addon_subs:
            if addon_sub.status == SubscriptionStatus.ACTIVE:
                addon_sub.status = SubscriptionStatus.CANCELLED
                addon_sub.cancelled_at = datetime.utcnow()
                repos["addon_subscription"].save(addon_sub)

        return EventResult.success_result({"subscription_id": str(event.subscription_id)})
```

### Register Handler in `app.py`
```python
cancel_handler = SubscriptionCancelledHandler(container)
dispatcher.register("subscription.cancelled", cancel_handler)
```

### Renewal Invoice Helper (in `plugins/stripe/routes.py`)

```python
def _create_renewal_invoice(subscription, stripe_invoice):
    """Create a renewal invoice in our system from Stripe's auto-generated invoice.

    Called when Stripe sends invoice.paid for a renewal charge.
    """
    container = current_app.container
    invoice_repo = container.invoice_repository()

    # Deduplication: check if we already processed this Stripe invoice
    existing = invoice_repo.find_by_stripe_invoice_id(stripe_invoice["id"])
    if existing:
        return existing

    plan = subscription.tarif_plan
    renewal_invoice = UserInvoice(
        user_id=subscription.user_id,
        tarif_plan_id=plan.id if plan else None,
        subscription_id=subscription.id,
        amount=Decimal(str(stripe_invoice["amount_paid"] / 100)),
        total_amount=Decimal(str(stripe_invoice["amount_paid"] / 100)),
        currency=stripe_invoice["currency"].upper(),
        status=InvoiceStatus.PENDING,  # Will be marked PAID by PaymentCapturedHandler
        payment_method="stripe",
        stripe_invoice_id=stripe_invoice["id"],
    )
    # Add subscription line item
    renewal_invoice.line_items.append(InvoiceLineItem(
        item_type=LineItemType.SUBSCRIPTION,
        item_id=subscription.id,
        description=f"Renewal: {plan.name}" if plan else "Subscription renewal",
        quantity=1,
        unit_price=renewal_invoice.amount,
        total_price=renewal_invoice.amount,
    ))
    invoice_repo.save(renewal_invoice)
    return renewal_invoice
```

### Stripe Subscription Linking Helper

```python
def _link_stripe_subscription(invoice_id, stripe_subscription_id):
    """Store stripe_subscription_id on our Subscription after initial checkout."""
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
                subscription.stripe_subscription_id = stripe_subscription_id
                sub_repo.save(subscription)
                break
```

---

## Task 12: Backend — Recurring Billing Tests

### Files
| File | Action |
|------|--------|
| `vbwd-backend/plugins/stripe/tests/test_recurring.py` | **NEW** |
| `vbwd-backend/tests/unit/handlers/test_subscription_cancel_handler.py` | **NEW** |

### `test_recurring.py` — Recurring Billing Tests (~15 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_determine_mode_recurring_plan` | `determine_session_mode(invoice)` returns `"subscription"` for monthly plan |
| 2 | `test_determine_mode_one_time_plan` | Returns `"payment"` for ONE_TIME plan |
| 3 | `test_determine_mode_recurring_addon` | Returns `"subscription"` for recurring add-on |
| 4 | `test_determine_mode_mixed_one_time` | Returns `"payment"` when only token bundles |
| 5 | `test_build_subscription_items_monthly` | Generates `{"interval": "month"}` for MONTHLY plan |
| 6 | `test_build_subscription_items_yearly` | Generates `{"interval": "year"}` for YEARLY plan |
| 7 | `test_build_subscription_items_quarterly` | Generates `{"interval": "month", "interval_count": 3}` |
| 8 | `test_create_session_subscription_mode` | `mode="subscription"` used, Stripe Customer created |
| 9 | `test_create_session_reuses_customer` | Existing `stripe_customer_id` used, no new customer created |
| 10 | `test_webhook_checkout_stores_subscription_id` | `subscription.stripe_subscription_id` set after checkout |
| 11 | `test_webhook_invoice_paid_creates_renewal` | Renewal invoice created on `invoice.paid` |
| 12 | `test_webhook_invoice_paid_skips_first` | `billing_reason=subscription_create` ignored (handled by checkout) |
| 13 | `test_webhook_invoice_paid_deduplication` | Same `stripe_invoice_id` not processed twice |
| 14 | `test_webhook_subscription_deleted_cancels` | Subscription marked CANCELLED |
| 15 | `test_webhook_payment_failed_emits_event` | `PaymentFailedEvent` emitted |

### `test_subscription_cancel_handler.py` — Cancel Handler Tests (~6 tests)

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_cancels_active_subscription` | Status → CANCELLED, cancelled_at set |
| 2 | `test_cancels_linked_addon_subscriptions` | Active add-ons also cancelled |
| 3 | `test_skips_already_cancelled` | No error on already-cancelled subscription |
| 4 | `test_skips_missing_subscription` | No error on unknown subscription_id |
| 5 | `test_event_driven_no_direct_mutations` | Handler only uses repos, never touches Stripe |
| 6 | `test_returns_success_result` | Returns EventResult.success_result with subscription_id |

**Recurring tests: +21 (total backend: 632 → ~705)**

---

## Implementation Order & Dependencies

```
Task 1: Shared backend payment_route_helpers.py (no deps)
Task 2: Shared frontend composables (no deps)
  ↓  (Tasks 1 & 2 can run in parallel)
Task 3: Stripe SDK Adapter (deps: requirements.txt)
  ↓
Task 4: Stripe Plugin Class (deps: Task 3 — imports StripeSDKAdapter)
  ↓
Task 10: DB Migration for Recurring Billing (deps: none — can run parallel with Tasks 3-4)
  ↓
Task 5: Stripe Routes (deps: Tasks 1, 4, 10 — uses helpers + imports blueprint + uses stripe_* fields)
  ↓
Task 11: Recurring Events + Handlers (deps: Task 10 — uses stripe_* fields + new event)
  ↓
Task 6: Backend Tests (deps: Tasks 1, 3, 4, 5, 11)
Task 12: Recurring Billing Tests (deps: Tasks 5, 10, 11)
  ↓  (Tasks 6 & 12 can run in parallel)
Task 7: Frontend Plugin Views (deps: Task 2 — uses composables)
  ↓
Task 8: Checkout Integration + i18n (deps: Task 7)
  ↓
Task 9: Frontend Tests + Build (deps: Tasks 6, 7, 8, 12 — all tests must pass)
```

## New Files Summary

**Shared backend (1 file):**
```
src/plugins/payment_route_helpers.py     ← check_plugin_enabled, validate_invoice, emit_payment_captured
```

**Shared frontend (2 new files):**
```
core/src/composables/usePaymentRedirect.ts   ← NEW: create-session → redirect composable
core/src/composables/usePaymentStatus.ts     ← NEW: poll status composable
```

**Stripe backend (10 files):**
```
plugins/stripe/
├── __init__.py, sdk_adapter.py, routes.py, config.json, admin-config.json
└── tests/ — __init__.py, conftest.py, test_plugin.py, test_sdk_adapter.py,
             test_routes.py, test_webhook_event.py
```

**Recurring backend (4 new files):**
```
vbwd-backend/alembic/versions/xxxx_add_stripe_fields.py   ← Alembic migration
vbwd-backend/src/handlers/subscription_cancel_handler.py   ← SubscriptionCancelledHandler
vbwd-backend/plugins/stripe/tests/test_recurring.py        ← 15 recurring tests
vbwd-backend/tests/unit/handlers/test_subscription_cancel_handler.py  ← 6 cancel handler tests
```

**Stripe frontend (8 files):**
```
user/plugins/stripe-payment/
├── index.ts, StripePaymentView.vue, StripeSuccessView.vue, StripeCancelView.vue
├── config.json, admin-config.json
user/vue/tests/unit/plugins/
├── stripe-payment.spec.ts, stripe-views.spec.ts
```

**Shared test files (3 files):**
```
vbwd-backend/tests/unit/plugins/test_payment_route_helpers.py
vbwd-frontend/core/tests/composables/usePaymentRedirect.spec.ts
vbwd-frontend/core/tests/composables/usePaymentStatus.spec.ts
```

**Modified files (12):**
- `vbwd-backend/requirements.txt` — add `stripe>=18.0.0`
- `vbwd-backend/src/models/user.py` — add `stripe_customer_id`
- `vbwd-backend/src/models/subscription.py` — add `stripe_subscription_id`
- `vbwd-backend/src/models/addon_subscription.py` — add `stripe_subscription_id`
- `vbwd-backend/src/models/invoice.py` — add `stripe_invoice_id`
- `vbwd-backend/src/events/payment_events.py` — add `SubscriptionCancelledEvent`
- `vbwd-backend/src/app.py` — register `SubscriptionCancelledHandler`
- `vbwd-frontend/core/src/composables/index.ts` — add exports
- `vbwd-frontend/user/package.json` — add `@stripe/stripe-js`
- `vbwd-frontend/user/vue/src/main.ts` — add stripePaymentPlugin
- `vbwd-frontend/user/plugins/plugins.json` — add stripe-payment
- `vbwd-frontend/user/plugins/checkout/PublicCheckoutView.vue` — redirect on stripe
- `vbwd-frontend/user/vue/src/views/Checkout.vue` — redirect on stripe

## Test Targets
- Backend: 632 → ~705 (+73: 10 shared helpers + 42 Stripe + 21 recurring)
- Core frontend: 289 → ~297 (+8 composable tests)
- User frontend: 154 → ~168 (+14: 6 plugin + 8 views)
- Admin frontend: maintain 331
- **Total: ~1501**
