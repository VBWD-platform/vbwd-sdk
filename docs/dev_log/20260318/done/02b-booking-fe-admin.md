# Sprint 02b: Booking Admin Frontend Plugin

**Date:** 2026-03-18
**Status:** Planned
**Repo:** `VBWD-platform/vbwd-fe-admin-plugin-booking`
**Overview:** [02-booking-overview.md](02-booking-overview.md)
**Depends on:** [02a-booking-be.md](02a-booking-be.md) (API routes must exist)

---

## Plugin Structure

```
plugins/booking/
├── index.ts                             # bookingAdminPlugin: IPlugin (named export)
├── admin-config.json                    # Nav sections, dashboard widget config
├── booking/
│   ├── views/
│   │   ├── BookingDashboard.vue         # Today's bookings, stats, upcoming
│   │   ├── BookingList.vue              # All bookings with filters (date, status, resource)
│   │   ├── BookingDetail.vue            # Single booking + admin actions (confirm, cancel, complete, no_show)
│   │   ├── ResourceList.vue             # Resource CRUD list
│   │   ├── ResourceForm.vue             # Create/edit resource (availability editor, custom fields schema)
│   │   ├── CategoryList.vue             # Category management
│   │   └── CategoryForm.vue             # Create/edit category
│   ├── stores/
│   │   ├── bookingAdmin.ts              # Pinia store: bookings CRUD, filters, stats
│   │   └── resourceAdmin.ts             # Pinia store: resources + categories CRUD
│   └── components/
│       ├── AvailabilityEditor.vue        # Visual weekly schedule editor (drag time blocks)
│       ├── CustomFieldsSchemaEditor.vue  # Define custom fields for booking form
│       └── BookingCalendar.vue           # Calendar view of bookings (day/week/month)
├── locales/
│   ├── en.json
│   ├── de.json
│   └── ru.json
├── tests/
│   ├── unit/
│   │   ├── stores/
│   │   │   ├── bookingAdmin.spec.ts
│   │   │   └── resourceAdmin.spec.ts
│   │   └── views/
│   │       ├── BookingList.spec.ts
│   │       ├── ResourceForm.spec.ts
│   │       └── BookingDashboard.spec.ts
│   └── e2e/
│       └── booking_admin.spec.ts
└── .github/
    └── workflows/
        └── tests.yml
```

---

## Admin Config (`admin-config.json`)

```json
{
  "booking_admin": {
    "nav_section": {
      "id": "booking",
      "label": "Bookings",
      "items": [
        { "label": "Dashboard", "to": "/admin/booking" },
        { "label": "All Bookings", "to": "/admin/booking/list" },
        { "label": "Resources", "to": "/admin/booking/resources" },
        { "label": "Categories", "to": "/admin/booking/categories" }
      ]
    },
    "dashboard_widget": true
  }
}
```

---

## Routes (registered via `sdk.addRoute()`)

| Path | Component | Description |
|------|-----------|-------------|
| `/admin/booking` | BookingDashboard | Today's overview + stats |
| `/admin/booking/list` | BookingList | All bookings with filters |
| `/admin/booking/:id` | BookingDetail | Single booking + admin actions |
| `/admin/booking/resources` | ResourceList | All resources |
| `/admin/booking/resources/new` | ResourceForm | Create resource |
| `/admin/booking/resources/:id` | ResourceForm | Edit resource |
| `/admin/booking/categories` | CategoryList | All categories |
| `/admin/booking/categories/new` | CategoryForm | Create category |
| `/admin/booking/categories/:id` | CategoryForm | Edit category (includes capture + cancellation policy) |

---

## Extension Registry

```typescript
// In install(sdk):
extensionRegistry.register('booking', {
  navSections: [{
    id: 'booking',
    label: t('booking.nav.title'),
    items: [
      { label: t('booking.nav.dashboard'), to: '/admin/booking' },
      { label: t('booking.nav.bookings'), to: '/admin/booking/list' },
      { label: t('booking.nav.resources'), to: '/admin/booking/resources' },
      { label: t('booking.nav.categories'), to: '/admin/booking/categories' },
    ],
  }],
});
```

---

## Pinia Stores

### `bookingAdmin.ts`

```typescript
actions: {
  fetchBookings(filters: { date?, status?, resource_id? })
  fetchBookingDetail(bookingId: string)
  updateBookingStatus(bookingId: string, status: string, adminNotes?: string)
  fetchDashboardStats()
}
state: {
  bookings: Booking[]
  currentBooking: Booking | null
  dashboardStats: { today: number, upcoming: number, revenue: number }
  filters: BookingFilters
  pagination: { page: number, totalPages: number }
}
```

### `resourceAdmin.ts`

```typescript
actions: {
  fetchResources()
  fetchResourceDetail(resourceId: string)
  createResource(data: ResourceFormData)
  updateResource(resourceId: string, data: ResourceFormData)
  deleteResource(resourceId: string)
  fetchCategories()
  createCategory(data: CategoryFormData)
  updateCategory(categoryId: string, data: CategoryFormData)
  deleteCategory(categoryId: string)
}
state: {
  resources: BookableResource[]
  currentResource: BookableResource | null
  categories: ResourceCategory[]
}
```

---

## Key Components

### AvailabilityEditor.vue

Visual weekly schedule editor:
- 7 rows (Mon-Sun), each with time blocks
- Drag to add/resize availability windows
- Exception dates list with add/remove
- Config: lead_time, max_advance_days, buffer_minutes
- Outputs JSON matching `resource.availability` schema

### CustomFieldsSchemaEditor.vue

Dynamic form builder:
- Add field: name, label, type (string, text, integer, boolean, select), required flag
- Reorder fields via drag
- Preview the form as user would see it
- Outputs JSON matching `resource.custom_fields_schema`

### BookingCalendar.vue

Calendar view:
- Day / week / month toggle
- Color-coded by status (confirmed=green, pending=yellow, cancelled=red)
- Click booking to navigate to detail
- Filter by resource

### BookingDetail.vue — Admin Actions

Admin actions on a booking detail page:

| Action | Condition | Effect |
|--------|-----------|--------|
| Confirm | Status == pending | Set status to confirmed |
| Mark Complete | Status == confirmed, end_at passed | Set status to completed |
| Mark No-Show | Status == confirmed, end_at passed | Set status to no_show |
| Cancel (user policy) | Status == confirmed | Refund per cancellation policy tiers. Admin is bound by the same policy as user. |
| Cancel by Provider | Status == confirmed | Admin enters reason → triggers `booking.cancelled_by_provider` event → 100% refund always. Used when doctor sick, room unavailable, etc. |

**Cancel by Provider** is a separate button/action from regular Cancel. It requires a `reason` text field (mandatory).

### CategoryForm.vue — Capture & Cancellation Policy

The category form includes two config sections (override global defaults):

**Capture Policy:**
- Trigger: dropdown (`immediate` / `on_booking_completed` / `before_start`)
- Days before start: number input (visible when trigger = `before_start`)

**Cancellation Policy:**
- Tiered refund rules: editable list
  - Each tier: `days_before_start` (number) + `refund_percent` (0-100%)
  - Add / remove tiers
  - Sorted by days descending automatically
- Preview: visual timeline showing refund tiers

---

## Testing

### Unit Tests (~20 tests)

```
tests/unit/
├── stores/
│   ├── bookingAdmin.spec.ts             (~8 tests)
│   │   ├── test_fetchBookings_populates_state
│   │   ├── test_updateBookingStatus_calls_api
│   │   ├── test_fetchDashboardStats
│   │   └── test_filters_applied_to_api_call
│   └── resourceAdmin.spec.ts            (~8 tests)
│       ├── test_fetchResources
│       ├── test_createResource
│       ├── test_updateResource
│       ├── test_deleteResource
│       └── test_fetchCategories
└── views/
    ├── BookingList.spec.ts              (~2 tests)
    ├── ResourceForm.spec.ts             (~2 tests)
    └── BookingDashboard.spec.ts         (~2 tests)
```

### E2E Tests (~10 tests)

```
tests/e2e/booking_admin.spec.ts
├── test_navigate_to_booking_dashboard
├── test_dashboard_shows_stats
├── test_create_resource_with_availability
├── test_edit_resource_custom_fields
├── test_create_category
├── test_view_booking_list
├── test_filter_bookings_by_status
├── test_view_booking_detail
├── test_change_booking_status
└── test_sidebar_shows_booking_section
```

### Run

```bash
# Unit tests
cd vbwd-fe-admin
npx vitest run plugins/booking/tests/unit/

# Style
./bin/pre-commit-check.sh --style

# E2E (against platform)
npx playwright test plugins/booking/tests/e2e/ --config=playwright.platform.config.ts
```

---

## CMS Widget Management (admin side)

The admin plugin does NOT manage CMS widgets directly — CMS widget/layout management is handled by the `cms-admin` plugin. The booking admin plugin only manages **booking-specific data**:

- Resource CRUD (name, type, capacity, price, availability schedule, custom fields schema)
- Category CRUD (name, slug, parent, image)
- Booking management (status changes, admin notes)

The CMS widgets (`BookingCatalogue`, `BookingResourceDetail`) are created once by the backend `populate_db.py` and rendered by the fe-user CMS system. The admin doesn't need to configure them — they are fully dynamic and fetch data from the booking API based on route params.

**What the admin controls:**
- Create/edit/delete booking resources → automatically appear in the catalogue widget
- Create/edit/delete booking categories → automatically appear as filter buttons
- Change resource availability → automatically reflected in the slot picker

**What the admin does NOT need to do:**
- Create CMS pages per category or per resource
- Configure CMS widgets or layouts
- Manage breadcrumbs (automatic from CMS breadcrumb widget)

---

## UI Style Requirements

All booking admin views MUST follow the existing core admin design system:

- **Reference pages:** Tarif Plan list (`Plans.vue`) and Plan edit detail (`PlanForm.vue`) — use the same layout, table styles, form patterns, button styles, card layouts
- **Tables:** Same structure as Plans/Invoices/Users tables (header, sortable columns, pagination, status badges)
- **Forms:** Same pattern as PlanForm (sections, labels, inputs, select, toggle, save/cancel buttons)
- **Cards/Stats:** Same pattern as Dashboard cards (icon + number + label)
- **Inherit global admin styles** from `vbwd-fe-core` — do NOT create custom CSS classes that duplicate existing ones
- **Use CSS custom properties** (`var(--vbwd-*)`) from the core design system for all colors, spacing, typography
- **No hardcoded colors/fonts** — everything via CSS variables for theme consistency

---

## Acceptance Criteria

1. `./bin/pre-commit-check.sh --unit` green
2. GitHub Actions CI green on `vbwd-fe-admin-plugin-booking`
3. Sidebar shows Booking section with 4 nav items
4. Admin can CRUD resources with availability schedule + custom fields
5. Admin can CRUD categories (flat or nested)
6. Admin can view/filter/update bookings
7. Dashboard shows today's bookings, upcoming count, revenue
8. All views use i18n (`$t()` keys)
