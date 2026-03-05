# Report: Session 3 — Billing Fixes, Deploy Pipeline & Domain Support

**Date**: 2026-02-25
**Status**: Complete
**Repositories**: vbwd-backend · vbwd-fe-user · vbwd-fe-admin · vbwd-sdk-2 (monorepo)

---

## Summary

Three independent workstreams completed in this session:

1. **Billing fixes** — Zero-price auto-activation, subscription history sort fix, payment handler field typo, multi-subscription dashboard/UI
2. **Deploy pipeline** — GitHub Actions build+deploy workflow with GHCR, production Dockerfiles, nginx configs
3. **Domain/SSL support** — `dev-install-ce.sh` accepts `--domain` and `--ssl` flags; no more hardcoded `localhost`

---

## 1. Billing Fixes

### 1.1 Zero-Price Checkout Auto-Activation

**File**: `vbwd-backend/src/handlers/checkout_handler.py`

After all items and the invoice are created, the handler checks `total_amount == Decimal("0.00")`. If true, it immediately dispatches `PaymentCapturedEvent(payment_reference="zero-price")` via the DI container's dispatcher. `PaymentCapturedHandler` runs synchronously, marks the invoice `PAID`, and activates all line items (subscription, tokens, add-ons). The invoice is reloaded before building the response so the caller sees `status: PAID`.

```
Checkout → total == 0 → PaymentCapturedEvent dispatched inline
                       → invoice marked PAID
                       → subscription activated
                       → tokens credited
Response: "Checkout complete. Free plan activated."
```

No changes to routes or PaymentCapturedHandler required — reuses existing activation logic.

### 1.2 Payment Handler Field Typo

**File**: `vbwd-backend/src/handlers/payment_handler.py` (line 118)

`subscription.starts_at` → `subscription.started_at`

Root cause of `started_at` always being `null` for all payment-handler-activated subscriptions, which broke subscription history sorting and hid multi-subscriptions at the bottom of history.

### 1.3 Subscription History Sort Fallback

**File**: `vbwd-fe-user/vue/src/stores/subscription.ts`

- Added `created_at: string | null` to `Subscription` interface
- `fetchHistory()` sort now uses `created_at` as fallback when `started_at` is null:

```typescript
.sort((a, b) => {
  const aTime = new Date(b.started_at || b.created_at || 0).getTime();
  const bTime = new Date(a.started_at || a.created_at || 0).getTime();
  return aTime - bTime;
})
```

Backend `list_subscriptions` returns `created_at` in the response for this purpose.

### 1.4 Multi-Subscription Dashboard & Subscription Page

**`vbwd-fe-user` — Dashboard.vue**: Subscription card renamed "Active Subscriptions". Computed `primarySubscription` (first with `is_single=true` category) displayed first; remaining multi-subscriptions listed below under "Additional Subscriptions".

**`vbwd-fe-user` — Subscription.vue**: Replaced "Current Plan" block with an "Active Subscriptions" table (Plan | Next Payment | Price | Cancel). Removed "Manage Subscription" block and "Usage Statistics" block. Per-row cancel passes explicit `subscriptionId` to store.

**`vbwd-fe-user` — subscription.ts store**: `cancelSubscription(subscriptionId?: string)` accepts optional explicit ID, calls both `fetchSubscription` and `fetchActiveSubscriptions` after cancel.

**`vbwd-fe-admin` — Plans.vue**: Added "Categories" column showing category slugs as pill badges; subscriber count fixed via batch SQL query (`func.count + group_by`) eliminating N+1.

---

## 2. Deploy Pipeline

### 2.1 Production Dockerfiles

**`vbwd-fe-user/Dockerfile`** and **`vbwd-fe-admin/Dockerfile`** — multi-stage builds:

```
Stage 1 (node:20-alpine):
  - Copy repo (requires --recurse-submodules)
  - Build vbwd-fe-core submodule
  - npm install + npm run build
  ARG VITE_API_URL=/api/v1  ← relative, domain-independent

Stage 2 (nginx:alpine):
  - COPY dist → /usr/share/nginx/html
  - COPY nginx.prod.conf.template → /etc/nginx/templates/
  ENV API_UPSTREAM=api:5000  ← override at runtime
```

`API_UPSTREAM` is injected into nginx via the official nginx image's `envsubst` template feature — no custom entrypoint needed.

### 2.2 Production Nginx Configs

**`vbwd-fe-user/nginx.prod.conf.template`**: Standard SPA — proxies `/api/` to `$API_UPSTREAM`, `try_files $uri $uri/ /index.html` for Vue Router.

**`vbwd-fe-admin/nginx.prod.conf.template`**: Admin SPA has `base: '/admin/'` in Vite config, so assets are referenced at `/admin/assets/*`. Uses `alias /usr/share/nginx/html/` for `location /admin/` with a named location SPA fallback:

```nginx
location /admin/ {
    alias /usr/share/nginx/html/;
    try_files $uri $uri/ @admin_spa;
}
location @admin_spa {
    root /usr/share/nginx/html;
    rewrite ^ /index.html break;
}
```

### 2.3 GitHub Actions Deploy Workflow

**`.github/workflows/deploy.yml`**

| Job | Description |
|-----|-------------|
| `ci-gate` | Aborts if CI pipeline did not pass (via `workflow_run` conclusion check) |
| `build-backend` | Clones `vbwd-backend:production`, builds + pushes `ghcr.io/…/vbwd_backend:latest` |
| `build-fe-user` | Clones `vbwd-fe-user:production` + submodules, builds + pushes `ghcr.io/…/vbwd_fe_user:latest` |
| `build-fe-admin` | Clones `vbwd-fe-admin:production` + submodules, builds + pushes `ghcr.io/…/vbwd_fe_admin:latest` |
| `deploy` | SSH to server, parallel `docker compose pull`, migrate, `docker compose up -d --force-recreate` |
| `verify` | Checks all containers running + HTTP 200 on API health, user app, admin app |

**Trigger**: `workflow_run` on `VBWD CE - CI/CD Pipeline` completing on `production` branch. Deploy only proceeds if `conclusion == 'success'`. `workflow_dispatch` bypasses the gate for manual re-deploys.

```
CI pipeline (ci.yml) → completes on production
          ↓
      ci-gate  ← blocks if CI failed
    ┌───┼───┐
    ▼   ▼   ▼
  back  fe-u  fe-a   (parallel builds)
    └───┼───┘
        ▼
      deploy → migrate → restart
        ↓
      verify
```

**Reuses loopai secrets**: `LOOPAI_SERVER2_IP`, `SERVER_USERNAME`, `LOOPAI_SERVER2_IP_SSH_PRIVATE_KEY`, `DANTWEB_DEPLOY_TOKEN`.

**GHA cache**: All three build jobs use `cache-from/cache-to: type=gha` with separate scopes — reduces rebuild time on unchanged layers.

---

## 3. Domain & SSL Support

**`recipes/dev-install-ce.sh`**

Added `--domain` and `--ssl` flags (also readable as `VBWD_DOMAIN` / `VBWD_SSL` env vars):

```bash
./recipes/dev-install-ce.sh                              # http://localhost
./recipes/dev-install-ce.sh --domain myapp.com          # http://myapp.com
./recipes/dev-install-ce.sh --domain myapp.com --ssl    # https://myapp.com
VBWD_DOMAIN=myapp.com VBWD_SSL=1 ./recipes/dev-install-ce.sh
```

Key fix: generated `.env` was previously writing `VITE_API_URL=http://localhost:5000`, overriding the safe `/api/v1` fallback in `api/index.ts` and baking `localhost` into the compiled JS bundle. Fixed to:

```bash
VITE_API_URL=/api/v1               # relative — works for any domain via nginx proxy
VITE_BACKEND_URL=${HTTP}://${DOMAIN}:5000   # Vite dev-server proxy target
VITE_WS_URL=${WS}://${DOMAIN}:5000
```

`VITE_API_URL` stays relative in all cases — nginx handles the actual protocol at the edge.

---

## Files Changed

### New Files

| File | Description |
|------|-------------|
| `vbwd-fe-user/Dockerfile` | Production multi-stage build |
| `vbwd-fe-user/nginx.prod.conf.template` | Production nginx with API proxy + SPA fallback |
| `vbwd-fe-admin/Dockerfile` | Production multi-stage build |
| `vbwd-fe-admin/nginx.prod.conf.template` | Production nginx with `/admin/` alias + SPA fallback |
| `.github/workflows/deploy.yml` | Full build → deploy → verify pipeline |

### Modified Files

| File | Change |
|------|--------|
| `vbwd-backend/src/handlers/checkout_handler.py` | Zero-price auto-payment (step 7) |
| `vbwd-backend/src/handlers/payment_handler.py` | `starts_at` → `started_at` typo fix |
| `vbwd-backend/src/routes/subscriptions.py` | `list_subscriptions` returns `created_at` + plan categories; added `/active-all` endpoint |
| `vbwd-fe-user/vue/src/stores/subscription.ts` | `created_at` on interface; `fetchHistory` sort fallback; `cancelSubscription` explicit ID |
| `vbwd-fe-user/vue/src/views/Dashboard.vue` | Multi-sub card with primary + additional sections |
| `vbwd-fe-user/vue/src/views/Subscription.vue` | Active subs table, per-row cancel, removed unused blocks |
| `vbwd-fe-admin/vue/src/views/Plans.vue` | Categories column (pill badges), batch subscriber count |
| `vbwd-fe-admin/vue/src/routes/admin/plans.py` | Batch `func.count + group_by` subscriber count |
| `recipes/dev-install-ce.sh` | `--domain` / `--ssl` flags; fixed `VITE_API_URL` to relative path |
| `.github/workflows/deploy.yml` | CI gate via `workflow_run` + `ci-gate` job |
