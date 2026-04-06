# Sprint 07a — Backend: Missing Routes + CMS Image Integration

**Status:** Pending approval
**Date:** 2026-03-29
**Repo:** `vbwd-backend`
**Parent:** [07-ecommerce-completion.md](07-ecommerce-completion.md)
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Admin Category Routes (NEW)

```
POST   /api/v1/admin/shop/categories          — create category
GET    /api/v1/admin/shop/categories           — list all (flat + tree)
GET    /api/v1/admin/shop/categories/<id>      — detail
PUT    /api/v1/admin/shop/categories/<id>      — update
DELETE /api/v1/admin/shop/categories/<id>      — delete
POST   /api/v1/admin/shop/categories/<id>/assign-products    — assign products
POST   /api/v1/admin/shop/categories/<id>/remove-products    — remove products
```

## Admin Stock Routes (NEW)

```
GET    /api/v1/admin/shop/stock                — cross-warehouse stock overview
PUT    /api/v1/admin/shop/stock/<product_id>   — update stock for product (per warehouse)
```

## Cart Checkout Route (NEW)

```
POST   /api/v1/shop/cart/checkout              — block stock + create invoice + return checkout URL
```

## Product ↔ CMS Image M2M (Reuse booking pattern)

Replace `ProductImage` model with M2M join to CMS images:

```python
class ProductCmsImage(BaseModel):
    __tablename__ = "ecommerce_product_cms_image"

    product_id: UUID (FK → ecommerce_product)
    cms_image_id: UUID (FK → cms_image)
    is_featured: bool               # Star icon in admin (primary image)
    sort_order: int
    # Unique: (product_id, cms_image_id)
```

Product's `primary_image_url` resolves from the featured CMS image. Admin can:
- Upload images directly (creates CMS image + links)
- Select from CMS image gallery
- Mark one as featured (star icon)
- Delete (unlinks, doesn't delete CMS image)
- CMS images have categories — ecommerce products live under a configurable root category slug

## Admin Bulk Product Routes (NEW)

```
POST   /api/v1/admin/shop/products/bulk-delete       — { product_ids: [...] }
POST   /api/v1/admin/shop/products/bulk-activate      — { product_ids: [...] }
POST   /api/v1/admin/shop/products/bulk-deactivate    — { product_ids: [...] }
POST   /api/v1/admin/shop/products/export              — CSV/JSON export
POST   /api/v1/admin/shop/products/import              — CSV/JSON import
```

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Admin category CRUD routes | Route tests |
| 2 | Admin stock routes | Route tests |
| 3 | Cart checkout route (block stock + create invoice) | Integration test |
| 4 | `ProductCmsImage` M2M model + migration | Model tests |
| 5 | Update Product model to resolve images from CMS | Unit tests |
| 6 | Bulk product routes (delete, activate, deactivate, export, import) | Route tests |
| 7 | CMS image category config: `ecommerce_image_root_category_slug` in plugin config | — |
| 8 | `pre-commit-check.sh --full` | — |

---

## Integration Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_admin_create_category` | POST category, verify 201 + persisted |
| 2 | `test_admin_list_categories_tree` | GET categories with parent/child hierarchy |
| 3 | `test_admin_assign_products_to_category` | Assign products, verify M2M records |
| 4 | `test_admin_stock_overview` | GET cross-warehouse stock, verify aggregation |
| 5 | `test_admin_update_stock` | PUT stock per warehouse, verify quantity change |
| 6 | `test_cart_checkout_blocks_stock` | POST checkout, verify stock reserved |
| 7 | `test_cart_checkout_creates_invoice` | POST checkout, verify invoice with CUSTOM line items |
| 8 | `test_product_cms_image_m2m` | Link CMS image to product, verify featured resolution |
| 9 | `test_bulk_delete_products` | Bulk delete, verify all removed |
| 10 | `test_bulk_activate_deactivate` | Toggle is_active on multiple products |

## Playwright E2E Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_admin_category_crud_flow` | Create, edit, delete category via admin UI |
| 2 | `test_admin_stock_update_flow` | Update stock levels via admin stock overview |
| 3 | `test_checkout_creates_order` | Cart to checkout, verify order created in admin |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | Product tabs are Open/Closed — plugins extend without modifying core. |
| **Liskov** | All tab components honour the tab interface. |
| **DI** | Services via container, handlers via registry. |
| **DRY** | CMS image gallery reused (not duplicated). Booking M2M pattern reused. |
| **Clean Code** | Meaningful names. No stubs left. |
| **No over-engineering** | Two-sided selector is a simple component, not a drag-and-drop framework. |
| **DevOps-first** | `pre-commit-check.sh --full` passes on all repos. |
| **i18n** | All new UI text in 8 languages. |

---

## Pre-commit Validation

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
```
