# Sprint 02c: Booking User Frontend Plugin

**Date:** 2026-03-18
**Status:** Planned
**Repo:** `VBWD-platform/vbwd-fe-user-plugin-booking`
**Overview:** [02-booking-overview.md](02-booking-overview.md)
**Depends on:** [02a-booking-be.md](02a-booking-be.md) (API routes must exist)

---

## Plugin Structure

```
plugins/booking/
├── index.ts                             # bookingPlugin: IPlugin (named export)
├── booking/
│   ├── views/
│   │   ├── BookingCatalogue.vue         # Browse resources by category (public)
│   │   ├── BookingResourceDetail.vue    # Resource detail + availability picker (public)
│   │   ├── BookingForm.vue              # Select slot + custom fields + confirm (auth)
│   │   ├── BookingConfirmation.vue      # Booking confirmed page (auth)
│   │   ├── MyBookings.vue               # User's booking list (auth, dashboard)
│   │   └── BookingDetail.vue            # Single booking detail + cancel (auth, dashboard)
│   ├── stores/
│   │   └── booking.ts                   # Pinia store
│   ├── components/
│   │   ├── SlotPicker.vue               # Date picker + time slot grid
│   │   ├── ResourceCard.vue             # Resource card for catalogue listing
│   │   ├── CustomFieldsForm.vue         # Dynamic form rendered from resource.custom_fields_schema
│   │   └── BookingStatusBadge.vue       # Status chip (confirmed, pending, cancelled, completed)
│   └── composables/
│       └── useAvailability.ts           # Fetch + cache availability for a resource + date
├── locales/
│   ├── en.json
│   ├── de.json
│   └── ru.json
├── tests/
│   ├── unit/
│   │   ├── stores/
│   │   │   └── booking.spec.ts
│   │   ├── components/
│   │   │   ├── SlotPicker.spec.ts
│   │   │   ├── CustomFieldsForm.spec.ts
│   │   │   └── ResourceCard.spec.ts
│   │   └── views/
│   │       ├── BookingCatalogue.spec.ts
│   │       └── MyBookings.spec.ts
│   └── e2e/
│       └── booking-user.spec.ts
└── .github/
    └── workflows/
        └── tests.yml
```

---

## Routes (registered via `sdk.addRoute()`)

| Path | Component | Auth | Description |
|------|-----------|------|-------------|
| `/booking` | BookingCatalogue | No | Browse resources (CMS page with vue-component) |
| `/booking/:slug` | BookingResourceDetail | No | Resource detail + availability calendar |
| `/booking/:slug/book` | BookingForm | Yes | Select slot + fill custom fields + confirm |
| `/booking/confirmation/:id` | BookingConfirmation | Yes | Booking confirmed |
| `/dashboard/bookings` | MyBookings | Yes | User's bookings list |
| `/dashboard/bookings/:id` | BookingDetail | Yes | Booking detail + cancel action |

---

## Plugin Registration

```typescript
import { registerCmsVueComponent } from '../cms/src/registry/vueComponentRegistry';

export const bookingPlugin: IPlugin = {
  name: 'booking',
  version: '1.0.0',
  install(sdk: IPlatformSDK) {
    // ── CMS vue-component widgets (same pattern as GHRM) ──
    // Register components so CmsWidgetRenderer can resolve them by name.
    // ONE widget handles ALL categories/resources dynamically via route params.
    Promise.all([
      import('./booking/views/BookingCatalogue.vue'),
      import('./booking/views/BookingResourceDetail.vue'),
    ]).then(([catalogue, detail]) => {
      registerCmsVueComponent('BookingCatalogue', catalogue.default);
      registerCmsVueComponent('BookingResourceDetail', detail.default);
    });

    // ── CMS routes (public, rendered inside CMS layout) ──
    // These routes load CmsPage.vue which resolves the layout + widgets.
    // The widget reads route.params to fetch the right data.
    sdk.addRoute({
      path: '/booking',
      name: 'booking-catalogue',
      component: () => import('../cms/src/views/CmsPage.vue'),
      props: { slug: 'booking' },
      meta: { requiresAuth: false, cmsLayout: true },
    });
    sdk.addRoute({
      path: '/booking/:slug',
      name: 'booking-resource',
      component: () => import('../cms/src/views/CmsPage.vue'),
      props: { slug: 'booking-resource-detail' },  // template page
      meta: { requiresAuth: false, cmsLayout: true },
    });

    // ── App routes (auth required, inside dashboard layout) ──
    sdk.addRoute({
      path: '/booking/:slug/book',
      name: 'booking-form',
      component: () => import('./booking/views/BookingForm.vue'),
      meta: { requiresAuth: true },
    });
    sdk.addRoute({
      path: '/booking/confirmation/:id',
      name: 'booking-confirmation',
      component: () => import('./booking/views/BookingConfirmation.vue'),
      meta: { requiresAuth: true },
    });
    sdk.addRoute({
      path: '/dashboard/bookings',
      name: 'my-bookings',
      component: () => import('./booking/views/MyBookings.vue'),
      meta: { requiresAuth: true },
    });
    sdk.addRoute({
      path: '/dashboard/bookings/:id',
      name: 'booking-detail',
      component: () => import('./booking/views/BookingDetail.vue'),
      meta: { requiresAuth: true },
    });

    // Translations
    sdk.addTranslations('en', en);
    sdk.addTranslations('de', de);
    sdk.addTranslations('ru', ru);
  },
  activate() { /* no-op */ },
  deactivate() { /* no-op */ },
};
```

---

## CMS Widget Architecture (same pattern as GHRM)

### How it works (no per-category/per-resource CMS pages)

```
User visits /booking
  ↓
Vue Router → CmsPage.vue with props slug="booking"
  ↓
CmsPage fetches page from API → gets layout "booking-catalogue"
  ↓
CmsLayoutRenderer renders areas → area "booking-catalogue" has widget
  ↓
CmsWidgetRenderer resolves content_json.component = "BookingCatalogue"
  ↓
registerCmsVueComponent("BookingCatalogue") → looked up in registry
  ↓
<BookingCatalogue /> renders → fetches ALL categories + resources from API
  ↓
User clicks resource card → navigates to /booking/dr-smith
  ↓
Vue Router → CmsPage.vue with props slug="booking-resource-detail" (template page)
  ↓
CmsLayoutRenderer → BookingResourceDetail widget
  ↓
BookingResourceDetail reads route.params.slug = "dr-smith"
  ↓
Fetches /api/v1/booking/resources/dr-smith + availability
```

### BookingCatalogue.vue (dynamic, handles all categories)

```typescript
// Reads NO route params — fetches all categories and resources
const store = useBookingStore();

onMounted(() => {
  store.fetchCategories();        // GET /api/v1/booking/categories
  store.fetchResources();         // GET /api/v1/booking/resources
});

// Category filter buttons (dynamic from API, not hardcoded)
const selectedCategory = ref<string | null>(null);

const filteredResources = computed(() => {
  if (!selectedCategory.value) return store.resources;
  return store.resources.filter(resource =>
    resource.categories.some(cat => cat.slug === selectedCategory.value)
  );
});
```

### BookingResourceDetail.vue (reads slug from route params)

```typescript
const route = useRoute();
const resourceSlug = computed(() => route.params.slug as string);

watch(resourceSlug, (slug) => {
  store.fetchResourceBySlug(slug);   // GET /api/v1/booking/resources/:slug
}, { immediate: true });

// Availability loaded when user picks a date
function loadAvailability(date: string) {
  store.fetchAvailability(resourceSlug.value, date);
}
```

### Key principle

- **ONE `BookingCatalogue` widget** handles all categories (fetched from API)
- **ONE `BookingResourceDetail` widget** handles all resources (slug from route params)
- **Categories are dynamic** — add a category in admin → appears automatically
- **Resources are dynamic** — add a resource in admin → appears automatically
- **NO per-category CMS pages** — unlike GHRM which creates one page per category slug, booking doesn't need this because categories are just filter buttons on the catalogue widget

---

## Pinia Store (`booking.ts`)

```typescript
state: {
  categories: ResourceCategory[]
  resources: BookableResource[]
  currentResource: BookableResource | null
  availableSlots: AvailableSlot[]
  userBookings: Booking[]
  currentBooking: Booking | null
}

actions: {
  fetchCategories()
  fetchResources(filters?: { category?: string, type?: string })
  fetchResourceBySlug(slug: string)
  fetchAvailability(slug: string, date: string)
  createBooking(resourceSlug: string, data: BookingFormData): Promise<Booking>
  fetchUserBookings()
  fetchBookingDetail(bookingId: string)
  cancelBooking(bookingId: string)
}
```

---

## Payment & Checkout Flow

### Flow: Browse → Select → Book → Pay → Authorize → Charge on completion

```
/booking                    Public: browse catalogue by category
  ↓ click resource
/booking/:slug              Public: resource detail + availability
  ↓ click "Book Now"
/booking/:slug/book         Auth required (redirect to login if not authenticated,
                            same pattern as landing1 → checkout)
  ↓ select slot + fill custom fields + submit
/checkout/:invoice_id       Core checkout page (Stripe/PayPal/YooKassa)
                            Payment is AUTHORIZED (hold), not charged yet
  ↓ payment authorized
/booking/confirmation/:id   Booking confirmed, amount on hold
  ↓ booking time passes, no cancellation
  → Amount CHARGED automatically (backend cron/scheduler)
  ↓ OR: user cancels within grace period
  → Authorization RELEASED, booking cancelled, no charge
```

### Auth Boundary

When unauthenticated user clicks "Book Now" on `/booking/:slug`:
- Redirect to `/login?redirect=/booking/:slug/book` (same as landing1 → checkout pattern)
- After login, user returns to the booking form

### Invoice Integration

- Booking creates an invoice with `LineItemType.CUSTOM` and `metadata` JSON
- Invoice appears in the existing `/dashboard/invoices` page (core invoice list)
- Invoice detail page renders booking metadata (resource name, date/time, custom fields)
- Core invoice detail view checks `line_item.item_type === 'CUSTOM'` and renders `metadata` as key-value pairs

### Payment Authorization vs Charge

```python
# On booking creation:
invoice = create_invoice(user, resource, LineItemType.CUSTOM, metadata={...})
payment = authorize_payment(invoice)  # Hold amount, don't charge
booking.status = "confirmed"
booking.invoice_id = invoice.id

# On booking completion (scheduler, after end_at passes):
if booking.status == "confirmed":
    capture_payment(booking.invoice_id)  # Charge the held amount
    booking.status = "completed"

# On cancellation within grace period:
if booking.status == "confirmed" and within_grace_period:
    release_authorization(booking.invoice_id)  # Release the hold
    booking.status = "cancelled"
```

---

## Dashboard Nav Integration

The booking plugin adds a top-level nav item to the user dashboard:

```typescript
// In install(sdk):
sdk.addNavItem({
  label: t('booking.nav.title'),  // "Bookings"
  to: '/dashboard/bookings',
  icon: 'calendar',
});
```

Dashboard sidebar shows:
```
Dashboard
Subscription
Invoices
Bookings          ← NEW (from booking plugin)
  My Bookings
Tokens
Add-ons
Profile
```

---

## Key Components

### SlotPicker.vue — One Component, Two Modes

The picker auto-detects the mode from the resource configuration:

```typescript
// Mode derived from resource — NOT a prop the parent sets
const pickerMode = computed(() => {
  // slot_duration_minutes set → fixed time slots (doctor, yoga, meeting room)
  // slot_duration_minutes null → date range (hotel, rental)
  return props.resource.slot_duration_minutes ? 'time-slots' : 'date-range';
});
```

**Time slot mode** (`slot_duration_minutes` is set):
- Calendar day picker (single date)
- Grid of available time slots for the selected day
- Each slot shows: start time, end time, available capacity
- Color: available (green), low capacity (yellow), full (grey)

**Date range mode** (`slot_duration_minutes` is null):
- Calendar range picker (check-in → check-out)
- Unavailable dates greyed out
- Shows price per night × number of nights

**Both modes emit the same event:**
```typescript
emit('selected', { start_at: DateTime, end_at: DateTime });
```

The parent `BookingForm.vue` doesn't care which mode was used — it receives `start_at` and `end_at` regardless.

### CustomFieldsForm.vue

- Renders form fields from `resource.custom_fields_schema` JSON
- Supported field types: `string`, `text`, `integer`, `boolean`, `select`
- Validates required fields
- Emits `fields-changed` with `{ [field_id]: value }`

### ResourceCard.vue

- Image, name, type badge, price with unit
- Capacity indicator (if > 1: "20 spots available")
- Category chips
- "Book now" button → navigates to resource detail

---

## Testing

### Unit Tests (~25 tests)

```
tests/unit/
├── stores/
│   └── booking.spec.ts                  (~10 tests)
│       ├── test_fetchResources_populates_state
│       ├── test_fetchAvailability_returns_slots
│       ├── test_createBooking_calls_api_and_returns_booking
│       ├── test_cancelBooking_updates_status
│       ├── test_fetchUserBookings
│       └── test_fetchCategories
├── components/
│   ├── SlotPicker.spec.ts              (~6 tests)
│   │   ├── test_renders_available_slots
│   │   ├── test_disables_full_slots
│   │   ├── test_emits_slot_selected
│   │   ├── test_respects_max_advance_days
│   │   └── test_date_range_mode_for_flexible_resources
│   ├── CustomFieldsForm.spec.ts        (~5 tests)
│   │   ├── test_renders_fields_from_schema
│   │   ├── test_validates_required_fields
│   │   ├── test_renders_select_with_options
│   │   ├── test_emits_fields_changed
│   │   └── test_renders_boolean_as_checkbox
│   └── ResourceCard.spec.ts            (~4 tests)
│       ├── test_renders_name_and_price
│       ├── test_shows_capacity_indicator
│       ├── test_shows_type_badge
│       └── test_book_now_navigates
└── views/
    ├── BookingCatalogue.spec.ts         (~3 tests)
    └── MyBookings.spec.ts               (~3 tests)
```

### E2E Tests (~12 tests)

```
tests/e2e/booking-user.spec.ts
├── test_browse_booking_catalogue
├── test_filter_by_category
├── test_view_resource_detail
├── test_resource_shows_availability_slots
├── test_select_slot_and_fill_form
├── test_submit_booking
├── test_booking_confirmation_page
├── test_my_bookings_list
├── test_booking_detail_page
├── test_cancel_booking
├── test_breadcrumb_navigation
└── test_unauthenticated_redirect_to_login
```

### Run

```bash
# Unit tests
cd vbwd-fe-user
npx vitest run plugins/booking/tests/unit/

# Style
./bin/pre-commit-check.sh --style

# E2E (against platform)
npx playwright test plugins/booking/tests/e2e/ --config=playwright.platform.config.ts
```

---

## UI Style Requirements

All booking user views MUST follow the existing core user design system:

- **Reference pages:** Tarif Plan list (pricing cards), Subscription detail, Invoice list — use the same layout patterns
- **Theme-switcher compatible:** All components MUST work with both light and dark themes. Use CSS custom properties (`var(--vbwd-*)`) exclusively — no hardcoded colors
- **Inherit global styles** from `vbwd-fe-core` — buttons, inputs, cards, badges, tables, modals all come from the core component library
- **Dashboard pages** (`/dashboard/bookings`, `/dashboard/bookings/:id`): same layout as existing dashboard pages (Subscription, Invoices, Profile) — sidebar nav, content area, breadcrumbs
- **Public CMS pages** (`/booking`, `/booking/:slug`): rendered inside CMS layout — no custom page chrome, the layout provides header/footer/nav
- **Mobile-responsive:** Same breakpoints as core (the core styles handle this — don't override)
- **No custom CSS that duplicates core** — if a style exists in `vbwd-fe-core`, use it

### Component style references:

| Booking Component | Reference Core Component |
|------------------|------------------------|
| ResourceCard | Tarif Plan pricing card |
| SlotPicker | Date inputs + button grid (core form elements) |
| CustomFieldsForm | Core form pattern (labels, inputs, validation messages) |
| BookingStatusBadge | Subscription/Invoice status badges |
| MyBookings list | Invoice list table |
| BookingDetail | Subscription detail page layout |

---

## Acceptance Criteria

1. `./bin/pre-commit-check.sh --unit` green
2. GitHub Actions CI green on `vbwd-fe-user-plugin-booking`
3. User can browse resources at `/booking` (public, no auth)
4. User can view resource detail with availability at `/booking/:slug` (public)
5. User can select slot, fill custom fields, and create booking (auth required)
6. User can view their bookings at `/dashboard/bookings`
7. User can cancel a booking within grace period
8. Booking creates an invoice with `CUSTOM` line item visible in user's invoice list
9. CMS page at `/booking` renders `BookingCatalogue` vue-component
10. All text uses i18n (`$t()` keys), 3 locales (en, de, ru)
11. SlotPicker handles both fixed-duration (specialist) and flexible-duration (hotel) resources
12. Unauthenticated user clicking "Book Now" → redirect to login → return to booking form
13. After booking, user redirected to core checkout page for payment authorization
14. Booking invoice visible in existing `/dashboard/invoices` with metadata rendered
15. Dashboard sidebar shows "Bookings" nav item with "My Bookings" sub-item
