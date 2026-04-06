# Task 4: Subscription Management Enhancement

**Priority:** MEDIUM
**Current:** 70% → **Target:** 100%
**Estimated Time:** 2-3 hours

---

## Current State Analysis

### Implemented (70%)
- [x] `get_active_subscription(user_id)`
- [x] `get_user_subscriptions(user_id)`
- [x] `create_subscription(user_id, tarif_plan_id)`
- [x] `activate_subscription(subscription_id)`
- [x] `cancel_subscription(subscription_id)`
- [x] `renew_subscription(subscription_id)`
- [x] `get_expiring_subscriptions(days)`
- [x] `expire_subscriptions()`
- [x] User routes: list, active, cancel

### Missing (30%)
- [ ] Pause/Resume functionality
- [ ] Upgrade/Downgrade between plans
- [ ] Proration calculation
- [ ] Extended test coverage

---

## TDD Checklist

### Step 1: Pause/Resume (RED → GREEN)

**Add tests to** `tests/unit/services/test_subscription_service.py`:

```python
class TestSubscriptionPauseResume:

    def test_pause_subscription_success(self):
        """Active subscription can be paused."""
        # Arrange
        subscription = create_active_subscription()

        # Act
        result = service.pause_subscription(subscription.id)

        # Assert
        assert result.success is True
        assert result.subscription.status == SubscriptionStatus.PAUSED

    def test_pause_subscription_already_paused(self):
        """Pausing already paused subscription fails."""
        subscription = create_paused_subscription()

        result = service.pause_subscription(subscription.id)

        assert result.success is False
        assert result.error == "Subscription is already paused"

    def test_pause_subscription_not_active(self):
        """Only active subscriptions can be paused."""
        subscription = create_pending_subscription()

        result = service.pause_subscription(subscription.id)

        assert result.success is False
        assert result.error == "Only active subscriptions can be paused"

    def test_pause_subscription_records_paused_at(self):
        """Pausing records the paused timestamp."""
        subscription = create_active_subscription()

        result = service.pause_subscription(subscription.id)

        assert result.subscription.paused_at is not None

    def test_resume_subscription_success(self):
        """Paused subscription can be resumed."""
        subscription = create_paused_subscription()

        result = service.resume_subscription(subscription.id)

        assert result.success is True
        assert result.subscription.status == SubscriptionStatus.ACTIVE

    def test_resume_subscription_not_paused(self):
        """Only paused subscriptions can be resumed."""
        subscription = create_active_subscription()

        result = service.resume_subscription(subscription.id)

        assert result.success is False
        assert result.error == "Subscription is not paused"

    def test_resume_extends_expiration(self):
        """Resuming extends expiration by paused duration."""
        # Subscription paused for 5 days
        subscription = create_paused_subscription(paused_days=5)
        original_expiration = subscription.expires_at

        result = service.resume_subscription(subscription.id)

        # Expiration extended by 5 days
        expected_expiration = original_expiration + timedelta(days=5)
        assert result.subscription.expires_at == expected_expiration

    def test_resume_clears_paused_at(self):
        """Resuming clears the paused_at timestamp."""
        subscription = create_paused_subscription()

        result = service.resume_subscription(subscription.id)

        assert result.subscription.paused_at is None
```

**Implement in** `src/services/subscription_service.py`:

```python
def pause_subscription(self, subscription_id: str) -> SubscriptionResult:
    """
    Pause an active subscription.

    The subscription will stop being billed and the expiration
    will be extended when resumed.
    """
    subscription = self._subscription_repo.find_by_id(subscription_id)
    if not subscription:
        return SubscriptionResult(success=False, error="Subscription not found")

    if subscription.status == SubscriptionStatus.PAUSED:
        return SubscriptionResult(success=False, error="Subscription is already paused")

    if subscription.status != SubscriptionStatus.ACTIVE:
        return SubscriptionResult(success=False, error="Only active subscriptions can be paused")

    subscription.pause()  # Model method
    self._subscription_repo.save(subscription)

    return SubscriptionResult(success=True, subscription=subscription)

def resume_subscription(self, subscription_id: str) -> SubscriptionResult:
    """
    Resume a paused subscription.

    The expiration date is extended by the duration of the pause.
    """
    subscription = self._subscription_repo.find_by_id(subscription_id)
    if not subscription:
        return SubscriptionResult(success=False, error="Subscription not found")

    if subscription.status != SubscriptionStatus.PAUSED:
        return SubscriptionResult(success=False, error="Subscription is not paused")

    # Calculate pause duration
    paused_duration = datetime.utcnow() - subscription.paused_at

    # Extend expiration
    subscription.expires_at += paused_duration

    # Resume
    subscription.resume()  # Model method
    self._subscription_repo.save(subscription)

    return SubscriptionResult(success=True, subscription=subscription)
```

**Update model** `src/models/subscription.py`:

```python
def pause(self) -> None:
    """Pause subscription."""
    self.status = SubscriptionStatus.PAUSED
    self.paused_at = datetime.utcnow()

def resume(self) -> None:
    """Resume paused subscription."""
    self.status = SubscriptionStatus.ACTIVE
    self.paused_at = None
```

---

### Step 2: Upgrade/Downgrade (RED → GREEN)

**Add tests:**

```python
class TestSubscriptionPlanChange:

    def test_upgrade_subscription_success(self):
        """User can upgrade to higher tier plan."""
        subscription = create_subscription(plan_id=basic_plan.id)

        result = service.upgrade_subscription(
            subscription.id,
            new_plan_id=premium_plan.id
        )

        assert result.success is True
        assert result.subscription.tarif_plan_id == premium_plan.id

    def test_upgrade_calculates_prorated_credit(self):
        """Upgrade calculates credit for unused time."""
        # Subscription with 15 days remaining on $10/month plan
        subscription = create_subscription(
            plan_id=basic_plan.id,  # $10/month
            days_remaining=15
        )

        result = service.calculate_proration(
            subscription.id,
            new_plan_id=premium_plan.id  # $20/month
        )

        # Credit: $10 * (15/30) = $5
        # New charge: $20 - $5 = $15
        assert result.credit == Decimal('5.00')
        assert result.amount_due == Decimal('15.00')

    def test_downgrade_subscription_success(self):
        """User can downgrade to lower tier plan."""
        subscription = create_subscription(plan_id=premium_plan.id)

        result = service.downgrade_subscription(
            subscription.id,
            new_plan_id=basic_plan.id
        )

        assert result.success is True
        # Downgrade takes effect at renewal
        assert result.subscription.pending_plan_id == basic_plan.id

    def test_downgrade_takes_effect_at_renewal(self):
        """Downgrade takes effect at next billing cycle."""
        subscription = create_subscription(
            plan_id=premium_plan.id,
            expires_at=datetime.utcnow() + timedelta(days=10)
        )

        result = service.downgrade_subscription(
            subscription.id,
            new_plan_id=basic_plan.id
        )

        # Current plan unchanged
        assert result.subscription.tarif_plan_id == premium_plan.id
        # Pending change recorded
        assert result.subscription.pending_plan_id == basic_plan.id

    def test_cannot_change_to_same_plan(self):
        """Changing to current plan is rejected."""
        subscription = create_subscription(plan_id=basic_plan.id)

        result = service.upgrade_subscription(
            subscription.id,
            new_plan_id=basic_plan.id
        )

        assert result.success is False
        assert result.error == "Already subscribed to this plan"

    def test_cannot_upgrade_inactive_subscription(self):
        """Only active subscriptions can be upgraded."""
        subscription = create_cancelled_subscription()

        result = service.upgrade_subscription(
            subscription.id,
            new_plan_id=premium_plan.id
        )

        assert result.success is False
```

**Implement:**

```python
def calculate_proration(
    self,
    subscription_id: str,
    new_plan_id: str
) -> ProrationResult:
    """
    Calculate proration for plan change.

    Returns credit for unused time and amount due for new plan.
    """
    subscription = self._subscription_repo.find_by_id(subscription_id)
    current_plan = self._plan_repo.find_by_id(subscription.tarif_plan_id)
    new_plan = self._plan_repo.find_by_id(new_plan_id)

    # Calculate days remaining
    days_remaining = (subscription.expires_at - datetime.utcnow()).days
    total_days = self.PERIOD_DAYS.get(current_plan.billing_period, 30)

    # Credit for unused time
    daily_rate = current_plan.price / Decimal(total_days)
    credit = daily_rate * Decimal(days_remaining)

    # Amount due for new plan
    amount_due = new_plan.price - credit

    return ProrationResult(
        credit=credit.quantize(Decimal('0.01')),
        amount_due=max(amount_due, Decimal('0')).quantize(Decimal('0.01')),
        days_remaining=days_remaining
    )

def upgrade_subscription(
    self,
    subscription_id: str,
    new_plan_id: str
) -> SubscriptionResult:
    """Upgrade subscription to higher tier plan immediately."""
    subscription = self._subscription_repo.find_by_id(subscription_id)

    if subscription.tarif_plan_id == new_plan_id:
        return SubscriptionResult(
            success=False,
            error="Already subscribed to this plan"
        )

    if subscription.status != SubscriptionStatus.ACTIVE:
        return SubscriptionResult(
            success=False,
            error="Only active subscriptions can be upgraded"
        )

    # Change plan immediately
    subscription.tarif_plan_id = new_plan_id
    self._subscription_repo.save(subscription)

    return SubscriptionResult(success=True, subscription=subscription)

def downgrade_subscription(
    self,
    subscription_id: str,
    new_plan_id: str
) -> SubscriptionResult:
    """Downgrade subscription at next renewal."""
    subscription = self._subscription_repo.find_by_id(subscription_id)

    if subscription.tarif_plan_id == new_plan_id:
        return SubscriptionResult(
            success=False,
            error="Already subscribed to this plan"
        )

    # Set pending plan change
    subscription.pending_plan_id = new_plan_id
    self._subscription_repo.save(subscription)

    return SubscriptionResult(success=True, subscription=subscription)
```

---

### Step 3: Add User Routes

**Add to** `src/routes/subscriptions.py`:

```python
@subscriptions_bp.route('/<subscription_id>/pause', methods=['POST'])
@require_auth
def pause_subscription(subscription_id):
    """POST /api/v1/user/subscriptions/<id>/pause"""
    pass

@subscriptions_bp.route('/<subscription_id>/resume', methods=['POST'])
@require_auth
def resume_subscription(subscription_id):
    """POST /api/v1/user/subscriptions/<id>/resume"""
    pass

@subscriptions_bp.route('/<subscription_id>/upgrade', methods=['POST'])
@require_auth
def upgrade_subscription(subscription_id):
    """
    POST /api/v1/user/subscriptions/<id>/upgrade

    Body: { "plan_id": "..." }
    """
    pass

@subscriptions_bp.route('/<subscription_id>/downgrade', methods=['POST'])
@require_auth
def downgrade_subscription(subscription_id):
    """
    POST /api/v1/user/subscriptions/<id>/downgrade

    Body: { "plan_id": "..." }
    """
    pass

@subscriptions_bp.route('/<subscription_id>/proration', methods=['GET'])
@require_auth
def get_proration(subscription_id):
    """
    GET /api/v1/user/subscriptions/<id>/proration?new_plan_id=...

    Returns proration calculation for plan change.
    """
    pass
```

---

### Step 4: Update Model (if needed)

Add fields to `src/models/subscription.py`:

```python
class Subscription(BaseModel):
    # ... existing fields ...

    paused_at = db.Column(db.DateTime, nullable=True)
    pending_plan_id = db.Column(
        db.String(36),
        db.ForeignKey('tarif_plan.id'),
        nullable=True
    )
```

**Migration:** Create Alembic migration for new fields.

---

### Step 5: Verify

```bash
# Run subscription tests
docker-compose run --rm python-test pytest tests/unit/services/test_subscription_service.py -v

# Check coverage
docker-compose run --rm python-test pytest tests/ --cov=src/services/subscription_service --cov-report=term-missing

# Target: 95%+ coverage
```

---

## New API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/user/subscriptions/<id>/pause` | Pause subscription |
| POST | `/api/v1/user/subscriptions/<id>/resume` | Resume subscription |
| POST | `/api/v1/user/subscriptions/<id>/upgrade` | Upgrade plan |
| POST | `/api/v1/user/subscriptions/<id>/downgrade` | Downgrade plan |
| GET | `/api/v1/user/subscriptions/<id>/proration` | Get proration |

---

## Acceptance Criteria

- [ ] Pause/Resume implemented and tested
- [ ] Upgrade/Downgrade implemented and tested
- [ ] Proration calculation correct
- [ ] 15+ new tests added
- [ ] Test coverage ≥ 95%
- [ ] New routes working
- [ ] Database migration created (if needed)
- [ ] No linting errors
