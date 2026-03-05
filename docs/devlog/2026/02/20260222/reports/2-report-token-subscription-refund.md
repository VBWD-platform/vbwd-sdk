# Report: Subscription Token Credit on Payment & Refund Token Deduction

**Date:** 2026-02-23
**Branch:** `feature/macfix`
**Author:** Claude Code (Opus 4.6)

---

## Summary

Fixed two related token balance bugs in the invoice payment/refund flow:

1. **Mark Paid:** Subscription activation did not credit `default_tokens` from the plan's features to the user's token balance.
2. **Refund:** Subscription refund did not deduct the previously credited `default_tokens` from the user's balance. Added a guard that blocks refunds when the user has insufficient tokens.

Additionally fixed all backend shell scripts (`docker-compose` V1 → `docker compose` V2) and corrected stale paths in the Makefile.

---

## Bug 1: Mark Paid — Missing Token Credit

### Problem

When an admin clicked "Mark Paid" on an invoice containing a subscription, the `PaymentCapturedHandler` activated the subscription but never credited `default_tokens` from `tarif_plan.features` to the user's `UserTokenBalance`.

The logic for crediting tokens existed in `SubscriptionService.activate_subscription()` but was not replicated in the event handler path used by manual payments.

### Root Cause

`PaymentCapturedHandler.handle()` processed subscription line items by setting status to `ACTIVE` and calculating expiration, but had no code to read `plan.features.default_tokens` or call the token service.

### Fix

**File:** `vbwd-backend/src/handlers/payment_handler.py` (lines 123-155)

After activating the subscription, the handler now:
1. Reads `default_tokens` from `subscription.tarif_plan.features`
2. Creates/updates `UserTokenBalance` with the credited amount
3. Records a `TokenTransaction` with type `SUBSCRIPTION` for audit trail

### Database Migration

The `SUBSCRIPTION` value existed in the Python `TokenTransactionType` enum but was missing from the PostgreSQL `tokentransactiontype` enum type. Without the migration, inserting a transaction with type `SUBSCRIPTION` caused:

```
psycopg2.errors.InvalidTextRepresentation: invalid input value for enum tokentransactiontype: "SUBSCRIPTION"
```

**Migration file:** `vbwd-backend/alembic/versions/20260223_0718_add_subscription_to_.py`

```python
def upgrade() -> None:
    op.execute("ALTER TYPE tokentransactiontype ADD VALUE IF NOT EXISTS 'SUBSCRIPTION'")
```

---

## Bug 2: Refund — Missing Token Deduction

### Problem

When an admin refunded a subscription invoice, `RefundService._reverse_subscription()` cancelled the subscription but did not deduct the `default_tokens` that were credited at payment time. Users kept tokens from refunded subscriptions.

### Business Rule

Refund should be **blocked** if the user has already spent tokens below the amount that needs to be deducted. The admin sees an error message instructing the user to purchase more tokens before the refund can proceed.

### Fix

**File:** `vbwd-backend/src/services/refund_service.py`

Three changes:

1. **`_calculate_tokens_to_debit()`** (new method) — Pre-calculates total tokens to debit across all line items (subscription `default_tokens` + token bundle amounts).

2. **`process_refund()`** — Added pre-check before marking the invoice as refunded:
   ```python
   if current_balance < total_tokens_to_debit:
       return RefundResult(
           success=False,
           error="Insufficient token balance for refund. ..."
       )
   ```

3. **`_reverse_subscription()`** — Now calls `token_service.debit_tokens()` to deduct `default_tokens` when cancelling a subscription.

**File:** `vbwd-backend/src/routes/admin/invoices.py` (refund_invoice route)

Added pre-check **before** calling the payment provider API. This prevents a scenario where Stripe/PayPal processes the refund but the local system rejects it due to insufficient tokens.

---

## Fix 3: Docker Compose V1 → V2 Migration

### Problem

All backend shell scripts used `docker-compose` (V1, deprecated) instead of `docker compose` (V2). The `reset-database.sh` script failed with "PostgreSQL container is not running" because `docker-compose` couldn't find the compose file when run from the repo root.

### Fix

Replaced `docker-compose` with `docker compose` in all scripts. Added auto-`cd` to `reset-database.sh` so it works from any directory.

---

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `vbwd-backend/src/handlers/payment_handler.py` | Modified | Credit `default_tokens` on subscription activation |
| `vbwd-backend/src/services/refund_service.py` | Modified | Debit tokens on refund, block if insufficient balance |
| `vbwd-backend/src/routes/admin/invoices.py` | Modified | Pre-check token balance before provider refund |
| `vbwd-backend/alembic/versions/20260223_0718_add_subscription_to_.py` | Created | Add `SUBSCRIPTION` to PostgreSQL enum |
| `vbwd-backend/tests/unit/services/test_refund_service.py` | Modified | Updated tests, added insufficient balance test |
| `vbwd-backend/bin/reset-database.sh` | Modified | V2 syntax, auto-cd to script directory |
| `vbwd-backend/bin/install_demo_data.sh` | Modified | V2 syntax |
| `vbwd-backend/bin/pre-commit-check.sh` | Modified | V2 syntax |
| `vbwd-backend/bin/create_user.sh` | Modified | V2 syntax |
| `vbwd-backend/bin/create_admin.sh` | Modified | V2 syntax |
| `vbwd-backend/plugins/taro/bin/populate-db.sh` | Modified | V2 syntax |
| `Makefile` | Modified | V2 syntax, fixed stale `vbwd-frontend/` paths |

---

## Payment Flow (After Fix)

```
Admin clicks "Mark Paid"
    |
    v
InvoiceService.mark_paid() — sets invoice status to PAID
    |
    v
PaymentCapturedEvent dispatched
    |
    v
PaymentCapturedHandler.handle()
    |-- Activate subscription (PENDING -> ACTIVE)
    |-- Credit default_tokens to UserTokenBalance    <-- NEW
    |-- Record TokenTransaction (type=SUBSCRIPTION)  <-- NEW
    |-- Credit token bundles (if any)
    |-- Activate add-ons (if any)
```

## Refund Flow (After Fix)

```
Admin clicks "Refund"
    |
    v
Pre-check: calculate tokens to debit             <-- NEW
    |-- Insufficient balance? -> 400 error        <-- NEW
    |
    v
Call payment provider (Stripe/PayPal)
    |
    v
PaymentRefundedEvent dispatched
    |
    v
RefundService.process_refund()
    |-- Pre-check token balance (double guard)    <-- NEW
    |-- Mark invoice REFUNDED
    |-- Cancel subscription
    |-- Debit default_tokens from balance         <-- NEW
    |-- Record TokenTransaction (type=REFUND)     <-- NEW
    |-- Reverse token bundles (if any)
    |-- Cancel add-ons (if any)
```

---

## Test Results

```
667 passed, 4 skipped (was 666 — added 1 new test)
```

New test: `test_refund_rejects_insufficient_balance` — verifies that refund is blocked when user has fewer tokens than the plan's `default_tokens`.
