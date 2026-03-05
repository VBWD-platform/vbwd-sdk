# Sprint 25c Report: Provider-Agnostic Refactoring

## Summary

Refactored all core code (models, repositories, admin routes) to be completely provider-agnostic. Provider-specific column names (`stripe_*`, `paypal_*`) replaced with generic names (`payment_*`, `provider_*`). Admin refund route now uses plugin system instead of direct provider imports. Also fixed two bugs: invoices staying "pending" after payment, and admin refund not reaching provider APIs.

## Bug Fixes

### 1. Invoice Stays Pending After Payment
**Root cause**: `capture-order` (PayPal) and `_reconcile_payment` (Stripe) relied on provider metadata (`custom_id`, `metadata.invoice_id`) to find the invoice. In sandbox environments, these fields could be empty after capture.

**Fix**: Store `provider_session_id` on invoice during `create-session` (before redirect). Added fallback lookup by `provider_session_id` in capture-order, session-status, and _reconcile_payment routes.

### 2. Admin Refund Not Reaching Provider API
**Root cause**: Admin refund route only emitted local `PaymentRefundedEvent` (updates DB status), never called Stripe/PayPal API to issue real refund.

**Fix**: Added `_refund_via_provider()` that uses the plugin system generically: `plugin_manager.get_plugin(payment_method).refund_payment(transaction_ref)`. No direct imports from any provider plugin.

### 3. PayPal Refund Capture ID Resolution
**Root cause**: PayPal refund API requires `capture_id` but we store `order_id`. Initial fix put resolution logic in core admin route (violated provider-agnostic principle).

**Fix**: Moved `_resolve_capture_id()` into `PayPalPlugin.refund_payment()` — the plugin internally resolves order_id → capture_id via `GET /v2/checkout/orders/{order_id}`.

## Provider-Agnostic Refactoring

### Column Renames (Alembic Migration)

| Table | Old Column(s) | New Column |
|-------|---------------|------------|
| `user` | `stripe_customer_id` | `payment_customer_id` |
| `subscription` | `stripe_subscription_id` + `paypal_subscription_id` | `provider_subscription_id` (merged) |
| `addon_subscription` | `stripe_subscription_id` | `provider_subscription_id` |
| `user_invoice` | `stripe_invoice_id` + `paypal_order_id` | `provider_session_id` (merged) |

Migration merges duplicate columns: copies PayPal data into Stripe column (mutually exclusive), drops PayPal column, renames to generic name. Full downgrade() support.

### Repository Method Renames

| Repository | Old Method(s) | New Method |
|------------|---------------|------------|
| `InvoiceRepository` | `find_by_stripe_invoice_id()` + `find_by_paypal_order_id()` | `find_by_provider_session_id()` |
| `SubscriptionRepository` | `find_by_stripe_subscription_id()` + `find_by_paypal_subscription_id()` | `find_by_provider_subscription_id()` |
| `AddOnSubscriptionRepository` | `find_by_stripe_subscription_id()` | `find_by_provider_subscription_id()` |

### Admin Refund Route

Before (provider-specific):
```python
from plugins.stripe.sdk_adapter import StripeSDKAdapter
from plugins.paypal.sdk_adapter import PayPalSDKAdapter
# ... direct provider logic
```

After (provider-agnostic):
```python
def _refund_via_provider(invoice):
    plugin = plugin_manager.get_plugin(invoice.payment_method)
    result = plugin.refund_payment(invoice.provider_session_id or invoice.payment_ref)
```

## Test Results

| Suite | Count | Status |
|-------|-------|--------|
| Backend unit | 661 | passing (4 skipped) |
| Stripe plugin | 76 | passing |
| PayPal plugin | 55 | passing |
| **Backend total** | **792** | **all passing** |

All plugin tests updated to use new generic column/method names.

## Files Changed

### New Files (1)
- `alembic/versions/20260212_rename_provider_columns.py` — Column rename + merge migration

### Modified Core Files (7)
- `src/models/user.py` — `stripe_customer_id` → `payment_customer_id`
- `src/models/subscription.py` — Merged to `provider_subscription_id`
- `src/models/addon_subscription.py` — `stripe_subscription_id` → `provider_subscription_id`
- `src/models/invoice.py` — Merged to `provider_session_id`
- `src/repositories/invoice_repository.py` — `find_by_provider_session_id()`
- `src/repositories/subscription_repository.py` — `find_by_provider_subscription_id()`
- `src/repositories/addon_subscription_repository.py` — `find_by_provider_subscription_id()`
- `src/routes/admin/invoices.py` — Generic `_refund_via_provider()` via plugin system
- `src/plugins/payment_route_helpers.py` — Added logging

### Modified Plugin Files (8)
- `plugins/stripe/routes.py` — Generic column names, store `provider_session_id` at create-session
- `plugins/stripe/tests/test_payment_e2e.py` — Updated column refs
- `plugins/stripe/tests/test_recurring.py` — Updated column/method refs
- `plugins/paypal/__init__.py` — `refund_payment()` with internal capture_id resolution
- `plugins/paypal/routes.py` — Generic column names, store `provider_session_id` at create-session, fallback lookups
- `plugins/paypal/tests/test_recurring.py` — Updated column/method refs

## Architecture Principle Enforced

> Core code (`src/`) must NEVER reference specific providers. Only plugin code (`plugins/`) may contain provider-specific logic and variable names.

This refactoring ensures the principle holds across models, repositories, and admin routes. The Sprint 25 report's "Architecture Comparison" table column names are now generic:

| Feature | Generic Column |
|---------|---------------|
| Customer link | `payment_customer_id` |
| Subscription link | `provider_subscription_id` |
| Invoice/session dedup | `provider_session_id` |
