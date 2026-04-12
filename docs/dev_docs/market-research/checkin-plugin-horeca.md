# Check-In Plugin for HoReCa — Product Specification

**Date:** 2026-04-12
**Goal:** Give HoReCa vendors a complete property management solution within VBWD — from online booking to physical check-in, room management, and checkout. Replace standalone PMS tools.

---

## Vision

A hotel/hostel/resort using VBWD can:
1. Accept bookings online (existing booking plugin)
2. Check guests in at the front desk (this plugin)
3. Manage room status, housekeeping, and guest services
4. Process checkout with final billing
5. All in one platform — no separate PMS needed

---

## Core Features

### 1. Property Floor Plan

**Admin defines the physical property:**
- Building → Floor → Room hierarchy
- Each room: number, type (single, double, suite, dorm bed), status, amenities
- Visual floor plan editor (grid or SVG-based)
- Room status indicators: Available, Occupied, Cleaning, Maintenance, Out of Order
- Drag-and-drop room assignment from booking

**Data model:**
```
checkin_property
├── id, name, address, timezone

checkin_floor
├── id, property_id, name, level_number, floor_plan_svg

checkin_room
├── id, floor_id, room_number, room_type_id
├── status (AVAILABLE, OCCUPIED, CLEANING, MAINTENANCE, OUT_OF_ORDER)
├── current_booking_id (FK → booking, nullable)
├── amenities (JSON: wifi, ac, minibar, balcony, etc.)
├── notes (text)

checkin_room_type
├── id, property_id, name, slug, max_occupancy, base_price
├── description, photos (JSON)
```

### 2. Check-In Flow

**Front desk workflow:**
1. Guest arrives → staff searches by booking reference, guest name, or phone
2. System shows booking details: dates, room type, guests, payment status
3. Staff assigns a specific room (auto-suggest based on type + availability)
4. Guest registration: passport/ID scan or manual entry (name, nationality, ID number)
5. Key card encoding (future: integration with lock systems)
6. Print registration card
7. Status changes: Booking → CHECKED_IN, Room → OCCUPIED

**Data model:**
```
checkin_registration
├── id, booking_id, room_id
├── guest_name, guest_nationality, id_type, id_number
├── check_in_at (timestamp)
├── check_out_at (timestamp, nullable — filled on checkout)
├── num_guests, num_adults, num_children
├── special_requests (text)
├── status (CHECKED_IN, CHECKED_OUT, NO_SHOW, EARLY_CHECKOUT)
├── registered_by (FK → user — staff who checked in)
```

### 3. Dashboard — Today's View

**Front desk sees at a glance:**
- **Arrivals today:** bookings expected, not yet checked in (sorted by time)
- **Departures today:** guests checked in, checkout due today
- **In-house guests:** total currently checked in
- **Room status grid:** visual overview of all rooms by floor
- **Alerts:** overdue checkouts, unpaid invoices, special requests

**Admin dashboard widgets:**
- Occupancy rate (today, this week, this month)
- Revenue per available room (RevPAR)
- Average daily rate (ADR)
- No-show rate

### 4. Room Management

**Housekeeping integration:**
- Room status workflow: OCCUPIED → CHECKOUT → CLEANING → INSPECTED → AVAILABLE
- Housekeeping task queue: auto-generated on checkout
- Staff assignment: assign cleaner to room
- Inspection checklist (configurable per room type)
- Minibar consumption tracking
- Maintenance requests: staff or guest can report issues

**Data model:**
```
checkin_housekeeping_task
├── id, room_id, task_type (CLEANING, INSPECTION, MAINTENANCE)
├── status (PENDING, IN_PROGRESS, COMPLETED)
├── assigned_to (FK → user)
├── notes, created_at, completed_at

checkin_minibar_item
├── id, room_type_id, name, price, default_quantity

checkin_minibar_consumption
├── id, registration_id, item_id, quantity, charged_at
```

### 5. Checkout Flow

**Staff processes checkout:**
1. Review room charges: minibar, late checkout fee, damage deposit
2. Review invoices: booking invoice, additional charges
3. Generate final folio (consolidated invoice)
4. Process payment (existing payment plugins) or mark as direct bill
5. Room status → CLEANING
6. Guest registration → CHECKED_OUT

### 6. Guest Portal (fe-user)

**Logged-in guest sees:**
- Current booking details
- Room number and floor (after check-in)
- Request services: extra towels, room service, late checkout
- View folio/charges in real-time
- Digital key (future: BLE/NFC integration)
- Feedback/rating form on checkout

---

## Admin Views (fe-admin Plugin)

| View | Route | Permission |
|------|-------|------------|
| Property Setup | `/admin/checkin/property` | `checkin.configure` |
| Floor Plan Editor | `/admin/checkin/floors/:id` | `checkin.configure` |
| Room Types | `/admin/checkin/room-types` | `checkin.configure` |
| Room List | `/admin/checkin/rooms` | `checkin.rooms.view` |
| Today's Dashboard | `/admin/checkin/dashboard` | `checkin.dashboard.view` |
| Check-In | `/admin/checkin/arrivals` | `checkin.manage` |
| In-House Guests | `/admin/checkin/in-house` | `checkin.manage` |
| Checkout | `/admin/checkin/departures` | `checkin.manage` |
| Housekeeping Queue | `/admin/checkin/housekeeping` | `checkin.housekeeping.manage` |
| Reports | `/admin/checkin/reports` | `checkin.reports.view` |

---

## Plugin Architecture

```
plugins/checkin/
├── __init__.py               # CheckInPlugin class
├── checkin/
│   ├── models/
│   │   ├── property.py       # Property, Floor, Room, RoomType
│   │   ├── registration.py   # CheckInRegistration
│   │   └── housekeeping.py   # HousekeepingTask, MinibarItem, Consumption
│   ├── repositories/
│   ├── services/
│   │   ├── checkin_service.py     # Check-in / checkout logic
│   │   ├── room_service.py        # Room status management
│   │   └── housekeeping_service.py
│   ├── handlers/
│   │   └── booking_handler.py     # Listen to booking.confirmed → auto-assign room
│   └── routes.py             # Admin + guest API routes
├── tests/
└── populate_db.py            # Demo property with rooms
```

### Backend Plugin Class

```python
class CheckInPlugin(BasePlugin):
    @property
    def metadata(self):
        return PluginMetadata(
            name="checkin",
            version="1.0.0",
            description="Front desk check-in, room management, housekeeping",
            dependencies=["booking"],
        )

    @property
    def admin_permissions(self):
        return [
            {"key": "checkin.dashboard.view", "label": "View dashboard", "group": "Check-In"},
            {"key": "checkin.rooms.view", "label": "View rooms", "group": "Check-In"},
            {"key": "checkin.manage", "label": "Check-in / checkout", "group": "Check-In"},
            {"key": "checkin.housekeeping.manage", "label": "Manage housekeeping", "group": "Check-In"},
            {"key": "checkin.reports.view", "label": "View reports", "group": "Check-In"},
            {"key": "checkin.configure", "label": "Configure property", "group": "Check-In"},
        ]

    @property
    def user_permissions(self):
        return [
            {"key": "checkin.guest.view", "label": "View room details", "group": "Guest"},
            {"key": "checkin.guest.request", "label": "Request services", "group": "Guest"},
        ]

    def register_event_handlers(self, bus):
        bus.subscribe("booking.confirmed", self._on_booking_confirmed)
        bus.subscribe("invoice.paid", self._on_invoice_paid)
```

### Event Flow

```
Guest books online (booking plugin)
  → booking.confirmed event
  → CheckInPlugin auto-suggests room assignment
  → Booking appears in "Today's Arrivals"

Guest arrives
  → Staff opens arrivals dashboard
  → Selects booking → assigns room → enters guest ID
  → checkin.checked_in event
  → Room status → OCCUPIED

During stay
  → Guest requests service via portal
  → Staff charges minibar
  → Housekeeping tasks auto-queued

Checkout
  → Staff reviews charges → generates folio
  → Payment processed (Stripe/PayPal/etc.)
  → checkin.checked_out event
  → Room status → CLEANING
  → Housekeeping task auto-created
```

---

## Integration with Existing VBWD Features

| VBWD Feature | Check-In Integration |
|-------------|---------------------|
| **Booking plugin** | Reservations → arrivals list, room assignment |
| **Subscription plugin** | Corporate accounts, long-stay billing |
| **Invoice plugin** | Room charges, minibar, additional services → invoice line items |
| **Payment plugins** | Checkout payment via Stripe/PayPal/local methods |
| **CMS plugin** | Guest-facing pages (hotel info, amenities, services) |
| **Email plugin** | Check-in confirmation, pre-arrival info, feedback request |
| **User access levels** | Guest portal visibility based on booking status |
| **Analytics widget** | Occupancy, RevPAR, ADR dashboard cards |

---

## Implementation Phases

### Phase 1 — Core Check-In (MVP)
- Property + Floor + Room + RoomType models
- Check-in / checkout flow
- Today's arrivals and departures dashboard
- Room status grid
- 4 weeks estimated

### Phase 2 — Housekeeping
- Task queue auto-generated on checkout
- Staff assignment
- Minibar tracking
- 2 weeks estimated

### Phase 3 — Guest Portal
- Room details widget in fe-user dashboard
- Service request form
- Real-time folio view
- 2 weeks estimated

### Phase 4 — Advanced
- Floor plan visual editor (SVG drag-and-drop)
- Key card integration (ASSA ABLOY, Salto)
- Channel manager sync (room inventory → OTAs)
- Revenue management (dynamic pricing)
- 4+ weeks estimated

---

## Competitive Advantage

**vs. standalone PMS (Cloudbeds, Opera, Mews):**
- No separate system — booking, check-in, billing, CMS all in one
- No integration costs — everything talks via EventBus
- Self-hosted — data sovereignty, no per-room SaaS fees
- Plugin architecture — enable only what you need

**vs. building from scratch:**
- Subscription billing already built
- Payment processing already built
- User management already built
- CMS for property website already built
- Access levels for staff roles already built

**Target customers:**
- Boutique hotels (10-100 rooms)
- Hostels
- Resorts with activity booking
- Serviced apartments
- Co-living spaces
