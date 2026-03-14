# Sprint Report: Billing Gaps — Recurring Billing & Subscription Lifecycle

**Date:** 2026-03-14
**Sprint:** `done/04-billing-gaps.md`
**Pre-commit result:** `./bin/pre-commit-check.sh` → **ALL PASSED** (Black ✓ Flake8 ✓ Mypy ✓ | 1133 unit tests ✓ | 62 integration tests ✓)

---

## What Was Done

### Step 1 — `DAILY` billing period (+ missing `WEEKLY` in PERIOD_DAYS)

- **`src/models/enums.py`** — added `BillingPeriod.DAILY = "DAILY"`
- **`src/services/subscription_service.py`** — added `BillingPeriod.DAILY: 1` and `BillingPeriod.WEEKLY: 7` to `PERIOD_DAYS` (WEEKLY was present in the enum but missing from the dict)
- **`plugins/stripe/routes.py`** — added `"DAILY": {"interval": "day"}` to `BILLING_PERIOD_TO_STRIPE`
- **`plugins/paypal/routes.py`** — added `"daily": {"interval_unit": "DAY", "interval_count": 1}` to `BILLING_PERIOD_TO_PAYPAL`
- **`alembic/versions/20260314_add_daily_billing_period.py`** — `ALTER TYPE billingperiod ADD VALUE IF NOT EXISTS 'DAILY'` (billingperiod is a native PostgreSQL enum on `tarif_plan.billing_period`)

**Note:** `src/models/subscription.py` stores `billing_period` as a VARCHAR — no migration needed there. The `tarif_plan` table uses a native PG enum, which required the migration.

### Step 2 — YooKassa auto-renewal (charge saved payment method)

- **Created** `plugins/yookassa/src/__init__.py`, `plugins/yookassa/src/services/__init__.py`
- **Created** `plugins/yookassa/src/services/yookassa_renewal_service.py` — `YooKassaRenewalService.charge_saved_method(subscription, invoice)`:
  - Reads `subscription.provider_subscription_id` (saved by `_save_payment_method_for_subscription` on initial payment)
  - Raises `ValueError` if no saved method
  - Calls `yookassa.Payment.create({...}, idempotency_key=str(invoice.id))` to prevent duplicate charges
  - Sets `"capture": True`, `"payment_method_id"`, and `"renewal": "true"` in metadata

Wire-up: the existing `payment.succeeded` webhook already handles invoice activation when the renewal charge succeeds.

### Step 3 — YooKassa `payment.canceled` webhook

**`plugins/yookassa/routes.py`** — `_handle_payment_canceled(obj)` previously only logged a warning. Now:

1. Looks up the invoice by `metadata.invoice_id` (consistent with `payment.succeeded`)
2. Falls back to `invoice_repo.find_by_provider_session_id(obj["id"])` if no metadata
3. Sets `invoice.status = InvoiceStatus.FAILED` and saves via `invoice_repo.save(invoice)`
4. Walks the invoice line items to find the subscription
5. Emits `PaymentFailedEvent(subscription_id, user_id, error_code="payment_canceled", error_message=reason, provider="yookassa")` via `container.event_dispatcher().emit(event)`
6. Unknown invoice → no-op, no exception

### Step 4 — APScheduler: auto-invoke `expire_subscriptions()` and `expire_trials()`

- **`requirements.txt`** — added `APScheduler==3.10.4`
- **`src/scheduler.py`** — `_run_subscription_jobs(app)` + `start_subscription_scheduler(app)`:
  - Cron trigger: daily at 00:05 UTC
  - Job: creates `SubscriptionRepository`, `InvoiceRepository`, `SubscriptionService` inside `app.app_context()` and calls `expire_subscriptions()`, `expire_trials(invoice_repo)`, `send_dunning_emails()`
  - Logs counts: `[Scheduler] Expired N subscriptions, N trials, N dunning`
- **`src/app.py`** — calls `start_subscription_scheduler(app)` at the end of `create_app()`, guarded by `if not app.config.get("TESTING")` to prevent scheduler startup during tests

### Step 5 — Dunning email sequence (day 3 + day 7 follow-ups)

**Model:**
- **`src/models/subscription.py`** — added `payment_failed_at = db.Column(db.DateTime, nullable=True)`

**Migration:**
- **`alembic/versions/20260314_add_payment_failed_at.py`** — revision `f2g3h4i5j6k7`, adds `payment_failed_at` column to `subscription` table

**Repository:**
- **`src/repositories/subscription_repository.py`** — `find_dunning_candidates(days_since_failure: int)` — queries `ACTIVE` subscriptions where `payment_failed_at` is in the window `[now - days, now - days + 1 day)` to prevent duplicate sends

**Service:**
- **`src/services/subscription_service.py`** — `DUNNING_DAYS = [3, 7]`; `send_dunning_emails(event_dispatcher=None) -> list` — iterates candidates at each threshold, dispatches `SubscriptionDunningEvent` if dispatcher provided, returns list of `{subscription_id, days_overdue}` dicts

**Event:**
- **`src/events/subscription_events.py`** — added `SubscriptionDunningEvent(subscription_id, user_id, days_overdue, name="subscription.dunning")`

**Handler:**
- **`src/handlers/payment_failed_handler.py`** — `PaymentFailedHandler(container)`:
  - On `PaymentFailedEvent`: finds the subscription via `subscription_repo.find_by_id(event.subscription_id)`
  - If `subscription.payment_failed_at` is `None`, sets it to `utcnow()` and saves
  - This ensures the dunning clock starts on first failure only

- **`src/app.py`** — registers `PaymentFailedHandler(container)` for `"payment.failed"` event in `_register_event_handlers()`

---

## Tests Added

| File | Tests | Coverage |
|------|-------|----------|
| `tests/unit/services/test_subscription_service.py` | `TestBillingPeriodDays` (3), `TestSendDunningEmails` (5) | DAILY=1, WEEKLY=7, all BillingPeriod values covered; dunning candidates, event dispatch, window logic |
| `plugins/stripe/tests/test_recurring.py` | `TestBillingPeriodToStripeDaily` (2) | DAILY→interval=day; DAILY in _build_stripe_subscription_items |
| `plugins/paypal/tests/test_recurring.py` | `TestBillingPeriodToPaypalDaily` (1) | daily→interval_unit=DAY, interval_count=1 |
| `plugins/yookassa/tests/test_renewal_service.py` | `TestYooKassaRenewalService` (4) | Payment.create called, idempotency key=invoice.id, correct amount, ValueError on no payment method |
| `plugins/yookassa/tests/test_webhook.py` | `TestPaymentCanceled` (4) | Invoice marked FAILED + saved, PaymentFailedEvent emitted, unknown invoice no-op, no invoice_id no-op |
| `tests/unit/test_scheduler.py` | `TestRunSubscriptionJobs` (4) | expire_subscriptions called, expire_trials called, send_dunning_emails called, counts logged |

---

## Pre-commit Verification

```
./bin/pre-commit-check.sh --quick → PASS (lint ✓ | 1133 unit tests ✓)
./bin/pre-commit-check.sh        → PASS (lint ✓ | 1133 unit ✓ | 62 integration ✓)
```

Integration test note: `test_model_columns_exist_in_database` and `test_enum_values_match_database` verified the `payment_failed_at` column and `DAILY` enum value were correctly migrated.

---

## Deferred

| Item | Reason |
|------|--------|
| Dunning for Stripe/PayPal | Stripe/PayPal retry autonomously; adding our own sequence would conflict |
| YooKassa retry schedule (day 3/7 re-charge) | Requires YooKassa account configuration review; tracked separately |
| Hash sync API keys | Requires DB migration; tracked in Sprint 01 deferral |
