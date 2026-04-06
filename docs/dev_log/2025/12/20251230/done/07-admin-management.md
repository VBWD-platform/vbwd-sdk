# Sprint 7: Admin Management

**Priority:** MEDIUM
**Duration:** 2-3 days
**Focus:** Admin UI for managing users, plans, subscriptions, and invoices

> **Core Requirements:** See [sprint-plan.md](./sprint-plan.md) for mandatory TDD-first, SOLID, DI, Clean Code, and No Over-Engineering requirements.

---

## 7.1 User Management UI

### Problem
No admin interface for user management.

### Requirements
- List all users with search/filter
- View user details
- Edit user information
- Suspend/activate users
- Assign roles
- Impersonate user (for debugging)

### Backend Implementation

**File:** `src/routes/admin/users.py`
```python
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from src.decorators.permissions import require_permission

admin_users_bp = Blueprint("admin_users", __name__)

@admin_users_bp.route("/", methods=["GET"])
@jwt_required()
@require_permission("view_users")
def list_users():
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)
    search = request.args.get("search", "")
    status = request.args.get("status", "")

    service: UserAdminService = current_app.container.user_admin_service()
    result = service.list_users(page, per_page, search, status)

    return jsonify({
        "users": [
            {
                "id": str(u.id),
                "email": u.email,
                "name": u.name,
                "is_active": u.is_active,
                "roles": [r.name for r in u.roles],
                "subscription_plan": u.active_subscription.tarif_plan.name if u.active_subscription else None,
                "created_at": u.created_at.isoformat()
            }
            for u in result.items
        ],
        "total": result.total,
        "page": page,
        "per_page": per_page
    })

@admin_users_bp.route("/<user_id>", methods=["GET"])
@jwt_required()
@require_permission("view_users")
def get_user(user_id):
    service: UserAdminService = current_app.container.user_admin_service()
    user = service.get_user(user_id)

    if not user:
        return jsonify({"error": "User not found"}), 404

    return jsonify({
        "user": {
            "id": str(user.id),
            "email": user.email,
            "name": user.name,
            "is_active": user.is_active,
            "roles": [r.name for r in user.roles],
            "created_at": user.created_at.isoformat(),
            "subscription": {
                "plan": user.active_subscription.tarif_plan.name if user.active_subscription else None,
                "status": user.active_subscription.status.value if user.active_subscription else None,
                "expires_at": user.active_subscription.end_date.isoformat() if user.active_subscription and user.active_subscription.end_date else None
            },
            "stats": {
                "total_payments": service.get_user_total_payments(user_id),
                "last_login": user.last_login.isoformat() if user.last_login else None
            }
        }
    })

@admin_users_bp.route("/<user_id>", methods=["PUT"])
@jwt_required()
@require_permission("edit_users")
def update_user(user_id):
    data = request.get_json()
    service: UserAdminService = current_app.container.user_admin_service()
    result = service.update_user(user_id, data)

    if result.success:
        return jsonify({"message": "User updated"})
    return jsonify({"error": result.error}), 400

@admin_users_bp.route("/<user_id>/suspend", methods=["POST"])
@jwt_required()
@require_permission("edit_users")
def suspend_user(user_id):
    data = request.get_json()
    reason = data.get("reason", "")

    service: UserAdminService = current_app.container.user_admin_service()
    result = service.suspend_user(user_id, reason)

    if result.success:
        return jsonify({"message": "User suspended"})
    return jsonify({"error": result.error}), 400

@admin_users_bp.route("/<user_id>/activate", methods=["POST"])
@jwt_required()
@require_permission("edit_users")
def activate_user(user_id):
    service: UserAdminService = current_app.container.user_admin_service()
    result = service.activate_user(user_id)

    if result.success:
        return jsonify({"message": "User activated"})
    return jsonify({"error": result.error}), 400

@admin_users_bp.route("/<user_id>/roles", methods=["PUT"])
@jwt_required()
@require_permission("manage_roles")
def update_user_roles(user_id):
    data = request.get_json()
    roles = data.get("roles", [])

    service: UserAdminService = current_app.container.user_admin_service()
    result = service.update_user_roles(user_id, roles)

    if result.success:
        return jsonify({"message": "Roles updated"})
    return jsonify({"error": result.error}), 400

@admin_users_bp.route("/<user_id>/impersonate", methods=["POST"])
@jwt_required()
@require_permission("impersonate_users")
def impersonate_user(user_id):
    admin_id = get_jwt_identity()
    service: UserAdminService = current_app.container.user_admin_service()
    result = service.create_impersonation_token(admin_id, user_id)

    if result.success:
        return jsonify({"token": result.token, "expires_in": 3600})
    return jsonify({"error": result.error}), 400
```

### Frontend Implementation

**File:** `vbwd-frontend/admin/vue/src/views/users/UserList.vue`
```vue
<template>
  <div class="users-page">
    <div class="page-header">
      <h1>Users</h1>
      <div class="actions">
        <Input
          v-model="search"
          placeholder="Search users..."
          @input="debouncedSearch"
        >
          <template #prefix>🔍</template>
        </Input>
        <Dropdown v-model="statusFilter" :options="statusOptions" placeholder="All statuses" />
      </div>
    </div>

    <Card>
      <Table :columns="columns" :data="users" :loading="loading" @row-click="viewUser">
        <template #cell-status="{ row }">
          <Badge :variant="row.is_active ? 'success' : 'danger'">
            {{ row.is_active ? 'Active' : 'Suspended' }}
          </Badge>
        </template>
        <template #cell-roles="{ row }">
          <Badge v-for="role in row.roles" :key="role" variant="info" class="mr-1">
            {{ role }}
          </Badge>
        </template>
        <template #cell-actions="{ row }">
          <Dropdown placement="bottom-end">
            <template #trigger>
              <Button variant="ghost" size="sm">⋮</Button>
            </template>
            <template #menu>
              <a @click="viewUser(row)">View Details</a>
              <a @click="editUser(row)">Edit</a>
              <a v-if="row.is_active" @click="suspendUser(row)">Suspend</a>
              <a v-else @click="activateUser(row)">Activate</a>
              <a @click="impersonate(row)">Impersonate</a>
            </template>
          </Dropdown>
        </template>
      </Table>

      <Pagination
        v-model:page="page"
        :total="total"
        :per-page="perPage"
        @change="fetchUsers"
      />
    </Card>

    <Modal v-model="showSuspendModal" title="Suspend User">
      <p>Suspending: {{ selectedUser?.email }}</p>
      <FormField label="Reason">
        <Input v-model="suspendReason" placeholder="Reason for suspension" />
      </FormField>
      <template #footer>
        <Button variant="ghost" @click="showSuspendModal = false">Cancel</Button>
        <Button variant="danger" @click="confirmSuspend" :loading="suspending">
          Suspend User
        </Button>
      </template>
    </Modal>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useUserAdminStore } from '../../stores/userAdmin';
import { Card, Table, Badge, Button, Input, Dropdown, Pagination, Modal, FormField } from '@vbwd/core-sdk';
import { debounce } from 'lodash-es';

const router = useRouter();
const store = useUserAdminStore();

const users = ref([]);
const loading = ref(false);
const page = ref(1);
const perPage = ref(20);
const total = ref(0);
const search = ref('');
const statusFilter = ref('');

const showSuspendModal = ref(false);
const selectedUser = ref(null);
const suspendReason = ref('');
const suspending = ref(false);

const columns = [
  { key: 'email', label: 'Email' },
  { key: 'name', label: 'Name' },
  { key: 'status', label: 'Status' },
  { key: 'roles', label: 'Roles' },
  { key: 'subscription_plan', label: 'Plan' },
  { key: 'created_at', label: 'Created', format: 'date' },
  { key: 'actions', label: '' },
];

const statusOptions = [
  { value: '', label: 'All' },
  { value: 'active', label: 'Active' },
  { value: 'suspended', label: 'Suspended' },
];

const debouncedSearch = debounce(() => {
  page.value = 1;
  fetchUsers();
}, 300);

onMounted(() => fetchUsers());

async function fetchUsers() {
  loading.value = true;
  try {
    const result = await store.fetchUsers({
      page: page.value,
      per_page: perPage.value,
      search: search.value,
      status: statusFilter.value,
    });
    users.value = result.users;
    total.value = result.total;
  } finally {
    loading.value = false;
  }
}

function viewUser(user) {
  router.push(`/users/${user.id}`);
}

function editUser(user) {
  router.push(`/users/${user.id}/edit`);
}

function suspendUser(user) {
  selectedUser.value = user;
  suspendReason.value = '';
  showSuspendModal.value = true;
}

async function confirmSuspend() {
  suspending.value = true;
  try {
    await store.suspendUser(selectedUser.value.id, suspendReason.value);
    showSuspendModal.value = false;
    fetchUsers();
  } finally {
    suspending.value = false;
  }
}

async function activateUser(user) {
  await store.activateUser(user.id);
  fetchUsers();
}

async function impersonate(user) {
  const result = await store.impersonateUser(user.id);
  // Store impersonation token and redirect
  window.open(`/impersonate?token=${result.token}`, '_blank');
}
</script>
```

---

## 7.2 Plan Management UI

### Requirements
- List all plans
- Create new plans
- Edit existing plans
- Archive plans
- Feature/limit configuration

### Backend Implementation

**File:** `src/routes/admin/plans.py`
```python
admin_plans_bp = Blueprint("admin_plans", __name__)

@admin_plans_bp.route("/", methods=["GET"])
@jwt_required()
@require_permission("view_plans")
def list_plans():
    service: PlanAdminService = current_app.container.plan_admin_service()
    plans = service.list_all_plans(include_archived=request.args.get("include_archived", False))

    return jsonify({
        "plans": [
            {
                "id": str(p.id),
                "name": p.name,
                "price": p.price,
                "currency": p.currency,
                "billing_period": p.billing_period,
                "features": p.features,
                "limits": p.limits,
                "is_active": p.is_active,
                "subscriber_count": service.get_subscriber_count(p.id),
                "created_at": p.created_at.isoformat()
            }
            for p in plans
        ]
    })

@admin_plans_bp.route("/", methods=["POST"])
@jwt_required()
@require_permission("manage_plans")
def create_plan():
    data = request.get_json()
    service: PlanAdminService = current_app.container.plan_admin_service()
    result = service.create_plan(data)

    if result.success:
        return jsonify({"plan_id": str(result.plan.id)}), 201
    return jsonify({"error": result.error}), 400

@admin_plans_bp.route("/<plan_id>", methods=["PUT"])
@jwt_required()
@require_permission("manage_plans")
def update_plan(plan_id):
    data = request.get_json()
    service: PlanAdminService = current_app.container.plan_admin_service()
    result = service.update_plan(plan_id, data)

    if result.success:
        return jsonify({"message": "Plan updated"})
    return jsonify({"error": result.error}), 400

@admin_plans_bp.route("/<plan_id>/archive", methods=["POST"])
@jwt_required()
@require_permission("manage_plans")
def archive_plan(plan_id):
    service: PlanAdminService = current_app.container.plan_admin_service()
    result = service.archive_plan(plan_id)

    if result.success:
        return jsonify({"message": "Plan archived"})
    return jsonify({"error": result.error}), 400
```

### Frontend Implementation

**File:** `vbwd-frontend/admin/vue/src/views/plans/PlanList.vue`
```vue
<template>
  <div class="plans-page">
    <div class="page-header">
      <h1>Plans</h1>
      <Button @click="showCreateModal = true">Create Plan</Button>
    </div>

    <div class="plans-grid">
      <Card v-for="plan in plans" :key="plan.id" :class="{ 'archived': !plan.is_active }">
        <template #header>
          <div class="plan-header">
            <h2>{{ plan.name }}</h2>
            <Badge v-if="!plan.is_active" variant="warning">Archived</Badge>
          </div>
          <p class="price">${{ plan.price }}/{{ plan.billing_period }}</p>
        </template>

        <div class="plan-stats">
          <p><strong>{{ plan.subscriber_count }}</strong> subscribers</p>
        </div>

        <div class="plan-features">
          <h4>Features</h4>
          <ul>
            <li v-for="feature in plan.features" :key="feature">{{ feature }}</li>
          </ul>
        </div>

        <div class="plan-limits" v-if="Object.keys(plan.limits).length">
          <h4>Limits</h4>
          <ul>
            <li v-for="(value, key) in plan.limits" :key="key">
              {{ key }}: {{ value }}
            </li>
          </ul>
        </div>

        <template #footer>
          <Button variant="ghost" @click="editPlan(plan)">Edit</Button>
          <Button
            v-if="plan.is_active"
            variant="ghost"
            @click="archivePlan(plan)"
          >
            Archive
          </Button>
        </template>
      </Card>
    </div>

    <Modal v-model="showCreateModal" title="Create Plan" size="lg">
      <PlanForm @submit="createPlan" @cancel="showCreateModal = false" />
    </Modal>

    <Modal v-model="showEditModal" title="Edit Plan" size="lg">
      <PlanForm
        :plan="selectedPlan"
        @submit="updatePlan"
        @cancel="showEditModal = false"
      />
    </Modal>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { usePlanAdminStore } from '../../stores/planAdmin';
import { Card, Badge, Button, Modal } from '@vbwd/core-sdk';
import PlanForm from '../../components/plans/PlanForm.vue';

const store = usePlanAdminStore();

const plans = ref([]);
const showCreateModal = ref(false);
const showEditModal = ref(false);
const selectedPlan = ref(null);

onMounted(() => fetchPlans());

async function fetchPlans() {
  plans.value = await store.fetchPlans();
}

function editPlan(plan) {
  selectedPlan.value = plan;
  showEditModal.value = true;
}

async function createPlan(data) {
  await store.createPlan(data);
  showCreateModal.value = false;
  fetchPlans();
}

async function updatePlan(data) {
  await store.updatePlan(selectedPlan.value.id, data);
  showEditModal.value = false;
  fetchPlans();
}

async function archivePlan(plan) {
  if (confirm(`Archive "${plan.name}"? Existing subscribers will keep their plan.`)) {
    await store.archivePlan(plan.id);
    fetchPlans();
  }
}
</script>
```

---

## 7.3 Subscription Management UI

### Requirements
- List all subscriptions
- Filter by status/plan
- Manual subscription management
- Extend/cancel subscriptions
- Apply credits/discounts

### Frontend Implementation

**File:** `vbwd-frontend/admin/vue/src/views/subscriptions/SubscriptionList.vue`
```vue
<template>
  <div class="subscriptions-page">
    <div class="page-header">
      <h1>Subscriptions</h1>
      <div class="filters">
        <Dropdown v-model="statusFilter" :options="statusOptions" placeholder="All statuses" />
        <Dropdown v-model="planFilter" :options="planOptions" placeholder="All plans" />
      </div>
    </div>

    <Card>
      <Table :columns="columns" :data="subscriptions" :loading="loading">
        <template #cell-user="{ row }">
          <a @click="viewUser(row.user_id)">{{ row.user_email }}</a>
        </template>
        <template #cell-status="{ row }">
          <Badge :variant="getStatusVariant(row.status)">{{ row.status }}</Badge>
        </template>
        <template #cell-actions="{ row }">
          <Dropdown placement="bottom-end">
            <template #trigger>
              <Button variant="ghost" size="sm">⋮</Button>
            </template>
            <template #menu>
              <a @click="viewDetails(row)">View Details</a>
              <a @click="extendSubscription(row)">Extend</a>
              <a @click="cancelSubscription(row)" v-if="row.status === 'active'">Cancel</a>
              <a @click="applyCredit(row)">Apply Credit</a>
            </template>
          </Dropdown>
        </template>
      </Table>

      <Pagination
        v-model:page="page"
        :total="total"
        :per-page="perPage"
        @change="fetchSubscriptions"
      />
    </Card>
  </div>
</template>
```

---

## 7.4 Invoice Management UI

### Requirements
- List all invoices
- Filter by status/date
- Manual invoice actions
- Refund processing
- Send invoice reminders

### Frontend Implementation

**File:** `vbwd-frontend/admin/vue/src/views/invoices/InvoiceList.vue`
```vue
<template>
  <div class="invoices-page">
    <div class="page-header">
      <h1>Invoices</h1>
      <div class="filters">
        <DateRangePicker v-model="dateRange" />
        <Dropdown v-model="statusFilter" :options="statusOptions" />
      </div>
    </div>

    <Card>
      <div class="invoice-stats">
        <div class="stat">
          <span class="label">Total Revenue</span>
          <span class="value">${{ stats.totalRevenue }}</span>
        </div>
        <div class="stat">
          <span class="label">Paid</span>
          <span class="value">{{ stats.paidCount }}</span>
        </div>
        <div class="stat">
          <span class="label">Pending</span>
          <span class="value">{{ stats.pendingCount }}</span>
        </div>
        <div class="stat">
          <span class="label">Overdue</span>
          <span class="value text-danger">{{ stats.overdueCount }}</span>
        </div>
      </div>

      <Table :columns="columns" :data="invoices" :loading="loading">
        <template #cell-status="{ row }">
          <Badge :variant="getStatusVariant(row.status)">{{ row.status }}</Badge>
        </template>
        <template #cell-actions="{ row }">
          <Dropdown placement="bottom-end">
            <template #trigger>
              <Button variant="ghost" size="sm">⋮</Button>
            </template>
            <template #menu>
              <a @click="viewInvoice(row)">View</a>
              <a @click="downloadPdf(row)">Download PDF</a>
              <a @click="sendReminder(row)" v-if="row.status === 'pending'">Send Reminder</a>
              <a @click="markPaid(row)" v-if="row.status === 'pending'">Mark as Paid</a>
              <a @click="issueRefund(row)" v-if="row.status === 'paid'">Issue Refund</a>
            </template>
          </Dropdown>
        </template>
      </Table>

      <Pagination
        v-model:page="page"
        :total="total"
        :per-page="perPage"
        @change="fetchInvoices"
      />
    </Card>
  </div>
</template>
```

---

## Checklist

### 7.1 User Management
- [ ] User list endpoint
- [ ] User detail endpoint
- [ ] Suspend/activate endpoints
- [ ] Role assignment endpoint
- [ ] Impersonation endpoint
- [ ] UserList.vue component
- [ ] UserDetail.vue component
- [ ] UserEdit.vue component
- [ ] All tests pass

### 7.2 Plan Management
- [ ] Plan CRUD endpoints
- [ ] Archive endpoint
- [ ] PlanList.vue component
- [ ] PlanForm.vue component
- [ ] Feature/limit editor
- [ ] All tests pass

### 7.3 Subscription Management
- [ ] Subscription list endpoint
- [ ] Extend endpoint
- [ ] Cancel endpoint
- [ ] Credit endpoint
- [ ] SubscriptionList.vue
- [ ] All tests pass

### 7.4 Invoice Management
- [ ] Invoice list endpoint
- [ ] Stats endpoint
- [ ] Refund endpoint
- [ ] Reminder endpoint
- [ ] InvoiceList.vue
- [ ] All tests pass

---

## Verification Commands

```bash
# Run admin tests
docker-compose --profile test run --rm test pytest tests/unit/routes/admin/ -v

# Test admin frontend
cd vbwd-frontend/admin/vue
npm run dev

# Check admin routes
curl http://localhost:5000/api/v1/admin/users -H "Authorization: Bearer $ADMIN_TOKEN"
```
