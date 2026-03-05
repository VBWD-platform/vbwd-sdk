# Sprint 06 Report: Cart Checkout Flow + Profile Fixes + Infrastructure

**Date:** 2026-02-07
**Status:** Complete (intermediate working state)

---

## Test Results (current)

| Suite | Passed | Skipped | Failed | Duration |
|-------|--------|---------|--------|----------|
| Backend unit tests | 508 | 4 | 0 | 8.66s |
| User app unit tests | 40 | 0 | 0 | 673ms |
| Admin app unit tests | 199 | 0 | 0 | 2.03s |
| **Total** | **747** | **4** | **0** | |

Previous session totals: Backend 504, Frontend 199+40=239. Delta: +4 backend tests, stable frontend.

---

## Running Services

| Container | Port | Status |
|-----------|------|--------|
| `vbwd-backend-api-1` (Gunicorn/Flask) | 5000 | Healthy |
| `vbwd-backend-postgres-1` (PostgreSQL 16) | 5432 | Healthy |
| `vbwd-backend-redis-1` (Redis 7) | 6379 | Healthy |
| `vbwd-backend-adminer-1` | 8088 | Running |
| `vbwd-frontend-user-app-1` (Nginx) | 8080 | Running |
| `vbwd-frontend-admin-app-1` (Nginx) | 8081 | Running |

---

## Work Completed This Sprint

### 1. Cart-Based Checkout Flow (Full Stack)

**Problem:** `/checkout/cart` route existed in the router but the Checkout view only handled plan-based checkout. Visiting `/checkout/cart` showed "No Plan Selected" because:
- `Checkout.vue` only called `store.loadPlan(planSlug)` when the route had a `planSlug` param
- Template gated the entire checkout form on `store.plan` being truthy
- Cart store (`@vbwd/view-component`) and checkout store were completely disconnected
- Backend `POST /user/checkout` required `plan_id` (returned 400 without it)

**Solution implemented:**

#### Frontend — `stores/checkout.ts`
- Added `loadFromCart()` action: maps cart items by type (`token_bundle`, `addon`, `plan`) into checkout store selections
- Added `paymentMethodCode` ref and `setPaymentMethod()` action
- Modified `submitCheckout()`: `plan_id` is now optional in the API call; sends `payment_method_code`; clears cart on success when `isCartCheckout` is true
- Made `subscription` optional in `CheckoutResult` interface (cart checkout may not create a subscription)

#### Frontend — `views/Checkout.vue`
- `onMounted()`: detects `checkout-cart` route and calls `store.loadFromCart()` instead of `store.loadPlan()`
- Template gate: `v-else-if="store.plan || store.lineItems.length > 0"` (shows form when there are any items)
- Hides `EmailBlock` for authenticated users (`v-if="!isAuthenticated"`)
- Hides token-bundle/addon browsing sections on cart checkout (items already chosen)
- `BillingAddressBlock` gets `:readonly="isAuthenticated"` for logged-in users
- Payment method selection wired to store
- Success section handles missing subscription gracefully

#### Frontend — `components/checkout/BillingAddressBlock.vue`
- Added `readonly` prop with disabled styling for logged-in users
- Fixed API endpoint: changed from non-existent `/user/billing-address` to `/user/details`
- Fixed field mapping: `address_line_1` -> `street`, `postal_code` -> `zip`
- Auto-validates on load in readonly mode (emits `valid(true)` immediately)

#### Backend — `routes/user.py`
- `plan_id` is now optional in `POST /user/checkout`
- Validation: "At least one item required (plan_id, token_bundle_ids, or add_on_ids)"
- Added `payment_method_code` parameter, passed through to checkout event

#### Backend — `events/checkout_events.py`
- Added `payment_method_code: str = None` to `CheckoutRequestedEvent` dataclass

#### Backend — `handlers/checkout_handler.py`
- Subscription creation is conditional on `event.plan_id` being present
- Addon subscriptions: `subscription_id` is `None` when no plan/subscription
- Invoice: `tarif_plan_id` can be `None`, `payment_method` set from event

#### Backend — Model changes
- `models/invoice.py`: `tarif_plan_id` column made `nullable=True`
- `models/addon_subscription.py`: `subscription_id` column made `nullable=True`; `to_dict()` handles null
- Database: `ALTER TABLE` executed for both columns

#### New tests
- `user/vue/tests/unit/stores/checkout.spec.ts` — **12 new tests**: `loadFromCart` (3), `submitCheckout` (4), computed properties (2), `setPaymentMethod` (1), `reset` (1), initial state (1)
- `vbwd-backend/tests/integration/test_checkout_endpoint.py` — **2 new tests**: checkout without plan with bundles (201), empty request (400)

---

### 2. User Profile — Schema + Country Field Fixes

**Problem 1:** PUT `/user/details` returned 400 when saving profile. Marshmallow's `UserDetailsUpdateSchema` was missing `company` and `tax_number` fields, so it rejected those fields as unknown.

**Fix:**
- Added `company = fields.Str(allow_none=True, validate=validate.Length(max=255))` to `UserDetailsUpdateSchema`
- Added `tax_number = fields.Str(allow_none=True, validate=validate.Length(max=100))` to both `UserDetailsSchema` and `UserDetailsUpdateSchema`
- Both fields are optional (`allow_none=True`)

**Problem 2:** Country field in Profile.vue was a free-text `<input>`. Users typed "Germany" but the backend validates `max=2` (ISO 3166-1 alpha-2 codes). Result: 400 error "Longer than maximum length 2."

**Fix:**
- Replaced `<input>` with `<select>` dropdown populated from `/settings/countries` API (with fallback to DE/AT/CH/US/GB)
- Country codes (e.g., "DE") are now submitted instead of full names

**Schema test updates:**
- Added `tax_number` to all `SimpleNamespace` test fixtures
- Added `test_has_tax_number_field` and `test_loads_optional_fields` tests for `UserDetailsUpdateSchema`
- Updated "removed fields" assertions (removed `company` from the assertion since it's now a valid field)

---

### 3. Admin Plugin Directory Move

**Change:** Moved `admin/vue/src/plugins/` to `admin/vue/plugins/` (outside `src/`) per project convention that plugins should be external to the main source tree.

**Files updated:**
- `admin/vue/vite.config.js` — added `'@plugins'` path alias pointing to `./plugins`
- `admin/vue/vitest.config.js` — same alias for test resolution
- `admin/vue/src/views/Dashboard.vue` — import updated to `@plugins/analytics-widget/AnalyticsWidget.vue`
- `admin/vue/tests/unit/plugins/analytics-widget.spec.ts` — imports updated
- `admin/vue/plugins/analytics-widget/AnalyticsWidget.vue` — API import changed from relative to `@/api`
- `admin/vue/bin/plugin-manager.ts` — config path updated to `./plugins`

All 199 admin tests passing after move.

---

### 4. Infrastructure Fix — Docker Compose V1 -> V2

**Problem:** `make rebuild-backend` and all other Makefile targets used `docker-compose` (V1 binary) which has a known `ContainerConfig` KeyError bug. This caused containers to crash during recreate, leaving postgres and redis in a stopped state while the API container ran — resulting in 500 errors on every authenticated endpoint (Redis unreachable for Flask-Limiter rate limiting).

**Fix:** Replaced all `docker-compose` references in `vbwd-backend/Makefile` with `docker compose` (V2 plugin). All 14 make targets updated.

---

## Codebase Statistics

### Source Files

| Area | Files |
|------|-------|
| Backend Python source (`src/`) | ~80 |
| Backend test files (`tests/`) | 61 |
| User app Vue/TS (`src/`) | 33 |
| Admin app Vue/TS (`src/`) | 41 |
| Frontend test files (`.spec.ts`) | 24+ active |

### Backend API Routes (14 modules)
`auth.py`, `user.py`, `invoices.py`, `subscriptions.py`, `tarif_plans.py`, `token_bundles.py`, `addons.py`, `settings.py`, `webhooks.py`, `health.py`, `events.py`, `config.py`, `admin/` (directory), `plugins/` (directory)

### Backend Models (24 files)
`user.py`, `user_details.py`, `subscription.py`, `invoice.py`, `invoice_line_item.py`, `tarif_plan.py`, `token_bundle.py`, `token_bundle_purchase.py`, `user_token_balance.py`, `addon.py`, `addon_subscription.py`, `payment_method.py`, `price.py`, `country.py`, `currency.py`, `tax.py`, `role.py`, `feature_usage.py`, `password_reset_token.py`, `user_case.py`, `enums.py`, `base.py`

### User App Views (11)
Dashboard, Profile, Plans, Checkout, Tokens, AddOns, Invoices, InvoiceDetail, InvoicePay, Subscription, Login

### User App Stores (6)
checkout, profile, plans, invoices, subscription, index

### Admin App Views (21)
Dashboard, Users, UserDetails, UserCreate, UserEdit, Plans, PlanForm, Subscriptions, SubscriptionDetails, SubscriptionCreate, Invoices, InvoiceDetails, PaymentMethods, PaymentMethodForm, AddOns, Countries, Settings, Profile, Login, Forbidden, TokenBundleForm

### Admin App Stores (11)
auth, users, planAdmin, subscriptions, invoices, paymentMethods, tokenBundles, analytics, countries, webhooks, index

### Plugin System
- **Backend:** `PluginManager`, `BasePlugin`, `PaymentProviderPlugin` base classes + `AnalyticsPlugin`, `MockPaymentPlugin` providers
- **Frontend:** `admin/vue/plugins/analytics-widget/` (AnalyticsWidget.vue + index.ts)
- **Core:** `PluginRegistry`, `PlatformSDK`, `IPlugin` interfaces in `@vbwd/view-component`

### i18n
- User app: EN + DE, 319+ keys each (`vue-i18n`, `legacy: false`)
- Admin app: EN + DE (pre-existing)

---

## Working User Flows (Verified)

1. **Login/Auth** — register, login, JWT token refresh
2. **Dashboard** — user info, token balance, subscription status
3. **Profile** — view/edit personal info, company, tax number, address (country dropdown), change password
4. **Plans** — browse plans, select plan -> checkout
5. **Checkout (plan-based)** — select plan + optional bundles/addons, billing address, payment method, submit
6. **Checkout (cart-based)** — add items to cart from Tokens/AddOns pages, go to cart, checkout with pre-selected items, billing address readonly for logged-in users
7. **Tokens** — browse token bundles, add to cart
8. **AddOns** — browse add-ons, add to cart
9. **Invoices** — list invoices, view detail, pay invoice (triggers subscription activation + token crediting)
10. **Subscription** — view active subscription, usage stats, cancellation
11. **Admin Dashboard** — analytics widget (plugin), user management, plan CRUD, invoice management

---

## Known Remaining Items

| Item | Priority | Notes |
|------|----------|-------|
| Frontend PluginRegistry init in `main.ts` | HIGH | Sprint 06 in TODO backlog — dynamic route injection via PlatformSDK |
| Backend dynamic route registration for plugins | MEDIUM | Sprint 07 — plugins declare Flask blueprints |
| Backend plugin config persistence | MEDIUM | Sprint 08 — DB table for enable/disable state |
| Backend plugin auto-discovery | LOW | Sprint 09 — scan providers directory |
| E2E test suite for user app | MEDIUM | 86 passed / 26 failed (last run 2026-01-23), needs revalidation |
| `to_dict()` UUID serialization | LOW | `UserDetails.to_dict()` and `Subscription.to_dict()` return raw UUID objects — works via marshmallow schemas but would fail if called directly with `jsonify()` |

---

## Files Changed This Sprint

| File | Change Type |
|------|-------------|
| `vbwd-frontend/user/vue/src/stores/checkout.ts` | Modified — cart checkout support |
| `vbwd-frontend/user/vue/src/views/Checkout.vue` | Modified — cart route handling, template gates |
| `vbwd-frontend/user/vue/src/views/Profile.vue` | Modified — country select dropdown |
| `vbwd-frontend/user/vue/src/components/checkout/BillingAddressBlock.vue` | Modified — readonly prop, API fix |
| `vbwd-frontend/user/vue/tests/unit/stores/checkout.spec.ts` | **New** — 12 tests |
| `vbwd-backend/src/routes/user.py` | Modified — optional plan_id, payment_method |
| `vbwd-backend/src/events/checkout_events.py` | Modified — payment_method_code field |
| `vbwd-backend/src/handlers/checkout_handler.py` | Modified — conditional subscription |
| `vbwd-backend/src/models/invoice.py` | Modified — nullable tarif_plan_id |
| `vbwd-backend/src/models/addon_subscription.py` | Modified — nullable subscription_id |
| `vbwd-backend/src/schemas/user_schemas.py` | Modified — company + tax_number fields |
| `vbwd-backend/tests/unit/schemas/test_user_schemas.py` | Modified — new schema tests |
| `vbwd-backend/tests/integration/test_checkout_endpoint.py` | Modified — 2 new tests |
| `vbwd-backend/Makefile` | Modified — docker-compose V1 -> V2 |
| `vbwd-frontend/admin/vue/vite.config.js` | Modified — @plugins alias |
| `vbwd-frontend/admin/vue/vitest.config.js` | Modified — @plugins alias |
| `vbwd-frontend/admin/vue/src/views/Dashboard.vue` | Modified — import path |
| `vbwd-frontend/admin/vue/plugins/analytics-widget/*` | Moved from src/plugins/ |
| `vbwd-frontend/admin/vue/bin/plugin-manager.ts` | Modified — plugins path |
