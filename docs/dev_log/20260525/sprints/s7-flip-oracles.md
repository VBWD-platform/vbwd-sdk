# S7 — Flip the agnosticism oracles + decision log

**Risk:** low. **Depends on S5** (flip the "models stay in core" oracle only once
they've actually moved). The programme exit gate.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **no overengineering** —
[`_engineering-requirements.md`](_engineering-requirements.md). Gate: all three
oracles + `bin/pre-commit-check.sh --full` green on every touched repo — this
slice *is* the quality gate for the whole sprint.

## Backend — `tests/unit/test_subscription_agnostic_backend.py`
- **Delete** `test_subscription_models_stay_in_core_per_decision_A`.
- **Add:** the 5 model modules are absent from `vbwd.models` (import raises);
  `vbwd/models/__init__` exports none of the 5; the 6 plugins
  (stripe/paypal/yookassa/taro/analytics/ghrm) import no `vbwd.models.{subscription,
  tarif_plan,addon,addon_subscription,tarif_plan_category}`.
- **Add:** core `invoice` has no `subscription_id`/`tarif_plan_id` (S4);
  payment plugins import no subscription model (S1); recurring determination
  goes through the line-item registry.

## FE oracles
- `vbwd-fe-admin` + `vbwd-fe-user` `subscription-agnostic.spec.ts`: assert no
  `subscription_*` invoice field in core (S6).

## Decision log — `../../20260519/reports/02-phase0-outcome-and-locked-decisions.md`
- **A → superseded by Sprint 11** (models now in the plugin).
- **R3 → resolved** (the 6 plugins use ports/registry, not the models).
- **R4 → resolved** (core invoice no longer FKs subscription/plan).
- Update report 06 §5 residual table → closed.

## Acceptance
All three oracles green encoding the **fully** agnostic contract; full suites
green across backend + plugin repos. Then Sprint 11 is done.

## (Stretch) S8 — permission namespace
Optional: rename core token/invoice permissions out of `subscription.*`
(`token.*`, `invoice.*`) + seed/data migration. Cosmetic; ship separately.
