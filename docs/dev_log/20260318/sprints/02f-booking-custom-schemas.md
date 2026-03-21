# Sprint 02f: Booking Custom Schemas (replaces Resource Types)

**Date:** 2026-03-21
**Status:** Planned
**Repos:** `vbwd-plugin-booking` (backend), `vbwd-fe-admin-plugin-booking` (admin), `vbwd-fe-user-plugin-booking` (user)
**Overview:** [02-booking-overview.md](02-booking-overview.md)
**Depends on:** [02a-booking-be.md](02a-booking-be.md), [02b-booking-fe-admin.md](02b-booking-fe-admin.md), [02c-booking-fe-user.md](02c-booking-fe-user.md)

---

## Problem

1. Each bookable resource needs a custom booking form (e.g., a doctor needs "Symptoms" + "Insurance ID", a meeting room needs "Number of Attendees" + "Need Projector?"). Currently `custom_fields_schema` is an inline JSON array on `booking_resource` — this doesn't scale when 50 doctors all need the same schema.

2. Resource types (`booking_resource_type`) are a flat classification (Specialist, Room, Space) with no additional semantics. A schema already defines what kind of resource it is — "Medical Intake" schema IS the specialist type, "Hotel Guest" schema IS the room type.

## Design Decision

**Schema replaces resource type.** One entity serves both purposes:

- **Categories** → browsing / filtering / navigation (Medical, Workspace, Events)
- **Schemas** → resource classification + booking form structure

Two independent dimensions on a resource. Admin assigns one schema per resource. The schema defines:
- The **type label** displayed on the catalogue (e.g., "Specialist", "Meeting Room")
- The **custom fields** rendered on the booking form

### What gets removed

- `booking_resource_type` table → **dropped**
- `booking_resource.resource_type` string column → **replaced by** `custom_schema_id` FK
- Backend: `ResourceTypeRepository`, resource type routes, resource type model
- Admin: "Types" tab on ResourceList.vue, type CRUD in store, type dropdown on ResourceForm.vue
- Admin e2e: `booking-resource-types.spec.ts` → replaced by `booking-schemas.spec.ts`

---

## Database

### New table: `booking_custom_schema`

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | BaseModel |
| name | String(255) | Display name, e.g., "Specialist", "Meeting Room" |
| slug | String(255), unique, indexed | e.g., "specialist", "meeting-room" |
| fields | JSON | Array of field definitions (see below) |
| sort_order | Integer | Display order in admin |
| is_active | Boolean | Soft-disable |
| created_at | DateTime | BaseModel |
| updated_at | DateTime | BaseModel |
| version | Integer | BaseModel |

### Field definition schema (inside `fields` JSON array)

```json
[
  {
    "id": "symptoms",
    "label": "Symptoms",
    "type": "text",
    "required": true,
    "placeholder": "Describe your symptoms"
  },
  {
    "id": "insurance",
    "label": "Insurance ID",
    "type": "string",
    "required": false
  },
  {
    "id": "guests",
    "label": "Number of Guests",
    "type": "integer",
    "required": true
  },
  {
    "id": "breakfast",
    "label": "Include Breakfast?",
    "type": "boolean",
    "required": false
  },
  {
    "id": "room_type",
    "label": "Room Type",
    "type": "select",
    "required": true,
    "options": ["Standard", "Deluxe", "Suite"]
  }
]
```

**Supported field types:** `string`, `text`, `integer`, `boolean`, `select`

### Modified table: `booking_resource`

| Change | Details |
|--------|---------|
| Add column | `custom_schema_id UUID FK → booking_custom_schema.id, nullable` |
| Drop column | `resource_type String` — replaced by schema slug |
| Keep column | `custom_fields_schema JSON` — deprecated fallback if `custom_schema_id` is null |

### Dropped table: `booking_resource_type`

Fully removed. The migration drops the table and its index.

**Resolution logic for resource type label:**
- `resource.custom_schema` → use `schema.name` as the type label
- If no schema → show "Unclassified"

**Resolution logic for custom fields:**
- `resource.custom_schema` → use `schema.fields`
- If no schema → fall back to `resource.custom_fields_schema`
- If both null → no custom fields on the booking form

---

## Backend (vbwd-plugin-booking)

### New files

```
plugins/booking/booking/models/custom_schema.py
plugins/booking/booking/repositories/custom_schema_repository.py
```

### Removed files

```
plugins/booking/booking/models/resource_type.py
plugins/booking/booking/repositories/resource_type_repository.py
```

### Model

```python
class BookingCustomSchema(BaseModel):
    __tablename__ = "booking_custom_schema"

    name = db.Column(db.String(255), nullable=False)
    slug = db.Column(db.String(255), unique=True, nullable=False, index=True)
    fields = db.Column(db.JSON, nullable=False, default=list)
    sort_order = db.Column(db.Integer, default=0)
    is_active = db.Column(db.Boolean, default=True)
```

### Repository

Standard CRUD: `find_all`, `find_by_id`, `find_by_slug`, `save`, `delete`

### API Routes

**New schema routes (replace resource type routes):**

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| GET | `/api/v1/admin/booking/schemas` | admin | List all schemas |
| POST | `/api/v1/admin/booking/schemas` | admin | Create schema (name, slug, fields) |
| GET | `/api/v1/admin/booking/schemas/<id>` | admin | Get schema detail |
| PUT | `/api/v1/admin/booking/schemas/<id>` | admin | Update schema |
| DELETE | `/api/v1/admin/booking/schemas/<id>` | admin | Delete schema |
| GET | `/api/v1/booking/schemas` | public | List active schemas (for catalogue filters) |

**Removed routes:**

| Route | Reason |
|-------|--------|
| `/api/v1/admin/booking/resource-types` (GET, POST) | Replaced by schema routes |
| `/api/v1/admin/booking/resource-types/<id>` (PUT, DELETE) | Replaced by schema routes |
| `/api/v1/booking/resource-types` (GET) | Replaced by `/api/v1/booking/schemas` |

### Resource model change

```python
class BookableResource(BaseModel):
    # Remove: resource_type = db.Column(db.String(100), ...)
    # Add:
    custom_schema_id = db.Column(
        UUID(as_uuid=True),
        db.ForeignKey("booking_custom_schema.id"),
        nullable=True,
    )
    custom_schema = db.relationship("BookingCustomSchema", lazy="selectin")

    def to_dict(self):
        result = { ...existing fields... }
        # Schema provides both type label and custom fields
        if self.custom_schema:
            result["resource_type"] = self.custom_schema.slug
            result["resource_type_name"] = self.custom_schema.name
            result["custom_fields_schema"] = self.custom_schema.fields
            result["custom_schema_id"] = str(self.custom_schema_id)
        else:
            result["resource_type"] = "unclassified"
            result["resource_type_name"] = "Unclassified"
        return result
```

**Key:** `resource_type` stays in the serialized output as a string (schema slug) — so existing frontend code that displays `resource.resource_type` doesn't break. The source of truth just moves from a column to a relationship.

### Migration

```
plugins/booking/migrations/versions/20260321_replace_types_with_schemas.py
```

1. Create `booking_custom_schema` table
2. Migrate existing `booking_resource_type` rows → create schemas (name, slug, empty fields)
3. Migrate existing `booking_resource.resource_type` string → look up matching schema → set `custom_schema_id`
4. Migrate existing `booking_resource.custom_fields_schema` → copy into the matching schema's `fields` if non-empty
5. Drop `booking_resource.resource_type` column
6. Drop `booking_resource_type` table
7. Add `custom_schema_id` FK column to `booking_resource`

### Populator update

Replace `RESOURCE_TYPES` with `SCHEMAS` in `populate_db.py`:

```python
SCHEMAS = [
    {
        "name": "Specialist",
        "slug": "specialist",
        "fields": [
            {"id": "symptoms", "label": "Symptoms", "type": "text", "required": True},
            {"id": "insurance", "label": "Insurance ID", "type": "string", "required": False},
        ],
    },
    {
        "name": "Room",
        "slug": "room",
        "fields": [
            {"id": "guests", "label": "Number of Guests", "type": "integer", "required": True},
            {"id": "breakfast", "label": "Include Breakfast?", "type": "boolean", "required": False},
        ],
    },
    {
        "name": "Space",
        "slug": "space",
        "fields": [
            {"id": "attendees", "label": "Number of Attendees", "type": "integer", "required": True},
            {"id": "projector", "label": "Need Projector?", "type": "boolean", "required": False},
        ],
    },
    {
        "name": "Seat",
        "slug": "seat",
        "fields": [],
    },
    {
        "name": "Class",
        "slug": "class",
        "fields": [],
    },
]
```

Assign schemas to demo resources:
- Dr. Smith, Dr. Johnson → "Specialist"
- Meeting Room A → "Space"
- Yoga Studio → "Class"
- Hotel Room Standard, Hotel Room Suite → "Room"

---

## Admin Frontend (vbwd-fe-admin-plugin-booking)

### Store changes (`resourceAdmin.ts`)

**Remove:** `ResourceType` interface, `resourceTypes` ref, `fetchResourceTypes`, `createResourceType`, `updateResourceType`, `deleteResourceType`

**Add:**

```typescript
export interface CustomSchema {
  id: string;
  name: string;
  slug: string;
  fields: SchemaField[];
  sort_order: number;
  is_active: boolean;
}

export interface SchemaField {
  id: string;
  label: string;
  type: 'string' | 'text' | 'integer' | 'boolean' | 'select';
  required: boolean;
  placeholder?: string;
  options?: string[];
}
```

Actions: `fetchSchemas`, `createSchema`, `updateSchema`, `deleteSchema`

### ResourceList.vue — "Schemas" tab replaces "Types" tab

**Remove:** "Types" tab button, types tab template, `newTypeName`/`newTypeSlug` refs, `countResourcesByType`, `generateTypeSlug`, `createResourceType`, `deleteResourceType` functions, `fetchResourceTypes` from `onMounted`

**Add:** "Schemas" tab with same pattern:
- Table: Name, Slug, Fields count, Resources count, Status, Actions (Edit/Delete)
- Inline add form: Name + Slug + Add button
- Clicking a schema row → navigates to schema editor page

Tabs become: **Resources | Categories | Schemas**

### Schema editor (new view)

Route: `/admin/booking/schemas/:id`

**Dynamic field list editor:**
- Each row: Label input, Type dropdown (string/text/integer/boolean/select), Required checkbox, Delete button
- ID auto-generated from label (slugified)
- For `select` type: additional "Options" input (comma-separated)
- "Add Field" button to add new row
- Save / Cancel buttons
- On save: calls `store.updateSchema(id, { name, slug, fields })`

### ResourceForm.vue — schema dropdown replaces type dropdown

**Remove:** hardcoded type `<select>` with specialist/room/space/seat/class options

**Add:** "Schema" dropdown populated from `store.schemas`:
```html
<select v-model="form.custom_schema_id">
  <option value="">No schema</option>
  <option v-for="schema in store.schemas" :key="schema.id" :value="schema.id">
    {{ schema.name }} ({{ schema.fields.length }} fields)
  </option>
</select>
```

Below the dropdown: read-only preview of the selected schema's fields (field names + types).

### Admin route registration

Add to `index.ts` plugin install:
```typescript
sdk.addRoute({
  path: 'booking/schemas/:id',
  name: 'booking-schema-editor',
  component: () => import('./booking/views/SchemaEditor.vue'),
});
```

---

## User Frontend (vbwd-fe-user-plugin-booking)

### BookingCatalogue.vue — no changes needed

Already displays `resource.resource_type` — the backend now returns the schema slug in that field. The catalogue filters by `resource_type` string, which still works.

### BookingForm.vue — no changes needed

Already reads `resource.custom_fields_schema` to render fields. Backend resolves schema → inline fields in `to_dict()`. **Zero frontend changes required.**

### BookingResourceDetail.vue — no changes needed

Same — `resource.resource_type` and `resource.custom_fields_schema` are populated by the backend.

---

## Testing

### Backend unit tests (~15 tests)

```
plugins/booking/tests/unit/
├── test_custom_schema_model.py
│   ├── test_create_schema_with_fields
│   ├── test_schema_to_dict
│   └── test_schema_field_types
├── test_custom_schema_repository.py
│   ├── test_find_all
│   ├── test_find_by_slug
│   └── test_save_and_delete
└── test_custom_schema_routes.py
    ├── test_list_schemas
    ├── test_create_schema
    ├── test_update_schema_fields
    ├── test_delete_schema
    ├── test_resource_serializes_schema_slug_as_type
    ├── test_resource_without_schema_shows_unclassified
    ├── test_resource_inherits_schema_fields
    ├── test_create_schema_requires_auth
    └── test_public_list_schemas
```

### Removed backend tests

```
tests/unit/test_resource_type_*.py  → deleted (entity no longer exists)
```

### Admin frontend unit tests (~8 tests)

```
plugins/booking/tests/unit/
├── stores/resourceAdmin-schemas.spec.ts
│   ├── test_fetchSchemas
│   ├── test_createSchema
│   ├── test_updateSchema
│   └── test_deleteSchema
└── views/SchemaEditor.spec.ts
    ├── test_renders_field_rows
    ├── test_add_field
    ├── test_remove_field
    └── test_save_calls_store
```

### Admin e2e tests

**Remove:** `booking-resource-types.spec.ts`

**Add:** `booking-schemas.spec.ts` — single-session Playwright test (same approach as `booking-resources-crud.spec.ts`)

```
plugins/booking/tests/e2e/booking-schemas.spec.ts
```

**Test: `booking: login → CRUD schemas → assign to resource → verify on booking form`**

```
Single session, all steps sequential:

1. Login
   - goto /admin/login
   - fill Email, Password, click Sign In
   - wait for dashboard

2. Navigate to Schemas tab
   - click sidebar → Booking → Resources
   - click "Schemas" tab
   - verify default schemas visible (specialist, room, space slugs in table)

3. Create schema "Fitness Class"
   - fill inline form: name = "Fitness Class {RUN_ID}", slug auto-generates
   - click Add
   - verify "Fitness Class {RUN_ID}" row appears in table
   - verify fields count shows "0" (no fields yet)

4. Open schema editor
   - click on "Fitness Class {RUN_ID}" row → navigates to /admin/booking/schemas/{id}
   - verify page title shows "Fitness Class {RUN_ID}"
   - verify empty fields list ("No fields yet" or empty table)

5. Add field: "Fitness Level"
   - click "Add Field" button
   - fill Label = "Fitness Level"
   - select Type = "select"
   - fill Options = "Beginner, Intermediate, Advanced"
   - check Required checkbox
   - verify ID auto-generated as "fitness-level"

6. Add field: "Health Conditions"
   - click "Add Field" button
   - fill Label = "Health Conditions"
   - select Type = "text"
   - leave Required unchecked
   - verify ID auto-generated as "health-conditions"

7. Save schema
   - click Save button
   - verify redirect back to Schemas tab (or success toast)
   - verify "Fitness Class {RUN_ID}" row now shows fields count = "2"

8. Reopen schema editor and verify persistence
   - click on "Fitness Class {RUN_ID}" row again
   - verify 2 field rows rendered
   - verify first field: label "Fitness Level", type "select", required checked
   - verify second field: label "Health Conditions", type "text", required unchecked

9. Edit a field
   - change "Health Conditions" label to "Medical Notes"
   - click Save
   - reopen editor → verify label is "Medical Notes"

10. Delete a field
    - click Delete button on "Medical Notes" field row
    - verify only 1 field remains ("Fitness Level")
    - click Save
    - verify fields count = "1" in table

11. Create resource with the new schema
    - click "Resources" tab
    - click "+ New Resource"
    - fill Name = "Yoga Class {RUN_ID}", slug auto-generates
    - select Schema dropdown = "Fitness Class {RUN_ID}"
    - verify schema field preview shows "Fitness Level (select, required)"
    - fill Capacity = 20, Price = 15.00, Currency = EUR
    - click Create/Save
    - verify redirect to resources list
    - verify "Yoga Class {RUN_ID}" row shows type = "fitness-class-{RUN_ID}"

12. Verify schema fields appear on resource detail API
    - API call: GET /api/v1/admin/booking/resources → find the created resource
    - assert resource.resource_type === "fitness-class-{RUN_ID}"
    - assert resource.custom_fields_schema has 1 field with id "fitness-level"

13. Delete schema — verify resource becomes "Unclassified"
    - click "Schemas" tab
    - click Delete on "Fitness Class {RUN_ID}" row, confirm dialog
    - verify row removed from table
    - click "Resources" tab
    - verify "Yoga Class {RUN_ID}" row now shows type = "unclassified"

14. Cleanup via API
    - DELETE created resource by matching name ending with RUN_ID
    - DELETE created schema by matching slug ending with RUN_ID (if not already deleted)
```

**Test: `booking: schema changes propagate to booking form (fe-user)`**

```
This test verifies the full stack: admin creates schema → user sees fields on booking form.
Requires fe-user running alongside fe-admin and backend.

1. Setup via API (no UI needed for setup)
   - POST /api/v1/admin/booking/schemas → create "E2E Schema {RUN_ID}" with fields:
     - {id: "test-field", label: "Test Field", type: "string", required: true}
   - POST /api/v1/admin/booking/resources → create resource with custom_schema_id pointing to the schema

2. Navigate to booking form (fe-user)
   - goto /booking/{resource-slug}/book
   - verify "Test Field" label visible
   - verify input field rendered with required attribute

3. Update schema via API
   - PUT /api/v1/admin/booking/schemas/{id} → add second field:
     - {id: "test-checkbox", label: "Agree to Terms", type: "boolean", required: false}

4. Reload booking form
   - reload page
   - verify "Test Field" still visible
   - verify "Agree to Terms" checkbox now visible

5. Cleanup via API
   - DELETE resource
   - DELETE schema
```

**Note:** The second test requires both fe-admin and fe-user running. It can be a separate test file `booking-schemas-propagation.spec.ts` and only runs in the full platform CI, not in the individual plugin CI.

### User frontend — no new tests

Schema resolution is backend-only. Existing tests cover `custom_fields_schema` rendering.

---

## File Changes Summary

### New files

| Repo | File | Description |
|------|------|-------------|
| backend | `booking/models/custom_schema.py` | BookingCustomSchema model |
| backend | `booking/repositories/custom_schema_repository.py` | CRUD repository |
| backend | `migrations/versions/20260321_replace_types_with_schemas.py` | Migration (create schema, migrate types, drop type table) |
| backend | `tests/unit/test_custom_schema_*.py` | Backend unit tests |
| backend | `docs/schemas/` | JSON import files for default schemas |
| fe-admin | `booking/views/SchemaEditor.vue` | Schema field editor view |
| fe-admin | `tests/e2e/booking-schemas.spec.ts` | E2E test |

### Removed files

| Repo | File | Reason |
|------|------|--------|
| backend | `booking/models/resource_type.py` | Replaced by custom_schema |
| backend | `booking/repositories/resource_type_repository.py` | Replaced by custom_schema_repository |
| fe-admin | `tests/e2e/booking-resource-types.spec.ts` | Replaced by booking-schemas.spec.ts |

### Modified files

| Repo | File | Change |
|------|------|--------|
| backend | `booking/routes.py` | Remove resource-type routes, add schema routes |
| backend | `booking/models/resource.py` | Remove `resource_type` column, add `custom_schema_id` FK + relationship, update `to_dict()` |
| backend | `populate_db.py` | Replace `RESOURCE_TYPES` with `SCHEMAS`, assign to resources |
| fe-admin | `booking/stores/resourceAdmin.ts` | Remove type state/actions, add schema state/actions |
| fe-admin | `booking/views/ResourceList.vue` | Replace "Types" tab with "Schemas" tab |
| fe-admin | `booking/views/ResourceForm.vue` | Replace type dropdown with schema dropdown |
| fe-admin | `index.ts` | Add schema editor route |

### Unchanged files

| File | Reason |
|------|--------|
| `BookingCatalogue.vue` (fe-user) | Reads `resource.resource_type` — backend returns schema slug |
| `BookingForm.vue` (fe-user) | Reads `resource.custom_fields_schema` — backend resolves |
| `BookingResourceDetail.vue` (fe-user) | Same |

---

## Implementation Order

| Step | What | Tests |
|------|------|-------|
| 1 | Backend: schema model + repository | ~6 |
| 2 | Backend: migration (create schema table, migrate types → schemas, drop type table) | — |
| 3 | Backend: resource model change (drop `resource_type`, add `custom_schema_id` FK, update `to_dict`) | ~3 |
| 4 | Backend: remove resource type routes, add schema CRUD + public routes | ~6 |
| 5 | Backend: remove resource_type model + repository files | — |
| 6 | Backend: populator update (SCHEMAS replaces RESOURCE_TYPES) | — |
| 7 | Admin: store (remove type actions, add schema actions) | ~4 |
| 8 | Admin: ResourceList.vue (replace Types tab with Schemas tab) | — |
| 9 | Admin: SchemaEditor.vue (field list editor) | ~4 |
| 10 | Admin: ResourceForm.vue (schema dropdown replaces type dropdown) | — |
| 11 | Admin: route registration for schema editor | — |
| 12 | Admin: e2e test — CRUD schemas + assign to resource (booking-schemas.spec.ts) | ~1 |
| 13 | Platform: e2e test — schema propagation to booking form (booking-schemas-propagation.spec.ts) | ~1 |
| 14 | Cleanup: remove resource_type files + old e2e test | — |
| **Total** | | **~26** |

---

## Acceptance Criteria

1. `booking_resource_type` table no longer exists
2. `booking_resource.resource_type` column no longer exists — replaced by `custom_schema_id` FK
3. Admin can create, edit, and delete schemas with typed fields via "Schemas" tab
4. Admin can assign a schema to a resource via dropdown on resource form
5. Resource serialization returns `resource_type` as schema slug (backward compatible)
6. 50 resources sharing one schema → change schema fields → all 50 booking forms update
7. Resource without a schema → type shows "Unclassified", no custom fields
8. Booking form (fe-user) renders correct fields without any frontend changes
9. Catalogue (fe-user) displays schema name as type badge without any frontend changes
10. Backend unit tests pass
11. Admin e2e test passes
12. `pre-commit-check.sh --quick` green on all 3 repos
