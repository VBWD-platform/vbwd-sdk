# Sprint 25d Report: Test/Live Credential Switching

## Summary

Added separate test and live credential fields to both Stripe and PayPal payment plugins. Admins can now store both sandbox and production credentials simultaneously and switch between them using the existing `sandbox` toggle — no need to manually swap API keys.

## Design

### Prefixed Flat Keys

Credentials use `test_` / `live_` prefixes in the existing flat config store. The `sandbox` boolean determines which prefix is active at runtime.

**Stripe keys:**
```
sandbox, test_publishable_key, test_secret_key, test_webhook_secret,
live_publishable_key, live_secret_key, live_webhook_secret
```

**PayPal keys:**
```
sandbox, test_client_id, test_client_secret, test_webhook_id,
live_client_id, live_client_secret, live_webhook_id
```

### Runtime Resolution

Every config read resolves the prefix first, with backward-compatible fallback:
```python
prefix = "test_" if config.get("sandbox", True) else "live_"
secret = config.get(f"{prefix}secret_key") or config.get("secret_key", "")
```

Existing installations with old flat keys (`secret_key`, `client_id`, etc.) continue to work until the admin re-saves configuration through the new UI.

### Admin UI Tabs

Both plugins now have 3 tabs instead of 1:
1. **Mode** — sandbox toggle
2. **Test Credentials** — `test_*` fields
3. **Live Credentials** — `live_*` fields

## Changes

### Config Schema (4 files)
- `plugins/stripe/config.json` — 3 flat credential keys replaced with 6 prefixed keys
- `plugins/stripe/admin-config.json` — Single "Credentials" tab → 3 tabs (Mode, Test, Live)
- `plugins/paypal/config.json` — 3 flat credential keys replaced with 6 prefixed keys
- `plugins/paypal/admin-config.json` — Single "Credentials" tab → 3 tabs (Mode, Test, Live)

### Stripe Plugin Code (2 files)
- `plugins/stripe/__init__.py` — `_get_adapter()` and `verify_webhook()` use prefix resolution
- `plugins/stripe/routes.py` — `_get_adapter()`, webhook handler (`stripe.api_key` + `webhook_secret`), `_handle_charge_refunded()`, and `_handle_refund_updated()` all use prefix resolution

### PayPal Plugin Code (2 files)
- `plugins/paypal/__init__.py` — `_get_adapter()` and `verify_webhook()` use prefix resolution
- `plugins/paypal/routes.py` — `_get_adapter()` and webhook handler (`webhook_id`) use prefix resolution

### Saved Config Migration (1 file)
- `plugins/config.json` — Existing sandbox credentials moved to `test_*` keys, empty `live_*` keys added

### Test Fixtures (8 fixtures across 7 files)
- `plugins/stripe/tests/conftest.py` — `stripe_config` + `sdk_config` use `test_*` keys
- `plugins/stripe/tests/test_routes.py` — `stripe_config` uses `test_*` keys
- `plugins/stripe/tests/test_webhook_event.py` — `stripe_config` uses `test_*` keys
- `plugins/stripe/tests/test_payment_e2e.py` — `stripe_config` uses `test_*` keys
- `plugins/stripe/tests/test_recurring.py` — `stripe_config` uses `test_*` keys
- `plugins/paypal/tests/conftest.py` — `paypal_config` + `sdk_config` use `test_*` keys

## Test Results

| Suite | Count | Status |
|-------|-------|--------|
| Backend unit | 661 | passing (4 skipped) |
| Stripe plugin | 76 | passing |
| PayPal plugin | 55 | passing |
| **Backend total** | **792** | **all passing** |

No frontend changes required — the admin plugin config UI renders tabs dynamically from `admin-config.json`.
