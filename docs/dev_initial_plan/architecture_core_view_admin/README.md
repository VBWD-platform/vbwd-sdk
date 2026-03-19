# VBWD Admin Application Architecture

**Project:** VBWD-SDK - Admin Dashboard Application
**Status:** Active Development
**Last Updated:** 2026-01-05
**License:** BSL 1.1 (Business Source Licence)

---

## Implementation Status (2026-01-05)

| Feature | Status | Notes |
|---------|--------|-------|
| **Authentication** | ✅ Implemented | JWT login, role-based guards |
| **Dashboard** | ✅ Implemented | Overview with key metrics |
| **User Management** | ✅ Implemented | List, view, edit, suspend |
| **Plan Management** | ✅ Implemented | CRUD, features as object/array |
| **Subscription Management** | ✅ Implemented | List, view, modify, cancel |
| **Invoice Management** | ✅ Implemented | List, view details, mark paid |
| **Analytics** | ✅ Implemented | Overview, date filters |
| **Webhook Monitor** | ✅ Implemented | List, view details, retry |
| **Settings** | ✅ Implemented | General, email, security tabs |
| **Core Views (Flat)** | ✅ By Design | Users, Plans, Subscriptions, Invoices, Settings |
| **Plugin Architecture** | ✅ Reserved | For payment integrations & value-added services |

### Architecture Decision (2026-01-05)

**Decision:** Hybrid architecture with flat core views + plugin system for integrations.

**Rationale:**
- **Core business logic** (users, tariffs, subscriptions, invoices, settings) uses flat `src/views/` structure - these are foundational features that every installation needs
- **Plugins** are reserved for extensibility: payment provider integrations (Stripe, PayPal) and value-added service provider integrations

**This is NOT a deviation** - it's the intended design:

| Component Type | Structure | Examples |
|----------------|-----------|----------|
| **Core Views** | Flat `src/views/` | Users, Plans, Subscriptions, Invoices, Settings, Analytics |
| **Core Stores** | Flat `src/stores/` | auth.ts, users.ts, planAdmin.ts, subscriptions.ts, invoices.ts |
| **Payment Plugins** | `src/plugins/payments/` | Stripe, PayPal, Custom payment providers |
| **Integration Plugins** | `src/plugins/integrations/` | Value-added service providers |

### Plugin System Usage

**Core SDK plugin system** (`frontend/core/src/plugins/`) will be used for:

1. **Payment Provider Plugins**
   - `src/plugins/payments/stripe/` - Stripe integration
   - `src/plugins/payments/paypal/` - PayPal integration
   - Each plugin provides: config UI, webhook handlers, payment flow components

2. **Value-Added Service Plugins**
   - Third-party integrations (CRM, email marketing, analytics providers)
   - Custom extensions by deployment

**Core admin features are NOT plugins** because:
- They are required for every installation
- They don't need to be swapped out or disabled
- Flat structure is simpler and sufficient

**Unit Tests:** 71 tests in 7 files
**E2E Tests:** 108 tests in 13 spec files

---

## 1. Project Overview

The **VBWD Admin Application** is a separate Vue.js 3 + TypeScript application for administrative operations. It uses a **hybrid architecture**:

- **Core features** (users, plans, subscriptions, invoices, settings) use flat `src/views/` structure
- **Extensibility** (payment providers, third-party integrations) uses the plugin system from Core SDK

### Key Features

**Core Features (Flat Views):**
- **User Management**: View, edit, suspend user accounts
- **Plan Management**: Create, edit, deactivate tariff plans
- **Subscription Management**: View, modify user subscriptions
- **Invoice Management**: View invoices, manual payment marking
- **Analytics Dashboard**: Metrics, charts, reports
- **Webhook Monitoring**: View webhook logs and events
- **Settings**: System configuration

**Plugin-Based Features (Future):**
- Payment provider configuration (Stripe, PayPal)
- Value-added service integrations

---

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VBWD Admin Application                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Application Shell                       │   │
│  │  - Admin Router (Vue Router)                            │   │
│  │  - Admin Layout (sidebar, topbar)                      │   │
│  │  - Global State (Pinia)                                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Core Views Layer                       │   │
│  │            (Flat Structure - src/views/)                │   │
│  │                                                          │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │   │
│  │  │ Users.vue  │  │ Plans.vue  │  │ Subscriptions.vue  │ │   │
│  │  └────────────┘  └────────────┘  └────────────────────┘ │   │
│  │                                                          │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │   │
│  │  │Invoices.vue│  │Analytics.vue│ │ Settings.vue       │ │   │
│  │  └────────────┘  └────────────┘  └────────────────────┘ │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Plugin Layer (Extensibility)               │   │
│  │         (Uses Core SDK Plugin System)                   │   │
│  │                                                          │   │
│  │  ┌────────────────┐  ┌────────────────┐  ┌───────────┐  │   │
│  │  │ Stripe Plugin  │  │ PayPal Plugin  │  │ Custom    │  │   │
│  │  │ (payments)     │  │ (payments)     │  │ Plugins   │  │   │
│  │  └────────────────┘  └────────────────┘  └───────────┘  │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
                  ┌────────────────┐
                  │  Backend API   │
                  │  (Flask)       │
                  │  /api/v1/admin/*│
                  └────────────────┘
```

---

## 3. Core Views (Flat Structure)

Core admin features use flat `src/views/` structure. These are foundational features required by every installation.

### 3.1 User Management

**Location:** `src/views/Users.vue`, `src/views/UserDetails.vue`
**Store:** `src/stores/users.ts`

**Responsibilities:**
- List all users with pagination, search, filters
- View user details (profile, subscriptions, invoices)
- Suspend/activate user accounts

**Routes:**
- `/users` - User list
- `/users/:id` - User details

---

### 3.2 Plan Management

**Location:** `src/views/Plans.vue`, `src/views/PlanForm.vue`
**Store:** `src/stores/planAdmin.ts`

**Responsibilities:**
- List all tariff plans
- Create/edit tariff plans
- Activate/deactivate plans
- Set pricing and features

**Routes:**
- `/plans` - Plan list
- `/plans/new` - Create plan
- `/plans/:id/edit` - Edit plan

---

### 3.3 Subscription Management

**Location:** `src/views/Subscriptions.vue`, `src/views/SubscriptionDetails.vue`
**Store:** `src/stores/subscriptions.ts`

**Responsibilities:**
- View all subscriptions with filters
- Cancel subscriptions
- View subscription history

**Routes:**
- `/subscriptions` - Subscription list
- `/subscriptions/:id` - Subscription details

---

### 3.4 Invoice Management

**Location:** `src/views/Invoices.vue`, `src/views/InvoiceDetails.vue`
**Store:** `src/stores/invoices.ts`

**Responsibilities:**
- List all invoices with filters
- View invoice details with line items
- Manual payment marking

**Routes:**
- `/invoices` - Invoice list
- `/invoices/:id` - Invoice details

---

### 3.5 Analytics Dashboard

**Location:** `src/views/Analytics.vue`, `src/views/Dashboard.vue`
**Store:** `src/stores/analytics.ts`

**Responsibilities:**
- Dashboard with key metrics
- Revenue overview
- User growth
- Plan distribution

**Routes:**
- `/` - Dashboard overview
- `/analytics` - Detailed analytics

---

### 3.6 Webhook Monitor

**Location:** `src/views/Webhooks.vue`, `src/views/WebhookDetails.vue`
**Store:** `src/stores/webhooks.ts`

**Responsibilities:**
- View webhook events
- View event payloads
- Retry failed webhooks

**Routes:**
- `/webhooks` - Webhook list
- `/webhooks/:id` - Event details

---

### 3.7 Settings

**Location:** `src/views/Settings.vue`

**Responsibilities:**
- Company information
- Billing settings
- Notification preferences

**Routes:**
- `/settings` - Settings page with tabs

---

## 4. Plugin Layer (Extensibility)

Plugins are used for features that:
- May vary between installations (payment providers)
- Need to be added/removed dynamically
- Integrate with external services

### 4.1 Payment Provider Plugins (Planned)

**Location:** `src/plugins/payments/`

| Plugin | Purpose |
|--------|---------|
| `stripe/` | Stripe payment integration, config UI, webhook handling |
| `paypal/` | PayPal payment integration, config UI, webhook handling |

Each payment plugin provides:
- Configuration UI in Settings
- Payment flow components
- Webhook event handlers

### 4.2 Value-Added Service Plugins (Planned)

**Location:** `src/plugins/integrations/`

For third-party integrations like:
- CRM systems
- Email marketing platforms
- Analytics providers
- Custom extensions

### 4.3 CLI Plugin Manager (Planned)

Each application that extends view-core (admin, user) should include a CLI tool for plugin management.

**Location:** `bin/plugin-manager` or `npm run plugin`

**Commands:**

| Command | Description |
|---------|-------------|
| `plugin list` | List all registered plugins with status (active/inactive) |
| `plugin install <name>` | Install a plugin from registry or local path |
| `plugin uninstall <name>` | Remove a plugin from the application |
| `plugin activate <name>` | Activate an installed plugin |
| `plugin deactivate <name>` | Deactivate a plugin without removing it |
| `plugin help` | Show help and available commands |

**Example Usage:**

```bash
# List all plugins
npm run plugin list

# Output:
# NAME              VERSION   STATUS      DESCRIPTION
# stripe-payment    1.2.0     active      Stripe payment provider
# paypal-payment    1.1.0     inactive    PayPal payment provider
# mailchimp         0.9.0     active      Mailchimp email integration

# Install a plugin
npm run plugin install @vbwd/stripe-payment

# Activate/deactivate
npm run plugin activate paypal-payment
npm run plugin deactivate stripe-payment

# Uninstall
npm run plugin uninstall mailchimp
```

**Implementation Notes:**
- CLI wraps `PluginRegistry` from view-core
- Plugins stored in `src/plugins/` directory
- Plugin state persisted in `plugins.json` config file
- Requires app restart after install/uninstall (hot reload for activate/deactivate planned)

---

## 5. Admin Layout Structure

### 5.1 Admin Layout Component

```
┌─────────────────────────────────────────────────────────┐
│ Topbar                                                  │
│ [VBWD Admin] [Search] [Notifications] [Admin User ▼]  │
├─────────────┬───────────────────────────────────────────┤
│             │                                           │
│  Sidebar    │  Main Content Area                        │
│             │  <router-view />                          │
│  Dashboard  │                                           │
│  Users      │                                           │
│  Plans      │                                           │
│  Subscr.    │                                           │
│  Invoices   │                                           │
│  Analytics  │                                           │
│  Webhooks   │                                           │
│  Settings   │                                           │
│             │                                           │
└─────────────┴───────────────────────────────────────────┘
```

**File:** `src/layouts/AdminLayout.vue`

```vue
<template>
  <div class="min-h-screen bg-gray-100">
    <!-- Topbar -->
    <AdminTopbar />

    <div class="flex">
      <!-- Sidebar -->
      <AdminSidebar />

      <!-- Main Content -->
      <main class="flex-1 p-8">
        <router-view />
      </main>
    </div>
  </div>
</template>
```

---

## 6. Directory Structure

```
frontend/admin/vue/
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.ts
├── playwright.config.ts
├── vitest.config.ts
│
├── src/
│   ├── main.ts                    # Admin app entry point
│   ├── App.vue                    # Root component
│   │
│   ├── api/
│   │   └── index.ts               # API client
│   │
│   ├── layouts/
│   │   ├── AdminLayout.vue        # Main admin layout
│   │   ├── AdminTopbar.vue        # Top navigation bar
│   │   └── AdminSidebar.vue       # Left sidebar menu
│   │
│   ├── stores/                    # Pinia stores (flat structure)
│   │   ├── index.ts               # Barrel exports
│   │   ├── auth.ts                # Authentication store
│   │   ├── users.ts               # User management store
│   │   ├── planAdmin.ts           # Plan management store
│   │   ├── subscriptions.ts       # Subscription store
│   │   ├── invoices.ts            # Invoice store
│   │   ├── webhooks.ts            # Webhook store
│   │   └── analytics.ts           # Analytics store
│   │
│   ├── views/                     # Core views (flat structure)
│   │   ├── Login.vue              # Admin login
│   │   ├── Forbidden.vue          # 403 error page
│   │   ├── Dashboard.vue          # Dashboard overview
│   │   ├── Users.vue              # User list
│   │   ├── UserDetails.vue        # User detail view
│   │   ├── Plans.vue              # Plan list
│   │   ├── PlanForm.vue           # Create/edit plan
│   │   ├── Subscriptions.vue      # Subscription list
│   │   ├── SubscriptionDetails.vue# Subscription detail
│   │   ├── Invoices.vue           # Invoice list
│   │   ├── InvoiceDetails.vue     # Invoice detail
│   │   ├── Webhooks.vue           # Webhook list
│   │   ├── WebhookDetails.vue     # Webhook detail
│   │   ├── Analytics.vue          # Analytics dashboard
│   │   └── Settings.vue           # Settings page
│   │
│   ├── plugins/                   # Extension plugins (future)
│   │   ├── payments/              # Payment provider plugins
│   │   │   ├── stripe/            # Stripe integration
│   │   │   └── paypal/            # PayPal integration
│   │   └── integrations/          # Value-added services
│   │
│   └── router/
│       └── index.ts               # Admin router config
│
├── tests/
│   ├── unit/                      # Vitest unit tests
│   │   ├── stores/
│   │   └── ...
│   ├── integration/               # Component integration tests
│   │   └── ...
│   └── e2e/                       # Playwright E2E tests
│       ├── admin-login.spec.ts
│       ├── admin-users.spec.ts
│       ├── admin-plans.spec.ts
│       └── ...
│
└── node_modules/
    └── @vbwd/core -> ../../core   # Symlink to core SDK
```

---

## 7. Authentication & Access Control

### 7.1 Admin Authentication

Admin login is separate from user login but uses the same AuthService from Core SDK.

**Requirements:**
- User must have `role: 'admin'`
- Login at `/admin/login`
- Separate session management
- Admin-only API endpoints (`/api/v1/admin/*`)

### 7.2 Route Protection

All admin routes require:
1. Authentication (via `authGuard`)
2. Admin role (via `adminRoleGuard`)

**Example:**
```typescript
{
  path: '/admin',
  component: AdminLayout,
  meta: {
    requiresAuth: true,
    requiredRole: 'admin'
  },
  children: [...]
}
```

---

## 8. Admin API Endpoints (Backend)

### 8.1 User Management
- `GET /api/v1/admin/users` - List users (paginated)
- `GET /api/v1/admin/users/:id` - Get user details
- `PUT /api/v1/admin/users/:id` - Update user
- `PUT /api/v1/admin/users/:id/status` - Suspend/activate user
- `GET /api/v1/admin/users/:id/subscriptions` - User subscriptions
- `GET /api/v1/admin/users/:id/invoices` - User invoices

### 8.2 Plan Management
- `GET /api/v1/admin/tarif-plans` - List all plans (including inactive)
- `POST /api/v1/admin/tarif-plans` - Create plan
- `PUT /api/v1/admin/tarif-plans/:id` - Update plan
- `DELETE /api/v1/admin/tarif-plans/:id` - Deactivate plan

### 8.3 Subscription Management
- `GET /api/v1/admin/subscriptions` - List all subscriptions
- `GET /api/v1/admin/subscriptions/:id` - Get subscription
- `PUT /api/v1/admin/subscriptions/:id` - Update subscription
- `PUT /api/v1/admin/subscriptions/:id/cancel` - Cancel subscription
- `PUT /api/v1/admin/subscriptions/:id/extend` - Extend subscription

### 8.4 Invoice Management
- `GET /api/v1/admin/invoices` - List all invoices
- `GET /api/v1/admin/invoices/:id` - Get invoice
- `PUT /api/v1/admin/invoices/:id/mark-paid` - Manually mark as paid

### 8.5 Analytics
- `GET /api/v1/admin/analytics/overview` - Dashboard metrics
- `GET /api/v1/admin/analytics/revenue` - Revenue data
- `GET /api/v1/admin/analytics/users` - User growth data
- `GET /api/v1/admin/analytics/subscriptions` - Subscription metrics

### 8.6 Webhooks
- `GET /api/v1/admin/webhooks` - List webhook events
- `GET /api/v1/admin/webhooks/:id` - Get event details
- `POST /api/v1/admin/webhooks/:id/retry` - Retry failed webhook

---

## 9. Shared Core SDK Usage

The admin app uses the same Core SDK as the user app:

```typescript
// main.ts
import { createPlatformSDK } from '@vbwd/core';

const sdk = createPlatformSDK(app, router);

// SDK provides:
// - sdk.apiClient (with admin endpoints)
// - sdk.authService (checks admin role)
// - sdk.eventBus
// - sdk.validationService
```

**Admin-specific API calls:**
```typescript
// Uses IApiClient.admin endpoints
const users = await sdk.apiClient.admin.users.list();
const plans = await sdk.apiClient.admin.plans.list();
```

---

## 10. Development Principles

- **TDD First**: Write E2E tests for admin workflows
- **SOLID**: Admin plugins implement IPlugin
- **DRY**: Reuse Core SDK components and logic
- **Type Safety**: Full TypeScript coverage
- **Accessibility**: WCAG 2.1 AA compliance
- **Performance**: Lazy load plugins, optimize tables

---

## 11. Testing Strategy

### 11.1 E2E Tests (Playwright)

**Critical Flows:**
- Admin login with valid/invalid credentials
- User management (create, edit, suspend)
- Plan management (create, edit, deactivate)
- Subscription modification
- Invoice manual payment marking
- Analytics dashboard loading

**Example:** `tests/e2e/user-management.spec.ts`
```typescript
test('admin can suspend user account', async ({ page }) => {
  // Login as admin
  await page.goto('/admin/login');
  await page.fill('input[type="email"]', 'admin@example.com');
  await page.fill('input[type="password"]', 'admin123');
  await page.click('button[type="submit"]');

  // Navigate to users
  await page.click('text=Users');
  await expect(page).toHaveURL('/admin/users');

  // Find user and suspend
  await page.click('tr:has-text("john@example.com") button:has-text("Actions")');
  await page.click('text=Suspend');
  await page.click('button:has-text("Confirm")');

  // Verify status changed
  await expect(page.locator('text=suspended')).toBeVisible();
});
```

### 11.2 Unit Tests (Vitest)

- Admin store logic
- Admin composables
- Admin-specific utilities

---

## 12. UI/UX Design

### 12.1 Admin Theme
- Darker sidebar for admin feel
- Tables with pagination and sorting
- Search and filter components
- Action buttons with confirmation dialogs
- Toast notifications for success/error

### 12.2 Data Tables
- Pagination (10, 25, 50, 100 per page)
- Column sorting
- Search/filter bar
- Bulk actions (select multiple rows)
- Export to CSV

### 12.3 Forms
- Validation with immediate feedback
- Save/Cancel actions
- Dirty state tracking ("You have unsaved changes")

---

## 13. PlantUML Diagrams

All admin architecture diagrams:

| Diagram                     | File                              | Description                       |
|-----------------------------|-----------------------------------|-----------------------------------|
| Admin Plugin Architecture   | `puml/admin-plugin-architecture.puml` | Admin plugin system      |
| User Management Flow        | `puml/user-management-flow.puml`  | Admin user CRUD operations        |
| Analytics Dashboard         | `puml/analytics-architecture.puml`| Analytics plugin structure        |
| Admin Layout Structure      | `puml/admin-layout.puml`          | Layout component hierarchy        |

---

## Related Documentation

- [Core SDK Documentation](../architecture_core_view_sdk/README.md)
- [User App Architecture](../architecture_core_view_user/README.md)
- [Server Architecture](../architecture_server/README.md)
- [Admin Sprint Plans](./sprints/README.md)
