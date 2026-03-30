# Sprint 07e — E2E Playwright: Full Shopping Flow

**Status:** Pending approval
**Date:** 2026-03-29
**Repos:** `vbwd-backend`, `vbwd-fe-admin`, `vbwd-fe-user`
**Parent:** [07-ecommerce-completion.md](07-ecommerce-completion.md)
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## The Complete Test

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

## Additional E2E Tests

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

## Steps

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
