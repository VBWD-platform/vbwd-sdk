# Sprint 8: Analytics Dashboard

**Priority:** LOW
**Duration:** 2-3 days
**Focus:** Analytics service and admin dashboard for business metrics

> **Core Requirements:** See [sprint-plan.md](./sprint-plan.md) for mandatory TDD-first, SOLID, DI, Clean Code, and No Over-Engineering requirements.

---

## 8.1 Backend Analytics Service

### Problem
No analytics or reporting capabilities.

### Requirements
- Time-series data aggregation
- Caching for expensive queries
- Export capabilities
- Historical comparisons

### TDD Tests First

**File:** `tests/unit/services/test_analytics_service.py`
```python
class TestAnalyticsService:
    def test_get_daily_revenue_returns_correct_totals(self):
        """Daily revenue calculated correctly."""
        pass

    def test_get_mrr_calculates_recurring_revenue(self):
        """MRR includes only active subscriptions."""
        pass

    def test_get_churn_rate_calculates_correctly(self):
        """Churn rate = cancelled / total * 100."""
        pass

    def test_get_user_growth_returns_signups(self):
        """User growth shows daily signups."""
        pass

    def test_results_are_cached(self):
        """Expensive queries are cached."""
        pass

    def test_cache_invalidates_on_new_data(self):
        """Cache invalidates when new data arrives."""
        pass
```

### Implementation

**File:** `src/services/analytics_service.py`
```python
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from src.extensions import redis_client
import json

@dataclass
class MetricPoint:
    date: datetime
    value: float

@dataclass
class AnalyticsResult:
    metric: str
    period: str
    data: List[MetricPoint]
    total: float
    change_percent: Optional[float] = None

class AnalyticsService:
    CACHE_TTL = 300  # 5 minutes

    def __init__(
        self,
        subscription_repo,
        payment_repo,
        user_repo,
        invoice_repo
    ):
        self.subscription_repo = subscription_repo
        self.payment_repo = payment_repo
        self.user_repo = user_repo
        self.invoice_repo = invoice_repo

    def get_mrr(self, as_of: datetime = None) -> AnalyticsResult:
        """Calculate Monthly Recurring Revenue."""
        as_of = as_of or datetime.utcnow()
        cache_key = f"analytics:mrr:{as_of.date()}"

        cached = redis_client.get(cache_key)
        if cached:
            return self._deserialize_result(cached)

        # Get all active subscriptions with their plan prices
        subscriptions = self.subscription_repo.get_active_subscriptions()

        mrr = 0.0
        for sub in subscriptions:
            if sub.tarif_plan.billing_period == 'monthly':
                mrr += sub.tarif_plan.price
            elif sub.tarif_plan.billing_period == 'yearly':
                mrr += sub.tarif_plan.price / 12

        # Compare to previous month
        prev_month = as_of - timedelta(days=30)
        prev_mrr = self._calculate_mrr_at_date(prev_month)
        change = ((mrr - prev_mrr) / prev_mrr * 100) if prev_mrr > 0 else 0

        result = AnalyticsResult(
            metric="mrr",
            period="monthly",
            data=[MetricPoint(date=as_of, value=mrr)],
            total=mrr,
            change_percent=round(change, 2)
        )

        redis_client.setex(cache_key, self.CACHE_TTL, self._serialize_result(result))
        return result

    def get_daily_revenue(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> AnalyticsResult:
        """Get daily revenue for a date range."""
        cache_key = f"analytics:daily_revenue:{start_date.date()}:{end_date.date()}"

        cached = redis_client.get(cache_key)
        if cached:
            return self._deserialize_result(cached)

        payments = self.payment_repo.get_payments_in_range(start_date, end_date)

        # Group by day
        daily_totals: Dict[str, float] = {}
        for payment in payments:
            day = payment.created_at.date().isoformat()
            daily_totals[day] = daily_totals.get(day, 0) + payment.amount

        data = [
            MetricPoint(date=datetime.fromisoformat(d), value=v)
            for d, v in sorted(daily_totals.items())
        ]

        total = sum(p.value for p in data)

        result = AnalyticsResult(
            metric="daily_revenue",
            period="daily",
            data=data,
            total=total
        )

        redis_client.setex(cache_key, self.CACHE_TTL, self._serialize_result(result))
        return result

    def get_churn_rate(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> AnalyticsResult:
        """Calculate churn rate for period."""
        # Starting subscribers
        start_subs = self.subscription_repo.count_active_at(start_date)

        # Cancelled during period
        cancelled = self.subscription_repo.count_cancelled_in_range(start_date, end_date)

        churn_rate = (cancelled / start_subs * 100) if start_subs > 0 else 0

        return AnalyticsResult(
            metric="churn_rate",
            period="custom",
            data=[MetricPoint(date=end_date, value=churn_rate)],
            total=churn_rate
        )

    def get_user_growth(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> AnalyticsResult:
        """Get user signup growth."""
        users = self.user_repo.get_signups_in_range(start_date, end_date)

        daily_signups: Dict[str, int] = {}
        for user in users:
            day = user.created_at.date().isoformat()
            daily_signups[day] = daily_signups.get(day, 0) + 1

        data = [
            MetricPoint(date=datetime.fromisoformat(d), value=v)
            for d, v in sorted(daily_signups.items())
        ]

        return AnalyticsResult(
            metric="user_growth",
            period="daily",
            data=data,
            total=sum(p.value for p in data)
        )

    def get_conversion_rate(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> AnalyticsResult:
        """Calculate free-to-paid conversion rate."""
        signups = self.user_repo.count_signups_in_range(start_date, end_date)
        conversions = self.subscription_repo.count_first_paid_in_range(start_date, end_date)

        rate = (conversions / signups * 100) if signups > 0 else 0

        return AnalyticsResult(
            metric="conversion_rate",
            period="custom",
            data=[MetricPoint(date=end_date, value=rate)],
            total=rate
        )

    def get_arpu(self, as_of: datetime = None) -> AnalyticsResult:
        """Calculate Average Revenue Per User."""
        as_of = as_of or datetime.utcnow()
        month_start = as_of.replace(day=1, hour=0, minute=0, second=0)

        revenue = self.payment_repo.get_total_revenue_in_range(month_start, as_of)
        active_users = self.subscription_repo.count_active_at(as_of)

        arpu = revenue / active_users if active_users > 0 else 0

        return AnalyticsResult(
            metric="arpu",
            period="monthly",
            data=[MetricPoint(date=as_of, value=arpu)],
            total=arpu
        )

    def get_dashboard_summary(self) -> Dict:
        """Get all key metrics for dashboard."""
        now = datetime.utcnow()
        month_start = now.replace(day=1)
        prev_month_start = (month_start - timedelta(days=1)).replace(day=1)

        return {
            "mrr": self.get_mrr(now).__dict__,
            "revenue": self.get_daily_revenue(month_start, now).__dict__,
            "churn": self.get_churn_rate(month_start, now).__dict__,
            "user_growth": self.get_user_growth(month_start, now).__dict__,
            "conversion": self.get_conversion_rate(month_start, now).__dict__,
            "arpu": self.get_arpu(now).__dict__,
        }

    def _serialize_result(self, result: AnalyticsResult) -> str:
        return json.dumps({
            "metric": result.metric,
            "period": result.period,
            "data": [{"date": p.date.isoformat(), "value": p.value} for p in result.data],
            "total": result.total,
            "change_percent": result.change_percent
        })

    def _deserialize_result(self, data: str) -> AnalyticsResult:
        obj = json.loads(data)
        return AnalyticsResult(
            metric=obj["metric"],
            period=obj["period"],
            data=[MetricPoint(date=datetime.fromisoformat(p["date"]), value=p["value"]) for p in obj["data"]],
            total=obj["total"],
            change_percent=obj.get("change_percent")
        )
```

**File:** `src/routes/admin/analytics.py`
```python
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from src.decorators.permissions import require_permission
from datetime import datetime, timedelta

analytics_bp = Blueprint("analytics", __name__)

@analytics_bp.route("/dashboard", methods=["GET"])
@jwt_required()
@require_permission("view_analytics")
def get_dashboard():
    service: AnalyticsService = current_app.container.analytics_service()
    summary = service.get_dashboard_summary()
    return jsonify(summary)

@analytics_bp.route("/mrr", methods=["GET"])
@jwt_required()
@require_permission("view_analytics")
def get_mrr():
    service: AnalyticsService = current_app.container.analytics_service()
    result = service.get_mrr()
    return jsonify(result.__dict__)

@analytics_bp.route("/revenue", methods=["GET"])
@jwt_required()
@require_permission("view_analytics")
def get_revenue():
    start = request.args.get("start", (datetime.utcnow() - timedelta(days=30)).isoformat())
    end = request.args.get("end", datetime.utcnow().isoformat())

    service: AnalyticsService = current_app.container.analytics_service()
    result = service.get_daily_revenue(
        datetime.fromisoformat(start),
        datetime.fromisoformat(end)
    )
    return jsonify(result.__dict__)

@analytics_bp.route("/churn", methods=["GET"])
@jwt_required()
@require_permission("view_analytics")
def get_churn():
    start = request.args.get("start", (datetime.utcnow() - timedelta(days=30)).isoformat())
    end = request.args.get("end", datetime.utcnow().isoformat())

    service: AnalyticsService = current_app.container.analytics_service()
    result = service.get_churn_rate(
        datetime.fromisoformat(start),
        datetime.fromisoformat(end)
    )
    return jsonify(result.__dict__)

@analytics_bp.route("/users/growth", methods=["GET"])
@jwt_required()
@require_permission("view_analytics")
def get_user_growth():
    start = request.args.get("start", (datetime.utcnow() - timedelta(days=30)).isoformat())
    end = request.args.get("end", datetime.utcnow().isoformat())

    service: AnalyticsService = current_app.container.analytics_service()
    result = service.get_user_growth(
        datetime.fromisoformat(start),
        datetime.fromisoformat(end)
    )
    return jsonify(result.__dict__)

@analytics_bp.route("/export", methods=["GET"])
@jwt_required()
@require_permission("export_analytics")
def export_analytics():
    format = request.args.get("format", "csv")
    metrics = request.args.getlist("metrics")
    start = request.args.get("start")
    end = request.args.get("end")

    service: AnalyticsService = current_app.container.analytics_service()
    export_data = service.export_metrics(metrics, start, end, format)

    if format == "csv":
        return Response(
            export_data,
            mimetype="text/csv",
            headers={"Content-Disposition": "attachment;filename=analytics.csv"}
        )
    return jsonify(export_data)
```

---

## 8.2 MRR & Revenue Metrics

### Requirements
- MRR calculation
- ARR (Annual Recurring Revenue)
- Revenue breakdown by plan
- Revenue trends

### Implementation Details

The MRR calculation considers:
- Monthly subscriptions: full price
- Annual subscriptions: price / 12
- Discounts: subtract from MRR
- Trials: not included

**Revenue Breakdown Query:**
```python
def get_revenue_by_plan(self, start_date, end_date) -> Dict[str, float]:
    """Get revenue breakdown by plan."""
    payments = self.payment_repo.get_payments_in_range(start_date, end_date)

    by_plan: Dict[str, float] = {}
    for payment in payments:
        plan_name = payment.subscription.tarif_plan.name if payment.subscription else "One-time"
        by_plan[plan_name] = by_plan.get(plan_name, 0) + payment.amount

    return by_plan
```

---

## 8.3 User & Churn Metrics

### Requirements
- User signup trends
- Active user count
- Churn rate calculation
- Cohort analysis (optional)
- User retention curves

### Implementation Details

**Churn Types:**
- Voluntary churn: User cancelled
- Involuntary churn: Payment failed
- Delinquent: Past due but not cancelled

**Cohort Analysis (Optional):**
```python
def get_cohort_retention(self, cohort_month: datetime) -> List[Dict]:
    """Calculate retention for a signup cohort."""
    # Users who signed up in cohort_month
    cohort_users = self.user_repo.get_signups_in_month(cohort_month)
    cohort_size = len(cohort_users)
    cohort_user_ids = [u.id for u in cohort_users]

    retention = []
    current = cohort_month
    while current < datetime.utcnow():
        active = self.subscription_repo.count_active_for_users(
            cohort_user_ids, current
        )
        retention.append({
            "month": current.isoformat(),
            "months_since_signup": (current.year - cohort_month.year) * 12 + current.month - cohort_month.month,
            "retained": active,
            "rate": round(active / cohort_size * 100, 2) if cohort_size > 0 else 0
        })
        current = (current + timedelta(days=32)).replace(day=1)

    return retention
```

---

## 8.4 Dashboard UI

### Requirements
- Overview cards (MRR, users, churn)
- Revenue chart
- User growth chart
- Plan distribution
- Recent activity feed

### Frontend Implementation

**File:** `vbwd-frontend/admin/vue/src/views/Dashboard.vue`
```vue
<template>
  <div class="dashboard">
    <h1>Dashboard</h1>

    <div class="metrics-grid">
      <MetricCard
        title="MRR"
        :value="formatCurrency(metrics.mrr?.total)"
        :change="metrics.mrr?.change_percent"
        icon="💰"
      />
      <MetricCard
        title="Active Users"
        :value="metrics.activeUsers"
        :change="metrics.userGrowthPercent"
        icon="👥"
      />
      <MetricCard
        title="Churn Rate"
        :value="`${metrics.churn?.total?.toFixed(1)}%`"
        :change="metrics.churnChange"
        invertChange
        icon="📉"
      />
      <MetricCard
        title="ARPU"
        :value="formatCurrency(metrics.arpu?.total)"
        icon="📊"
      />
    </div>

    <div class="charts-row">
      <Card class="chart-card">
        <template #header>
          <h2>Revenue</h2>
          <DateRangePicker v-model="dateRange" @change="fetchData" />
        </template>
        <LineChart :data="revenueChartData" />
      </Card>

      <Card class="chart-card">
        <template #header>
          <h2>User Growth</h2>
        </template>
        <BarChart :data="userGrowthChartData" />
      </Card>
    </div>

    <div class="charts-row">
      <Card class="chart-card">
        <template #header>
          <h2>Subscriptions by Plan</h2>
        </template>
        <PieChart :data="planDistributionData" />
      </Card>

      <Card class="chart-card">
        <template #header>
          <h2>Recent Activity</h2>
        </template>
        <ActivityFeed :items="recentActivity" />
      </Card>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { useAnalyticsStore } from '../stores/analytics';
import { Card, DateRangePicker } from '@vbwd/core-sdk';
import MetricCard from '../components/dashboard/MetricCard.vue';
import LineChart from '../components/charts/LineChart.vue';
import BarChart from '../components/charts/BarChart.vue';
import PieChart from '../components/charts/PieChart.vue';
import ActivityFeed from '../components/dashboard/ActivityFeed.vue';

const store = useAnalyticsStore();

const metrics = computed(() => store.dashboard);
const dateRange = ref({ start: null, end: null });
const recentActivity = ref([]);

const revenueChartData = computed(() => ({
  labels: metrics.value.revenue?.data?.map(d => formatDate(d.date)) || [],
  datasets: [{
    label: 'Revenue',
    data: metrics.value.revenue?.data?.map(d => d.value) || [],
    borderColor: '#3b82f6',
    fill: true,
    backgroundColor: 'rgba(59, 130, 246, 0.1)',
  }]
}));

const userGrowthChartData = computed(() => ({
  labels: metrics.value.user_growth?.data?.map(d => formatDate(d.date)) || [],
  datasets: [{
    label: 'New Users',
    data: metrics.value.user_growth?.data?.map(d => d.value) || [],
    backgroundColor: '#10b981',
  }]
}));

const planDistributionData = computed(() => ({
  labels: Object.keys(store.planDistribution || {}),
  datasets: [{
    data: Object.values(store.planDistribution || {}),
    backgroundColor: ['#3b82f6', '#10b981', '#f59e0b', '#ef4444'],
  }]
}));

onMounted(() => {
  fetchData();
  fetchActivity();
});

async function fetchData() {
  await store.fetchDashboard(dateRange.value);
  await store.fetchPlanDistribution();
}

async function fetchActivity() {
  recentActivity.value = await store.fetchRecentActivity();
}

function formatCurrency(value: number) {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(value || 0);
}

function formatDate(date: string) {
  return new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}
</script>

<style scoped>
.dashboard {
  padding: 1.5rem;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.charts-row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
  gap: 1.5rem;
  margin-bottom: 1.5rem;
}

.chart-card {
  min-height: 300px;
}
</style>
```

**File:** `vbwd-frontend/admin/vue/src/components/dashboard/MetricCard.vue`
```vue
<template>
  <Card class="metric-card">
    <div class="metric-icon">{{ icon }}</div>
    <div class="metric-content">
      <p class="metric-title">{{ title }}</p>
      <p class="metric-value">{{ value }}</p>
      <p v-if="change !== undefined" :class="['metric-change', changeClass]">
        <span>{{ changeIcon }}</span>
        {{ Math.abs(change) }}%
        <span class="period">vs last month</span>
      </p>
    </div>
  </Card>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { Card } from '@vbwd/core-sdk';

const props = defineProps<{
  title: string;
  value: string | number;
  change?: number;
  icon?: string;
  invertChange?: boolean;
}>();

const isPositive = computed(() => {
  const positive = props.change > 0;
  return props.invertChange ? !positive : positive;
});

const changeClass = computed(() => isPositive.value ? 'positive' : 'negative');
const changeIcon = computed(() => props.change > 0 ? '↑' : '↓');
</script>

<style scoped>
.metric-card {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
}

.metric-icon {
  font-size: 2rem;
}

.metric-title {
  font-size: 0.875rem;
  color: var(--color-text-muted);
  margin: 0;
}

.metric-value {
  font-size: 1.5rem;
  font-weight: 700;
  margin: 0.25rem 0;
}

.metric-change {
  font-size: 0.75rem;
  margin: 0;
}

.metric-change.positive {
  color: var(--color-success);
}

.metric-change.negative {
  color: var(--color-danger);
}

.period {
  color: var(--color-text-muted);
}
</style>
```

---

## Chart Library Integration

**Install Chart.js:**
```bash
cd vbwd-frontend/admin/vue
npm install chart.js vue-chartjs
```

**File:** `vbwd-frontend/admin/vue/src/components/charts/LineChart.vue`
```vue
<template>
  <Line :data="data" :options="options" />
</template>

<script setup lang="ts">
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

defineProps<{
  data: any;
}>();

const options = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: false },
  },
  scales: {
    y: { beginAtZero: true },
  },
};
</script>
```

---

## Checklist

### 8.1 Backend Analytics
- [ ] Tests for AnalyticsService
- [ ] AnalyticsService implemented
- [ ] Redis caching working
- [ ] Analytics routes created
- [ ] Export functionality
- [ ] All tests pass

### 8.2 MRR & Revenue
- [ ] MRR calculation correct
- [ ] Revenue by plan
- [ ] Revenue trends
- [ ] ARR calculation

### 8.3 User & Churn
- [ ] User growth metrics
- [ ] Churn rate calculation
- [ ] Active user count
- [ ] Cohort analysis (optional)

### 8.4 Dashboard UI
- [ ] MetricCard component
- [ ] LineChart component
- [ ] BarChart component
- [ ] PieChart component
- [ ] ActivityFeed component
- [ ] Dashboard.vue complete
- [ ] DateRangePicker working
- [ ] Charts display correctly

---

## Verification Commands

```bash
# Run analytics tests
docker-compose --profile test run --rm test pytest tests/unit/services/test_analytics_service.py -v

# Test dashboard API
curl http://localhost:5000/api/v1/admin/analytics/dashboard -H "Authorization: Bearer $ADMIN_TOKEN"

# Test admin frontend
cd vbwd-frontend/admin/vue
npm run dev
```
