# Sprint 02 — `vbwd-plugin-shop` CI Recovery

**Status:** PLANNED — 2026-05-14
**Repo:** `VBWD-platform/vbwd-plugin-shop` (cloned at `vbwd-backend/plugins/shop/`)
**Last failed run:** [25366542159 — 2026-05-05](https://github.com/VBWD-platform/shop/actions/runs/25366542159) — commit "update checkout confirmation page".
**Engineering requirements:** [`../../20260422/sprints/_engineering-requirements.md`](../../20260422/sprints/_engineering-requirements.md) — binding.
**Sister sprints:** [03 — subscription](./03-subscription-ci-fix.md) (same root cause), [04 — shared workflow guard](./04-shared-ci-pytest-no-collect-guard.md) (the proper DRY fix).

---

## 1. Failure analysis (root cause, not symptom)

The CI job `CI — shop` failed at step **"Run integration tests"** with exit code `5`. Decoded log excerpt:

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

`pytest` exit code `5` = **"no tests collected"**. The CI workflow guards the integration step with:

```yaml
- name: Run integration tests
  if: always()
  working-directory: vbwd-backend
  run: |
    if [ -d "plugins/shop/tests/integration" ]; then
      docker compose --profile test run --rm -T test \
        pytest plugins/shop/tests/integration/ \
        -v --tb=short --junit-xml=/app/test-results/integration.xml
    else
      echo "No integration tests — skipping."
    fi
```

The guard `[ -d "plugins/shop/tests/integration" ]` is **truthy** because the directory exists — but it contains only `__init__.py` (verified locally: `ls plugins/shop/tests/integration/` → just `__init__.py`). pytest collects zero items and exits `5`. The shell, running `bash -e`, propagates the non-zero exit and the job fails.

The unit test step *passed* (3 files: `test_line_item_handler.py`, `test_models.py`, `test_stock_service.py`) — confirmed by the absence of any earlier `##[error]` in the log. Style checks also passed.

**Why the dir exists empty:** `__init__.py` was scaffolded when the plugin was extracted, in anticipation of integration tests, but no test was ever added. This is a *latent* CI bomb that detonates on the first push after the workflow was added.

**Two valid fixes exist:**
1. **Quick (this sprint):** Add at least one real integration smoke test so collection > 0. This is the right move because shop's domain (orders, stock, warehouses) genuinely benefits from a DB-backed smoke test.
2. **Systemic (sprint 04):** Strengthen the workflow guard so empty dirs don't fail CI.

We do **both**, sequenced: this sprint adds the smoke test (real coverage gain), sprint 04 hardens every plugin's workflow against future regressions.

## 2. Scope

**In:**
- One TDD-built integration smoke test under `tests/integration/` covering the highest-value happy path (product create → list → soft-delete via the repository layer with the `db` fixture).
- A `tests/integration/conftest.py` if one is missing, mirroring the pattern from `vbwd-backend/plugins/cms/tests/integration/conftest.py`.

**Out:**
- New unit tests beyond what is needed to cover the new test's helper paths.
- Any production code changes to `shop/` (the existing models/repositories already work; the failure is purely a "test collection" issue).
- Workflow YAML changes — sprint 04 owns that.
- Touching the line-item-handler subsystem — that has dedicated unit coverage already.

## 3. TDD checkpoints (red → green → refactor)

### Pre-flight: capture baseline

```bash
cd vbwd-backend
./bin/pre-commit-check.sh --plugin shop --quick
```

Should exit `0` (lint + unit are already green per the CI log). If anything else is red, log it as a follow-up — don't bundle.

### TDD cycle 1 — `tests/integration/test_product_repository_smoke.py`

**Red:** Author the test first, run it before any production code or fixture exists, watch it fail with a *meaningful* error (import error, missing fixture, missing table — not `collected 0 items`).

```python
# plugins/shop/tests/integration/test_product_repository_smoke.py
"""Smoke integration test: prove the shop plugin's product repository round-trips
through a real PostgreSQL session. Defends against silent regressions in the
SQLAlchemy mapper, the migration, and the conftest wiring.
"""
import pytest
from decimal import Decimal

from plugins.shop.shop.models.product import Product
from plugins.shop.shop.repositories.product_repository import ProductRepository


@pytest.mark.integration
def test_product_create_then_get_round_trips_through_real_db(db_session):
    repository = ProductRepository(db_session)
    created_product = repository.create(
        Product(
            name="Smoke Widget",
            slug="smoke-widget",
            price=Decimal("9.99"),
            currency="EUR",
        )
    )
    db_session.commit()

    fetched_product = repository.get_by_id(created_product.id)

    assert fetched_product is not None
    assert fetched_product.slug == "smoke-widget"
    assert fetched_product.price == Decimal("9.99")
```

**Why this test and no other:** it exercises the layered architecture end-to-end (model → repository → real DB session), which is the *cheapest* assertion that proves the integration harness itself works. Any deeper test (services, routes) is over-scope for a CI-recovery sprint.

**Green:** Run it.

```bash
docker compose --profile test run --rm -T test \
  pytest plugins/shop/tests/integration/test_product_repository_smoke.py -v
```

If the existing `tests/conftest.py` does not export `db_session`, **adapt** the test to whatever fixture exists in `vbwd-backend/conftest.py` or `plugins/cms/tests/integration/conftest.py` (the template). Do not invent a new fixture name — DRY by reuse.

**Refactor:** None expected. The test is intentionally minimal.

### TDD cycle 2 — verify CI-equivalent invocation

```bash
cd vbwd-backend
./bin/pre-commit-check.sh --plugin shop --integration
```

This runs the *exact* path the CI workflow runs (`pytest plugins/shop/tests/integration/`). Must exit `0`. If `--integration` is unsupported (check `pre-commit-check.sh --help`), use:

```bash
docker compose --profile test run --rm -T test \
  pytest plugins/shop/tests/integration/ -v --tb=short
```

### TDD cycle 3 — full local gate

```bash
./bin/pre-commit-check.sh --plugin shop --full
```

Equivalent to CI's combined checks. Must exit `0` before any push.

## 4. SOLID / DRY / clean code applied

- **SRP:** the new test asserts one behavior (round-trip persistence). It does not also test routes, services, or migrations.
- **OCP:** test depends on `IShippingProvider`-style abstractions only via the repository — adding more product fields later does not break this test.
- **DIP:** test injects the `db_session` fixture rather than newing up a session, matching the repository's constructor contract.
- **DRY:**
  - Reuses the `db_session` fixture pattern from `cms/tests/integration/`. Does not duplicate fixture setup.
  - The Black/Flake8/Mypy invocations are identical to those used by 9 other plugins — the project standard, not bespoke.
- **Clean code (per `feedback_variable_naming.md`):** full, readable names — `created_product`, `fetched_product`, `repository`. **No** `p`, `r`, `obj`.
- **Test data through services/repositories (per `feedback_no_direct_db_for_test_data.md`):** the test goes through `ProductRepository.create` — no raw `INSERT INTO products …`.
- **No suppression comments** — if mypy or flake8 complains about the test, fix the cause (e.g. import order) per `feedback_no_noqa_without_permission.md`.

## 5. Acceptance criteria

- [ ] `plugins/shop/tests/integration/test_product_repository_smoke.py` exists, follows the template, has full readable identifiers.
- [ ] `pytest plugins/shop/tests/integration/ -v` collects ≥ 1 test and passes locally inside the `test` compose service.
- [ ] `./bin/pre-commit-check.sh --plugin shop --full` exits `0`.
- [ ] `git diff` is limited to: the new test file, optionally a tiny `conftest.py` import re-export. **No** changes under `plugins/shop/shop/`.
- [ ] Push to `VBWD-platform/vbwd-plugin-shop` `main`; CI run `CI — shop` flips to `completed/success`.
- [ ] `./recipes/ci-status.sh` shows `vbwd-plugin-shop completed/success`.

## 6. Commit / push procedure

```bash
cd vbwd-backend/plugins/shop
git status
git diff
git add tests/integration/test_product_repository_smoke.py
# add conftest.py only if you actually created/edited it
git commit -m "test(integration): add product round-trip smoke test to unblock CI

- Fixes 'collected 0 items' / exit 5 from pytest in the integration step.
- Smoke test goes through ProductRepository → real DB → assert round-trip.
- Sister fix for empty integration/ dirs is sprint 04 (workflow guard)."
git push origin main
gh run watch --repo VBWD-platform/vbwd-plugin-shop
```

## 7. Risk register

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| `db_session` fixture name differs from cms template | Medium | Read `cms/tests/integration/conftest.py` first; copy fixture wiring verbatim. |
| Smoke test hits a missing migration in CI | Low | The shop migration registers via `alembic.ini` `version_locations`; CI runs `flask db upgrade` implicitly via `docker compose up --build`. If it fails, that's a *separate* migration bug — open a follow-up sprint, do not patch over with `pytest -k "not …"`. |
| Race between this sprint and sprint 04 | Low | Sequenced: 02 + 03 land first (provide *real* coverage), 04 lands second (defense-in-depth). 04 alone would let `tests/integration/` stay empty forever — that's regression appetite we don't want. |
