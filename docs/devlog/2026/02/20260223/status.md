# Sprint Status — 2026-02-23

**Branch:** `feature/macfix`
**Approach:** TDD-first (Red → Green → Refactor)
**Principles:** SOLID, DI, DRY, Liskov, Clean Code, no overengineering, drop deprecated stubs

---

## Completed Today

### 1. Token Credit on Subscription Payment
- **Status:** DONE
- **Files:** `src/handlers/payment_handler.py`, migration `20260223_0718_add_subscription_to_.py`
- **Summary:** Mark-paid now credits `default_tokens` from plan features to user's token balance. Added `SUBSCRIPTION` value to PostgreSQL `tokentransactiontype` enum.

### 2. Token Deduction on Subscription Refund
- **Status:** DONE
- **Files:** `src/services/refund_service.py`, `src/routes/admin/invoices.py`, `tests/unit/services/test_refund_service.py`
- **Summary:** Refund now deducts `default_tokens` from user balance. Blocked if user has insufficient tokens. Pre-check runs before payment provider call.

### 3. Docker Compose V1 → V2 Migration
- **Status:** DONE
- **Files:** `Makefile`, `bin/reset-database.sh`, `bin/install_demo_data.sh`, `bin/pre-commit-check.sh`, `bin/create_user.sh`, `bin/create_admin.sh`, `plugins/taro/bin/populate-db.sh`
- **Summary:** Replaced all `docker-compose` (V1) with `docker compose` (V2). Fixed stale `vbwd-frontend/` paths in Makefile. Added auto-cd to `reset-database.sh`.

### 4. Report: Token/Subscription/Refund Fix
- **Status:** DONE
- **File:** `docs/devlog/20260222/reports/2-report-token-subscription-refund.md`

---

### 5. Sprint 01: Trial Period for Subscriptions
- **Status:** DONE
- **Sprint doc:** `docs/devlog/20260223/sprints/01-trial-period.md`
- **Steps completed:** 12/12
- **New tests:** 18 (8 model + 10 service)
- **Migration:** `20260223_0814_add_trial_support.py`
- **Summary:**
  - Added `TRIALING` to `SubscriptionStatus` enum
  - Added `trial_days` column to `tarif_plan` (per-plan trial duration)
  - Added `trial_end_at` column to `subscription`
  - Added `has_used_trial` column to `user` (one trial per user lifetime)
  - `Subscription.start_trial()` model method, `is_trialing` property
  - `is_valid` now returns `True` for TRIALING (full feature access, no tokens)
  - `SubscriptionService.start_trial()` — validates user eligibility, creates trial
  - `SubscriptionService.expire_trials()` — auto-cancels expired trials + creates invoice
  - `activate_subscription()` blocks TRIALING (must go through invoice payment)
  - `PaymentCapturedHandler` handles post-trial CANCELLED → ACTIVE conversion
  - `find_active_by_user()` includes TRIALING subscriptions
  - Dropped broken trial stubs from admin route, replaced with service call
  - Invoice detail route returns real trial data instead of hardcoded `False`

---

## Test Results

```
Backend: 685 passed, 4 skipped
```
