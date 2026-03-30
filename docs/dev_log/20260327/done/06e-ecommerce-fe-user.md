# Sprint 06e — E-commerce User Frontend

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Create `ecommerce` plugin for fe-user with product catalog, cart, checkout extension, order history. Register reusable widgets (like CMS does) that can be embedded in CMS layouts or standalone pages.

---

## Three Layers: Widgets, Layouts, Pages

Following the CMS plugin pattern, ecommerce provides three layers:

### 1. Widgets (reusable components)

Registered via a widget registry (same pattern as `registerCmsVueComponent`). Can be embedded in CMS page layouts or used standalone.

| Widget | Purpose | Embeddable in CMS? |
|--------|---------|-------------------|
| `ProductCard` | Single product card (image, name, price, add-to-cart) | Yes |
| `ProductGrid` | Grid of products (accepts category slug filter) | Yes |
| `ProductCarousel` | Horizontal scroll of featured/related products | Yes |
| `CategoryNav` | Category tree navigation sidebar | Yes |
| `CartSummary` | Mini cart (item count, total, checkout button) | Yes |
| `CartWidget` | Floating cart icon with badge (for topbar/layout) | Yes |
| `AddToCartButton` | Standalone add-to-cart button (by product slug) | Yes |
| `OrderStatusTimeline` | Visual order status progress | No (order detail only) |

Registered in `install()`:
```typescript
import { registerCmsVueComponent } from '../../plugins/cms/src/registry/vueComponentRegistry';

// Register ecommerce widgets for CMS layout embedding
registerCmsVueComponent('ProductGrid', ProductGrid);
registerCmsVueComponent('ProductCard', ProductCard);
registerCmsVueComponent('ProductCarousel', ProductCarousel);
registerCmsVueComponent('CategoryNav', CategoryNav);
registerCmsVueComponent('CartSummary', CartSummary);
registerCmsVueComponent('CartWidget', CartWidget);
registerCmsVueComponent('AddToCartButton', AddToCartButton);
```

### 2. Layout Components (page sections)

Used by the ecommerce pages but also available for custom CMS layouts:

| Component | Purpose |
|-----------|---------|
| `ShopHeader` | Category breadcrumb + search bar + cart icon |
| `ProductFilters` | Price range, category, availability sidebar |
| `ShippingAddressStep` | Checkout step: shipping address form |
| `ShippingMethodStep` | Checkout step: select shipping provider |
| `CartLineItems` | Cart page: editable line items with quantity controls |

### 3. Pages (full views)

Registered as routes via `sdk.addRoute()`:

| Page | Route | Description |
|------|-------|-------------|
| `ProductCatalog.vue` | `/shop` | Product grid with category filter, search, pagination |
| `ProductCatalog.vue` | `/shop/category/:slug` | Filtered by category |
| `ProductDetail.vue` | `/shop/product/:slug` | Full product page: images, description, variants, stock, add-to-cart |
| `Cart.vue` | `/shop/cart` | Full cart page: line items, quantity edit, remove, subtotal, checkout button |
| `OrderHistory.vue` | `/shop/orders` | User's past orders |
| `OrderDetail.vue` | `/shop/orders/:id` | Order detail with items, status timeline, tracking |

---

## Plugin Structure

```
plugins/ecommerce/
├── ecommerce/
│   ├── views/
│   │   ├── ProductCatalog.vue       Grid/list with filters, search, category nav
│   │   ├── ProductDetail.vue        Full product page with gallery, stock, add-to-cart
│   │   ├── Cart.vue                 Shopping cart with quantity controls + checkout CTA
│   │   ├── OrderHistory.vue         User's orders list
│   │   └── OrderDetail.vue          Order detail with tracking timeline
│   ├── components/
│   │   ├── widgets/
│   │   │   ├── ProductCard.vue
│   │   │   ├── ProductGrid.vue
│   │   │   ├── ProductCarousel.vue
│   │   │   ├── CategoryNav.vue
│   │   │   ├── CartSummary.vue
│   │   │   ├── CartWidget.vue
│   │   │   └── AddToCartButton.vue
│   │   ├── layout/
│   │   │   ├── ShopHeader.vue
│   │   │   └── ProductFilters.vue
│   │   ├── checkout/
│   │   │   ├── ShippingAddressStep.vue
│   │   │   └── ShippingMethodStep.vue
│   │   └── OrderStatusTimeline.vue
│   └── stores/
│       ├── products.ts              Product catalog store (search, filter, pagination)
│       ├── cart.ts                  Cart state (localStorage guest / backend user)
│       └── orders.ts               User orders store
├── locales/{en,de,es,fr,ja,ru,th,zh}.json
├── index.ts
├── config.json
├── admin-config.json
└── tests/unit/
```

---

## Cart Page (`Cart.vue`)

Full-page shopping cart with:

- Product image + name (linked to product detail)
- Unit price
- Quantity selector (min 1, max = available stock)
- Remove button per item
- Line item total
- Subtotal + estimated shipping + tax + total
- "Continue Shopping" link → `/shop`
- "Proceed to Checkout" button → triggers stock blocking + redirects to checkout
- Empty cart state with CTA to browse products

---

## Product Detail Page (`ProductDetail.vue`)

- Image gallery (primary + thumbnails, like booking resource)
- Product name, description (rich text)
- Price (with currency)
- Stock status badge: "In Stock" / "Low Stock (3 left)" / "Out of Stock"
- Quantity selector
- "Add to Cart" button (disabled when out of stock)
- Category breadcrumb
- Related products carousel (from same category)

---

## Checkout Extension

Extends existing `checkout` plugin via `checkoutContextRegistry`:

```typescript
checkoutContextRegistry.register({
  plugin: 'ecommerce',
  steps: [
    { id: 'shipping-address', component: ShippingAddressStep, order: 10 },
    { id: 'shipping-method', component: ShippingMethodStep, order: 20 },
  ],
  cartSummary: CartLineItems,  // Replaces default plan summary in checkout
});
```

---

## CMS Integration — Import Files + Populate

Following the booking plugin pattern, ecommerce provides CMS import files for layouts, pages, and widgets:

```
plugins/ecommerce/docs/imports/cms/
├── layouts/
│   ├── shop-catalogue.json           Layout: category nav + product grid + filters
│   └── shop-product-detail.json      Layout: image gallery + product info + related
├── pages/
│   ├── shop.json                     CMS page: /shop (uses shop-catalogue layout)
│   └── shop-product-detail.json      CMS page: /shop/product/:slug (uses product-detail layout)
├── widgets/
│   ├── product-grid.json             Widget config: ProductGrid with category filter
│   ├── product-carousel.json         Widget config: ProductCarousel (featured products)
│   ├── category-nav.json             Widget config: CategoryNav sidebar
│   ├── cart-summary.json             Widget config: CartSummary mini-cart
│   └── add-to-cart-button.json       Widget config: AddToCartButton by product slug
└── email/
    └── ecommerce-email-templates.json  order.created, order.shipped, order.completed templates

plugins/ecommerce/populate_db.py:
  - Creates demo product categories (Electronics, Clothing, Books)
  - Creates demo products with images (5-10 products)
  - Creates demo warehouse + stock
  - Imports CMS layouts + pages + widgets from docs/imports/cms/
  - Imports email templates from docs/imports/email/
```

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Plugin skeleton + index.ts + configs + route registration | — |
| 2 | Cart store (localStorage + backend sync) | `tests/unit/stores/test_cart.spec.ts` |
| 3 | Products store (catalog, search, filter) | `tests/unit/stores/test_products.spec.ts` |
| 4 | Orders store | `tests/unit/stores/test_orders.spec.ts` |
| 5 | Widget components: ProductCard, ProductGrid, CartSummary, CartWidget | Unit tests |
| 6 | ProductCatalog.vue + ProductFilters + CategoryNav | Unit tests |
| 7 | ProductDetail.vue + AddToCartButton + image gallery | Unit tests |
| 8 | Cart.vue page (quantity edit, remove, checkout CTA) | Unit tests |
| 9 | OrderHistory + OrderDetail + OrderStatusTimeline | Unit tests |
| 10 | Checkout extension: ShippingAddressStep + ShippingMethodStep | Unit tests |
| 11 | Register widgets in CMS widget registry | — |
| 12 | i18n: all 8 languages | — |
| 13 | `pre-commit-check.sh --full` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | Single responsibility per service/component. Open/Closed for shipping providers. |
| **Liskov** | All `IShippingProvider` and `ILineItemHandler` implementations honour contracts. |
| **DI** | Dependencies injected. Services via container, handlers via registry. |
| **DRY** | No duplicate logic. Shared patterns from booking plugin reused. |
| **Clean Code** | No `console.log`, no `as any`, no bare `except:`. Meaningful variable names. |
| **No over-engineering** | Minimum complexity. Stock blocking is a simple TTL table, not a distributed lock. |
| **DevOps-first** | `pre-commit-check.sh --full` passes. CI-ready from day one. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (Vitest with mocked API)

```
Catalog:
- test_product_catalog_renders_grid_with_products
- test_product_catalog_filters_by_category
- test_product_catalog_search_by_name
- test_product_catalog_pagination
- test_product_catalog_grid_list_toggle

Product detail:
- test_product_detail_shows_images_and_description
- test_product_detail_shows_stock_status_badge
- test_product_detail_add_to_cart_updates_cart_count
- test_product_detail_variant_selector_updates_price
- test_product_detail_out_of_stock_disables_add_button

Cart:
- test_cart_renders_line_items_with_quantities
- test_cart_update_quantity_recalculates_total
- test_cart_remove_item
- test_cart_empty_state_shows_browse_cta
- test_cart_localStorage_persistence_for_guests
- test_cart_backend_sync_for_logged_in_users
- test_cart_login_merge_prompt (guest → user)

Checkout:
- test_checkout_shows_shipping_address_step
- test_checkout_shows_shipping_method_step
- test_checkout_shipping_method_updates_total

Orders:
- test_order_history_renders_past_orders
- test_order_detail_shows_items_and_tracking
- test_order_status_timeline_renders_correctly
```

## Playwright E2E

```
Full shopping flow:
- test_browse_catalog_filter_by_category_view_product
    → /shop → click category → see filtered products → click product → detail page
- test_add_to_cart_and_view_cart
    → product detail → set quantity → "Add to Cart" → cart icon badge updates → /shop/cart
- test_cart_update_quantity_and_remove
    → /shop/cart → change quantity → total updates → remove item → item gone
- test_full_checkout_flow_with_shipping
    → /shop/cart → "Checkout" → shipping address → shipping method → payment (mocked) → order confirmation
- test_order_appears_in_history
    → complete checkout → /shop/orders → new order visible with correct status
- test_order_detail_shows_tracking_after_shipment
    → /shop/orders/:id → see tracking number and link

Stock blocking:
- test_stock_decrements_during_checkout
    → add item (stock=5) → checkout → product shows stock=4
- test_stock_restores_on_checkout_timeout
    → add item → start checkout → wait → stock restored

Widget embedding:
- test_product_grid_widget_renders_in_cms_page
    → CMS page with ProductGrid widget → products visible
- test_cart_widget_shows_count_in_topbar
    → add item → CartWidget badge shows "1"
```

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
cd vbwd-fe-user && ./bin/pre-commit-check.sh --style      # ESLint + TypeScript
cd vbwd-fe-user && ./bin/pre-commit-check.sh --unit       # Vitest unit tests
cd vbwd-fe-user && ./bin/pre-commit-check.sh --e2e        # Playwright E2E tests
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full       # All of the above
```
