# Sprint 25d: Test/Live Credential Switching for Payment Plugins

## Goal

Both Stripe and PayPal plugins currently have a single set of credentials plus a `sandbox` boolean toggle. The admin must manually swap credentials when switching between test and live mode. Add two separate sets of credential fields (test + live) with a mode switcher, so the admin can store both sets and simply flip the toggle to switch environments.

## Design: Prefixed Flat Keys

Use `test_` / `live_` prefixed keys (not nested objects) to stay compatible with the existing flat config store and admin UI rendering. Each config read uses fallback: `config.get(f"{prefix}key") or config.get("key", "")` for backward compatibility with existing installations.

## Files to Modify

| File | Change |
|------|--------|
| `plugins/stripe/config.json` | 3 flat keys → 6 prefixed keys |
| `plugins/stripe/admin-config.json` | 1 tab → 3 tabs (Mode, Test, Live) |
| `plugins/stripe/__init__.py` | `_get_adapter()` + `verify_webhook()` read prefixed keys |
| `plugins/stripe/routes.py` | `_get_adapter()` + webhook + refund handlers read prefixed keys |
| `plugins/paypal/config.json` | 3 flat keys → 6 prefixed keys |
| `plugins/paypal/admin-config.json` | 1 tab → 3 tabs (Mode, Test, Live) |
| `plugins/paypal/__init__.py` | `_get_adapter()` + `verify_webhook()` read prefixed keys |
| `plugins/paypal/routes.py` | `_get_adapter()` + webhook handler read prefixed keys |
| `plugins/config.json` | Migrate saved values to `test_*` keys |
| `plugins/stripe/tests/*.py` | Update mocked config keys |
| `plugins/paypal/tests/*.py` | Update mocked config keys |
