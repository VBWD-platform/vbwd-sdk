# Sprint 02e: Booking Import/Export + Event-Driven Export

**Date:** 2026-03-18
**Status:** Planned
**Repos:** `vbwd-plugin-booking` (backend) + `vbwd-fe-admin-plugin-booking` (admin UI)
**Overview:** [02-booking-overview.md](02-booking-overview.md)
**Depends on:** [02a-booking-be.md](02a-booking-be.md), [02b-booking-fe-admin.md](02b-booking-fe-admin.md)

---

## Goal

Two features:

1. **Manual Import/Export** — admin can export/import categories, resources, bookings, invoices as CSV/JSON
2. **Event-Driven Export** — admin configures automatic exports triggered by booking/invoice events (webhook to 3rd-party API, or save CSV/XML to a file path)

---

## Feature 1: Manual Import/Export

### Backend — Export Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/admin/booking/export/categories` | Export all categories (CSV or JSON) |
| GET | `/api/v1/admin/booking/export/resources` | Export all resources (CSV or JSON) |
| GET | `/api/v1/admin/booking/export/bookings` | Export bookings with filters (date range, status) |
| GET | `/api/v1/admin/booking/export/invoices` | Export booking invoices (CUSTOM line items only) |

**Query params:**
- `format=csv` or `format=json` (default: csv)
- `date_from=2026-01-01&date_to=2026-03-31` (for bookings/invoices)
- `status=confirmed,completed` (for bookings)

**Response:** File download with `Content-Disposition: attachment; filename="bookings_2026-03-18.csv"`

### Backend — Import Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/admin/booking/import/categories` | Import categories from CSV/JSON |
| POST | `/api/v1/admin/booking/import/resources` | Import resources from CSV/JSON |

**Request:** `multipart/form-data` with file upload

**Import rules:**
- Match by `slug` — if exists, update; if not, create (upsert)
- Validate required fields before import
- Return summary: `{ created: 5, updated: 2, errors: [{ row: 3, error: "..." }] }`
- Bookings and invoices are NOT importable (they reference users, payment data — too risky)

### Backend — Export Service

```python
class BookingExportService:
    def __init__(self, resource_repository, booking_repository, category_repository):
        ...

    def export_resources(self, format="csv") -> bytes:
        resources = self.resource_repository.find_all()
        if format == "json":
            return json.dumps([resource.to_export_dict() for resource in resources])
        return self._to_csv(resources, fields=[
            "slug", "name", "resource_type", "capacity",
            "slot_duration_minutes", "price", "currency", "price_unit",
            "is_active", "categories",
        ])

    def export_bookings(self, date_from, date_to, status=None, format="csv") -> bytes:
        bookings = self.booking_repository.find_by_date_range(date_from, date_to, status)
        ...

    def import_resources(self, file_content, format="csv") -> dict:
        rows = self._parse(file_content, format)
        created, updated, errors = 0, 0, []
        for index, row in enumerate(rows):
            try:
                existing = self.resource_repository.find_by_slug(row["slug"])
                if existing:
                    self._update_resource(existing, row)
                    updated += 1
                else:
                    self._create_resource(row)
                    created += 1
            except Exception as error:
                errors.append({"row": index + 1, "error": str(error)})
        return {"created": created, "updated": updated, "errors": errors}
```

### Admin UI — Export/Import Page

New route: `/admin/booking/data` (added to nav section)

**ExportImport.vue:**
- **Export tab:**
  - Entity selector: Categories / Resources / Bookings / Invoices
  - Format selector: CSV / JSON
  - Date range picker (for bookings/invoices)
  - Status filter (for bookings)
  - "Export" button → file download
- **Import tab:**
  - Entity selector: Categories / Resources (bookings/invoices not importable)
  - File upload (drag & drop)
  - Format auto-detected from file extension
  - Preview table (first 5 rows)
  - "Import" button → summary dialog (created/updated/errors)

---

## Feature 2: Event-Driven Export (Automated)

Admin configures **export rules** that fire automatically when booking or invoice events occur.

### Database Table

```sql
booking_export_rule
├── id              UUID PK (BaseModel)
├── name            VARCHAR(255) NOT NULL           -- "Notify CRM on booking"
├── trigger_type    VARCHAR(50) NOT NULL             -- "event" or "cron"
├── event_type      VARCHAR(100) NULL INDEX          -- "booking.confirmed", etc. (when trigger_type=event)
├── cron_expression VARCHAR(100) NULL                -- "0 2 * * *" (when trigger_type=cron)
├── cron_export_scope VARCHAR(50) NULL               -- "last_24h", "last_7d", "current_month"
├── cron_entity     VARCHAR(50) NULL                 -- "bookings", "invoices", "resources"
├── cron_status_filter VARCHAR(255) NULL             -- "confirmed,completed" (comma-separated)
├── export_type     VARCHAR(50) NOT NULL             -- "webhook", "csv_file", "xml_file"
├── config          JSON NOT NULL                    -- type-specific config (see below)
├── is_active       BOOLEAN DEFAULT TRUE
├── last_triggered_at  DATETIME NULL
├── last_status     VARCHAR(50) NULL                 -- "success", "failed"
├── last_error      TEXT NULL
├── created_at, updated_at, version
```

### Export Types

#### `webhook` — HTTP POST to 3rd-party API

```json
{
  "export_type": "webhook",
  "config": {
    "url": "https://crm.example.com/api/bookings",
    "method": "POST",
    "headers": {
      "Authorization": "Bearer sk-xxx",
      "Content-Type": "application/json"
    },
    "payload_template": "json",
    "timeout_seconds": 10,
    "retry_count": 3,
    "retry_delay_seconds": 30
  }
}
```

Payload sent to webhook:
```json
{
  "event": "booking.confirmed",
  "timestamp": "2026-03-18T14:30:00Z",
  "booking": {
    "id": "uuid",
    "resource_name": "Dr. Smith",
    "start_at": "2026-03-20T10:00:00",
    "end_at": "2026-03-20T10:30:00",
    "user_email": "alice@example.com",
    "custom_fields": { "symptoms": "headache" },
    "status": "confirmed"
  },
  "invoice": {
    "invoice_number": "BK-0001",
    "amount": "50.00",
    "currency": "EUR"
  }
}
```

#### `csv_file` — Append row to CSV file

```json
{
  "export_type": "csv_file",
  "config": {
    "file_path": "/app/exports/bookings_{year}_{month}.csv",
    "columns": ["booking_id", "resource_name", "user_email", "start_at", "end_at", "amount", "status"],
    "include_header": true,
    "append_mode": true
  }
}
```

#### `xml_file` — Write XML to file

```json
{
  "export_type": "xml_file",
  "config": {
    "file_path": "/app/exports/bookings_{year}_{month}.xml",
    "root_element": "bookings",
    "item_element": "booking",
    "fields": ["booking_id", "resource_name", "user_email", "start_at", "amount"]
  }
}
```

### Export Rule Triggers

Export rules can fire on **events** OR on a **cron schedule**:

```json
{
  "trigger_type": "event",
  "event_type": "booking.confirmed"
}
```

```json
{
  "trigger_type": "cron",
  "cron_expression": "0 2 * * *",
  "cron_export_scope": "last_24h"
}
```

#### Cron-Driven Export

Admin configures a schedule (cron expression) and the rule exports a batch of data at each run:

| Field | Description | Example |
|-------|-------------|---------|
| `cron_expression` | Standard cron (5 fields) | `0 2 * * *` (daily at 2 AM) |
| `cron_export_scope` | Time window for data selection | `last_24h`, `last_7d`, `last_30d`, `current_month` |
| `cron_entity` | What to export | `bookings`, `invoices`, `resources` |
| `cron_status_filter` | Optional status filter | `confirmed,completed` |

**Use cases:**
- Daily CSV dump of yesterday's bookings to `/app/exports/bookings_2026_03.csv` at 2 AM
- Weekly XML export of all invoices to SFTP path for accounting system
- Daily webhook POST of new bookings to CRM (batch, not per-event)

**Cron payload** (for webhook type):
```json
{
  "export_type": "cron_batch",
  "timestamp": "2026-03-19T02:00:00Z",
  "scope": "last_24h",
  "entity": "bookings",
  "count": 12,
  "items": [
    { "id": "uuid", "resource_name": "Dr. Smith", "start_at": "...", ... },
    ...
  ]
}
```

**Cron payload** (for csv_file/xml_file type): writes all matching records to the configured file path, replacing `{year}`, `{month}`, `{day}` placeholders.

#### Scheduler Integration

Cron rules are registered with APScheduler on plugin enable:

```python
def on_enable(self):
    cron_rules = self.export_rule_repo.find_active_cron_rules()
    for rule in cron_rules:
        scheduler.add_job(
            self._execute_cron_rule,
            trigger=CronTrigger.from_crontab(rule.config["cron_expression"]),
            id=f"export_rule_{rule.id}",
            args=[rule.id],
            replace_existing=True,
        )
```

When admin creates/updates/deletes a cron rule, the scheduler job is added/updated/removed immediately.

### Subscribable Events

Admin can create export rules for any of these events:

| Event | Description |
|-------|-------------|
| `booking.created` | New booking received |
| `booking.confirmed` | Payment authorized, booking confirmed |
| `booking.cancelled` | Cancelled by user (with refund info) |
| `booking.cancelled_by_provider` | Provider cancelled, full refund |
| `booking.charged` | Payment captured |
| `booking.completed` | Booking time passed |
| `invoice.created` | Invoice generated (any type, not just booking) |
| `invoice.paid` | Invoice paid |

### Backend — Export Rule Service

```python
class ExportRuleService:
    def __init__(self, export_rule_repository, http_client):
        ...

    def execute_rule(self, rule: ExportRule, event_data: dict) -> None:
        if rule.export_type == "webhook":
            self._send_webhook(rule, event_data)
        elif rule.export_type == "csv_file":
            self._append_csv(rule, event_data)
        elif rule.export_type == "xml_file":
            self._write_xml(rule, event_data)

        rule.last_triggered_at = utcnow()
        rule.last_status = "success"

    def _send_webhook(self, rule, event_data):
        config = rule.config
        response = httpx.post(
            config["url"],
            json=event_data,
            headers=config.get("headers", {}),
            timeout=config.get("timeout_seconds", 10),
        )
        response.raise_for_status()

    def _append_csv(self, rule, event_data):
        file_path = rule.config["file_path"].format(
            year=utcnow().year, month=f"{utcnow().month:02d}"
        )
        columns = rule.config["columns"]
        row = [str(event_data.get(column, "")) for column in columns]
        # Append to file (create if not exists, write header on first row)
        ...
```

### Backend — Event Handler Registration

```python
# In BookingPlugin.register_event_handlers(bus):
def register_event_handlers(self, bus):
    # ... existing handlers ...

    # Export rule handler — subscribes to ALL events and checks for matching rules
    bus.subscribe("booking.*", self._on_any_booking_event)
    bus.subscribe("invoice.*", self._on_any_invoice_event)

def _on_any_booking_event(self, event_name, data):
    rules = self.export_rule_repo.find_active_by_event(event_name)
    for rule in rules:
        try:
            self.export_service.execute_rule(rule, {
                "event": event_name,
                "timestamp": utcnow().isoformat(),
                **self._build_payload(event_name, data),
            })
        except Exception as error:
            rule.last_status = "failed"
            rule.last_error = str(error)
            logger.error(f"Export rule '{rule.name}' failed: {error}")
```

### Admin API — Export Rules CRUD

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/admin/booking/export-rules` | List all export rules |
| POST | `/api/v1/admin/booking/export-rules` | Create export rule |
| PUT | `/api/v1/admin/booking/export-rules/:id` | Update export rule |
| DELETE | `/api/v1/admin/booking/export-rules/:id` | Delete export rule |
| POST | `/api/v1/admin/booking/export-rules/:id/test` | Test-fire rule with sample data |
| GET | `/api/v1/admin/booking/export-rules/:id/logs` | View execution history |

### Admin UI — Export Rules Management

New views added to booking admin:

**ExportRuleList.vue:**
- Table: name, event, type (webhook/csv/xml), status (active/inactive), last triggered, last status
- Toggle active/inactive
- "Test" button → fires rule with sample data, shows result

**ExportRuleForm.vue:**
- Name
- **Trigger type:** radio (`Event-driven` / `Scheduled (Cron)`)
- *When Event-driven:*
  - Event selector (dropdown: booking.confirmed, booking.cancelled, etc.)
- *When Cron:*
  - Cron expression input (with helper presets: "Daily at 2 AM", "Weekly Monday", "Monthly 1st")
  - Export scope (dropdown: last 24h, last 7 days, last 30 days, current month)
  - Entity (dropdown: bookings, invoices, resources)
  - Status filter (multi-select, optional)
- Export type selector (webhook / CSV file / XML file)
- **Webhook config:** URL, method, headers (key-value editor), timeout, retries
- **CSV config:** file path (with `{year}`, `{month}`, `{day}` placeholders), columns (checkboxes), append mode
- **XML config:** file path, root element, item element, fields
- "Test" button → sends sample payload / generates sample file, shows response

Nav section updated:
```
Bookings
├── Dashboard
├── All Bookings
├── Resources
├── Categories
├── Import/Export        ← NEW
└── Export Rules         ← NEW
```

---

## Plugin Structure Additions

```
plugins/booking/
├── booking/
│   ├── services/
│   │   ├── export_service.py            # Manual CSV/JSON export
│   │   ├── import_service.py            # CSV/JSON import (upsert)
│   │   └── export_rule_service.py       # Event-driven export execution
│   ├── models/
│   │   └── export_rule.py               # BookingExportRule model
│   └── repositories/
│       └── export_rule_repository.py
└── tests/
    ├── unit/
    │   ├── services/
    │   │   ├── test_export_service.py
    │   │   ├── test_import_service.py
    │   │   └── test_export_rule_service.py
    └── integration/
        ├── test_export_api.py
        └── test_import_api.py
```

---

## Testing

### Unit Tests (~25 tests)

```
test_export_service.py (~8 tests)
├── test_export_resources_csv
├── test_export_resources_json
├── test_export_bookings_with_date_filter
├── test_export_bookings_with_status_filter
├── test_export_invoices_custom_only

test_import_service.py (~7 tests)
├── test_import_categories_creates_new
├── test_import_categories_updates_existing
├── test_import_resources_upsert_by_slug
├── test_import_reports_errors_per_row
├── test_import_validates_required_fields

test_export_rule_service.py (~16 tests)
├── test_webhook_sends_post_with_payload
├── test_webhook_retries_on_failure
├── test_webhook_respects_timeout
├── test_csv_appends_row
├── test_csv_creates_file_with_header
├── test_csv_path_interpolates_year_month_day
├── test_xml_writes_valid_xml
├── test_rule_updates_last_triggered
├── test_rule_records_error_on_failure
├── test_inactive_rule_not_executed
├── test_cron_rule_exports_last_24h_bookings
├── test_cron_rule_exports_last_7d_invoices
├── test_cron_rule_applies_status_filter
├── test_cron_rule_batch_webhook_payload
├── test_cron_rule_registered_with_scheduler
├── test_cron_rule_removed_from_scheduler_on_delete
```

### Integration Tests (~10 tests)

```
test_export_api.py (~5 tests)
├── test_export_resources_csv_download
├── test_export_bookings_json_with_filters
├── test_export_requires_admin_auth

test_import_api.py (~5 tests)
├── test_import_categories_from_csv
├── test_import_resources_returns_summary
├── test_import_rejects_invalid_format
```

---

## Acceptance Criteria

### Manual Import/Export:
1. Admin can export categories, resources, bookings, invoices as CSV or JSON
2. Export supports date range and status filters
3. Admin can import categories and resources from CSV/JSON (upsert by slug)
4. Import returns summary with created/updated/error counts
5. Bookings and invoices are NOT importable

### Event-Driven Export:
6. Admin can create export rules triggered by booking/invoice events
7. Webhook rules send HTTP POST with booking + invoice payload
8. CSV rules append rows to configurable file path
9. XML rules write valid XML to configurable file path
10. File paths support `{year}`, `{month}`, `{day}` placeholders
11. Rules track last_triggered_at, last_status, last_error
12. Admin can test-fire a rule with sample data
13. Failed webhooks retry up to configured retry_count
14. Inactive rules are not executed

### Cron-Driven Export:
15. Admin can create cron-scheduled export rules (e.g., daily at 2 AM)
16. Cron rules export a batch of records for a configurable time window (last 24h, 7d, 30d, current month)
17. Cron rules support entity filter (bookings, invoices, resources) and status filter
18. Cron rules registered with APScheduler on plugin enable
19. Creating/updating/deleting cron rules updates scheduler jobs immediately
20. Cron webhook sends batch payload with all matching records
21. Cron CSV/XML writes all matching records to file (not append per-event)

---

## Estimated Effort

| Component | Effort |
|-----------|--------|
| Export endpoints (CSV/JSON) | 1 day |
| Import endpoints (upsert) | 1 day |
| Export rule model + service (event-driven) | 1.5 days |
| Cron-driven export + APScheduler integration | 1.5 days |
| Event handler integration | 0.5 day |
| Admin UI (export/import page + rule management + cron config) | 2.5 days |
| Tests | 1.5 days |
| **Total** | **9.5 days** |
