# Report: Trial Period for Subscriptions

**Date:** 2026-02-23
**Branch:** `feature/macfix`
**Sprint doc:** `docs/devlog/20260223/sprints/01-trial-period.md`
**Author:** Claude Code (Opus 4.6)
**Approach:** TDD-first (Red → Green → Refactor)
**Principles:** SOLID, DI, DRY, Liskov, Clean Code, no overengineering, drop deprecated stubs

---

## Summary

Implemented full trial period support for subscriptions. Trial duration is defined per plan (`tarif_plan.trial_days`). Users get one trial across all plans. During trial, users have full feature access but receive no tokens. When a trial expires, the subscription is auto-cancelled and a pending invoice is generated for conversion.

---

## Requirements

| # | Decision | Choice |
|---|----------|--------|
| 1 | Where trial_days lives | Per plan — `trial_days` column on `tarif_plan` |
| 2 | Trial expiry behavior | Auto-cancel + invoice |
| 3 | Tokens during trial | No — only on ACTIVE |
| 4 | Trial limit | One trial ever per user |
| 5 | `is_valid` includes TRIALING | Yes — full feature access |
| 6 | Manual activation of trial | No — must go through invoice payment |

---

## What Was Done

### Schema Changes (single migration: `20260223_0814_add_trial_support.py`)

| Table | Column | Type | Default | Purpose |
|-------|--------|------|---------|---------|
| `tarif_plan` | `trial_days` | `INTEGER NOT NULL` | `0` | Days of trial for this plan (0 = no trial) |
| `subscription` | `trial_end_at` | `TIMESTAMP` | `NULL` | When the trial ends |
| `user` | `has_used_trial` | `BOOLEAN NOT NULL` | `false` | One-trial-per-user guard |

PostgreSQL enum: added `TRIALING` to `subscriptionstatus`.

### Model Changes

**`src/models/enums.py`**
- Added `TRIALING = "TRIALING"` to `SubscriptionStatus`

**`src/models/tarif_plan.py`**
- Added `trial_days` column
- Included `trial_days` in `to_dict()`

**`src/models/subscription.py`**
- Added `trial_end_at` column
- Added `start_trial(trial_days)` method — sets TRIALING status, calculates trial_end_at and expires_at
- Added `is_trialing` property
- Modified `is_valid` — returns `True` for both ACTIVE and TRIALING (Liskov: trialing subscriptions are valid subscriptions)
- Updated `to_dict()` — includes `is_trialing` and `trial_end_at`

**`src/models/user.py`**
- Added `has_used_trial` column

### Service Changes

**`src/services/subscription_service.py`**

`start_trial(user_id, tarif_plan_id, user_repo)`:
- Validates user exists
- Rejects if `user.has_used_trial` is True
- Rejects if user already has active/trialing subscription
- Rejects if plan has `trial_days <= 0`
- Creates subscription via `Subscription.start_trial()`
- Sets `user.has_used_trial = True`
- DI: `user_repo` passed as argument (Interface Segregation — SubscriptionService doesn't own UserRepository)

`activate_subscription()`:
- Added guard: TRIALING subscriptions cannot be force-activated. Must go through invoice payment.

`expire_trials(invoice_repo)`:
- Finds all TRIALING subscriptions past their `trial_end_at`
- Cancels each subscription
- Creates a PENDING invoice for the plan's full price
- Returns list of `{subscription_id, invoice_id}` for audit

### Repository Changes

**`src/repositories/subscription_repository.py`**
- `find_active_by_user()` — now queries `status IN (ACTIVE, TRIALING)` instead of just ACTIVE
- Added `find_expired_trials()` — finds TRIALING subscriptions where `trial_end_at <= now`

### Handler Changes

**`src/handlers/payment_handler.py`**
- `PaymentCapturedHandler.handle()` — subscription activation now accepts both PENDING and CANCELLED status. This allows post-trial conversion: when a trial expires (TRIALING → CANCELLED) and the user pays the generated invoice, the subscription becomes ACTIVE with full billing period and token credit.

### Route Changes

**`src/routes/admin/subscriptions.py`**
- Deleted broken trial stubs (lines 106-120) that referenced non-existent `SubscriptionStatus.TRIALING` and had case mismatch bugs
- Replaced with call to `SubscriptionService.start_trial()` when `requested_status == "trialing"`
- Removed unused `trial_days` variable extraction from request body (plan owns trial_days)
- Returns 409 for "already used trial" or "active subscription" conflicts

**`src/routes/admin/invoices.py`**
- Replaced hardcoded `subscription_is_trial = False` / `subscription_trial_end = None`
- Now reads real values from `subscription.trial_end_at`

---

## Deprecated Code Removed

| Location | What | Why |
|----------|------|-----|
| `routes/admin/subscriptions.py:106-120` | Broken `if requested_status == "trialing"` block | Referenced non-existent enum, case mismatch, duplicated logic |
| `routes/admin/subscriptions.py:78` | `trial_days = data.get("trial_days")` | trial_days now comes from plan, not request |
| `routes/admin/invoices.py:128-129` | Hardcoded `False` / `None` | Replaced with real data |

---

## Trial Lifecycle

```
Admin creates trial subscription (POST /api/v1/admin/subscriptions with status: "trialing")
    |
    v
SubscriptionService.start_trial()
    |-- Validate: user exists, no active sub, hasn't used trial, plan has trial_days
    |-- Create subscription with status=TRIALING, trial_end_at=now+trial_days
    |-- Set user.has_used_trial = True
    |-- No invoice created, no tokens credited
    |
    v
User has feature access (is_valid=True, is_trialing=True)
    |
    v
Trial expires (trial_end_at <= now)
    |
    v
expire_trials() [called by cron/scheduled task]
    |-- Cancel subscription (TRIALING -> CANCELLED)
    |-- Create PENDING invoice for full plan price
    |
    v
Two paths:
    |
    ├─ User pays invoice (admin clicks "mark paid")
    |   └─ PaymentCapturedHandler converts CANCELLED -> ACTIVE
    |       |-- Full billing period set
    |       |-- default_tokens credited
    |       |-- User is now a paying subscriber
    |
    └─ User doesn't pay
        └─ Subscription stays CANCELLED, invoice stays PENDING/expires
```

---

## Test Results

```
Before: 667 passed, 4 skipped
After:  685 passed, 4 skipped (+18 new tests)
```

### New Test Files

**`tests/unit/models/test_subscription.py`** (8 tests):
- `test_subscription_status_has_trialing`
- `test_start_trial_sets_trialing_status`
- `test_is_trialing_true_for_trialing_status`
- `test_is_trialing_false_for_active_status`
- `test_is_valid_true_for_trialing_with_future_expiry`
- `test_is_valid_false_for_expired_trial`
- `test_is_valid_still_true_for_active`
- `test_to_dict_includes_trial_fields`

**`tests/unit/services/test_subscription_service.py`** (10 new tests added):
- `TestStartTrial::test_creates_trialing_subscription`
- `TestStartTrial::test_rejects_user_who_used_trial`
- `TestStartTrial::test_rejects_user_with_active_subscription`
- `TestStartTrial::test_sets_has_used_trial_on_user`
- `TestStartTrial::test_uses_plan_trial_days`
- `TestStartTrial::test_rejects_plan_without_trial`
- `TestActivateRejectsTrialing::test_activate_rejects_trialing_subscription`
- `TestExpireTrials::test_cancels_expired_trials`
- `TestExpireTrials::test_creates_pending_invoice_on_expiry`
- `TestExpireTrials::test_skips_active_trials`

---

## Files Changed

| File | Action |
|------|--------|
| `src/models/enums.py` | Added `TRIALING` |
| `src/models/tarif_plan.py` | Added `trial_days` column |
| `src/models/subscription.py` | Added `trial_end_at`, `start_trial()`, `is_trialing`, updated `is_valid`, `to_dict()` |
| `src/models/user.py` | Added `has_used_trial` column |
| `src/services/subscription_service.py` | Added `start_trial()`, `expire_trials()`, guarded `activate_subscription()` |
| `src/repositories/subscription_repository.py` | Added `find_expired_trials()`, updated `find_active_by_user()` |
| `src/handlers/payment_handler.py` | Extended to handle post-trial CANCELLED → ACTIVE |
| `src/routes/admin/subscriptions.py` | Dropped broken stubs, delegated to service |
| `src/routes/admin/invoices.py` | Returns real trial data |
| `alembic/versions/20260223_0814_add_trial_support.py` | Migration for all schema changes |
| `tests/unit/models/test_subscription.py` | Created (8 tests) |
| `tests/unit/services/test_subscription_service.py` | Added 10 trial tests |

---

## Out of Scope

- Cron job / scheduled task to call `expire_trials()` (infrastructure)
- Frontend changes (admin UI already supports trial creation and display)
- Email notifications on trial start/expiry
- Trial extension by admin
- Stripe/PayPal trial period integration
