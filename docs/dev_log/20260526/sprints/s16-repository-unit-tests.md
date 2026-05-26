# S16 — Add unit tests for the 18 core repositories

**Source:** review §5.1 → no `vbwd-backend/tests/unit/repositories/` directory exists.
**Risk:** LOW (additive). High payoff in regression coverage.
**Outcome:** Every core repository has a unit test file in `tests/unit/repositories/` exercising its public surface. Tests use the `db` fixture (real Postgres in CI, in-memory or scoped Postgres locally per existing infra) and cover happy path + at least one edge per public method.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md). This is the TDD-discipline backfill sprint.

## Baseline (E1)

1. `tests/meta/test_repository_coverage.py::test_every_repository_has_a_test_file`
   — walks `vbwd/repositories/*.py`, computes the expected test file
   name, asserts existence under `tests/unit/repositories/`. **Today:
   fails on 18 of them.**

## Touch-points

Create `tests/unit/repositories/`. Files (one per repo):

```
test_user_repository.py
test_user_details_repository.py
test_invoice_repository.py
test_invoice_line_item_repository.py
test_token_repository.py
test_token_bundle_repository.py
test_token_bundle_purchase_repository.py
test_password_reset_repository.py
test_payment_method_repository.py
test_role_repository.py
test_tax_repository.py
test_country_repository.py
test_currency_repository.py
test_feature_usage_repository.py
test_plugin_config_repository.py
# + any others surfaced by the meta test
```

## Steps (each validated)

1. **Write the meta test** — it lists the gap automatically.
2. **Write `tests/unit/repositories/conftest.py`** if needed — provides
   the `db` fixture (re-use existing infra; do NOT introduce new
   fixtures — §8).
3. **For each repo**, write a focused unit test file. Template:
   ```python
   class TestUserRepository:
       def test_create_persists_and_returns(self, db):
           repo = UserRepository(db.session)
           user = repo.create(email="t@x.io", password_hash="…")
           assert user.id is not None
           assert repo.find_by_email("t@x.io") == user

       def test_find_by_email_returns_none_when_absent(self, db):
           assert UserRepository(db.session).find_by_email("nope@x.io") is None

       def test_delete_removes_row(self, db):
           …
   ```
   3-6 tests per repo. **Don't pad** — one happy path + one edge per
   method is the floor (§8 no overengineering).
4. **Re-run the meta test** — green when all files exist.
5. **Pre-commit `--full` green.**
6. **Optional:** measure coverage delta (`make test-coverage`); aim
   for >90% on `vbwd/repositories/`.

## Acceptance (oracle)

- Meta test green.
- Pre-commit `--full` green on backend.
- Coverage on `vbwd/repositories/` ≥ 90%.

## Notes

- Pair with [[s17]] which covers the agnosticism-port services.
- §5 DRY: extract shared test data builders (`UserFactory`,
  `InvoiceFactory`) only when the same fixture appears in ≥2 files —
  don't pre-build factories speculatively.
- §7 clean code: tests follow the project's naming rule —
  `test_<method>_<scenario>_<expected>`. No cryptic abbreviations
  ([[feedback_variable_naming]]).
