# Sprint 08 — fe-admin: resolve subscription couplings + plugin→core `@/` imports

**Phase:** 1 · **Repos:** `vbwd-fe-admin`, `vbwd-fe-admin/plugins/subscription-admin`
**Effort:** L (~3–4 dev-days) ⚠ · **Depends on:** 02, 06 · **Blocks:** 09
**Engineering requirements:** [`_engineering-requirements.md`](../sprints/_engineering-requirements.md) — binding (E6).
**Re-baselined by:** [`../reports/02-phase0-outcome-and-locked-decisions.md`](../reports/02-phase0-outcome-and-locked-decisions.md) (read it first).

> **STATUS: ✅ DONE (P1 + P2), e2e-verified on :8081.** Outcome recorded in
> report **§3m** (P1) / **§3j** (P2). Core `stores/subscriptions.ts` deleted;
> Subscriptions/Add-ons tabs, UserDetails summary, AccessLevels Linked-Plan
> column + form field all plugin-contributed via the extension registry.
> Decision-locked residuals (D4 invoice metadata; `/deletion-info`
> `subscription_count`) documented in §3m. fe-admin agnosticism oracle
> (`vue/tests/unit/subscription-agnostic.spec.ts`) green — see §3n.

## Scope correction (read before anything)

The original Sprint 08 said "delete ~13 dead files". **Wrong.** Phase 0
proved:
- Only **8 per-view core copies** were dead — already deleted in Sprint 02.
- `vue/src/stores/{planAdmin,addons,categoryAdmin}.ts` and
  `vue/src/components/CategoriesTab.vue` are **live**: the
  `subscription-admin` plugin imports them through the core `@/` alias
  (`@/stores/planAdmin`, `@/components/CategoriesTab`, …). They were restored.

So fe-admin has **two distinct problems**, both addressed here:

- **P1 — subscription contamination of core user/access domain** (real
  leftover): core user views/stores/layout know about subscription.
- **P2 — plugin→core `@/` import inversion** (the corrected architectural
  finding, report 02 §2): `plugins/subscription-admin` reaches into core
  internals (`@/stores/planAdmin`, `@/stores/addons`,
  `@/stores/categoryAdmin`, `@/components/CategoriesTab`) instead of owning
  its domain code. The plugin even *ships its own* `src/stores/planAdmin.ts`
  yet its views import the **core** one via `@/` — a latent correctness trap.

## Goal

After this sprint: core fe-admin contains zero subscription literals in
user/access views, layout and i18n; **and** the subscription-admin plugin no
longer imports core domain stores/components through `@/` — the dependency
arrow points plugin→(its own code), not plugin→core-internals.

### P1 couplings
1. `stores/subscriptions.ts` — imported by live core `views/UserEdit.vue:708`.
2. `UserEdit.vue:58-79,421-504,603-691` — hardcoded "Subscriptions"/"Add-ons"
   tabs with fetch/pagination in a core user view.
3. `UserDetails.vue:89-112`, `stores/users.ts:18-32`, `Users.vue:523-547`,
   `UserCreate.vue:85` — core user model/views embed `subscription_*`.
4. `AccessLevels.vue:169,201-203` — hardcoded "Linked Plan" **column** while
   the *form field* is already plugin-driven (`accessLevelFormFields`).
5. `layouts/AdminTopbar.vue:22-23` — hardcodes plugin route titles.
6. core `i18n/locales/*.json` (8 locales) — `subscriptions/plans/addOns`,
   `nav.tarifs/plans/...`; plugin ships no i18n.

### P2 coupling
7. `plugins/subscription-admin/src/views/*.vue` + `components/CategoriesTab.vue`
   import `@/stores/{planAdmin,addons,categoryAdmin}` and
   `@/components/CategoriesTab` (core internals).

## Open question (resolve at kickoff, BEFORE coding P2)

**How to invert P2** — pick one, record in the PR before touching code:

- **(a) Plugin owns its domain code (recommended).** The plugin already has
  `src/stores/planAdmin.ts` etc.; repoint every plugin `@/stores/*` /
  `@/components/CategoriesTab` import to the plugin-local copies, then **delete
  the now-unreferenced core `vue/src/stores/{planAdmin,addons,categoryAdmin}.ts`
  + `components/CategoriesTab.vue`** (they become truly dead once the plugin
  stops importing them — re-run the E1 RED-gate to confirm zero importers).
  Net: plugin self-contained; core loses subscription stores entirely.
- **(b) Core publishes a generic, un-named extension API.** Only if a
  *non-subscription* admin plugin also needs these. No evidence it does →
  default to (a). Do **not** keep the `@/`-into-core-internals status quo.

Decision changes only P2's mechanics, not P1 or the acceptance oracle.

## Baseline (E1)

Playwright + Vitest char specs GREEN on `main`:
- UserEdit Subscriptions/Add-ons tabs + data + pagination;
- UserDetails plan/status/expiry block; Users bulk-delete subscription count;
- AccessLevels list "Linked Plan" column + `linked_plan_slug`;
- topbar titles for `/admin/plans`, `/admin/subscriptions`;
- the plugin's plan/subscription/addon screens (served by plugin routes)
  render correctly **before and after** the P2 repoint (the substitution
  proof for the import inversion).

Unchanged after the moves (E2).

## TDD plan (RED → GREEN)

**P1**
1. **`userEditTabs` registry (E6)** — model on the existing
   `accessLevelFormFields`/`extensionRegistry` pattern. RED: plugin spec —
   after `activate()`, registry yields "Subscriptions"+"Add-ons" tab
   descriptors. Move tab markup + fetch/pagination + the `subscriptions` store
   usage into plugin tab components; core `UserEdit.vue` renders core tabs +
   `extensionRegistry.getUserEditTabs()`. Delete core `stores/subscriptions.ts`
   (its only live importer was `UserEdit`). Baseline UserEdit e2e GREEN
   unchanged.
2. **De-contaminate `UserDetail`** — core type loses `subscription_*`; a
   plugin "user summary" slot renders plan/status. Bulk-delete subscription
   count line becomes a plugin-contributed generic "dependency warning"
   fragment. RED core type guard + plugin slot spec; Baseline e2e GREEN.
3. **AccessLevels column via the existing field registry** — the "Linked
   Plan" *column* becomes a plugin contribution alongside the already-plugin
   *field*. RED plugin column spec; core `AccessLevels.vue` loses
   `linked_plan_slug`/"Linked Plan" literals. Baseline e2e GREEN.
4. **Topbar titles from route meta** — plugin registers `meta.title` with its
   routes; delete the hardcoded map entries in `AdminTopbar.vue`. Baseline
   title e2e GREEN.
5. **i18n into the plugin** — move `subscriptions/plans/addOns`,
   `nav.tarifs/plans/addOns/subscriptions` out of all 8 core locale files into
   the plugin via `sdk.addTranslations`. Core-bundle guard: none remain.
   Baseline rendering e2e GREEN.

**P2 (after the kickoff decision; default = option a)**
6. Repoint every `plugins/subscription-admin` import from
   `@/stores/{planAdmin,addons,categoryAdmin}` and
   `@/components/CategoriesTab` to the plugin-local equivalents (the plugin
   already ships `src/stores/planAdmin.ts` etc.). RED: a plugin guard spec
   asserting no `@/stores/(planAdmin|addons|categoryAdmin)` /
   `@/components/CategoriesTab` import remains in the plugin. GREEN after
   repoint.
7. **E1 RED-gate before deletion:** re-grep — core
   `vue/src/stores/{planAdmin,addons,categoryAdmin}.ts` +
   `components/CategoriesTab.vue` now have **zero** importers. Only then
   delete them (+ the `usePlanAdminStore`/`AdminPlan`/`CreatePlanData` barrel
   exports). `vue-tsc` must show no new errors (a dangling import ⇒ a missed
   importer ⇒ stop).
8. Baseline plugin-screen e2e GREEN unchanged (the plugin renders identically
   off its own stores/components — the Liskov/E2 proof for the inversion).

**Plugin-disabled e2e (new):** subscription-admin off ⇒ UserEdit has no
sub/addon tabs, UserDetails no plan block, AccessLevels no Linked-Plan column,
no subscription nav/titles/i18n, bulk-delete omits the subscription line — no
errors anywhere.

**e2e relocation:** move the ~11 `admin-subscription*/plan*` specs from
`vbwd-fe-admin/vue/tests/e2e/` into `plugins/subscription-admin/tests/e2e/`
(plugin-id Vitest/Playwright filter per the CI lesson).

## SOLID / clean-code notes

- **DIP (P2):** the import arrow is inverted — the plugin owns its domain
  stores/components; core no longer hosts subscription-admin internals for a
  plugin to reach into. This is the core architectural payoff of the sprint.
- **OCP (P1, E6):** every core coupling becomes a registered contribution
  (`userEditTabs`, user-summary slot, access-level column, route-meta titles,
  translations) — booking/shop reuse the same generic registries.
- **SRP:** `UserEdit`/`UserDetails`/`AccessLevels`/`AdminTopbar` render core
  concerns + generic extension areas; subscription specifics live in the
  plugin.
- **Liskov (E2):** every Baseline char/e2e spec (incl. the plugin-screen
  parity for the P2 repoint) is the substitution proof; none may be edited.
- Clean code: full names (`userEditTabs`, `accessLevelListColumns`); zero
  feature literals in core layouts/types/i18n.

## Acceptance criteria

- core `UserEdit/UserDetails/Users/UserCreate/AccessLevels/AdminTopbar` + 8
  locale files: **zero** subscription literals (guard specs green).
- `stores/subscriptions.ts` deleted; and (option a) core
  `stores/{planAdmin,addons,categoryAdmin}.ts` + `components/CategoriesTab.vue`
  deleted **only after** the E1 RED-gate proves zero importers.
- `plugins/subscription-admin` has **no** `@/stores/(planAdmin|addons|
  categoryAdmin)` / `@/components/CategoriesTab` import (P2 guard green).
- All Baseline char/e2e GREEN unchanged (incl. plugin-screen parity). New
  plugin-disabled e2e GREEN. e2e specs relocated + green in plugin CI.
- Consumes Sprint 06 fe-core pin; `npm run lint`, `vue-tsc` (no **new**
  errors vs the Phase-0 pre-existing baseline), Vitest, Playwright green.

### E3 oracle slice made true

"fe-admin core has zero subscription literals in user/access views/layout/
i18n; the subscription-admin plugin imports no core domain internals via `@/`;
disabling the plugin yields a clean subscription-free admin."

## Risks ⚠

- Three new generic registries (tabs, user-summary, list-column) — over-
  engineering risk. Mitigation: copy the existing `accessLevelFormFields`
  shape exactly; one method each (ISP).
- `UserEdit` is large and central. Mitigation: comprehensive Baseline e2e +
  Vitest char specs **before** edits (E1); per-coupling atomic commits.
- P2 deletion lands on a missed importer. Mitigation: the mandatory E1
  RED-gate re-grep + `vue-tsc` before the core-file deletion — exactly the
  check that caught the audit error in Phase 0.

## Effort

L — ~3–4 dev-days (P1 ≈ original; P2 adds the import inversion + a guarded
deletion, but removes the bogus "delete 13 dead files" work).
