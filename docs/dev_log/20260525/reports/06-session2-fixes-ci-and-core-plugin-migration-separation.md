# Report — 2026-05-25 (session 2): fe-user fixes, plugin docs, CI remediation & core⇄plugin migration separation

Continues the day after [`05-fe-user-fixes-and-ux-features.md`](05-fe-user-fixes-and-ux-features.md).
This session covers six tracks of work, ending with the headline item: **finishing
the core⇄plugin separation at the migration/dependency layer** so the backend
core resolves standalone and every CI is green.

Read order for this report:
1. [Cart / checkout persistence](#1-cart--checkout-persistence-fe-user)
2. [Subscription plugin documentation](#2-subscription-plugin-documentation)
3. [Token-bundle delete 500 guard](#3-token-bundle-delete-500--guard)
4. [Access Levels checkbox-hides-table bug](#4-access-levels-checkbox-hides-table-bug-fe-admin)
5. [CI remediation across the org](#5-ci-remediation-across-the-org)
6. [Core⇄plugin migration & dependency separation](#6-coreplugin-migration--dependency-separation-priority-1)

**Engineering requirements (binding):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering**, with `bin/pre-commit-check.sh`
as the quality guard. All changes were validated (unit + Playwright e2e + the
pre-commit gate + live CI).

**Commit ownership.** The non-CI fixes (tracks 1–4) were implemented here and
committed by the user under "multiple updates" / "access management features"
commits (`plugins/` is gitignored in each core repo, so plugin code lives on
disk and in its own repo). The CI remediation and the core⇄plugin separation
(tracks 5–6) were committed **and pushed** directly to `main` of each affected
repo this session (the user said "fix CIs" / "priority #1: finish separating").

---

## 1. Cart / checkout persistence (fe-user)

**Problem (user).** "The cart and checkout in the user dashboard forget their
line-item list when the user goes to another page. The cart should be kept also
after logout/login." Reproduction: plans → select plan → on checkout add 3
add-ons + 2 bundles → the cart icon shows no count, the popup is empty, navigate
away/back → only the tarif plan remains.

**Root cause.** The subscription checkout store
(`plugins/subscription/subscription/stores/checkout.ts`, id
`subscription-checkout`) kept `selectedBundles` / `selectedAddons` as **ephemeral
Pinia refs**, and `Checkout.vue`'s `onUnmounted(() => store.reset())` wiped them
on every navigation. They never reached the persisted fe-core `useCartStore`, so
the cart icon/popup (which read the cart store) stayed empty and selections were
lost on nav + logout/login. The plan persisted only because it was route-driven.

**Fix (SOLID/DRY — single source of truth).** Made the persisted `useCartStore`
the single source of truth for the whole checkout selection:
- `selectedBundles` / `selectedAddons` are now **computeds** over
  `cart.getItemsByType('TOKEN_BUNDLE' | 'ADD_ON')`.
- `addBundle`/`addAddon` → `cart.addItem(...)` (idempotent); remove → `cart.removeItem(...)`.
- The **plan** is also cart-backed: `loadPlan(slug)` mirrors it into the cart as a
  single `PLAN` item (replacing any previous — one plan at a time), and `plan` is
  a computed reconstructed from that item (`metadata.plan_id` carries the UUID
  used on submit). So "Select plan" adds the plan to the cart.
- `reset()` no longer clears the cart (it's called on unmount); `submitCheckout()`
  clears the cart on any successful checkout. Logout (`UserLayout.logout()`)
  only removes auth keys, never `vbwd_cart`.

**Validation.**
- Unit `plugins/subscription/tests/unit/checkout-store.spec.ts` — rewritten with
  a reactive in-memory cart mock + persistence contract; **19 pass** (incl. "Select
  plan adds to cart" and "new selection replaces the old").
- e2e `vue/tests/e2e/cart-checkout-persistence.spec.ts` — full flow on
  `localhost:8080`: add 2 bundles + 3 add-ons → cart badge **6** (plan + extras) +
  popup lists 6 → invoices → back → still 6 → logout+login → still 6. Passes.
- Full fe-user unit suite green; lint clean.

---

## 2. Subscription plugin documentation

**Request.** Comprehensive docs (human + LLM) for all subscription plugins +
a README in each.

**Delivered.** ~1,370 lines across **three plugins**, written from the actual
code (not assumptions):

| Plugin | Files |
|---|---|
| `vbwd-backend/plugins/subscription` | `README.md` + `docs/{ARCHITECTURE,EXTENDING,LLM_GUIDE}.md` |
| `vbwd-fe-user/plugins/subscription` | same four |
| `vbwd-fe-admin/plugins/subscription-admin` | same four |

- **README** — what it is, the agnostic-core principle, identity table, layout,
  quick start, docs map.
- **ARCHITECTURE** — layers, the core ports/registries it plugs into (line-item
  registry, `ISubscriptionLifecycle`, entitlement/read-model/catalog/deletion
  registries, DI providers), data model, checkout→invoice→activation flow,
  recurring billing & webhooks, scheduler/events, permissions. FE docs cover
  routes, stores, the `CheckoutSource` / `extensionRegistry` integration, and the
  cart-backed checkout.
- **EXTENDING** — concrete recipes (add a line-item type / entitlement / endpoint
  / view / extension block) each with a "before done" checklist.
- **LLM_GUIDE** — compact identity, invariants, "where to change X" file map,
  exact contracts, endpoint/permission tables, gotchas.

---

## 3. Token-bundle delete 500 → guard

**Problem.** `DELETE /api/v1/admin/token-bundles/<id>` returned **500**.

**Root cause.** `IntegrityError: null value in column "bundle_id" of
vbwd_token_bundle_purchase`. Deleting a `TokenBundle` made SQLAlchemy null the
`bundle_id` FK on related purchase rows (`backref="purchases"`, `bundle_id` is
`NOT NULL`). A bundle with purchase history is financial history and must not be
hard-deleted.

**Fix (mirrors the plan-delete guard).**
- `vbwd/repositories/token_bundle_purchase_repository.py` — `count_by_bundle(id)`.
- `vbwd/routes/admin/token_bundles.py` — refuse with **400** "Cannot delete a
  token bundle that has purchases. Deactivate it instead." when purchases exist;
  purchase-free bundles still delete (200). fe-core `ApiClient` surfaces the
  message, so the admin sees it and can use the existing Deactivate action.

**Validation.** TDD `tests/unit/routes/test_admin_token_bundles_delete_guard.py`
(400 with purchases; 200 without); live request on the reported bundle now
returns 400; black + flake8 (max-line 120) clean.

---

## 4. Access Levels checkbox-hides-table bug (fe-admin)

**Problem.** On `/admin/settings/access`, clicking any row checkbox made the
whole table disappear.

**Root cause.** In `vue/src/views/AccessLevels.vue` the bulk-actions bar and the
table were in the **same `v-if`/`v-else-if` chain**: the bulk-actions div was the
`v-if` branch and the table an `v-else-if`. Selecting a row
(`selectedIds.size > 0`) made the bulk-actions branch win and excluded the table.

**Fix.** Made the bulk-actions bar **independent** (renders above the table): the
admin table became its own `v-if`, and the empty-state `<p>` became
`v-else-if="!loading"`.

**Validation.** Unit `vue/tests/unit/views/AccessLevels.spec.ts` (table stays
after checking a row) + e2e `vue/tests/e2e/access-levels-checkbox-keeps-table.spec.ts`
on `localhost:8081`. Lint 0 errors.

---

## 5. CI remediation across the org

`./recipes/ci-status.sh` showed ~10 red repos. Diagnosed and fixed the ones with
clear causes (each pushed to its own `main`):

| Repo(s) | Root cause | Fix | Commit |
|---|---|---|---|
| `vbwd-fe-user`, `vbwd-fe-admin` (+ their plugin CIs) | 7 plugin dirs committed as **gitlinks** with no `.gitmodules` URL → `checkout --submodules` failed | untrack + gitignore (CI clones plugins explicitly) | fe-user `0079ef2`, fe-admin `26c496b` |
| `vbwd-plugin-ghrm` | stale run vs older backend (missing `catalog_read_model`) | re-ran against current `main` | — |
| `vbwd-plugin-subscription` | black drift + DI-provider test relied on ambient DB plugin state | black-format 3 files; conftest enables the plugin **deterministically** | `1485d4f` |
| `vbwd-plugin-taro` | `get_feature_value` now requires `UUID`, taro passed `str` | normalise to UUID | `0f5ed29` |
| `vbwd-fe-user` (`Unit — cms`) | vitest collected the cms plugin's Playwright e2e spec | exclude `plugins/*/tests/e2e/**`; skip plugins with only e2e specs | `2ee1365` |
| `vbwd-backend` (matrix `Unit — cms`) | plugin flake8 linted `docs/` (cms's intentional CSS-string generator) | exclude `docs/` (align with each plugin's own CI) | `68527e4` |

> One recovery: a `git commit` on fe-user accidentally swept in unrelated staged
> `shop` work; caught immediately and `--force-with-lease`-amended out (lease
> verified), shop preserved on disk + re-staged. Nothing lost or published.

`vbwd-ios` remains red — an unrelated, pre-existing iOS workflow misconfiguration
(`working-directory: Packages/VBWDSdk` doesn't exist), out of scope.

---

## 6. Core⇄plugin migration & dependency separation (priority #1)

The remaining red CIs (backend, taro) shared one root: the **Alembic graph was
fragmented across repos** — core and plugin migrations were auto-anchored on
*other plugins'* revisions, so `alembic upgrade heads` only resolved with the
exact plugin set cloned. The user set the governing rule:

> **Core never depends on a plugin. Plugin→plugin dependencies are legitimate but
> must be deliberately declared** in the plugin's config (taro→subscription,
> meinchat→subscription).

Scope chosen: **Core-standalone** (move plugin migrations out of core + declare
deps; leave the `vbwd_001` "all tables" monolith as a legacy baseline).

### 6.1 What was wrong (target couplings)
- `core 20260422_1200_cms_page_slug_full_path ← cms 20260420_1000_style_default` — a **core migration depending on a plugin** (the cms migrations `20260408_1000`/`20260412_1000`/`20260422_1200` operate on `cms_page`/`cms_category` and were misplaced in core).
- `subscription sub_baseline ← meinchat 20260424_1015 ← … ← core 20260422_1200` — wrong-direction cross-plugin chain (subscription is a *base*, not a dependent).
- `taro`/`meinchat` declared `dependencies=[]` despite consuming subscription.

### 6.2 Target graph (implemented + validated)
```
CORE (resolves with ZERO plugins):
  vbwd_001 → 20260404_1500(tax) → 20260406_1800(access) → 20260525_1000_inv_drop_sub_fk
CMS plugin (← core 20260406_1800):  20260408_1000 → 20260412_1000 → 20260420_1000_style_default → 20260422_1200
SUBSCRIPTION (← core 20260406_1800):  sub_baseline   [foundational base]
MEINCHAT (← subscription sub_baseline):  20260424_1000 → 1005 → 1010 → 1015   [declares dep]
TARO:  no migrations; declares dependencies=["subscription"]
```

### 6.3 Changes by repo
| Repo | Change | Commit |
|---|---|---|
| `vbwd-backend` (core) | moved the 3 cms migrations out; re-anchored invoice migration to core head `20260406_1800`; relocated the 2 subscription-coupled core tests to the subscription plugin | `d04a510` |
| `vbwd-plugin-cms` | now owns the 3 cms migrations | `aa570a2` |
| `vbwd-plugin-subscription` | `sub_baseline` re-anchored on core; adopted the relocated route-ownership + migration-wiring tests; conftest `client` fixture | `6ad046e` |
| `vbwd-plugin-meinchat` | `dependencies=["subscription"]`; base re-anchored on `sub_baseline`; CI clones subscription+email | `1969825` |
| `vbwd-plugin-taro` | `dependencies=["subscription"]`; CI clones+enables email→subscription→taro | `e45ca08` |
| `vbwd-backend` (CI) | integration matrix clones `subscription` (ghrm's model FKs to `vbwd_tarif_plan`) | `3fcd873` |

### 6.4 The integration-matrix discovery
Once the core fixes made the **Unit** matrix green, the **Integration** matrix
(long skipped via `needs: unit`) ran for the first time and exposed a
**model-level** coupling: `ghrm/src/models/ghrm_software_package.py` has a
`ForeignKey("vbwd_tarif_plan.id")` (a subscription table), so the full-app boot
needs subscription's models loaded or SQLAlchemy `configure_mappers` fails
(`NoReferencedTableError`). Fix: clone `subscription` in the full-SDK matrix.
Confirmed safe because the boot enables plugins via
`PluginManager.load_persisted_state → plugin.enable()`, which **skips the
dependency check** (only the CLI `enable_plugin` enforces it) — so declared deps
don't cause enable-order failures at boot.

### 6.5 Validation
- Graph (via `ScriptDirectory.walk_revisions`): **core-only OK**, core+cms OK,
  core+subscription OK, +meinchat OK, full OK; meinchat-**without**-subscription
  correctly **fails** (declared dep enforced).
- backend core unit **819 passed**; relocated subscription tests **12 passed**;
  meinchat+taro+subscription units **413 passed**; black/flake8 clean.
- Live CI (final): **backend `Tests` + `Plugin Tests` (unit & integration) green**;
  cms / subscription / meinchat / taro / ghrm plugin CIs green; fe-user / fe-admin
  / fe-core green; the three dependent FE plugin CIs green.

---

## 7. Final state

**Every CI touched this session is green** (only the unrelated `vbwd-ios`
workflow-misconfig remains red). Core now resolves with zero plugins; plugin
dependencies are explicit; the migration graph respects the separation.

### Deferred (user's call)
1. **Declare `ghrm→subscription` formally** — ghrm has the real `vbwd_tarif_plan`
   FK, but ghrm's own CI uses dep-checked `flask plugins enable ghrm` without
   cloning subscription, so declaring it also needs a ghrm-CI tweak. Not done to
   avoid risking ghrm's green CI.
2. **Split the `vbwd_001` monolith** so each plugin's tables come from its own
   baseline (`sub_baseline` is currently a no-op; the monolith still creates all
   plugin tables) — explicitly the out-of-scope "Full untangle" option.
3. **Payment-plugin migration chain** (`c2p2 → … → promptpay ← cms style_default`)
   untouched — those CIs don't run `alembic upgrade`, so it's latent, not breaking.
