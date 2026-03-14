# Sprint: Billing Gaps — Recurring Billing & Subscription Lifecycle

**Date:** 2026-03-14
**Scope:** `vbwd-backend` — payment plugins + subscription service

## Context

A billing audit identified 5 gaps that leave subscribers in incorrect states or prevent certain billing configurations. This sprint closes all of them. No new features beyond what is described; no changes to frontend.

## Core Requirements

TDD, SOLID, DI, DRY, DevOps First, clean code, no overengineering.

---

## Step 1 — Add `DAILY` billing period (all layers)

**Files:**
- `src/models/enums.py` — `BillingPeriod`
- `src/services/subscription_service.py` — `PERIOD_DAYS`
- `plugins/stripe/routes.py` — `BILLING_PERIOD_TO_STRIPE`
- `plugins/paypal/routes.py` — `BILLING_PERIOD_TO_PAYPAL`
- `alembic/versions/` — new migration (no schema change needed; `billing_period` is a VARCHAR, not a DB enum)

**Changes:**

```python
# src/models/enums.py
class BillingPeriod(enum.Enum):
    DAILY     = "DAILY"      # ← add
    WEEKLY    = "WEEKLY"
    MONTHLY   = "MONTHLY"
    QUARTERLY = "QUARTERLY"
    YEARLY    = "YEARLY"
    ONE_TIME  = "ONE_TIME"
```

```python
# src/services/subscription_service.py
PERIOD_DAYS = {
    BillingPeriod.DAILY:     1,      # ← add
    BillingPeriod.WEEKLY:    7,
    BillingPeriod.MONTHLY:   30,
    BillingPeriod.QUARTERLY: 90,
    BillingPeriod.YEARLY:    365,
    BillingPeriod.ONE_TIME:  36500,
}
```

```python
# plugins/stripe/routes.py
BILLING_PERIOD_TO_STRIPE = {
    "DAILY":     {"interval": "day"},      # ← add
    "WEEKLY":    {"interval": "week"},
    "MONTHLY":   {"interval": "month"},
    "QUARTERLY": {"interval": "month", "interval_count": 3},
    "YEARLY":    {"interval": "year"},
}
```

```python
# plugins/paypal/routes.py
BILLING_PERIOD_TO_PAYPAL = {
    "daily":     {"interval_unit": "DAY",   "interval_count": 1},  # ← add
    "weekly":    {"interval_unit": "WEEK",  "interval_count": 1},
    "monthly":   {"interval_unit": "MONTH", "interval_count": 1},
    "quarterly": {"interval_unit": "MONTH", "interval_count": 3},
    "yearly":    {"interval_unit": "YEAR",  "interval_count": 1},
}
```

**Tests:**
- Unit: `tests/unit/test_subscription_service.py` — assert `PERIOD_DAYS[BillingPeriod.DAILY] == 1`; assert `expires_at = started_at + 1 day` for a DAILY plan
- Unit: `tests/unit/plugins/stripe/test_stripe_routes.py` — assert DAILY maps to `{"interval": "day"}`
- Unit: `tests/unit/plugins/paypal/test_paypal_routes.py` — assert DAILY maps to `{"interval_unit": "DAY", "interval_count": 1}`

---

## Step 2 — YooKassa auto-renewal (charge saved payment method)

**Context:** `save_payment_method: True` is already sent on the initial payment and the payment method ID is stored as `subscription.provider_subscription_id`. The renewal charge code does not exist yet.

**Files:**
- `plugins/yookassa/routes.py` — add `_charge_saved_method(subscription, invoice)` helper
- `plugins/yookassa/src/services/yookassa_renewal_service.py` (new) — renewal logic, injectable

**New helper — `_charge_saved_method`:**

```python
def _charge_saved_method(subscription, invoice):
    """Charge the saved YooKassa payment method for a renewal invoice."""
    payment_method_id = subscription.provider_subscription_id
    if not payment_method_id:
        raise ValueError("No saved payment method for subscription")

    idempotency_key = str(invoice.id)
    response = yookassa_sdk.Payment.create({
        "amount": {
            "value": str(invoice.amount),
            "currency": "RUB",
        },
        "capture": True,
        "payment_method_id": payment_method_id,
        "description": f"Renewal: {invoice.id}",
        "metadata": {
            "invoice_id": str(invoice.id),
            "subscription_id": str(subscription.id),
            "renewal": "true",
        },
    }, idempotency_key)
    return response
```

**Wire-up:**
- When `expire_trials()` / `expire_subscriptions()` creates a renewal invoice for a YooKassa subscription, call `_charge_saved_method` immediately.
- On `payment.succeeded` webhook — already handled; the existing `_handle_payment_succeeded()` activates the subscription and marks the invoice PAID.
- Add `payment.canceled` webhook handler — see Step 3.

**Tests:**
- Unit: mock `yookassa_sdk.Payment.create`; assert it is called with `payment_method_id`, correct amount, idempotency key = invoice ID
- Unit: assert `ValueError` when `provider_subscription_id` is None

---

## Step 3 — YooKassa payment failure webhook

**Context:** `plugins/yookassa/routes.py` handles `payment.succeeded` and `payment.canceled` but does not emit `PaymentFailedEvent` on cancellation, and `payment.canceled` (YooKassa's term for a failed/rejected payment) has no handler body.

**Changes in `plugins/yookassa/routes.py`:**

```python
# In the webhook dispatcher:
elif event_type == "payment.canceled":
    _handle_payment_canceled(data)
```

```python
def _handle_payment_canceled(payment_data):
    """Handle YooKassa payment.canceled — mark invoice FAILED and emit event."""
    provider_session_id = payment_data.get("id")
    invoice = Invoice.query.filter_by(provider_session_id=provider_session_id).first()
    if not invoice:
        return

    invoice.status = InvoiceStatus.FAILED
    db.session.commit()

    dispatcher.dispatch(PaymentFailedEvent(
        invoice_id=str(invoice.id),
        user_id=str(invoice.user_id),
        provider="yookassa",
        reason=payment_data.get("cancellation_details", {}).get("reason", "unknown"),
    ))
```

**Tests:**
- Unit: POST `payment.canceled` webhook → invoice status becomes FAILED, `PaymentFailedEvent` dispatched
- Unit: unknown `provider_session_id` → no-op, no exception

---

## Step 4 — Auto-invoke `expire_subscriptions()` and `expire_trials()`

**Context:** Both methods exist in `SubscriptionService` but are never called automatically. Expired subscriptions remain ACTIVE indefinitely.

**Solution:** Add an APScheduler job in the backend's startup (same pattern already used in `plugins/ghrm/src/scheduler.py`).

**New file: `src/scheduler.py`**

```python
from apscheduler.schedulers.background import BackgroundScheduler
from src.extensions import db
from src.services.subscription_service import SubscriptionService
from src.repositories.subscription_repository import SubscriptionRepository
import logging

logger = logging.getLogger(__name__)

def _run_subscription_expiry():
    """Expire subscriptions and trials. Runs daily."""
    with db.app.app_context():   # db.app set at startup
        repo = SubscriptionRepository(db.session)
        svc  = SubscriptionService(repo)
        expired = svc.expire_subscriptions()
        trials  = svc.expire_trials()
        logger.info("[Scheduler] Expired %d subscriptions, %d trials", len(expired), len(trials))

def start_subscription_scheduler(app):
    """Start the background scheduler. Call once from create_app()."""
    scheduler = BackgroundScheduler()
    scheduler.add_job(
        _run_subscription_expiry,
        trigger="cron",
        hour=0,
        minute=5,
        id="expire_subscriptions",
        replace_existing=True,
    )
    scheduler.start()
    logger.info("[Scheduler] Subscription expiry scheduler started (daily 00:05 UTC)")
    return scheduler
```

**Wire-up in `src/app.py` or `create_app()`:**

```python
from src.scheduler import start_subscription_scheduler

def create_app(config=None):
    app = Flask(__name__)
    # ... existing setup ...
    start_subscription_scheduler(app)
    return app
```

**Tests:**
- Unit: mock `SubscriptionService`; call `_run_subscription_expiry()`; assert `expire_subscriptions()` and `expire_trials()` were each called once
- Integration: create a subscription with `expires_at` in the past; call `_run_subscription_expiry()`; assert status = EXPIRED

---

## Step 5 — Dunning email sequence (day 3, day 7 follow-ups)

**Context:** Currently `PaymentFailedHandler` sends one email immediately. There is no follow-up if the payment remains unpaid.

**Approach:** Store the failure timestamp on the subscription and schedule follow-ups via the daily scheduler job.

**New field on `Subscription` model:**

```python
payment_failed_at = db.Column(db.DateTime, nullable=True)  # set on first failure, cleared on payment
```

**Migration:** `alembic/versions/<date>_add_payment_failed_at.py`

**Changes in `PaymentFailedHandler` (`src/handlers/payment_handlers.py`):**

```python
def handle(self, event: PaymentFailedEvent):
    # existing: send immediate failure email
    _send_payment_failed_email(event)
    # new: record failure timestamp if not already set
    subscription = _get_subscription_for_invoice(event.invoice_id)
    if subscription and not subscription.payment_failed_at:
        subscription.payment_failed_at = utcnow()
        db.session.commit()
```

**New method on `SubscriptionService` — `send_dunning_emails()`:**

```python
DUNNING_DAYS = [3, 7]   # days after first failure to send follow-ups

def send_dunning_emails(self):
    """Send dunning follow-ups for subscriptions with unpaid invoices."""
    now = utcnow()
    results = []
    for days in DUNNING_DAYS:
        cutoff = now - timedelta(days=days)
        # Find subscriptions whose first failure was exactly `days` ago (±1 day window)
        subs = (
            db.session.query(Subscription)
            .filter(
                Subscription.payment_failed_at <= cutoff,
                Subscription.payment_failed_at > cutoff - timedelta(days=1),
                Subscription.status == SubscriptionStatus.ACTIVE,
            )
            .all()
        )
        for sub in subs:
            _send_dunning_email(sub, days_overdue=days)
            results.append(sub.id)
    return results
```

**Wire into scheduler** (Step 4's `_run_subscription_expiry` or a separate daily job):

```python
svc.send_dunning_emails()
```

**Email templates needed:**
- `day-3` subject: "Payment still pending — action required"
- `day-7` subject: "Final notice — subscription will be cancelled"

**Tests:**
- Unit: subscription with `payment_failed_at = now - 3 days` → `send_dunning_emails()` triggers day-3 email
- Unit: subscription with `payment_failed_at = now - 7 days` → day-7 email triggered
- Unit: subscription with `payment_failed_at = now - 1 day` → no email yet
- Unit: subscription with `payment_failed_at = now - 8 days` → no duplicate email (window passed)
- Unit: subscription with status CANCELLED → excluded

---

## Verification

```bash
cd vbwd-backend
./bin/pre-commit-check.sh              # lint + mypy
./bin/pre-commit-check.sh --quick      # lint + unit tests
./bin/pre-commit-check.sh              # full (lint + unit + integration)
```

All checks must be green. Specifically:
1. `BillingPeriod.DAILY` usable end-to-end: create plan with DAILY period, create subscription, assert `expires_at = started_at + 1 day`
2. YooKassa `payment.canceled` → invoice FAILED + event dispatched
3. YooKassa renewal: saved method charged on subscription renewal
4. Scheduler: `expire_subscriptions()` called on cron trigger
5. Dunning: 3-day and 7-day follow-up emails triggered correctly, no double-sends

## Steps deferred

| Item | Reason |
|------|--------|
| Dunning for Stripe/PayPal | Providers already retry autonomously; adding our own sequence would conflict. Monitor provider webhooks instead. |
| YooKassa retry schedule (day 3, day 7 re-charge attempts) | Requires YooKassa account configuration review; tracked separately. |
