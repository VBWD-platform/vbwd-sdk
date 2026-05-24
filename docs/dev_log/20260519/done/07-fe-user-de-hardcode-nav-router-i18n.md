# Sprint 07 — fe-user: de-hardcode subscription nav / i18n / Dashboard gating

**Phase:** 1 · **Repos:** `vbwd-fe-user`, `vbwd-fe-user/plugins/subscription`
**Effort:** S–M (~1.5–2 dev-days) — *shrunk by decision D4*
**Depends on:** 02, 06 · **Blocks:** 09
**Engineering requirements:** [`_engineering-requirements.md`](../sprints/_engineering-requirements.md) — binding (E6).
**Re-baselined by:** [`../reports/02-phase0-outcome-and-locked-decisions.md`](../reports/02-phase0-outcome-and-locked-decisions.md) (read it first).

## Scope correction (read before anything)

The original Sprint 07 also moved invoices/tokens routes into the plugin and
treated `stores/checkout.ts` as a dead duplicate. **Both were wrong:**

- **Decision D4:** `/dashboard/invoice*`, `/dashboard/tokens*`, their
  views/stores and permission checks are **core functionality and stay in
  core**. They are *not* touched by this sprint. The
  `subscription.invoices.*` / `subscription.tokens.*` permission strings are
  treated as **core permission keys** (a namespace rename is explicitly out
  of scope).
- **Phase 0 finding:** `stores/checkout.ts` and `components/checkout/*` are
  **live, generic, shared** core building blocks (used by `plugins/checkout`,
  `plugins/booking`, `plugins/subscription` via `@/`). Multiple plugins
  consuming a generic core capability is *legitimate* (category b) — **not a
  violation, not in scope.**

What actually remains for this sprint: three genuinely subscription-specific
hardcodings in fe-user core.

## Goal

Remove the three subscription-specific couplings from fe-user core so that
disabling the subscription plugin leaves no subscription trace — while
**leaving invoices/tokens and the shared checkout primitives untouched**.

1. `layouts/UserLayout.vue:165-202,425,448` — hardcoded "Subscription" nav
   group; `toggleGroup`'s type union hardwires `'subscription'`. An agnostic
   `userNavRegistry` (`vue/src/plugins/userNavRegistry.ts`) already exists and
   is used by other plugins; the subscription group bypasses it.
2. `i18n/locales/{en,de,zh}.json` — `subscription.*` / `nav.subscription`
   trees; the plugin ships none.
3. `views/Dashboard.vue:73,110` — hardcoded `subscription.*` permission
   literals gating dashboard cards.

> The plugin's own screens (`/dashboard/subscription`, `/plans`, `/add-ons`,
> `/checkout/*`) are already plugin-registered routes — **not** in scope;
> only the *core-side* hardcodings above are.

## Baseline (E1)

Playwright e2e char specs, GREEN on `main` before any change:
- nav: an entitled user sees the "Subscription" group + sub-links;
- i18n: subscription menu/labels render en/de/zh strings;
- dashboard: subscription-gated cards show/hide per permission;
- **regression guard:** invoices + tokens nav/routes/screens render exactly
  as today (proves D4 — they are untouched).

Unchanged after the move (E2): identical user-visible nav, strings, cards;
invoices/tokens **byte-identical**.

## TDD plan (RED → GREEN)

1. **Nav group via `userNavRegistry` (E6):**
   - **RED:** plugin spec `subscription-nav.spec.ts` — after the plugin
     `install(sdk)`, `userNavRegistry` contains the Subscription group; red
     (plugin registers no nav yet).
   - Plugin registers its nav group through `userNavRegistry`/`sdk.addNavGroup`.
     Delete the hardcoded block from `UserLayout.vue`; generalise
     `toggleGroup(groupName: string)` and drop `expandedGroups.subscription`.
   - Baseline nav e2e GREEN unchanged; **invoices/tokens nav still rendered by
     core** (Baseline regression-guard e2e GREEN — they are core nav items,
     not part of the moved group).
   - Guard spec: `UserLayout.vue` source contains no `subscription` literal.
2. **i18n into the plugin:**
   - Move only the `subscription.*` / `nav.subscription` keys out of core
     `locales/{en,de,zh}.json` into the plugin via
     `sdk.addTranslations(...)`. **Leave `invoices`/`tokens` keys in core**
     (D4 — core features keep core i18n).
   - Guard spec: rendered core i18n bundle has no `subscription`/`tarif`/
     `plan` key; `nav.invoices`/token keys **still present** in core.
     Baseline i18n e2e GREEN unchanged.
3. **Dashboard gating via capability, not hardcoded string:**
   - Replace the `subscription.*` literals on the *subscription* cards in
     `Dashboard.vue` with a generic capability lookup the plugin contributes
     (same pattern as the nav registry). The **invoices/tokens cards keep
     their core permission checks** (D4).
   - Card visibility unchanged for entitled users (Baseline e2e); the
     subscription card simply doesn't exist when the plugin is disabled (new
     plugin-disabled e2e).
4. **Plugin-disabled e2e (new):** subscription plugin off ⇒ no Subscription
   nav, no subscription i18n in the DOM, no subscription dashboard card, **but
   invoices + tokens nav/routes/cards still fully work** (the D4 proof).

## SOLID / clean-code notes

- **OCP (E6):** subscription nav/i18n/gating are *registered*, not edited
  into core. Core stops naming subscription.
- **SRP:** `UserLayout` lays out whatever the nav registry yields; invoices/
  tokens remain first-class core nav (correctly, per D4).
- **Liskov (E2):** Baseline e2e (incl. the invoices/tokens regression guard)
  is the substitution proof; none may be edited to pass.
- Clean code: `toggleGroup(groupName: string)` — no feature literal in a core
  layout signature.

## Acceptance criteria

- `UserLayout.vue`, core `locales/{en,de,zh}.json`, the subscription cards in
  `Dashboard.vue` contain **zero** `subscription`/`tarif`/`plan` literals.
- **Invoices & tokens unchanged**: their routes, nav, views, stores,
  permission strings and i18n keys are byte-identical to pre-sprint
  (regression-guard e2e GREEN).
- Plugin registers nav + i18n; all Baseline e2e GREEN unchanged; new
  plugin-disabled e2e GREEN.
- Consumes the Sprint 06 fe-core pin; `npm run lint`, `vue-tsc` (no **new**
  errors vs the Phase-0 pre-existing baseline), `npm run test`, Playwright
  green (in-container; no host npm on fe-core).

### E3 oracle slice made true

"fe-user core registers no subscription nav, renders no subscription i18n,
evaluates no `subscription.*` capability when the plugin is disabled — while
invoices/tokens remain fully core."

## Risks

- Touching `Dashboard.vue` could disturb the invoices/tokens cards.
  Mitigation: the Baseline regression-guard e2e asserts those cards
  unchanged; only the subscription card's gate is rewritten.
- A `subscription.*` literal elsewhere in `vue/src`. Mitigation: the guard
  spec greps all of `vue/src`, excluding the legitimately-core invoices/
  tokens permission keys via an explicit allow-list reviewed in the PR.

## Effort

S–M — ~1.5–2 dev-days (down from M–L; D4 removed the route-relocation and
the §2 finding removed the false "checkout duplicate" work).
