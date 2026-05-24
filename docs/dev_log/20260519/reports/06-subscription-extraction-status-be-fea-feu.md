# Report 06 — Subscription extraction: what's in core vs plugins (BE / FE-A / FE-U)

**Date:** 2026-05-24 · **Author:** Claude (Opus 4.7)
**Scope:** the current, verified state of the subscription extraction (Direction
A) across the three layers — backend (`vbwd-backend`), admin frontend
(`vbwd-fe-admin`), user frontend (`vbwd-fe-user`).
**Method:** read the live plugin trees + core source + the three CI agnosticism
oracles (the authoritative contracts). Decision keys (A, A1, D3, D4, R3, R4) are
from [report 02](02-phase0-outcome-and-locked-decisions.md).

---

## 0. Executive summary

| Layer | Subscription owned by plugin | Stays in core (by decision) | CI gate |
|---|---|---|---|
| **Backend** | routes, repositories, services, handlers, scheduler, DI providers, Alembic branch, email templates | model **classes** (A/R3), generic ports, invoices+tokens (D4), domain-event defs | `tests/unit/test_subscription_agnostic_backend.py` |
| **fe-admin** | all subscription/plan/add-on views + stores + UI (tabs, columns, fields, widget) | extension-point registry, invoices+tokens (D4), deletion dependency count | `vue/tests/unit/subscription-agnostic.spec.ts` |
| **fe-user** | plan/subscription/add-on/checkout views + stores + nav + i18n; public checkout + shop checkout source | generic checkout store + source registry, invoices+tokens (D4) routes + Dashboard gates | `vue/tests/unit/subscription-agnostic.spec.ts` |

**One line:** core owns **no** subscription routes / repos / services / stores /
business logic in any layer. What remains is decision-locked: the **model
classes** (shared domain), the **generic ports/extension points** plugins plug
into, and **invoices + tokens** (which were deliberately kept core, D4).

---

## 1. Backend (`vbwd-backend`)

### Moved to `plugins/subscription/`
- **Routes** (9): `user_checkout`, `user_subscriptions`, `user_plans`,
  `user_addons`, `admin_subscriptions`, `admin_plans`, `admin_addons`,
  `admin_categories` (+ `__init__` blueprint).
- **Repositories** (5): `subscription`, `addon`, `addon_subscription`,
  `tarif_plan`, `tarif_plan_category`.
- **Services**: `subscription_service`, `tarif_plan_service`,
  `tarif_plan_category_service`, + the port **implementations**
  `subscription_entitlement_provider`, `subscription_read_model`.
- **Handlers**: `checkout_handler`, `cancel_handler`, `line_item_handler`
  (registers SUBSCRIPTION/ADD_ON handlers), `access_level_handler`,
  `subscription_handlers`.
- **Scheduler**: subscription lifecycle jobs (core `scheduler.py` now only
  carries a "moved to plugin" note).
- **DI providers**: the 5 repository providers registered on the container in
  `__init__.on_enable` (see [report 04](04-checkout-payment-di-provider-fix.md)).
- **Alembic**: own migration branch `plugins/subscription/migrations/versions`
  (decision **A1**).
- **Email**: the 5 subscription/payment templates (Sprint 05); core kept a
  generic `register_template_path`.

### Stays in core (by decision)
- **Model classes** — `vbwd/models/{subscription,tarif_plan,addon,
  addon_subscription,tarif_plan_category}.py` (**decision A / R3**: 6 plugins —
  stripe, paypal, taro, analytics, ghrm, + invoices — depend on them). The
  plugin's `models/` only re-exports.
- **Generic ports** (core defines the interface, the plugin implements):
  - `vbwd/services/entitlement.py` — `IEntitlementProvider` + default-**allow**
    when no plugin (decision **D3**).
  - `vbwd/services/subscription_read_model.py` — `ISubscriptionReadModel` + null.
  - `vbwd/services/demo_data_registry.py` — seeder/cleaner hooks.
  - `vbwd/events/line_item_registry.py` + `vbwd/handlers/core_line_item_handler.py`
    — core handles **TOKEN_BUNDLE**; SUBSCRIPTION/ADD_ON delegated to the plugin.
- **Invoices + tokens (D4)** — `invoice`, `invoice_line_item`, `token_*`
  models/repos/routes remain core. The invoice→subscription FK is the **R4**
  entanglement (an invoice may reference a subscription).

### Residuals worth a later look (not gated, low priority)
- `vbwd/events/subscription_events.py` — subscription `DomainEvent` *class
  definitions* still in core. Candidate to move to the plugin; harmless today.

### CI gate
`tests/unit/test_subscription_agnostic_backend.py` asserts: deleted core
modules (routes/repos/services/feature-guard) are gone; core repos/services
export no subscription classes; the container wires no subscription factories;
`user_bp` serves no `/checkout` or `/addons`; `InvoiceLineItem` has no
subscription coupling (uses the registry); seeders don't import subscription
models; the **ports** exist; the **models stay** (A); the plugin owns a
**migration branch** (A1); no subscription email templates/methods in core.

---

## 2. Admin frontend (`vbwd-fe-admin`)

### Moved to `plugins/subscription-admin/`
- **Views** (8): `Plans`, `PlanForm`, `Subscriptions`, `SubscriptionDetails`,
  `SubscriptionCreate`, `AddOns`, `AddonForm`, `CategoryForm`.
- **Stores** (4): `subscriptions`, `planAdmin`, `addons`, `categoryAdmin`.
- **Components / extension contributions**: `SubscriptionAdminWidget`
  (dashboard), `CategoriesTab`, `LinkedPlanField` + `LinkedPlanColumn` (access
  levels), `UserSubscriptionsTab` + `UserAddonsTab` (UserEdit), and
  `UserSubscriptionSection` (UserDetails).
- **Routes + nav** for all of the above; core `stores/subscriptions.ts`
  **deleted**.

### Stays in core
- **The extension registry** `vue/src/plugins/extensionRegistry.ts` — the
  *points*, not subscription logic: `getUserEditTabs`,
  `getUserDetailsSections`, `getAccessLevelTabs`, `getAccessLevelFormFields`,
  `getAccessLevelUserColumns`, `getPlanTabSections`, nav/section getters.
- **Invoices + tokens (D4)** — `stores/invoices.ts`, `InvoiceDetails.vue`
  (carries optional `subscription_*` invoice metadata), token views.
- **Deletion dependency count** — `Users.vue` / `stores/users.ts` read
  `subscription_count` from the backend `/deletion-info` (a backend API
  contract; see residuals §5).
- `AccessLevelForm.vue` is **generic** (plugin fields via `pluginFieldKeys`); it
  only mentions `linked_plan_slug` in a doc comment.

### CI gate
`vue/tests/unit/subscription-agnostic.spec.ts` (7 assertions): no subscription
store/view in core; no core import of a subscription store or the plugin; no
subscription routes in the core router; `UserEdit` has no `useSubscriptionsStore`;
the registry exposes the 5 decoupling getters; `AccessLevels`/`AccessLevelForm`
name no `linked_plan_slug`.

---

## 3. User frontend (`vbwd-fe-user`)

### Moved to plugins
- **`plugins/subscription/`** — views (`Plans`, `Subscription`, `AddOns`,
  `Checkout`, `AddonDetail`, `AddonInfoView`, `PlanDetailView`,
  `TarifPlanDetail`), stores (`plans`, `subscription`, `checkout`), all
  `/dashboard/{plans,subscription,add-ons,checkout/*}` routes, nav
  (`userNavRegistry`), i18n (8 locales), and a **checkout source** + its
  `PlanCheckoutSummary`.
- **`plugins/checkout/`** — the generic public `/checkout` page + the
  step/context/confirmation registries (provider-agnostic framework).
- **`plugins/shop/`** — `shopCheckoutSource` + `ShopCheckoutSummary` (shop cart
  is a checkout source, not core).

### Stays in core
- **Generic checkout store** `vue/src/stores/checkout.ts` — now plugin-agnostic:
  drives whatever `CheckoutSource` matches (no `/user/checkout`, `/tarif-plans`,
  `loadPlan`, or `shopItems` — verified 0 references).
- **`vue/src/registries/checkoutSourceRegistry.ts`** — the checkout extension
  point; plus `userNavRegistry`, `planDetailTabRegistry`.
- **Invoices + tokens (D4)** — `stores/invoices.ts`, `InvoiceDetail.vue`,
  `InvoicePay.vue`, and the core router routes `/dashboard/tokens`,
  `/dashboard/tokens/:id`, `/dashboard/subscription/invoices`,
  `/dashboard/invoice/:id`, `/dashboard/invoice/:id/pay`.
- **Dashboard gates** — `Dashboard.vue` uses `subscription.tokens.view` /
  `subscription.invoices.view` permissions (the backend permission **namespace**;
  the features themselves are core by D4).

### CI gate
`vue/tests/unit/subscription-agnostic.spec.ts` (5 assertions): the source
registry exists; the core checkout store carries no subscription/shop endpoint
or state and delegates via `loadForContext`; no core file imports a
subscription/shop/checkout plugin store; the core router hosts no
plan/checkout/add-ons routes.

---

## 4. Decisions reference

| Key | Decision |
|---|---|
| **A** | Subscription **model classes** stay core-defined (shared by 6 plugins). |
| **A1** | The plugin owns its **Alembic migration branch**. |
| **D3** | Disabled-plugin entitlement default = config flag, default **allow**. |
| **D4** | **Invoices and tokens stay in core** (and may reference subscriptions). |
| **R3** | Subscription models are a shared dependency of 6 plugins → can't move. |
| **R4** | Invoice→subscription FK entanglement → invoice metadata stays core. |

---

## 5. Net residuals (in core, by design or pending)

| Residual | Layer | Status |
|---|---|---|
| Subscription model classes | BE | **D4/A — keep** (shared domain) |
| Invoice `subscription_*` metadata + "Subscription Info" section | BE, FE-A, FE-U | **D4 — keep** (could later move behind an `invoiceDetailSections` point) |
| Tokens (routes/views/repos) | all | **D4 — keep** |
| `subscription.*` **permission namespace** on core token/invoice routes/gates | FE-A, FE-U | cosmetic backend naming; harmless |
| `/deletion-info` `subscription_count` | FE-A | backend API contract — needs a generic `dependencies[]` (backend follow-up) |
| `subscription_events.py` class defs | BE | candidate to move to plugin (not gated) |
| Checkout/invoice **e2e fixtures** target removed routes | FE-U | pre-existing rot — **task #36** |

**Three CI oracles** (one per layer) keep the contract from regressing; all
three are green.

---

## 6. Conclusion

The subscription extraction (Direction A) is **functionally complete** across
all three layers. Core is provably subscription-agnostic for routes, repos,
services, stores, and business logic. The remaining core footprint is exactly
the locked decisions — shared model classes, the generic ports/extension points,
and the deliberately-core invoices + tokens — plus a short list of cosmetic /
backend-contract residuals tracked above. The recent fixes
([report 04](04-checkout-payment-di-provider-fix.md) DI providers,
[report 05](05-stripe-success-polling-loop-fix.md) polling loop) closed the last
runtime gaps the extraction had left in the checkout/payment path.
