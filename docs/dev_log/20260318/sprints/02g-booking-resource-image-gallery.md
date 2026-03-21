# Sprint 02g: Booking Resource Image Gallery

**Date:** 2026-03-21
**Status:** Planned
**Repos:** `vbwd-plugin-booking` (backend), `vbwd-fe-admin-plugin-booking` (admin)
**Overview:** [02-booking-overview.md](02-booking-overview.md)
**Depends on:** [02a-booking-be.md](02a-booking-be.md), [02b-booking-fe-admin.md](02b-booking-fe-admin.md)

---

## Problem

Booking resources currently have a single `image_url` text field. Real-world resources (hotel rooms, meeting spaces, specialists) need multiple photos — a primary image shown in the catalogue card, plus additional images displayed on the detail page as a gallery.

## Design Decision

**CMS-dependent image gallery** — uses the CMS plugin's existing `CmsImage` model and file storage infrastructure. If CMS is not installed, the image gallery block doesn't appear on the resource edit page (graceful degradation).

### Architecture

```
BookableResource ──1:N──> BookableResourceImage (join entity)
                                │
                                └──> CmsImage (from CMS plugin)
```

- **BookableResourceImage** — join table with `resource_id`, `cms_image_id`, `is_primary`, `sort_order`
- **CmsImage** — existing CMS model, handles file upload/storage/thumbnails
- The gallery reuses CMS file storage (`IFileStorage`, `LocalFileStorage`) — no new upload infrastructure needed

### Key principle

The booking plugin **does not import or depend on CMS models at the Python import level**. Instead:
- The join table uses raw FK columns (`cms_image_id UUID REFERENCES cms_image(id)`)
- The route handler imports CMS models lazily inside the function body (same pattern as `populate_db.py`)
- If CMS plugin is not installed, the gallery routes return `501 Not Implemented`
- The admin frontend checks CMS availability and conditionally renders the gallery block

---

## Database

### New table: `booking_resource_image`

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | BaseModel |
| resource_id | UUID FK → booking_resource.id | NOT NULL, indexed, ON DELETE CASCADE |
| cms_image_id | UUID FK → cms_image.id | NOT NULL, ON DELETE CASCADE |
| is_primary | Boolean | Default false; exactly one per resource should be true |
| sort_order | Integer | Display order in gallery (0 = first) |
| created_at | DateTime | BaseModel |
| updated_at | DateTime | BaseModel |

**Constraint:** Unique on `(resource_id, cms_image_id)` — same image can't be attached twice.

### Modified: `booking_resource.to_dict()`

Add `images` array to serialized output:
```python
"images": [
    {
        "id": str(image.id),
        "cms_image_id": str(image.cms_image_id),
        "url": image.cms_image.url,           # resolved from CmsImage
        "thumbnail_url": image.cms_image.thumbnail_url,
        "alt": image.cms_image.alt_text,
        "is_primary": image.is_primary,
        "sort_order": image.sort_order,
    }
]
```

The existing `image_url` field becomes a computed shortcut — returns the primary image's URL (or null if no images).

---

## Backend (vbwd-plugin-booking)

### Model

```
plugins/booking/booking/models/resource_image.py
```

```python
class BookableResourceImage(BaseModel):
    __tablename__ = "booking_resource_image"

    resource_id = db.Column(UUID, FK("booking_resource.id", ondelete="CASCADE"), nullable=False)
    cms_image_id = db.Column(UUID, FK("cms_image.id", ondelete="CASCADE"), nullable=False)
    is_primary = db.Column(db.Boolean, default=False)
    sort_order = db.Column(db.Integer, default=0)

    __table_args__ = (
        db.UniqueConstraint("resource_id", "cms_image_id"),
    )
```

### API Routes

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| GET | `/api/v1/admin/booking/resources/<id>/images` | admin | List resource images (sorted) |
| POST | `/api/v1/admin/booking/resources/<id>/images` | admin | Upload + attach image (multipart form) |
| PUT | `/api/v1/admin/booking/resources/<id>/images/<image_id>` | admin | Update is_primary / sort_order |
| DELETE | `/api/v1/admin/booking/resources/<id>/images/<image_id>` | admin | Remove image from resource |
| POST | `/api/v1/admin/booking/resources/<id>/images/reorder` | admin | Batch reorder: `{ order: [id1, id2, ...] }` |
| POST | `/api/v1/admin/booking/resources/<id>/images/<image_id>/primary` | admin | Set as primary image |

### Upload flow

1. Admin uploads file via multipart form
2. Backend calls `CmsImageService.create(file)` — saves to file storage, creates `CmsImage` row
3. Backend creates `BookableResourceImage` linking the resource to the new `CmsImage`
4. Returns the image entry with URL

### CMS dependency check

```python
def _check_cms_available():
    try:
        from plugins.cms.src.models.cms_image import CmsImage  # noqa: F401
        return True
    except ImportError:
        return False

@booking_bp.route("/api/v1/admin/booking/resources/<id>/images", methods=["GET"])
@require_auth
@require_admin
def admin_list_resource_images(id):
    if not _check_cms_available():
        return jsonify({"error": "CMS plugin required for image gallery"}), 501
    # ... handle request
```

### Migration

```
plugins/booking/migrations/versions/20260321_add_resource_images.py
```

Create `booking_resource_image` table with FKs and unique constraint.

---

## Admin Frontend (vbwd-fe-admin-plugin-booking)

### ResourceForm.vue — new "Images" block

Conditionally rendered when CMS plugin is active (check via API or store flag).

**Layout:**
```
┌──────────────────────────────────────────────────────┐
│ Images                                                │
│                                                       │
│ ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
│ │ ★ PRIMARY│  │  img 2  │  │  img 3  │  │  + Add  │ │
│ │  [photo] │  │  [photo]│  │  [photo]│  │         │ │
│ │         │  │         │  │         │  │         │ │
│ └─────────┘  └─────────┘  └─────────┘  └─────────┘ │
│                                                       │
│ Drag to reorder · Click ★ to set primary              │
└──────────────────────────────────────────────────────┘
```

**Features:**
- Grid of thumbnail cards (4 per row desktop, 2 per row mobile)
- Primary image has a gold star badge and border highlight
- Click star icon on any image → sets it as primary (API call)
- Drag-and-drop to reorder (or arrow buttons for mobile)
- "+" card at the end → opens file upload dialog
- Delete button (×) on each image card
- Supports: JPG, PNG, WebP (enforced by CMS image service)

### Store additions (`resourceAdmin.ts`)

```typescript
async function fetchResourceImages(resourceId: string): Promise<ResourceImage[]>
async function uploadResourceImage(resourceId: string, file: File): Promise<ResourceImage>
async function setResourceImagePrimary(resourceId: string, imageId: string): Promise<void>
async function reorderResourceImages(resourceId: string, imageIds: string[]): Promise<void>
async function deleteResourceImage(resourceId: string, imageId: string): Promise<void>
```

### Component: `ResourceImageGallery.vue`

Extracted as a separate component (not inline in ResourceForm.vue):

```
plugins/booking/booking/components/ResourceImageGallery.vue
```

Props: `resourceId: string`
Emits: `primary-changed` (when primary image changes → parent can update `image_url`)

---

## User Frontend (vbwd-fe-user-plugin-booking)

### BookingResourceDetail.vue

Replace the single image with a gallery:
- Primary image shown large at the top
- Thumbnail strip below for additional images
- Click thumbnail → swaps with the large image
- Same GHRM detail page style (`.ghrm-detail-icon` becomes a larger image area)

### BookingCatalogue.vue

Resource cards show the primary image (already uses `resource.image_url` which now resolves from the primary gallery image).

---

## Testing

### Backend integration tests (~8 tests)

```
plugins/booking/tests/integration/test_resource_images.py
├── test_upload_image_to_resource
├── test_list_resource_images
├── test_set_primary_image
├── test_reorder_images
├── test_delete_image
├── test_resource_to_dict_includes_images
├── test_primary_image_sets_image_url
└── test_gallery_returns_501_without_cms
```

### Admin e2e tests (~1 test)

```
booking-resource-images.spec.ts
├── login → edit resource
├── verify Images block visible
├── upload an image
├── verify thumbnail appears
├── set as primary
├── verify primary badge
└── cleanup
```

---

## File Changes Summary

### New files

| Repo | File | Description |
|------|------|-------------|
| backend | `booking/models/resource_image.py` | BookableResourceImage model |
| backend | `migrations/versions/20260321_add_resource_images.py` | Migration |
| backend | `tests/integration/test_resource_images.py` | Integration tests |
| fe-admin | `booking/components/ResourceImageGallery.vue` | Image gallery component |

### Modified files

| Repo | File | Change |
|------|------|--------|
| backend | `booking/routes.py` | Add image gallery routes (6 endpoints) |
| backend | `booking/models/resource.py` | Add `images` relationship + update `to_dict()` |
| fe-admin | `booking/stores/resourceAdmin.ts` | Add image CRUD actions |
| fe-admin | `booking/views/ResourceForm.vue` | Include `ResourceImageGallery` block |
| fe-user | `booking/views/BookingResourceDetail.vue` | Gallery display |

---

## Implementation Order

| Step | What | Tests |
|------|------|-------|
| 1 | Backend: model + migration | — |
| 2 | Backend: image gallery routes (CRUD + reorder + primary) | ~8 |
| 3 | Backend: resource model `images` relationship + `to_dict()` | — |
| 4 | Admin: store image actions | — |
| 5 | Admin: ResourceImageGallery.vue component | — |
| 6 | Admin: integrate into ResourceForm.vue | — |
| 7 | User: BookingResourceDetail.vue gallery display | — |
| 8 | Admin: e2e test | ~1 |
| **Total** | | **~9** |

---

## Acceptance Criteria

1. Admin can upload multiple images to a resource
2. Admin can set one image as primary (gold star badge)
3. Admin can drag-to-reorder images
4. Admin can delete images
5. Resource detail API returns `images` array sorted by `sort_order`
6. `image_url` field auto-resolves to primary image URL
7. If CMS plugin is not installed, image gallery block is hidden (no error)
8. Catalogue cards show primary image
9. Resource detail page shows image gallery with thumbnail strip
10. Integration tests pass
11. Mobile responsive — 2 columns on phones
