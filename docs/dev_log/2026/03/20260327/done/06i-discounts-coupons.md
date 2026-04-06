# Sprint 06i — Discount & Coupon System

**Status:** Pending
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first
**Parent:** [06 — E-commerce Plugin Bundle](06-ecommerce-plugin-bundle.md)

---

## Goal

Create a discount and coupon plugin that works with the core invoicing system. Discounts apply to ecommerce products, subscriptions, and bookings. Coupons are user-facing codes. The system integrates as a line item modifier, not a separate line item type.

---

## Architecture

### Core Agnostic

The discount plugin hooks into the invoice creation flow via the event bus. When an invoice is being created, the discount plugin checks for applicable discounts/coupons and modifies line item prices or adds a discount line item.

### Integration Points

| System | How discounts use it |
|--------|---------------------|
| **Event Bus** | Listens to `invoice.creating` (new event) to apply discounts before payment |
| **Invoice model** | Adds discount line items (negative amount) or modifies `total_amount` |
| **Checkout plugin** | Coupon code input field (injected as checkout step) |
| **Extension Registry** | Admin nav in Sales section |

---

## Models

**Discount:**
```python
class Discount(BaseModel):
    __tablename__ = "ecommerce_discount"

    name: str                       # "Summer Sale 20%"
    slug: str
    discount_type: DiscountType     # PERCENTAGE, FIXED_AMOUNT, FREE_SHIPPING
    value: Numeric(10, 2)           # 20.00 (= 20%) or 5.00 (= €5 off)
    currency: str                   # For FIXED_AMOUNT
    scope: DiscountScope            # ALL_PRODUCTS, SPECIFIC_PRODUCTS, SPECIFIC_CATEGORIES, SUBSCRIPTION, BOOKING
    min_order_amount: Numeric       # Minimum cart total to apply
    max_discount_amount: Numeric    # Cap for percentage discounts
    max_uses: int                   # Total uses allowed (null = unlimited)
    max_uses_per_user: int          # Per-user limit (null = unlimited)
    current_uses: int               # Counter
    starts_at: DateTime
    expires_at: DateTime
    is_active: bool
    stackable: bool                 # Can combine with other discounts
    metadata: JSON                  # Product IDs, category IDs for scoped discounts
```

**DiscountType enum:**
```python
PERCENTAGE = "PERCENTAGE"           # 20% off
FIXED_AMOUNT = "FIXED_AMOUNT"      # €5 off
FREE_SHIPPING = "FREE_SHIPPING"    # Shipping cost = 0
BUY_X_GET_Y = "BUY_X_GET_Y"       # Buy 2 get 1 free
```

**DiscountScope enum:**
```python
ALL_PRODUCTS = "ALL_PRODUCTS"
SPECIFIC_PRODUCTS = "SPECIFIC_PRODUCTS"
SPECIFIC_CATEGORIES = "SPECIFIC_CATEGORIES"
SUBSCRIPTION = "SUBSCRIPTION"       # Works on subscription plans
BOOKING = "BOOKING"                 # Works on booking invoices
```

**Coupon:**
```python
class Coupon(BaseModel):
    __tablename__ = "ecommerce_coupon"

    code: str                       # "SUMMER2026" (unique, uppercase)
    discount_id: UUID (FK)          # Links to Discount
    max_uses: int
    max_uses_per_user: int
    current_uses: int
    is_active: bool
    starts_at: DateTime
    expires_at: DateTime
```

**CouponUsage:**
```python
class CouponUsage(BaseModel):
    __tablename__ = "ecommerce_coupon_usage"

    coupon_id: UUID (FK)
    user_id: UUID (FK)
    invoice_id: UUID (FK)
    discount_amount: Numeric(10, 2)
    used_at: DateTime
```

---

## Services

**DiscountService:**
```python
class DiscountService:
    def get_applicable(self, cart_items, user_id) -> list[Discount]
    def calculate_discount(self, discount, cart_items) -> Decimal
    def apply_to_invoice(self, discount, invoice) -> None
    def validate_coupon(self, code, user_id, cart_total) -> Coupon | ValidationError
    def redeem_coupon(self, code, user_id, invoice_id) -> CouponUsage
    def check_limits(self, discount, user_id) -> bool
```

### Discount Application Flow

```
1. User enters coupon code at checkout
2. POST /api/v1/shop/coupons/validate { code: "SUMMER2026", cart_total: 89.00 }
3. Backend validates: exists, active, not expired, under limits, min order met
4. Returns: { valid: true, discount: { type: "PERCENTAGE", value: 20, amount: 17.80 } }
5. Frontend shows discount in cart summary
6. On invoice creation: discount applied as negative line item or price modifier
7. On payment success: coupon usage recorded
```

---

## API Routes

**Public:**
- `POST /api/v1/shop/coupons/validate` — validate coupon code
- `POST /api/v1/shop/coupons/apply` — apply to current cart/invoice

**Admin:**
- `GET/POST /api/v1/admin/shop/discounts` — list, create
- `GET/PUT/DELETE /api/v1/admin/shop/discounts/<id>` — CRUD
- `GET/POST /api/v1/admin/shop/coupons` — list, create
- `GET/PUT/DELETE /api/v1/admin/shop/coupons/<id>` — CRUD
- `GET /api/v1/admin/shop/coupons/<id>/usage` — usage history

---

## Frontend

### Admin
- Discount list + form (type, value, scope, limits, date range)
- Coupon list + form (code generator, link to discount)
- Usage analytics per coupon

### User (checkout)
- Coupon code input field (registered as checkout step via `CheckoutStepRegistry`)
- Cart summary shows: subtotal, discount, shipping, tax, total
- "Remove coupon" button

---

## Steps

| # | What | Tests first |
|---|------|-------------|
| 1 | Discount + Coupon + CouponUsage models + repos | Model tests |
| 2 | DiscountService — calculate, validate, apply, limits | Service tests |
| 3 | Routes: validate/apply coupon, admin CRUD | Route tests |
| 4 | Fe-admin: discount/coupon management views | Unit tests |
| 5 | Fe-user: coupon input in checkout | Unit tests |
| 6 | Cart summary: show discount breakdown | Unit tests |
| 7 | Populate_db: demo discounts + coupons | — |
| 8 | i18n: all 8 languages | — |
| 9 | `pre-commit-check.sh --full` | — |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | DiscountType strategies are polymorphic (PERCENTAGE vs FIXED_AMOUNT). |
| **Liskov** | All discount types honour the calculate interface. |
| **DI** | DiscountService injected, not imported directly. |
| **DRY** | Single `calculate_discount()` method with type-based strategy. |
| **Clean Code** | Meaningful names. No magic numbers. |
| **No over-engineering** | No complex rule engine. Simple conditions + limits. |
| **DevOps-first** | `pre-commit-check.sh --full` passes. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (real PostgreSQL)

```
Discount calculation:
- test_percentage_discount_calculates_correctly
- test_fixed_amount_discount_calculates_correctly
- test_free_shipping_discount_zeroes_shipping_cost
- test_buy_x_get_y_discount_applies_free_item
- test_discount_respects_min_order_amount
- test_discount_capped_by_max_discount_amount

Coupon validation:
- test_valid_coupon_returns_discount_details
- test_expired_coupon_rejected
- test_coupon_max_uses_reached_rejected
- test_coupon_per_user_limit_reached_rejected
- test_coupon_inactive_rejected
- test_coupon_scope_matches_cart_items

Coupon usage:
- test_redeem_coupon_increments_usage_counter
- test_redeem_coupon_creates_usage_record
- test_coupon_applied_to_invoice_as_discount_line_item
```

## Playwright E2E

```
User flow:
- test_enter_coupon_code_at_checkout
    → checkout → enter "SUMMER2026" → discount shown in cart summary → total reduced
- test_invalid_coupon_shows_error
    → enter "EXPIRED123" → error message "Coupon is expired"
- test_remove_coupon_restores_original_total
    → apply coupon → remove coupon → total restored

Admin:
- test_admin_create_discount
    → /admin/shop/discounts/new → fill form → save → visible in list
- test_admin_create_coupon_linked_to_discount
    → /admin/shop/coupons/new → select discount → set code → save
- test_admin_view_coupon_usage_history
    → /admin/shop/coupons/:id/usage → see usage records
```

---

## Pre-commit Validation

Run after every step and before marking sprint as done:

```bash
# Backend (models, services, routes)
cd vbwd-backend && ./bin/pre-commit-check.sh --full

# Admin frontend (management views)
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full

# User frontend (checkout / catalog integration)
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
