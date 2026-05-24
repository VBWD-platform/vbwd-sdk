# Sprint 02 — Frontend: delete dead duplicate views / stores

**Phase:** 0 (safe deletion) · **Repos:** `vbwd-fe-user`, `vbwd-fe-admin`
**Effort:** M (~2 dev-days) · **Depends on:** nothing · **Blocks:** 07, 08
**Engineering requirements:** [`_engineering-requirements.md`](../sprints/_engineering-requirements.md) — binding.

## Goal

Delete the ~16 dead duplicate subscription views/stores/components in
`vue/src/` of both frontends. The plugins own the routed copies; the core
copies are unreachable and **already diverged** (a correctness hazard).

## Baseline (E1)

Prove each file is unreachable before deleting it:

- `vbwd-fe-user`: `vue/src/router/index.ts` registers **none** of the dead
  views; the plugin `index.ts` registers `/dashboard/plans`, `/subscription`,
  `/add-ons`, `/checkout/*` → plugin copies. Grep core for imports of each
  candidate; expect hits only from *other dead candidates* (closed cluster).
- `vbwd-fe-admin`: `vue/src/router/index.ts` registers **zero**
  subscription/plan/addon/category routes; plugin `index.ts:12-77` registers
  all 12 → plugin copies. Core `Plans.vue`'s only importers are
  `CategoriesTab.vue` → `categoryAdmin.ts` (a closed dead cluster).

Record the import-graph grep proving each deleted file's only referrers are
other files in the same delete set (or nothing). Run `npm run test` +
`npm run build` (in the container, never host npm on fe-core) and record green
counts as the regression baseline.

## In scope — delete

**fe-user `vue/src/`:**
- views: `Plans.vue`, `Subscription.vue`, `AddOns.vue`, `AddonDetail.vue`,
  `AddonInfoView.vue`, `Checkout.vue`, `PlanDetailView.vue`,
  `TarifPlanDetail.vue`
- stores: `subscription.ts`, `plans.ts`, `checkout.ts`
- component: `components/checkout/BillingAddressBlock.vue` (+ any sibling
  duplicate of a plugin `components/checkout/*` confirmed dead)
- barrel: remove the `useSubscriptionStore` / `usePlansStore` /
  `Subscription` / `Usage` / `Plan` re-exports from `stores/index.ts`

**fe-admin `vue/src/`:**
- views: `Plans.vue`, `PlanForm.vue`, `Subscriptions.vue`,
  `SubscriptionDetails.vue`, `SubscriptionCreate.vue`, `AddOns.vue`,
  `AddonForm.vue`, `CategoryForm.vue`
- stores: `planAdmin.ts`, `addons.ts`, `categoryAdmin.ts`
- component: `components/CategoriesTab.vue`
- barrel: remove `usePlanAdminStore` / `AdminPlan` / `CreatePlanData` from
  `stores/index.ts`

## Out of scope (Phase 1)

`stores/subscriptions.ts` (fe-admin) — duplicated **and live** via
`UserEdit.vue:708` → Sprint 08. fe-user hardcoded nav/router/i18n → Sprint 07.
`stores/invoices.ts` (both) — generic, kept.

## TDD plan

Deletion of unreachable UI; the suite + typecheck + build are the net:

1. **RED (deadness proof):** Baseline import-graph grep. Any deleted file
   imported by a *live* file ⇒ out of scope, escalate.
2. Add a guard spec per repo,
   `vue/tests/unit/no-dead-subscription-core.spec.ts`:
   - asserts `vue/src/router/index.ts` exposes no route component path under
     the deleted view filenames;
   - asserts `vue/src/stores/index.ts` no longer exports the removed symbols.
   Run RED (export assertion fails pre-delete), delete, GREEN.
3. `vue-tsc` / `npm run build` must succeed — a dangling import anywhere is a
   compile error and proves a missed live reference. `npm run test` count ==
   Baseline.
4. Existing Playwright e2e for the live (plugin) subscription screens must
   stay green — they exercise the plugin copies, unaffected.

## SOLID / clean-code notes

- **S:** one component per screen again; ends the silent core/plugin fork.
- **DRY:** removes the worst DRY violation in the frontends (whole-file
  duplicates that already diverged — exactly the >2-copies promotion failure
  §4 of the inherited reqs warns about).
- The guard specs are generic agnosticism assertions; they remain valuable
  after Phase 1 (regression fence).

## Acceptance criteria

- All listed files/exports removed in both repos.
- Guard specs green; `npm run test` == Baseline; `vue-tsc` + `npm run build`
  clean; `npm run lint` (project-wide, per CI lesson) clean.
- Live subscription screens (plugin-served) unchanged — Playwright e2e green.

### E3 oracle slice made true

"zero dead duplicate subscription views/stores in fe-user/fe-admin core" — the
divergent-duplicate hazard is eliminated; hardcoded wiring + i18n remain for
Sprints 07/08.

## Risks

- fe-admin core `Subscriptions.vue` / `CategoryForm.vue` are still byte-identical
  to plugin copies (not yet diverged) — safe to delete, but double-check no
  test imports the **core** path. Mitigation: `vue-tsc` + grep.
- Deleting a store still imported by a *live* core view (e.g. an overlooked
  reference) → compile error caught by build. Per-file atomic commits → cheap
  `git revert`.

## Effort

M — ~2 dev-days across both repos (incl. container test/build cycles).
