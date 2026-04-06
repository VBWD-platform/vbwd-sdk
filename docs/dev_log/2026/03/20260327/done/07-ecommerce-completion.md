# Sprint 07 — E-commerce Completion & Full Shopping Flow

**Status:** Pending approval
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Problem Analysis

The ecommerce plugin has a solid foundation (models, repos, services, line item handler, migration) but most frontend views are stubs and critical flows are broken. This sprint completes everything needed for a working end-to-end shopping experience.

### Critical Issues

| # | Issue | Severity |
|---|-------|----------|
| 1 | **Shop page shows "No products"** — `ProductCatalog.vue` fetch logic missing (stub) | CRITICAL |
| 2 | **Checkout flow broken** — no `/shop/checkout` route, no Checkout.vue component | CRITICAL |
| 3 | **ProductDetail.vue stub** — no fetch, no variants, no image gallery, no cart integration | CRITICAL |
| 4 | **Admin categories CRUD missing** — no backend routes, no frontend forms | HIGH |
| 5 | **Admin stock/warehouse stubs** — placeholder text only | HIGH |
| 6 | **No bulk operations on Products** — no checkboxes, select all, bulk actions | HIGH |
| 7 | **OrderHistory.vue stub** — no fetch logic | HIGH |
| 8 | **Product images use own model** — should reuse CMS image gallery (like booking) | MEDIUM |
| 9 | **No product admin tabs** — General/Stock/Images/Categories tabs missing | MEDIUM |
| 10 | **No CMS page/layout/widget imports** — shop page not wired to CMS | MEDIUM |
| 11 | **Two-sided category selector** — admin product detail needs category assignment tab | MEDIUM |

---

## Sub-Sprints

| # | Sprint | Scope |
|---|--------|-------|
| 07a | [Backend: Missing Routes + CMS Image Integration](07a-ecommerce-backend-completion.md) | Admin category CRUD, stock routes, cart checkout route, product ↔ CMS image M2M |
| 07b | [Fe-admin: Product Management Complete](07b-ecommerce-admin-completion.md) | Bulk ops, tabs (General/Stock/Images/Categories), two-sided category selector, warehouse/stock views |
| 07c | [Fe-user: Catalog + Detail + Checkout Complete](07c-ecommerce-user-completion.md) | ProductCatalog fetch, ProductDetail with images/variants/cart, checkout flow, order history |
| 07d | [CMS Integration: Pages + Layouts + Widgets](07d-ecommerce-cms-integration.md) | Shop CMS page, product detail layout, widget imports, public routing |
| 07e | [E2E Playwright: Full Shopping Flow](07e-ecommerce-e2e-playwright.md) | Complete end-to-end test with Stripe payment, emails via mailpit, webhook-triggered events |

---

## 07a — Backend: Missing Routes + CMS Image Integration {#07a}

### Admin Category Routes (NEW)

```
POST   /api/v1/admin/shop/categories          — create category
GET    /api/v1/admin/shop/categories           — list all (flat + tree)
GET    /api/v1/admin/shop/categories/<id>      — detail
PUT    /api/v1/admin/shop/categories/<id>      — update
DELETE /api/v1/admin/shop/categories/<id>      — delete
POST   /api/v1/admin/shop/categories/<id>/assign-products    — assign products
POST   /api/v1/admin/shop/categories/<id>/remove-products    — remove products
```

### Admin Stock Routes (NEW)

```
GET    /api/v1/admin/shop/stock                — cross-warehouse stock overview
PUT    /api/v1/admin/shop/stock/<product_id>   — update stock for product (per warehouse)
```

### Cart Checkout Route (NEW)

```
POST   /api/v1/shop/cart/checkout              — block stock + create invoice + return checkout URL
```

### Product ↔ CMS Image M2M (Reuse booking pattern)

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
- CMS images have categories — ecommerce products live under a configurable root category slug

### Admin Bulk Product Routes (NEW)

```
POST   /api/v1/admin/shop/products/bulk-delete       — { product_ids: [...] }
POST   /api/v1/admin/shop/products/bulk-activate      — { product_ids: [...] }
POST   /api/v1/admin/shop/products/bulk-deactivate    — { product_ids: [...] }
POST   /api/v1/admin/shop/products/export              — CSV/JSON export
POST   /api/v1/admin/shop/products/import              — CSV/JSON import
```

### Steps

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

## 07b — Fe-admin: Product Management Complete {#07b}

### Product List — Bulk Operations

- Checkbox per row
- Select all on page / Select all in shop / Select all active
- Bulk toolbar: Delete, Activate, Deactivate, Export, Import
- Confirmation dialog for destructive actions

### Product Detail — Tabbed Interface (extendable)

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

### Warehouse & Stock Views (functional)

- `Warehouses.vue` — list with name, address, stock count, default badge, create/edit
- `StockOverview.vue` — cross-warehouse table: product name, warehouse columns, total, low stock alerts

### Steps

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

## 07c — Fe-user: Catalog + Detail + Checkout Complete {#07c}

### ProductCatalog.vue (fix stub)

- Fetch products from `/api/v1/shop/products` on mount
- Category navigation sidebar (from `/api/v1/shop/categories`)
- Search input with debounced API call
- Grid/list view toggle
- Pagination
- Route param `:slug` filters by category
- Stock badge on cards (In Stock / Low Stock / Out of Stock)
- "Add to Cart" button on cards

### ProductDetail.vue (fix stub)

- Fetch product from `/api/v1/shop/products/:slug`
- Image gallery (primary + thumbnails, click to enlarge)
- Variant selector (dropdowns for each attribute: size, color)
- Price updates when variant selected (if variant has own price)
- Stock status per variant
- Quantity selector (max = available stock)
- "Add to Cart" — integrates with `useCartStore`
- Breadcrumb: Shop > Category > Product
- Related products carousel (same category)

### Checkout Flow (NEW)

Route: `/shop/checkout` — uses `CheckoutStepRegistry` from Sprint 06h:

```
Step 1: Cart review (products, quantities, subtotal)
Step 2: Shipping address (form)
Step 3: Shipping method (select from providers)
Step 4: Coupon code input (optional)
Step 5: Payment (Stripe/PayPal via existing payment plugins)
→ Order confirmation page
```

Backend flow:
1. `POST /api/v1/shop/cart/checkout` — block stock, create invoice with CUSTOM line items
2. Payment plugin redirects to Stripe/PayPal
3. On payment success → `EcommerceLineItemHandler.activate_line_item()` → creates Order + commits stock
4. Redirect to order confirmation

### OrderHistory.vue (fix stub)

- Fetch orders from `/api/v1/shop/orders`
- Order list with status badges, totals, dates
- Click to see order detail

### Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | ProductCatalog: fetch + category nav + search + pagination | Unit tests |
| 2 | ProductDetail: fetch + image gallery + variant selector | Unit tests |
| 3 | ProductDetail: add-to-cart integration with cart store | Unit tests |
| 4 | Checkout.vue: step-based flow using CheckoutStepRegistry | Unit tests |
| 5 | ShippingAddressStep + ShippingMethodStep components | Unit tests |
| 6 | CouponCodeStep component | Unit tests |
| 7 | Cart → checkout → invoice creation API integration | Integration tests |
| 8 | OrderHistory + OrderDetail: fetch and display | Unit tests |
| 9 | `pre-commit-check.sh --full` | — |

---

## 07d — CMS Integration: Pages + Layouts + Widgets {#07d}

### Shop is a CMS page (public, not dashboard)

The `/shop` URL should render as a CMS page with the `shop-catalogue` layout, not as a Vue router page behind authentication. The ecommerce plugin registers a CMS page at slug `shop` with:
- Layout: `shop-catalogue` (header + category nav + product grid + footer)
- The `ProductGrid` and `CategoryNav` are CMS vue-component widgets

### Widget Consistency

Ensure all ecommerce widgets work as CMS vue-components:
- `ProductGrid` — configurable: category filter, items per page
- `ProductCard` — single product by slug
- `ProductCarousel` — featured/related products
- `CategoryNav` — category tree sidebar
- `CartSummary` — mini cart (item count + total)
- `AddToCartButton` — by product slug

### Product Detail Page Layout

CMS layout `shop-product-detail`:
- Areas: header, breadcrumbs, product-detail (vue component), related-products (carousel), footer
- The `/shop/product/:slug` route renders this layout

### Import Files Update

Update `docs/imports/cms/` JSON files + `populate_db.py` to create functional CMS pages that actually render the widgets.

### Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Register ecommerce widgets in CMS vue-component registry | — |
| 2 | Update populate_db to create functional CMS pages with widget assignments | — |
| 3 | Ensure `/shop` renders as CMS page (public, no auth) | Integration test |
| 4 | Ensure `/shop/product/:slug` renders product detail via CMS layout | Integration test |
| 5 | Test all widgets render correctly in CMS context | Unit tests |
| 6 | `pre-commit-check.sh --full` | — |

---

## 07e — E2E Playwright: Full Shopping Flow {#07e}

### The Complete Test

One Playwright test that exercises the entire ecommerce system end-to-end:

```
test('complete shopping flow with payment and email notifications', async ({ page }) => {
  // 1. Browse shop (public, no login)
  → go to /shop
  → see product categories in sidebar
  → click "Electronics" category
  → see filtered products (Wireless Headphones, USB-C Cable)

  // 2. Select configurable product
  → click "Wireless Headphones"
  → product detail page loads with images, description, price
  → select variant: "Black"
  → stock shows "In Stock (30 available)"
  → set quantity to 2
  → click "Add to Cart"
  → cart badge shows "2"

  // 3. Add another product
  → go to /shop
  → click "USB-C Cable"
  → click "Add to Cart"
  → cart badge shows "3"

  // 4. View cart
  → go to /shop/cart
  → see 2 items (Headphones x2, Cable x1)
  → subtotal: €172.97

  // 5. Apply coupon
  → enter coupon code "SUMMER20"
  → discount applied: -€34.59 (20%)
  → new total: €138.38

  // 6. Checkout
  → click "Proceed to Checkout"
  → Step 1: shipping address form → fill → next
  → Step 2: shipping method → select "Flat Rate €5.99" → next
  → Step 3: review order → total: €144.37 (subtotal + shipping - discount)
  → Step 4: payment → Stripe test card 4242...
  → payment redirects to Stripe, completes

  // 7. Verify order created
  → redirected to order confirmation
  → order number displayed
  → status: "Confirmed"

  // 8. Check emails in mailpit
  → verify "Order confirmed" email received
  → verify email contains order number, product names, total

  // 9. Admin ships order
  → login to admin
  → /admin/shop/orders → find order → click
  → click "Ship" → enter tracking number → confirm
  → order status: "Shipped"

  // 10. Verify shipping email
  → check mailpit → "Your order has been shipped" email
  → contains tracking number

  // 11. Admin completes order
  → click "Complete" → order status: "Completed"
  → check mailpit → "Order complete" email with review link

  // 12. Verify stock decremented
  → /admin/shop/stock → Wireless Headphones Black: was 30, now 28
  → USB-C Cable: was 200, now 199
});
```

### Additional E2E Tests

```
Admin product management:
- test_admin_create_product_with_images_and_variants
- test_admin_bulk_select_and_deactivate
- test_admin_category_two_sided_selector
- test_admin_stock_edit_per_warehouse

Public catalog:
- test_shop_page_loads_as_cms_page_no_auth
- test_category_filter_shows_correct_products
- test_search_finds_products_by_name
- test_out_of_stock_product_shows_disabled_button

Cart:
- test_cart_persists_after_page_reload
- test_cart_quantity_update_recalculates_total
- test_cart_remove_item
```

### Steps

| # | What |
|---|------|
| 1 | Setup: mock Stripe, seed demo data, configure mailpit |
| 2 | Full shopping flow E2E test |
| 3 | Admin product management E2E tests |
| 4 | Public catalog E2E tests |
| 5 | Cart E2E tests |
| 6 | `npx playwright test` passes |

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
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
npx playwright test
```
