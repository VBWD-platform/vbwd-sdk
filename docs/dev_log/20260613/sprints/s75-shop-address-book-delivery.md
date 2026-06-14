# S75 — Shop address book & delivery address (multiple addresses, save-or-ephemeral)

**Area:** plugin `shop` (`vbwd-backend/plugins/shop`) + `vbwd-fe-user` (shop checkout) + `vbwd-fe-admin` (read on user) · **Depends on:** core `UserDetails` billing address + S74 account type, shop `Order` (has `shipping_address`/`billing_address` JSONB), shop checkout flow · **Part of:** Shopware-parity follow-ups ([report 01](../reports/01-shopware-vs-vbwd-user-product-comparison.md)).
**Engineering requirements:** TDD-first, SOLID/DI/DRY, no overengineering; `--plugin shop --full` + fe Vitest/ESLint green. Core stays single-billing-address (S74); **multiple addresses live in the shop plugin only**. **Not committed.**

## Problem
Tangible products need shipping. Today the core user has **one** billing address and the shop has no address book — `Order.shipping_address`/`billing_address` are free JSONB snapshots with no source of saved addresses and no UI to pick/enter a delivery address. A shop customer needs: a **default delivery address**, the ability at checkout to **pick a saved address**, **enter a new one**, and **optionally save it for future** — or use it **once** (ephemeral: stored only in the order/invoice documents, never in the user's saved book).

## Locked decisions
| # | Decision |
|---|---|
| **D1 — Address book is shop-owned.** | New `shop_user_address` (owned by core `user_id`, FK → `vbwd_user.id` `ON DELETE CASCADE`). Core's single `UserDetails` billing address is **untouched** and remains the default billing party. |
| **D2 — Default delivery.** | A user may flag one saved address `is_default_delivery`. First saved address auto-defaults. Billing defaults to the core `UserDetails` billing address; the customer may override billing with a saved/new address at checkout. |
| **D3 — Save-or-ephemeral at checkout.** | When the customer enters a new delivery (or billing) address, a **"save for future"** toggle: if on → persist a `shop_user_address` row and use it; if off → **ephemeral**: snapshot the address JSON directly into `Order.shipping_address` (/`billing_address`) only — never written to the address book or `UserDetails`. Orders/invoices always carry a full **immutable snapshot** regardless (so later edits/deletes of saved addresses don't mutate historical documents). |
| **D4 — Snapshot is authoritative on the order.** | `Order.shipping_address`/`billing_address` JSONB are always the full captured address at purchase time (Shopware-style order-address snapshot). Saved addresses are only the *source* for pre-filling. |

## Scope
**Shop backend:**
- Model `plugins/shop/shop/models/user_address.py` **`ShopUserAddress`** (`shop_user_address`): `user_id` FK, `label` (e.g. "Home"/"Office"), `type` (`delivery`|`billing`|`both`), `is_default_delivery` (bool), salutation, first_name, last_name, company, vat_id, line1, line2, city, postal_code, country (ISO2), phone, timestamps. Repo + service (CRUD, set-default, only one default per user). Migration `down_revision` = shop head (verify).
- Routes (gated on auth; self-service) `GET|POST|PUT|DELETE /api/v1/shop/addresses` + `POST .../addresses/<id>/default-delivery`. Admin read: `GET /api/v1/admin/shop/users/<id>/addresses` (gated `users.view`).
- **Checkout integration:** the checkout/order-creation path accepts a `delivery_address` and optional `billing_address` as either `{address_id}` (use a saved one) or an inline address object + `save: bool` (D3). It resolves → snapshots the full address into `Order.shipping_address`/`billing_address`; when `save` is true it also upserts a `ShopUserAddress`. Invoice documents read the order snapshot.

**fe-user (shop):**
- An **address book** view (list saved addresses, add/edit/delete, set default delivery), reachable from the account area.
- **Checkout** (`plugins/shop/shop/views/Cart.vue` / checkout step): a delivery-address selector — radio list of saved addresses + "Use a different address" (inline form) with a **"Save this address"** checkbox; billing defaults to the core billing address with an optional override. Pass the selection to order creation per D3.
- i18n keys (all locales).

**fe-admin:** on `UserEdit.vue`, a **read-only Addresses** section (shop-contributed via the `userDetailsSections`/`userEditTabs` extension point — keeps core agnostic) listing the user's saved shop addresses; full management stays in fe-user (self-service).

## TDD
- **Backend:** address CRUD + single-default invariant; checkout with `{address_id}` snapshots that address into the order; checkout with an inline address + `save:true` creates a `ShopUserAddress` **and** snapshots it; `save:false` snapshots **without** creating a saved row or touching `UserDetails`; deleting/editing a saved address does **not** mutate prior orders' snapshots.
- **fe-user (Vitest):** address book CRUD; checkout shows saved addresses + new-address form + save toggle; selection reaches the order payload.
- **fe-admin (Vitest):** the user Addresses section lists shop addresses read-only.

## Definition of done
Shop users have a multi-entry address book with a default delivery address; at checkout they pick a saved address or enter a new one and choose to save it or use it once (ephemeral → order/invoice snapshot only, not the book or `UserDetails`); orders carry immutable address snapshots; core billing stays single-address; `--plugin shop --full` + fe Vitest/ESLint green; core untouched (shop contributes the admin view via the extension point). Not committed ([[feedback_no_commit_without_ask]]).
