# Sprint 06 — E-commerce Plugin Bundle

**Status:** Pending approval
**Date:** 2026-03-29
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Create a full e-commerce plugin bundle (backend + fe-admin + fe-user) for selling physical and digital products. Uses core invoicing via `CUSTOM` line items. Includes stock management with blocking, shipping method plugins (same pattern as payment plugins), partial refunds, and warehouse support. Extends the existing checkout plugin for the storefront flow.

---

## Architecture

### Core Integration Points

| Core system | How ecommerce uses it |
|-------------|----------------------|
| **Invoicing** | Creates invoices with `CUSTOM` line items (`plugin: "ecommerce"`) |
| **Line Item Registry** | Registers `EcommerceLineItemHandler` for order fulfillment on payment |
| **Event Bus** | `stock.blocked`, `stock.committed`, `stock.released`, `order.created`, `order.shipped`, etc. |
| **Checkout plugin** (fe-user) | **Extended** — adds shipping address step + shipping method selection |
| **Payment plugins** | Standard payment flow (Stripe, PayPal) — no changes needed |
| **Token economy** | Optional: products can cost tokens instead of/in addition to money |
| **Extension Registry** (fe-admin) | Sidebar nav via `sectionItems.sales`, dashboard widgets |
| **Shipping plugins** | Same pattern as payment plugins — `IShippingProvider` interface |

### Plugin Does NOT Modify Core

- No core model changes
- No core route changes
- No core handler changes
- Line item type: `CUSTOM` (existing), identified by `metadata.plugin === "ecommerce"`
- Shipping providers: plugin-based, registered via core plugin system

---

## Sub-Sprints

| # | Sprint | Scope |
|---|--------|-------|
| 06h | [Checkout Plugin Extension](06h-checkout-plugin-extension.md) | **FIRST** — step-based checkout extension architecture |
| 06a | [Backend: Models + Stock Management](06a-ecommerce-be-models.md) | Product + variants, category, warehouse, stock, order models + repos |
| 06b | [Backend: Services + Line Item Handler](06b-ecommerce-be-services.md) | Stock service (blocking), order service, cart, EcommerceLineItemHandler |
| 06c | [Backend: Routes + Shipping Interface](06c-ecommerce-be-routes-shipping.md) | Public catalog + admin CRUD + `IShippingProvider` core interface |
| 06d | [Frontend: Admin (fe-admin)](06d-ecommerce-fe-admin.md) | Product/category/order/warehouse management + dashboard widgets |
| 06e | [Frontend: User (fe-user)](06e-ecommerce-fe-user.md) | Catalog, cart, widgets, CMS integration, checkout extension, orders |
| 06f | [Shipping Plugins](06f-shipping-plugins.md) | Flat rate + weight-based shipping (reference implementations) |
| 06g | [Tests & Compatibility](06g-ecommerce-tests.md) | Unit + integration + E2E, all plugins green |
| 06i | [Discounts & Coupons](06i-discounts-coupons.md) | Percentage/fixed/free-shipping discounts, coupon codes, usage limits |
| 06j | [Product Reviews & Ratings](06j-product-reviews.md) | Star ratings, review moderation, verified purchase badge |
| 06k | [Wishlist / Favorites](06k-wishlist.md) | Heart icon, wishlist page, guest localStorage, move-to-cart |
| 06l | [Abandoned Cart Recovery](06l-abandoned-cart-recovery.md) | 3-stage email reminders, auto-discount on final reminder, analytics |

---

## Implementation Order

```
06h → 06a → 06b → 06c → 06f → 06d → 06e → 06i → 06j → 06k → 06l → 06g
 │      │      │      │      │      │      │      │      │      │      │      │
 │      └──────┴──────┴──────┘      │      └──────┘      │      │      │      │
 │         Backend core              │     Frontend       │      │      │      │
 │                                   │                    │      │      │      │
 Checkout extension                  Shipping             Disc.  Rev.   Wish.  Tests
 (prerequisite)                      plugins              coupons       list   final
```

---

## Design Decisions

| Question | Decision |
|----------|----------|
| Stock blocking trigger | Checkout only — not on add-to-cart |
| Warehouse selection | Admin configures mode: closest to address, highest stock, or auto (closest first, fallback to highest) |
| Product variants | Yes — `ProductVariant` model (size, color) with own SKU, price, stock |
| Digital product delivery | Download link in order detail + emailed to user |
| Guest cart → login merge | Ask the user (merge / replace / keep existing) |
| Shipping zone editor | Full UI editor in admin (not raw JSON) |
| Tax calculation | Use core's `TaxService` + `TaxRepository` |
| Checkout extension | New sprint 06h — `CheckoutStepRegistry` before 06e |
| Order email notifications | All events: created, confirmed, shipped, delivered, completed, cancelled, refunded |
| Stock display | Per-warehouse (for "ships from" display + delivery estimates) |

---

## 06a — Backend: Models + Stock Management {#06a}

### Models

```
plugins/ecommerce/ecommerce/models/
├── product.py
├── product_category.py
├── product_image.py
├── warehouse.py
├── warehouse_stock.py
├── stock_block.py
├── order.py
└── order_item.py
```

**Product:**
```python
class Product(BaseModel):
    __tablename__ = "ecommerce_product"

    name: str                       # "Wireless Headphones"
    slug: str                       # "wireless-headphones" (unique, indexed)
    description: str                # Rich text / markdown
    sku: str                        # Stock keeping unit (unique, nullable)
    price: Numeric(10, 2)           # Base price
    currency: str                   # "EUR"
    price_float: float              # For fast sorting/filtering
    is_active: bool                 # Published/draft
    is_digital: bool                # No shipping needed
    sort_order: int
    weight: Numeric(10, 3)          # kg — for shipping calculation
    dimensions: JSON                # { length, width, height } cm
    metadata: JSON                  # Flexible product attributes (color, size, etc.)
    tax_class: str                  # "standard", "reduced", "zero" — for tax calculation
    has_variants: bool              # True if product uses variant system
```

**ProductVariant** (size S/M/L, color red/blue — each variant has own SKU/price/stock):
```python
class ProductVariant(BaseModel):
    __tablename__ = "ecommerce_product_variant"

    product_id: UUID (FK)
    name: str                       # "Large / Red"
    sku: str                        # Unique variant SKU (nullable, fallback to product SKU)
    price: Numeric(10, 2)           # Variant-specific price (nullable — fallback to product price)
    price_float: float
    weight: Numeric(10, 3)          # Variant-specific weight (nullable — fallback to product)
    is_active: bool
    sort_order: int
    attributes: JSON                # { "size": "L", "color": "Red" }
    image_url: str                  # Variant-specific image (nullable)
    # Stock is tracked per variant in WarehouseStock (product_id OR variant_id)
```

**Note:** When `product.has_variants` is True, stock is tracked per variant (not per product). The `WarehouseStock` table has an optional `variant_id` FK. Cart items reference `variant_id` when applicable.

**ProductCategory** (hierarchical, like booking categories):
```python
class ProductCategory(BaseModel):
    __tablename__ = "ecommerce_product_category"

    name, slug, description, image_url
    parent_id: UUID (self-ref, nullable)
    sort_order: int
    # M2M with Product via ecommerce_product_category_link junction table
```

**ProductImage:**
```python
class ProductImage(BaseModel):
    __tablename__ = "ecommerce_product_image"

    product_id: UUID (FK)
    url: str
    alt: str
    sort_order: int
    is_primary: bool
```

**Warehouse:**
```python
class Warehouse(BaseModel):
    __tablename__ = "ecommerce_warehouse"

    name: str                       # "Main Warehouse", "EU Fulfillment"
    slug: str
    address: JSON                   # { street, city, country, zip }
    is_active: bool
    is_default: bool                # Default warehouse for new stock
    sort_order: int
```

**WarehouseStock** (stock per product per warehouse):
```python
class WarehouseStock(BaseModel):
    __tablename__ = "ecommerce_warehouse_stock"

    warehouse_id: UUID (FK)
    product_id: UUID (FK)
    quantity: int                   # Available stock
    reserved: int                   # Blocked during checkout (default 0)
    low_stock_threshold: int        # Trigger "low stock" alert
    # Unique constraint: (warehouse_id, product_id)
```

**StockBlock** (temporary reservation during checkout):
```python
class StockBlock(BaseModel):
    __tablename__ = "ecommerce_stock_block"

    product_id: UUID (FK)
    warehouse_id: UUID (FK)
    session_id: str                 # Checkout session / invoice ID
    quantity: int                   # Blocked amount
    expires_at: DateTime            # Auto-release after 5 min (configurable)
    status: str                     # "active", "committed", "released", "expired"
```

**Order:**
```python
class Order(BaseModel):
    __tablename__ = "ecommerce_order"

    user_id: UUID (FK → user)
    invoice_id: UUID (FK → user_invoice, nullable)
    order_number: str               # "ORD-A1B2C3D4" (auto-generated)
    status: OrderStatus             # PENDING → CONFIRMED → PROCESSING → SHIPPED → DELIVERED → COMPLETED
    shipping_address: JSON          # { name, street, city, state, country, zip, phone }
    billing_address: JSON
    shipping_method: str            # Plugin slug: "flat-rate", "dhl-express"
    shipping_cost: Numeric(10, 2)
    tracking_number: str
    tracking_url: str
    subtotal: Numeric(10, 2)
    tax_amount: Numeric(10, 2)
    total_amount: Numeric(10, 2)
    currency: str
    notes: str
```

**OrderStatus enum:**
```python
class OrderStatus(enum.Enum):
    PENDING = "PENDING"             # Created, awaiting payment
    CONFIRMED = "CONFIRMED"         # Payment received
    PROCESSING = "PROCESSING"       # Being prepared
    SHIPPED = "SHIPPED"             # In transit
    DELIVERED = "DELIVERED"         # Arrived
    COMPLETED = "COMPLETED"         # Finalized
    CANCELLED = "CANCELLED"
    REFUNDED = "REFUNDED"
    PARTIALLY_REFUNDED = "PARTIALLY_REFUNDED"
```

**OrderItem:**
```python
class OrderItem(BaseModel):
    __tablename__ = "ecommerce_order_item"

    order_id: UUID (FK)
    product_id: UUID (FK)
    warehouse_id: UUID (FK, nullable)  # Which warehouse fulfilled
    quantity: int
    unit_price: Numeric(10, 2)
    total_price: Numeric(10, 2)
    is_refunded: bool               # For partial refund tracking
    refunded_quantity: int           # 0 by default
    product_snapshot: JSON           # Frozen product data at purchase time (name, sku, image_url)
```

---

## 06b — Backend: Services + Line Item Handler {#06b}

### Stock Service (event-driven)

```python
class StockService:
    def get_available(self, product_id, warehouse_id=None) -> int
        """Available = quantity - reserved (across warehouses or specific one)."""

    def block_stock(self, product_id, quantity, session_id, ttl_minutes=5) -> StockBlock
        """Reserve stock for checkout. Raises InsufficientStockError if unavailable.
        Publishes: stock.blocked"""

    def commit_stock(self, session_id) -> None
        """Convert blocks to permanent decrement on payment success.
        Publishes: stock.committed"""

    def release_stock(self, session_id) -> None
        """Release expired/cancelled blocks.
        Publishes: stock.released"""

    def restore_stock(self, order_id, items: list[dict]) -> None
        """Restore stock on refund. items = [{product_id, quantity}]
        Publishes: stock.restored"""

    def cleanup_expired_blocks(self) -> int
        """Scheduler job: release blocks past expires_at.
        Returns count of released blocks."""
```

### Stock Blocking Flow

```
1. User adds items to cart
2. User clicks "Checkout" → POST /api/v1/shop/cart/checkout
3. Backend:
   a. For each cart item: stock_service.block_stock(product_id, qty, invoice_id, ttl=5min)
   b. Create invoice with CUSTOM line items
   c. Return invoice_id + checkout URL
4. User pays via Stripe/PayPal
5. Payment webhook → PaymentCapturedEvent → EcommerceLineItemHandler:
   a. stock_service.commit_stock(invoice_id)  # blocks → permanent
   b. Create Order + OrderItems
   c. Publish order.created
6. If payment times out (5 min):
   a. Scheduler: stock_service.cleanup_expired_blocks()
   b. Blocks released, stock available again
```

### EcommerceLineItemHandler

```python
class EcommerceLineItemHandler(ILineItemHandler):

    def can_handle_line_item(self, line_item, context):
        return (line_item.item_type == LineItemType.CUSTOM
                and (line_item.extra_data or {}).get("plugin") == "ecommerce")

    def activate_line_item(self, line_item, context):
        # 1. Commit stock blocks for this invoice
        # 2. Create Order + OrderItems from line item metadata
        # 3. Publish order.created event
        # 4. Return order_id in result data

    def reverse_line_item(self, line_item, context):
        # 1. Cancel order (or mark items as refunded for partial)
        # 2. Restore stock to warehouse
        # 3. Publish order.cancelled / order.refunded event

    def restore_line_item(self, line_item, context):
        # 1. Re-confirm order
        # 2. Re-decrement stock (re-block + commit)
        # 3. Publish order.restored event
```

### Invoice Line Item Metadata

```python
line_item.extra_data = {
    "plugin": "ecommerce",
    "product_id": str(product.id),
    "product_slug": product.slug,
    "product_name": product.name,
    "product_sku": product.sku,
    "is_digital": product.is_digital,
    "warehouse_id": str(warehouse.id),  # Assigned warehouse
    "quantity": quantity,
    "weight": float(product.weight),
    "stock_block_id": str(block.id),    # For commit/release tracking
}
```

### Events

```python
# Stock events
"stock.blocked"     → { product_id, quantity, session_id, expires_at }
"stock.committed"   → { product_id, quantity, session_id, order_id }
"stock.released"    → { product_id, quantity, session_id, reason }
"stock.restored"    → { product_id, quantity, order_id }
"stock.low"         → { product_id, warehouse_id, quantity, threshold }
"stock.out"         → { product_id, warehouse_id }

# Order events
"order.created"     → { order_id, user_email, order_number, total, items }
"order.confirmed"   → { order_id, user_email }
"order.shipped"     → { order_id, user_email, tracking_number, tracking_url }
"order.delivered"   → { order_id, user_email }
"order.completed"   → { order_id, user_email }
"order.cancelled"   → { order_id, user_email, reason }
"order.refunded"    → { order_id, user_email, refund_amount, items_refunded }
```

---

## 06c — Backend: Routes + Shipping Interface {#06c}

### API Routes

**Public (user):**
- `GET /api/v1/shop/products` — catalog with search, category filter, price range, pagination
- `GET /api/v1/shop/products/<slug>` — product detail with images, stock status
- `GET /api/v1/shop/categories` — category tree
- `GET /api/v1/shop/categories/<slug>` — category with products
- `POST /api/v1/shop/cart/checkout` — block stock + create invoice
- `GET /api/v1/shop/orders` — user order history
- `GET /api/v1/shop/orders/<id>` — order detail with tracking
- `GET /api/v1/shop/shipping/methods` — available shipping methods for cart

**Admin:**
- `GET/POST /api/v1/admin/shop/products` — list, create
- `GET/PUT/DELETE /api/v1/admin/shop/products/<id>` — CRUD
- `POST /api/v1/admin/shop/products/<id>/images` — upload images
- `GET/POST /api/v1/admin/shop/categories` — list, create
- `GET/PUT/DELETE /api/v1/admin/shop/categories/<id>` — CRUD
- `GET /api/v1/admin/shop/orders` — all orders with filters
- `GET/PUT /api/v1/admin/shop/orders/<id>` — detail, update status
- `POST /api/v1/admin/shop/orders/<id>/ship` — mark shipped + tracking
- `POST /api/v1/admin/shop/orders/<id>/complete` — mark completed
- `POST /api/v1/admin/shop/orders/<id>/refund` — full/partial refund
- `GET /api/v1/admin/shop/warehouses` — warehouse list
- `GET/PUT /api/v1/admin/shop/warehouses/<id>` — warehouse detail + stock levels
- `GET /api/v1/admin/shop/stock` — stock overview across warehouses

### IShippingProvider Interface (Core)

Same pattern as `IPaymentProvider` — defined in core, implemented by shipping plugins:

```python
class IShippingProvider(ABC):
    """Interface for shipping method plugins."""

    @property
    @abstractmethod
    def slug(self) -> str:
        """Unique identifier: 'flat-rate', 'dhl-express', 'local-pickup'"""

    @property
    @abstractmethod
    def name(self) -> str:
        """Display name: 'Flat Rate Shipping'"""

    @abstractmethod
    def calculate_rate(self, items: list, address: dict, currency: str) -> ShippingRate:
        """Calculate shipping cost for items to address."""

    @abstractmethod
    def create_shipment(self, order: dict) -> ShipmentResult:
        """Create shipment with carrier. Returns tracking number/URL."""

    @abstractmethod
    def get_tracking(self, tracking_number: str) -> TrackingInfo:
        """Get tracking status for a shipment."""

@dataclass
class ShippingRate:
    provider_slug: str
    name: str               # "Standard Shipping", "Express 2-Day"
    cost: Decimal
    currency: str
    estimated_days: int     # 3-5 business days
    description: str

@dataclass
class ShipmentResult:
    success: bool
    tracking_number: str
    tracking_url: str
    label_url: str          # Shipping label PDF (optional)
    error: str | None
```

Shipping plugins register via `BasePlugin.register_shipping_providers(registry)` — same lifecycle as `register_line_item_handlers()`.

### Shipping in Admin Settings

Shipping methods appear in admin Settings alongside Payment Methods:
```
▼ Settings
    Settings
    Payment Methods
    Shipping Methods    ← injected by ecommerce plugin via sectionItems.settings
```

Each shipping plugin has its own config page (like payment plugins): credentials, default rates, zones.

---

## 06d — Frontend: Admin (fe-admin) {#06d}

### Plugin Structure

```
plugins/ecommerce-admin/
├── src/views/
│   ├── Products.vue              Product list with search, filters, bulk actions
│   ├── ProductForm.vue           Create/edit with image gallery, inventory, SEO
│   ├── ProductCategories.vue     Category tree management
│   ├── CategoryForm.vue          Category CRUD
│   ├── Orders.vue                Order list with status filters
│   ├── OrderDetails.vue          Order detail + status actions + refund
│   ├── Warehouses.vue            Warehouse list
│   ├── WarehouseDetail.vue       Stock levels per warehouse
│   ├── StockOverview.vue         Cross-warehouse stock dashboard
│   └── ShippingMethods.vue       Shipping provider config (like PaymentMethods.vue)
├── src/stores/
│   ├── productAdmin.ts
│   ├── orderAdmin.ts
│   ├── shopCategoryAdmin.ts
│   ├── warehouseAdmin.ts
│   └── stockAdmin.ts
├── src/components/
│   ├── ProductImageGallery.vue
│   ├── OrderStatusBadge.vue
│   ├── OrderRefundModal.vue      Partial refund — select items + quantities
│   ├── StockLevelBadge.vue
│   └── ShopRevenueWidget.vue     Dashboard widget
├── index.ts
├── admin-config.json
├── config.json
├── locales/{en,de,es,fr,ja,ru,th,zh}.json
└── tests/
```

### Nav Registration

```typescript
extensionRegistry.register('ecommerce-admin', {
  sectionItems: {
    sales: [
      {
        label: 'Shop',
        to: '/admin/shop',
        id: 'shop',
        children: [
          { label: 'Products', to: '/admin/shop/products' },
          { label: 'Categories', to: '/admin/shop/categories' },
          { label: 'Orders', to: '/admin/shop/orders' },
          { label: 'Stock', to: '/admin/shop/stock' },
          { label: 'Warehouses', to: '/admin/shop/warehouses' },
        ],
      },
    ],
    settings: [
      { label: 'Shipping Methods', to: '/admin/shop/shipping-methods' },
    ],
  },
});
```

### Order Refund (Partial)

Admin can refund individual order items:
1. Click "Refund" on order detail
2. Modal shows order items with checkboxes + quantity inputs
3. Select items/quantities to refund
4. Backend: marks `order_item.is_refunded`, `refunded_quantity` += qty
5. Backend: restores stock to warehouse
6. Backend: creates refund via payment provider (partial amount)
7. Order status → `PARTIALLY_REFUNDED` (or `REFUNDED` if all items)

---

## 06e — Frontend: User (fe-user) {#06e}

### Cart

**Dual storage:**
- **Guest users:** `localStorage` — cart persists in browser, syncs to backend on login
- **Logged-in users:** Backend `POST/GET /api/v1/shop/cart` — persists across devices

**Cart store** (`cart.ts`):
```typescript
interface CartItem {
  productId: string;
  productSlug: string;
  productName: string;
  imageUrl: string;
  price: number;
  currency: string;
  quantity: number;
  maxQuantity: number;  // From stock availability
  isDigital: boolean;
  weight: number;
}

// Actions: addItem, removeItem, updateQuantity, clearCart, syncWithBackend
```

### Checkout Extension

The existing `checkout` plugin (fe-user) is **extended** by ecommerce — not replaced:

```
Standard checkout flow (subscription/token bundles):
  1. Select plan/bundle → 2. Payment → 3. Done

Extended checkout flow (ecommerce):
  1. Cart review → 2. Shipping address → 3. Shipping method → 4. Payment → 5. Order confirmation
```

Ecommerce registers checkout steps via the checkout plugin's extension mechanism:
```typescript
checkoutContextRegistry.register({
  plugin: 'ecommerce',
  steps: [
    { id: 'shipping-address', component: ShippingAddressStep, order: 10 },
    { id: 'shipping-method', component: ShippingMethodStep, order: 20 },
  ],
  // Cart summary component (replaces default plan summary)
  cartSummary: CartSummaryBlock,
});
```

### Routes

```typescript
sdk.addRoute({ path: '/shop', component: ProductCatalog });
sdk.addRoute({ path: '/shop/category/:slug', component: ProductCatalog });
sdk.addRoute({ path: '/shop/product/:slug', component: ProductDetail });
sdk.addRoute({ path: '/shop/cart', component: Cart });
sdk.addRoute({ path: '/shop/orders', component: OrderHistory });
sdk.addRoute({ path: '/shop/orders/:id', component: OrderDetail });
```

### Stock Display

Product detail page shows:
- "In Stock" (green) / "Low Stock — only 3 left" (orange) / "Out of Stock" (red)
- "Add to Cart" button disabled when out of stock
- Quantity selector limited to available stock

---

## 06f — Shipping Plugins {#06f}

### Reference Implementations

**Flat Rate Shipping** (`plugins/shipping-flat-rate/`):
```python
class FlatRateShippingProvider(IShippingProvider):
    slug = "flat-rate"
    name = "Flat Rate Shipping"

    def calculate_rate(self, items, address, currency):
        # Config: domestic_rate, international_rate, free_above
        return ShippingRate(cost=config.domestic_rate, estimated_days=5)
```

**Weight-Based Shipping** (`plugins/shipping-weight/`):
```python
class WeightBasedShippingProvider(IShippingProvider):
    slug = "weight-based"
    name = "Weight-Based Shipping"

    def calculate_rate(self, items, address, currency):
        # Config: rate_per_kg, base_cost, zones
        total_weight = sum(item.weight * item.quantity for item in items)
        return ShippingRate(cost=base + total_weight * rate_per_kg)
```

Both plugins have:
- `admin-config.json` with rate/zone configuration
- fe-admin settings page for rate management
- `locales/` for all 8 languages

Future shipping plugins (not in this sprint): DHL, FedEx, UPS — API integration with real carrier rates + label generation.

---

## 06g — Tests & Compatibility {#06g}

### Backend Tests

**Stock management:**
- Block stock → committed on payment
- Block stock → released on timeout
- Block stock → insufficient stock error
- Concurrent blocks (race condition handling)
- Multi-warehouse stock aggregation
- Partial refund → stock restored for refunded items only

**Line item handler:**
- `EcommerceLineItemHandler` activate → creates order + commits stock
- Reverse → cancels order + restores stock
- Restore → re-confirms order + re-decrements stock

**Order lifecycle:**
- PENDING → CONFIRMED → PROCESSING → SHIPPED → DELIVERED → COMPLETED
- Partial refund → PARTIALLY_REFUNDED
- Full refund → REFUNDED

### Frontend Tests

- Product catalog: filtering, search, pagination
- Cart: add/remove/quantity, localStorage persistence, guest→login sync
- Checkout: shipping address validation, shipping method selection, stock blocking
- Order history: list, detail, tracking display
- Admin: product CRUD, order management, stock overview, warehouse management

### Playwright E2E

- Browse catalog → add to cart → checkout → payment (mocked) → order confirmation
- Admin: create product → set stock → verify in catalog
- Stock blocking: add to cart → stock decrements → timeout → stock restored
- Partial refund: admin refunds 1 item → stock restored → order shows partial refund

### Compatibility

- All existing plugins green
- Booking unaffected
- Subscription unaffected
- Checkout plugin extended (not broken)
- Payment plugins work for product purchases

---

## Invoice Line Item Links

Admin invoice detail `itemLink()`:
```typescript
if (item.type === 'ecommerce' && item.metadata?.product_id) {
  return `/admin/shop/products/${item.metadata.product_id}`;
}
```

User invoice detail `itemLink()`:
```typescript
if (item.extra_data?.plugin === 'ecommerce' && item.extra_data?.product_slug) {
  return `/shop/product/${item.extra_data.product_slug}`;
}
```

---

## Plugin Configs

### 1. Ecommerce Backend (`plugins/ecommerce/`)

**`config.json`:**
```json
{
  "currency": "EUR",
  "stock_block_ttl_minutes": 5,
  "low_stock_threshold_default": 10,
  "enable_warehouses": true,
  "enable_digital_products": true,
  "order_number_prefix": "ORD",
  "tax_included_in_price": true,
  "max_cart_items": 50,
  "guest_checkout_enabled": true
}
```

**`admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        { "key": "currency", "label": "Default Currency", "component": "input", "inputType": "text", "description": "ISO 4217 code (EUR, USD, GBP)" },
        { "key": "order_number_prefix", "label": "Order Number Prefix", "component": "input", "inputType": "text", "description": "Prefix for order numbers (e.g., ORD)" },
        { "key": "tax_included_in_price", "label": "Tax Included in Price", "component": "checkbox", "description": "Product prices include tax" },
        { "key": "guest_checkout_enabled", "label": "Guest Checkout", "component": "checkbox", "description": "Allow checkout without account" }
      ]
    },
    {
      "id": "stock",
      "label": "Stock Management",
      "fields": [
        { "key": "enable_warehouses", "label": "Enable Warehouses", "component": "checkbox", "description": "Multi-warehouse stock tracking" },
        { "key": "stock_block_ttl_minutes", "label": "Stock Block Duration (min)", "component": "input", "inputType": "number", "min": 1, "max": 30, "description": "Minutes to reserve stock during checkout" },
        { "key": "low_stock_threshold_default", "label": "Default Low Stock Threshold", "component": "input", "inputType": "number", "min": 0, "max": 1000, "description": "Default threshold for low stock alerts" },
        { "key": "max_cart_items", "label": "Max Cart Items", "component": "input", "inputType": "number", "min": 1, "max": 200, "description": "Maximum items per cart" }
      ]
    },
    {
      "id": "products",
      "label": "Products",
      "fields": [
        { "key": "enable_digital_products", "label": "Enable Digital Products", "component": "checkbox", "description": "Allow products that don't require shipping" }
      ]
    }
  ]
}
```

### 2. Ecommerce Admin Frontend (`plugins/ecommerce-admin/`)

**`config.json`:**
```json
{
  "products_per_page": 25,
  "orders_per_page": 25,
  "show_sku_column": true,
  "show_weight_column": true,
  "default_product_sort": "created_at_desc"
}
```

**`admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "display",
      "label": "Display",
      "fields": [
        { "key": "products_per_page", "label": "Products Per Page", "component": "input", "inputType": "number", "min": 10, "max": 100 },
        { "key": "orders_per_page", "label": "Orders Per Page", "component": "input", "inputType": "number", "min": 10, "max": 100 },
        { "key": "show_sku_column", "label": "Show SKU Column", "component": "checkbox", "description": "Display SKU in product table" },
        { "key": "show_weight_column", "label": "Show Weight Column", "component": "checkbox", "description": "Display weight in product table" },
        { "key": "default_product_sort", "label": "Default Sort", "component": "select", "options": [
          { "value": "created_at_desc", "label": "Newest First" },
          { "value": "name_asc", "label": "Name A-Z" },
          { "value": "price_asc", "label": "Price Low-High" },
          { "value": "price_desc", "label": "Price High-Low" }
        ]}
      ]
    }
  ]
}
```

### 3. Ecommerce User Frontend (`plugins/ecommerce/` in fe-user)

**`config.json`:**
```json
{
  "products_per_page": 12,
  "show_out_of_stock": true,
  "default_catalog_view": "grid",
  "show_product_weight": false,
  "cart_sync_on_login": true
}
```

**`admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "catalog",
      "label": "Catalog Display",
      "fields": [
        { "key": "products_per_page", "label": "Products Per Page", "component": "input", "inputType": "number", "min": 4, "max": 48 },
        { "key": "default_catalog_view", "label": "Default View", "component": "select", "options": [
          { "value": "grid", "label": "Grid" },
          { "value": "list", "label": "List" }
        ]},
        { "key": "show_out_of_stock", "label": "Show Out-of-Stock Products", "component": "checkbox", "description": "Display products with zero stock (grayed out)" },
        { "key": "show_product_weight", "label": "Show Product Weight", "component": "checkbox" },
        { "key": "cart_sync_on_login", "label": "Sync Cart on Login", "component": "checkbox", "description": "Merge localStorage cart with backend cart when user logs in" }
      ]
    }
  ]
}
```

### 4. Flat Rate Shipping (`plugins/shipping-flat-rate/`)

**`config.json`:**
```json
{
  "domestic_rate": 5.99,
  "international_rate": 14.99,
  "currency": "EUR",
  "free_shipping_above": 50.00,
  "estimated_days_domestic": 5,
  "estimated_days_international": 14,
  "enabled_countries": []
}
```

**`admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "rates",
      "label": "Shipping Rates",
      "fields": [
        { "key": "domestic_rate", "label": "Domestic Rate", "component": "input", "inputType": "number", "min": 0, "description": "Flat rate for domestic shipping" },
        { "key": "international_rate", "label": "International Rate", "component": "input", "inputType": "number", "min": 0, "description": "Flat rate for international shipping" },
        { "key": "currency", "label": "Currency", "component": "input", "inputType": "text" },
        { "key": "free_shipping_above", "label": "Free Shipping Above", "component": "input", "inputType": "number", "min": 0, "description": "Order total above which shipping is free (0 = disabled)" }
      ]
    },
    {
      "id": "delivery",
      "label": "Delivery Estimates",
      "fields": [
        { "key": "estimated_days_domestic", "label": "Domestic (days)", "component": "input", "inputType": "number", "min": 1, "max": 60 },
        { "key": "estimated_days_international", "label": "International (days)", "component": "input", "inputType": "number", "min": 1, "max": 120 }
      ]
    }
  ]
}
```

### 5. Weight-Based Shipping (`plugins/shipping-weight/`)

**`config.json`:**
```json
{
  "base_cost": 3.99,
  "rate_per_kg": 1.50,
  "currency": "EUR",
  "max_weight_kg": 30,
  "free_shipping_above": 100.00,
  "zones": [
    { "name": "Domestic", "countries": ["DE"], "rate_multiplier": 1.0 },
    { "name": "EU", "countries": ["FR", "IT", "ES", "NL", "AT", "BE"], "rate_multiplier": 1.5 },
    { "name": "International", "countries": [], "rate_multiplier": 3.0 }
  ]
}
```

**`admin-config.json`:**
```json
{
  "tabs": [
    {
      "id": "rates",
      "label": "Base Rates",
      "fields": [
        { "key": "base_cost", "label": "Base Cost", "component": "input", "inputType": "number", "min": 0, "description": "Fixed base cost per shipment" },
        { "key": "rate_per_kg", "label": "Rate per kg", "component": "input", "inputType": "number", "min": 0, "description": "Additional cost per kilogram" },
        { "key": "currency", "label": "Currency", "component": "input", "inputType": "text" },
        { "key": "max_weight_kg", "label": "Max Weight (kg)", "component": "input", "inputType": "number", "min": 1, "max": 500, "description": "Maximum weight per shipment" },
        { "key": "free_shipping_above", "label": "Free Shipping Above", "component": "input", "inputType": "number", "min": 0 }
      ]
    },
    {
      "id": "zones",
      "label": "Shipping Zones",
      "fields": [
        { "key": "zones", "label": "Zone Configuration", "component": "textarea", "description": "JSON array of zones: [{name, countries, rate_multiplier}]. Managed via dedicated zone editor (future)." }
      ]
    }
  ]
}
```

---

## i18n — All Supported Languages

All ecommerce plugins must provide translations for all 8 core-supported languages:

| Code | Language |
|------|----------|
| `en` | English |
| `de` | Deutsch |
| `es` | Español |
| `fr` | Français |
| `ja` | 日本語 |
| `ru` | Русский |
| `th` | ไทย |
| `zh` | 中文 |

Applies to: backend email templates, fe-admin (nav, forms, tables), fe-user (catalog, cart, checkout, orders), shipping plugins.

---

## Acceptance Criteria

- Products with categories, images, multi-warehouse inventory
- Stock blocking during checkout (5 min TTL, configurable)
- Stock committed on payment, released on timeout
- Standard checkout flow extended with shipping address + shipping method
- Shipping plugins follow payment plugin pattern (`IShippingProvider`)
- `EcommerceLineItemHandler` creates orders on payment capture
- Partial refund: refund specific items, restore stock, update order status
- Admin manages products, categories, orders, warehouses, stock, shipping methods
- User browses catalog, adds to cart, checks out, views order history
- Cart: localStorage for guests, backend for logged-in users
- Invoice line items link to product detail pages
- All existing plugins pass tests
- `pre-commit-check.sh --full` passes on all 3 repos
- All UI text in 8 languages

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests before implementation |
| **Plugin pattern** | `plugin_id/plugin_id/`, `__init__.py`, `admin-config.json`, `populate_db.py` |
| **Core agnostic** | Zero core changes — CUSTOM line items + event bus + line item registry |
| **DI** | Services via container, handlers via registry |
| **Event-driven** | Stock management via event bus (blocked, committed, released, restored) |
| **Meaningful names** | `ecommerce_product`, `ecommerce_order`, `EcommerceLineItemHandler` |
| **i18n** | All UI text in 8 languages |

---

## Pre-commit Checks

```bash
cd vbwd-backend && ./bin/pre-commit-check.sh --full
cd vbwd-fe-admin && ./bin/pre-commit-check.sh --full
cd vbwd-fe-user && ./bin/pre-commit-check.sh --full
```
