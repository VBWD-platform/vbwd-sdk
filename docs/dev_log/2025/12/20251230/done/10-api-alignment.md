# Sprint 10: Backend-Frontend API Alignment

**Priority:** CRITICAL (Blocker for Integration Testing)
**Duration:** 1-2 days
**Focus:** Align frontend stores with existing backend API patterns

> **Core Requirements:** TDD-first, SOLID, DI, Clean Code

---

## Approach

**Frontend adapts to backend** - The backend API uses `/api/v1/` prefix and specific endpoint names. Frontend stores must be updated to match.

---

## 10.1 Environment Configuration

### Current State
- Frontend stores use: `baseURL: import.meta.env.VITE_API_URL || '/api'`
- Backend uses: `/api/v1/` prefix

### Required Change
Set `VITE_API_URL=/api/v1` in all frontend environments.

**Files to update:**
- `vbwd-frontend/docker-compose.yaml` - Update env vars
- `vbwd-frontend/user/.env` - Create/update
- `vbwd-frontend/admin/vue/.env` - Create/update

```yaml
# docker-compose.yaml
environment:
  - VITE_API_URL=/api/v1
```

---

## 10.2 Plans Store URL Correction

### Current State
| Store | Current Path | Backend Path | Action |
|-------|-------------|--------------|--------|
| `plans.ts` | `/plans` | `/tarif-plans` | **FIX** |
| `plans.ts` | `/plans/subscribe` | `/tarif-plans/subscribe` | **FIX** |
| `planAdmin.ts` | `/admin/plans` | `/admin/tarif-plans` | **FIX** |
| `planAdmin.ts` | `/admin/plans/{id}` | `/admin/tarif-plans/{id}` | **FIX** |
| `planAdmin.ts` | `/admin/plans/{id}/archive` | `/admin/tarif-plans/{id}/archive` | **FIX** |
| `planAdmin.ts` | `/admin/plans/{id}/subscribers/count` | `/admin/tarif-plans/{id}/subscribers/count` | **FIX** |

### TDD Test Updates

**User plans.spec.ts:**
```typescript
// tests/unit/stores/plans.spec.ts
it('fetches plans from /tarif-plans', async () => {
  const { usePlansStore, api } = await import('../../../src/stores/plans');
  const store = usePlansStore();

  api.get = vi.fn().mockResolvedValue({ plans: [] });

  await store.fetchPlans();

  expect(api.get).toHaveBeenCalledWith('/tarif-plans');
});

it('subscribes via /tarif-plans/subscribe', async () => {
  const { usePlansStore, api } = await import('../../../src/stores/plans');
  const store = usePlansStore();

  api.post = vi.fn().mockResolvedValue({ subscriptionId: '123' });

  await store.subscribe('plan-1');

  expect(api.post).toHaveBeenCalledWith('/tarif-plans/subscribe', { planId: 'plan-1' });
});
```

**Admin planAdmin.spec.ts:**
```typescript
// tests/unit/stores/planAdmin.spec.ts
it('fetches plans from /admin/tarif-plans', async () => {
  const { usePlanAdminStore, api } = await import('../../../src/stores/planAdmin');
  const store = usePlanAdminStore();

  api.get = vi.fn().mockResolvedValue({ plans: [] });

  await store.fetchPlans();

  expect(api.get).toHaveBeenCalledWith('/admin/tarif-plans', expect.any(Object));
});
```

### Implementation Changes

**user/vue/src/stores/plans.ts:**
```typescript
// Change line 31
const response = await api.get('/tarif-plans') as { plans: Plan[] };

// Change line 55
const response = await api.post('/tarif-plans/subscribe', { planId });
```

**admin/vue/src/stores/planAdmin.ts:**
```typescript
// Change line 44
const response = await api.get('/admin/tarif-plans', {

// Change line 63
const response = await api.post('/admin/tarif-plans', data);

// Change line 78
const response = await api.put(`/admin/tarif-plans/${planId}`, data);

// Change line 93
const response = await api.post(`/admin/tarif-plans/${planId}/archive`);

// Change line 105
const response = await api.get(`/admin/tarif-plans/${planId}/subscribers/count`) as { count: number };
```

---

## 10.3 Profile Store URL Correction

### Current State
| Store | Current Path | Backend Path | Action |
|-------|-------------|--------------|--------|
| `profile.ts` | `PUT /user/profile` | `PUT /user/details` | **FIX** |

### TDD Test Updates

```typescript
// tests/unit/stores/profile.spec.ts
it('updates profile via /user/details', async () => {
  const { useProfileStore, api } = await import('../../../src/stores/profile');
  const store = useProfileStore();

  api.put = vi.fn().mockResolvedValue({ id: '1', name: 'New Name', email: 'test@test.com' });

  await store.updateProfile({ name: 'New Name' });

  expect(api.put).toHaveBeenCalledWith('/user/details', { name: 'New Name' });
});
```

### Implementation Change

**user/vue/src/stores/profile.ts:**
```typescript
// Change line 44
const response = await api.put('/user/details', data);
```

---

## 10.4 Subscription Store URL Correction

### Current State
| Store | Current Path | Backend Path | Action |
|-------|-------------|--------------|--------|
| `subscription.ts` | `/user/subscription` | `/user/subscriptions/active` | **FIX** |
| `subscription.ts` | `/user/subscription/cancel` | `/user/subscriptions/{id}/cancel` | **NEEDS ID** |
| `subscription.ts` | `/user/subscription/change` | `/user/subscriptions/{id}/upgrade` or `/downgrade` | **NEEDS ID** |

### TDD Test Updates

```typescript
// tests/unit/stores/subscription.spec.ts
it('fetches subscription from /user/subscriptions/active', async () => {
  const { useSubscriptionStore, api } = await import('../../../src/stores/subscription');
  const store = useSubscriptionStore();

  api.get = vi.fn().mockResolvedValue({ id: '1', planId: 'pro', status: 'active' });

  await store.fetchSubscription();

  expect(api.get).toHaveBeenCalledWith('/user/subscriptions/active');
});

it('cancels subscription with ID', async () => {
  const { useSubscriptionStore, api } = await import('../../../src/stores/subscription');
  const store = useSubscriptionStore();
  store.subscription = { id: 'sub-123', planId: 'pro', planName: 'Pro', status: 'active', currentPeriodEnd: '2025-01-31' };

  api.post = vi.fn().mockResolvedValue({ success: true });

  await store.cancelSubscription();

  expect(api.post).toHaveBeenCalledWith('/user/subscriptions/sub-123/cancel');
});
```

### Implementation Changes

**user/vue/src/stores/subscription.ts:**
```typescript
async fetchSubscription() {
  this.loading = true;
  this.error = null;

  try {
    const response = await api.get('/user/subscriptions/active');
    this.subscription = response as Subscription;
    return response;
  } catch (error) {
    this.error = (error as Error).message || 'Failed to fetch subscription';
    throw error;
  } finally {
    this.loading = false;
  }
},

async cancelSubscription() {
  if (!this.subscription?.id) {
    throw new Error('No active subscription to cancel');
  }

  this.loading = true;
  this.error = null;

  try {
    const response = await api.post(`/user/subscriptions/${this.subscription.id}/cancel`);
    if (this.subscription) {
      this.subscription.status = 'cancelling';
    }
    return response as { success: boolean; cancellationDate: string };
  } catch (error) {
    this.error = (error as Error).message || 'Failed to cancel subscription';
    throw error;
  } finally {
    this.loading = false;
  }
},

async changePlan(planId: string) {
  if (!this.subscription?.id) {
    throw new Error('No active subscription to change');
  }

  this.loading = true;
  this.error = null;

  try {
    // Determine if upgrade or downgrade based on plan comparison
    // For now, use upgrade endpoint
    const response = await api.post(`/user/subscriptions/${this.subscription.id}/upgrade`, { plan_id: planId });
    this.subscription = response as Subscription;
    return response;
  } catch (error) {
    this.error = (error as Error).message || 'Failed to change plan';
    throw error;
  } finally {
    this.loading = false;
  }
}
```

---

## 10.5 Backend Endpoints Still Missing

After frontend URL corrections, these backend endpoints are still **genuinely missing**:

| Endpoint | Required For | Priority |
|----------|-------------|----------|
| `POST /user/change-password` | Profile password change | HIGH |
| `GET /user/usage` | Usage statistics display | MEDIUM |
| `GET /user/invoices/{id}/download` | Invoice PDF download | MEDIUM |
| `PUT /admin/users/{id}/roles` | Admin role management | HIGH |
| `POST /admin/users/{id}/impersonate` | Admin user impersonation | LOW |
| `GET /admin/tarif-plans/{id}/subscribers/count` | Plan subscriber stats | LOW |
| `/admin/analytics/*` | Full analytics API | HIGH (Sprint 11) |

### 10.5.1 Change Password Endpoint (Backend)

**TDD Test:**
```python
# tests/unit/routes/test_user_routes.py
class TestChangePassword:
    def test_change_password_success(self, client, auth_headers, user):
        """User can change password with valid current password."""
        response = client.post('/api/v1/user/change-password',
            json={
                'current_password': 'OldPassword123!',
                'new_password': 'NewPassword456!'
            },
            headers=auth_headers
        )
        assert response.status_code == 200
        assert response.json['success'] == True

    def test_change_password_wrong_current(self, client, auth_headers):
        """Returns 400 if current password is wrong."""
        response = client.post('/api/v1/user/change-password',
            json={
                'current_password': 'WrongPassword!',
                'new_password': 'NewPassword456!'
            },
            headers=auth_headers
        )
        assert response.status_code == 400
```

**Implementation:**
```python
# src/routes/user.py
@user_bp.route('/change-password', methods=['POST'])
@require_auth
def change_password():
    data = request.get_json()
    current_password = data.get('current_password')
    new_password = data.get('new_password')

    if not current_password or not new_password:
        return jsonify({'error': 'Current and new password required'}), 400

    user_service = current_app.container.user_service()
    result = user_service.change_password(g.user_id, current_password, new_password)

    if not result.success:
        return jsonify({'error': result.error}), 400

    return jsonify({'success': True})
```

### 10.5.2 Usage Endpoint (Backend)

**TDD Test:**
```python
class TestUsage:
    def test_get_usage_stats(self, client, auth_headers, active_subscription):
        """GET /user/usage returns usage statistics."""
        response = client.get('/api/v1/user/usage', headers=auth_headers)
        assert response.status_code == 200
        assert 'apiCalls' in response.json
        assert 'storage' in response.json
```

**Implementation:**
```python
@user_bp.route('/usage', methods=['GET'])
@require_auth
def get_usage():
    """Get user's feature usage statistics."""
    feature_guard = current_app.container.feature_guard()
    subscription_service = current_app.container.subscription_service()

    subscription = subscription_service.get_active_for_user(g.user_id)
    if not subscription:
        return jsonify({'error': 'No active subscription'}), 404

    usage = feature_guard.get_usage_for_user(g.user_id)
    plan = subscription.tarif_plan

    return jsonify({
        'apiCalls': {
            'used': usage.get('api_calls', 0),
            'limit': plan.features.get('api_calls_limit', 1000)
        },
        'storage': {
            'used': usage.get('storage_mb', 0),
            'limit': plan.features.get('storage_limit_mb', 100),
            'unit': 'MB'
        }
    })
```

---

## Implementation Checklist

### 10.1 Environment Configuration
- [ ] Update `docker-compose.yaml` with `VITE_API_URL=/api/v1`
- [ ] Create/update `user/.env` with `VITE_API_URL=/api/v1`
- [ ] Create/update `admin/vue/.env` with `VITE_API_URL=/api/v1`

### 10.2 Plans Store (Frontend)
- [ ] TDD: Update plans.spec.ts tests for `/tarif-plans`
- [ ] Update `plans.ts` to use `/tarif-plans`
- [ ] TDD: Update planAdmin.spec.ts tests for `/admin/tarif-plans`
- [ ] Update `planAdmin.ts` to use `/admin/tarif-plans`

### 10.3 Profile Store (Frontend)
- [ ] TDD: Update profile.spec.ts test for `/user/details`
- [ ] Update `profile.ts` to use `/user/details` for PUT

### 10.4 Subscription Store (Frontend)
- [ ] TDD: Update subscription.spec.ts tests
- [ ] Update `subscription.ts` to use `/user/subscriptions/active`
- [ ] Update cancel to use `/user/subscriptions/{id}/cancel`
- [ ] Update change to use `/user/subscriptions/{id}/upgrade`

### 10.5 Backend Missing Endpoints
- [ ] TDD: Change password tests
- [ ] Implement `POST /user/change-password`
- [ ] TDD: Usage endpoint tests
- [ ] Implement `GET /user/usage`
- [ ] (Optional) Implement other missing endpoints

---

## Verification Commands

```bash
# Run frontend tests after changes
docker-compose --profile test run --rm user-test
docker-compose --profile test run --rm admin-test

# Run backend tests
docker-compose run --rm python-test pytest tests/unit/routes/test_user_routes.py -v
```
