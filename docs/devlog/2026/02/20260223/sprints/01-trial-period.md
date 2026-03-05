# Sprint 01: Trial Period for Subscriptions

**Date:** 2026-02-23
**Branch:** `feature/macfix`
**Approach:** TDD-first (Red → Green → Refactor)
**Principles:** SOLID, DI, DRY, Liskov, Clean Code, no overengineering, drop deprecated stubs

---

## Requirements (confirmed with product owner)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Where trial_days lives | **Per plan** — `trial_days` column on `tarif_plan` |
| 2 | Trial expiry behavior | **Auto-cancel + invoice** — TRIALING → CANCELLED, pending invoice generated |
| 3 | Tokens during trial | **No** — tokens credited only on ACTIVE (after payment) |
| 4 | Trial limit | **One trial ever** per user (across all plans) |
| 5 | `is_valid` includes TRIALING | **Yes** — TRIALING users get full feature access (except tokens) |
| 6 | Manual activation of trial | **No** — TRIALING → ACTIVE only via invoice mark-paid |

---

## Current State (what exists today)

### Dead code to remove

- `src/routes/admin/subscriptions.py:106-120` — Broken trial stub referencing non-existent `SubscriptionStatus.TRIALING`, case mismatch (`"trialing"` vs uppercase)
- `src/routes/admin/invoices.py:128-129` — Hardcoded `subscription_is_trial = False` / `subscription_trial_end = None`

### Frontend (already built, needs no changes unless noted)

- `vbwd-fe-admin/vue/src/views/SubscriptionCreate.vue` — Trial days input when status is TRIALING
- `vbwd-fe-admin/vue/src/views/InvoiceDetails.vue` — Displays `subscription_is_trial` and `subscription_trial_end`
- `vbwd-fe-admin/vue/src/stores/invoices.ts` — TypeScript interface has `subscription_is_trial?` and `subscription_trial_end?`

---

## Implementation Plan

### Step 1: Add `TRIALING` to `SubscriptionStatus` enum

**Test first:** `test_subscription_status_has_trialing`
- Assert `SubscriptionStatus.TRIALING.value == "TRIALING"`

**Implementation:**
- Add `TRIALING = "TRIALING"` to `SubscriptionStatus` in `src/models/enums.py`
- Alembic migration: `ALTER TYPE subscriptionstatus ADD VALUE IF NOT EXISTS 'TRIALING'`

**Files:**
- `src/models/enums.py`
- `alembic/versions/YYYYMMDD_HHMM_add_trialing_status.py`

---

### Step 2: Add `trial_days` column to `tarif_plan`

**Test first:** `test_tarif_plan_has_trial_days_field`
- Create TarifPlan with `trial_days=14`, assert it persists and defaults to `0`

**Implementation:**
- Add `trial_days = db.Column(db.Integer, nullable=False, default=0)` to `TarifPlan`
- Include `trial_days` in `TarifPlan.to_dict()`
- Alembic migration: `ADD COLUMN trial_days INTEGER NOT NULL DEFAULT 0`

**Files:**
- `src/models/tarif_plan.py`
- `alembic/versions/YYYYMMDD_HHMM_add_trial_days_to_plan.py`

---

### Step 3: Add `trial_end_at` column to `subscription`

**Test first:** `test_subscription_has_trial_end_at_field`
- Create Subscription with `trial_end_at`, assert it persists and defaults to `None`

**Implementation:**
- Add `trial_end_at = db.Column(db.DateTime, nullable=True)` to `Subscription`
- Include `trial_end_at` in `Subscription.to_dict()`
- Alembic migration: `ADD COLUMN trial_end_at TIMESTAMP`

**Files:**
- `src/models/subscription.py`
- `alembic/versions/YYYYMMDD_HHMM_add_trial_end_at_to_subscription.py`

---

### Step 4: Add `has_used_trial` column to `user`

**Test first:** `test_user_has_used_trial_field`
- Create User with `has_used_trial=False`, assert default is `False`

**Implementation:**
- Add `has_used_trial = db.Column(db.Boolean, nullable=False, default=False)` to `User`
- Alembic migration: `ADD COLUMN has_used_trial BOOLEAN NOT NULL DEFAULT FALSE`

**Files:**
- `src/models/user.py`
- `alembic/versions/YYYYMMDD_HHMM_add_has_used_trial_to_user.py`

> **Note:** Steps 2-4 migrations can be combined into a single migration file.

---

### Step 5: Update `Subscription` model methods

**Tests first:**

1. `test_start_trial_sets_trialing_status` — `subscription.start_trial(14)` sets status=TRIALING, started_at=now, trial_end_at=now+14d, expires_at=now+14d
2. `test_is_valid_returns_true_for_trialing` — TRIALING subscription with future trial_end_at → `is_valid == True`
3. `test_is_valid_returns_false_for_expired_trial` — TRIALING subscription with past trial_end_at → `is_valid == False`
4. `test_is_trialing_property` — TRIALING status → `is_trialing == True`, ACTIVE → `False`

**Implementation:**

Add to `Subscription` model:

```python
def start_trial(self, trial_days: int) -> None:
    now = datetime.utcnow()
    self.status = SubscriptionStatus.TRIALING
    self.started_at = now
    self.trial_end_at = now + timedelta(days=trial_days)
    self.expires_at = self.trial_end_at

@property
def is_trialing(self) -> bool:
    return self.status == SubscriptionStatus.TRIALING

@property
def is_valid(self) -> bool:  # MODIFIED — add TRIALING
    if self.status not in (SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING):
        return False
    if self.expires_at and self.expires_at < datetime.utcnow():
        return False
    return True
```

**Files:**
- `src/models/subscription.py`
- `tests/unit/models/test_subscription.py`

---

### Step 6: Add `start_trial()` to `SubscriptionService`

**Tests first:**

1. `test_start_trial_creates_trialing_subscription` — Creates subscription with TRIALING status, sets trial_end_at, no invoice, no tokens credited
2. `test_start_trial_rejects_user_who_used_trial` — User with `has_used_trial=True` → returns error
3. `test_start_trial_rejects_user_with_active_subscription` — User with active sub → returns error
4. `test_start_trial_sets_has_used_trial_on_user` — After trial creation, `user.has_used_trial == True`
5. `test_start_trial_uses_plan_trial_days` — Reads `trial_days` from tarif_plan, not from request

**Implementation:**

Add to `SubscriptionService`:

```python
def start_trial(self, user_id: UUID, tarif_plan_id: UUID, user_repo) -> SubscriptionResult:
    user = user_repo.find_by_id(user_id)
    if not user:
        return SubscriptionResult(success=False, error="User not found")

    if user.has_used_trial:
        return SubscriptionResult(success=False, error="User has already used a trial")

    existing = self._subscription_repo.find_active_by_user(user_id)
    if existing:
        return SubscriptionResult(success=False, error="User already has an active subscription")

    plan = self._tarif_plan_repo.find_by_id(tarif_plan_id)
    if not plan:
        return SubscriptionResult(success=False, error="Plan not found")
    if plan.trial_days <= 0:
        return SubscriptionResult(success=False, error="Plan has no trial period")

    subscription = Subscription()
    subscription.user_id = user_id
    subscription.tarif_plan_id = tarif_plan_id
    subscription.start_trial(plan.trial_days)

    saved = self._subscription_repo.save(subscription)

    user.has_used_trial = True
    user_repo.save(user)

    return SubscriptionResult(success=True, subscription=saved)
```

**DI note:** `user_repo` passed as argument (not stored on service) — SubscriptionService shouldn't own UserRepository as a permanent dependency. This follows Interface Segregation.

**Files:**
- `src/services/subscription_service.py`
- `tests/unit/services/test_subscription_service.py`

---

### Step 7: Update `activate_subscription()` — block direct activation of trials

**Tests first:**

1. `test_activate_rejects_trialing_subscription` — TRIALING subscription → returns error "Trial subscriptions can only be activated via invoice payment"

**Implementation:**

Add guard at the top of `activate_subscription()`:

```python
if subscription.status == SubscriptionStatus.TRIALING:
    return SubscriptionResult(
        success=False,
        error="Trial subscriptions can only be activated via invoice payment",
    )
```

**Files:**
- `src/services/subscription_service.py`
- `tests/unit/services/test_subscription_service.py`

---

### Step 8: Add `expire_trials()` to `SubscriptionService`

**Tests first:**

1. `test_expire_trials_cancels_expired_trials` — Trialing subscription with past trial_end_at → CANCELLED
2. `test_expire_trials_skips_active_trials` — Trialing subscription with future trial_end_at → still TRIALING
3. `test_expire_trials_creates_pending_invoice` — Expired trial generates a PENDING invoice for the plan's full price

**Implementation:**

Add to `SubscriptionService`:

```python
def expire_trials(self, invoice_repo) -> list[dict]:
    expired_trials = self._subscription_repo.find_expired_trials()
    results = []

    for subscription in expired_trials:
        subscription.cancel()
        self._subscription_repo.save(subscription)

        plan = subscription.tarif_plan
        invoice = UserInvoice()
        invoice.user_id = subscription.user_id
        invoice.tarif_plan_id = plan.id
        invoice.subscription_id = subscription.id
        invoice.invoice_number = UserInvoice.generate_invoice_number()
        invoice.amount = plan.price or plan.price_float or 0
        invoice.currency = plan.currency or "EUR"
        invoice.status = InvoiceStatus.PENDING
        invoice.invoiced_at = datetime.utcnow()
        invoice.expires_at = datetime.utcnow() + timedelta(days=30)
        invoice_repo.save(invoice)

        results.append({
            "subscription_id": str(subscription.id),
            "invoice_id": str(invoice.id),
        })

    return results
```

Add to `SubscriptionRepository`:

```python
def find_expired_trials(self) -> list[Subscription]:
    return self._session.query(Subscription).filter(
        Subscription.status == SubscriptionStatus.TRIALING,
        Subscription.trial_end_at <= datetime.utcnow(),
    ).all()
```

**Files:**
- `src/services/subscription_service.py`
- `src/repositories/subscription_repository.py`
- `tests/unit/services/test_subscription_service.py`

---

### Step 9: Update `PaymentCapturedHandler` — handle trial conversion

**Tests first:**

1. `test_payment_converts_trial_to_active` — CANCELLED (post-trial) subscription linked to a paid invoice → becomes ACTIVE, tokens credited, expiration set to billing period

**Implementation:**

In `PaymentCapturedHandler.handle()`, the subscription activation block already handles PENDING → ACTIVE. Extend to also allow CANCELLED subscriptions that have a `trial_end_at` (indicating they were trials):

```python
if subscription and subscription.status in (
    SubscriptionStatus.PENDING,
    SubscriptionStatus.CANCELLED,  # post-trial conversion
):
```

The rest of the activation logic (set ACTIVE, calculate expiration, credit tokens) stays the same.

**Files:**
- `src/handlers/payment_handler.py`
- `tests/unit/handlers/test_payment_handler.py`

---

### Step 10: Clean up admin routes — drop broken stubs

**Tests first:**

1. `test_create_subscription_with_trial_status` — POST with `status: "trialing"` → creates TRIALING subscription via service, no invoice
2. `test_create_subscription_trial_rejected_for_used_trial` — User with `has_used_trial=True` → 409

**Implementation:**

In `src/routes/admin/subscriptions.py`:
- **Delete** the broken `if requested_status == "trialing"` block (lines 106-120)
- Replace with a call to `subscription_service.start_trial()` when `requested_status == "trialing"`
- Return 201 with subscription data, no invoice object

**Files:**
- `src/routes/admin/subscriptions.py`
- `tests/unit/routes/test_admin_subscriptions.py` (if exists) or integration tests

---

### Step 11: Update invoice detail route — return real trial data

**Tests first:**

1. `test_invoice_detail_shows_trial_status` — Invoice linked to a subscription with `trial_end_at` → response has `subscription_is_trial: true`, `subscription_trial_end: <iso date>`

**Implementation:**

In `src/routes/admin/invoices.py`, replace hardcoded values:

```python
# DELETE these two lines:
# inv_dict["subscription_is_trial"] = False
# inv_dict["subscription_trial_end"] = None

# REPLACE with:
inv_dict["subscription_is_trial"] = subscription.trial_end_at is not None
inv_dict["subscription_trial_end"] = (
    subscription.trial_end_at.isoformat()
    if subscription.trial_end_at
    else None
)
```

**Files:**
- `src/routes/admin/invoices.py`

---

### Step 12: Update `find_active_by_user` to include TRIALING

**Tests first:**

1. `test_find_active_by_user_returns_trialing` — User with TRIALING subscription → found by `find_active_by_user`

**Implementation:**

In `SubscriptionRepository.find_active_by_user()`, change filter:

```python
# FROM:
Subscription.status == SubscriptionStatus.ACTIVE
# TO:
Subscription.status.in_([SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING])
```

This ensures "User already has an active subscription" checks catch trials too.

**Files:**
- `src/repositories/subscription_repository.py`
- `tests/unit/repositories/test_subscription_repository.py`

---

## Migration Summary (single migration file)

```python
def upgrade() -> None:
    op.execute("ALTER TYPE subscriptionstatus ADD VALUE IF NOT EXISTS 'TRIALING'")
    op.add_column('tarif_plan', sa.Column('trial_days', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('subscription', sa.Column('trial_end_at', sa.DateTime(), nullable=True))
    op.add_column('user', sa.Column('has_used_trial', sa.Boolean(), nullable=False, server_default='false'))
```

---

## Files Changed Summary

| File | Action |
|------|--------|
| `src/models/enums.py` | Add `TRIALING` to `SubscriptionStatus` |
| `src/models/tarif_plan.py` | Add `trial_days` column, update `to_dict()` |
| `src/models/subscription.py` | Add `trial_end_at` column, `start_trial()`, `is_trialing`, update `is_valid` and `to_dict()` |
| `src/models/user.py` | Add `has_used_trial` column |
| `src/services/subscription_service.py` | Add `start_trial()`, `expire_trials()`, guard `activate_subscription()` |
| `src/repositories/subscription_repository.py` | Add `find_expired_trials()`, update `find_active_by_user()` |
| `src/handlers/payment_handler.py` | Allow post-trial CANCELLED → ACTIVE conversion |
| `src/routes/admin/subscriptions.py` | Drop broken stubs, call `start_trial()` |
| `src/routes/admin/invoices.py` | Return real trial data instead of hardcoded False |
| `alembic/versions/YYYYMMDD_add_trial_support.py` | Single migration for all schema changes |
| `tests/unit/models/test_subscription.py` | New/updated model tests |
| `tests/unit/services/test_subscription_service.py` | New service tests |

---

## Out of Scope

- Cron job / scheduled task to call `expire_trials()` (infrastructure, not code)
- Frontend changes (already built)
- Email notifications on trial expiry
- Trial extension by admin
- Stripe/PayPal trial integration
