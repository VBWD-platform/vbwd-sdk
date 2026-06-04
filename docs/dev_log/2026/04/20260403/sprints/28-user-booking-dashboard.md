# Sprint 28 — User booking dashboard (fe-user)

**Status:** READY — all 15 clarifying questions answered 2026-04-22.
**Date:** 2026-04-22
**Repos touched:**
- `vbwd-fe-user-plugin-booking` (primary — new views, store extensions, dashboard widget)
- `vbwd-backend-plugin-booking` — new endpoints: reschedule, PDF
- `vbwd-backend` (core) — implement real invoice PDF (existing endpoint is a stub returning JSON), expose user-side `/api/v1/user/invoices/:id/pdf`
- `vbwd-fe-user` (core) — fix the broken `downloadInvoice` flow in `Invoices.vue` / `InvoiceDetail.vue` / `stores/invoices.ts`
- `vbwd-sdk` umbrella — sprint doc only

No changes to `vbwd-fe-core` or `vbwd-fe-admin`.

## Core engineering requirements (binding for every deliverable)

These are **non-negotiable** and apply to every backend and frontend task in this sprint. A deliverable is not "done" until it satisfies every item below for the code it touches.

### 1. TDD-first
- Every new function / service / endpoint gets its test **written first**, run, watched fail, then implementation follows.
- Backend: pytest unit test under `plugins/booking/tests/unit/` (or `vbwd/tests/unit/` for core) lands in the same commit as the implementation; integration test follows before route is wired.
- Frontend: Vitest spec co-located with the store/component (`booking.spec.ts` next to `booking.ts`). Playwright E2E spec under `vue/tests/e2e/` co-lands with the view.
- Concrete checkpoints:
  - `BookingService.reschedule_booking` — happy path + slot taken 409 + past cutoff + non-owner 403 specs authored **before** the method body.
  - `PdfService.render` — smoke spec (output bytes start with `%PDF-`) authored before WeasyPrint is wired.
  - Pagination params — spec for `?page=2&per_page=20` authored before the repo method is touched.
  - fe-user store: `cancelBooking` and `rescheduleBooking` state-transition specs authored before the store actions are written.
- No "refactor now, test later". If a test is hard to write, that's a design signal — redesign, don't skip the test.

### 2. DevOps-first
- Every change ships with its deploy concern answered in the same PR:
  - WeasyPrint system libs → Dockerfile edit + `docker-compose up --build` verified locally.
  - Alembic migration → only if schema changes (reschedule changes zero schema; pagination changes zero schema; config endpoint reads from `config.json`; no migrations expected). If any deliverable discovers a schema need, it creates an Alembic migration — **never** raw SQL.
  - Pre-commit hook passes locally before push: `make pre-commit-quick` on backend, `npm run lint && npm run test` on frontend.
  - CI must stay green across `vbwd-backend`, `vbwd-plugin-booking`, `vbwd-fe-user-plugin-booking`, `vbwd-fe-user`. Touching shared CI scripts without `bash -n` verification is forbidden (see `feedback_ci_precommit_lessons.md`).
  - No `npm install` on the host inside `vbwd-fe-core` (bind-mounted — see `feedback_no_host_npm_install_in_bindmounts.md`).

### 3. SOLID
- **SRP:** one class / module = one reason to change. `PdfService` renders PDFs — it does **not** know about bookings or invoices; those templates live in their respective repos and are handed in by name.
- **OCP:** new PDF types added by registering a template path, not by editing `PdfService`. Plugin template registration is an extension point.
- **LSP (Liskov):** any concrete `IFileStorage`, any subclass of `BasePlugin` must honour the contract of its base. The new reschedule service must not weaken `BookingService`'s postconditions (a successful return ⇒ booking persisted, event emitted).
- **ISP:** keep the public booking config DTO narrow — only return the 4 fields the client uses. Don't fatten the response with admin-only values.
- **DP (Dependency Inversion):** see §5.

### 4. DRY
- `PdfService` is shared between invoice and booking PDFs — **no** invoice-specific rendering logic in the booking plugin and vice versa.
- `SlotPicker.vue` is extracted from `BookingResourceDetail.vue` **before** being reused in `BookingReschedule.vue`. No copy-paste.
- Blob-download helper: yes, duplicated across `vue/src/utils/download.ts` and `plugins/booking/booking/utils/download.ts` (per Q11 — pragmatic choice). Both files kept identical; any fix must be applied to both. If a third consumer appears, promote to `vbwd-fe-core` (see §7 on over-engineering — we resist promoting earlier).

### 5. Dependency injection
- Backend: services receive their collaborators through constructor DI, never via module-level singletons. `BookingService(booking_repo, availability_service, event_dispatcher, invoice_service)`. Existing plugin DI pattern is respected.
- `PdfService(template_env)` — the Jinja env is injected, not imported globally. Makes template-path registration per-plugin clean and tests trivial (pass a `DictLoader`).
- Frontend: stores are Pinia singletons but composables that take `sdk` / `api` as arguments stay testable. Don't reach for `import api from '@/api'` inside unit-tested logic; inject it.

### 6. Clean Code
- **Naming:** full, pronounceable names. `cancellationGracePeriodHours`, not `cgph`. `rescheduleBooking`, not `rb`. Matches `feedback_variable_naming.md`.
- **Functions:** < 30 lines where possible, single level of abstraction per function, no flag arguments (no `reschedule(booking, notify=True)` — split into two methods).
- **Comments:** zero comments that explain *what*. Only comments that explain *why* (non-obvious invariants, references to specific tickets).
- **Formatting:** `black` / `isort` on backend, `eslint --fix` / `prettier` on frontend, both gated in pre-commit.
- **No dead code:** if `BookingCancel.vue` is repurposed as a modal, either rename + reuse OR delete it. Not both.

### 7. No over-engineering
- Do not add what is not in the sprint:
  - No rescheduling-with-invoice-adjustment even though it's tempting (Q2 locked to in-place, invoice frozen).
  - No user.timezone profile field (Q13 locked to browser tz).
  - No reason-capture on cancel (Q6 locked to modal, no reason field).
  - No review/rating surface (user explicitly said no).
  - No recurring bookings (user explicitly said no).
- Do not design for hypothetical future features. If email reminders come later, they'll use the same iCal renderer — no need to pre-abstract for them now.
- Do not promote the blob-download helper to `vbwd-fe-core` this sprint. Two copies. Promote when a third consumer appears — not on speculation.
- Do not introduce a generic "PluginTemplateRegistry" when a single `register_pdf_templates(path)` hook on `PluginManager` is enough.

### 8. Drop deprecated
- **Delete, don't comment out.** Any code this sprint replaces is removed in the same commit:
  - `stores/invoices.ts:79-92` old `downloadInvoice` returning `{ downloadUrl }` — **deleted**, not flagged deprecated.
  - `views/InvoiceDetail.vue:261-264` the `window.open(response.downloadUrl, '_blank')` path — **deleted**.
  - `admin/invoices.py:459-486` stub returning `{"message": "PDF generation not implemented"}` — **deleted** and replaced with real `PdfService.render` call.
  - `BookingCancel.vue` standalone view (no longer reachable after modal lands) — either repurposed as the modal component (`components/BookingCancelModal.vue`, renamed and re-wired) or **deleted entirely**. Not left dangling.
  - `MyBookings.vue` old table body — **fully replaced**, not left under a feature flag.
- No `// @deprecated` markers, no `# removed` comment headstones. The git history is the audit log.
- Old translation keys that become unused (`booking.myBookings.view`, `booking.myBookings.unknown`) — **removed** from all 8 locale files, not left as dead entries.

### Gate

A deliverable is accepted when:
1. Its spec(s) were authored first and are now green.
2. `make pre-commit-quick` (backend) and `npm run lint && npm run test` (frontend) pass.
3. No item above is violated in the diff.
4. No deprecated code left behind.

## Goal

Turn the existing minimal `MyBookings.vue` (a single flat table at `/dashboard/bookings`) into a full **user-facing booking management surface** inside the fe-user dashboard, reachable from the main dashboard and from every booking-related email/receipt the user receives. The user should be able to:

1. See a summary of their next upcoming booking on the main `/dashboard` page (as a Dashboard widget card, same pattern as the existing token-activity and recent-invoices cards).
2. Land on `/dashboard/bookings` and see two segmented lists — **Upcoming** and **Past** — with counts, sortable by date.
3. Open `/dashboard/bookings/:id` and see every detail of the booking (resource, date/time, status, quantity, price, invoice link, custom-field answers, notes).
4. **Cancel** an upcoming booking (subject to the plugin's `cancellation_grace_period_hours` config).
5. **Reschedule** an upcoming booking — pick a new start time from the same resource's availability. Keeps the booking id and its invoice link; status stays `confirmed`.
6. Download an `.ics` file to add the booking to their personal calendar.
7. **Download a PDF** of the booking (shareable receipt / appointment card).
8. Re-book the same resource (deep-link into `BookingCheckout.vue` pre-filled with the original resource + a fresh time pick).

Adjacent core fix bundled in this sprint (user explicitly asked):

9. **Invoice PDF download** actually works end-to-end. Today the fe-user button at `InvoiceDetail.vue:159-164` calls `/user/invoices/:id/download`, which does not exist; the admin stub at `/admin/invoices/:id/pdf` returns JSON `{"message": "PDF generation not implemented"}`. We implement real PDF rendering, expose a user-side endpoint, and rewire both the list and detail views to stream the file.

Out of scope for this sprint (tracked as follow-ups):
- Recurring bookings (backend `enable_recurring_bookings = false` by default — product hasn't decided).
- Review / rating after `completed` (user explicitly said we don't need this).
- Notifications / email reminders (separate plugin responsibility).

## Current state (baseline)

**Backend** (`vbwd-backend/plugins/booking/`) — already exposes:
- `GET /api/v1/booking/bookings` → list authenticated user's bookings (returns `{ bookings: [...] }`)
- `GET /api/v1/booking/bookings/:id` → single booking, 403 if not owner
- `POST /api/v1/booking/bookings/:id/cancel` → user cancels own booking
- `Booking.to_dict()` returns: `id, resource_id, user_id, customer_email, customer_name, customer_phone, customer_company, invoice_id, start_at, end_at, status, quantity, custom_fields, notes, resource {…}, created_at, updated_at`
- Statuses: `pending | confirmed | cancelled | completed`
- **No reschedule endpoint, no iCal endpoint, no PDF endpoint** — all three added this sprint.

**Core backend** (`vbwd-backend/vbwd/routes/`) — invoice PDF state:
- Admin stub at `admin/invoices.py:459-486` returns `{"invoice": …, "message": "PDF generation not implemented"}`. No actual PDF rendering.
- No user-side PDF route exists. `fe-user`'s `stores/invoices.ts:84` calls `/user/invoices/:id/download` expecting `{ downloadUrl }` → currently 404.

This needs implementing in this sprint because (a) users expect a working "Download PDF" button and (b) the booking PDF will share the same renderer, so doing both together avoids duplicating infrastructure.

**Frontend** (`vbwd-fe-user/plugins/booking/booking/`) — already has:
- `views/MyBookings.vue` — one flat table, no upcoming/past split, no filter, no pagination. "View" button pushes to `/dashboard/bookings/:id` but **that route is not registered**, so it 404s today.
- `views/BookingCheckout.vue`, `BookingCatalogue.vue`, `BookingResourceDetail.vue`, `BookingSuccess.vue`, `BookingCancel.vue`, `BookingForm.vue`, `BookingRedirect.vue` — the booking flow, plus a standalone cancel page.
- `stores/booking.ts` — has `userBookings`, `fetchUserBookings()`; lacks detail fetch, cancel action, and typed response.
- `components/BookingConfirmationDetails.vue` — rendered on post-checkout invoice page via `checkoutConfirmationRegistry`.
- `index.ts` registers one dashboard route (`/dashboard/bookings`) and zero dashboard widgets.

**Core dashboard** (`vbwd-fe-user/vue/src/views/Dashboard.vue`) —
- Renders hard-coded Profile / Tokens / Invoices cards.
- Iterates `sdk.getComponents()` for any component whose registered name starts with `Dashboard*` and renders them as additional panels. This is the hook the booking plugin will use.

## Deliverables

### D1 — Extend the booking Pinia store

File: `vbwd-fe-user/plugins/booking/booking/stores/booking.ts`

Backend route changes (per Q14): `GET /api/v1/booking/bookings` gains query params `status=upcoming|past|all` (default `all`), `page` (default 1), `per_page` (default 20, max 100). Response shape becomes `{ bookings, page, per_page, total, total_pages }`. Filtering logic lives in `BookingRepository.find_by_user()` with SQL-level pagination.

Frontend store gets:
- Two separate lists: `upcomingBookings: Booking[]` (fetched in full on mount) and `pastBookings: Booking[]` with `pastPagination: { page, perPage, total, totalPages }`.
- `fetchUpcomingBookings()` — calls `GET /booking/bookings?status=upcoming&per_page=100`. Small list, one shot.
- `fetchPastBookings(page = 1, perPage = 20)` — calls `GET /booking/bookings?status=past&page=N&per_page=M`. Replaces `pastBookings` and `pastPagination` in state.
- `currentBooking: Ref<Booking | null>` + `fetchBooking(id)` calling `GET /api/v1/booking/bookings/:id`.
- `cancelBooking(id): Promise<Booking>` calling `POST /api/v1/booking/bookings/:id/cancel`; on success updates `currentBooking` and removes the entry from `upcomingBookings`, prepends it to `pastBookings` (with status now `cancelled`).
- `rescheduleBooking(id, newStart, newEnd): Promise<Booking>` calling `PATCH /api/v1/booking/bookings/:id` (D8). On success updates `currentBooking` and re-sorts `upcomingBookings`.
- Derived getters: `nextUpcomingBooking` (upcomingBookings[0]), `nextUpcomingBookings3` (upcomingBookings.slice(0, 3)).
- Proper TypeScript interface for `Booking` matching `Booking.to_dict()`. Put it in `plugins/booking/booking/types.ts` and re-export.

### D2 — New route + detail view

File: `vbwd-fe-user/plugins/booking/booking/views/BookingDetail.vue` (new)

Renders, for `/dashboard/bookings/:id`:
- Header: resource name + status pill (re-use `.booking-status--*` classes from `MyBookings.vue` — move them into a shared `plugins/booking/booking/styles/booking.css` so both views share them).
- Details grid (2 columns on ≥640px, 1 column below): date/time, duration, quantity, price (formatted via shared currency helper), resource location/address if the resource exposes one, custom-field answers, user notes, admin notes (only shown if not empty), invoice link.
- Action row (flex, wraps):
  - **Cancel booking** (destructive — red outline). Shown only if `status ∈ {pending, confirmed}` AND `now + cancellation_grace_period_hours < start_at`. On click → confirm modal → `store.cancelBooking` → success toast → route back to `/dashboard/bookings`.
  - **Reschedule** — opens the reschedule flow (D8). Same visibility rules as Cancel.
  - **Add to calendar** (`.ics` download — see D4).
  - **Download PDF** (booking receipt — see D9).
  - **Book again** — navigates to `/booking/:resourceSlug` (the existing `BookingResourceDetail.vue`).
  - **View invoice** (if `invoice_id`) → `/dashboard/invoice/:invoice_id`.

Route registration in `plugins/booking/index.ts`:
```ts
sdk.addRoute({
  path: '/dashboard/bookings/:id',
  name: 'booking-detail',
  component: () => import('./booking/views/BookingDetail.vue'),
  meta: { requiresAuth: true },
});
```

### D3 — Rewrite MyBookings as a two-tab view

File: `vbwd-fe-user/plugins/booking/booking/views/MyBookings.vue` (rewrite)

- Header with title + count badge (Upcoming count = `upcomingBookings.length`, Past count = `pastPagination.total`).
- Segmented control: **Upcoming (N)** / **Past (N)**. Default = Upcoming.
- Upcoming tab: fully loaded list, ascending by `start_at`.
- Past tab (per Q14): paginated. Rows descending by `start_at`. Prev / Next controls + "Page X of Y" label at the bottom of the table. Tab-switch or page-change triggers `store.fetchPastBookings(page)`.
- Empty states per tab (per Q15, no CTA):
  - Upcoming: "No upcoming bookings."
  - Past: "No past bookings yet."
- Row click navigates to detail view — whole row clickable, tabindex=0, keyboard-navigable (Enter/Space). No explicit "View" button.

### D4 — .ics calendar export (server-side per Q9)

**Backend** — `vbwd-backend/plugins/booking/booking/routes.py`:

```
GET /api/v1/booking/bookings/:id/ical
  auth: require_auth, must be booking owner
  returns: text/calendar (UTF-8), Content-Disposition: attachment; filename="booking-<short-id>.ics"
```

Calendar content:
- `BEGIN:VCALENDAR` / `VERSION:2.0` / `PRODID:-//vbwd//booking//EN` / `METHOD:PUBLISH`
- One `VTIMEZONE` block for the booking's resolved timezone (plugin config `default_timezone` or resource-level override if present)
- One `VEVENT`:
  - `UID:<booking.id>@<host>`
  - `DTSTAMP` (now UTC)
  - `DTSTART;TZID=...` / `DTEND;TZID=...`
  - `SUMMARY:<resource.name>`
  - `DESCRIPTION:<resource.description + notes + invoice link>`
  - `LOCATION:<resource.location if present>`
  - `ORGANIZER;CN=<company name>:mailto:<support email>` (from core company settings)
  - `STATUS:<CONFIRMED|TENTATIVE|CANCELLED>` (mapped from booking.status)
  - `SEQUENCE:<N>` — increment on reschedule so clients update existing events

Service: `vbwd-backend/plugins/booking/booking/services/ical_service.py`. Library: `ics>=0.7` (or hand-rolled f-string template — 30 lines, no new dep). Choice left to implementer.

**Frontend** — `plugins/booking/booking/components/BookingDetail.vue` action button fetches the endpoint as a blob and triggers download via the shared helper from D11. No new store action needed.

### D5 — Dashboard widget

File: `vbwd-fe-user/plugins/booking/booking/components/DashboardNextBooking.vue` (new)

Card rendered on the main `/dashboard` page via the plugin-widget hook, same visual weight as the existing Tokens and Invoices cards. Shows (per Q8):
- Header: "Your upcoming bookings".
- Up to 3 next upcoming booking rows, sorted ascending by `start_at`. Each row: resource name, date/time (compact format), status pill.
- Whole row clickable → `/dashboard/bookings/:id` (tabindex=0, Enter/Space activates).
- Footer link "View all →" → `/dashboard/bookings`.
- Empty state (per Q15): copy "No upcoming bookings." — no CTA.
- Loading skeleton: 3 placeholder rows while `store.fetchUpcomingBookings()` is in flight.

Registration in `plugins/booking/index.ts`:
```ts
sdk.addComponent('DashboardNextBooking', DashboardNextBooking);
```

Name MUST begin with `Dashboard` so the core Dashboard.vue computed filter picks it up (`vue/src/views/Dashboard.vue:149-154`).

### D6 — i18n

Add new keys under the `booking.*` namespace in `plugins/booking/locales/en.json`:

```
booking.myBookings.tabs.upcoming
booking.myBookings.tabs.past
booking.myBookings.empty.upcoming
booking.myBookings.empty.past
booking.detail.title
booking.detail.dateTime
booking.detail.duration
booking.detail.quantity
booking.detail.price
booking.detail.customFields
booking.detail.notes
booking.detail.invoiceLink
booking.detail.actions.cancel
booking.detail.actions.cancelConfirm
booking.detail.actions.addToCalendar
booking.detail.actions.bookAgain
booking.detail.actions.viewInvoice
booking.detail.cancelNotAllowed
booking.dashboard.nextBookingTitle
booking.dashboard.nextBookingManage
booking.dashboard.nextBookingBrowse
booking.dashboard.nextBookingNone
```

Mirror into `de.json`, `fr.json`, `es.json`, `ru.json`, `zh.json`, `ja.json`, `th.json`. English is the source; the rest can be machine-translated and marked `// TODO: human-review` (see Q8).

### D8 — Reschedule flow

**Backend** — new endpoint `vbwd-backend/plugins/booking/booking/routes.py`:

```
PATCH /api/v1/booking/bookings/:id
  body: { start_at: ISO8601, end_at: ISO8601 }
  auth: require_auth, must be booking owner
  validation (per Q3):
    - booking.status ∈ {pending, confirmed}
    - now + config.cancellation_grace_period_hours <= booking.start_at  (same cut-off as cancel, regardless of payment status)
    - new start_at > now + config.min_lead_time_hours
    - new slot available (reuse AvailabilityService — exclude the current booking from capacity count)
    - new slot not manually blocked
  behaviour (per Q2 = in-place):
    - update booking.start_at / end_at only
    - bump booking.updated_at
    - emit event "booking.rescheduled" with {old_start, new_start}
    - DO NOT touch the invoice — amount, line item, extra_data all stay frozen
    - append a "rescheduled from <old_start> on <timestamp>" note to admin_notes for audit
  returns: 200 { booking } | 400 {error} | 409 {error: "slot_unavailable"}
```

New service method: `BookingService.reschedule_booking(booking_id, user_id, new_start, new_end)` — validates, checks availability via `AvailabilityService`, saves, publishes event.

Unit tests (backend):
- reschedule updates fields, emits event
- reschedule fails if slot is taken
- reschedule fails if status ∈ {cancelled, completed}
- non-owner gets 403

**Frontend** — new view `vbwd-fe-user/plugins/booking/booking/views/BookingReschedule.vue`:
- Route: `/dashboard/bookings/:id/reschedule`
- Re-uses availability slot picker from `BookingResourceDetail.vue` (extract the slot-picker into a shared component `booking/components/SlotPicker.vue` first).
- Shows original date/time side-by-side with the new selection so user confirms the change.
- Submit → `store.rescheduleBooking(id, new_start, new_end)` → toast → redirect to `/dashboard/bookings/:id`.
- If `409 slot_unavailable` returned, re-fetch availability and show error inline — don't leave stale slots rendered.

### D9 — Booking PDF

**Shared rendering service** (core) — `vbwd-backend/vbwd/services/pdf_service.py`:

```python
class PdfService:
    def __init__(self, template_env: jinja2.Environment): ...
    def render(self, template_name: str, context: dict) -> bytes:
        html = self.template_env.get_template(template_name).render(**context)
        return weasyprint.HTML(string=html, base_url=self._base_url).write_pdf()
```

Template search path seeds `vbwd/templates/pdf/` + any plugin-registered path (plugin adds its own template dir during init via a new `register_pdf_templates(path)` hook on PluginManager). Booking plugin registers `plugins/booking/booking/templates/pdf/`.

Dependencies added to `vbwd-backend/requirements.txt`:
```
weasyprint>=60.0
jinja2>=3.1  # already a transitive, pin explicitly
```

Dockerfile (API image) `apt-get install -y libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz0b libffi-dev shared-mime-info`.

Booking plugin endpoint:
```
GET /api/v1/booking/bookings/:id/pdf
  auth: require_auth, must be booking owner
  returns: application/pdf stream, Content-Disposition: attachment; filename="booking-<short-id>.pdf"
```

PDF content (one page):
- Company logo + name (from core settings)
- "Booking confirmation" header + status badge
- Booking id, date created
- Resource name + description snippet
- Date, time, duration, quantity
- Price line + currency
- Customer name, email, phone
- Custom-field answers (if any)
- Notes (if any)
- "Paid" stamp or "Pending payment" banner based on invoice status
- Footer: company address, support email, line "Present this booking on arrival" (optional)

Template file: `vbwd-backend/plugins/booking/booking/templates/pdf/booking.html` (Jinja2). Styles inline via a `<style>` block at the top of the template or a sibling `booking.css` imported via `@import`. A4 portrait, 20mm margins.

Frontend: a button in `BookingDetail.vue` that fetches the endpoint as a `Blob`, triggers download via `URL.createObjectURL`. No new store action needed — pure fetch helper in `plugins/booking/booking/utils/download.ts`.

### D10 — Invoice PDF (core fix)

**Backend** — `vbwd-backend/vbwd/routes/user/invoices.py` (create if doesn't exist, or add to existing user invoice route file):

```
GET /api/v1/user/invoices/:id/pdf
  auth: require_auth, must be invoice owner
  returns: application/pdf stream, Content-Disposition: attachment; filename="invoice-<number>.pdf"
```

Uses the same shared `PdfService` from D9. Template: `vbwd-backend/vbwd/templates/pdf/invoice.html` (Jinja2). Company metadata (logo path, address, support email) read from existing core settings.

PDF content — standard invoice layout:
- Company details (from settings)
- Customer billing details (from user + UserDetails)
- Invoice number, issue date, due date, status
- Line items table (description, quantity, unit price, total)
- Subtotal / taxes / discounts / total
- Payment status + payment method
- Notes / terms if present
- Footer with contact info

Admin stub (`admin/invoices.py:459-486`) — replace the "not implemented" message with a call into the same service. One admin endpoint, one user endpoint, same renderer.

**Frontend** — rewire:
- `vbwd-fe-user/vue/src/stores/invoices.ts:79-92` — replace `downloadInvoice` with a blob-fetch that hits `/user/invoices/:id/pdf`, reads the response as `Blob`, triggers browser download. Drop the `{ downloadUrl }` indirection entirely.
- `vbwd-fe-user/vue/src/views/InvoiceDetail.vue:257-268` — use the updated store action; remove the `window.open(response.downloadUrl, '_blank')` code path.
- `vbwd-fe-user/vue/src/views/Invoices.vue` — same treatment for the list-row download button.

Extract the blob-download helper to `vbwd-fe-user/vue/src/utils/download.ts` so the booking plugin can import the same helper from `vbwd-view-component` (or duplicate it if the core utils aren't exported — decision noted as Q11).

### D12 — Public booking config endpoint

**Backend** — `vbwd-backend/plugins/booking/booking/routes.py`:

```
GET /api/v1/booking/config
  auth: none (public — values are policy, not secrets)
  returns: 200 {
    cancellation_grace_period_hours: int,
    min_lead_time_hours: int,
    max_advance_booking_days: int,
    default_slot_duration_minutes: int,
  }
```

Values sourced from the plugin's `config.json` / runtime config via the existing plugin config accessor. No DB hit.

**Frontend** — `vbwd-fe-user/plugins/booking/booking/stores/booking.ts`:
- New state: `config: { cancellationGracePeriodHours, minLeadTimeHours, maxAdvanceBookingDays, defaultSlotDurationMinutes } | null`
- New action: `fetchConfig()` — called once when the booking plugin activates (from `plugins/booking/index.ts` activate() hook). Cached for the session.
- Getter used by cancel/reschedule buttons:
  ```ts
  const canCancel = computed(() => {
    if (!booking.value || !store.config) return false;
    if (!['pending', 'confirmed'].includes(booking.value.status)) return false;
    const cutoff = Date.parse(booking.value.start_at) - store.config.cancellationGracePeriodHours * 3600_000;
    return Date.now() < cutoff;
  });
  ```
- Same computed used for the Reschedule button (per Q3).

### D7 — Tests

Vitest (unit):
- Store: upcoming/past/nextUpcoming derivation from a fixed clock.
- Store: `cancelBooking` updates state.
- `ical.ts`: generated VEVENT for a fixed booking matches a snapshot.

Playwright (E2E) — extend existing booking E2E suite:
- Login as test user with seeded bookings (one upcoming, one past).
- Hit `/dashboard` → next-booking card renders correct resource + date.
- Click into `/dashboard/bookings` → both tabs populated, counts match.
- Open detail → cancel → row moves from upcoming to past, status pill = "cancelled".
- Download `.ics` → file arrives with expected UID.

Seeding: prefer extending `plugins/booking/populate_db.py` (or `bin/populate-db.sh`) to insert 2 bookings for the standard `test@example.com` user. Avoids per-test bootstrap code.

## Out-of-scope (follow-ups)

- **S28.1 — Reschedule:** new `PATCH /api/v1/booking/bookings/:id` (user-side), re-runs availability check, emits `booking.rescheduled` event, updates invoice line item date metadata. Own sprint because it touches availability algorithm + invoice immutability rules.
- **S28.2 — Email reminders:** plugin-level cron export rule → email plugin. Own sprint.
- **S28.3 — Recurring bookings:** backend config flag exists but UI/service logic doesn't. Product decision first.

## Risks

- **Ownership enforcement**: the detail endpoint already 403s non-owners (`booking_service.get_booking` compares `user_id`), but we should assert this with an E2E test (log in as user A, fetch user B's booking id).
- **Cancellation race**: a booking just past `start_at - grace_period` is no longer cancellable. UI should re-check server-side; if server returns 400 we show a toast and refresh the booking state.
- **Timezone**: backend stores UTC; `Booking.start_at` is ISO with offset. Display must use the user's browser timezone via `toLocaleString()` with explicit options. The user's saved timezone preference (if any) lives on the user profile — check whether we should honour it over browser default (Q9).

---

## Open questions (one at a time)

Each Q will be resolved before the corresponding deliverable is built. Questions are numbered so we can track answers in the follow-up commits.

- [x] **Q1 — Scope confirmation.** ✅ Answered 2026-04-22: include cancel AND reschedule, include booking PDF, fix core invoice PDF. No review/rating, no recurring.
- [x] **Q2 — Reschedule mechanics.** ✅ Answered 2026-04-22: **(a)** — in-place update of `booking.start_at/end_at`, keep the invoice as-is (same amount, same line item). Emit `booking.rescheduled` event with `{old_start, new_start}`. Invoice's `extra_data.booking_start_at` (if present) is not mutated — invoices remain immutable post-creation.
- [x] **Q3 — Reschedule cut-off.** ✅ Answered 2026-04-22: Part A = **(a)** reuse `cancellation_grace_period_hours` for reschedule too (no new config key). Part B = **(a)** apply the cut-off regardless of booking status — `pending` bookings follow the same rule as `confirmed`, prevents gaming the system by leaving bookings unpaid.
- [x] **Q4 — PDF rendering stack.** ✅ Answered 2026-04-22: **WeasyPrint**. Jinja2 HTML templates → WeasyPrint → PDF bytes. Adds `weasyprint` + `jinja2` to `vbwd-backend/requirements.txt` and `libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz0b libffi-dev shared-mime-info` to the API Dockerfile.
- [x] **Q5 — Detail route naming.** ✅ Answered 2026-04-22: **`/dashboard/bookings/:id`** — consistent with `/dashboard/invoice/:id`. Reschedule sub-route: `/dashboard/bookings/:id/reschedule`.
- [x] **Q6 — Cancellation UX.** ✅ Answered 2026-04-22: **(b)** bespoke modal inside `BookingDetail.vue`. Shows booking summary + cancellation-policy note + "Cancel booking" / "Keep it" buttons. Styled with theme tokens. No reason-capture — keeps scope tight and backend `/cancel` endpoint unchanged. Existing `BookingCancel.vue` file is repurposed as the modal component (`components/BookingCancelModal.vue`).
- [x] **Q7 — Cancellation window source.** ✅ Answered 2026-04-22: **(b)** — new public endpoint `GET /api/v1/booking/config` returning user-relevant policy values (`cancellation_grace_period_hours`, `min_lead_time_hours`, `max_advance_booking_days`, `default_slot_duration_minutes`). Plugin fetches once on store-activate, caches in Pinia. Backend still validates defensively (belt-and-braces). Adds `D12 — Public booking config endpoint` to the deliverables.
- [x] **Q8 — Dashboard widget density.** ✅ Answered 2026-04-22: Part A = **(b)** list of up to 3 next upcoming bookings. Part B = **(a)** show status pill on each row (consistent with detail page). Rows are clickable → `/dashboard/bookings/:id`. Card header "Your upcoming bookings"; footer link "View all →" → `/dashboard/bookings`. Empty state (no upcoming): "Browse resources →" CTA.
- [x] **Q9 — iCal strategy.** ✅ Answered 2026-04-22: **(b)** server-side. New endpoint `GET /api/v1/booking/bookings/:id/ical` returning `text/calendar` with `VTIMEZONE` and `METHOD:PUBLISH`. UID = booking id. Organizer from core company-settings. Adds `ics>=0.7` to backend requirements (or hand-rolled template — 30 lines). Future reminder sprint can reuse the same renderer.
- [x] **Q10 — "Book again" behaviour.** ✅ Answered 2026-04-22: **(a)** — dumb deep link to `/booking/:resourceSlug`. User picks a fresh slot from scratch on the resource detail page. No state pass-through, no stale-slot fallback logic. Recurring behaviour is out of scope anyway.
- [x] **Q11 — Shared download util.** ✅ Answered 2026-04-22: **(a)** — two copies, no cross-repo coupling. `vbwd-fe-user/vue/src/utils/download.ts` for core invoice views; `vbwd-fe-user/plugins/booking/booking/utils/download.ts` for the plugin's booking PDF + iCal. ~30 lines each, promote to `vbwd-fe-core` only if a third consumer appears.
- [x] **Q12 — Non-English translations.** ✅ Answered 2026-04-22: **(a)** — machine-translate all 7 non-English locales (de, fr, es, ru, zh, ja, th) as part of this sprint. Each translated key carries a `// TODO: human-review` comment (or the file header marks the LLM-translated block) so native speakers can polish later. Avoids mixed-language UI on day one.
- [x] **Q13 — Timezone display.** ✅ Answered 2026-04-22: **(a)** — browser/OS timezone via `toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' })`. No profile preference honoured. Matches Google Calendar / Gmail default behaviour and avoids adding a timezone field to the user profile. The iCal `VTIMEZONE` still uses the resource's configured timezone (that's the business's canonical timezone, which is correct for calendar invites).
- [x] **Q14 — Past bookings pagination.** ✅ Answered 2026-04-22: **(b)** — add backend pagination to `GET /api/v1/booking/bookings`. New query params: `status=upcoming|past|all` (default `all`), `page` (default 1), `per_page` (default 20, max 100). Response shape: `{ bookings: [], page, per_page, total, total_pages }`. Fe-user fetches upcoming in full on mount (typically ≤10 items); past tab loads page-by-page on demand with prev/next controls.
- [x] **Q15 — Empty-state CTA target.** ✅ Answered 2026-04-22: **(c)** — no CTA. Empty states just show the copy ("No upcoming bookings.", "No past bookings yet.") with no button or link. Users navigate via main nav. Keeps the dashboard widget and tabs visually clean; avoids an opinionated pointer that only fits some instance types.

---

## Final delivery order

1. **Backend — infra**
   - Add WeasyPrint + Jinja2 to `requirements.txt`; add Pango/HarfBuzz libs to API Dockerfile (Q4).
   - Create `vbwd-backend/vbwd/services/pdf_service.py` with `PdfService.render(template_name, context) -> bytes`.
   - Register plugin-template search-path hook on PluginManager.
2. **Backend — booking endpoints** (`plugins/booking/booking/routes.py`)
   - `GET /api/v1/booking/config` (D12, public, Q7).
   - `GET /api/v1/booking/bookings?status=upcoming|past|all&page&per_page` — extend existing list route to paginate (Q14).
   - `PATCH /api/v1/booking/bookings/:id` — reschedule in-place, same grace as cancel (D8, Q2, Q3).
   - `GET /api/v1/booking/bookings/:id/pdf` — booking PDF (D9).
   - `GET /api/v1/booking/bookings/:id/ical` — iCal with VTIMEZONE (D4, Q9).
3. **Backend — core invoice PDF** (D10)
   - `GET /api/v1/user/invoices/:id/pdf` — new user-owned route.
   - Replace admin stub at `admin/invoices.py:459-486` with real `PdfService.render`.
4. **Backend tests**
   - Unit: `BookingService.reschedule_booking` (happy path, slot taken 409, past-cutoff rejection, non-owner 403).
   - Unit: `PdfService.render` smoke test (bytes start with `%PDF-`).
   - Unit: iCal generator snapshot test.
   - Integration: reschedule endpoint full round trip, invoice untouched assertion.
5. **Frontend — store** (D1)
   - `plugins/booking/booking/types.ts` — typed Booking interface.
   - `plugins/booking/booking/stores/booking.ts` — split upcoming/past, add fetchBooking, cancelBooking, rescheduleBooking, fetchConfig actions.
6. **Frontend — utils**
   - `plugins/booking/booking/utils/download.ts` — blob-download helper (Q11).
   - `vue/src/utils/download.ts` — same helper for core invoice views.
7. **Frontend — plugin views** (D2, D3, D8, D5)
   - `views/BookingDetail.vue` + `components/BookingCancelModal.vue` (Q6).
   - `views/MyBookings.vue` tabs rewrite with paginated past tab (Q14).
   - `views/BookingReschedule.vue` + `components/SlotPicker.vue` (extract from `BookingResourceDetail.vue`).
   - `components/DashboardNextBooking.vue` — up-to-3 rows with status pills (Q8).
   - Register routes + `DashboardNextBooking` component in `plugins/booking/index.ts`.
8. **Frontend — core invoice PDF fix** (D10)
   - Rewrite `stores/invoices.ts:downloadInvoice` to blob-fetch `/user/invoices/:id/pdf`.
   - Update `views/InvoiceDetail.vue:downloadInvoice` and `views/Invoices.vue` list button to use new store action.
9. **PDF templates**
   - `vbwd-backend/vbwd/templates/pdf/invoice.html` (Jinja2, A4 portrait, 20mm margins).
   - `vbwd-backend/plugins/booking/booking/templates/pdf/booking.html` (same page geometry, booking layout per D9).
10. **i18n** (D6, Q12)
    - Add ~25 new keys to `plugins/booking/locales/en.json` + invoice PDF keys to core `vue/src/i18n/locales/en.json`.
    - Machine-translate into de, fr, es, ru, zh, ja, th with `// TODO: human-review` markers.
11. **Tests** (D7)
    - Vitest: store derivations, cancel/reschedule state transitions.
    - Playwright E2E: dashboard widget renders, tab counts correct, open detail → cancel modal → cancel works, reschedule works, PDF downloads with `Content-Type: application/pdf`, iCal downloads with `Content-Type: text/calendar`.
    - Seed 2 bookings (1 upcoming, 1 past) via `plugins/booking/populate_db.py` extension.

## Effort estimate

- Backend infra (WeasyPrint + PdfService + templates scaffold): ~0.5 day
- Backend endpoints (config + reschedule + PDF + iCal + pagination + invoice PDF): ~1 day
- Backend tests: ~0.5 day
- Frontend store + utils + views + reschedule + dashboard widget + core invoice fix: ~2 days
- PDF template design (invoice + booking, A4, print-clean): ~0.5 day
- i18n sweep (8 locales, ~30 keys): ~0.25 day
- E2E + unit tests: ~0.75 day

**Total: ~5.5 person-days.** Backend work front-loaded so frontend can wire against real endpoints from day 2.
