# Report — Shopware vs vbwd: Customer/User & Product (gap analysis + proposed updates)

**Date:** 2026-06-11
**Scope:** Compare **Shopware 6**'s *customer* and *product* (entity model + admin detail page) against vbwd's current implementation, then propose concrete updates for **vbwd-core** (user) and the **vbwd shop plugin** (product).
**Method:** vbwd side = direct code exploration (paths cited). Shopware side = Shopware 6 entity model + Administration detail-page structure (stable, well-documented). Shopware is a full e-commerce storefront; vbwd is a subscription-first SaaS platform with a lean shop plugin — so "parity" is selective, not wholesale.
**Cross-refs:** [S72 Taxes](../sprints/s72-taxes.md) (fixes product tax) · [S73 User Groups](../sprints/s73-user-groups.md) (customer-group equivalent). Proposals below cite these and suggest new sprint ids (s74+).

---

## Part A — Customer (Shopware) vs User (vbwd)

### A.1 Where the data lives
- **vbwd** splits identity from PII (GDPR): `vbwd/models/user.py` **`User`** (`vbwd_user`: email, password_hash, status, role, payment_customer_id, has_used_trial) + 1:1 `vbwd/models/user_details.py` **`UserDetails`** (`vbwd_user_details`: first_name, last_name, **single** address_line_1/2, city, postal_code, country, phone, company, tax_number, `config` JSONB, balance). A user's "customer 360" is spread across `UserInvoice`, `Subscription`/`AddOnSubscription` (subscription plugin), `Order` (shop), `ProductReview`, `WishlistItem`, `UserTokenBalance`/`TokenTransaction`, `ApiKey`, `UserCase`.
- **Shopware** has a single `customer` aggregate: customerNumber, salutation, title, firstName, lastName, company, vatIds[], email, **customerGroup**, defaultPaymentMethod, language, salesChannel, **accountType** (private/business), active, **guest**, birthday, **multiple addresses** (default billing + shipping), tags, customFields, newsletter/double-opt-in, plus order/review/wishlist/promotion history.

### A.2 Field-level comparison
| Capability | Shopware customer | vbwd User/UserDetails | Gap |
|---|---|---|---|
| Email + auth | ✓ | ✓ | — |
| Status/active | ✓ active + guest | ✓ status enum (PENDING/ACTIVE/SUSPENDED/DELETED) | vbwd lacks **guest** accounts |
| Customer number | ✓ `customerNumber` | ✗ (only UUID) | **missing** human id |
| Salutation / title | ✓ | ✗ | missing |
| First/last name | ✓ | ✓ (UserDetails) | — |
| Company / VAT id | ✓ company + vatIds[] | ✓ company + tax_number (single) | vbwd single vatId |
| Account type (private/business) | ✓ | ✗ | missing |
| Birthday | ✓ | ✗ | missing |
| Language/locale | ✓ | ~ (in `UserDetails.config` JSONB, not a column) | informal |
| **Addresses** | ✓ **many**, default billing/shipping | ✗ **one** inline address on UserDetails | **biggest gap** |
| Default payment method | ✓ | ~ (`payment_customer_id` provider ref only) | missing |
| **Customer group** | ✓ (drives pricing/visibility) | ✗ → **S73** adds user groups | covered by S73 (grouping; pricing-per-group is further) |
| Tags | ✓ | ✗ | missing |
| Custom fields | ✓ framework | ~ (`config` JSONB, ad-hoc) | no formal framework |
| Newsletter / consent | ✓ double-opt-in | ✗ | missing (GDPR-relevant) |
| Roles/permissions | (admin users only) | ✓ RBAC roles + user access levels (richer than Shopware here) | vbwd **ahead** |
| Tokens / balance | n/a | ✓ token balance + ledger, account balance | vbwd **ahead** (SaaS) |

### A.3 Admin detail page
- **Shopware customer detail tabs:** *General* (account + default addresses + customer group + default payment + language), *Addresses*, *Orders*, *Reviews*, plus tags/custom-fields/comments.
- **vbwd:** `UserDetails.vue` (header + read-only account grid + plugin `userDetailsSections` — only subscription summary today) and `UserEdit.vue` tabs: **Account** (email/status/role + access levels + personal/company/tax/**single** address + token balance), **Invoices**, **API**, plus plugin `userEditTabs` (Subscriptions, Add-ons). Users list (`Users.vue`) has search/status filter, sort, bulk suspend/activate/delete/assign-access-level, and import/export.
- **Assessment:** vbwd's tab/section extension model is solid and already aggregates more than Shopware in some axes (subscriptions, API keys, tokens). The structural gaps are **multiple addresses**, **a true customer-360 detail view**, and the small profile fields (salutation, birthday, account type, customer number, newsletter).

### A.4 Proposed updates — vbwd-core (user)
**P0 — cheap, high value (extend `UserDetails` + `UserEdit` Account tab):**
- Add `salutation`, `title`, `birthday` (Date), `account_type` (`private|business`), `locale` (promote from `config`), `customer_number` (human-readable, sequence/seeded), `marketing_consent` + `consent_at` (GDPR). All nullable, one additive core migration; surface in the Account tab.

**P1 — structural: multiple addresses (new sprint, suggest `s74-user-addresses`).**
- New core `vbwd/models/user_address.py` **`UserAddress`** (`vbwd_user_address`): user_id FK, `type` (billing/shipping/both), `is_default_billing`/`is_default_shipping`, salutation, first/last name, company, vat_id, line1/line2, city, postal_code, country, phone. Migrate the existing single inline `UserDetails` address into one default `UserAddress` row (back-compat: keep reading the legacy fields until migrated).
- Admin: an **Addresses** tab on `UserEdit.vue` (list + add/edit/set-default). fe-user: address book.
- Data-exchange: a `user_addresses` exchanger (json+csv), and carry addresses on the `users` export.

**P1 — Customer-360 detail page (suggest `s75-customer-360`).**
- Promote `UserDetails.vue` into a real customer dashboard using the existing extension points: add an **Orders** section (shop), **Reviews**, **Token transactions**, **Cases**, lifetime value/last-order — all data already exists via `user_id`. Mostly UI wiring of `userDetailsSections` + a few read endpoints; no schema change.

**P2 — generic Tags + Custom Fields framework (core, reused by user *and* product).**
- A small polymorphic `tag` + `entity_tag(entity_type, entity_id, tag)` and a `custom_field` definition + value store, exposed on user/product/plan/resource. This is the cross-cutting answer to several Shopware gaps; scope as its own sprint.

**Note:** customer **group** itself → **S73**. Group-driven *pricing tiers* (Shopware customer-group pricing) is a follow-on once S73 + S72.3 land (see Part B.4).

---

## Part B — Product (Shopware) vs Product (vbwd shop plugin)

### B.1 What vbwd already has (better than assumed)
`plugins/shop/shop/models/`: **Product** (name, slug, sku, description, price+currency+price_float, is_active, is_digital, **has_variants**, sort_order, weight, `dimensions` JSONB, `product_metadata` JSONB, **tax_class string**), **ProductVariant** (sku, price, weight, `attributes` JSONB, image_url), **ProductCategory** (hierarchical, M2M via `shop_product_category_link`), **ProductImage** (url, alt, sort_order, is_primary), **Warehouse**/**WarehouseStock** (qty, reserved, low_stock_threshold)/**StockBlock** (checkout reservation), **Order**/**OrderItem** (with product_snapshot), **ProductReview** (rating/body/verified/admin_response/helpful_count), **WishlistItem**, **AbandonedCart**. Admin: products list (bulk activate/deactivate/delete), product form tabs **General / Stock / Images / Categories**, category manager, orders, warehouses, shipping methods, stock overview. Shop has **no own customer model** — it reuses core `User` via `Order.user_id`.

### B.2 Field-level comparison
| Capability | Shopware product | vbwd Product | Gap |
|---|---|---|---|
| Product number | ✓ `productNumber` (+ ean) | ~ `sku` only | add distinct number + EAN/GTIN |
| Manufacturer | ✓ entity + manufacturerNumber | ✗ | **missing** |
| Categories | ✓ hierarchical M2M | ✓ hierarchical M2M | — (but see B.3 bug) |
| Properties / options | ✓ property groups + options | ✗ (variant `attributes` JSONB only) | **missing** real property framework |
| Variants | ✓ configurator (option matrix, inheritance) | ~ flat `ProductVariant` rows, no CRUD API | partial; no admin CRUD |
| Media | ✓ product + **variant** media, cover, order, alt | ✓ product images, primary, alt; **no reorder/variant media** | partial |
| Tax | ✓ tax classes with **rates** | ✗ `tax_class` **string**, no rate | → **S72.3** fixes (assign core `Tax`) |
| Pricing | ✓ per-currency gross/net, **tiered/quantity**, **per-customer-group**, purchase price | single price+currency | **missing** advanced pricing |
| Net/gross display | ✓ | ✗ → **S72.4** adds netto/brutto | covered by S72.4 |
| Stock | ✓ stock, availableStock, isCloseout, restockTime, min/max purchase, steps | ✓ warehouse qty/reserved/low-threshold | add min/max/closeout/restock |
| Shipping | ✓ weight + width/height/length + deliveryTime + shippingFree | ~ weight + `dimensions` JSONB (unused) | formalize dims + delivery time |
| SEO | ✓ seoUrls, meta title/desc | ✗ (only `product_metadata`) | **missing** (could reuse CMS S56 SEO) |
| Sales-channel visibility | ✓ per channel | ✗ (single storefront) | likely N/A for vbwd; note |
| Cross-sell / bundles | ✓ | ✗ | missing |
| CMS layout | ✓ cmsPage | ✗ (CMS plugin exists — could assign a layout) | opportunity |
| Tags / custom fields | ✓ | ✗ / ~ JSONB | missing (see core Tags/CF framework) |
| Reviews | ✓ | ✓ (needs admin moderation UI) | UI gap |

### B.3 Admin detail page + a concrete defect
- **Shopware product detail tabs:** General, Specifications (measures/packaging, properties), Advanced pricing, Properties, Variants, Layout, Cross Selling, SEO, Reviews.
- **vbwd `ProductForm.vue` tabs:** General (name/slug/sku/price/currency/weight/tax_class select/description/active/digital), Stock, Images (`ProductImageGallery`), Categories.
- **Defect to fix (call-out, à la S68):** the **Categories** tab in `ProductForm.vue` has *TODO* — **category assignment is not persisted** (no API call); and there are **no admin variant CRUD endpoints** (variants serialize but can't be created/edited from the UI). Both are real, shippable fixes.

### B.4 Proposed updates — vbwd shop plugin (product)
**P0 — close the obvious gaps + fix the defect:**
- **Fix category persistence** in `ProductForm.vue` (+ a `PUT /admin/shop/products/<id>/categories` set-endpoint). Quick correctness fix.
- **Manufacturer**: new `Manufacturer` model + FK on Product + admin manager + a Manufacturer field on the form.
- **Product number + EAN/GTIN**: add `product_number` (distinct, sequence/seeded) and `ean`.
- **SEO**: add `seo_title`/`seo_description`/`canonical`/`og_*` — or, better, **reuse the CMS SEO mechanism (S56)** so product detail pages share the platform's SEO tooling. (Suggest `s76-shop-product-catalog-parity`.)
- **Tax**: already addressed by **S72.3** (assign core `Tax` records; net/gross via S72.4) — replace the `tax_class` string.

**P1 — properties, variants, advanced pricing (suggest `s77-shop-properties-variants` + `s78-shop-advanced-pricing`):**
- **Property framework**: `PropertyGroup` + `PropertyOption` (e.g. Color → Red/Blue) and product↔option links; drive variants from option combinations (a real configurator) and admin variant CRUD endpoints + a Variants tab.
- **Advanced pricing**: tiered/quantity price breaks and **per-customer-group pricing** (ties **S73** groups + **S72** tax) and optional per-currency price rows; surface in a Pricing tab.
- **Inventory parity**: add `min_purchase`/`max_purchase`/`purchase_steps`/`is_closeout`/`restock_time` to Product; **shipping**: formalize `width`/`height`/`length` + a `DeliveryTime` lookup + `shipping_free`.

**P2 — depth & UX:**
- Cross-selling/related products (+ bundles); product **CMS layout** assignment (reuse CMS plugin); variant-level media + media reorder + inline alt/caption + bulk upload; admin **review moderation** UI; Tags + Custom Fields (the shared core framework from A.4 P2); per-product price-display override (S72.4).

---

## Prioritized roadmap (consolidated)
| Pri | Item | Where | Sprint |
|---|---|---|---|
| P0 | Product **category-assign not persisted** + admin variant CRUD | shop | new `s76` (or hotfix) |
| P0 | Tax on products/plans/resources (net/gross) | core+plugins | **S72** (planned) |
| P0 | User profile fields (salutation, birthday, account_type, locale, customer_number, consent) | core | extend UserEdit (small) |
| P0 | Manufacturer, product_number/EAN, SEO (reuse S56) | shop | `s76` |
| P1 | Customer **groups** | core | **S73** (planned) |
| P1 | **Multiple user addresses** | core | `s74` |
| P1 | Customer-360 detail page | fe-admin | `s75` |
| P1 | Property framework + real variant configurator | shop | `s77` |
| P1 | Advanced/tiered + per-group pricing | shop (+S73/S72) | `s78` |
| P2 | Generic **Tags + Custom Fields** framework (user+product) | core | new |
| P2 | Cross-sell/bundles, product CMS layout, media UX, review moderation | shop | new |

## Bottom line
vbwd is **ahead** of Shopware on identity/permissions/tokens/subscriptions (its SaaS core) and already has a credible shop spine (variants, categories, warehouses, orders, reviews, wishlist, abandoned-cart). The **highest-leverage** gaps are: (1) **multiple addresses** + a few profile fields and a real **customer-360** view on the user side; (2) on the product side — **proper tax (S72)**, **manufacturer/product-number/SEO**, a **property→variant configurator**, **advanced/per-group pricing**, and fixing the **un-persisted category assignment** defect. S72 and S73 already cover tax and customer-groups; the rest map cleanly to new sprints s74–s78. None of this is committed — this report is analysis + proposals.
