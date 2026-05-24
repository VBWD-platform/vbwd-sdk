# Phase 0 Outcome + Locked Decisions (authoritative)

**Date:** 2026-05-19
**Status:** Phase 0 implemented & verified. Phase 1 plan re-baselined per this
document. This file is the **single source of truth** for the corrected
findings and the locked decisions; report 01 and Sprints 03–08 are revised to
agree with it.

---

## 1. Phase 0 — what shipped (code only, no commits)

| Sprint | Result |
|---|---|
| 01 backend dead code | 11 unreachable files deleted (8 orphan routes + 3 unregistered handlers), dangling `handlers/__init__` export fixed, 4 dead-handler test classes removed, agnosticism-fence test added. **750 passed / 4 skipped == baseline.** App boots; plugin still serves all 41 subscription routes. Lint clean. |
| 02 frontend dead duplicates | fe-user: 8 dead views + 2 dead stores (`subscription.ts`, `plans.ts`) + barrel + 10 dead-code specs deleted. fe-admin: 8 dead views deleted. Guard specs added. fe-user core suite **311 passed**; fe-admin **236 passed**. |

## 2. The audit correction (why Phase 1 is re-baselined)

The E1 RED-gate (`vue-tsc`/`vitest`) **falsified part of report 01's audit**.
Files report 01 §3.2/§3.4 labelled "dead duplicates" are in fact **live
shared core capabilities** that plugins import through the `@/` alias:

- **fe-user:** `vue/src/stores/checkout.ts` and all of
  `vue/src/components/checkout/*` (`EmailBlock`, `PaymentMethodsBlock`,
  `TermsCheckbox`, `BillingAddressBlock`) are imported by `plugins/checkout`,
  `plugins/booking`, and `plugins/subscription` via `@/stores/checkout` /
  `@/components/checkout/*`. **Restored.**
- **fe-admin:** `vue/src/stores/{planAdmin,addons,categoryAdmin}.ts` and
  `vue/src/components/CategoriesTab.vue` are imported by
  `plugins/subscription-admin` via `@/stores/*` / `@/components/CategoriesTab`.
  **Restored.**

Only files with **zero live importers** were deleted (the per-view dead
copies). Net architectural truth, revised:

> The frontend problem is **not** dead duplication. It is **plugins
> depending on core internals through the `@/` alias** — a core→plugin
> dependency-inversion violation in the *opposite* shape we assumed. Core
> ships generic stores/components; plugins reach into them. Phase 1's job is
> to invert that dependency (plugins own their domain code; core exposes only
> generic, un-named extension points), **not** to delete files.

This is the single biggest correction. Sprints 06–08 are rewritten around it.

## 3. Locked decisions (binding for Phase 1)

### D1 — Re-baseline before Phase 1 coding
Report 01 §3/§5/§6 and Sprints 06–08 are revised to match §2 **before** any
Phase 1 implementation. (This document + those revisions = the re-baseline.)

### D2 — Subscription DB schema moves into the plugin migration
`vbwd_subscription`, `vbwd_tarif_plan`, `vbwd_addon*`,
`vbwd_tarif_plan_category*` are **owned by a subscription-plugin Alembic
migration**, not core. Core keeps only the basic entities (`users`,
`user_details`, `invoice`, token economy, …). Core's monolith
`20260403_1612_vbwd_all_tables.py` must **stop creating** the subscription
tables going forward.

Constraint: **data-preserving**. On an existing/prod DB the plugin migration
*adopts* the already-present tables (guarded no-op DDL, branch/stamp); on a
fresh DB the plugin migration *creates* them; with the plugin disabled the
tables are never created. No drop-and-recreate of populated tables. A prod
roll-out needs a backup + window (ops task, outside the sprint estimate).

### D3 — Disabled-plugin entitlement default = config flag, default **allow**
Core's generic `IEntitlementProvider`: when no provider is registered
(subscription plugin disabled), feature-gating **allows** by default,
overridable by an explicit core config flag. Booking/shop installs have no
plan concept and must not be gated by an absent one. Deny-all is available
only via the flag.

### D4 — Invoices and tokens **stay in core**
`/dashboard/invoice*`, `/dashboard/tokens*`, the invoices/tokens
views/stores, and their permission checks are **core functionality** and
remain in core. They are *not* moved into the subscription plugin.

Consequences for Sprint 07: its scope **shrinks**. It no longer relocates
invoices/tokens routes. It only:
- moves the hardcoded **Subscription nav group** out of `UserLayout.vue` into
  `userNavRegistry` (plugin-registered);
- moves the `subscription.*` **i18n** into the plugin via
  `sdk.addTranslations`;
- replaces hardcoded `subscription.*` permission **literals** on
  `Dashboard.vue` cards with a generic capability lookup;
- the invoices/tokens routes and their permission strings are **left as-is**
  (core), since they are core features — the `subscription.invoices.*` /
  `subscription.tokens.*` permission *names* are treated as core permission
  keys (a rename is explicitly out of scope; revisit only if you later want
  the namespace cleaned).

The deeper plugin→core `@/` coupling (§2) is the new Phase-1 frontend theme:
plugins must stop importing core stores/components by reaching through `@/`.
Whether that is solved by (a) plugins owning their own copies, or (b) core
publishing those generic pieces as a documented, un-domain-named extension
API, is a **design question to settle at the kickoff of the revised Sprint
08** (recorded there as an open question), not assumed here.

## 3e. Backend complete (merged Sprint 03 — S1–S5b, S6→A, S7→A1) ✅

As of 2026-05-23 the backend slice of the extraction is **done & verified**
under the locked decisions; the tree is green (core unit **777/4**, plugin
**36**, lint clean, single Alembic head, clean `alembic upgrade head`).

Core owns **no** subscription: routes (S2), repos/services/DI (S4),
feature-gating (S3→`IEntitlementProvider`), invoice line-item resolution +
recurrence (S1, S5a→line-item registry), admin read enrichment
(S4→`ISubscriptionReadModel`), seeders (S5b→demo-data registry). Subscription
**model classes stay in core** as shared domain (R3=A — 6 plugins depend on
them). The subscription plugin **owns an Alembic migration branch** (S7=A1);
future subscription schema changes live there. Remaining backend item: **A2**
(extract the initial table DDL from the core monolith) — deferred, low value,
prod-gated, FK-entangled.

**S7 prod RUNBOOK:** the baseline revision `20260523_1000_sub_baseline` is a
**no-op** (initial tables already exist via the monolith). Prod deploy =
`alembic upgrade head` — zero DDL, zero data risk, no backup/window needed.
(A backup/window is only required if A2 is ever undertaken.)

Remaining programme: frontend Sprints 06 (fe-core purge), 07 (fe-user),
08 (fe-admin), then 09 (cross-repo agnostic-install CI gate).

## 3l. Sprint 05 — email service made subscription-agnostic — DONE

Core `email_service` carried 5 subscription/payment send methods
(`send_subscription_activated/cancelled`, `send_payment_receipt/failed`,
`send_renewal_reminder`) + their templates + default subjects — all
**dead** (the plugin handlers are constructed with `email_service=None`, and
their tests were removed in S1). Removed them from core; added a generic
`register_template_path` (Jinja `ChoiceLoader`) so plugins own their email
templates; moved the 5 templates (10 files) to
`plugins/subscription/subscription/templates/email/` (they `{% extends
"base.html" %}` — ChoiceLoader resolves the shared base from core); rewired
the plugin handlers to the generic `send_template(to, template, context,
subject)`; `MockEmailService` accepts `subject` + `register_template_path`.
Removed the 5 stale core email tests; added `test_email_service_agnostic.py`
(register_template_path resolves a plugin template) + an oracle assertion.
Backend unit **804/4**, plugin **36**, lint clean.

> Note: full runtime template-path registration from the plugin awaits a
> real container-provided `EmailService` (today it's a `MockEmailService`
> built locally in `app.py`; subscription email sending is dead). The
> agnostic core + plugin-owned templates + generic primitive are in place.

## 3m. Sprint 08 (fe-admin) P1 — central views decoupled — DONE & e2e-verified

The last **live** core→subscription couplings in fe-admin (the ones P2 left)
are gone. New extension points on the existing `extensionRegistry`:

- **`userEditTabs`** — `UserEdit.vue`'s Subscriptions + Add-ons tabs moved to
  the plugin (`UserSubscriptionsTab.vue`, `UserAddonsTab.vue`); core renders
  plugin tabs dynamically (`getUserEditTabs()`), lazy-loading via an `active`
  prop. **Core `vue/src/stores/subscriptions.ts` deleted** (its only live
  consumer was UserEdit) — the headline result. Store + tab tests relocated
  to the plugin.
- **`userDetailsSections`** (already existed) — the `UserDetails.vue`
  subscription summary block moved to plugin `UserSubscriptionSection.vue`;
  core `UserDetail.subscription?` type + `.subscription-status` CSS + dead
  `User.subscription_plan?` removed.
- **`accessLevelUserColumns`** — the "Linked Plan" column on the user Access
  Levels table moved to plugin `LinkedPlanColumn.vue`.
- **`AccessLevelFormField.fields`** — the Access Level form now loads / seeds /
  saves plugin-owned fields **generically** (`pluginFieldKeys`,
  `pluginFieldValues`); core no longer names `linked_plan_slug` in init /
  payload / load. The UserEdit access-level checklist `linked_plan_slug` badge
  was removed (the canonical AccessLevels page shows it via the plugin column).
- **P1d**: `UserCreate.vue` user-status dropdown stopped borrowing
  `subscriptions.statuses.pending` → uses the core `users.pending` key.

**Live-verified on :8081** (admin e2e harness cracked — needs **both**
`admin_token` and `admin_token_user` in localStorage; `isAuthenticated =
token && user`): UserEdit shows Account/Invoices + plugin Subscriptions/Add-ons
tabs, each fetching on first activation (`/admin/subscriptions?...user_id=` and
`/admin/users/<id>/addons`); AccessLevels user table header row is
`[…,Permissions,System,Linked Plan,Actions]` (plugin column); the Access Level
edit form loads `linked_plan_slug` and a **save round-trip preserves it**
(PUT body carries it, re-fetch confirms). Core fe-admin **294** unit tests
(incl. the new oracle), plugin **108**, type-clean (only pre-existing
payment-plugin `vue-tsc` debt remains), lint clean.

**Residuals (decision-locked — NOT P1 violations):**
- *Invoice subscription metadata* (`stores/invoices.ts` `subscription_*`;
  `InvoiceDetails.vue` "Subscription Info" section + SUBSCRIPTION line-item
  badge) stays core under **D4** — the FE mirror of subscription *models*
  staying in core on the backend (R3). Could later move behind an
  `invoiceDetailSections` point, but it is consistent, not a leak.
- *`/admin/users/:id/deletion-info` `subscription_count`* (core `users.ts`
  type + `Users.vue` bulk-delete dialog) is a **backend API contract**;
  decoupling needs a generic `dependencies[]` payload (a backend sprint).

## 3n. Sprint 09 (FE) — fe-admin agnosticism oracle DONE; fe-user → see §3o

> **Update:** the fe-user gap identified below was closed in **§3o (Sprint 10)**.
> Both FE oracles are now green.

**fe-admin oracle DONE & CI-gating:**
`vbwd-fe-admin/vue/tests/unit/subscription-agnostic.spec.ts` (7 assertions,
green) fences the contract: core owns no subscription store / view; no core
file imports a subscription store or names the plugin; the core router has
**zero** subscription routes; `UserEdit` carries no `useSubscriptionsStore`;
the registry exposes all five decoupling getters; `AccessLevels`/
`AccessLevelForm` name no `linked_plan_slug`. The D4 / deletion-info residuals
are documented in the test as allowed.

**fe-user is NOT yet subscription-agnostic — needs its own sprint.** Sprint 07
(deliberately *shrunk*) only moved the **nav group → `userNavRegistry`** and
**subscription i18n → plugin**. A core sweep shows real, *un-extracted*
structural couplings beyond the D4-accepted invoice/token surface:
- **`stores/checkout.ts`** — the purchase/cart flow is subscription-aware
  (`type: 'subscription'`, a `subscription` cart shape, `GET /tarif-plans/:slug`,
  subscription-checkout branch). This is the big one.
- **`router/index.ts`** — `/dashboard/subscription/*` routes +
  `requiredUserPermission: 'subscription.tokens.view'` live in core.
- **`Dashboard.vue`** — `hasUserPermission('subscription.tokens.view' /
  '...invoices.view')` gates (token/invoice are D4-core, but the *checkout/
  routes* coupling is not).

→ **New finding: Sprint 10 (fe-user) needed** — extract the checkout
subscription line-item handling to the fe-user subscription plugin. **Done in
§3o below.**

## 3o. Sprint 10 (fe-user) — checkout decoupled via a source registry — DONE & e2e-verified

**Investigation correction.** Most of what §3n flagged was already
plugin-owned or D4-accepted:
- `/dashboard/{subscription,plans,add-ons,checkout/*}` routes are **already
  registered by the subscription plugin** (`plugins/subscription/index.ts`);
  core router only hosts `/dashboard/tokens` + `/dashboard/subscription/invoices`
  (D4: tokens + invoices stay core, `subscription.*` permission namespace).
- The plugin's own `subscription/stores/checkout.ts` was **dead** (no importer).

The **one real coupling** was the core `vue/src/stores/checkout.ts` — a
payment-critical store that knew both subscription (`plan`/bundles/addons,
`/user/checkout`, `/tarif-plans`) and shop (`shopItems`, `/shop/cart/checkout`),
used live by the checkout plugin's `PublicCheckoutView` **and** the subscription
`Checkout.vue`. **User chose full decouple via a registry.**

**Decoupling (mirrors the backend line-item registry):**
- **`vue/src/registries/checkoutSourceRegistry.ts`** (new, core) — generic
  `CheckoutSource` contract: `matches(ctx)` / `load` / `getLineItems` /
  `getOrderTotal` / `submit` / `reset` / optional `summaryComponent`.
- **Core `stores/checkout.ts` rewritten generic** — holds only the active
  source + payment method + submit lifecycle + result; `loadForContext(ctx)`
  picks the matching source via the registry; `lineItems`/`orderTotal`/
  `summaryComponent` project from it. Core names no plugin domain.
- **Subscription plugin** revives `subscription/stores/checkout.ts` as
  `useSubscriptionCheckoutStore` (id `subscription-checkout`) and registers a
  `CheckoutSource` (id `subscription`, `matches` planSlug) + a
  `PlanCheckoutSummary.vue`. `Checkout.vue` now uses the plugin store directly.
- **Shop plugin** adds `shop/checkoutSource.ts` (id `shop`, `matches`
  `?source=shop`, submits `/shop/cart/checkout`) + `ShopCheckoutSummary.vue`,
  derived from the existing `shopCart` store.
- **`PublicCheckoutView`** is now generic: `loadForContext({ source, planSlug })`
  + renders the active source's `summaryComponent`; no `plan`/shop branching.

**Tests:** core subscription checkout-store test **relocated** to
`plugins/subscription/tests/unit/checkout-store.spec.ts` (12, retargeted to the
plugin store); new generic core store test `vue/tests/unit/stores/checkout.spec.ts`
(8, registry-driven fake source); **fe-user oracle**
`vue/tests/unit/subscription-agnostic.spec.ts` (5) fences the contract (core
checkout store has no `/user/checkout` `/tarif-plans` `/shop/cart/checkout`
`loadPlan` `selectedBundles` `shopItems`; delegates to the registry; no core
import of a subscription/shop/checkout plugin store; no plan/checkout routes in
core). fe-user unit **477** green, type-clean (only pre-existing payment-plugin
`vue-tsc` debt), lint clean.

**Live-verified on :8080** (after a dev-container restart — Vite/bind-mount HMR
served a stale `PublicCheckoutView`, the Sprint 07 gotcha):
- `/checkout?tarif_plan_id=free` → subscription source loads, `PlanCheckoutSummary`
  renders "Free".
- `/checkout?source=shop` (empty cart) → shop source **matches** (error "Cart is
  empty", not the no-source empty state) — proves registration + matching.
- `/dashboard/checkout/free` → subscription `Checkout.vue` renders via the plugin
  store ("Free", $0/month, order summary).

**Residuals (D4-accepted, unchanged):** invoice `subscription_*` metadata
(`stores/invoices.ts`, `InvoiceDetail.vue`); `/dashboard/tokens` +
`/dashboard/subscription/invoices` core routes with `subscription.*` permission
names; `Dashboard.vue` token/invoice gates. These are tokens/invoices (core by
D4), not the checkout coupling.

## 3k. Sprint 09 — backend agnosticism oracle DONE (CI exit gate, backend)

`tests/unit/test_subscription_agnostic_backend.py` — **28 assertions**
aggregating the S1–S8 per-slice guards into one authoritative contract: core
contains no subscription routes / repos / services / DI / feature-gating /
line-item coupling / seeder imports; exposes the generic ports
(`IEntitlementProvider`, `ISubscriptionReadModel`, demo-data registry); the
plugin owns its Alembic migration branch (A1); the model classes stay in
core (A). Lives in `tests/unit/`, so it runs in the standard CI `make test`
gate automatically — the backend extraction is permanently fenced. Backend
suite **805 passed / 4 skipped**, lint clean.

**Sprint 09 remaining:** the frontend agnosticism oracle (fe-user/fe-admin
plugin-disabled assertions — depends on Sprint 08 P1) + a plugin-disabled
backend runtime proof (needs a plugins.json-toggle harness) + per-repo CI
`subscription-agnostic` jobs. Follow-ups.

## 3j. Sprint 08 (fe-admin) P2 — plugin→core `@/` import inversion DONE; P1 remaining

**P2 done & verified (decision (a) — plugin owns its copies).** The
subscription-admin plugin's views/components imported core
`@/stores/{planAdmin,addons,categoryAdmin,subscriptions}` +
`@/components/CategoriesTab`. The plugin already shipped its own copies,
diverging from core **only** by the api import path (`../api` vs `@/api` —
functionally identical, E2-safe). Repointed all plugin imports to its own
copies (`../stores/*`, `../components/CategoriesTab`); then the core copies
`vue/src/stores/{planAdmin,addons,categoryAdmin}.ts` +
`components/CategoriesTab.vue` became dead (E1 RED-gate: zero importers) and
were **deleted**, plus the `stores/index.ts` barrel export. Core
`stores/subscriptions.ts` **kept** — still used by core `UserEdit.vue` (P1).
Removed 2 core specs testing the deleted stores. Verified: fe-admin compiles
(login page renders), plugin vitest **91**, full fe-admin unit **294**,
vue-tsc no dangling refs, eslint clean.

**P1 partial — AdminTopbar titles → route meta (DONE).** The plugin's
`plans`/`subscriptions` admin routes now carry `meta.title`; core
`AdminTopbar.vue` prefers `route.meta.title` and its fallback map no longer
hardcodes `'plans'`/`'subscriptions'`. Verified: source-guard clean, fe-admin
unit **294**, eslint clean. Also cracked admin e2e auth key (**`admin_token`**,
not `auth_token`) — though full admin e2e needs the auth store's async
init/user state too (a setup prerequisite for verifying the central-view P1
work).

**P1 remaining (the larger half):** decouple core fe-admin from subscription
via extension points — `UserEdit.vue` Subscriptions/Add-Ons tabs +
`stores/subscriptions.ts` (the last live core→subscription coupling),
`UserDetails`/`stores/users.ts` (`subscription_plan`/`subscription_count`),
`AccessLevels.vue` "Linked Plan" column + `AccessLevelForm` `linked_plan_slug`,
`AdminTopbar.vue` hardcoded `'plans'`/`'subscriptions'` titles,
`UserCreate.vue` `subscriptions.statuses.*`, i18n. Needs ~3 new generic
registries (userEditTabs, user-summary slot, access-level column) on the
central admin views + admin-app e2e auth sorted (the admin guard needs more
than `auth_token` in localStorage). A focused unit (report estimate: the bulk
of L 3–4 days).

## 3i. Sprint 07 (fe-user) nav split — DONE & e2e-verified; i18n move remaining

Decision (i) implemented and verified live (dev stack up, Playwright against
localhost:8080 as the test user):
- `userNavRegistry` enhanced: `group` widened to open `string`; **multiple
  items per plugin** supported (keyed by `pluginName::route`;
  `unregister(pluginName)` removes all the plugin's items) — backward
  compatible (chat/ghrm/meinchat single-item plugins still pass).
- `UserLayout.vue`: the **hardcoded Subscription nav group is removed**;
  Plans/Add-Ons removed from the hardcoded Store group (Tokens stays);
  a **core top-level "Invoices"** link added (decision i);
  `expandedGroups`/`toggleGroup` de-subscriptioned.
- Subscription plugin `index.ts` registers its nav via `userNavRegistry`:
  **Subscription** (top-level) + **Plans**/**Add-Ons** (`group:'store'`).
  No nav-level permission gate (E2 — old group was unconditional; routes keep
  their own `meta` gating).
- **Verified sidebar (test user):** Dashboard · Subscription · LLM-Chat ·
  Taro · Messages · Invoices(core) · Store{Tokens(core), Plans, Add-Ons,
  Software Catalogue}. Vitest guards (8) green; live render = compile proof.
- Gotcha logged: vite dev needed a **container restart** to re-run the
  plugin `install()` (HMR doesn't re-execute one-time plugin registration).

**i18n ownership move — DONE & e2e-verified.** Moved the subscription-
exclusive keys across all **8** locales (en/de/es/fr/ja/ru/th/zh) from core
into `plugins/subscription/locales/` + `sdk.addTranslations`: top-level
`subscription`, `plans`, `addons`, `addonInfo`, `planDetail` trees +
`nav.subscription/plans/addons`. Kept in core (shared/core): `common`,
`checkout` (checkout-plugin-owned, wasn't in core), `nav.invoices/tokens/
store`. Verified live: sidebar labels + the `/dashboard/plans` view render
from the plugin's i18n with **zero raw keys**; core code references none of
the moved keys; fe-user unit suite **334 passed/1 skipped**; eslint clean.
**Sprint 07 is fully complete.**

## 3h. Backend extraction LIVE-VALIDATED + Sprint 07 nav design tension

**Milestone:** the dev stack was brought up (fe-user 8080, fe-admin 8081,
backend api) and the **entire backend extraction (S1–S7) boots and serves in
the real running app** — `GET /api/v1/health` 200, admin/test **login works**,
cms/ghrm/permissions all serving. This validates S1–S7 beyond unit tests
(the app actually runs with subscription routes/repos/services/DI/feature-
gating/read-logic/seeders removed from core). Orphan `.pyc` from deleted
modules were cleaned. Sprint 07 **E1 baseline captured** (sidebar renders
Dashboard, LLM-Chat, Taro, Messages, **Store** group, **Subscription** group
for the test user; screenshot in `.sprint07/`).

**`userNavRegistry` reality:** its `UserNavItem.group` type is the literal
`'store'` only, and it *appends* items to existing groups (the Store group's
base links — plans/tokens/add-ons — are still hardcoded in `UserLayout.vue`;
only plugin extras use `getGroupItems('store')`). The subscription plugin
registers **no** nav today. So the nav split needs: widen `group` to an open
`string`, have the plugin register its items, and make `UserLayout` render
plugin-defined groups generically.

**Design tension (needs a call) — where does the core Invoices nav link go?**
Today the hardcoded "Subscription" group contains `/dashboard/subscription`
(plugin) **and** `/dashboard/subscription/invoices` (**core**, D4). Three
constraints collide: E2 (don't change UX), D4 (invoices stays core), and
agnosticism (the Subscription group should be plugin-owned). If the
Subscription group becomes plugin-owned, the core Invoices link must move
somewhere — which is a (small) UX change. Options:
- **(i)** Invoices becomes a top-level core sidebar item ("Invoices") —
  cleanest core/plugin separation; minor UX change (no longer nested under
  Subscription).
- **(ii)** Keep a core-rendered "Billing" group holding Invoices; plugin
  owns a separate "Subscription" group — two groups, closest to D4 intent.
- **(iii)** Plugin owns the "Subscription" group and the plugin renders an
  Invoices link that deep-links the core invoices route — pragmatic, but a
  plugin rendering a core link.
Plans/Add-Ons are simpler: they live in the **Store** group today and the
registry already supports plugin items there (`getGroupItems('store')`), so
the plugin registers them with `group:'store'` — zero UX change.

## 3g. Sprint 07 (fe-user) scoping — Dashboard dissolves under D4; nav/i18n are e2e-sensitive

- **Dashboard.vue: no change.** Its two gated cards (Token Activity, Recent
  Invoices) are **core** features (D4); their `subscription.tokens.view` /
  `subscription.invoices.view` permission keys are core permission keys
  (rename out of scope). No subscription-plugin card to relocate.
- **Nav group: real restructure, not a deletion.** The hardcoded
  "Subscription" group (`UserLayout.vue:165-203`) mixes a plugin link
  (`/dashboard/subscription`) with a **core** link
  (`/dashboard/subscription/invoices`, stays core per D4); the "store" group
  mixes plugin links (plans, add-ons) with a core link (tokens). De-hardcoding
  means **splitting core vs plugin nav items** and having the plugin register
  its items via `userNavRegistry` — behaviour-sensitive sidebar UI.
- **i18n:** move `subscription.*` keys to the plugin via `sdk.addTranslations`,
  leaving `nav.invoices`/tokens in core.

Per the engineering requirements (E1/E2), nav + i18n changes are verified by
**Playwright e2e** (sidebar render, route gating, string rendering) against a
live stack — there is no cheap unit-test net for sidebar behaviour. Sprint 07
(and 08, which additionally has the open P2 `@/`-import-inversion decision)
are therefore best executed with the dev stack up for e2e, not as a
unit-only tail-end change. Backend (S1–S7) + fe-core (06) are done & green.

## 3f. Sprint 06 (fe-core purge) — DONE (code), pin-propagation deferred

Org-wide E1 gate confirmed the subscription store + `useFeatureAccess` +
`FeatureGate`/`UsageLimit` + `SUBSCRIPTION_*` events + `SubscriptionPayload`
were a **self-contained dead cluster** (zero consumers across fe-user,
fe-admin, their plugins, pitchmacher). Deleted them + all public exports;
generalised `CartItemType` to an open `string` (was `'PLAN'|'TOKEN_BUNDLE'|
'ADD_ON'` — backward-compatible, consumers pass string literals). Removed 3
dead-code test files; added `tests/unit/no-domain-words.spec.ts` (9 tests)
fencing the public surface. fe-core **build green** (vite + `tsc` — dist
regenerated), eslint clean; only 2 **pre-existing** unrelated test failures
remain (`package-config` package-name, `auth-login` isAdmin).

**Propagation caveat:** fe-user/fe-admin consume fe-core via a **git
submodule pin** (their own `vbwd-fe-core/` checkouts), so seeing the new
`dist/` requires committing the fe-core change + bumping the submodule pin —
a **commit/deploy step** (not done here per the standing "code only, no
commit"). **07/08 are NOT blocked by this**: the deleted symbols had zero
consumers, so fe-user/fe-admin compile and run identically with or without
the pin bump. The "06-before-07/08" ordering only mattered for a *shared*
change with consumers; this purge has none.

## 3d. Refinement R4 — S7 true table-ownership is FK-blocked; do (A1) (OPEN-ish)

S7 Baseline (E1): single Alembic head `20260424_1015`. The subscription
tables are created **only** by the core monolith
`alembic/versions/20260403_1612_vbwd_all_tables.py` (`vbwd_addon` L300,
`vbwd_tarif_plan_category` L414, `vbwd_tarif_plan` L989, + `vbwd_subscription`,
`vbwd_addon_subscription`, 2 m2m). `alembic.ini version_locations` registers
plugin migration dirs for taro/cms/ghrm/booking/chat/shop/discount/meinchat —
**but not `plugins/subscription`** (the subscription plugin has no migration
dir yet).

**Blocker:** truly moving the *initial* subscription DDL out of the monolith
into a plugin migration is **FK-entangled** — `vbwd_user_invoice` (and others)
carry nullable FKs to `vbwd_subscription` / `vbwd_tarif_plan` created **within
the same monolith**, so the subscription tables must exist before those FKs.
Extracting them would require deferring/altering the invoice FKs too — large,
risky surgery on an already-applied migration, exactly the kind the CI
lessons warn breaks every job.

**Realisation of S7 under decision (A): do (A1).**
- **(A1) — recommended, low-risk.** Register
  `plugins/subscription/migrations/versions` in `alembic.ini` so **all future
  subscription schema changes live in the plugin** (satisfies E4 +
  `feedback_plugin_migrations_in_plugin`). The **initial** tables remain
  created by the core monolith (consistent with decision (A): subscription
  entities are shared core domain, so core legitimately owns their initial
  DDL). The plugin's first revision is a marker that chains off the core head
  (no DDL, or guarded create-if-not-exists as belt-and-suspenders). Drops the
  "plugin-disabled fresh DB has zero subscription tables" oracle line — already
  moot under (A), since the models are in core metadata and `create_all`
  builds them in dev/test regardless.
- **(A2) — deferred.** Full monolith surgery to defer the subscription DDL
  (and rework invoice FKs) to the plugin. High risk, prod-gated on the DB
  backup/window, and low marginal value given (A). Not now.

**Status:** paused before touching `alembic.ini`/migrations — the Alembic
branch wiring (down_revision chaining, single-head invariant) is CI-critical
and deserves a focused unit, not a tail-end edit. S1–S5b done & green; S6
cancelled (A); S7 = (A1), scaffolding pending.

## 3c. Refinement R3 — subscription MODELS are a shared dependency of 6 plugins (OPEN decision)

Progress: S1–S5b all **done & verified** (core suite 774/4, plugin 36).
S5b cleared every *core* importer of the 5 subscription models, so S6 (model
relocation) was attempted. It was **reverted** because relocating the models
broke the build: **six other plugins import the core subscription models
directly** —

- `plugins/stripe` (`Subscription`, `AddOnSubscription`)
- `plugins/paypal` (`Subscription`)
- `plugins/taro` (`Subscription`)
- `plugins/analytics` (`Subscription`) — MRR/active-subscription metrics
- `plugins/ghrm` (`TarifPlan`, `TarifPlanCategory`,
  `tarif_plan_category_plans`) — software catalogue reuses tarif plans

So the 5 models are not a leaf concern — they are a **shared domain
dependency** several verticals build on (like `User`/`Invoice`). Relocating
them forces a fork:

- **(A) Keep models in core** (treat subscription entities as shared core
  domain). Plugin still owns routes/services/handlers/read-port/seeders
  (S1–S5b, done) and the **DB migration** (S7/D2). The model *classes* stay
  in `vbwd/models/`. Smallest, unblocks S7 immediately; the "core defines no
  subscription model" oracle line is dropped. Pragmatic given the evidence.
- **(B) Relocate models into the subscription plugin + repoint the 6
  plugins** to import from it. Makes subscription a **required base plugin**
  for stripe/paypal/taro/analytics/ghrm — they break when it is disabled.
  Violates agnosticism (a payment plugin must not require subscription) and
  weakens the Sprint 09 oracle. Not recommended.
- **(C) Relocate models AND decouple all 6 plugins via ports/guards** (true
  agnosticism). Largest effort — effectively a mini-programme per plugin
  (analytics→metrics port, stripe/paypal→already use the line-item registry
  for recurrence, ghrm→a plan-catalogue port, etc.).

**DECISION (locked): (A).** The 5 subscription model **classes stay in
core** (`vbwd/models/`) as shared domain entities — like `User`/`Invoice` —
because 6 plugins depend on them. **S6 (model relocation) is cancelled.** The
original E3 oracle line "`import vbwd.models.subscription` ⇒
ModuleNotFoundError" is **dropped**; the revised end-state is: core *defines*
the subscription models but owns no subscription routes / services / repos /
DI / feature-gating / read logic / seeders (all done, S1–S5b) and **does not
own the subscription DB migration** (S7). Next: **S7 under (A)**. Build is
green (S6 reverted).

## 3b. Refinement R2 — S4 is a port design, not a deletion (OPEN decision)

Progress through merged Sprint 03: S1 (invoice_line_item→registry), S2
(/checkout+/addons→plugin), S3 (FeatureGuard→IEntitlementProvider, D3) all
**done & verified** (core suite 757/4, plugin 31). S4 inspection then
falsified the merged plan's S4 scope ("delete the dead core subscription
repos/services"): three **live** core surfaces still consume them for
legitimate cross-domain reads —

- `vbwd/handlers/payment_handlers.py` — payment event → activate/update
  subscription via `SubscriptionService`.
- `vbwd/routes/admin/invoices.py` — admin invoice view enriched with
  tarif-plan + subscription.
- `vbwd/routes/admin/users.py` — admin user delete/detail counts
  subscriptions (+ `container.addon_subscription_repository()`).

**R2 (binding): S4 must introduce narrow core port(s) the subscription
plugin implements** — not delete. Pattern = S3's `IEntitlementProvider`,
extended to:
- a **payment→subscription command port** (activate/update subscription on
  a captured/failed payment), and
- a **subscription read port** for admin enrichment (plan/subscription/
  addon summary by invoice / by user), with a null/empty default when the
  plugin is disabled (analogous to D3).

**Decisions (locked):** two ports (command + read), ISP-separated;
plugin-disabled read default = **empty/None enrichment** (no error).

**Findings during S4 inspection that tighten scope:**

1. **No command port is needed.** `vbwd/handlers/payment_handlers.py`'s
   "activate/update subscription via SubscriptionService" is **only
   commentary** in stub handlers — there is *no* real import or call of
   the subscription repos/services there (the grep matched a comment +
   `event.subscription_id` attributes). Building `ISubscriptionLifecycle`
   now would be a dead abstraction (YAGNI). It is **deferred** until a real
   payment→subscription call exists; the event bus already carries
   `subscription.*` if/when needed.

2. **Read port only**, with exactly three methods the live core admin
   surfaces need:
   - `enrich_invoice(invoice) -> dict` (admin invoice detail: plan_* +
     subscription_* keys) — `vbwd/routes/admin/invoices.py`
   - `count_user_subscriptions(user_id) -> int` (delete-info +
     delete_user dependency/409 check) — `vbwd/routes/admin/users.py`
   - `user_addon_subscriptions(user_id) -> list[dict]` (admin user-addons
     listing) — `vbwd/routes/admin/users.py`
   `_NullSubscriptionReadModel` returns `{}` / `0` / `[]` when the plugin
   is disabled (the locked empty/None default). The admin **endpoints stay
   in core** and merely delegate their subscription reads to the port —
   relocating those endpoints into the plugin is **out of S4 scope**
   (admin-API restructuring; a later concern aligned with Sprint 08).

This is the bounded, behaviour-preserving (E2) S4. S5–S7 remain gated
behind it (core importers gone before the S6 model move). Core
subscription repos/services + container DI deleted only **after** the read
port replaces every live consumer.

Discovered during Sprint 03 Baseline: **11 core non-plugin files** still
hard-import the 5 subscription model modules (subscription/tarif_plan/…
repositories + services, `payment_route_helpers.py`,
`invoice_line_item.py`, seeders). Those importers are **Sprint 04's**
removal scope, and Sprint 04 runs *after* Sprint 03. So Sprint 03 cannot
hard-delete the core model modules (it would `ModuleNotFoundError` the whole
backend — a gross E2 violation).

**R1 first attempt (inverted shim) — REJECTED.** Leaving core
`vbwd/models/*.py` as re-export stubs that `import from
plugins.subscription...` would force **core to import the plugin package on
startup** (`vbwd.models.__init__` is imported by almost all of core), an
import cycle risk and a *worse* "core is agnostic" violation than today.

**R1 conclusion (binding) — re-sequence, don't shim.** The model
relocation **cannot precede** the removal of core's 11 subscription
importers. The README dependency graph (03 → 04) is **backwards for this
slice**. Correct order:

1. **Sprint 04 first** (or merged): remove/relocate the core importers —
   subscription repositories, services, `payment_route_helpers`,
   `invoice_line_item` branch, seeders — so *core no longer imports the
   subscription models at all*.
2. **Then Sprint 03**: with zero core importers, the models move cleanly
   into the plugin and `import vbwd.models.subscription` ⇒
   `ModuleNotFoundError` is achievable as originally written (no shim).
3. **03b** (Alembic migration, D2) still gated on the ops
   DB-backup/maintenance-window prerequisite, run as its own focused unit.

This is a programme-structure change (swap/merge 03 and 04) and is paused
for an explicit decision rather than self-applied. Sprint 03 Baseline (E1)
remains valid and done regardless of ordering.

Status: Sprint 03 Baseline (E1) **done & verified** — schema fingerprint
snapshot captured and stable; repo round-trip green; `alembic heads` =
`20260424_1015`.

## 4. Honesty note

Per the programme rule "do not repeat the 04c mistake": Phase 0 is recorded
as Done **because the green test output exists** (counts above). The audit
correction is recorded openly here rather than silently absorbed — the report
was wrong about FE deadness; this document supersedes it where they conflict.

## 5. No commits

All Phase 0 changes are uncommitted working-tree edits in `vbwd-backend`,
`vbwd-fe-user`, `vbwd-fe-admin`, per the standing "code only, no commit"
instruction. (An environment hook auto-committed in earlier turns; no
`git commit` was issued by the implementer this session.)
