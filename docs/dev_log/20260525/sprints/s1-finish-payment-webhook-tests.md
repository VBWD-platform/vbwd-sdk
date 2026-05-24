# S1 (finish) — rewire payment-webhook tests to the lifecycle port

**Risk:** medium (tedious, not architectural). **Independent** of S4/S5 — can run
anytime to get CI green. S1 *code* is done; only its tests are stale.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md). Gate:
`bin/pre-commit-check.sh --full` green before "done" (tests assert the port
seam via DI — register a fake `ISubscriptionLifecycle` / patch `resolve_*`;
don't reintroduce the old repo coupling).

## Why they're red
The webhook handlers no longer call `container.subscription_repository()` — they
call the `ISubscriptionLifecycle` port (link / record_provider_renewal /
cancel_by_provider_subscription_id / mark_provider_payment_failed /
mark_invoice_payment_failed) and `line_item_registry.recurring_billing_spec`.
~40–50 tests across `plugins/{stripe,paypal,yookassa}/tests` still mock + assert
the old `subscription_repository` seam.

## Pattern to apply (per failing test)
- Drop `mock_container.subscription_repository...` setup/asserts.
- Register a fake lifecycle: `register_subscription_lifecycle(FakeLifecycle())`
  (from `vbwd.services.subscription_lifecycle`) in setup; `clear_*` in teardown
  — OR patch `resolve_subscription_lifecycle` in the route module.
- Assert the port method was called with the expected provider args
  (e.g. `record_provider_renewal("stripe", sub_id, amount, currency, ref)`),
  and that `emit_payment_captured` is still called with the returned invoice id.
- For recurring-checkout tests (`_build_stripe_subscription_items`,
  `_get_or_create_paypal_plan`): register a fake line-item handler returning a
  `RecurringBillingSpec`, or assert via the real subscription handler.

## Reference (the new seams)
- `vbwd/services/subscription_lifecycle.py` — port + null + register/clear/resolve.
- `vbwd/events/line_item_registry.py` — `recurring_billing_spec` + `RecurringBillingSpec`.
- Already-green examples to copy the style from:
  `tests/unit/test_recurring_line_item_registry.py`,
  `plugins/subscription/tests/unit/test_subscription_recurring_spec.py`,
  `tests/unit/test_entitlement_port.py`.

## Pre-existing (do NOT try to fix here)
`plugins/paypal/tests/test_sdk_adapter.py` errors on an unimplemented
`release_authorization` abstractmethod — unrelated to this sprint.

## Acceptance
`docker compose run --rm test pytest plugins/{stripe,paypal,yookassa}/tests -q`
green (modulo the pre-existing paypal adapter errors, tracked separately).
