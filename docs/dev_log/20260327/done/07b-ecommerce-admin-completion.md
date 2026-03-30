# Sprint 07b — Fe-admin: Product Management Complete

**Status:** Pending approval
**Date:** 2026-03-29
**Repo:** `vbwd-fe-admin`
**Parent:** [07-ecommerce-completion.md](07-ecommerce-completion.md)
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Product List — Bulk Operations

- Checkbox per row
- Select all on page / Select all in shop / Select all active
- Bulk toolbar: Delete, Activate, Deactivate, Export, Import
- Confirmation dialog for destructive actions

## Product Detail — Tabbed Interface (extendable)

```
┌──────────┬───────┬────────┬────────────┐
│ General  │ Stock │ Images │ Categories │  ← tabs (plugins can add more)
└──────────┴───────┴────────┴────────────┘
```

**General tab:** name, slug, sku, price, currency, description, weight, tax_class, is_active, is_digital, has_variants + variant editor

**Stock tab:** per-warehouse stock levels, edit quantity, low stock threshold, reserved count

**Images tab:** CMS image gallery integration
- Upload new images (creates CMS image + links to product)
- Select from CMS image gallery browser
- Drag to reorder
- Star icon to mark featured
- Delete (unlinks, doesn't delete CMS image)

**Categories tab:** two-sided selector
- Left panel: "Available categories" (all categories not assigned)
- Right panel: "Assigned categories" (current product categories)
- Arrow buttons: → assign, ← unassign
- Search/filter on both sides

**Tab extensibility:** uses same pattern as booking's `extensionRegistry.getPlanTabSections()`. Third-party plugins can add, hide, or extend tabs:

```typescript
extensionRegistry.register('my-plugin', {
  productTabSections: [
    { id: 'seo', label: 'SEO', component: SeoTab },
    { id: 'shipping', label: 'Shipping', component: ShippingTab },
  ],
});
```

## Warehouse & Stock Views (functional)

- `Warehouses.vue` — list with name, address, stock count, default badge, create/edit
- `StockOverview.vue` — cross-warehouse table: product name, warehouse columns, total, low stock alerts

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Product list: checkboxes + bulk toolbar | Unit tests |
| 2 | Product list: select all variants (page / all / active) | Unit tests |
| 3 | Product detail: tab container (General/Stock/Images/Categories) | Unit tests |
| 4 | General tab: variant editor (add/remove/edit attributes) | Unit tests |
| 5 | Stock tab: per-warehouse stock editor | Unit tests |
| 6 | Images tab: CMS gallery integration + featured star | Unit tests |
| 7 | Categories tab: two-sided selector | Unit tests |
| 8 | Tab extensibility via extensionRegistry | Unit tests |
| 9 | Warehouses.vue: functional CRUD | Unit tests |
| 10 | StockOverview.vue: cross-warehouse table | Unit tests |
| 11 | `pre-commit-check.sh --full` | — |

---

## Integration Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_bulk_toolbar_renders_on_selection` | Select rows, verify toolbar appears with correct actions |
| 2 | `test_select_all_selects_visible_rows` | Click "Select all on page", verify all checkboxes checked |
| 3 | `test_bulk_delete_calls_api` | Select products, click delete, verify API call with correct IDs |
| 4 | `test_tab_container_switches_tabs` | Click each tab, verify correct panel content |
| 5 | `test_variant_editor_add_remove` | Add variant, remove variant, verify state |
| 6 | `test_stock_tab_shows_per_warehouse` | Load stock tab, verify warehouse rows with quantities |
| 7 | `test_images_tab_upload_and_feature` | Upload image, mark as featured, verify star icon |
| 8 | `test_categories_two_sided_selector` | Assign/unassign categories, verify panels update |
| 9 | `test_tab_extensibility_registers_custom_tab` | Register plugin tab, verify it appears in tab bar |
| 10 | `test_warehouse_crud` | Create, edit, delete warehouse, verify list updates |

## Playwright E2E Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_admin_product_bulk_operations` | Select multiple products, bulk deactivate, verify status change |
| 2 | `test_admin_product_tabs_navigation` | Navigate all tabs, verify content renders |
| 3 | `test_admin_category_two_sided_selector` | Assign and unassign categories via two-sided selector |
| 4 | `test_admin_stock_edit_per_warehouse` | Edit stock quantities, verify saved values |
| 5 | `test_admin_image_gallery_integration` | Upload image, set featured, reorder, verify display |

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
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
```
