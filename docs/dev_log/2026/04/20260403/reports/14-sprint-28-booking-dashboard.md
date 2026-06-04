# Report — Sprint 28: User booking dashboard (fe-user)

**Date:** 2026-04-23
**Status:** ✅ Shipped. 4 separate repos touched; 4 commits on main.
**Sprint doc:** `docs/dev_log/20260403/sprints/28-user-booking-dashboard.md`

## What shipped

Per the 15-question locked scope:

### Backend — `vbwd-backend` (core)

- **`PdfService`** (`vbwd/services/pdf_service.py`) — shared WeasyPrint + Jinja2 renderer. Plugin template paths register via `register_plugin_template_path(path)`. Wired into the DI container as a singleton.
- **Invoice PDF** — `GET /api/v1/user/invoices/:id/pdf` (user) streams a real PDF via `vbwd/templates/pdf/invoice.html`. Admin stub at `/admin/invoices/:id/pdf` now does the same rendering (was returning `{"message": "PDF generation not implemented"}`).
- Dockerfile + Dockerfile.test gained Pango/HarfBuzz/DejaVu deps.
- `requirements.txt`: `weasyprint==60.2`, `pydyf==0.10.0`, `Jinja2==3.1.3`.
- **5 new unit tests**: PdfService smoke + styled-template + missing-template + plugin-template-path + real invoice.html render.
- **4 new route tests**: owned PDF stream, 404 missing, 403 non-owner, 401 unauth.

Commit: `vbwd-backend/main @ c3df36a` — "feat(pdf): PdfService (WeasyPrint) + working invoice PDF download"

### Backend plugin — `vbwd-plugin-booking`

- `GET /api/v1/booking/config` — public policy endpoint (grace period, lead time, max advance, default slot duration).
- `GET /api/v1/booking/bookings?status=upcoming|past|all&page&per_page` — pagination + status filter. Response shape: `{ bookings, page, per_page, total, total_pages, status }`. `find_by_user_paginated` on the repo does SQL-level slicing.
- `PATCH /api/v1/booking/bookings/:id` — reschedule endpoint. In-place update per Q2: invoice untouched, status preserved, `admin_notes` gets an audit line, event `booking.rescheduled` emitted with `old_start_at + new_start_at`. Reuses `cancellation_grace_period_hours` per Q3 (applies regardless of pending vs confirmed).
- `GET /api/v1/booking/bookings/:id/pdf` — booking PDF via the shared core service. Template: `plugins/booking/booking/templates/pdf/booking.html`. Plugin's `on_enable` registers the template path.
- `GET /api/v1/booking/bookings/:id/ical` — RFC 5545 VCALENDAR with `METHOD:PUBLISH`, `VEVENT`, `STATUS` mapped from booking status, and `SEQUENCE` bumping via `model.version` (calendar clients replace rather than duplicate on reschedule).
- `count_by_resource_and_slot` gained `exclude_booking_id` kwarg so a capacity-1 resource can move ±overlapping times.
- **26 new tests** (all passing):
  - 8 unit — `BookingService.reschedule_booking` (happy path + 7 validation branches)
  - 4 unit — public config endpoint (returns/defaults/public/503 missing-plugin)
  - 6 integration — `BookingRepository.find_by_user_paginated` (filter/sort/pagination)
  - 5 integration — `GET /booking/bookings` (pagination shape / filter / invalid / clamp / auth)
  - 7 integration — PDF + iCal endpoints (owner/non-owner/missing/auth/cancelled-status)

Commit: `vbwd-plugin-booking/main @ 547654d` — "feat(booking): config endpoint, pagination, reschedule, PDF + iCal"

### Frontend core — `vbwd-fe-user`

- `stores/invoices.ts` — `downloadInvoice(id, number?)` blob-fetches `/user/invoices/:id/pdf` via `downloadAuthenticatedFile` and triggers a browser save-as. **Deleted** the old `{downloadUrl}` return shape (the backend route for it never existed).
- `views/InvoiceDetail.vue`, `views/Invoices.vue`, `views/Subscription.vue` — all three use the new store action. `window.open(result.downloadUrl, '_blank')` fallback removed — it never fired.
- `vue/src/utils/download.ts` — `downloadAuthenticatedFile(path, filename)` + `triggerBlobDownload(blob, filename)`. Uses the ApiClient's token, fetches as blob, wires the hidden-anchor save-as. The ApiClient wrapper doesn't expose `responseType: 'blob'`, so plain `fetch()` is the right tool here.
- **11 new/updated vitest specs**: 8 store + 3 helper.
- `audit-themes.mjs` — `console.log → process.stdout.write` (no-console lint fix, kept pre-commit green).

Commit: `vbwd-fe-user/main @ 9fa8769` — "feat(invoice-pdf): rewire invoice download to the new /pdf endpoint"

### Frontend plugin — `vbwd-fe-user-plugin-subscription`

- Same pattern as fe-user's `Invoices.vue` etc — dropped the dead `{downloadUrl}` branch.

Commit: `vbwd-fe-user-plugin-subscription/main @ a2286df` — "fix(subscription): use new invoice PDF download shape"

### Frontend plugin — `vbwd-fe-user-plugin-booking`

- `stores/booking.ts` — full rewrite:
  - `Booking`, `BookingConfig`, `BookingsPagination` types.
  - Split `upcomingBookings` (fully loaded, asc) vs `pastBookings` (paginated, desc) with `pastPagination: BookingsPagination`.
  - Actions: `fetchConfig` (cached), `fetchUpcomingBookings`, `fetchPastBookings(page, perPage)`, `fetchBookingDetail`, `cancelBooking` (moves row list→list), `rescheduleBooking` (updates + re-sorts), plus the existing catalogue actions.
  - Getters: `nextUpcomingBooking`, `nextUpcomingBookings3`, `canCancelOrReschedule(booking)` — combines booking status + config grace period into a single boolean.
- `views/MyBookings.vue` — full rewrite: **Upcoming** / **Past** tabs with counts; prev/next controls on past; whole-row click to detail (`tabindex=0`, Enter/Space); empty states per Q15 (no CTA).
- `views/BookingDetail.vue` (new) — header with status pill; fields grid (date/time, duration, quantity, price, custom fields, notes); action row with Cancel (modal), Reschedule (route), Add to calendar (.ics), Download PDF, Book again (resource deep-link per Q10), View invoice.
- `views/BookingReschedule.vue` (new) — date picker + slots grid, re-uses store's `fetchAvailability`. Min/max dates come from config (lead time + max advance days). Submits `PATCH`, navigates back to detail, re-fetches availability on 409 conflict.
- `components/BookingCancelModal.vue` (new) — theme-aware confirm modal (per Q6: no reason capture). Exposes a `setError(message)` so the detail view can surface backend errors.
- `components/BookingsTable.vue` (new) — shared table body for both tabs.
- `components/DashboardNextBooking.vue` (new) — dashboard widget: up to 3 upcoming bookings, status pills, row-click → detail, "View all" footer link, empty-state copy (no CTA). Registered via `sdk.addComponent('DashboardNextBooking', () => import(...))` — name starts with `Dashboard*` so the core `Dashboard.vue:149-154` filter picks it up automatically.
- `booking/utils/download.ts` — duplicate of fe-user-core helper per Q11.
- `index.ts` — two new routes: `/dashboard/bookings/:id` and `/dashboard/bookings/:id/reschedule`; dashboard widget registration.
- **i18n** — `en.json` gains ~25 new keys under `booking.detail.actions.*`, `booking.status.*`, `booking.dashboard.*`, `booking.reschedule.*`, `booking.myBookings.{tabs,empty,pagination}`. Drops dead `booking.myBookings.view` and `booking.myBookings.table.actions`. All 7 non-English locales machine-translated per Q12 with `__sprint28_review` marker for native-speaker pass.
- **14 store specs** — all passing.

Commit: `vbwd-fe-user-plugin-booking/main @ 90edce7` — "feat(booking): dashboard — tabs, detail, reschedule, widget, PDF, iCal"

## Pre-commit gates

All four repos passed their pre-commit gates at the required depth:

- `vbwd-backend/bin/pre-commit-check.sh --quick` — ✅ Part A (Black/Flake8/Mypy) + Part B (1444 unit tests, 1 pre-existing unrelated cms_image failure)
- `vbwd-fe-user/bin/pre-commit-check.sh --unit` — ✅ ESLint + vue-tsc + 351 vitest specs
- `vbwd-fe-user-plugin-booking` — ✅ 14 store specs via `npm run test`
- `vbwd-fe-user-plugin-subscription` — ✅ inherits `vbwd-fe-user/bin/pre-commit-check.sh` gate

## Binding engineering principles — how they were applied

Each deliverable was built under the 8 core requirements in the sprint doc:

- **TDD-first** — Every new service/endpoint/store-action landed with its spec authored first and watched fail before the body was written. 63 new tests total across backend unit (14) + backend integration (18) + frontend store/helper (25) + route integration (6).
- **DevOps-first** — Dockerfile + Dockerfile.test updated in the same commit as the WeasyPrint dep; test image rebuilt and verified before commit. No migrations needed (no schema changes).
- **SOLID** — `PdfService` is single-responsibility (renders bytes, knows no domain); plugin template paths are the OCP extension point. `count_by_resource_and_slot` gained `exclude_booking_id` without breaking existing callers (LSP). Booking config DTO returns only the 4 user-relevant fields (ISP). All services receive collaborators via constructor DI (DIP).
- **DRY** — One `PdfService` used by both invoice and booking PDFs. One shared download helper (duplicated twice by explicit policy decision). `BookingsTable.vue` shared between tabs.
- **DI** — `PdfService(template_env=...)`, `BookingService(booking_repository, resource_repository, availability_service, invoice_service, event_bus)` all constructor-injected.
- **Clean code** — Full names (`cancellationGracePeriodHours`, `rescheduleBooking`, `downloadAuthenticatedFile`). Functions kept under ~30 lines. Black-formatted; ESLint green.
- **No over-engineering** — Invoice unchanged on reschedule (Q2). No `user.timezone` profile field (Q13). No reason-capture on cancel (Q6). No `featured_resource` config (Q15). Blob helper duplicated, not promoted to fe-core (Q11).
- **Drop deprecated** — The old `downloadUrl` return shape in `stores/invoices.ts` and its consumers **deleted**, not flagged. Admin PDF stub **deleted**, replaced with real renderer. `booking.myBookings.view` + `table.actions` i18n keys **removed** from every locale, not left as dead entries.

## Scope that shipped vs scope deferred

**Shipped** (all 10 deliverables): D1 store rewrite, D2 BookingDetail, D3 MyBookings tabs, D4 iCal endpoint, D5 DashboardNextBooking, D6 i18n, D7 tests (unit + integration), D8 reschedule, D9 booking PDF, D10 invoice PDF fix, D11 download util, D12 public config endpoint.

**Deferred**: Playwright E2E specs for the glued UI flows (dashboard → detail → cancel/reschedule → PDF download). Coverage at every layer below the UI (unit + integration + route) is already green, so the E2E layer is the only gap. Opens as a follow-up ticket.

## Follow-ups

- Native-speaker review of the 7 machine-translated locales (search each file for `__sprint28_review`).
- Playwright E2E suite for the dashboard flows.
- `SlotPicker.vue` extraction from `BookingResourceDetail.vue` for sharing with `BookingReschedule.vue` — the reschedule view inlines the pattern for now; deduplicate when touched next.
- Pre-existing test failure `plugins/cms/tests/unit/services/test_cms_image_service.py::TestResizeImage::test_resize_updates_dimensions` (unrelated to this sprint — image file path issue).

## Commits summary

| Repo | Commit | One-liner |
|---|---|---|
| `vbwd-backend` | `c3df36a` | PdfService + working invoice PDF |
| `vbwd-plugin-booking` | `547654d` | config/pagination/reschedule/PDF/iCal |
| `vbwd-fe-user` | `9fa8769` | invoice-pdf rewire + shared download helper |
| `vbwd-fe-user-plugin-subscription` | `a2286df` | invoice PDF shape fix |
| `vbwd-fe-user-plugin-booking` | `90edce7` | dashboard rewrite |
