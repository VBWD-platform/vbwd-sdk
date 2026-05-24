# Report 04 — Checkout / payment broken: missing subscription DI providers (fixed)

**Date:** 2026-05-24 · **Author:** Claude (Opus 4.7) · **Severity:** high
(checkout + all paid payments broken in the running app)

## Symptoms (reported by user)

1. Stripe checkout fails. `POST /api/v1/user/checkout`
   `{plan_id, payment_method_code: "stripe", …}` →
   `"error": "'DynamicContainer' object has no attribute 'subscription_repository'"`.
2. "invoice payment is not possible — no payment methods work."

## Root cause

The backend subscription **extraction** (prior sprint) moved the subscription
repositories out of core `vbwd/container.py` into
`plugins/subscription/subscription/repositories/`, but **never re-registered
them as DI providers** on the runtime container. `vbwd.container.Container` is a
`DeclarativeContainer` that instantiates to a `DynamicContainer`; the extraction
removed `subscription_repository`, `addon_subscription_repository`,
`addon_repository`, `tarif_plan_repository`, `tarif_plan_category_repository`
from it and added them nowhere.

Meanwhile every subscription-domain consumer still resolves them off the shared
container:
- `CheckoutHandler` (`checkout.requested`) → `container.subscription_repository()`
- `SubscriptionCancelledHandler`, the line-item handlers
- the **payment plugins**: `stripe`, `paypal`, `yookassa` routes/webhooks all
  call `container.subscription_repository()`

So **checkout** threw immediately, and **payment processing** (stripe/paypal/
yookassa webhooks + reconciliation) would have thrown too — hence symptom 2:
checkout never produced a payable invoice, and the pay path was broken.

**Why it shipped:** the extraction was live-validated only for
"login / permissions / cms / ghrm" (report 02 §3e) — **checkout and payment were
never exercised**, and no test covered the container wiring.

> Note: this is a **backend extraction** defect, independent of the Sprint 10
> *frontend* checkout work. The frontend was sending the correct payload.

## Fix

`plugins/subscription/__init__.py` `on_enable()` now registers the five
subscription repository providers on the shared container (the "plugins are
gnostic, core is agnostic" pattern — the plugin owns and wires its own repos):

```python
from dependency_injector import providers
container.subscription_repository = providers.Factory(
    SubscriptionRepository, session=container.db_session)
container.addon_subscription_repository = providers.Factory(
    AddOnSubscriptionRepository, session=container.db_session)
container.addon_repository = providers.Factory(
    AddOnRepository, session=container.db_session)
container.tarif_plan_repository = providers.Factory(
    TarifPlanRepository, session=container.db_session)
container.tarif_plan_category_repository = providers.Factory(
    TarifPlanCategoryRepository, session=container.db_session)
```

`session=container.db_session` matches how core repos are wired (the
`before_request` hook overrides `db_session` per request).

## Verification (live, against `:5000` after `docker compose restart api`)

| Step | Result |
|---|---|
| `POST /user/checkout` (free plan) | ✅ invoice created (was: 500 `subscription_repository`) |
| `POST /user/checkout` (Basic 9.99 + stripe) | ✅ `is_payable: true`, `paid_at: null`, subscription **PENDING** |
| `GET /settings/payment-methods` | ✅ invoice / stripe / paypal active (list was never the problem) |
| `POST /plugins/stripe/create-session` (payable invoice) | ✅ real `cs_test_…` + `checkout.stripe.com` URL |

Both reported symptoms resolved by this one fix.

## Regression guard (so it can't silently break again)

`plugins/subscription/tests/integration/test_di_providers_registered.py` — 6
tests asserting each provider exists on `app.container` and resolves to a
repository. **6 passed.** Full subscription suite **36 passed**. `black` +
`flake8 --max-line-length=120` clean.

## Follow-ups

- Consider asserting the same contract in the backend agnosticism oracle
  (`tests/unit/test_subscription_agnostic_backend.py`) so core stays free of
  these providers *and* the plugin is proven to supply them.
- The prod deploy of the subscription extraction needs this fix before paid
  checkout/payment work — flag for the release gate.
