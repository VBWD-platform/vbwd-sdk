# Report — Sprint 15: Shipping, Discount Admin, Tax

**Date:** 2026-04-04
**Status:** In Progress (15a, 15b done; 15c, 15d pending)

---

## Completed

### Sprint 15a — Shipping Methods (Shop Plugin)

**Backend:**
- `ShippingMethodRegistry` — singleton in shop plugin, providers register on enable
- `PickupAtStoreProvider` — built-in zero-cost method, cannot be disabled
- 3 admin routes: `GET /admin/shop/shipping/methods`, `POST .../toggle`, `POST .../rates`
- Rate preview endpoint calculates from all enabled providers

**Frontend:**
- `ShippingMethods.vue` — table: name, type (built-in/plugin badge), status, toggle + config link
- Route `shop/shipping` with `requiredPermission: 'shop.configure'`
- "Shipping" child item in Shop sidebar nav

**Architecture:** Shop plugin is agnostic — only provides the interface and registry. Each shipping provider (DHL, UPS, etc.) is its own plugin that depends on shop and implements `IShippingProvider`.

### Sprint 15b — Discount Admin Plugin (Core)

**New plugin:** `plugins/discount-admin/` — standalone fe-admin plugin

**Views (5):**
- `Discounts.vue` — list with type/scope/value/uses/status columns, delete
- `DiscountForm.vue` — create/edit: type selector (PERCENTAGE/FIXED/FREE_SHIPPING/BUY_X_GET_Y), scope (GLOBAL/ECOMMERCE/SUBSCRIPTION/BOOKING), limits, dates, stackable, priority
- `Coupons.vue` — list with code/discount/uses/status, bulk generate modal
- `CouponForm.vue` — manual code entry + "Generate" button (random 8-char alphanumeric), discount link
- `CouponUsage.vue` — usage history per coupon

**Backend:**
- `POST /admin/coupons/generate` — bulk generate up to 100 random codes linked to a discount

**Store:** `discountAdmin.ts` — full CRUD for discounts + coupons + usage + bulk generate

**Sidebar:** "Promotions" in Sales section → Discounts, Coupons (with `requiredPermission`)

### Other Fixes

- Product edit stock tab: now editable — inline quantity editing + add stock for new warehouse
- fe-core rebuilt and copied to submodules (auth store with permissions)

---

## Architecture Principles Applied

| Principle | How Applied |
|-----------|------------|
| **Core agnostic** | Shipping = shop feature; discount/tax = core. Core models don't know about shipping. |
| **Plugin isolation** | Each shipping provider is its own plugin with own config. Discount admin is standalone. |
| **SOLID — Open/Closed** | `ShippingMethodRegistry` accepts any `IShippingProvider` without modification. New providers = new plugins. |
| **SOLID — Single Responsibility** | `DiscountForm.vue` handles discount CRUD only. `CouponForm.vue` handles coupon CRUD only. Store separates data from UI. |
| **Liskov** | All shipping providers honour `IShippingProvider` (calculate_rate, create_shipment, get_tracking). Built-in pickup is a valid provider. |
| **DRY** | Reused data-table, badge, form-group, btn CSS patterns from existing admin views. One Pinia store for all discount/coupon operations. |
| **DI** | Store uses `api` client (injected). Registry is a singleton provided by the shop plugin. |
