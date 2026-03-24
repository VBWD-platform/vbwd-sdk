# Sprint Report: Booking Event-Driven Checkout + Authorize/Capture

**Date:** 2026-03-23
**Sprint:** 02i — Event-Driven Booking Creation + Payment Authorization
**Status:** Complete
**Repos:** `vbwd-backend`, `vbwd-fe-user`, `vbwd-fe-admin`

---

## Objectives Completed

### 1. Event-Driven Booking Creation

**Problem:** The old `POST /booking/bookings` created a booking + invoice in one step, requiring auth before the form. The booking form is public — user hasn't logged in yet.

**Solution:** Checkout creates an invoice only. Booking is created after payment via event system.

**Flow:**
```
User picks slot → fills form → checkout page (login here) → pay
  → Stripe authorizes/captures → webhook → invoice.paid event
  → BookingPaymentHandler creates Booking record → booking.created event
```

**Changes:**
- New route `POST /api/v1/booking/checkout` — creates invoice with booking metadata in line_item.extra_data
- `BookingPaymentHandler.on_invoice_paid` — subscribes to `invoice.paid`, creates confirmed booking
- `BookingPaymentHandler.on_invoice_refunded` — subscribes to `invoice.refunded`, cancels bookings
- Old `POST /booking/bookings` moved to admin-only `POST /admin/booking/bookings`
- Core `PaymentRefundedHandler` now publishes `invoice.refunded` on event_bus

### 2. Email Notifications for Booking Events

**4 new booking email handlers** in `plugins/email/src/handlers.py`:
- `booking.created` → booking confirmation email
- `booking.cancelled` → cancellation email
- `booking.cancelled_by_provider` → provider cancellation with reason
- `booking.completed` → completion thank-you email

**4 new templates** in `plugins/email/src/seeds.py` with HTML + text bodies.

**All booking event payloads enriched** with `user_email`, `user_name`, `booking_url` for email delivery.

### 3. CMS Widget Architecture

All booking pages converted to CMS widgets with own layouts:

| Widget | CMS Page Slug | Layout | URL |
|--------|---------------|--------|-----|
| BookingCatalogue | `booking` | booking-catalogue | `/booking` |
| BookingResourceDetail | `booking-resource-detail` | booking-resource-detail | `/booking/:slug` |
| BookingForm | `booking-form` | booking-form | `/booking-form/:slug` |
| BookingSuccess | `booking-success` | booking-success | `/booking/success` |

- **Configurable form page slug** via `config.json` (`booking_form_slug`)
- **"Book Now" button** reads slug from shared `bookingConfig.ts`
- **Success page** shows invoice details + resource info + custom fields + notes
- **Auto-redirect** from generic checkout confirmation to booking success page

### 4. Authorize-Only + Charge Later (Provider-Agnostic)

**New invoice lifecycle:**
```
PENDING → AUTHORIZED → PAID (on capture)
                      → CANCELLED (on release/void)
```

**Core (provider-agnostic):**
- `UserInvoice.mark_authorized()`, `is_capturable` property, `payment_intent_id` column
- `PaymentAuthorizedEvent` — emitted when card is authorized (not charged)
- `PaymentAuthorizedHandler` — sets invoice AUTHORIZED, publishes `invoice.authorized`
- `CaptureService.capture()` / `.release()` — calls provider SDK adapter
- Admin API: `POST /admin/invoices/:id/capture` and `/release`
- `emit_payment_authorized()` + `determine_capture_method()` in payment route helpers
- `ISDKAdapter.release_authorization()` added to SDK interface

**Stripe plugin:**
- `create-session` uses `determine_capture_method()` → `capture=False` for manual mode
- Webhook distinguishes `payment_status="unpaid"` (authorized) vs `"paid"` (captured)

**Booking plugin:**
- `capture_mode: "manual"` in config — booking invoices use authorize-only sessions

### 5. Booking Completion Scheduler + Auto-Capture

**Scheduler** (every 15 min via APScheduler):
- `BookingCompletionService.complete_past_bookings()` — finds confirmed bookings where `end_at < now()`, marks completed
- `find_past_confirmed()` on booking repository

**Auto-Capture Handler:**
- Subscribes to `booking.completed` event
- Finds AUTHORIZED invoice linked to the booking
- Calls `CaptureService.capture()` → charges the held funds
- Complete flow: booking time passes → auto-complete → auto-capture → payment charged

### 6. Frontend Fixes

- **Registration error display** — `EmailBlock.vue` now shows actual server validation errors instead of generic message
- **Admin resource form** — uses `plans-view` layout (consistent with booking list)
- **Schedule button** on resource edit page
- **`admin-config.json`** for both backend and fe-user booking plugins

---

## Test Coverage

### Backend Unit Tests: 102

| Area | Tests |
|------|-------|
| BookingService (create, cancel, complete) | 13 |
| BookingInvoiceService | 6 |
| Checkout invoice | 7 |
| BookingPaymentHandler (paid + refund) | 15 |
| BookingCompletionService | 5 |
| PaymentAuthorizedHandler | 6 |
| CaptureService (capture + release) | 8 |
| AutoCaptureHandler | 4 |
| Export/import services | 15 |
| Models | 23 |

### Backend Integration Tests: 51

| Area | Tests |
|------|-------|
| Public endpoints (resources, availability) | 5 |
| Checkout flow | 5 |
| Event-driven booking creation | 1 |
| User booking operations | 5 |
| Refund → cancellation | 1 |
| Capacity enforcement | 1 |
| Admin operations | 4 |
| Authorize / capture flow | 4 |
| Schema CRUD + persistence | 17 |
| Schedule + slot blocking | 8 |

### Email Plugin Tests: 48

| Area | Tests |
|------|-------|
| Booking email handlers (4 events) | 6 |
| All event subscriptions | 10+ |
| Existing handler tests | 32 |

### Playwright E2E Tests: 6

| Test | Duration |
|------|----------|
| New user registers on checkout, pays Stripe | ~26s |
| Logged-in user books, pays, verifies success page content | ~52s |
| Existing user logs in on checkout, pays | ~27s |
| API: checkout creates invoice, no booking on authorize | <1s |
| API: admin can list pending invoices | <1s |
| UI: success page renders with CMS layout | ~4s |

### Success Page Verification (Test 2)

The logged-in user test verifies the BookingSuccess page shows:
- Status banner (paid/authorized/pending)
- Invoice number (BK-XXXXXXXX format)
- Amount and currency (50.00 EUR)
- Resource name (Dr. Smith)
- Resource type (specialist)
- Date & Time
- Custom fields (symptoms)
- Notes (E2E test booking)
- "Back to catalogue" and "View My Bookings" buttons

---

## Files Created

### Backend
| File | Purpose |
|------|---------|
| `plugins/booking/booking/handlers/__init__.py` | Package |
| `plugins/booking/booking/handlers/payment_handler.py` | on_invoice_paid + on_invoice_refunded |
| `plugins/booking/booking/services/booking_completion_service.py` | Auto-complete past bookings |
| `vbwd/handlers/payment_authorized_handler.py` | payment.authorized → AUTHORIZED status |
| `vbwd/handlers/auto_capture_handler.py` | booking.completed → auto-capture |
| `vbwd/services/capture_service.py` | Provider-agnostic capture/release |
| `alembic/versions/20260323_add_payment_intent_id.py` | Migration |
| Tests: 6 new test files | TDD coverage |

### Frontend
| File | Purpose |
|------|---------|
| `plugins/booking/booking/views/BookingSuccess.vue` | Success page widget |
| `plugins/booking/booking/bookingConfig.ts` | Shared config for widgets |
| `plugins/booking/admin-config.json` (fe-user) | Plugin admin config |
| `vue/tests/e2e/booking-checkout.spec.ts` | 3 Stripe payment e2e tests |
| `vue/tests/e2e/booking-authorize.spec.ts` | 3 authorize flow tests |

---

## Files Modified

### Backend (Key Changes)
| File | Change |
|------|--------|
| `vbwd/models/invoice.py` | mark_authorized, is_capturable, payment_intent_id |
| `vbwd/events/payment_events.py` | PaymentAuthorizedEvent |
| `vbwd/plugins/payment_route_helpers.py` | emit_payment_authorized, determine_capture_method |
| `vbwd/routes/admin/invoices.py` | capture + release endpoints |
| `vbwd/sdk/interface.py` | release_authorization abstract method |
| `vbwd/app.py` | Register PaymentAuthorizedHandler |
| `vbwd/scheduler.py` | Booking completion job (every 15 min) |
| `vbwd/handlers/refund_handler.py` | Publish invoice.refunded on event_bus |
| `plugins/stripe/stripe/routes.py` | Authorize-only sessions + webhook |
| `plugins/booking/__init__.py` | capture_mode, event handler registration |
| `plugins/booking/booking/routes.py` | checkout route, admin booking route |
| `plugins/booking/booking/services/booking_service.py` | Enriched event payloads |
| `plugins/booking/booking/services/booking_invoice_service.py` | create_checkout_invoice |
| `plugins/booking/populate_db.py` | CMS layouts/widgets/pages for form + success |
| `plugins/email/src/handlers.py` | 4 booking email handlers |
| `plugins/email/src/seeds.py` | 4 booking email templates |

### Frontend
| File | Change |
|------|--------|
| `plugins/booking/index.ts` | CMS widget registration, routes |
| `plugins/booking/booking/stores/booking.ts` | checkout() replaces createBooking(), pendingCheckout |
| `plugins/booking/booking/views/BookingForm.vue` | No API call, saves to store |
| `plugins/booking/booking/views/BookingCheckout.vue` | Calls checkout API on Pay |
| `plugins/booking/booking/views/BookingResourceDetail.vue` | Configurable form page slug |
| `plugins/booking/booking/components/BookingConfirmationDetails.vue` | Auto-redirect to success |
| `vue/src/components/checkout/EmailBlock.vue` | Show actual registration errors |
| `playwright.config.ts` | E2E_BASE_URL support |

---

## Architecture Decisions

1. **Core agnostic** — authorize/capture logic lives in core (`CaptureService`, `PaymentAuthorizedHandler`). Payment providers implement `capture_payment()` and `release_authorization()` via `ISDKAdapter`. Plugins set `capture_mode` in their config.

2. **Event-driven** — booking creation triggered by `invoice.paid` event, not direct API call. Auto-capture triggered by `booking.completed` event. Email notifications triggered by all booking lifecycle events.

3. **CMS widgets** — all booking pages (catalogue, detail, form, success) are CMS widgets with admin-configurable layouts. Admin controls page slugs via config.

4. **TDD-first** — all 28+ new unit tests written before implementation.

---

## Verification Commands

```bash
# Backend
cd vbwd-backend
./bin/pre-commit-check.sh --full --plugin booking    # 102 unit + 51 integration
./bin/pre-commit-check.sh --quick --plugin email      # 48 unit

# Frontend
cd vbwd-fe-user
npx vitest run plugins/booking/                        # 9 unit tests

# Playwright E2E (requires running services on port 8080)
E2E_BASE_URL=http://localhost:8080 npx playwright test vue/tests/e2e/booking-checkout.spec.ts vue/tests/e2e/booking-authorize.spec.ts --headed
```
