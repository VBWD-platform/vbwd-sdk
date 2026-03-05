# Sprint: Default Tokens for Tarif Plans

**Date:** 2026-02-22
**Status:** Pending Approval

---

## Goal

Allow tarif plans to include a `default_tokens` value in their `features` JSON field. On each subscription payment (activation), the user's token balance is credited with that amount.

---

## Scope

- No database migrations, no model changes
- Use existing `features` JSON field on `tarif_plan` table
- Credit tokens on subscription activation via existing `TokenService`
- Update admin routes and frontend to read/write `default_tokens` in features
- Update demo data

---

## Data Structure

The `features` column (JSON) on `tarif_plan` already stores plan configuration. Add `default_tokens` key:

```json
{
  "api_calls": 1000,
  "storage_gb": 10,
  "support": "email",
  "default_tokens": 100
}
```

No value or `0` means no tokens granted.

---

## Tasks (TDD-first, in order)

### Task 1: Add `SUBSCRIPTION` to `TokenTransactionType` enum

**File:** `vbwd-backend/src/models/enums.py`

Add `SUBSCRIPTION = "SUBSCRIPTION"` to distinguish plan-granted tokens from purchases and bonuses in transaction history.

**Test:** Verify enum value exists and is usable.

---

### Task 2: Inject `TokenService` into `SubscriptionService`

**File:** `vbwd-backend/src/services/subscription_service.py`

Add `token_service` as optional constructor parameter (backward compatible):
```python
def __init__(self, subscription_repo, token_service=None):
    self._subscription_repo = subscription_repo
    self._token_service = token_service
```

No behavior change yet. Existing callers don't break.

**Tests first** (`tests/unit/services/test_subscription_service.py`):
```python
def test_subscription_service_accepts_token_service():
    service = SubscriptionService(subscription_repo=Mock(), token_service=Mock())
    assert service._token_service is not None

def test_subscription_service_works_without_token_service():
    service = SubscriptionService(subscription_repo=Mock())
    assert service._token_service is None
```

---

### Task 3: Credit tokens on subscription activation

**File:** `vbwd-backend/src/services/subscription_service.py`

In `activate_subscription()`, after `subscription.activate(duration_days)`:
```python
features = plan.features or {}
default_tokens = features.get("default_tokens", 0) if isinstance(features, dict) else 0

if self._token_service and default_tokens > 0:
    self._token_service.credit_tokens(
        user_id=subscription.user_id,
        amount=default_tokens,
        transaction_type=TokenTransactionType.SUBSCRIPTION,
        reference_id=subscription.id,
        description=f"Plan tokens: {plan.name}"
    )
```

Guard conditions: service injected, features is dict, `default_tokens` > 0.

**Tests first** (`tests/unit/services/test_subscription_service.py`):
```python
def test_activate_credits_tokens_when_features_has_default_tokens():
    # plan.features = {"default_tokens": 100}
    # Assert token_service.credit_tokens called with amount=100

def test_activate_skips_tokens_when_features_has_zero():
    # plan.features = {"default_tokens": 0}
    # Assert token_service.credit_tokens NOT called

def test_activate_skips_tokens_when_features_has_no_key():
    # plan.features = {"api_calls": 1000}
    # Assert token_service.credit_tokens NOT called

def test_activate_skips_tokens_when_features_is_list():
    # plan.features = ["feature_a", "feature_b"]
    # Assert token_service.credit_tokens NOT called

def test_activate_skips_tokens_when_no_token_service():
    # plan.features = {"default_tokens": 100}, token_service=None
    # No error, subscription still activated
```

---

### Task 4: Update DI container wiring

**File:** Check `src/containers.py` or wherever `SubscriptionService` is instantiated.

Pass existing `TokenService` instance to `SubscriptionService` constructor. Follow existing DI pattern.

---

### Task 5: Update admin plan routes

**File:** `vbwd-backend/src/routes/admin/plans.py`

Ensure `default_tokens` is always present in `features` when saving a plan. In both create and update:

```python
features = data.get("features", {})
if isinstance(features, dict) and "default_tokens" not in features:
    features["default_tokens"] = 0
```

This guarantees every plan's features dict has `default_tokens` — either the value provided by admin or `0` as default. No ambiguity between missing key and intentional zero.

---

### Task 6: Admin frontend — plan form field

**File:** `vbwd-fe-admin/vue/src/views/PlanForm.vue`

Add number input for default tokens. Read from / write to `formData.features.default_tokens`:
- Label: "Default Tokens"
- Help text: "Tokens credited to user on each subscription payment"
- Input: `type="number"`, `min="0"`, `step="1"`, default `0`

On submit, include `default_tokens` in the features object sent to the API.

On load (edit mode), read `default_tokens` from plan's features and populate the field.

---

### Task 7: Update demo data

**File:** `vbwd-backend/bin/install_demo_data.sh`

Add `default_tokens` to existing plan features dicts:
- Free: `"default_tokens": 0`
- Basic: `"default_tokens": 50`
- Pro: `"default_tokens": 200`
- Enterprise: `"default_tokens": 1000`
- Lifetime: `"default_tokens": 500`

---

## Out of Scope

- Token deduction on plan downgrade
- Prorated token credits on plan upgrade
- Token expiry tied to subscription period
- Recurring token grants on renewal (only on activation)
- Database migrations or model schema changes

---

## Definition of Done

- [ ] All tests pass (unit + existing integration)
- [ ] Admin can set `default_tokens` in plan features via the form
- [ ] User receives tokens when subscription is activated
- [ ] User does NOT receive tokens when `default_tokens` is 0, missing, or features is a list
- [ ] Token transaction shows type `SUBSCRIPTION` in user history
- [ ] Existing plans and subscriptions unaffected (backward compatible)
