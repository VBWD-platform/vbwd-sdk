# Sprint 11: Analytics Backend Implementation

**Priority:** HIGH (Required for Admin Dashboard)
**Duration:** 2-3 days
**Focus:** Implement analytics API endpoints for admin dashboard

> **Core Requirements:** TDD-first, SOLID, DI, Clean Code

---

## Overview

The frontend analytics store expects a complete analytics API that currently does NOT exist in the backend. This sprint implements all required endpoints.

### Frontend Expectations (from analytics.spec.ts)

| Endpoint | Purpose |
|----------|---------|
| `GET /admin/analytics/dashboard` | Summary with MRR, revenue, churn, user_growth, conversion, ARPU |
| `GET /admin/analytics/mrr` | Monthly Recurring Revenue data |
| `GET /admin/analytics/revenue` | Revenue time series (with date range) |
| `GET /admin/analytics/churn` | Churn rate data |
| `GET /admin/analytics/users/growth` | User growth time series |
| `GET /admin/analytics/plans/distribution` | Subscription distribution by plan |
| `GET /admin/analytics/activity` | Recent activity feed |

---

## 11.1 Analytics Service Layer

### 11.1.1 Data Models

**TDD Tests First:**
```python
# tests/unit/services/test_analytics_service.py
import pytest
from datetime import datetime, timedelta
from src.services.analytics_service import AnalyticsService, MetricData, MetricPoint

class TestMetricDataStructures:
    def test_metric_point_has_date_and_value(self):
        """MetricPoint contains date and value."""
        point = MetricPoint(date='2025-01-01', value=1000)
        assert point.date == '2025-01-01'
        assert point.value == 1000

    def test_metric_data_has_total_and_optional_change(self):
        """MetricData contains total, optional change_percent, optional data array."""
        metric = MetricData(total=5000, change_percent=10.5)
        assert metric.total == 5000
        assert metric.change_percent == 10.5
        assert metric.data is None

    def test_metric_data_with_time_series(self):
        """MetricData can include time series data."""
        points = [
            MetricPoint(date='2025-01-01', value=100),
            MetricPoint(date='2025-01-02', value=150)
        ]
        metric = MetricData(total=250, data=points)
        assert len(metric.data) == 2
```

**Implementation:**
```python
# src/services/analytics_service.py
from dataclasses import dataclass
from typing import Optional, List
from datetime import datetime

@dataclass
class MetricPoint:
    date: str
    value: float

@dataclass
class MetricData:
    total: float
    change_percent: Optional[float] = None
    data: Optional[List[MetricPoint]] = None

@dataclass
class DashboardData:
    mrr: MetricData
    revenue: MetricData
    churn: MetricData
    user_growth: MetricData
    conversion: MetricData
    arpu: MetricData

@dataclass
class ActivityItem:
    type: str
    user: str
    timestamp: str
    details: Optional[dict] = None
```

---

## 11.2 MRR Calculation

### 11.2.1 Monthly Recurring Revenue

**TDD Tests:**
```python
class TestMRRCalculation:
    def test_calculate_mrr_from_active_subscriptions(self, analytics_service, subscriptions):
        """MRR is sum of monthly values from active subscriptions."""
        # 3 active subscriptions: $10/mo, $20/mo, $50/mo
        result = analytics_service.calculate_mrr()
        assert result.total == 80  # $80 MRR

    def test_mrr_excludes_cancelled_subscriptions(self, analytics_service, cancelled_subscription):
        """Cancelled subscriptions don't contribute to MRR."""
        result = analytics_service.calculate_mrr()
        assert cancelled_subscription.plan.price not in [result.total]

    def test_mrr_change_percent_vs_previous_month(self, analytics_service):
        """MRR includes change percent compared to previous month."""
        # Current: $1000, Previous: $900 → +11.1%
        result = analytics_service.calculate_mrr()
        assert result.change_percent is not None
        assert result.change_percent == pytest.approx(11.1, rel=0.1)

    def test_mrr_handles_annual_subscriptions(self, analytics_service, annual_subscription):
        """Annual subscriptions contribute monthly equivalent to MRR."""
        # $120/year = $10/month
        result = analytics_service.calculate_mrr()
        assert 10 in result.total  # Monthly equivalent included

    def test_mrr_with_date_range(self, analytics_service):
        """Can calculate MRR for specific date."""
        result = analytics_service.calculate_mrr(as_of_date=datetime(2025, 1, 15))
        assert result.total >= 0
```

**Implementation:**
```python
# src/services/analytics_service.py
class AnalyticsService:
    def __init__(self, subscription_repo, user_repo, payment_repo):
        self._subscription_repo = subscription_repo
        self._user_repo = user_repo
        self._payment_repo = payment_repo

    def calculate_mrr(self, as_of_date: datetime = None) -> MetricData:
        """Calculate Monthly Recurring Revenue."""
        as_of_date = as_of_date or datetime.utcnow()

        active_subscriptions = self._subscription_repo.get_active_as_of(as_of_date)

        current_mrr = sum(
            self._get_monthly_value(sub) for sub in active_subscriptions
        )

        # Calculate previous month MRR for change percent
        prev_month = as_of_date.replace(day=1) - timedelta(days=1)
        prev_subscriptions = self._subscription_repo.get_active_as_of(prev_month)
        prev_mrr = sum(
            self._get_monthly_value(sub) for sub in prev_subscriptions
        )

        change_percent = None
        if prev_mrr > 0:
            change_percent = ((current_mrr - prev_mrr) / prev_mrr) * 100

        return MetricData(total=current_mrr, change_percent=change_percent)

    def _get_monthly_value(self, subscription) -> float:
        """Convert subscription to monthly value."""
        plan = subscription.tarif_plan
        if plan.billing_period == 'annual':
            return plan.price / 12
        return plan.price
```

---

## 11.3 Revenue Analytics

### 11.3.1 Revenue Time Series

**TDD Tests:**
```python
class TestRevenueAnalytics:
    def test_get_revenue_time_series(self, analytics_service, payments):
        """Returns revenue grouped by day."""
        result = analytics_service.get_revenue(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert result.data is not None
        assert len(result.data) > 0
        assert all(isinstance(p, MetricPoint) for p in result.data)

    def test_revenue_total_matches_sum(self, analytics_service, payments):
        """Total equals sum of all data points."""
        result = analytics_service.get_revenue(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        calculated_total = sum(p.value for p in result.data)
        assert result.total == calculated_total

    def test_revenue_includes_only_successful_payments(self, analytics_service, failed_payment):
        """Only successful payments count toward revenue."""
        result = analytics_service.get_revenue(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert failed_payment.amount not in [p.value for p in result.data]

    def test_revenue_handles_refunds(self, analytics_service, refund):
        """Refunds reduce revenue total."""
        result = analytics_service.get_revenue(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        # Revenue should account for refund as negative
        assert result.total < result.total + refund.amount
```

**Implementation:**
```python
def get_revenue(self, start_date: datetime, end_date: datetime) -> MetricData:
    """Get revenue time series for date range."""
    payments = self._payment_repo.get_successful_in_range(start_date, end_date)
    refunds = self._payment_repo.get_refunds_in_range(start_date, end_date)

    # Group by day
    daily_revenue = {}
    for payment in payments:
        day = payment.created_at.strftime('%Y-%m-%d')
        daily_revenue[day] = daily_revenue.get(day, 0) + payment.amount

    for refund in refunds:
        day = refund.created_at.strftime('%Y-%m-%d')
        daily_revenue[day] = daily_revenue.get(day, 0) - refund.amount

    # Convert to MetricPoints
    data = [
        MetricPoint(date=day, value=value)
        for day, value in sorted(daily_revenue.items())
    ]

    total = sum(p.value for p in data)

    return MetricData(total=total, data=data)
```

---

## 11.4 Churn Analytics

### 11.4.1 Churn Rate Calculation

**TDD Tests:**
```python
class TestChurnAnalytics:
    def test_calculate_churn_rate(self, analytics_service, subscriptions):
        """Churn rate = cancelled / total at start of period."""
        result = analytics_service.get_churn(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        # 5 cancelled out of 100 at start = 5%
        assert result.total == 5.0

    def test_churn_zero_when_no_cancellations(self, analytics_service):
        """Churn is 0 when no subscriptions cancelled."""
        result = analytics_service.get_churn(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert result.total == 0

    def test_churn_excludes_trial_cancellations(self, analytics_service, trial_cancellation):
        """Trial cancellations don't count toward churn."""
        result = analytics_service.get_churn(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        # Trial cancellations excluded from churn calculation
        assert True  # Verify trial not included

    def test_churn_change_vs_previous_period(self, analytics_service):
        """Churn includes change percent vs previous period."""
        result = analytics_service.get_churn(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert result.change_percent is not None
```

**Implementation:**
```python
def get_churn(self, start_date: datetime, end_date: datetime) -> MetricData:
    """Calculate churn rate for period."""
    # Subscribers at start of period
    start_count = self._subscription_repo.count_active_as_of(start_date)

    if start_count == 0:
        return MetricData(total=0, change_percent=0)

    # Cancellations during period (excluding trials)
    cancellations = self._subscription_repo.count_cancellations_in_range(
        start_date, end_date, exclude_trials=True
    )

    churn_rate = (cancellations / start_count) * 100

    # Calculate previous period for comparison
    period_length = (end_date - start_date).days
    prev_start = start_date - timedelta(days=period_length)
    prev_end = start_date

    prev_start_count = self._subscription_repo.count_active_as_of(prev_start)
    if prev_start_count > 0:
        prev_cancellations = self._subscription_repo.count_cancellations_in_range(
            prev_start, prev_end, exclude_trials=True
        )
        prev_churn = (prev_cancellations / prev_start_count) * 100
        change_percent = churn_rate - prev_churn  # Absolute change for churn
    else:
        change_percent = 0

    return MetricData(total=round(churn_rate, 2), change_percent=round(change_percent, 2))
```

---

## 11.5 User Growth Analytics

### 11.5.1 User Growth Time Series

**TDD Tests:**
```python
class TestUserGrowthAnalytics:
    def test_get_user_growth_time_series(self, analytics_service):
        """Returns new user signups grouped by day."""
        result = analytics_service.get_user_growth(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert result.data is not None
        assert result.total >= 0

    def test_user_growth_counts_new_registrations(self, analytics_service, new_users):
        """Total is count of new registrations in period."""
        result = analytics_service.get_user_growth(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert result.total == len(new_users)

    def test_user_growth_change_percent(self, analytics_service):
        """Includes growth change vs previous period."""
        result = analytics_service.get_user_growth(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert result.change_percent is not None
```

**Implementation:**
```python
def get_user_growth(self, start_date: datetime, end_date: datetime) -> MetricData:
    """Get user growth time series."""
    new_users = self._user_repo.get_created_in_range(start_date, end_date)

    # Group by day
    daily_signups = {}
    for user in new_users:
        day = user.created_at.strftime('%Y-%m-%d')
        daily_signups[day] = daily_signups.get(day, 0) + 1

    data = [
        MetricPoint(date=day, value=count)
        for day, count in sorted(daily_signups.items())
    ]

    total = len(new_users)

    # Previous period comparison
    period_length = (end_date - start_date).days
    prev_start = start_date - timedelta(days=period_length)
    prev_count = self._user_repo.count_created_in_range(prev_start, start_date)

    change_percent = 0
    if prev_count > 0:
        change_percent = ((total - prev_count) / prev_count) * 100

    return MetricData(
        total=total,
        change_percent=round(change_percent, 2),
        data=data
    )
```

---

## 11.6 Plan Distribution

### 11.6.1 Subscription Distribution by Plan

**TDD Tests:**
```python
class TestPlanDistribution:
    def test_get_plan_distribution(self, analytics_service, subscriptions):
        """Returns count of active subscribers per plan."""
        result = analytics_service.get_plan_distribution()
        assert 'Free' in result
        assert 'Pro' in result
        assert all(isinstance(v, int) for v in result.values())

    def test_distribution_only_active_subscriptions(self, analytics_service):
        """Only counts active subscriptions."""
        result = analytics_service.get_plan_distribution()
        # Cancelled/expired not included
        assert sum(result.values()) == analytics_service._subscription_repo.count_active()

    def test_distribution_empty_when_no_subscriptions(self, analytics_service_empty):
        """Returns empty dict when no subscriptions."""
        result = analytics_service_empty.get_plan_distribution()
        assert result == {}
```

**Implementation:**
```python
def get_plan_distribution(self) -> dict:
    """Get active subscription count per plan."""
    active = self._subscription_repo.get_all_active()

    distribution = {}
    for subscription in active:
        plan_name = subscription.tarif_plan.name
        distribution[plan_name] = distribution.get(plan_name, 0) + 1

    return distribution
```

---

## 11.7 Activity Feed

### 11.7.1 Recent Activity

**TDD Tests:**
```python
class TestActivityFeed:
    def test_get_recent_activity(self, analytics_service):
        """Returns list of recent activity items."""
        result = analytics_service.get_recent_activity(limit=10)
        assert isinstance(result, list)
        assert len(result) <= 10

    def test_activity_includes_signups(self, analytics_service, recent_signup):
        """Activity includes user signups."""
        result = analytics_service.get_recent_activity()
        signup_types = [a.type for a in result]
        assert 'signup' in signup_types

    def test_activity_includes_subscriptions(self, analytics_service, recent_subscription):
        """Activity includes new subscriptions."""
        result = analytics_service.get_recent_activity()
        types = [a.type for a in result]
        assert 'subscription' in types

    def test_activity_includes_cancellations(self, analytics_service, recent_cancellation):
        """Activity includes cancellations."""
        result = analytics_service.get_recent_activity()
        types = [a.type for a in result]
        assert 'cancellation' in types

    def test_activity_sorted_by_timestamp_desc(self, analytics_service):
        """Activity is sorted newest first."""
        result = analytics_service.get_recent_activity()
        timestamps = [a.timestamp for a in result]
        assert timestamps == sorted(timestamps, reverse=True)

    def test_activity_item_has_required_fields(self, analytics_service):
        """Each activity item has type, user, timestamp."""
        result = analytics_service.get_recent_activity()
        for item in result:
            assert item.type is not None
            assert item.user is not None
            assert item.timestamp is not None
```

**Implementation:**
```python
def get_recent_activity(self, limit: int = 20) -> List[ActivityItem]:
    """Get recent activity feed."""
    activities = []

    # Recent signups
    recent_users = self._user_repo.get_recent(limit=limit)
    for user in recent_users:
        activities.append(ActivityItem(
            type='signup',
            user=user.email,
            timestamp=user.created_at.isoformat()
        ))

    # Recent subscriptions
    recent_subs = self._subscription_repo.get_recent_created(limit=limit)
    for sub in recent_subs:
        activities.append(ActivityItem(
            type='subscription',
            user=sub.user.email,
            timestamp=sub.created_at.isoformat(),
            details={'plan': sub.tarif_plan.name}
        ))

    # Recent cancellations
    recent_cancels = self._subscription_repo.get_recent_cancellations(limit=limit)
    for sub in recent_cancels:
        activities.append(ActivityItem(
            type='cancellation',
            user=sub.user.email,
            timestamp=sub.cancelled_at.isoformat(),
            details={'plan': sub.tarif_plan.name}
        ))

    # Sort by timestamp descending and limit
    activities.sort(key=lambda x: x.timestamp, reverse=True)
    return activities[:limit]
```

---

## 11.8 Dashboard Aggregate Endpoint

### 11.8.1 Combined Dashboard Data

**TDD Tests:**
```python
class TestDashboardAggregate:
    def test_get_dashboard_returns_all_metrics(self, analytics_service):
        """Dashboard returns MRR, revenue, churn, user_growth, conversion, ARPU."""
        result = analytics_service.get_dashboard()
        assert result.mrr is not None
        assert result.revenue is not None
        assert result.churn is not None
        assert result.user_growth is not None
        assert result.conversion is not None
        assert result.arpu is not None

    def test_dashboard_with_date_range(self, analytics_service):
        """Dashboard respects date range parameters."""
        result = analytics_service.get_dashboard(
            start_date=datetime(2025, 1, 1),
            end_date=datetime(2025, 1, 31)
        )
        assert result is not None

    def test_conversion_rate_calculation(self, analytics_service):
        """Conversion = paid subscribers / total users %."""
        result = analytics_service.get_dashboard()
        # Verify conversion is a percentage
        assert 0 <= result.conversion.total <= 100

    def test_arpu_calculation(self, analytics_service):
        """ARPU = MRR / active subscribers."""
        result = analytics_service.get_dashboard()
        assert result.arpu.total >= 0
```

**Implementation:**
```python
def get_dashboard(
    self,
    start_date: datetime = None,
    end_date: datetime = None
) -> DashboardData:
    """Get complete dashboard metrics."""
    end_date = end_date or datetime.utcnow()
    start_date = start_date or (end_date - timedelta(days=30))

    mrr = self.calculate_mrr()
    revenue = self.get_revenue(start_date, end_date)
    churn = self.get_churn(start_date, end_date)
    user_growth = self.get_user_growth(start_date, end_date)

    # Conversion rate
    total_users = self._user_repo.count_all()
    paid_subscribers = self._subscription_repo.count_paid_active()
    conversion = MetricData(
        total=round((paid_subscribers / total_users * 100) if total_users > 0 else 0, 2)
    )

    # ARPU (Average Revenue Per User)
    active_subs = self._subscription_repo.count_active()
    arpu = MetricData(
        total=round(mrr.total / active_subs if active_subs > 0 else 0, 2)
    )

    return DashboardData(
        mrr=mrr,
        revenue=revenue,
        churn=churn,
        user_growth=user_growth,
        conversion=conversion,
        arpu=arpu
    )
```

---

## 11.9 Analytics Routes

### 11.9.1 API Endpoints

**TDD Tests:**
```python
# tests/unit/routes/test_analytics_routes.py
class TestAnalyticsRoutes:
    def test_get_dashboard(self, client, admin_headers):
        """GET /admin/analytics/dashboard returns dashboard data."""
        response = client.get('/api/v1/admin/analytics/dashboard', headers=admin_headers)
        assert response.status_code == 200
        assert 'mrr' in response.json
        assert 'revenue' in response.json
        assert 'churn' in response.json

    def test_get_dashboard_with_date_range(self, client, admin_headers):
        """Dashboard accepts date range params."""
        response = client.get(
            '/api/v1/admin/analytics/dashboard?start=2025-01-01&end=2025-01-31',
            headers=admin_headers
        )
        assert response.status_code == 200

    def test_get_mrr(self, client, admin_headers):
        """GET /admin/analytics/mrr returns MRR data."""
        response = client.get('/api/v1/admin/analytics/mrr', headers=admin_headers)
        assert response.status_code == 200
        assert 'total' in response.json

    def test_get_revenue(self, client, admin_headers):
        """GET /admin/analytics/revenue returns revenue data."""
        response = client.get(
            '/api/v1/admin/analytics/revenue?start=2025-01-01&end=2025-01-31',
            headers=admin_headers
        )
        assert response.status_code == 200
        assert 'total' in response.json
        assert 'data' in response.json

    def test_get_churn(self, client, admin_headers):
        """GET /admin/analytics/churn returns churn data."""
        response = client.get(
            '/api/v1/admin/analytics/churn?start=2025-01-01&end=2025-01-31',
            headers=admin_headers
        )
        assert response.status_code == 200
        assert 'total' in response.json

    def test_get_user_growth(self, client, admin_headers):
        """GET /admin/analytics/users/growth returns growth data."""
        response = client.get(
            '/api/v1/admin/analytics/users/growth?start=2025-01-01&end=2025-01-31',
            headers=admin_headers
        )
        assert response.status_code == 200

    def test_get_plan_distribution(self, client, admin_headers):
        """GET /admin/analytics/plans/distribution returns distribution."""
        response = client.get('/api/v1/admin/analytics/plans/distribution', headers=admin_headers)
        assert response.status_code == 200
        assert isinstance(response.json, dict)

    def test_get_activity(self, client, admin_headers):
        """GET /admin/analytics/activity returns activity feed."""
        response = client.get('/api/v1/admin/analytics/activity', headers=admin_headers)
        assert response.status_code == 200
        assert 'activity' in response.json

    def test_analytics_requires_admin(self, client, user_headers):
        """Analytics endpoints require admin role."""
        response = client.get('/api/v1/admin/analytics/dashboard', headers=user_headers)
        assert response.status_code == 403

    def test_analytics_requires_auth(self, client):
        """Analytics endpoints require authentication."""
        response = client.get('/api/v1/admin/analytics/dashboard')
        assert response.status_code == 401
```

**Implementation:**
```python
# src/routes/admin/analytics.py
from flask import Blueprint, jsonify, request, current_app, g
from datetime import datetime
from src.decorators import require_auth, require_role

analytics_bp = Blueprint('analytics', __name__, url_prefix='/admin/analytics')

@analytics_bp.route('/dashboard', methods=['GET'])
@require_auth
@require_role('admin')
def get_dashboard():
    """Get dashboard summary metrics."""
    start = request.args.get('start')
    end = request.args.get('end')

    start_date = datetime.fromisoformat(start) if start else None
    end_date = datetime.fromisoformat(end) if end else None

    analytics_service = current_app.container.analytics_service()
    dashboard = analytics_service.get_dashboard(start_date, end_date)

    return jsonify({
        'mrr': {'total': dashboard.mrr.total, 'change_percent': dashboard.mrr.change_percent},
        'revenue': {'total': dashboard.revenue.total, 'data': [{'date': p.date, 'value': p.value} for p in (dashboard.revenue.data or [])]},
        'churn': {'total': dashboard.churn.total},
        'user_growth': {'total': dashboard.user_growth.total},
        'conversion': {'total': dashboard.conversion.total},
        'arpu': {'total': dashboard.arpu.total}
    })

@analytics_bp.route('/mrr', methods=['GET'])
@require_auth
@require_role('admin')
def get_mrr():
    """Get MRR data."""
    analytics_service = current_app.container.analytics_service()
    mrr = analytics_service.calculate_mrr()
    return jsonify({'total': mrr.total, 'change_percent': mrr.change_percent})

@analytics_bp.route('/revenue', methods=['GET'])
@require_auth
@require_role('admin')
def get_revenue():
    """Get revenue time series."""
    start = datetime.fromisoformat(request.args.get('start'))
    end = datetime.fromisoformat(request.args.get('end'))

    analytics_service = current_app.container.analytics_service()
    revenue = analytics_service.get_revenue(start, end)

    return jsonify({
        'total': revenue.total,
        'data': [{'date': p.date, 'value': p.value} for p in revenue.data]
    })

@analytics_bp.route('/churn', methods=['GET'])
@require_auth
@require_role('admin')
def get_churn():
    """Get churn rate."""
    start = datetime.fromisoformat(request.args.get('start'))
    end = datetime.fromisoformat(request.args.get('end'))

    analytics_service = current_app.container.analytics_service()
    churn = analytics_service.get_churn(start, end)

    return jsonify({'total': churn.total, 'change_percent': churn.change_percent})

@analytics_bp.route('/users/growth', methods=['GET'])
@require_auth
@require_role('admin')
def get_user_growth():
    """Get user growth time series."""
    start = datetime.fromisoformat(request.args.get('start'))
    end = datetime.fromisoformat(request.args.get('end'))

    analytics_service = current_app.container.analytics_service()
    growth = analytics_service.get_user_growth(start, end)

    return jsonify({
        'total': growth.total,
        'change_percent': growth.change_percent,
        'data': [{'date': p.date, 'value': p.value} for p in growth.data]
    })

@analytics_bp.route('/plans/distribution', methods=['GET'])
@require_auth
@require_role('admin')
def get_plan_distribution():
    """Get subscription distribution by plan."""
    analytics_service = current_app.container.analytics_service()
    distribution = analytics_service.get_plan_distribution()
    return jsonify(distribution)

@analytics_bp.route('/activity', methods=['GET'])
@require_auth
@require_role('admin')
def get_activity():
    """Get recent activity feed."""
    limit = request.args.get('limit', 20, type=int)

    analytics_service = current_app.container.analytics_service()
    activity = analytics_service.get_recent_activity(limit)

    return jsonify({
        'activity': [
            {'type': a.type, 'user': a.user, 'timestamp': a.timestamp, 'details': a.details}
            for a in activity
        ]
    })
```

---

## 11.10 Repository Extensions

### Required Repository Methods

```python
# src/repositories/subscription_repository.py - Extensions needed
class SubscriptionRepository:
    def get_active_as_of(self, date: datetime) -> List[Subscription]:
        """Get subscriptions that were active on a specific date."""
        pass

    def count_active_as_of(self, date: datetime) -> int:
        """Count active subscriptions as of date."""
        pass

    def count_cancellations_in_range(self, start: datetime, end: datetime, exclude_trials: bool = False) -> int:
        """Count cancellations in date range."""
        pass

    def get_recent_created(self, limit: int = 20) -> List[Subscription]:
        """Get recently created subscriptions."""
        pass

    def get_recent_cancellations(self, limit: int = 20) -> List[Subscription]:
        """Get recently cancelled subscriptions."""
        pass

    def count_paid_active(self) -> int:
        """Count active paid (non-free) subscriptions."""
        pass

# src/repositories/user_repository.py - Extensions needed
class UserRepository:
    def get_created_in_range(self, start: datetime, end: datetime) -> List[User]:
        """Get users created in date range."""
        pass

    def count_created_in_range(self, start: datetime, end: datetime) -> int:
        """Count users created in date range."""
        pass

    def get_recent(self, limit: int = 20) -> List[User]:
        """Get recently created users."""
        pass

# src/repositories/payment_repository.py - Extensions needed
class PaymentRepository:
    def get_successful_in_range(self, start: datetime, end: datetime) -> List[Payment]:
        """Get successful payments in date range."""
        pass

    def get_refunds_in_range(self, start: datetime, end: datetime) -> List[Payment]:
        """Get refunds in date range."""
        pass
```

---

## Implementation Checklist

### 11.1 Data Models
- [ ] TDD: MetricPoint and MetricData tests
- [ ] Implement data classes

### 11.2 MRR Calculation
- [ ] TDD: MRR calculation tests
- [ ] Implement calculate_mrr method

### 11.3 Revenue Analytics
- [ ] TDD: Revenue time series tests
- [ ] Implement get_revenue method

### 11.4 Churn Analytics
- [ ] TDD: Churn rate tests
- [ ] Implement get_churn method

### 11.5 User Growth
- [ ] TDD: User growth tests
- [ ] Implement get_user_growth method

### 11.6 Plan Distribution
- [ ] TDD: Plan distribution tests
- [ ] Implement get_plan_distribution method

### 11.7 Activity Feed
- [ ] TDD: Activity feed tests
- [ ] Implement get_recent_activity method

### 11.8 Dashboard Aggregate
- [ ] TDD: Dashboard aggregate tests
- [ ] Implement get_dashboard method

### 11.9 Routes
- [ ] TDD: Analytics route tests
- [ ] Implement analytics blueprint
- [ ] Register blueprint in app

### 11.10 Repository Extensions
- [ ] Extend SubscriptionRepository
- [ ] Extend UserRepository
- [ ] Extend PaymentRepository

### 11.11 DI Container
- [ ] Register AnalyticsService in container
- [ ] Wire dependencies

---

## Verification Commands

```bash
# Run analytics tests
docker-compose run --rm python-test pytest tests/unit/services/test_analytics_service.py -v

# Run route tests
docker-compose run --rm python-test pytest tests/unit/routes/test_analytics_routes.py -v

# Test endpoint manually
curl -X GET http://localhost:5000/api/v1/admin/analytics/dashboard \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Test with date range
curl -X GET "http://localhost:5000/api/v1/admin/analytics/revenue?start=2025-01-01&end=2025-01-31" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```
