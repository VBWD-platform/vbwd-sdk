# Sprint 17 — User Access Levels (fe-user)

**Status:** Planned
**Date:** 2026-04-06
**Principles:** TDD-first · SOLID · Liskov · DI · DRY · Clean Code · No over-engineering · Core agnostic · Event-driven
**Pre-commit:** `pre-commit-check.sh --full` must pass after every sub-sprint

---

## Summary

Extend the access level system to the user-facing app. Admin configures user access levels that control what fe-user features/widgets/routes are visible and accessible. Plans auto-assign default levels; admin can override.

---

## Decisions

| Question | Answer |
|----------|--------|
| Auto-assign from plans | Both: plans auto-assign, admin can override |
| Plan-to-level mapping | One-to-many: one plan can trigger multiple access levels |
| Enforcement | Full stack: backend API + frontend routes + widget visibility |
| Data model | Separate `vbwd_user_access_level` table (independent from admin roles) |
| Default levels | Plan-linked: new, logged-in, subscribed-basic, subscribed-pro |
| Anonymous visitors | Implicit "new" level — treated as having "new" access level |
| Anonymous implementation | Server-side: API pre-filters widget visibility, frontend doesn't need "new" level logic |
| Widget visibility | Multi-select: admin picks multiple levels per widget slot, user sees if they have ANY |
| Navigation menu | Filtered by level (like admin sidebar) — items hidden if no permission |
| Manual vs auto assignment | No distinction — plugin only revokes levels it linked via plan slug |
| User permissions source | Plugins only — core defines zero user permissions, everything from plugins |

---

## Data Model

### New table: `vbwd_user_access_level`

```
vbwd_user_access_level
├── id (UUID PK)
├── name (VARCHAR 100, UNIQUE) — "New User", "Logged In", "Subscribed Basic"
├── slug (VARCHAR 100, UNIQUE) — "new", "logged-in", "subscribed-basic"
├── description (VARCHAR 500)
├── is_system (BOOLEAN) — seeded levels cannot be deleted
├── linked_plan_slug (VARCHAR 100, NULLABLE) — auto-assign when user subscribes to this plan
├── created_at, updated_at, version
```

### Association table: `vbwd_user_access_level_permissions`

```
vbwd_user_access_level_permissions
├── user_access_level_id (FK → vbwd_user_access_level)
├── permission_id (FK → vbwd_permission)
```

Reuses existing `vbwd_permission` table — same permission format (`resource.action`).

### Association table: `vbwd_user_user_access_levels`

```
vbwd_user_user_access_levels
├── user_id (FK → vbwd_user)
├── user_access_level_id (FK → vbwd_user_access_level)
```

Multiple levels per user (union of permissions, same as admin).

---

## User Permission Namespace

**Core defines zero user permissions.** All user permissions come from plugins via `plugin.user_permissions`. This keeps core fully agnostic.

```
# Subscription plugin
subscription.plans.view         — View available plans
subscription.manage             — Change plan, cancel, resubscribe
subscription.invoices.view      — View own invoices
subscription.tokens.view        — View token balance
subscription.tokens.manage      — Purchase token bundles

# User profile plugin (or subscription plugin)
user.profile.view               — View own profile
user.profile.manage             — Edit name, address, avatar

# Shop plugin
shop.catalog.view               — Browse product catalog
shop.cart.manage                 — Add to cart, checkout
shop.orders.view                — View own order history

# Booking plugin
booking.calendar.view           — View available slots
booking.bookings.manage         — Create/cancel own bookings
booking.bookings.view           — View own booking history

# CMS plugin
cms.content.view                — View CMS pages (public by default)
```

---

## Default Access Levels (Seeded)

| Level | Slug | Linked Plan | Permissions |
|-------|------|-------------|-------------|
| New User | `new` | (none — no plan) | `user.profile.view`, `cms.content.view` |
| Logged In | `logged-in` | `free` | Above + `user.profile.manage`, `user.invoices.view`, `user.tokens.view` |
| Subscribed Basic | `subscribed-basic` | `basic` | Above + `user.subscription.view`, `shop.catalog.view`, `shop.cart.manage`, `booking.calendar.view` |
| Subscribed Pro | `subscribed-pro` | `pro` | Above + `user.subscription.manage`, `user.tokens.manage`, `shop.orders.view`, `booking.bookings.manage`, `booking.bookings.view` |

---

## Auto-Assignment Flow

**Core is agnostic.** Core provides the model + assign/revoke API. Plugins handle their own event-driven assignment.

```
SUBSCRIPTION PLUGIN (not core):

User subscribes to plan "basic"
  │
  ├── SubscriptionActivatedEvent (plugin event)
  │     └── SubscriptionAccessLevelHandler (plugin handler)
  │           ├── Find vbwd_user_access_level where linked_plan_slug = "basic"
  │           ├── Call core: assign_user_access_level(user_id, level_id)
  │           └── Call core: revoke previous plan-linked levels (upgrade path)
  │
  └── User now has "subscribed-basic" permissions

User cancels subscription
  │
  ├── SubscriptionCancelledEvent (plugin event)
  │     └── SubscriptionAccessLevelHandler (plugin handler)
  │           ├── Call core: revoke plan-linked level
  │           └── Call core: assign "logged-in" fallback level
```

**Any plugin can do the same:**
- Booking plugin → assign level on first booking
- Shop plugin → assign level on first purchase
- Core just provides: `assign_user_access_level()` and `revoke_user_access_level()`

Admin override: admin can manually add/remove user access levels via the admin panel. Manual assignments are never auto-revoked by plugins.

---

## Admin UI

### Access Levels page — Two tabs

```
┌─────────────────────────────────────────────────┐
│  Access Levels                                   │
│                                                  │
│  [Admin Access Levels] [User Access Levels]      │
│  ────────────────────────────────────────────── │
│                                                  │
│  ☐  Name          Slug              Linked Plan  │
│  ☐  New User      new               —            │
│  ☐  Logged In     logged-in         free         │
│  ☐  Sub Basic     subscribed-basic  basic        │
│  ☐  Sub Pro       subscribed-pro    pro          │
│                                                  │
│  [Import] [Export] [Delete Selected]             │
│  [+ New User Access Level]                       │
└─────────────────────────────────────────────────┘
```

Both tabs have: bulk checkboxes, Import, Export, Delete Selected, Create New.
All behind `settings.system` permission (same as admin access levels).

### User Access Level Form

Same as admin access level form but:
- Additional field: "Linked Plan" dropdown (optional — select from available plans)
- Permission matrix shows USER permissions (not admin permissions)
- Plugins declare `user_permissions` (separate from `admin_permissions`)

---

## fe-user Enforcement

### Backend (API)

New decorator for user routes:

```python
@require_user_permission("shop.catalog.view")
def list_products():
    ...
```

Checks user's assigned user access levels for the permission. Works like `@require_permission` but checks `vbwd_user_user_access_levels` instead of `vbwd_user_roles`.

### Frontend (Routes)

fe-user plugin routes get `meta.requiredUserPermission`:

```typescript
sdk.addRoute({
  path: '/shop/products',
  name: 'shop-catalog',
  component: () => import('./views/Catalog.vue'),
  meta: { requiredUserPermission: 'shop.catalog.view' },
});
```

Router guard checks `authStore.hasUserPermission()`.

### Frontend (Widgets)

Widgets declare required user permission:

```typescript
sdk.addWidget({
  name: 'booking-calendar',
  component: () => import('./widgets/BookingCalendar.vue'),
  requiredUserPermission: 'booking.calendar.view',
});
```

Dashboard/pages only render widgets the user has permission for.

### Frontend (Buttons)

Same `canManage` pattern as admin:

```vue
<button v-if="canManage" @click="editProfile()">Edit Profile</button>
```

Where `canManage = authStore.hasUserPermission('user.profile.manage')`.

---

## Plugin Integration

### Backend: Declaring user permissions

```python
class ShopPlugin(BasePlugin):
    @property
    def user_permissions(self):
        return [
            {"key": "shop.catalog.view", "label": "Browse catalog", "group": "Shop"},
            {"key": "shop.cart.manage", "label": "Add to cart & checkout", "group": "Shop"},
            {"key": "shop.orders.view", "label": "View order history", "group": "Shop"},
        ]
```

### Frontend: Registering with permissions

```typescript
// fe-user plugin
sdk.addRoute({
  path: '/shop',
  component: () => import('./views/Shop.vue'),
  meta: { requiredUserPermission: 'shop.catalog.view' },
});
```

---

## Implementation Sub-Sprints

### 17a — Backend: Model + Migration + Repository

- `UserAccessLevel` model
- `vbwd_user_access_level` + association tables in migration
- `UserAccessLevelRepository`
- `UserAccessLevelService` (CRUD + assign/revoke)
- `User.user_access_levels` relationship
- `User.has_user_permission()` method
- `User.effective_user_permissions` property
- `@require_user_permission` decorator
- Seed 4 default levels in `install_demo_data.py`

### 17b — Subscription Plugin: Auto-Assignment via Events

- `SubscriptionAccessLevelHandler` in `plugins/subscription/` (NOT core)
- Listens to plugin's own events:
  - `subscription.activated` → call core assign API with plan-linked level
  - `subscription.cancelled` → call core revoke API, assign fallback
  - `subscription.changed` → swap levels
- Core provides: `UserAccessLevelService.assign(user_id, level_id)` / `.revoke(user_id, level_id)`
- `BasePlugin.user_permissions` property added to core (default: empty list)

### 17c — Backend: Admin API for User Access Levels

- `GET /admin/user-access-levels` — list
- `POST /admin/user-access-levels` — create
- `GET /admin/user-access-levels/:id` — detail
- `PUT /admin/user-access-levels/:id` — update
- `DELETE /admin/user-access-levels/:id` — delete
- `POST /admin/user-access-levels/export` — export
- `POST /admin/user-access-levels/import` — import
- `GET /admin/user-access-levels/permissions` — list available user permissions
- `POST /admin/users/:id/user-access-levels` — assign to user
- `DELETE /admin/users/:id/user-access-levels/:levelId` — revoke
- All protected with `@require_permission("settings.system")`

### 17d — Frontend: Admin UI (Two Tabs)

- Refactor AccessLevels.vue into tabbed view (Admin / User tabs)
- User Access Levels list with bulk checkboxes, Import, Export, Delete
- User Access Level Form with linked-plan dropdown + user permission matrix
- UserEdit.vue: show user access levels section (separate from admin access levels)
- All behind `canManage` with `settings.system`

### 17e — Frontend: fe-user Permission Engine

- Update fe-core auth store: `user_permissions` field, `hasUserPermission()` getter
- Login response includes `user_permissions` from user access levels
- fe-user router guard checks `meta.requiredUserPermission`
- Sidebar/nav filtering by user permission
- Widget visibility by user permission

### 17f — Frontend: fe-user Plugin Integration

- Each fe-user plugin adds `meta.requiredUserPermission` to routes
- Dashboard widgets conditionally rendered
- Button guards (`v-if="canManage"` pattern) on user-facing forms
- Subscription plugin aware of access level changes

### 17g — Tests + Pre-commit

- Backend unit tests: model, service, auto-assignment, decorator
- Playwright E2E: user with basic plan sees basic features, user with pro sees more
- `pre-commit-check.sh --full`

---

## CMS Content Access Level Restrictions

### CMS Pages — Optional Access Level Restriction

CMS pages can be optionally restricted to one or more user access levels. If set, only users with a matching level can view the page. Public pages (no restriction) are visible to everyone including anonymous visitors.

**Data model:** New association table `cms_page_access_levels`:
```
cms_page_access_levels
├── page_id (FK → cms_page)
├── user_access_level_id (FK → vbwd_user_access_level)
```

Empty = public page. One or more entries = restricted to users with ANY of those levels.

**Admin UI:** On the CMS page editor, a multi-select "Visible to" field listing all user access levels. Default: empty (everyone).

**API:** `GET /api/v1/cms/pages/:slug` — server checks user's access levels. Returns 403 if restricted page and user lacks required level. Anonymous users only see unrestricted pages.

---

## CMS Widget Access Level Condition

### Admin: Layout Editor — Widget Visibility Condition

On the CMS layout editor, when admin places a widget into a layout area, each widget slot gets an optional **"Visible to"** dropdown:

```
┌─────────────────────────────────────────┐
│  Layout Area: sidebar                    │
│                                          │
│  Widget: Booking Calendar                │
│  Visible to: [Subscribed Basic ▼]        │
│                                          │
│  Widget: Promotions Banner               │
│  Visible to: [Everyone ▼]               │
│                                          │
│  Widget: VIP Support Chat                │
│  Visible to: [Subscribed Pro ▼]          │
└─────────────────────────────────────────┘
```

Options: "Everyone" (default), or multi-select from `vbwd_user_access_level`. Widget shows if user has ANY of the selected levels.

### Data Model

New association table `cms_widget_area_access_levels`:
```
cms_widget_area_access_levels
├── widget_area_id (FK → cms layout-widget assignment)
├── user_access_level_id (FK → vbwd_user_access_level)
```

Empty = visible to everyone. One or more entries = visible only to users with ANY of those levels.

### fe-user Rendering (Server-Side)

API pre-filters widgets based on the requesting user's access levels:
```
GET /api/v1/cms/layouts/:id → returns only widgets the caller can see
  - Anonymous → "new" level → sees widgets tagged "new" + untagged
  - Logged-in → sees widgets tagged "logged-in" + "new" + untagged
  - Subscribed-basic → sees widgets tagged "subscribed-basic" + lower + untagged
```

Frontend renders whatever the API returns — no client-side permission check needed for widgets.

### Populate DB

Seed a demo widget in `populate_db`:
- Widget "Booking Quick Reserve" on a resource page layout
- `required_user_access_level_id` → "subscribed-basic"
- Only visible to users with "subscribed-basic" or higher

---

## Playwright E2E Test Scenarios

### Test 1: Anonymous user sees public menu only
```
- Visit homepage (no login)
- Sidebar/header shows: Home, Pricing, Login
- Does NOT show: Dashboard, My Bookings, My Orders
```

### Test 2: Logged-in user (free plan) sees expanded menu
```
- Login as user with "logged-in" access level
- Header shows: Dashboard, Profile, Invoices, Logout
- Does NOT show: My Bookings, My Orders (no subscription permissions)
```

### Test 3: Subscribed Basic user sees subscription features
```
- Login as user with "subscribed-basic" access level
- Header shows: Dashboard, Shop, Bookings, Profile, Invoices, Logout
- Can browse catalog, view booking calendar
- Cannot: manage bookings (no booking.bookings.manage)
```

### Test 4: Subscribed Pro user sees full features
```
- Login as user with "subscribed-pro" access level
- All menu items visible
- Can create bookings, view order history, manage tokens
```

### Test 5: Widget visibility by access level
```
- Visit a booking resource page as anonymous → "Booking Quick Reserve" widget NOT shown
- Login as "logged-in" user → widget NOT shown (no subscribed-basic level)
- Login as "subscribed-basic" user → widget IS shown
- Screenshot proof of each state
```

### Test 6: API enforcement
```
- Login as "logged-in" user (no shop permissions)
- POST /api/v1/user/cart → 403 (no shop.cart.manage)
- Login as "subscribed-basic" user
- POST /api/v1/user/cart → 200 (has shop.cart.manage)
```

### Test 7: Admin manages user access levels
```
- Login as super-admin
- Navigate to Access Levels → User Access Levels tab
- Create new level "VIP" with all permissions
- Assign to a test user
- Login as that user → sees all features
- Cleanup: delete VIP level
```

---

## Not in Scope

- Per-widget admin drag-and-drop configuration
- A/B testing based on access levels
- Temporary access level grants (time-limited)
- Access level marketplace
