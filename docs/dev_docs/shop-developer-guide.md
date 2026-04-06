# Shop Developer Guide

How the shop plugin integrates with core, and how to extend it.

## Architecture Overview

The shop system spans three repositories:

| Repository | Plugin | Role |
|-----------|--------|------|
| `vbwd-backend` | `plugins/shop/` | Products, orders, stock, discounts, API |
| `vbwd-backend` | `plugins/shipping_flat_rate/` | Flat rate shipping provider |
| `vbwd-fe-admin` | `plugins/shop-admin/` | Admin product/order management UI |
| `vbwd-fe-user` | `plugins/shop/` | Catalog, cart, checkout, order history |

All code lives in plugin directories. Core files (`vbwd/`, `vue/src/`) are never modified.

## Core Integration Points

### 1. Line Item Registry

The shop plugin uses **CUSTOM** line items to represent product purchases on invoices. Core does not know about products -- it delegates line item processing to registered handlers.

**Registration** (in `ShopPlugin.__init__.py`):

```python
def register_line_item_handlers(self, registry):
    handler = ShopLineItemHandler(session_factory=db.session, event_bus=event_bus)
    registry.register(handler)
```

**Handler routing** -- `can_handle_line_item()` matches on:

```python
line_item.item_type == LineItemType.CUSTOM
and line_item.extra_data.get("plugin") == "shop"
```

**Three operations:**

| Method | Trigger | What it does |
|--------|---------|-------------|
| `activate_line_item` | Payment captured | Commits stock blocks, creates Order + OrderItem |
| `reverse_line_item` | Refund issued | Sets order to REFUNDED, restores stock |
| `restore_line_item` | Refund reversed | Re-confirms order |

### 2. Event Bus

The plugin publishes events via `event_bus.publish()`. Other plugins (e.g., email) can subscribe.

**Stock events:**

| Event | Data | Trigger |
|-------|------|---------|
| `stock.blocked` | product_id, quantity, session_id, expires_at | Checkout starts |
| `stock.committed` | product_id, quantity, session_id | Payment captured |
| `stock.released` | product_id, quantity, session_id, reason | Timeout/cancellation |
| `stock.restored` | product_id, quantity | Refund issued |

**Order events:**

| Event | Data | Trigger |
|-------|------|---------|
| `order.created` | order_id, order_number, user_id, total | Payment captured |
| `order.refunded` | order_id, user_id | Refund issued |

### 3. Invoicing

The checkout flow creates an invoice with CUSTOM line items:

```python
line_item = InvoiceLineItem(
    item_type=LineItemType.CUSTOM,
    description="Product Name x2",
    quantity=2,
    unit_price=Decimal("29.99"),
    extra_data={
        "plugin": "shop",
        "product_id": "uuid-here",
        "variant_id": "uuid-or-null",
        "warehouse_id": "uuid-or-null",
        "product_name": "Widget",
        "product_sku": "WGT-001",
        "product_slug": "widget",
    }
)
```

After payment capture, core calls `LineItemHandlerRegistry.process_activation()`, which routes to `ShopLineItemHandler`.

## Stock Blocking Flow

Stock is temporarily reserved during checkout to prevent overselling:

```
Customer adds to cart
    │
    ▼
Checkout begins ──► StockService.block_stock()
    │                   ├── Finds best warehouse with available qty
    │                   ├── Increments warehouse_stock.reserved
    │                   ├── Creates StockBlock (status=ACTIVE, expires_at=now+TTL)
    │                   └── Publishes stock.blocked
    ▼
Payment processing
    │
    ├── SUCCESS ──► ShopLineItemHandler.activate_line_item()
    │                   ├── StockService.commit_stock(session_id)
    │                   │       ├── StockBlock.status = COMMITTED
    │                   │       ├── warehouse_stock.reserved -= qty
    │                   │       ├── warehouse_stock.quantity -= qty
    │                   │       └── Publishes stock.committed
    │                   └── Creates Order + OrderItem
    │
    ├── FAILURE ──► StockService.release_stock(session_id)
    │                   ├── StockBlock.status = RELEASED
    │                   ├── warehouse_stock.reserved -= qty
    │                   └── Publishes stock.released
    │
    └── TIMEOUT ──► StockService.cleanup_expired_blocks() (scheduler job)
                        ├── StockBlock.status = EXPIRED
                        └── warehouse_stock.reserved -= qty
```

**Key details:**
- `session_id` is the invoice UUID, linking stock blocks to the checkout session
- `stock_block_ttl_minutes` defaults to 5 minutes (configurable)
- `cleanup_expired_blocks()` should run on a scheduler (e.g., every minute)
- `available = quantity - reserved` at the warehouse level

## Creating a Shipping Plugin

Shipping plugins implement `IShippingProvider` from `vbwd.plugins.shipping_interface`.

### Step 1: Create the plugin directory

```
plugins/my_shipping/
├── __init__.py                  # MyShippingPlugin(BasePlugin)
├── my_shipping/
│   └── provider.py              # MyShippingProvider(IShippingProvider)
└── tests/
    └── unit/
        └── test_provider.py
```

### Step 2: Implement the provider

```python
from vbwd.plugins.shipping_interface import (
    IShippingProvider,
    ShippingRate,
    ShipmentResult,
    TrackingInfo,
)

class MyShippingProvider(IShippingProvider):
    def __init__(self, config):
        self._config = config

    @property
    def slug(self) -> str:
        return "my-shipping"

    @property
    def name(self) -> str:
        return "My Shipping Service"

    def calculate_rate(self, items, address, currency):
        # items: list of dicts with total_price, weight, etc.
        # address: dict with country, postal_code, city, etc.
        # Return one or more ShippingRate options
        return [
            ShippingRate(
                provider_slug=self.slug,
                name="Standard",
                cost=Decimal("9.99"),
                currency=currency,
                estimated_days=7,
            )
        ]

    def create_shipment(self, order):
        # Call carrier API, return tracking info
        return ShipmentResult(
            success=True,
            tracking_number="TRACK123",
            tracking_url="https://carrier.com/track/TRACK123",
        )

    def get_tracking(self, tracking_number):
        # Query carrier API for status
        return TrackingInfo(status="in_transit", location="Berlin")
```

### Step 3: Register the provider

In `__init__.py`:

```python
class MyShippingPlugin(BasePlugin):
    # ... metadata, initialize, etc.

    def register_shipping_providers(self, registry):
        from plugins.my_shipping.my_shipping.provider import MyShippingProvider
        provider = MyShippingProvider(self._config)
        registry.append(provider)
```

### Step 4: Register in plugins.json

```json
{
  "my-shipping": {
    "enabled": true,
    "version": "1.0.0",
    "installedAt": "",
    "source": "local"
  }
}
```

## Discount System

### Discount Types

| Type | Behaviour |
|------|-----------|
| `PERCENTAGE` | Percentage off cart total (with optional max_discount_amount cap) |
| `FIXED_AMOUNT` | Fixed amount off (capped at cart total) |
| `FREE_SHIPPING` | Shipping cost waived (returns 0.00 discount) |

### Coupon Validation

`DiscountService.validate_coupon(code, user_id, cart_total)` checks:

1. Coupon exists and is active
2. Current date is within `starts_at` -- `expires_at` range
3. Global usage limit (`max_uses`) not exceeded
4. Per-user limit (`max_uses_per_user`) not exceeded
5. Associated discount is active
6. Cart meets `min_order_amount` requirement

On success returns the `Coupon` object. On failure raises `CouponValidationError` with a user-friendly message.

### Redemption

After payment capture, call `DiscountService.redeem_coupon()` to:
- Create a `CouponUsage` record
- Increment `coupon.current_uses` and `discount.current_uses`

## Extending the Product Model

To add a new product type or custom fields, create a new model in your own plugin that references the shop product:

```python
class DigitalProductMeta(BaseModel):
    __tablename__ = "digital_product_meta"

    product_id = db.Column(db.UUID, db.ForeignKey("product.id"), nullable=False, unique=True)
    download_url = db.Column(db.String(500))
    file_size_bytes = db.Column(db.BigInteger)
    max_downloads = db.Column(db.Integer, default=5)
```

Register a line item handler in your plugin to handle delivery of the digital product after payment.

## Checkout Extension

The checkout flow in `vbwd-fe-user` supports step injection. To add a step (e.g., gift wrapping):

```typescript
// In your fe-user plugin's install():
sdk.addCheckoutStep({
  id: 'gift-wrap',
  label: 'Gift Wrapping',
  component: () => import('./views/GiftWrapStep.vue'),
  position: 'before:payment',   // before the payment step
  validate: (data) => !!data.giftWrapChoice,
});
```

## Frontend Plugin Architecture

### fe-admin (shop-admin)

The admin plugin:
1. Registers routes via `sdk.addRoute()` -- these become child routes under `/admin/`
2. Injects nav items into the **Sales** sidebar section via `extensionRegistry.register()`
3. Registers a dashboard widget via `sdk.addComponent()`

**extensionRegistry options used:**

```typescript
extensionRegistry.register('shop-admin', {
  sectionItems: {
    sales: [
      {
        label: 'Shop',
        to: '/admin/shop/products',
        id: 'shop',
        children: [
          { label: 'Products', to: '/admin/shop/products' },
          // ...
        ],
      },
    ],
  },
});
```

### fe-user (shop)

The user plugin:
1. Registers public routes via `sdk.addRoute()` with `meta.requiresAuth` flags
2. Uses a Pinia store (`useCartStore`) backed by `localStorage`
3. Named export: `export const shopPlugin: IPlugin`

**Cart persistence strategy:**
- Guest: localStorage only, no API calls
- Authenticated: localStorage is the source of truth; synced to backend on login when `cart_sync_on_login` is enabled

## Access Level Permissions

The shop plugin declares these permissions for the access level system:

| Permission | Action | Controls |
|-----------|--------|----------|
| `shop.products.view` | view | List products, open product detail/edit page (read-only) |
| `shop.products.manage` | manage | Create, update, delete products. Save/Delete buttons visible |
| `shop.orders.view` | view | List orders, view order details |
| `shop.orders.manage` | manage | Ship order, complete order |
| `shop.categories.manage` | manage | Create, edit, delete product categories |
| `shop.stock.manage` | manage | View and update warehouse stock |
| `shop.warehouses.manage` | manage | Manage warehouses |
| `shop.configure` | configure | Configure shipping methods |

**View vs Manage pattern:**
- `view` permission lets the user open list and detail/edit pages in read-only mode
- `manage` permission shows Save/Delete/Create buttons and allows API mutations
- Edit pages require only `view` to open — the Save button is hidden without `manage`

Backend enforcement: every admin route has `@require_permission("shop.xxx.yyy")`.
Frontend enforcement: destructive buttons have `v-if="canManage"` guards.
