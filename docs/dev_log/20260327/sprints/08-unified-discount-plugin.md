# Sprint 08 — Unified Discount & Coupon Plugin

**Status:** Pending approval
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · No over-engineering · DevOps-first

---

## Goal

Extract the discount/coupon system from the ecommerce plugin into a standalone `discount` plugin that works across **all** invoice line item types. Subscriptions, ecommerce, and bookings each register their own discount rules via an `IDiscountRule` interface — same pattern as `ILineItemHandler`.

Core stays agnostic. The discount plugin is the orchestrator.

---

## Architecture

### Why a Standalone Plugin?

Discounts are a **cross-cutting billing concern**, not ecommerce-specific:

| Plugin | Discount examples |
|--------|------------------|
| **Subscription** | 30% off first 2 months, loyalty 10% after 12 months, annual billing discount |
| **Ecommerce** | Product sale price, cart-level %, buy-X-get-Y, free shipping |
| **Booking** | Early-bird (X days before), group size ≥5, seasonal rates |
| **Future plugins** | Any line item type may need discounts |

### Core Integration — Zero Core Changes

| Core system | How discount plugin uses it |
|-------------|----------------------------|
| **Event Bus** | Listens to `invoice.before_finalize` to apply discounts |
| **InvoiceLineItem.extra_data** | Stores `discount_amount`, `discount_reason`, `coupon_code` in existing JSON field |
| **Line Item Registry** | Not modified — discount is applied *before* line item activation, not during |
| **Checkout plugin** (fe-user) | Coupon input registered as checkout step via `CheckoutStepRegistry` |
| **Extension Registry** (fe-admin) | Nav items in Sales section |

**No new core columns.** Discount metadata goes into `InvoiceLineItem.extra_data` (already a JSON field) and into the `UserInvoice.extra_data` or a new invoice-level JSON. The discount plugin owns its own tables.

### Plugin Interaction Pattern

```
Discount Plugin (orchestrator)
  ├── IDiscountRule interface
  ├── DiscountRuleRegistry          (like LineItemHandlerRegistry)
  ├── Models: Discount, Coupon, CouponUsage, DiscountApplication
  ├── DiscountService.apply_discounts(invoice) → evaluates all rules
  ├── Routes: admin CRUD + public validate/apply
  └── Event listener: invoice.before_finalize

Subscription Plugin (registers rules)
  └── SubscriptionDiscountRule(IDiscountRule)
      - can_apply(line_item) → item_type == SUBSCRIPTION
      - evaluate(line_item, context) → "30% off first 2 months"

Ecommerce Plugin (registers rules)
  └── EcommerceDiscountRule(IDiscountRule)
      - can_apply(line_item) → extra_data.plugin == "ecommerce"
      - evaluate(line_item, context) → product/cart/shipping discounts

Booking Plugin (registers rules)
  └── BookingDiscountRule(IDiscountRule)
      - can_apply(line_item) → extra_data.plugin == "booking"
      - evaluate(line_item, context) → early-bird, group, seasonal
```

---

## Models (in `plugins/discount/`)

### Discount

```python
class Discount(BaseModel):
    __tablename__ = "discount"

    name: str                          # "Summer Sale 20%"
    slug: str                          # unique
    discount_type: DiscountType        # PERCENTAGE, FIXED_AMOUNT, FREE_SHIPPING, BUY_X_GET_Y
    value: Numeric(10, 2)              # 20.00 = 20% or €5 off
    currency: str                      # For FIXED_AMOUNT (nullable for PERCENTAGE)
    scope: DiscountScope               # GLOBAL, ECOMMERCE, SUBSCRIPTION, BOOKING
    conditions: JSON                   # Scope-specific: product_ids, category_ids, plan_ids, etc.
    min_order_amount: Numeric          # Minimum invoice total to qualify
    max_discount_amount: Numeric       # Cap for percentage discounts
    max_uses: int                      # Total uses (null = unlimited)
    max_uses_per_user: int             # Per-user limit (null = unlimited)
    current_uses: int                  # Counter
    starts_at: DateTime
    expires_at: DateTime
    is_active: bool
    stackable: bool                    # Can combine with other discounts
    priority: int                      # Lower = applied first (for non-stackable)
```

### DiscountType enum

```python
PERCENTAGE = "PERCENTAGE"
FIXED_AMOUNT = "FIXED_AMOUNT"
FREE_SHIPPING = "FREE_SHIPPING"
BUY_X_GET_Y = "BUY_X_GET_Y"
```

### DiscountScope enum

```python
GLOBAL = "GLOBAL"                      # Applies to any line item
ECOMMERCE = "ECOMMERCE"               # Products / cart
SUBSCRIPTION = "SUBSCRIPTION"          # Plans / renewals
BOOKING = "BOOKING"                    # Booking resources
```

### Coupon

```python
class Coupon(BaseModel):
    __tablename__ = "coupon"

    code: str                          # "SUMMER2026" (unique, uppercased)
    discount_id: UUID (FK → discount)
    max_uses: int
    max_uses_per_user: int
    current_uses: int
    is_active: bool
    starts_at: DateTime
    expires_at: DateTime
```

### CouponUsage

```python
class CouponUsage(BaseModel):
    __tablename__ = "coupon_usage"

    coupon_id: UUID (FK)
    user_id: UUID (FK)
    invoice_id: UUID (FK → user_invoice)
    discount_amount: Numeric(10, 2)
    used_at: DateTime
```

### DiscountApplication (audit log)

```python
class DiscountApplication(BaseModel):
    __tablename__ = "discount_application"

    discount_id: UUID (FK)
    invoice_id: UUID (FK)
    line_item_id: UUID (FK, nullable)  # null = invoice-level discount
    user_id: UUID (FK)
    original_amount: Numeric(10, 2)
    discount_amount: Numeric(10, 2)
    final_amount: Numeric(10, 2)
    coupon_id: UUID (FK, nullable)     # If applied via coupon
```

---

## Interfaces

### IDiscountRule

```python
class IDiscountRule(ABC):
    """Interface for plugin-specific discount rules."""

    @abstractmethod
    def can_apply(self, line_item: InvoiceLineItem, discount: Discount) -> bool:
        """Check if this rule can evaluate the given line item + discount combo."""

    @abstractmethod
    def evaluate(self, line_item: InvoiceLineItem, discount: Discount, context: DiscountContext) -> Decimal:
        """Calculate discount amount for the line item. Returns 0 if not applicable."""

    @abstractmethod
    def get_supported_scopes(self) -> list[DiscountScope]:
        """Which discount scopes this rule handles."""
```

### DiscountRuleRegistry

```python
class DiscountRuleRegistry:
    """Registry for plugin discount rules. Same pattern as LineItemHandlerRegistry."""

    def register(self, rule: IDiscountRule) -> None
    def get_rules_for_scope(self, scope: DiscountScope) -> list[IDiscountRule]
    def evaluate_all(self, line_items: list, discounts: list, context: DiscountContext) -> list[DiscountResult]
```

### DiscountContext

```python
@dataclass
class DiscountContext:
    user_id: UUID
    invoice_id: UUID
    coupon_code: str | None
    cart_total: Decimal
    line_item_count: int
    metadata: dict              # Plugin-specific context (e.g., subscription month number)
```

---

## Services

### DiscountService

```python
class DiscountService:
    def __init__(self, registry: DiscountRuleRegistry, discount_repo, coupon_repo, usage_repo):
        ...

    def get_applicable_discounts(self, invoice, user_id) -> list[Discount]
    def apply_discounts(self, invoice, user_id, coupon_code=None) -> list[DiscountApplication]
    def validate_coupon(self, code, user_id, cart_total) -> Coupon
    def redeem_coupon(self, coupon, user_id, invoice_id, discount_amount) -> CouponUsage
    def check_limits(self, discount, user_id) -> bool
```

### Discount Application Flow

```
1. User enters coupon code at checkout (or automatic discounts apply)
2. POST /api/v1/coupons/validate { code, cart_total }
3. DiscountService validates: exists, active, not expired, under limits, min order met
4. Returns applicable discount details + calculated amount
5. On invoice.before_finalize event:
   a. DiscountService collects all applicable discounts (auto + coupon)
   b. For each line item, asks registered IDiscountRules to evaluate
   c. Best/stackable discounts applied
   d. DiscountApplication records created (audit)
   e. Line item extra_data updated with discount info
   f. Invoice total recalculated
6. On payment success: CouponUsage recorded, counters incremented
```

---

## API Routes

### Public

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/v1/coupons/validate` | Validate coupon code against cart |
| POST | `/api/v1/coupons/apply` | Apply coupon to current invoice |
| DELETE | `/api/v1/coupons/remove` | Remove applied coupon |

### Admin

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/admin/discounts` | List discounts (with filters) |
| POST | `/api/v1/admin/discounts` | Create discount |
| GET | `/api/v1/admin/discounts/<id>` | Get discount detail |
| PUT | `/api/v1/admin/discounts/<id>` | Update discount |
| DELETE | `/api/v1/admin/discounts/<id>` | Delete discount |
| GET | `/api/v1/admin/coupons` | List coupons |
| POST | `/api/v1/admin/coupons` | Create coupon |
| GET | `/api/v1/admin/coupons/<id>` | Get coupon detail |
| PUT | `/api/v1/admin/coupons/<id>` | Update coupon |
| DELETE | `/api/v1/admin/coupons/<id>` | Delete coupon |
| GET | `/api/v1/admin/coupons/<id>/usage` | Coupon usage history |
| POST | `/api/v1/admin/coupons/generate` | Bulk generate coupon codes |

---

## Frontend

### Admin (fe-admin)

- **Discounts list** — table with name, type, scope, value, uses, status, date range
- **Discount form** — create/edit with type selector, scope selector, conditions builder (product/plan/category picker based on scope), limits, date range
- **Coupons list** — table with code, linked discount, uses, status
- **Coupon form** — code (manual or auto-generate), link to discount, limits, date range
- **Coupon usage** — table showing who used it, when, which invoice, amount saved
- **Dashboard widget** — top coupons by usage, total discount given this month

### User (fe-user)

- **Coupon input** — registered as checkout step via `CheckoutStepRegistry`
- **Cart summary** — shows: subtotal, discount line (with reason), shipping, tax, total
- **"Remove coupon" button** — clears applied discount
- **Automatic discounts** — shown as "You save X%" without needing a code

---

## Migration from Ecommerce Plugin

The existing `Discount`, `Coupon`, `CouponUsage` models in `plugins/ecommerce/` will be:
1. **Moved** to `plugins/discount/` with new table names (`discount`, `coupon`, `coupon_usage` — no `ecommerce_` prefix)
2. **Alembic migration** renames the existing tables (if data exists) or creates fresh
3. **Ecommerce plugin** removes its discount models, registers `EcommerceDiscountRule` instead
4. **Ecommerce routes** for discount/coupon removed — discount plugin owns those routes

---

## Sub-Sprints

| # | Sprint | Scope |
|---|--------|-------|
| 08a | [Backend: Plugin + Models + Registry](08a-discount-be-models.md) | Plugin skeleton, IDiscountRule, DiscountRuleRegistry, models, repos, migration |
| 08b | [Backend: Service + Routes](08b-discount-be-service.md) | DiscountService, event listener, admin CRUD routes, public validate/apply |
| 08c | [Backend: Plugin Rules](08c-discount-plugin-rules.md) | EcommerceDiscountRule, SubscriptionDiscountRule, BookingDiscountRule — each plugin registers its rule |
| 08d | [Admin Frontend](08d-discount-fe-admin.md) | Discount/coupon management views, usage analytics, dashboard widget |
| 08e | [User Frontend](08e-discount-fe-user.md) | Coupon input checkout step, cart summary discount display, auto-discount badges |
| 08f | [Tests & Compatibility](08f-discount-tests.md) | Integration tests, E2E Playwright, ecommerce migration cleanup, all plugins green |

### Implementation Order

```
08a → 08b → 08c → 08d → 08e → 08f
```

Each sub-sprint is self-contained and tested before moving to the next.

---

## Plugin Skeleton

```
plugins/discount/
├── __init__.py                         DiscountPlugin(BasePlugin)
├── config.json
├── admin-config.json
├── README.md
├── populate_db.py
├── bin/
│   ├── populate-db.sh
│   └── run_populate.py
├── migrations/
│   └── versions/
│       └── 20260329_create_discount_tables.py
├── discount/
│   ├── __init__.py
│   ├── interfaces.py                   IDiscountRule, DiscountContext, DiscountResult
│   ├── registry.py                     DiscountRuleRegistry
│   ├── models/
│   │   ├── __init__.py
│   │   ├── discount.py                 Discount, DiscountType, DiscountScope
│   │   ├── coupon.py                   Coupon
│   │   ├── coupon_usage.py             CouponUsage
│   │   └── discount_application.py     DiscountApplication
│   ├── repositories/
│   │   ├── __init__.py
│   │   ├── discount_repository.py
│   │   ├── coupon_repository.py
│   │   ├── coupon_usage_repository.py
│   │   └── discount_application_repository.py
│   ├── services/
│   │   ├── __init__.py
│   │   └── discount_service.py         DiscountService
│   └── routes.py                       Admin + public routes
└── tests/
    ├── __init__.py
    ├── conftest.py
    ├── unit/
    │   ├── __init__.py
    │   ├── test_discount_service.py
    │   ├── test_registry.py
    │   └── test_models.py
    └── integration/
        ├── __init__.py
        ├── test_discount_routes.py
        └── test_coupon_flow.py
```

### Fe-admin Plugin

```
plugins/discount-admin/
├── index.ts
├── config.json
├── admin-config.json
├── src/
│   ├── views/
│   │   ├── Discounts.vue
│   │   ├── DiscountForm.vue
│   │   ├── Coupons.vue
│   │   ├── CouponForm.vue
│   │   └── CouponUsage.vue
│   └── stores/
│       └── discountAdmin.ts
└── tests/
    └── unit/
        ├── Discounts.spec.ts
        ├── DiscountForm.spec.ts
        ├── Coupons.spec.ts
        └── CouponForm.spec.ts
```

### Fe-user Plugin Extension

No new plugin — the ecommerce plugin registers the coupon checkout step. Cart summary updated to show discounts.

---

## Design Decisions

| Question | Decision |
|----------|----------|
| Stacking | By default non-stackable. Admin can mark a discount as `stackable: true`. |
| Priority | Lower `priority` number wins for non-stackable conflicts. |
| Discount vs negative line item | Stored in `extra_data` of affected line items + `DiscountApplication` audit table. Not a separate negative line item — avoids confusing totals. |
| Scope enforcement | `IDiscountRule.can_apply()` checks scope match. Plugin rule only fires for its own line items. |
| Auto vs coupon | Discounts without a linked coupon apply automatically. Coupon discounts require user to enter code. |
| Coupon code format | Uppercase alphanumeric, 6-12 chars. Auto-generate or manual entry by admin. |

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before implementation. No step done without passing tests. |
| **SOLID** | `IDiscountRule` is Open/Closed — new plugins add rules without modifying existing code. Single responsibility: registry orchestrates, rules evaluate, service coordinates. |
| **Liskov** | All `IDiscountRule` implementations honour the contract — `can_apply()` + `evaluate()` + `get_supported_scopes()`. |
| **DI** | `DiscountService` receives registry + repos via constructor. Plugin rules registered in `on_enable()`. |
| **DRY** | Single `DiscountService.apply_discounts()` flow for all scopes. No per-plugin discount logic in the discount plugin itself. |
| **Clean Code** | Meaningful names. No magic numbers. No bare `except:`. No `# noqa`. |
| **No over-engineering** | No complex rule engine. No expression language. Simple conditions + limits. `conditions` JSON is a flat dict, not a DSL. |
| **DevOps-first** | `pre-commit-check.sh --full` passes in all 3 repos after every sub-sprint. |
| **i18n** | All UI text in 8 languages (en, de, es, fr, ja, ru, th, zh). |

---

## Integration Tests (real PostgreSQL)

```
Discount calculation:
- test_percentage_discount_calculates_correctly
- test_fixed_amount_discount_calculates_correctly
- test_free_shipping_discount_zeroes_shipping_cost
- test_buy_x_get_y_applies_cheapest_free
- test_discount_respects_min_order_amount
- test_discount_capped_by_max_discount_amount
- test_stackable_discounts_combine
- test_non_stackable_discount_priority_wins

Coupon validation:
- test_valid_coupon_returns_discount_details
- test_expired_coupon_rejected
- test_inactive_coupon_rejected
- test_coupon_max_uses_reached_rejected
- test_coupon_per_user_limit_reached_rejected
- test_coupon_min_order_not_met_rejected

Coupon usage:
- test_redeem_coupon_increments_usage_counter
- test_redeem_coupon_creates_usage_record
- test_redeem_coupon_creates_discount_application

Cross-plugin:
- test_subscription_discount_rule_applies_to_subscription_line_items_only
- test_ecommerce_discount_rule_applies_to_ecommerce_line_items_only
- test_booking_discount_rule_applies_to_booking_line_items_only
- test_global_discount_applies_to_all_line_item_types
- test_discount_does_not_apply_to_wrong_scope
```

## Playwright E2E

```
User flow:
- test_enter_coupon_code_at_checkout_shows_discount
- test_invalid_coupon_shows_error_message
- test_remove_coupon_restores_original_total
- test_auto_discount_shown_without_coupon_code

Admin:
- test_admin_create_percentage_discount
- test_admin_create_coupon_linked_to_discount
- test_admin_view_coupon_usage_history
- test_admin_bulk_generate_coupon_codes
```

---

## Pre-commit Validation

Run after every sub-sprint:

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
