# Sprint 25 Report: PayPal Payment Plugin

## Summary

Added PayPal payment processing as a plugin, mirroring the Stripe plugin architecture from Sprint 24. Reused all shared payment abstractions — PayPal is a thin wrapper using `payment_route_helpers.py`, `usePaymentRedirect`, and `usePaymentStatus` composables.

## Test Results

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| Backend unit tests | 661 passed, 4 skipped | 661 passed, 4 skipped | — |
| Stripe plugin tests | 70 passed | 76 passed | +6 (fixed regression) |
| **PayPal plugin tests** | — | **55 passed** | **+55 new** |
| Admin frontend | 331 passed | 331 passed | — |
| User frontend | 169 passed | 185 passed | +16 new |
| Core frontend | 300 passed, 1 skipped | 300 passed, 1 skipped | — |
| **Total** | **1531** | **1608** | **+77** |

## Backend Changes

### DB Migration
- **`alembic/versions/20260212_add_paypal_fields.py`** — Adds `paypal_subscription_id` (Subscription) and `paypal_order_id` (UserInvoice) with indexes
- **`src/models/subscription.py`** — Added `paypal_subscription_id` column
- **`src/models/invoice.py`** — Added `paypal_order_id` column
- **`src/repositories/subscription_repository.py`** — Added `find_by_paypal_subscription_id()`
- **`src/repositories/invoice_repository.py`** — Added `find_by_paypal_order_id()`

### Shared Helpers Refactoring
- **`src/plugins/payment_route_helpers.py`** — Moved `determine_session_mode()` from Stripe routes to shared module (DRY: used by both Stripe and PayPal)
- **`plugins/stripe/routes.py`** — Updated import to use shared `determine_session_mode`
- **`plugins/stripe/tests/test_recurring.py`** — Fixed 6 tests to mock `payment_route_helpers.db` instead of `plugins.stripe.routes.db`

### PayPal Plugin (new)
- **`plugins/paypal/__init__.py`** — `PayPalPlugin(PaymentProviderPlugin)` with metadata, blueprint, lifecycle
- **`plugins/paypal/sdk_adapter.py`** — `PayPalSDKAdapter(BaseSDKAdapter)` with:
  - OAuth2 token caching
  - `create_payment_intent()` → PayPal Orders API v2
  - `capture_order()` → explicit capture (unlike Stripe auto-capture)
  - `create_subscription()` → PayPal Billing Subscriptions API
  - `create_billing_plan()` / `create_product()` → auto-create billing plans
  - `get_payment_status()` / `get_subscription_status()`
  - `verify_webhook_signature()` → PayPal API verification (not local like Stripe)
  - `refund_payment()` → full/partial refund
- **`plugins/paypal/routes.py`** — 4 routes + 5 webhook handlers:
  - `POST /create-session` (alias: `/create-order`) — Create PayPal Order or Subscription
  - `POST /capture-order` — Explicit capture after buyer approval
  - `POST /webhook` — Handles 5 event types:
    - `PAYMENT.CAPTURE.COMPLETED` → PaymentCapturedEvent
    - `BILLING.SUBSCRIPTION.ACTIVATED` → Link subscription + PaymentCapturedEvent
    - `PAYMENT.SALE.COMPLETED` → Renewal invoice + PaymentCapturedEvent
    - `BILLING.SUBSCRIPTION.CANCELLED` → SubscriptionCancelledEvent
    - `BILLING.SUBSCRIPTION.PAYMENT.FAILED` → PaymentFailedEvent
  - `GET /session-status/<order_id>` — Payment status with auto-reconciliation
- **`plugins/paypal/config.json`** — Plugin config schema
- **`plugins/paypal/admin-config.json`** — Admin UI config layout

### PayPal Backend Tests (55 tests)
- `test_plugin.py` — 10 tests (metadata, hierarchy, blueprint, lifecycle)
- `test_sdk_adapter.py` — 15 tests (auth, create order, capture, subscription, refund, webhook verify)
- `test_routes.py` — 16 tests (auth, validation, CRUD, webhook verification, session-status)
- `test_webhook.py` — 6 tests (event emission, correct fields, no direct mutations)
- `test_recurring.py` — 8 tests (subscription activated, sale renewal, deduplication, cancellation, payment failed, capture event)

## Frontend Changes

### PayPal Frontend Plugin (new)
- **`plugins/paypal-payment/index.ts`** — Plugin registering 3 routes (`/pay/paypal`, `/pay/paypal/success`, `/pay/paypal/cancel`)
- **`plugins/paypal-payment/PayPalPaymentView.vue`** — Uses shared `usePaymentRedirect('/plugins/paypal', api)` for redirect flow
- **`plugins/paypal-payment/PayPalSuccessView.vue`** — Custom capture-then-confirm flow:
  - Reads `token` (order ID) or `subscription_id` from PayPal return URL
  - For one-time: POST `/capture-order`, then show confirmation
  - For subscription: Webhook handles activation, show confirmation immediately
- **`plugins/paypal-payment/PayPalCancelView.vue`** — Static cancel page with retry link

### Checkout Integration
- **`Checkout.vue`** — Added PayPal redirect watcher alongside Stripe
- **`PublicCheckoutView.vue`** — Added PayPal redirect watcher
- **`InvoicePay.vue`** — Added PayPal redirect for pending invoices
- **`InvoiceDetail.vue`** — Added PayPal "Pay Now" button

### Plugin Registration
- **`main.ts`** — Added `paypalPaymentPlugin` to available plugins
- **`plugins.json`** — Added `paypal-payment` entry

### i18n (EN + DE)
- Added `paypal.payment.*`, `paypal.success.*`, `paypal.cancel.*` keys to both `en.json` and `de.json`

### PayPal Frontend Tests (16 tests)
- `paypal-payment.spec.ts` — 6 tests (plugin name, version, routes, auth meta, activate/deactivate)
- `paypal-views.spec.ts` — 10 tests (redirect loading/error/retry, capture success/subscription/failure/no-token, cancel view)

## Architecture Comparison: Stripe vs PayPal

| Feature | Stripe | PayPal |
|---------|--------|--------|
| Auth | API key header | OAuth2 client credentials |
| Amount format | Cents (2999) | Dollars ("29.99") |
| Capture | Automatic (on checkout.session.completed) | Explicit (POST /capture-order) |
| Webhook verify | Local signature check (stripe library) | PayPal API call |
| Subscription link | `provider_subscription_id` | `provider_subscription_id` |
| Invoice dedup | `provider_session_id` | `provider_session_id` |
| Renewal webhook | `invoice.paid` | `PAYMENT.SALE.COMPLETED` |
| Cancel webhook | `customer.subscription.deleted` | `BILLING.SUBSCRIPTION.CANCELLED` |
| Shared helpers | All 4 from payment_route_helpers.py | All 4 from payment_route_helpers.py |
| Frontend composable | `usePaymentRedirect` + `usePaymentStatus` | `usePaymentRedirect` + custom capture |

## Files Changed

### New Files (18)
- `plugins/paypal/__init__.py`
- `plugins/paypal/sdk_adapter.py`
- `plugins/paypal/routes.py`
- `plugins/paypal/config.json`
- `plugins/paypal/admin-config.json`
- `plugins/paypal/tests/__init__.py`
- `plugins/paypal/tests/conftest.py`
- `plugins/paypal/tests/test_plugin.py`
- `plugins/paypal/tests/test_sdk_adapter.py`
- `plugins/paypal/tests/test_routes.py`
- `plugins/paypal/tests/test_webhook.py`
- `plugins/paypal/tests/test_recurring.py`
- `alembic/versions/20260212_add_paypal_fields.py`
- `user/plugins/paypal-payment/index.ts`
- `user/plugins/paypal-payment/PayPalPaymentView.vue`
- `user/plugins/paypal-payment/PayPalSuccessView.vue`
- `user/plugins/paypal-payment/PayPalCancelView.vue`
- Frontend test files (2)

### Modified Files (14)
- `src/models/subscription.py` — Added paypal_subscription_id
- `src/models/invoice.py` — Added paypal_order_id
- `src/repositories/subscription_repository.py` — Added find_by_paypal_subscription_id
- `src/repositories/invoice_repository.py` — Added find_by_paypal_order_id
- `src/plugins/payment_route_helpers.py` — Added determine_session_mode
- `plugins/stripe/routes.py` — Import shared determine_session_mode
- `plugins/stripe/tests/test_recurring.py` — Fixed db mock paths
- `user/vue/src/main.ts` — Register PayPal plugin
- `user/plugins/plugins.json` — Add paypal-payment entry
- `user/vue/src/views/Checkout.vue` — PayPal redirect
- `user/plugins/checkout/PublicCheckoutView.vue` — PayPal redirect
- `user/vue/src/views/InvoicePay.vue` — PayPal redirect
- `user/vue/src/views/InvoiceDetail.vue` — PayPal "Pay Now" button
- `user/vue/src/i18n/locales/{en,de}.json` — PayPal i18n keys
