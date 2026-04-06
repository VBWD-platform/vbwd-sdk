# Access Level Management System

## Overview

The VBWD platform uses a two-layer access control system:

1. **User Role** (enum on `vbwd_user.role`) — determines which application a user can access
2. **Access Levels** (RBAC roles in `vbwd_role`) — granular permissions for ADMIN users

## User Roles

| Role | Admin Panel | User App | Permissions |
|------|------------|----------|-------------|
| `SUPER_ADMIN` | Full access | Yes | Wildcard `*` — bypasses all permission checks |
| `ADMIN` | Yes (limited) | Yes | Only what access levels grant |
| `USER` | Never | Yes | N/A |
| `VENDOR` | Never | Yes | N/A |

- `SUPER_ADMIN` can do everything — no restrictions, no access levels needed
- `ADMIN` without access levels sees only the dashboard — all other pages/APIs return 403
- `USER` and `VENDOR` are redirected to forbidden on any admin panel attempt

## Access Levels

Access levels are named permission bundles stored in `vbwd_role`. They only apply to `ADMIN` users.

Examples:
- "Editor" — `cms.pages.view`, `cms.pages.manage`, `cms.images.view`
- "Observer" — `analytics.view`, `users.view`, `invoices.view`
- "Full Access" — `*` (wildcard)

### Permission Format

Permissions follow `resource.action` format where the action defines the access scope:

| Action | Meaning | Allowed Operations |
|--------|---------|-------------------|
| **view** | Read-only access | List, get detail, export, preview, download PDF |
| **manage** | Destructive operations | Create, update, delete, bulk operations, import |
| **configure** | Plugin configuration | Change plugin settings on config pages in admin Settings |

Examples:

```
users.view              — Open user list, view user details
users.manage            — Create, edit, delete, suspend users
invoices.view           — Open invoice list, view details, download PDF
invoices.manage         — Mark paid, void, refund, delete invoices
analytics.view          — View dashboard analytics cards
settings.view           — Open settings pages, view countries, token bundles
settings.manage         — Edit settings, payment methods, tax config, countries
settings.system         — Manage plugins, access levels, API keys
cms.pages.view          — Open CMS pages list, view page content
cms.pages.manage        — Create, edit, delete CMS pages, import/export
cms.configure           — Change CMS routing rules
shop.configure          — Configure shipping methods
booking.configure       — Manage booking schemas, export rules
```

**Rule of thumb:** if the operation changes data → `manage`. If it only reads → `view`. If it changes plugin behavior → `configure`.

### View vs Manage on Edit Pages

Edit/detail pages require `view` permission (not `manage`). This lets view-only users **open** an item and see its full details. The `manage` permission controls whether **Save/Delete/Publish buttons are visible**.

Frontend pattern for any edit page:

```vue
<script setup>
import { useAuthStore } from '@/stores/auth';
const authStore = useAuthStore();
const canManage = computed(() => authStore.hasPermission('resource.manage'));
</script>

<template>
  <!-- Edit route requires only 'view' permission to open -->
  <!-- Save/Delete buttons hidden without 'manage' permission -->
  <button v-if="canManage" @click="save()">Save</button>
  <button v-if="canManage" @click="remove()">Delete</button>
</template>
```

Backend enforces the same: GET detail → `view`, PUT/DELETE → `manage`.

### Wildcard Support

- `*` — matches all permissions
- `shop.*` — matches all shop permissions (e.g., `shop.products.view`, `shop.orders.manage`)

## How It Works

### Backend (API Protection)

Every admin route is protected by two decorators:

```python
@admin_bp.route("/users/", methods=["GET"])
@require_auth          # 1. Verify JWT token
@require_admin         # 2. Check user.role is SUPER_ADMIN or ADMIN
@require_permission("users.view")  # 3. Check access level grants this permission
def list_users():
    ...
```

- `@require_admin` — returns 403 if user is not SUPER_ADMIN or ADMIN
- `@require_permission` — returns 403 with `{"error": "Permission denied", "required": "users.view"}`
- SUPER_ADMIN bypasses `@require_permission` automatically (has wildcard `*`)

### Frontend (Route Protection)

Every admin route has `meta.requiredPermission`:

```typescript
sdk.addRoute({
  path: 'cms/pages',
  name: 'cms-admin-pages',
  component: () => import('./views/CmsPageList.vue'),
  meta: { requiredPermission: 'cms.pages.view' },
});
```

The router guard checks permissions before navigation:

```typescript
router.beforeEach((to, _from, next) => {
  const requiredPermission = to.meta.requiredPermission;
  if (requiredPermission && !authStore.hasPermission(requiredPermission)) {
    next({ name: 'forbidden', query: { required: requiredPermission } });
    return;
  }
  next();
});
```

### Frontend (Sidebar Filtering)

Sidebar nav items have `requiredPermission`. Items without permission are hidden:

```typescript
extensionRegistry.register('shop-admin', {
  sectionItems: {
    sales: [{
      label: 'Shop',
      to: '/admin/shop/products',
      requiredPermission: 'shop.products.view',
      children: [
        { label: 'Products', to: '...', requiredPermission: 'shop.products.view' },
        { label: 'Orders', to: '...', requiredPermission: 'shop.orders.view' },
      ],
    }],
  },
});
```

### Frontend (Dashboard)

Dashboard widgets are conditionally rendered based on permissions:

```vue
<template v-if="authStore.hasPermission('analytics.view')">
  <!-- Analytics cards -->
</template>
```

## Plugin Integration

### Declaring Permissions (Backend)

Each backend plugin declares its permissions in `admin_permissions`:

```python
class ShopPlugin(BasePlugin):
    @property
    def admin_permissions(self):
        return [
            {"key": "shop.products.view", "label": "View products", "group": "Shop"},
            {"key": "shop.products.manage", "label": "Manage products", "group": "Shop"},
            {"key": "shop.orders.view", "label": "View orders", "group": "Shop"},
            {"key": "shop.orders.manage", "label": "Manage orders", "group": "Shop"},
            {"key": "shop.configure", "label": "Configure shop", "group": "Shop"},
        ]
```

These permissions automatically appear in the Access Level form's permission matrix.

### Protecting Plugin Routes (Backend)

Plugin routes use the same decorators:

```python
@shop_bp.route("/admin/shop/products", methods=["GET"])
@require_auth
@require_permission("shop.products.view")
def list_products():
    ...
```

### Protecting Plugin Routes (Frontend)

Plugin fe-admin routes include `meta.requiredPermission`:

```typescript
sdk.addRoute({
  path: 'shop/products',
  name: 'shop-products',
  component: () => import('./views/Products.vue'),
  meta: { requiredPermission: 'shop.products.view' },
});
```

Plugin sidebar items include `requiredPermission` — hidden when user lacks the permission.

## Core Permissions

Defined in `vbwd/routes/admin/access.py`:

| Key | Label | Group |
|-----|-------|-------|
| `users.view` | View users | Users |
| `users.manage` | Manage users | Users |
| `invoices.view` | View invoices | Invoices |
| `invoices.manage` | Manage invoices | Invoices |
| `analytics.view` | View analytics | Analytics |
| `settings.view` | View settings | Settings |
| `settings.manage` | Manage settings | Settings |
| `settings.system` | System settings | Settings |

## Permission Matrix UI

The Access Level form (`/admin/settings/access/:id`) shows a permission matrix:

- **Columns**: Bulk checkbox, Resource, View, Manage, Configure
- **Column header checkboxes**: Toggle all permissions in that column
- **Group header checkboxes**: Toggle all view+manage in the group
- **Row checkboxes**: Toggle view+manage for that resource
- **Special permissions section**: Permissions that don't fit the standard pattern

## API Endpoints

| Method | Path | Permission | Purpose |
|--------|------|------------|---------|
| GET | `/admin/access/levels` | `settings.system` | List access levels |
| POST | `/admin/access/levels` | `settings.system` | Create access level |
| GET | `/admin/access/levels/:id` | `settings.system` | Get access level detail |
| PUT | `/admin/access/levels/:id` | `settings.system` | Update access level |
| DELETE | `/admin/access/levels/:id` | `settings.system` | Delete access level |
| GET | `/admin/access/permissions` | `settings.system` | List all available permissions |
| POST | `/admin/access/users/:id/roles` | `settings.system` | Assign access level to user |
| DELETE | `/admin/access/users/:id/roles/:roleId` | `settings.system` | Revoke access level |
| POST | `/admin/access/export` | `settings.system` | Export access levels |
| POST | `/admin/access/import` | `settings.system` | Import access levels |

## Data Model

### Admin Access Levels

```
vbwd_user
  ├── role (ENUM: SUPER_ADMIN, ADMIN, USER, VENDOR)
  └── assigned_roles ──M:N──> vbwd_role (admin access levels)
                                  └── permissions ──M:N──> vbwd_permission

vbwd_role (admin access level)
  ├── name, slug, description
  ├── is_system (protected from deletion)
  └── permissions[] (view, manage, configure per resource)
```

### User Access Levels

```
vbwd_user
  └── assigned_user_access_levels ──M:N──> vbwd_user_access_level
                                              └── permissions ──M:N──> vbwd_permission

vbwd_user_access_level
  ├── name, slug, description
  ├── is_system (protected from deletion)
  ├── linked_plan_slug (auto-assign when user subscribes to this plan)
  └── permissions[] (user-facing permissions from plugins)
```

```
vbwd_permission (shared by both systems)
  ├── name (e.g., "users.view" or "subscription.manage")
  ├── resource (e.g., "users", "subscription")
  └── action (e.g., "view", "manage")
```

---

## User Access Levels (fe-user)

User access levels control feature visibility in the user-facing app (fe-user). Unlike admin access levels, these apply to regular users and are separate from the admin RBAC system.

### How It Differs from Admin Access Levels

| Aspect | Admin Access Levels | User Access Levels |
|--------|--------------------|--------------------|
| Table | `vbwd_role` | `vbwd_user_access_level` |
| Applies to | ADMIN users in fe-admin | All users in fe-user |
| Permissions source | `plugin.admin_permissions` | `plugin.user_permissions` |
| Auto-assignment | Manual only | Plan-linked via `linked_plan_slug` |
| Backend decorator | `@require_permission()` | `@require_user_permission()` |
| Frontend guard | `authStore.hasPermission()` | `authStore.hasUserPermission()` |

### Default User Access Levels (Seeded)

| Level | Slug | Linked Plan | Permissions |
|-------|------|-------------|-------------|
| New User | `new` | (none) | `user.profile.view`, `cms.content.view` |
| Logged In | `logged-in` | `free` | Above + `user.profile.manage`, `subscription.invoices.view`, `subscription.tokens.view` |
| Subscribed Basic | `subscribed-basic` | `basic` | Above + `subscription.manage`, `shop.catalog.view`, `shop.cart.manage`, `booking.calendar.view` |
| Subscribed Pro | `subscribed-pro` | `pro` | Above + `subscription.tokens.manage`, `shop.orders.view`, `booking.bookings.manage`, `booking.bookings.view` |

### User Permission Namespace

Core defines zero user permissions. All user permissions come from plugins via `plugin.user_permissions`:

```
# Subscription plugin
subscription.plans.view         -- View available plans
subscription.manage             -- Change plan, cancel, resubscribe
subscription.invoices.view      -- View own invoices
subscription.tokens.view        -- View token balance
subscription.tokens.manage      -- Purchase token bundles

# User profile (subscription plugin)
user.profile.view               -- View own profile
user.profile.manage             -- Edit name, address, avatar

# Shop plugin
shop.catalog.view               -- Browse product catalog
shop.cart.manage                 -- Add to cart, checkout
shop.orders.view                -- View own order history

# Booking plugin
booking.calendar.view           -- View available slots
booking.bookings.manage         -- Create/cancel own bookings
booking.bookings.view           -- View own booking history

# CMS plugin
cms.content.view                -- View CMS pages
```

### Auto-Assignment via Subscription Events

The subscription plugin auto-assigns access levels when subscriptions change:

```
User subscribes to plan "basic"
  --> subscription.activated event
      --> SubscriptionAccessLevelHandler
          --> Find vbwd_user_access_level where linked_plan_slug = "basic"
          --> Assign "subscribed-basic" level to user

User cancels subscription
  --> subscription.cancelled event
      --> SubscriptionAccessLevelHandler
          --> Revoke plan-linked level
          --> Assign "logged-in" fallback level
```

Any plugin can follow the same pattern by subscribing to events and calling `UserAccessLevelService.assign()` / `.revoke()`.

Admin can manually add/remove user access levels via the admin panel. Manual assignments are never auto-revoked by plugins.

### Backend (API Protection)

User routes are protected with `@require_user_permission`:

```python
@my_bp.route("/api/v1/shop/products", methods=["GET"])
@require_auth
@require_user_permission("shop.catalog.view")
def list_products():
    ...
```

This checks the user's assigned user access levels for the permission.

### Frontend (Route Protection)

fe-user plugin routes use `meta.requiredUserPermission`:

```typescript
sdk.addRoute({
  path: '/shop/products',
  name: 'shop-catalog',
  component: () => import('./views/Catalog.vue'),
  meta: { requiredUserPermission: 'shop.catalog.view' },
});
```

Router guard checks `authStore.hasUserPermission()` before navigation.

### Frontend (Widget Visibility)

Widgets declare required user permissions:

```typescript
sdk.addWidget({
  name: 'booking-calendar',
  component: () => import('./widgets/BookingCalendar.vue'),
  requiredUserPermission: 'booking.calendar.view',
});
```

### Frontend (Button Guards)

Same `canManage` pattern as admin but using user permissions:

```vue
<button v-if="canManage" @click="editProfile()">Edit Profile</button>

<script setup>
const authStore = useAuthStore();
const canManage = computed(() => authStore.hasUserPermission('user.profile.manage'));
</script>
```

### User Access Level API Endpoints

| Method | Path | Permission | Purpose |
|--------|------|------------|---------|
| GET | `/admin/user-access-levels` | `settings.system` | List user access levels |
| POST | `/admin/user-access-levels` | `settings.system` | Create user access level |
| GET | `/admin/user-access-levels/:id` | `settings.system` | Get user access level detail |
| PUT | `/admin/user-access-levels/:id` | `settings.system` | Update user access level |
| DELETE | `/admin/user-access-levels/:id` | `settings.system` | Delete user access level |
| GET | `/admin/user-access-levels/permissions` | `settings.system` | List available user permissions |
| POST | `/admin/users/:id/user-access-levels` | `settings.system` | Assign to user |
| DELETE | `/admin/users/:id/user-access-levels/:levelId` | `settings.system` | Revoke from user |

### Admin UI: Two Tabs

The Access Levels page in fe-admin has two tabs:

```
[Admin Access Levels] [User Access Levels]
```

Both tabs share the same UI pattern: list with bulk checkboxes, Import, Export, Delete Selected, Create New. The User Access Level form has an additional "Linked Plan" dropdown and shows user permissions (not admin permissions) in the permission matrix.
