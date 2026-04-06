# Sprint 07c — Fe-user: Catalog + Detail + Checkout Complete

**Status:** Pending approval
**Date:** 2026-03-29
**Repo:** `vbwd-fe-user`
**Parent:** [07-ecommerce-completion.md](07-ecommerce-completion.md)
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## ProductCatalog.vue (fix stub)

- Fetch products from `/api/v1/shop/products` on mount
- Category navigation sidebar (from `/api/v1/shop/categories`)
- Search input with debounced API call
- Grid/list view toggle
- Pagination
- Route param `:slug` filters by category
- Stock badge on cards (In Stock / Low Stock / Out of Stock)
- "Add to Cart" button on cards

## ProductDetail.vue (fix stub)

- Fetch product from `/api/v1/shop/products/:slug`
- Image gallery (primary + thumbnails, click to enlarge)
- Variant selector (dropdowns for each attribute: size, color)
- Price updates when variant selected (if variant has own price)
- Stock status per variant
- Quantity selector (max = available stock)
- "Add to Cart" — integrates with `useCartStore`
- Breadcrumb: Shop > Category > Product
- Related products carousel (same category)

## Checkout Flow (NEW)

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

## OrderHistory.vue (fix stub)

- Fetch orders from `/api/v1/shop/orders`
- Order list with status badges, totals, dates
- Click to see order detail

## Steps

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

## Integration Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_catalog_fetches_products_on_mount` | Mount ProductCatalog, verify API call + products rendered |
| 2 | `test_catalog_category_filter` | Click category, verify filtered API call |
| 3 | `test_catalog_search_debounced` | Type search query, verify debounced API call |
| 4 | `test_product_detail_fetches_by_slug` | Navigate to product detail, verify API call with slug |
| 5 | `test_variant_selector_updates_price` | Select variant, verify price display updates |
| 6 | `test_add_to_cart_updates_store` | Click add to cart, verify cart store state |
| 7 | `test_checkout_step_navigation` | Navigate through all checkout steps |
| 8 | `test_checkout_creates_invoice` | Complete checkout, verify invoice creation API call |
| 9 | `test_order_history_fetches_orders` | Mount OrderHistory, verify orders listed |
| 10 | `test_coupon_applies_discount` | Enter coupon code, verify discount applied to total |

## Playwright E2E Tests

| # | Test | Description |
|---|------|-------------|
| 1 | `test_shop_browse_and_filter` | Browse shop, filter by category, search products |
| 2 | `test_product_detail_variant_selection` | View product, select variant, verify price + stock |
| 3 | `test_add_to_cart_and_view_cart` | Add products to cart, verify cart contents |
| 4 | `test_checkout_full_flow` | Cart through checkout with shipping + payment |
| 5 | `test_order_history_after_purchase` | Complete purchase, verify order in history |

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
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
