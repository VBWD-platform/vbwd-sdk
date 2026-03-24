# Sprint 02i: Event-Driven Booking Creation

**Date:** 2026-03-23
**Status:** Planned
**Repos:** `vbwd-plugin-booking` (backend), `vbwd-fe-user-plugin-booking` (user)
**Overview:** [02-booking-overview.md](02-booking-overview.md)

---

## Problem

Currently `POST /api/v1/booking/bookings` creates a booking + invoice in one step, requiring authentication. This is wrong because:

1. The booking form is public — user hasn't logged in yet
2. The booking should only be created **after payment is authorized** (not before)
3. The correct flow uses the event system: checkout creates invoice → payment provider authorizes → `invoice.paid` event → booking created

## Correct Flow

```
User browses /booking → picks resource → picks slot → fills form
  ↓
Form collects: resource_slug, start_at, end_at, custom_fields, notes
  ↓
/booking/:slug/book/pay (BookingCheckout.vue)
  → User logs in (EmailBlock)
  → Creates invoice via new API: POST /api/v1/booking/checkout
    (creates invoice with CUSTOM line item + booking metadata in extra_data)
  → Redirects to payment provider
  ↓
Payment provider → authorizes → webhook → payment_handler
  → marks invoice PAID
  → publishes "invoice.paid" event
  ↓
Booking plugin event handler listens for "invoice.paid"
  → checks extra_data.plugin === "booking"
  → creates Booking record
  → publishes "booking.created" event
```

## Backend Changes

### 1. New route: `POST /api/v1/booking/checkout`

Replaces the current `POST /api/v1/booking/bookings` for the user flow. This route:
- Requires auth (`@require_auth`)
- Receives: `resource_slug`, `start_at`, `end_at`, `quantity`, `custom_fields`, `notes`
- Validates the slot is available
- Creates an invoice with a CUSTOM line item containing all booking data in `extra_data`
- Does **NOT** create a Booking record
- Returns `{ invoice_id, invoice_number }`

```python
@booking_bp.route("/api/v1/booking/checkout", methods=["POST"])
@require_auth
def booking_checkout():
    # Validate slot availability
    # Create invoice with CUSTOM line item
    # extra_data = { plugin: "booking", resource_slug, start_at, end_at, ... }
    # Return invoice_id for payment redirect
```

### 2. New event handler: `on_invoice_paid`

Listens for `invoice.paid` and creates bookings for invoices with booking metadata.

```python
# plugins/booking/booking/handlers/payment_handler.py

def on_invoice_paid(event_data):
    invoice = load_invoice(event_data["invoice_id"])
    for line_item in invoice.line_items:
        if line_item.extra_data.get("plugin") == "booking":
            create_booking_from_invoice(invoice, line_item)
```

### 3. Register event handler

In the booking plugin's `on_enable()`:
```python
def on_enable(self):
    event_bus.subscribe("invoice.paid", on_invoice_paid)
```

### 4. Remove or repurpose `POST /api/v1/booking/bookings`

- Keep for admin-created bookings (admin can create bookings directly)
- Remove `@require_auth` issue — admin route stays, user route becomes `/booking/checkout`

## Frontend Changes

### BookingForm.vue

On "Confirm Booking" click:
- Does NOT call `POST /api/v1/booking/bookings`
- Navigates to BookingCheckout page with all form data in query params or store

### BookingCheckout.vue

- Shows EmailBlock for login/register (already there)
- On "Pay Now" click:
  1. Calls `POST /api/v1/booking/checkout` with resource + slot + custom fields
  2. Gets back `invoice_id`
  3. Redirects to payment provider: `/pay/stripe?invoice={invoice_id}`

## Implementation Order

| Step | What |
|------|------|
| 1 | Backend: new `POST /api/v1/booking/checkout` route (creates invoice only) |
| 2 | Backend: new event handler `on_invoice_paid` (creates booking from invoice) |
| 3 | Backend: register handler in plugin `on_enable()` |
| 4 | Frontend: BookingForm → navigate to checkout with data (no API call) |
| 5 | Frontend: BookingCheckout → call `/booking/checkout` then redirect to payment |
| 6 | Integration test: create invoice → simulate payment → verify booking created |

## Acceptance Criteria

1. Booking form is fully public — no auth required
2. Booking record created only after payment succeeds
3. Invoice created at checkout with full booking metadata in extra_data
4. `invoice.paid` event triggers booking creation
5. Booking shows in admin dashboard after payment
6. User sees booking in "My Bookings" after payment
