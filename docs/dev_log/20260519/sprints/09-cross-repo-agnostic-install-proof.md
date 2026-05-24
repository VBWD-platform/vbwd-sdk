# Sprint 09 — Cross-repo agnostic-install proof + CI exit gate

**Phase:** 2 (proof) · **Repos:** all four + CI
**Effort:** M (~2 dev-days) · **Depends on:** 01–08 (all merged)
**Blocks:** programme sign-off · **Engineering requirements:** [`_engineering-requirements.md`](./_engineering-requirements.md) — binding (esp. **E3**).

## Goal

Turn the **agnosticism oracle (E3)** into an automated, falsifiable CI gate so
the extraction can never silently regress again — the exact failure mode of
the 2026-03-27 set (recorded "Done", absent from `main`, undetected ~7 weeks).
This sprint writes no feature code; it writes the **proof harness**.

## The oracle (must all hold with the subscription plugins DISABLED)

1. **Backend schema:** a fresh DB migrated with the subscription plugin
   disabled has **zero** `vbwd_subscription*`, `vbwd_tarif_plan*`,
   `vbwd_addon*` tables.
2. **Backend imports:** `import vbwd.models.subscription` (and the other 4)
   ⇒ `ModuleNotFoundError`; no `vbwd.*` module transitively imports
   subscription (clean `sys.modules` after importing the core app).
3. **Backend routes/DI:** the app registers no subscription route; the core
   container exposes no subscription factory; a representative non-subscription
   flow (e.g. a booking/shop checkout, token purchase) works end-to-end.
4. **fe-user:** built bundle for a plugin-disabled config has no subscription
   route, no Subscription nav, no `subscription.*` permission evaluated, and
   the rendered i18n bundles contain no `subscription`/`tarif`/`plan` key.
5. **fe-admin:** same — no subscription views/nav/titles; core locale bundles
   subscription-free; UserEdit/UserDetails/AccessLevels clean.
6. **fe-core:** the published `vbwd-view-component` public surface contains
   zero subscription identifiers.
7. **Plugin enabled (regression of the move):** with the plugins enabled,
   the full subscription experience is byte-/behaviour-identical to the
   pre-programme Baselines (the aggregate of Sprints 01–08 char tests).

## TDD plan

This sprint is tests-only; the "RED" is that the oracle is currently
unenforced (and items would have been red mid-programme).

1. **Backend oracle test module**
   `tests/integration/test_subscription_agnostic_install.py`:
   - parametrised over plugin **disabled/enabled**;
   - disabled: assert (1)(2)(3); enabled: assert the schema + a smoke of the
     plugin's checkout/addon/feature path (re-using Sprints 03–05 char fixtures
     — DRY, don't duplicate assertions).
2. **fe-user / fe-admin oracle specs** (Vitest + a Playwright run against a
   plugin-disabled build): assert (4)/(5). Add a tiny build-config fixture
   that disables the plugin (mirrors how other plugin-toggle tests build).
3. **fe-core guard** already added in Sprint 06 (`no-domain-words.spec.ts`) —
   here it is wired into the **shared** CI gate so a future fe-core change
   re-introducing subscription fails CI.
4. **CI exit gate:** add a `subscription-agnostic` job to each repo's
   pipeline (per `feedback_ci_precommit_lessons.md`: correct Vitest
   plugin-id filter, project-wide ESLint, mypy excludes tests, graceful
   skip rules, all plugins installed for vue-tsc). The job runs the oracle
   module for that repo. **A red oracle blocks merge.**
5. **Anti-regression doc check:** a lightweight test asserting every
   `20260519/sprints/NN-*.md` marked Done has its "E3 oracle slice" line and
   that the union of slices == the full oracle (prevents a future "Done"
   that doesn't actually satisfy its slice — the 04c failure mode).

## SOLID / clean-code notes

- **DRY:** the oracle reuses Sprints 01–08 Baseline/char fixtures; it
  aggregates, it does not re-implement assertions.
- **OCP:** the gate keys on *generic* invariants ("core defines no
  subscription module/route/i18n"), so it equally protects the *next*
  extraction (booking/shop) without modification.
- **SRP:** one job per repo, one responsibility — assert that repo's slice.
- Clean code: the parametrised disabled/enabled test reads as the spec of the
  architecture itself.

## Acceptance criteria

- Oracle module green: **disabled** ⇒ items 1–6 hold; **enabled** ⇒ item 7
  (full Baseline parity) holds.
- `subscription-agnostic` CI job added to all four repos and **required** for
  merge; deliberately re-introducing a core subscription import/route/i18n in
  a scratch branch turns the job red (proof the gate bites).
- Doc-honesty check green (every Done sprint's oracle slice present;
  slices ∪ == oracle).
- `bin/pre-commit-check.sh --full` green on all touched repos.

### E3 oracle slice made true

**The entire E3 oracle**, and it is now machine-enforced in CI — the
programme's exit gate. Subscription is, provably, a plugin peer of
shop/booking/ghrm.

## Risks

- A flaky plugin-disabled frontend build harness. Mitigation: reuse the
  existing plugin-toggle build fixture pattern already in the repos; keep the
  Playwright slice minimal (presence/absence assertions, not full journeys —
  journeys are covered by the per-sprint Baselines).
- Oracle too strict / false positives on legitimate generic words (e.g. a
  generic `plan` in an unrelated context). Mitigation: assert on
  *identifiers/keys/routes/tables*, not free-text greps; allow-list reviewed
  in PR.

## Effort

M — ~2 dev-days (no feature code; harness + CI wiring + reuse of existing
fixtures).

---

## Programme close-out

When 09 is green: update each sprint doc Status to **IMPLEMENTED & VERIFIED**
with the green oracle command output, and correct
`docs/dev_log/2026/03/20260327/done/04c-core-cleanup.md` /`reports/03` to
reflect that core cleanup actually landed on `main` on this programme — not in
the 2026-03 set. Honest dev log is part of "Done" (README cross-cutting rule).
