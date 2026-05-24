# Subscription Extraction — Leftover Audit & Effort Estimate

**Date:** 2026-05-19
**Type:** Investigation / architecture report (no code changed)
**Scope:** `vbwd-backend`, `vbwd-fe-user`, `vbwd-fe-admin`, `vbwd-fe-core`

> **⚠ PARTIALLY SUPERSEDED — read
> [`02-phase0-outcome-and-locked-decisions.md`](./02-phase0-outcome-and-locked-decisions.md)
> first.** Phase 0 implementation falsified part of the frontend audit
> below: the §3.2/§3.4 "dead duplicate" stores/components are in fact
> **live shared core code imported by plugins through the `@/` alias**, not
> dead files. §3.2/§3.4 carry inline corrections; report 02 is authoritative
> where they conflict. Direction was decided (**A**); four implementation
> decisions are locked in report 02 (subscription DB schema → plugin
> migration; entitlement default = config-flag/allow; invoices+tokens stay
> core; FE re-baseline).

**Question:** The 2026-03-27 sprint set extracted *subscription* out of core so it
becomes a plugin peer of *shop / booking / ghrm / ecommerce*. How complete is
that extraction, what are the leftovers, and what is the effort to (A) finish
the extraction, or (B) revert and merge the plugin back into core?

---

## 1. Executive summary

The extraction is **functionally live but physically half-done**.

- **The plugins are authoritative and wired.** `vbwd-backend/plugins/subscription`,
  `vbwd-fe-user/plugins/subscription`, and `vbwd-fe-admin/plugins/subscription-admin`
  own the routes, handlers, nav and views that actually serve traffic today.
- **Core was never cleaned.** The pre-extraction subscription code still sits in
  all four core trees as **dead duplicates, live couplings, models, DB schema,
  and i18n**. The sprint reports (`20260327/.../04c-core-cleanup.md`,
  `reports/03`) mark "delete from core" as **Done**, but those deletions are
  **absent from `main`** — and a later monolithic migration
  (`alembic/versions/20260403_1612_vbwd_all_tables.py`, dated *after* the
  extraction) re-baked the subscription schema back into core. So the recorded
  "Done" is contradicted by the codebase.
- **The original architectural goal is unmet.** A booking-only or shop-only
  install still ships and migrates the entire subscription schema, still carries
  subscription models, a live `/checkout` + `/addons` core route, `FeatureGuard`,
  and a subscription store inside the *shared component library* (`vbwd-fe-core`).

**Net assessment:** This is not a small mop-up. It is a deferred "Phase 2" that
was documented as complete but never landed. Both directions below are real
projects, not afternoons.

| Direction | Effort (engineer-days) | Risk | Architectural outcome |
|---|---|---|---|
| **A — Finish the extraction** (core → plugin) | **~15–22 dev-days** | Medium–High (DB migration, FK rework) | Matches stated goal; core truly agnostic |
| **B — Revert** (plugin → core) | **~9–14 dev-days** | Medium (mostly deletion + re-wiring) | Abandons plugin parity for subscription |

Recommendation in §6.

---

## 2. Background — what the 2026-03-27 sprint set claimed

| Sprint | Claim | Reality on `main` |
|---|---|---|
| 04a — Line-item handler registry | Added `vbwd/events/line_item_registry.py`, `handlers/core_line_item_handler.py`; slimmed `PaymentCapturedHandler`/refund/restore to delegate | **TRUE.** Sound, generic, keep. |
| 04b — Backend subscription plugin | Created `plugins/subscription/` with repos/services/routes/handlers/events/scheduler; plugin `models/__init__.py` *re-exports core models* during transition | **TRUE — and the re-export shim is still there**; transition never finished. |
| 04c — Core cleanup | Deleted core subscription models/repos/services/routes/handlers/events; removed DI; 653 tests pass | **FALSE.** None of the deletions exist on `main`. Report 03 itself admits models stayed ("…will remain until Phase 2"). |
| 04d/04e — fe-user / fe-admin plugin | Frontend plugins created | **TRUE for the plugin; core copies never deleted.** |
| 04f — Plugin compatibility | Re-added `refund_service` to container; 1,034 tests green | TRUE; but confirms subscription DI is back in core `container.py`. |

Items the docs **explicitly deferred by design** (legitimate, not bugs):
`LineItemType.SUBSCRIPTION/ADD_ON`, `SubscriptionStatus`, `BillingPeriod` enums
kept for DB compat; nullable `invoice.subscription_id` / `invoice.tarif_plan_id`
FK columns kept for existing-invoice compat; model relocation punted to an
unscheduled "Phase 2".

---

## 3. Leftover inventory (by repo)

Categories: **(a)** true leftover that belongs in the plugin · **(b)** legitimate
generic core capability — keep · **(c)** dead/unused duplicate · **(d)** test-only.

### 3.1 `vbwd-backend/vbwd/` (core)

**(a) Live couplings / true leftovers**
- `vbwd/routes/user.py` — **registered `user_bp` (app.py:230)** serves
  `/checkout` (emits `CheckoutRequestedEvent`) and `/addons*` (uses
  `container.addon_subscription_repository()`). Core actively serving
  subscription/checkout endpoints — *worst backend violation*.
- `vbwd/services/feature_guard.py` — core service, ctor depends on
  `SubscriptionRepository`, implements plan/tier feature-gating (pure
  subscription domain logic in core).
- `vbwd/models/invoice_line_item.py:45-63` — `_resolve_catalog_item_id()`
  hard-imports `Subscription`/`AddOnSubscription`, branches on
  `LineItemType.SUBSCRIPTION/ADD_ON` — exactly the anti-pattern 04a's registry
  was meant to delete.
- `vbwd/container.py:19-26,91-106` — DI factories for all 5 subscription repos,
  under a docstring that *falsely* claims subscription DI is plugin-only.
- 5 model classes (`subscription.py`, `tarif_plan.py`, `addon.py`,
  `addon_subscription.py`, `tarif_plan_category.py`) + their `__init__.py`
  exports; plugin only **re-exports** them.
- `alembic/versions/20260403_1612_vbwd_all_tables.py` — creates
  `vbwd_subscription`, `vbwd_tarif_plan`, addon tables in **core**; **no plugin
  migration exists**.
- Email templates `vbwd/templates/email/subscription_*.{html,txt}` (rendered by
  core `email_service.py`).

**(b) Keep (generic / by-design):** `line_item_registry.py`,
`core_line_item_handler.py` (TOKEN_BUNDLE-only), the kept enums and nullable
invoice FKs, loose `"subscription_id"` string keys in refund/restore aggregation,
`user_access_level_service.py` (already agnostic).

**(c) Dead/unused:** 7 orphaned route files (`routes/subscriptions.py`,
`tarif_plans.py`, `addons.py`, `admin/{subscriptions,plans,addons,categories}.py`
— blueprints never registered), `handlers/{checkout_handler,
subscription_handlers,subscription_cancel_handler}.py` (imported, never
dispatched), `routes/admin/analytics.py` (hard-imports `Subscription`, never
registered).

**(d) Test-only:** `vbwd/testing/test_data_seeder.py` + `cli/` demo seeders
import `TarifPlan`/`Subscription`.

> Note: no core file imports from `plugins.subscription` (good). The coupling is
> the inverse — the plugin depends on core models, and core depends on its own
> retained subscription code.

### 3.2 `vbwd-fe-user/vue/src/` (core)

> **CORRECTION (Phase 0):** `stores/checkout.ts` and `components/checkout/*`
> are **NOT dead** — `plugins/checkout`, `plugins/booking` and
> `plugins/subscription` import them via `@/stores/checkout` /
> `@/components/checkout/*`. Only `stores/subscription.ts` & `stores/plans.ts`
> were dead and were deleted in Sprint 02; checkout store/components were
> restored. Per locked decision **D4**, `router/index.ts` invoices/tokens
> routes **stay in core** (core functionality) — the bullet below is
> down-scoped accordingly. The real FE issue is plugins importing core via
> `@/` (see report 02 §2).

**(a) True leftovers / violations**
- `layouts/UserLayout.vue:165-202,425,448` — hardcoded "Subscription" nav group
  while an agnostic `userNavRegistry` exists right beside it and is used for
  other plugins. `toggleGroup`'s type union hardwires `'subscription'`.
- `router/index.ts:32-56` — 5 hardcoded subscription routes (tokens, invoices,
  invoice pay) + `subscription.*` permission strings. Plugin `index.ts` comment
  even admits "Invoices route is in core router".
- `stores/subscription.ts`, `stores/plans.ts`, `stores/checkout.ts` — duplicated
  by the plugin; still exported via `stores/index.ts`.
- `i18n/locales/{en,de,zh}.json` — full `subscription.*` / `nav.subscription`
  trees; plugin ships **no** translations and depends on these.
- `views/Dashboard.vue:73,110` — hardcoded `subscription.*` permission gates.

**(b) Keep (generic):** `utils/planDetailTabRegistry.ts`,
`registries/checkout*Registry.ts` (generic checkout extension hooks consumed by
the plugin), `stores/invoices.ts` (core domain; carries optional subscription
FKs).

**(c) Dead duplicates:** `views/{Plans,Subscription,AddOns,AddonDetail,
AddonInfoView,Checkout,PlanDetailView,TarifPlanDetail}.vue`,
`components/checkout/BillingAddressBlock.vue` — all shadow the plugin's
authoritative copies; not in the core router.

### 3.3 `vbwd-fe-core/src/` (shared `vbwd-view-component` library) — **highest severity**

A reusable library must never know about subscription. It currently does, **and
it is dead** (no fe-user/plugin consumer imports it):
- `stores/subscription.ts` + `stores/index.ts:12-13` (public export
  `useSubscriptionStore`, `SubscriptionState`).
- `composables/useFeatureAccess.ts` (imports the subscription store).
- `components/access/FeatureGate.vue`, `UsageLimit.vue` (subscription-worded).
- `events/events.ts:22-28,99-102,181-186` — `SUBSCRIPTION_*` events +
  `SubscriptionPayload` on the shared bus.
- `stores/cart.ts:8` `CartItemType = 'PLAN' | 'TOKEN_BUNDLE' | 'ADD_ON'`,
  `CartItem.vue` label — bakes subscription kinds into the generic cart.

### 3.4 `vbwd-fe-admin/vue/src/` (core)

> **CORRECTION (Phase 0):** `stores/{planAdmin,addons,categoryAdmin}.ts` and
> `components/CategoriesTab.vue` are **NOT dead** — `plugins/subscription-admin`
> imports them via `@/stores/*` / `@/components/CategoriesTab`. Only the 8
> per-view core copies (`views/{Plans,PlanForm,Subscriptions,…}.vue`) were
> dead and were deleted in Sprint 02; the stores/component were restored. The
> "~13 dead files" figure in §5/A9 is wrong — see report 02 §2. The real FE
> issue is the plugin→core `@/` import coupling, addressed by the rewritten
> Sprint 08.

**(a) Live leftovers / violations**
- `stores/subscriptions.ts` — duplicated by plugin **and** still imported by
  live core `views/UserEdit.vue:708`. Only leftover that is both duplicated and
  live; core `UserEdit` cannot function without it.
- `views/UserEdit.vue:58-79,421-504,603-691` — hardcoded "Subscriptions" and
  "Add-ons" tabs with full fetch/pagination baked into a core user view.
- `views/UserDetails.vue`, `stores/users.ts` (`UserDetail` embeds
  `subscription_plan/_count/subscription{}`), `Users.vue`, `UserCreate.vue` —
  core user domain model is subscription-contaminated.
- `views/AccessLevels.vue:169,201-203` — hardcoded "Linked Plan" **column**
  even though the *form field* was correctly migrated to a plugin extension
  hook (`accessLevelFormFields`). Half-migrated, inconsistent.
- `layouts/AdminTopbar.vue:22-23` — hardcodes plugin route titles
  (`'plans': 'Plan Management'`, `'subscriptions': 'Subscriptions'`).
- `i18n/locales/*.json` (8 locales) — top-level `subscriptions/plans/addOns`,
  `nav.tarifs/plans/addOns/subscriptions`; plugin ships **no** i18n.

**(b) Keep (generic):** `stores/invoices.ts` + `InvoiceDetails.vue`
(invoice carrying optional subscription metadata), `analytics.ts`,
`tokenBundles.ts`/`TokenBundleForm.vue` (token bundles are a *separate* core
feature, not subscription).

**(c) Dead duplicates (safe to delete):** core
`views/{Plans,PlanForm,Subscriptions,SubscriptionDetails,SubscriptionCreate,
AddOns,AddonForm,CategoryForm}.vue`, `stores/{planAdmin,addons,categoryAdmin}.ts`,
`components/CategoriesTab.vue`, and the `usePlanAdminStore` barrel export. Router
registers **zero** subscription routes; the plugin registers all 12 → core
copies are unreachable. The copies have **diverged** (plugin `Plans.vue` adds
permission gating absent from core), proving the plugin is the maintained fork.

**(d) Test-only:** ~11 core e2e specs (`admin-subscription*.spec.ts`,
`admin-plan*.spec.ts`, `admin-user-subscription-flow.spec.ts`, …) target
plugin-owned routes; should move to `plugins/subscription-admin/tests/`.

---

## 4. Risk / severity ranking (worst first)

1. **fe-core ships a dead subscription store/composable/events as public library
   API.** A shared lib being gnostic about subscription is the single worst
   violation; also dead weight.
2. **Backend `user_bp` serves live `/checkout` + `/addons`** from core, plus
   `feature_guard.py` and `invoice_line_item.py` hard-coding subscription.
3. **DB schema + 5 models owned by core; no plugin migration.** The original
   motivation (booking-only install shouldn't carry subscription) is unmet.
4. **fe-admin `UserEdit.vue` + `stores/subscriptions.ts`** — duplicated *and*
   live; core user editing depends on subscription code.
5. **Hardcoded nav/router/i18n in both frontends** bypassing the agnostic
   registries that already exist.
6. **~16 dead duplicate view/store files across the two frontends** — risk of
   edits landing on the wrong (dead) copy. (We already hit this class of bug
   indirectly: divergence between core and plugin copies is unmanaged.)

---

## 5. Effort estimates (both directions)

Assumptions: one engineer familiar with the codebase; estimates are
**engineer-days** including tests, lint/CI green, and review; they exclude
product/QA sign-off and prod data migration windows. Ranges reflect the DB-FK
unknowns. "S/M/L" ≈ <1 / 1–3 / 3+ days.

### Direction A — Finish the extraction (core → plugin) — **~15–22 dev-days**

> **CORRECTION (Phase 0, report 02):** Direction A was **chosen** and is in
> progress. The table below is the original estimate; these rows are now
> wrong and superseded by the revised Sprints 01–09:
> - **A1/A6** "delete dead" — done in Sprints 01–02, but far fewer files
>   were dead than estimated (the FE stores/components were live; see §3.2/
>   §3.4 corrections). The remaining FE work is **decoupling plugin→core
>   `@/` imports**, not deletion.
> - **A7** — invoices/tokens routes **stay in core** (decision D4); A7
>   shrinks to nav-group + i18n + Dashboard-gating only.
> - **A9** "delete ~13 dead files" — wrong; fe-admin had 8 dead views, the
>   rest are live. Rewritten as Sprint 08 (plugin→core coupling).
> - **A3** — subscription DB schema moves into a **plugin migration**
>   (decision D2), not "adopt in place".
> Authoritative breakdown: `docs/dev_log/20260519/sprints/` (revised).

| # | Workstream | Detail | Effort |
|---|---|---|---|
| A1 | Backend: delete dead core code | Remove 7 orphaned routes, 3 unregistered handlers, `routes/admin/analytics.py`, dead service files; drop their `__init__` exports | M (2) |
| A2 | Backend: move models into plugin | Move 5 model classes into `plugins/subscription/subscription/models/`, flip the re-export shim, fix `vbwd/models/__init__.py` | M–L (3) |
| A3 | Backend: plugin owns its schema | New `plugins/subscription/migrations/` with create-tables; **migration to detach from `20260403` monolith**; keep nullable invoice FKs as generic columns | **L (3–5)** ⚠ |
| A4 | Backend: break live couplings | Relocate `FeatureGuard` to plugin (or behind a generic capability interface); remove subscription DI from `container.py`; replace `invoice_line_item._resolve_catalog_item_id` subscription branch with a registry lookup; move `/checkout` + `/addons` off `user_bp` into the plugin blueprint | **L (3–4)** ⚠ |
| A5 | Backend: email templates | Move `subscription_*` templates to plugin; make `email_service` resolve templates via a plugin-registered path | S–M (1–2) |
| A6 | fe-user: delete dead views/stores | Remove 8 dead views + 3 stores + dup component + barrel exports | S (1) |
| A7 | fe-user: de-hardcode nav/router/i18n | Move the Subscription nav group to `userNavRegistry`, move the 5 routes + permission strings into the plugin, move `subscription.*` i18n into `sdk.addTranslations`; fix `Dashboard.vue` gating via a capability flag | M–L (2–3) |
| A8 | fe-core: purge subscription from shared lib | Delete `stores/subscription.ts`, `useFeatureAccess`, `SUBSCRIPTION_*` events; generalise `FeatureGate`/`UsageLimit`/`cart` types to remove subscription vocabulary; **bump the consumed dist + submodule pins** | M (2) — coordination-heavy |
| A9 | fe-admin: delete dead + resolve live | Delete ~13 dead files; resolve `UserEdit` tabs + `stores/subscriptions.ts` via a plugin tab-extension point; move "Linked Plan" column to a plugin column hook; de-hardcode `AdminTopbar` titles; move i18n into plugin; relocate e2e specs | **L (3–4)** ⚠ |
| A10 | Cross-repo: agnostic install proof | Verify a booking-only/shop-only install has zero subscription tables, routes, nav, strings; CI matrix | M (2) |

Risk drivers: **A3/A4/A9** (DB migration off a monolithic baseline; FK
direction; an established extension-point pattern must be introduced for
`UserEdit` tabs). If existing prod data must be migrated table-by-table, add
**+3–5 days** and a maintenance window.

### Direction B — Revert: merge plugin back into core — **~9–14 dev-days**

| # | Workstream | Detail | Effort |
|---|---|---|---|
| B1 | Pick the source of truth | Plugin copies have **diverged** and are the maintained fork (e.g. fe-admin plugin `Plans.vue` adds permission gating core lacks). Reverting means **promoting plugin copies over the stale core copies**, not just deleting plugins | M (2) — diff/merge each pair |
| B2 | Backend: fold plugin into core | Move plugin repos/services/routes/handlers/events/scheduler back under `vbwd/`; register blueprints/handlers in `app.py`; keep models/schema where they already are | M–L (3) |
| B3 | Backend: delete plugin + re-export shim | Remove `plugins/subscription/`, drop from `plugins.json`/`config.json`; un-shim models | S–M (1–2) |
| B4 | fe-user: promote plugin views/stores into core | Replace the 8 stale core views/3 stores with the plugin's diverged copies; re-add routes/nav to core router/UserLayout (already partly hardcoded — convenient here); delete plugin | M (2–3) |
| B5 | fe-admin: same | Promote plugin's 8 views/4 stores/components into core; re-register 12 routes + nav in core; resolve `UserEdit`/`AccessLevels` back to plain core; delete plugin | M–L (3) |
| B6 | fe-core | Keep the (now-used) subscription store/composable, or inline into fe-user core; minor | S (1) |
| B7 | i18n / tests | i18n already in core (no move needed); move plugin tests back into core suites | S–M (1–2) |

Risk drivers: **B1/B4/B5** — the divergence means a real merge, not a delete;
miss a plugin-only fix and you regress behaviour that's live today. Lower DB
risk than A (schema already in core).

> Why B is cheaper: most of what A must *build* (plugin migration, extension
> points, agnostic registries, dist/submodule bumps) simply disappears, and the
> core hardcoded nav/router/i18n that A must *remove* becomes *reuse* for B.

---

## 6. Recommendation

**Pursue Direction A (finish the extraction), in two shippable phases — but
first close the documentation/reality gap.**

1. **Immediate, low-risk, do regardless of direction (~2–3 days):** delete the
   ~16 dead duplicate view/store files in both frontends and the 7 orphaned
   backend routes. This removes the "edit the wrong copy" hazard and shrinks the
   problem before any architectural decision. It is pure subtraction with no
   behaviour change (the files are unreachable today).
2. **Phase A-core (the architectural payoff, ~10–14 days):** plugin owns its
   models + migration, break the live `user_bp`/`FeatureGuard`/`invoice_line_item`
   couplings, purge fe-core. This is what actually delivers "a booking-only
   install carries no subscription".
3. **Phase A-polish (~3–5 days):** i18n into plugin, nav via registries, e2e
   specs relocated, agnostic-install CI proof.

Rationale: Direction B is cheaper today but **permanently abandons subscription
parity with shop/booking/ghrm** — i.e. it spends 9–14 days to move *away* from
the stated architecture, and the next vertical (booking/shop) will re-raise the
exact same agnosticism problem. Direction A is more expensive but is the only
one that satisfies the original goal and is naturally phaseable so value lands
incrementally. Choose B only if the plugin-parity goal itself has been dropped.

**Also:** correct `docs/dev_log/2026/03/20260327/done/04c-core-cleanup.md` /
`reports/03` — they record core cleanup as **Done** when it never landed.
Leaving a false "Done" in the dev log is how this stayed hidden for ~7 weeks.

---

## 7. Appendix — key evidence pointers

- Sprint docs: `docs/dev_log/2026/03/20260327/done/04-subscription-plugin-extraction.md`,
  `04c-core-cleanup.md`, `reports/01-sprint-04a-line-item-handler-registry.md`,
  `reports/02-sprint-04b-subscription-backend-plugin.md`, `reports/03`.
- Backend live coupling: `vbwd/routes/user.py` (registered `app.py:230`),
  `vbwd/services/feature_guard.py`, `vbwd/models/invoice_line_item.py:45-63`,
  `vbwd/container.py:19-26,91-106`,
  `alembic/versions/20260403_1612_vbwd_all_tables.py`.
- fe-user: `vue/src/layouts/UserLayout.vue:165-202`,
  `vue/src/router/index.ts:32-56`, dead `vue/src/views/{Plans,Subscription,…}.vue`.
- fe-core: `src/stores/subscription.ts`, `src/composables/useFeatureAccess.ts`,
  `src/events/events.ts:22-28`.
- fe-admin: `vue/src/views/UserEdit.vue:708`, `vue/src/stores/subscriptions.ts`,
  dead `vue/src/views/{Plans,PlanForm,Subscriptions,…}.vue`,
  plugin routes `plugins/subscription-admin/index.ts:12-77`.

*Investigation was read-only; no source files were modified.*
