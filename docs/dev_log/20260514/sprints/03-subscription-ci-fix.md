# Sprint 03 — `vbwd-plugin-subscription` CI Recovery

**Status:** PLANNED — 2026-05-14
**Repo:** `VBWD-platform/vbwd-plugin-subscription` (cloned at `vbwd-backend/plugins/subscription/`)
**Last failed run:** [25628978013 — 2026-05-10](https://github.com/VBWD-platform/vbwd-plugin-subscription/actions/runs/25628978013) — commit "feat: self-heal checkout-confirmation CMS page on app boot".
**Engineering requirements:** [`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md) — binding.
**Sister sprints:** [02 — shop](./02-shop-ci-fix.md) (identical root cause), [04 — shared workflow guard](./04-shared-ci-pytest-no-collect-guard.md).

---

## 1. Failure analysis (root cause, not symptom)

The CI job `CI — subscription` failed at step **"Run integration tests"** with exit code `5`. Decoded log excerpt:

```
============================= test session starts ==============================
platform linux -- Python 3.11.15, pytest-7.4.3
configfile: pytest.ini
plugins: asyncio-0.23.2, flask-1.3.0, mock-3.12.0, …, xdist-3.5.0
collecting ... collected 0 items
------------ generated xml file: /app/test-results/integration.xml -------------
============================ no tests ran in 0.10s =============================
##[error]Process completed with exit code 5.
```

Same pattern as sprint 02:

- The workflow guards integration with `if [ -d "plugins/subscription/tests/integration" ]; then …`.
- `ls plugins/subscription/tests/integration/` → only `__init__.py`. No `test_*.py`.
- pytest collects 0 items → exit 5 → `bash -e` fails the job.

The *unit* layer is healthy: `tests/unit/test_line_item_handler.py` and `tests/unit/test_access_level_handler.py` are present and (per the run log) collected and passed. So this sprint is purely about giving the integration step at least one real test to chew on.

**Why this matters more than for shop:** the subscription plugin owns billing-critical state machines (active → past_due → canceled, addon attach/detach, scheduler-driven renewal). A smoke integration test now also reduces the long-tail risk that an addon model or repository refactor silently breaks DB persistence. The TDD smoke test added here is genuine coverage, not a placeholder.

## 2. Scope

**In:**
- One TDD-built integration smoke test under `tests/integration/` covering the highest-value happy path: tarif-plan create → tarif-plan list via repository, with the `db` fixture.
- A `tests/integration/conftest.py` (or import re-export from the existing top-level `tests/conftest.py`) if the integration dir doesn't already inherit fixtures.

**Out:**
- New unit tests beyond what's needed by the smoke test.
- Production code changes under `subscription/`.
- Workflow YAML changes (sprint 04).
- Anything touching `subscription/scheduler.py` or the addon-attach state machine — those have unit coverage already.

## 3. TDD checkpoints (red → green → refactor)

### Pre-flight: capture baseline

```bash
cd vbwd-backend
./bin/pre-commit-check.sh --plugin subscription --quick
```

Expected exit `0` (lint + unit are green per the CI log). If anything is red, log it as a follow-up — don't bundle.

### TDD cycle 1 — `tests/integration/test_tarif_plan_repository_smoke.py`

**Red:** Author the test first. Run it. Watch it fail with a *meaningful* error (not "collected 0 items").

```python
# plugins/subscription/tests/integration/test_tarif_plan_repository_smoke.py
"""Smoke integration test: prove subscription's tarif_plan repository round-trips
through real PostgreSQL. Defends the SQLAlchemy mapper, the migration, and the
conftest wiring against silent regressions.
"""
import pytest
from decimal import Decimal

from plugins.subscription.subscription.models.tarif_plan import TarifPlan
from plugins.subscription.subscription.repositories.tarif_plan_repository import (
    TarifPlanRepository,
)


@pytest.mark.integration
def test_tarif_plan_create_then_list_round_trips_through_real_db(db_session):
    repository = TarifPlanRepository(db_session)
    created_plan = repository.create(
        TarifPlan(
            name="Smoke Plan",
            slug="smoke-plan",
            price=Decimal("19.99"),
            currency="EUR",
            interval="month",
            is_active=True,
        )
    )
    db_session.commit()

    fetched_plans = repository.list_active()

    assert any(plan.id == created_plan.id for plan in fetched_plans)
    assert any(plan.slug == "smoke-plan" for plan in fetched_plans)
```

**Why this test:** `list_active` is hit on every dashboard page load — the cheapest, highest-leverage assertion that proves the integration harness, the model mapping, and the repository's filter are all wired correctly.

**Adapt to reality:** if the actual model exposes the field as `monthly_price` or the method is `list_published`, **update the test to match the existing API** before invoking — do not invent. Read `subscription/models/tarif_plan.py` and `subscription/repositories/tarif_plan_repository.py` first.

**Green:**

```bash
docker compose --profile test run --rm -T test \
  pytest plugins/subscription/tests/integration/test_tarif_plan_repository_smoke.py -v
```

**Refactor:** None expected.

### TDD cycle 2 — verify CI-equivalent invocation

```bash
cd vbwd-backend
docker compose --profile test run --rm -T test \
  pytest plugins/subscription/tests/integration/ -v --tb=short
```

This is the exact command from `.github/workflows/tests.yml` step 7. Must exit `0`.

### TDD cycle 3 — full local gate

```bash
./bin/pre-commit-check.sh --plugin subscription --full
```

Must exit `0` before any push.

## 4. SOLID / DRY / clean code applied

- **SRP:** the new test asserts one behavior (round-trip persistence + active-list filter). Does not also test scheduler, handlers, or routes.
- **OCP:** depends on the existing `TarifPlanRepository` interface; new plan fields can be added without touching the test.
- **LSP / DIP:** receives `db_session` via fixture (does not new it up); the repository is constructed via its public constructor — no hidden globals.
- **DRY:** reuses the same `db_session` pattern shop sprint 02 uses, which itself comes from the cms plugin's integration conftest. The test layout, naming, and assertion style mirror sprint 02 deliberately — sprint 04 will lift this into a shared template.
- **Variable naming:** `created_plan`, `fetched_plans`, `repository`. **Not** `p`, `r`, `lst`. Per `feedback_variable_naming.md`.
- **Test data through services/repositories:** all DB writes go through `TarifPlanRepository.create`. Per `feedback_no_direct_db_for_test_data.md` — no raw SQL, no direct ORM session manipulation.
- **No suppression comments** — fix root causes per `feedback_no_noqa_without_permission.md`.

## 5. Acceptance criteria

- [ ] `plugins/subscription/tests/integration/test_tarif_plan_repository_smoke.py` exists, follows the template, uses full readable identifiers.
- [ ] `pytest plugins/subscription/tests/integration/ -v` collects ≥ 1 test and passes locally inside the `test` compose service.
- [ ] `./bin/pre-commit-check.sh --plugin subscription --full` exits `0`.
- [ ] `git diff` is limited to: the new test file (and at most a small conftest re-export). **No** changes under `plugins/subscription/subscription/`.
- [ ] Push to `VBWD-platform/vbwd-plugin-subscription` `main`; CI run `CI — subscription` flips to `completed/success`.
- [ ] `./recipes/ci-status.sh` shows `vbwd-plugin-subscription completed/success`.

## 6. Commit / push procedure

```bash
cd vbwd-backend/plugins/subscription
git status
git diff
git add tests/integration/test_tarif_plan_repository_smoke.py
# add conftest.py only if you actually created/edited it
git commit -m "test(integration): add tarif_plan round-trip smoke test to unblock CI

- Fixes 'collected 0 items' / exit 5 from pytest in the integration step.
- Smoke test goes through TarifPlanRepository → real DB → assert active filter.
- Sister fix for empty integration/ dirs is sprint 04 (workflow guard)."
git push origin main
gh run watch --repo VBWD-platform/vbwd-plugin-subscription
```

## 7. Risk register

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| `TarifPlan` field/constructor signature differs from the test stub | High | Read the model first. The test snippet above is a *template*, not a copy-paste mandate. Adapt before running. |
| Subscription's existing `tests/conftest.py` lives at `tests/`, not `tests/integration/` — fixtures might not propagate | Medium | pytest auto-discovers conftests up the tree, so a top-level `tests/conftest.py` *does* apply to `tests/integration/`. If the `db_session` fixture is in `vbwd-backend/conftest.py` instead, the test will pick it up via rootdir. Verify by running step 1 — failure mode will be `fixture not found`, easy to diagnose. |
| Race between this sprint and sprint 04 | Low | Same reasoning as sprint 02 §7. |
| Subscription scheduler interferes with the test session | Low | The scheduler starts only when `flask plugins enable subscription` runs; in pytest-only mode the scheduler is not bootstrapped. If a future change wires it in, gate the smoke test with `-p no:cacheprovider` or skip the scheduler in test config — out of scope for this sprint. |
