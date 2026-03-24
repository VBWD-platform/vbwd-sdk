# Sprint 02h: Booking Availability & Schedule Editor

**Date:** 2026-03-22
**Status:** Planned
**Repos:** `vbwd-fe-admin-plugin-booking` (admin), `vbwd-plugin-booking` (backend)
**Overview:** [02-booking-overview.md](02-booking-overview.md)
**Depends on:** [02a-booking-be.md](02a-booking-be.md), [02b-booking-fe-admin.md](02b-booking-fe-admin.md)

---

## Problem

The resource's `availability` JSON controls when time slots are generated, but there's no admin UI to edit it. Admins also can't manually block slots (e.g., doctor booked by phone) or see the actual booking calendar. This is core functionality for any booking software.

---

## Design

### New tab: "Schedule" on the resource edit page

The resource form gets a fourth tab (alongside the existing form, categories, and images sections):

**Resources → Edit Resource → Schedule tab**

This tab contains a **calendar view** with three modes (daily, weekly, monthly) — standard for booking software like Calendly, Cal.com, or Acuity.

### Calendar Views

#### Daily View
```
┌──────────────────────────────────────────────────────────────┐
│  ← 2026-03-23 (Monday) →          [Day] [Week] [Month]      │
│                                                               │
│  09:00  ┌─────────────────────────────┐                      │
│         │ ■ Dr. Smith — 09:00–09:30   │ ← booked (grey)     │
│  09:30  └─────────────────────────────┘                      │
│         ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐                      │
│  10:00  │ ○ Available — 09:40–10:10   │ ← open (green)      │
│         └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘                      │
│  10:30  ┌─────────────────────────────┐                      │
│         │ ✕ Blocked — 10:20–10:50     │ ← manually blocked  │
│  11:00  └─────────────────────────────┘                      │
│         ...                                                   │
│                                                               │
│  [Edit Mode]  [Block Selected Slots]  [Copy Schedule To...]  │
└──────────────────────────────────────────────────────────────┘
```

Slot states:
- **Available** (green outline) — open for booking
- **Booked** (solid grey) — has a booking (shows customer name or "Booked")
- **Blocked** (red/striped) — manually blocked by admin

#### Weekly View
```
┌──────────────────────────────────────────────────────────────┐
│  ← Week of 2026-03-23 →           [Day] [Week] [Month]      │
│                                                               │
│         Mon    Tue    Wed    Thu    Fri    Sat    Sun         │
│  09:00  ○      ○      ○      ○      ○      —      —         │
│  09:40  ■      ○      ○      ■      ○      —      —         │
│  10:20  ○      ○      ✕      ○      ○      —      —         │
│  11:00  ○      ■      ○      ○      ○      —      —         │
│  ...                                                          │
│                                                               │
│  ○ = available  ■ = booked  ✕ = blocked  — = closed          │
└──────────────────────────────────────────────────────────────┘
```

#### Monthly View
```
┌──────────────────────────────────────────────────────────────┐
│  ← March 2026 →                    [Day] [Week] [Month]      │
│                                                               │
│  Mon  Tue  Wed  Thu  Fri  Sat  Sun                           │
│                          1    2    3                          │
│                         12/12 10/12  —                        │
│   4    5    6    7    8    9   10                             │
│  12/12 11/12 12/12 12/12 12/12  —    —                       │
│  ...                                                          │
│                                                               │
│  Number = available/total slots · Click day → opens daily view│
└──────────────────────────────────────────────────────────────┘
```

### Edit Mode

When admin clicks **"Edit Mode"** button:
- Available slots become clickable
- Clicking an available slot → blocks it (turns red/striped)
- Clicking a blocked slot → unblocks it (turns green)
- Booked slots are NOT editable (can't cancel from calendar — use booking detail for that)
- Changes save immediately via API (no "Save" button needed — each click is one API call)

### Block/Unblock API

New backend endpoints:

| Method | Route | Description |
|--------|-------|-------------|
| POST | `/api/v1/admin/booking/resources/<id>/block-slot` | Block a time slot |
| POST | `/api/v1/admin/booking/resources/<id>/unblock-slot` | Unblock a time slot |
| GET | `/api/v1/admin/booking/resources/<id>/schedule` | Get schedule for a date range (slots + bookings + blocks) |

#### Block slot request:
```json
{
  "date": "2026-03-23",
  "start": "10:20",
  "end": "10:50",
  "reason": "Phone booking"
}
```

#### Schedule response (for a date range):
```json
{
  "date_from": "2026-03-23",
  "date_to": "2026-03-29",
  "days": [
    {
      "date": "2026-03-23",
      "slots": [
        {"start": "09:00", "end": "09:30", "status": "booked", "booking_id": "abc", "customer": "John"},
        {"start": "09:40", "end": "10:10", "status": "available"},
        {"start": "10:20", "end": "10:50", "status": "blocked", "block_id": "xyz", "reason": "Phone booking"},
        ...
      ]
    },
    ...
  ]
}
```

### Copy Schedule To...

Button opens a modal:
- Shows a list of all resources (checkboxes)
- Admin selects target resources
- Clicks "Copy" → copies the current resource's `availability` JSON to all selected resources
- Does NOT copy bookings or blocks — only the weekly template schedule

---

## Backend

### New model: `BookableResourceSlotBlock`

Stores manually blocked slots (separate from bookings).

```python
class BookableResourceSlotBlock(BaseModel):
    __tablename__ = "booking_resource_slot_block"

    resource_id = db.Column(UUID, FK("booking_resource.id", ondelete="CASCADE"), nullable=False, index=True)
    date = db.Column(db.Date, nullable=False)
    start_time = db.Column(db.String(5), nullable=False)  # "HH:MM"
    end_time = db.Column(db.String(5), nullable=False)    # "HH:MM"
    reason = db.Column(db.String(255), nullable=True)
    blocked_by = db.Column(UUID, FK("user.id"), nullable=True)  # admin who blocked
```

### New migration

```
plugins/booking/migrations/versions/20260322_add_slot_blocks.py
```

### New routes

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| GET | `/api/v1/admin/booking/resources/<id>/schedule` | admin | Get schedule with slots + bookings + blocks for date range |
| POST | `/api/v1/admin/booking/resources/<id>/block-slot` | admin | Block a slot |
| DELETE | `/api/v1/admin/booking/resources/<id>/block-slot/<block_id>` | admin | Unblock a slot |
| POST | `/api/v1/admin/booking/resources/<id>/copy-schedule` | admin | Copy availability JSON to other resources |

### Schedule endpoint logic

The `/schedule` endpoint combines three data sources:
1. **Generated slots** from `availability` JSON + `slot_duration_minutes` + `config.buffer_minutes`
2. **Existing bookings** from `booking` table for the date range
3. **Manual blocks** from `booking_resource_slot_block` table

For each slot, it returns:
- `status: "available"` — no booking or block
- `status: "booked"` — has a confirmed/pending booking
- `status: "blocked"` — has a manual block

### Availability template editor (existing)

The weekly schedule editor (Mon–Sun time blocks) edits `resource.availability.schedule` via the existing resource update route. No new endpoint needed.

---

## Admin Frontend

### New route

```
/admin/booking/resources/:id/schedule
```

Or, alternatively, a tab within the existing resource form page.

**Recommendation:** Separate route (like the schema editor), accessed by clicking a "Schedule" button on the resource list or a tab on the resource form. The calendar is complex enough to warrant its own page.

### Components

```
plugins/booking/booking/views/ResourceSchedule.vue     — main page (calendar + controls)
plugins/booking/booking/components/ScheduleCalendar.vue — calendar component (day/week/month)
plugins/booking/booking/components/ScheduleSettings.vue — weekly template + slot settings
plugins/booking/booking/components/CopyScheduleModal.vue — copy to other resources
```

### Store additions

```typescript
// Schedule
async function fetchSchedule(resourceId: string, dateFrom: string, dateTo: string): Promise<ScheduleDay[]>
async function blockSlot(resourceId: string, data: { date: string; start: string; end: string; reason?: string }): Promise<void>
async function unblockSlot(resourceId: string, blockId: string): Promise<void>
async function copySchedule(resourceId: string, targetResourceIds: string[]): Promise<void>
```

### Navigation

Add "Schedule" link to resource list table (new action button) or as a nav item:
- Resource list → click resource row → resource form (existing)
- Resource list → click "Schedule" button → schedule calendar (new)

---

## I18n

```json
{
  "schedule": {
    "title": "Schedule",
    "daily": "Day",
    "weekly": "Week",
    "monthly": "Month",
    "editMode": "Edit Mode",
    "viewMode": "View Mode",
    "available": "Available",
    "booked": "Booked",
    "blocked": "Blocked",
    "closed": "Closed",
    "blockSlot": "Block Slot",
    "unblockSlot": "Unblock",
    "blockReason": "Reason (optional)",
    "copySchedule": "Copy Schedule To...",
    "copyScheduleTitle": "Copy Schedule",
    "copyScheduleDesc": "Copy this resource's weekly schedule template to selected resources.",
    "copyButton": "Copy",
    "copied": "Schedule copied to {count} resources",
    "settings": "Schedule Settings",
    "weeklyTemplate": "Weekly Template",
    "bufferMinutes": "Buffer between slots (min)",
    "leadTimeHours": "Lead time (hours)",
    "maxAdvanceDays": "Max advance (days)",
    "addBlock": "+ Add time block",
    "removeBlock": "Remove",
    "to": "to",
    "slotsAvailable": "{available}/{total} slots",
    "noSlots": "No slots",
    "exceptions": "Date Exceptions",
    "addException": "+ Add exception",
    "exceptionClosed": "Closed",
    "exceptionSpecial": "Special hours"
  }
}
```

---

## Testing

### Backend integration tests (~6 tests)

```
test_schedule.py
├── test_get_schedule_returns_slots_with_bookings
├── test_block_slot_creates_block
├── test_unblock_slot_removes_block
├── test_blocked_slot_appears_in_schedule
├── test_copy_schedule_to_other_resources
└── test_schedule_excludes_blocked_from_availability
```

### Admin e2e test (~1 test)

```
booking-schedule.spec.ts
├── login → navigate to resource → open schedule
├── verify calendar renders with slots
├── switch between day/week/month views
├── enable edit mode → block a slot
├── verify slot turns blocked
├── unblock the slot
├── verify slot returns to available
├── open settings → change buffer minutes
├── save → verify slots recalculated
└── cleanup
```

---

## Implementation Order

| Step | What | Tests |
|------|------|-------|
| 1 | Backend: SlotBlock model + migration | — |
| 2 | Backend: schedule endpoint (combines slots + bookings + blocks) | ~2 |
| 3 | Backend: block/unblock/copy routes | ~4 |
| 4 | Admin: ScheduleCalendar.vue (daily view first) | — |
| 5 | Admin: weekly + monthly views | — |
| 6 | Admin: edit mode (block/unblock slots) | — |
| 7 | Admin: ScheduleSettings.vue (weekly template + slot settings) | — |
| 8 | Admin: CopyScheduleModal.vue | — |
| 9 | Admin: ResourceSchedule.vue (main page, route registration) | — |
| 10 | Admin: store actions + i18n (8 locales) | — |
| 11 | Admin: integrate schedule link in resource list | — |
| 12 | Backend: blocked slots excluded from user-facing availability | — |
| 13 | E2e test | ~1 |
| **Total** | | **~7** |

---

## Acceptance Criteria

1. Admin can view resource schedule in daily, weekly, monthly calendar views
2. Daily view shows individual slots colored by status (available/booked/blocked)
3. Weekly view shows slot grid across 7 days
4. Monthly view shows available/total slots per day; clicking a day opens daily view
5. Admin can toggle edit mode and click slots to block/unblock them
6. Blocked slots are excluded from user-facing availability (no double-booking)
7. Admin can edit weekly schedule template (Mon–Sun time blocks)
8. Admin can set buffer, lead time, max advance days
9. Admin can add date exceptions (closed days, special hours)
10. Admin can copy schedule to other resources
11. Booked slots show customer name (not editable from calendar)
12. All text uses `$t()` with 8 languages
13. Calendar is responsive on mobile (daily view default on small screens)

---

## Notes

- **No timezone selector** for v1 — uses server's default timezone (`Europe/Berlin` from config). Can be added per-resource in v2.
- **No recurring exceptions** for v1 — only single-date exceptions. Recurring patterns (e.g., "closed every first Monday") can be a v2 feature.
- **No drag-to-select** for v1 — individual click per slot. Multi-select drag could be a v2 UX improvement.
- **Slot preview** is built into the daily view — admin sees the actual generated slots, so no separate preview section needed.
