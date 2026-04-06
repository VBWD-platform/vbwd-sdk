# Sprint 02a/02b/02c: Booking Plugin Bundle — Implementation Report

**Date:** 2026-03-19
**Status:** Done
**Sprints:** 02a (BE), 02b (FE-Admin), 02c (FE-User)

---

## Summary

Implemented the booking plugin bundle across 3 repos — backend, admin frontend, user frontend. One abstract `BookableResource` model handles all booking types (specialist, room, space, seat, class) via JSON configuration. Core invoicing extended with `CUSTOM` line item type.

---

## Core Change

| Change | Details |
|--------|---------|
| `LineItemType.CUSTOM` | New enum value for plugin-created invoice items |
| `InvoiceLineItem.extra_data` | JSON column (maps to DB column `metadata`, Python attr `extra_data` to avoid SQLAlchemy reserved name) |
| Migration | `20260319_add_custom_line_item_type.py` |
| Tests | 9 unit tests |

---

## Backend Plugin (`vbwd-plugin-booking`)

### Models (4 tables, all prefixed `booking_`)
- `BookableResourceCategory` — with `config` JSON for capture/cancellation policy
- `BookableResource` — one model for all types (specialist, room, space, seat, class)
- `booking_resource_category_link` — many-to-many
- `Booking` — reservation with custom_fields, notes, status

### Services (Dependency Injection)
- `AvailabilityService` — computes slots from weekly schedule + exceptions (no TimeSlot table)
  - Fixed-duration mode (specialist/class): time slot grid with buffer
  - Flexible-duration mode (hotel): day availability
  - Capacity-aware, lead time, max advance days
- `BookingService` — create, cancel, cancel_by_provider, complete
  - Validates capacity, active status
  - Publishes events: booking.created, .cancelled, .cancelled_by_provider, .completed
- `BookingInvoiceService` — creates invoice with CUSTOM line item + extra_data metadata

### Routes (16 endpoints)
- 8 public: categories, resources, availability, bookings CRUD
- 8 admin: categories CRUD, resources CRUD, bookings management, dashboard

### Events (7 types)
- booking.created, .confirmed, .cancelled, .cancelled_by_provider, .charged, .completed, .reminder
- Email template contexts registered in `on_enable()`

### Other
- Migration: `20260319_create_booking_tables.py`
- `populate_db.py`: 3 categories, 6 resources, idempotent
- `config.json`: default timezone, lead time, buffer, cancellation policy

### Tests: 54 unit tests (all pass, lint green)

---

## Admin Frontend Plugin (`vbwd-fe-admin-plugin-booking`)

### Stores (2 Pinia stores)
- `bookingAdmin` — fetchBookings, fetchDetail, updateStatus, dashboardStats
- `resourceAdmin` — CRUD resources + categories

### Views (5)
- `BookingDashboard` — stats cards + recent bookings table
- `BookingList` — filterable booking table (by status)
- `BookingDetail` — booking info + admin actions (confirm, complete, no_show, cancel, cancel by provider with reason modal)
- `ResourceList` — resource table with active toggle
- `ResourceForm` — create/edit with type, capacity, price, categories

### Extension Registry
- Bookings nav section in admin sidebar (Dashboard, All Bookings, Resources)

### Tests: 14 unit tests (all pass, ESLint + TypeScript green)

---

## User Frontend Plugin (`vbwd-fe-user-plugin-booking`)

### Store (1 Pinia store)
- `booking` — fetchCategories, fetchResources, fetchAvailability, createBooking, fetchUserBookings, cancelBooking

### Views (2)
- `BookingCatalogue` — category filter buttons + resource cards grid
- `MyBookings` — user's booking list with status badges

### CMS Integration
- `BookingCatalogue` registered as CMS vue-component widget via dynamic import
- Routes: `/booking` (CMS layout), `/dashboard/bookings` (auth required)

### Tests: 9 unit tests (all pass, ESLint + TypeScript green)

---

## CI Improvements Made During Sprint

| Fix | Impact |
|-----|--------|
| `--plugin` flag for `bin/pre-commit-check.sh` (be + fe-user + fe-admin) | Scoped lint/test per plugin |
| `plugin-tests.yml` with integration jobs | Per-plugin integration tests on full SDK |
| Platform CI split into 3 groups | platform_tests, all_plugins_unit, all_plugins_integration |
| Mypy excludes tests/ + disable import-untyped | Plugin source code only |
| Mypy non-blocking for --plugin mode | Pre-existing issues don't block new plugins |
| Vitest include pattern `**` | Deep test directories matched |
| ESLint: always `npm run lint` | Scoped eslint crashes on CI |
| Skip tests gracefully | Plugins without tests don't fail CI |
| Booking repos made public | CI clone works without tokens |

---

## Test Summary

| Module | Unit Tests | Lint | Pre-commit |
|--------|-----------|------|------------|
| Core (CUSTOM line item) | 9 | green | `--quick` green |
| Backend plugin | 54 | green | `--plugin booking --quick` green |
| FE-Admin plugin | 14 | green | `--plugin booking --unit` green |
| FE-User plugin | 9 | green | `--plugin booking --unit` green |
| **Total** | **86** | | |

---

## Repos

| Repo | URL |
|------|-----|
| `vbwd-plugin-booking` | https://github.com/VBWD-platform/vbwd-plugin-booking |
| `vbwd-fe-admin-plugin-booking` | https://github.com/VBWD-platform/vbwd-fe-admin-plugin-booking |
| `vbwd-fe-user-plugin-booking` | https://github.com/VBWD-platform/vbwd-fe-user-plugin-booking |
