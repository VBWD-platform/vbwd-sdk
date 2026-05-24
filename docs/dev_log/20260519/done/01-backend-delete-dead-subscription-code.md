# Sprint 01 — Backend: delete dead / orphaned subscription code

**Phase:** 0 (safe deletion) · **Repo:** `vbwd-backend` · **Effort:** M (~2 dev-days)
**Depends on:** nothing · **Blocks:** 03 (smaller surface first)
**Engineering requirements:** [`_engineering-requirements.md`](../sprints/_engineering-requirements.md) — binding.

## Goal

Delete subscription code in `vbwd-backend/vbwd/` that **no live code reaches**.
Pure subtraction, zero behaviour change. This shrinks the Phase 1 surface and
removes the "edit the wrong copy" hazard.

## Baseline (E1)

Before touching anything, capture the proof that these paths are dead:

```
make test                       # full unit suite — record N passed
docker compose run --rm test pytest -q
grep -rn "subscriptions_bp\|tarif_plans_bp\|addons_bp\|admin_subscriptions_bp\|\
admin_plans_bp\|admin_addons_bp\|admin_categories_bp\|admin_analytics_bp" \
  vbwd/app.py vbwd/routes/__init__.py vbwd/routes/admin/__init__.py
```

The grep must return **no registration** for any blueprint listed in
Deliverables. Record the command + empty output in the sprint PR as the
deadness proof. Record the green test count as the regression baseline.

## Failure / architecture analysis

Report §3.1(c): the 04c "core cleanup" never landed. These files import
cleanly (so the package still loads them) but are never registered with the
app or dispatcher — the plugin serves the live equivalents. They are stale
forks that silently diverge from the plugin.

## In scope — delete

Orphaned route modules (blueprints never registered — verified in Baseline):
- `vbwd/routes/subscriptions.py`, `tarif_plans.py`, `addons.py`
- `vbwd/routes/admin/subscriptions.py`, `plans.py`, `addons.py`, `categories.py`
- `vbwd/routes/admin/analytics.py` (hard-imports `Subscription`; the live
  analytics admin blueprint is the analytics **plugin**'s — confirm in Baseline)

Unregistered handlers (imported by `__init__`, never `dispatcher.register`-ed;
plugin registers its own):
- `vbwd/handlers/checkout_handler.py`
- `vbwd/handlers/subscription_handlers.py`
- `vbwd/handlers/subscription_cancel_handler.py`

Dangling exports to remove (not whole-file deletes):
- `vbwd/handlers/__init__.py` — drop the `CheckoutHandler` import line
- the `routes/__init__.py` / `routes/admin/__init__.py` lines (if any) that
  reference the deleted modules

## Out of scope (deferred to Phase 1)

`subscription_events.py`, `checkout_events.py`, `subscription_service.py`,
`feature_guard.py`, the 5 models, `container.py` DI, the live `user_bp`
`/checkout` + `/addons`. Those are **reachable** — Sprints 03/04.

## TDD plan

This is deletion of unreachable code, so the test is the **whole existing
suite** as a characterisation net (E1):

1. **RED gate (deadness proof):** the Baseline grep proves no live route/handler
   reaches these modules. If any grep hits, that file is *not* dead — remove it
   from scope and escalate (it means more is live than the audit found).
2. Add one focused regression test `tests/unit/test_no_orphan_subscription_blueprints.py`:
   - `test_app_registers_no_core_subscription_blueprint` — build the app, assert
     no `url_map` rule path starts with the deleted modules' prefixes
     *except* those served by the plugin blueprint (assert by blueprint name).
   - `test_core_handlers_init_has_no_subscription_import` — import
     `vbwd.handlers` and assert `CheckoutHandler` is not an attribute.
   Run it RED (before edits the first sub-assertion about the import will be
   red), then delete code, then GREEN.
3. Full `make test` count must equal the Baseline count (no test depended on
   the dead code). A drop ⇒ something was live ⇒ stop.

## SOLID / clean-code notes

- **S/O:** removing dead alternative implementations restores a single
  responsible owner (the plugin) per concern — no more two-headed routes.
- **Clean code:** net negative diff; no new abstractions. The regression test
  is the only addition and it is generic (asserts *core* has no subscription
  blueprint), so it keeps protecting the oracle after Phase 1.

## Acceptance criteria

- All listed files deleted; dangling imports/exports removed.
- New regression test green; full suite count == Baseline count.
- `make lint` (black/flake8/mypy via `bin/pre-commit-check.sh --lint`) green.
- App boots (`make up`) and the live subscription flow (served by the plugin)
  is unaffected — smoke: `POST /api/v1/.../checkout` still 2xx via plugin.

### E3 oracle slice made true

"zero **unregistered** subscription route modules in core" — partial: core no
longer *contains* dead subscription routes (full route-registration oracle
completed in Sprint 04).

## Risks

- A grep miss → a "dead" file is actually imported on a hot path. Mitigation:
  the Baseline grep + the full-suite count + app boot smoke. If the suite
  count drops, `git revert` the single deletion commit (atomic per file group).
- Demo seeders (`vbwd/testing/`, `vbwd/cli/`) may import a deleted symbol —
  in scope to fix the import (point at plugin or remove the seed line); covered
  by `make test` since seeders are exercised by integration fixtures.

## Effort

M — ~2 dev-days incl. Baseline capture, regression test, lint, smoke.
