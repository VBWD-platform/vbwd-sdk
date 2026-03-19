# Sprint 02a: Booking Backend Plugin

**Date:** 2026-03-18
**Status:** Planned
**Repo:** `VBWD-platform/vbwd-plugin-booking`
**Overview:** [02-booking-overview.md](02-booking-overview.md)

---

## Prerequisite: Core Change

Add `CUSTOM` line item type + `metadata` column to core (in `vbwd-backend`).

**Files to modify:**

1. `vbwd/models/enums.py` — add `CUSTOM = "CUSTOM"` to `LineItemType`
2. `vbwd/models/invoice_line_item.py` — add `metadata = db.Column(db.JSON, nullable=True, default=dict)`
3. `vbwd/models/invoice_line_item.py` — update `to_dict()` to include `metadata`
4. `alembic/versions/YYYYMMDD_add_custom_line_item_type.py` — migration

**Tests (TDD — write first):**
- Test `CUSTOM` type creation
- Test `metadata` JSON serialization/deserialization
- Test existing `SUBSCRIPTION`, `TOKEN_BUNDLE`, `ADD_ON` types still work

**Acceptance:** `bin/pre-commit-check.sh --quick` green, no regressions

---

## Database Tables (prefix: `booking_`)

```sql
booking_resource_category
├── id              UUID PK (BaseModel)
├── name            VARCHAR(255) NOT NULL
├── slug            VARCHAR(255) UNIQUE INDEX
├── description     TEXT NULL
├── image_url       VARCHAR(512) NULL
├── parent_id       UUID FK → booking_resource_category.id NULL
├── config          JSON NULL DEFAULT '{}'           -- capture_policy + cancellation_policy (overrides global)
├── sort_order      INTEGER DEFAULT 0
├── is_active       BOOLEAN DEFAULT TRUE
├── created_at, updated_at, version (BaseModel)

booking_resource
├── id              UUID PK (BaseModel)
├── name            VARCHAR(255) NOT NULL
├── slug            VARCHAR(255) UNIQUE INDEX
├── description     TEXT NULL
├── resource_type   VARCHAR(100) NOT NULL INDEX    -- "specialist", "room", "space", "seat"
├── capacity        INTEGER NOT NULL DEFAULT 1
├── slot_duration_minutes  INTEGER NULL             -- NULL = flexible (per night)
├── price           NUMERIC(10,2) NOT NULL
├── currency        VARCHAR(3) DEFAULT 'EUR'
├── price_unit      VARCHAR(50) DEFAULT 'per_slot'  -- per_slot, per_night, per_hour, per_seat
├── availability    JSON NOT NULL DEFAULT '{}'       -- weekly schedule + exceptions
├── custom_fields_schema  JSON NULL                  -- merchant-defined form fields
├── image_url       VARCHAR(512) NULL
├── config          JSON NULL DEFAULT '{}'           -- confirmation_mode, cancellation_hours, etc.
├── is_active       BOOLEAN DEFAULT TRUE
├── sort_order      INTEGER DEFAULT 0
├── created_at, updated_at, version

booking_resource_category_link
├── resource_id     UUID FK → booking_resource.id PK
├── category_id     UUID FK → booking_resource_category.id PK

booking
├── id              UUID PK (BaseModel)
├── resource_id     UUID FK → booking_resource.id INDEX
├── user_id         UUID FK → user.id INDEX
├── invoice_id      UUID FK → user_invoice.id NULL INDEX
├── start_at        DATETIME NOT NULL INDEX
├── end_at          DATETIME NOT NULL
├── status          VARCHAR(50) DEFAULT 'confirmed'  -- confirmed, pending, cancelled, completed, no_show
├── quantity        INTEGER DEFAULT 1
├── custom_fields   JSON NULL DEFAULT '{}'            -- user-submitted data
├── notes           TEXT NULL
├── admin_notes     TEXT NULL
├── created_at, updated_at, version
```

---

## Plugin Structure

```
plugins/booking/
├── __init__.py                          # BookingPlugin(BasePlugin)
├── config.json                          # Default plugin configuration
├── booking/                             # Source code (not src/)
│   ├── __init__.py
│   ├── models/
│   │   ├── __init__.py
│   │   ├── resource_category.py         # BookableResourceCategory
│   │   ├── resource.py                  # BookableResource
│   │   └── booking.py                   # Booking
│   ├── repositories/
│   │   ├── __init__.py
│   │   ├── resource_category_repository.py
│   │   ├── resource_repository.py
│   │   └── booking_repository.py
│   ├── services/
│   │   ├── __init__.py
│   │   ├── resource_service.py          # CRUD for resources + categories
│   │   ├── availability_service.py      # Compute available slots (no TimeSlot table)
│   │   ├── booking_service.py           # Create, cancel, reschedule, complete
│   │   └── booking_invoice_service.py   # Create invoices with CUSTOM line items
│   ├── routes.py                        # Public + admin Blueprint
│   └── events.py                        # Event definitions + handlers
├── migrations/
│   └── versions/
│       └── 20260318_create_booking_tables.py
├── populate_db.py                       # Demo data (idempotent)
├── tests/
│   ├── conftest.py                      # Test DB setup (_test suffix)
│   ├── unit/
│   │   ├── services/
│   │   │   ├── test_availability_service.py
│   │   │   ├── test_booking_service.py
│   │   │   ├── test_booking_invoice_service.py
│   │   │   └── test_resource_service.py
│   │   ├── repositories/
│   │   │   ├── test_resource_repository.py
│   │   │   └── test_booking_repository.py
│   │   └── models/
│   │       ├── test_resource.py
│   │       └── test_booking.py
│   └── integration/
│       ├── test_booking_api.py
│       └── test_availability_api.py
└── .github/
    └── workflows/
        └── tests.yml
```

---

## Plugin Config (`config.json`)

```json
{
  "booking": {
    "default_timezone": "Europe/Berlin",
    "max_advance_booking_days": 90,
    "min_lead_time_hours": 1,
    "cancellation_grace_period_hours": 24,
    "default_confirmation_mode": "auto",
    "default_slot_duration_minutes": 60,
    "default_buffer_minutes": 15,
    "invoice_prefix": "BK",
    "enable_recurring_bookings": false,
    "max_bookings_per_user_per_day": 5
  }
}
```

---

## API Routes

### Public (auth required)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/booking/categories` | List resource categories |
| GET | `/api/v1/booking/resources` | List active resources (filter: category, type) |
| GET | `/api/v1/booking/resources/:slug` | Resource detail |
| GET | `/api/v1/booking/resources/:slug/availability` | Available slots for date range |
| POST | `/api/v1/booking/bookings` | Create a booking |
| GET | `/api/v1/booking/bookings` | List user's bookings |
| GET | `/api/v1/booking/bookings/:id` | Booking detail |
| POST | `/api/v1/booking/bookings/:id/cancel` | Cancel a booking |

### Admin (admin auth required)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/admin/booking/categories` | List all categories |
| POST | `/api/v1/admin/booking/categories` | Create category |
| PUT | `/api/v1/admin/booking/categories/:id` | Update category |
| DELETE | `/api/v1/admin/booking/categories/:id` | Delete category |
| GET | `/api/v1/admin/booking/resources` | List all resources |
| POST | `/api/v1/admin/booking/resources` | Create resource |
| PUT | `/api/v1/admin/booking/resources/:id` | Update resource |
| DELETE | `/api/v1/admin/booking/resources/:id` | Delete resource |
| GET | `/api/v1/admin/booking/bookings` | List all bookings (filter: date, status, resource) |
| GET | `/api/v1/admin/booking/bookings/:id` | Booking detail + admin notes |
| PUT | `/api/v1/admin/booking/bookings/:id` | Update booking (status, admin_notes) |
| GET | `/api/v1/admin/booking/dashboard` | Stats (today, upcoming, revenue) |

---

## Services (Dependency Injection)

```python
class BookingService:
    def __init__(
        self,
        booking_repository: BookingRepository,
        resource_repository: ResourceRepository,
        availability_service: AvailabilityService,
        invoice_service: BookingInvoiceService,
        event_bus: EventBus,
    ):
        ...

# Factory in routes.py
def _booking_service() -> BookingService:
    return BookingService(
        booking_repository=BookingRepository(db.session),
        resource_repository=ResourceRepository(db.session),
        availability_service=AvailabilityService(BookingRepository(db.session)),
        invoice_service=BookingInvoiceService(db.session),
        event_bus=current_app.extensions.get("event_bus"),
    )
```

---

## AvailabilityService (computed, NO TimeSlot table)

```python
class AvailabilityService:
    """Compute available slots from schedule + existing bookings."""

    def get_available_slots(self, resource, date) -> list[dict]:
        # 1. Get weekly schedule from resource.availability["schedule"][weekday]
        # 2. Apply exceptions from resource.availability["exceptions"]
        # 3. Query existing bookings for resource + date
        # 4. Subtract booked intervals (respect capacity)
        # 5. Apply buffer_minutes between slots
        # 6. Apply lead_time_hours and max_advance_days
        # 7. Return [{start: "09:00", end: "09:30", available_capacity: 1}, ...]
```

---

## Payment Flow: Authorize → Charge/Release

Booking uses payment **authorization** (hold), not immediate charge:

```
1. User submits booking form
2. BookingService creates Booking (status: "pending")
3. BookingInvoiceService creates Invoice with CUSTOM line item + metadata
4. User redirected to /checkout/:invoice_id (core checkout page)
5. Payment provider AUTHORIZES the amount (hold on card)
6. Booking status → "confirmed", invoice status → "authorized"
7. After booking end_at passes (scheduler/cron):
   → If status == "confirmed": CAPTURE payment, status → "completed"
8. If user cancels within grace period:
   → RELEASE authorization, booking → "cancelled", invoice → "cancelled"
9. If user cancels after grace period:
   → CAPTURE payment (no refund), booking → "cancelled"
```

### BookingInvoiceService

```python
class BookingInvoiceService:
    def create_booking_invoice(self, user, resource, booking) -> UserInvoice:
        invoice = UserInvoice(
            user_id=user.id,
            invoice_number=f"BK-{generate_number()}",
            amount=resource.price * booking.quantity,
            currency=resource.currency,
            status=InvoiceStatus.PENDING,
        )
        db.session.add(invoice)
        db.session.flush()

        line_item = InvoiceLineItem(
            invoice_id=invoice.id,
            item_type=LineItemType.CUSTOM,
            item_id=booking.id,
            description=f"{resource.name} — {booking.start_at.strftime('%Y-%m-%d %H:%M')}",
            quantity=booking.quantity,
            unit_price=resource.price,
            total_price=resource.price * booking.quantity,
            metadata={
                "plugin": "booking",
                "booking_id": str(booking.id),
                "resource_slug": resource.slug,
                "resource_name": resource.name,
                "resource_type": resource.resource_type,
                "start_at": booking.start_at.isoformat(),
                "end_at": booking.end_at.isoformat(),
                "custom_fields": booking.custom_fields,
            },
        )
        db.session.add(line_item)
        booking.invoice_id = invoice.id
        return invoice
```

### Invoice Metadata in Core

The core invoice detail API already returns `line_items[].metadata`. The fe-user invoice detail view needs a minor update to render `CUSTOM` line item metadata as key-value pairs. This is a **core change** (not plugin code):

```typescript
// In InvoiceDetail.vue — add rendering for CUSTOM line items:
<template v-if="lineItem.type === 'CUSTOM' && lineItem.metadata">
  <div v-for="(value, key) in lineItem.metadata" :key="key">
    <strong>{{ formatKey(key) }}:</strong> {{ value }}
  </div>
</template>
```

---

## Events

| Event | When | Payload | Email |
|-------|------|---------|-------|
| `booking.created` | New booking | `{user_id, booking_id, resource_name, start_at, end_at}` | Booking received |
| `booking.confirmed` | Payment authorized | `{user_id, booking_id, resource_name, start_at}` | Booking confirmed |
| `booking.cancelled` | Cancelled by user | `{user_id, booking_id, resource_name, cancelled_by, refund_percent}` | Booking cancelled + refund info |
| `booking.cancelled_by_provider` | Provider cancels (doctor sick, room unavailable) | `{user_id, booking_id, resource_name, reason}` | Special email: provider cancelled, 100% refund |
| `booking.charged` | Payment captured (immediate, before_start, or on_completed) | `{user_id, booking_id, resource_name, amount}` | Payment charged |
| `booking.completed` | Booking time passed | `{user_id, booking_id, resource_name}` | Thank you / review request |
| `booking.reminder` | Before booking (configurable) | `{user_id, booking_id, resource_name, start_at, hours_until}` | Upcoming booking reminder |

### `booking.cancelled` vs `booking.cancelled_by_provider`

- **`booking.cancelled`** — user or admin cancels. Refund amount determined by cancellation policy tiers. Admin is bound by the same policy as user.
- **`booking.cancelled_by_provider`** — admin explicitly triggers this event when the resource provider needs to cancel. Bypasses cancellation policy. Always 100% refund. Dedicated email template with `reason` field (e.g., "Dr. Smith is unavailable due to illness").

### Scheduler Tasks

| Task | Schedule | Action |
|------|----------|--------|
| Capture pending payments | Every hour | Find bookings with `capture_policy.trigger == "before_start"` where `start_at - days_before_start <= now` and invoice status is `AUTHORIZED` → charge |
| Complete past bookings | Every hour | Find confirmed bookings where `end_at < now` → set status to `completed`, publish `booking.completed` |
| Send reminders | Every hour | Find confirmed bookings where `start_at - reminder_hours <= now` and reminder not yet sent → publish `booking.reminder` |

---

## CMS Integration (same pattern as GHRM)

The booking plugin uses the **GHRM headless CMS pattern**: two reusable template pages with vue-component widgets that render dynamic content based on route params. No per-category or per-resource CMS pages needed.

### CMS Structure Created by `populate_db.py`

**Layouts (2):**

| Layout | Slug | Areas | Purpose |
|--------|------|-------|---------|
| Booking Catalogue | `booking-catalogue` | header, breadcrumbs, booking-catalogue, footer | Browse resources by category |
| Booking Resource Detail | `booking-resource-detail` | header, breadcrumbs, booking-detail, footer | Resource detail + availability |

**Widgets (2 vue-components):**

| Widget | Slug | Type | Component | Content JSON |
|--------|------|------|-----------|-------------|
| Booking Catalogue | `booking-catalogue` | vue-component | `BookingCatalogue` | `{"component": "BookingCatalogue"}` |
| Booking Resource Detail | `booking-resource-detail` | vue-component | `BookingResourceDetail` | `{"component": "BookingResourceDetail"}` |

**CMS Pages (template pages, NOT per-item):**

| Page Slug | Layout | Published | Purpose |
|-----------|--------|-----------|---------|
| `booking` | booking-catalogue | Yes | Root catalogue index: `/booking` |
| `booking-resource-detail` | booking-resource-detail | No (template only) | Detail template: `/booking/:slug` |

**How it works:**
1. User visits `/booking` → CmsPage loads page slug `booking` → layout renders `BookingCatalogue` widget
2. `BookingCatalogue` widget fetches categories + resources from `/api/v1/booking/resources`
3. User clicks a resource → navigates to `/booking/dr-smith`
4. CmsPage loads template page `booking-resource-detail` → layout renders `BookingResourceDetail` widget
5. `BookingResourceDetail` reads `route.params.slug` = `"dr-smith"` → fetches resource + availability

**One widget, all categories.** Categories are fetched dynamically from the API — no CMS page per category. Adding a new category in admin = instantly visible in catalogue.

**Nav integration:**
- Header nav widget updated with: "Book" → `/booking`
- Breadcrumb widget: Home → Book → {Resource Name}

### populate_db.py creates:

```python
# 1. Create layouts
layout_catalogue = CmsLayout(name="Booking Catalogue", slug="booking-catalogue", ...)
layout_detail = CmsLayout(name="Booking Resource Detail", slug="booking-resource-detail", ...)

# 2. Create vue-component widgets
widget_catalogue = CmsWidget(
    name="Booking Catalogue", slug="booking-catalogue",
    widget_type="vue-component",
    content_json={"component": "BookingCatalogue"},
)
widget_detail = CmsWidget(
    name="Booking Resource Detail", slug="booking-resource-detail",
    widget_type="vue-component",
    content_json={"component": "BookingResourceDetail"},
)

# 3. Assign widgets to layout areas
LayoutWidgetAssignment(layout=layout_catalogue, area="booking-catalogue", widget=widget_catalogue)
LayoutWidgetAssignment(layout=layout_detail, area="booking-detail", widget=widget_detail)

# 4. Create CMS pages (templates only — NOT one per resource/category)
CmsPage(slug="booking", title="Book", layout=layout_catalogue, is_published=True)
CmsPage(slug="booking-resource-detail", layout=layout_detail, is_published=False)  # template

# 5. Add header nav item
# Update header-nav widget to include "Book" → "/booking"
```

---

## Demo Data (`populate_db.py`)

Creates:
- 3 categories: Medical, Workspace, Events
- 6 resources: Dr. Smith, Dr. Johnson, Meeting Room A, Yoga Studio, Hotel Standard, Hotel Suite
- 5 demo bookings (various statuses)
- 2 CMS layouts + 2 CMS widgets + 2 CMS pages (catalogue + detail template)
- Header nav "Book" link

---

## Testing

### Unit Tests (~60 tests, TDD — write first)

```
tests/unit/
├── services/
│   ├── test_availability_service.py     (~20 tests)
│   │   ├── test_returns_slots_from_weekly_schedule
│   │   ├── test_subtracts_existing_bookings
│   │   ├── test_respects_capacity_for_group_resources
│   │   ├── test_applies_buffer_between_slots
│   │   ├── test_applies_lead_time
│   │   ├── test_applies_max_advance_days
│   │   ├── test_handles_closed_days
│   │   ├── test_handles_exception_dates
│   │   ├── test_returns_empty_for_fully_booked
│   │   └── test_flexible_duration_resources
│   ├── test_booking_service.py          (~15 tests)
│   │   ├── test_create_booking_success
│   │   ├── test_create_booking_no_availability_raises
│   │   ├── test_create_booking_validates_custom_fields
│   │   ├── test_cancel_within_grace_period
│   │   ├── test_cancel_after_grace_period_raises
│   │   ├── test_cancel_publishes_event
│   │   ├── test_complete_changes_status
│   │   └── test_create_booking_creates_invoice
│   ├── test_booking_invoice_service.py  (~8 tests)
│   │   ├── test_creates_invoice_with_custom_line_item
│   │   ├── test_line_item_metadata_contains_booking_details
│   │   ├── test_line_item_type_is_custom
│   │   └── test_invoice_amount_matches_resource_price
│   └── test_resource_service.py         (~10 tests)
├── repositories/                        (~10 tests)
└── models/                              (~8 tests)
```

### Integration Tests (~25 tests)

```
tests/integration/
├── test_booking_api.py                  (~15 tests)
│   ├── test_create_booking_full_flow
│   ├── test_create_booking_returns_invoice
│   ├── test_list_user_bookings
│   ├── test_cancel_booking_api
│   ├── test_admin_list_all_bookings
│   └── test_booking_respects_capacity
└── test_availability_api.py             (~10 tests)
```

### Run

```bash
# Unit tests
docker compose run --rm test pytest plugins/booking/tests/unit/ -v

# Integration tests
docker compose run --rm test pytest plugins/booking/tests/integration/ -v

# Full pre-commit
docker compose run --rm test ./bin/pre-commit-check.sh --quick
```

---

## Acceptance Criteria

1. `bin/pre-commit-check.sh --quick` green (backend core + booking plugin)
2. GitHub Actions CI green on `vbwd-plugin-booking`
3. All 16 API routes respond correctly
4. Invoices created with `LineItemType.CUSTOM` and `metadata` JSON
5. Existing subscription/token/addon invoicing NOT affected
6. Availability computed in < 100ms (no TimeSlot table)
7. `populate_db.py` is idempotent
8. Payment authorization flow: authorize on booking, capture on completion, release on cancellation
9. Invoice `metadata` contains: plugin, booking_id, resource_slug, resource_name, resource_type, start_at, end_at, custom_fields
10. Core invoice detail API returns `metadata` for CUSTOM line items
