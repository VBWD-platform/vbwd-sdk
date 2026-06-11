# 2026-06-11 — Dev day status

> Forward backlog. Planned/unfinished sprints carried from [`../20260610/status.md`](../20260610/status.md) and earlier; everything **done** stays archived under its dev-day `done/`.
> **Reports (this day):** [01 — Shopware vs vbwd user product comparison](reports/01-shopware-vs-vbwd-user-product-comparison.md) · [02 — bot rich rendering + portable styles (S70/S71)](reports/02-bot-rich-rendering-and-portable-styles.md).
>
> **🟢 Recently done (2026-06-11):** **S70 — bot rich-choice rendering in meinchat + portable conversation styles** — the storefront bot now renders **styled cards / command menu / cart** in the real meinchat UI (priced choice cards, `/help` menu, `/cart`·`/cart-edit`·`/cart-clear`, tap-to-select), the bot-chat look is a **portable `BotConversationStyle`** exportable through the unified S46 Import/Export, and the fe applies the active style. 70.0–70.5 all gate-green on disk, **not committed**. Verified in the live UI; walkthrough rebuilt with real screenshots ([bot-base-meinchat-walk.html](../20260607/reports/bot-base-meinchat-walk.html)). See report 02.

## Theme

The S45 bot bridge + S53 storefront are now a **presentable in-chat commerce experience** (S70). Next rocks are the **Shopware-parity** follow-ups surfaced in report 01: the data-model foundations — **taxes/countries (S72)** and **user groups (S73)** — then the customer/catalog batch — **account type (S74)**, **shop address book + delivery (S75)**, **manufacturer/product-number/SEO (S76)**, a cross-cutting **tags + custom-fields framework (S77)**, and **cross-sell + product CMS layout (S78)** — plus the **iOS** counterpart of the bot rich rendering (S71).

## Sprints

| # | Sprint | Area | Status |
|---|--------|------|--------|
| **70** | [Bot rich-choice rendering in meinchat + portable conversation styles](../20260610/sprints/s70-bot-rich-choice-rendering-and-portable-styles.md) | `meinchat`/`bot_meinchat`/`bot_base`/`subscription` + `vbwd-fe-user` | 🟢 **DONE on disk, gate-green (70.0–70.5) — 2026-06-11**; not committed. Real-UI verified. |
| **71** | [iOS: meinchat + meinchat-plus updates for rich bot-choice rendering & styling](../20260610/sprints/s71-ios-meinchat-rich-choice-rendering.md) | meinchat iOS + meinchat-plus iOS | **PLANNED** — consumes the S70 `meta` contract; native cards/menu/cart + token→native theme; depends on 70.0 (green). |
| **66/67** | **Notifications & badges** — [S67 umbrella](../20260610/sprints/s67-notifications-and-badges.md) → **split BE/iOS 2026-06-11**: [S67.1 (BE) device-registration + APNs + push hook](../20260610/sprints/s67-1-be-device-registration-and-push.md) (**≡ [S66](../20260610/sprints/s66-backend-apns-push-notifications.md)** — canonical BE design, implement once) · [S67.2 (iOS) app notifications + side-menu + app-icon badge](../20260610/sprints/s67-ios-notifications-and-badges.md) (depends on S67.1) | `vbwd-backend` (core + `plugins/meinchat`) + `vbwd-ios` | **PLANNED** — split into BE + iOS sub-sprints against a fixed wire contract (`/devices/register` + push payload + badge). |
| **72** | [Taxes & Countries (umbrella)](sprints/s72-taxes.md) — [72.1 countries page](sprints/s72-1-tax-countries-page.md) · [72.2 import/export](sprints/s72-2-tax-import-export.md) · [72.3 entity assignment](sprints/s72-3-entity-tax-assignment.md) · [72.4 netto/brutto](sprints/s72-4-netto-brutto-display.md) | core + `vbwd-fe-admin` + `subscription`/`shop`/`booking` + `vbwd-fe-user` | **PLANNED** |
| **73** | [User Groups (new core entity) + subscription-driven membership](sprints/s73-user-groups.md) | core + `vbwd-fe-admin` + `subscription` | **PLANNED** |
| **74** | [User account type (private person / business)](sprints/s74-user-account-type.md) | core + `vbwd-fe-admin` + fe-user profile | **PLANNED** — confirms core keeps a single billing address (multi-address is shop-only, S75). |
| **75** | [Shop address book & delivery address](sprints/s75-shop-address-book-delivery.md) | `shop` + `vbwd-fe-user` + `vbwd-fe-admin` | **PLANNED** — shop-owned `shop_user_address` (multiple, default delivery); checkout save-or-ephemeral → `Order.shipping_address` snapshot; orders carry immutable snapshots. |
| **76** | [Shop catalog parity: manufacturer, product number/EAN, SEO](sprints/s76-shop-catalog-parity.md) | `shop` + `shop-admin` + `vbwd-fe-user` | **PLANNED** — `Manufacturer` model + FK; distinct `product_number` (auto) + `ean`; SEO reusing the CMS S56 shape. |
| **77** | [Generic Tags & Custom Fields framework (BE + FE)](sprints/s77-tags-custom-fields-framework.md) | **core** + `vbwd-fe-admin` + consumers (`user`/`shop_product`) | **PLANNED** — polymorphic `(entity_type, entity_id)` tags + typed custom fields (no per-entity migration); core port + reusable `TagPicker`/`CustomFieldsEditor`; json/csv. |
| **78** | [Shop cross-selling + product CMS layout](sprints/s78-shop-crosssell-cms-layout.md) | `shop` + `shop-admin` + `vbwd-fe-user` | **PLANNED** — typed `shop_product_crosssell`; `cms_layout_slug` rendered via CMS `CmsLayoutRenderer` (graceful fallback when CMS off). |

## Carry-forward / open

- **Bot epic packaging** — batch-create + push the 4 standalone `vbwd-plugin-*` repos (`bot-base`, `bot-telegram`, `bot-meinchat`, `fe-admin-bot-telegram`); still pending the owner's go-ahead (irreversible outward action).
- **45.5.1** — meinchat E2E bot-participant decrypt, blocked on meinchat-plus implementing `e2e_v1` Signal decrypt; S70 rich `meta` rides the **plain** path; S71 reserves the `{body,meta}` envelope shape.
- **Real Telegram smoke test (S45 Q2)** — ready whenever a @BotFather token is provided.
- Optional **fe-admin styling UI** for `BotConversationStyle` (today: generic plugin config + Import/Export surface).

## Dev-stack note (reversible, 2026-06-11)

The storefront catalog is deactivated to the demo set (`is_active` toggle: Starter/Pro/Business · Priority Support/Extra Seats · 1k/5k/20k); `bot-meinchat` + `subscription.bot_storefront_enabled` on; a `Default` `BotConversationStyle` seeded; bot user `assistant` provisioned; S70 migrations applied to the dev DB. Plugins are gitignored/on-disk — nothing committed.
