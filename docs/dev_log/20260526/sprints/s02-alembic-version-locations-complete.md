# S02 — Complete `alembic.ini` `version_locations`; fix `head` → `heads`

**Source:** review §2.1 + §2.3.
**Risk:** CRITICAL. Today, environments with `c2p2`, `conekta`, `mercado_pago`, `promptpay`, `toss_payments`, `truemoney` enabled run on an under-migrated DB — webhooks 500 the moment they touch a missing table.
**Outcome:** Every plugin with a `migrations/versions/` directory is discoverable by Alembic. `make migrate` and `Makefile.server::migrate` both run `alembic upgrade heads` (plural) and exit non-zero on failure. A CI step asserts every plugin migration dir is registered.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md). Gate: `bin/pre-commit-check.sh --full` green; new test asserts the registry is complete.

## Baseline (E1)

Tests to add first:

1. `tests/unit/test_alembic_config.py::test_every_plugin_with_migrations_is_registered`
   — walks `plugins/*/migrations/versions/`, parses `alembic.ini`
   `version_locations`, asserts every plugin dir with `*.py` migration
   files is present in `version_locations`. **Today: fails on
   c2p2, conekta, mercado_pago, promptpay, toss_payments, truemoney.**
2. `tests/integration/test_alembic_upgrade_heads.py::test_upgrade_heads_succeeds_with_all_plugins`
   — fresh DB, all plugins cloned, runs `alembic upgrade heads`, asserts
   exit 0 and every plugin's primary table exists.
3. `tests/unit/test_makefile_server.py::test_uses_alembic_upgrade_heads`
   — greps `Makefile.server` for `alembic upgrade head\b` (singular).
   **Today: fails.**

## Touch-points

- `vbwd-backend/alembic.ini` (the `version_locations =` line)
- `vbwd-backend/Makefile.server:67`
- `vbwd-backend/container/python/Dockerfile:27` (also runs `heads` —
  verify; if any environment uses `head` singular, fix here too — but
  the inline-migration removal is [[s03]], not this slice)
- CI workflow that runs migrations: `.github/workflows/tests.yml`
- CI workflow that deploys: `.github/workflows/deploy.yml`

## Steps (each validated)

1. **Write the three tests above.** They MUST fail.
2. **Append the 6 missing dirs** to `alembic.ini` `version_locations`:
   `plugins/c2p2/migrations/versions`,
   `plugins/conekta/migrations/versions`,
   `plugins/mercado_pago/migrations/versions`,
   `plugins/promptpay/migrations/versions`,
   `plugins/toss_payments/migrations/versions`,
   `plugins/truemoney/migrations/versions`.
3. **Evaluate `recursive_version_locations = true`.** If accepted, drop
   the explicit per-plugin list and just point at `plugins/` —
   self-maintaining (one home for "where do migrations live", §5 DRY).
   If the recursive flag pulls in unwanted dirs (e.g. plugin `__pycache__`),
   stay explicit and accept the per-plugin maintenance cost.
4. **Fix `Makefile.server:67`** — `alembic upgrade head` → `alembic upgrade heads`.
5. **Re-run the three tests** — all green.
6. **CI step (`tests.yml`)** — make the migration step fail-fast:
   `alembic upgrade heads || { echo "Migration failed"; exit 1; }`. This
   closes the cousin bug in §2.8 / [[s15]] for the migration step itself.

## Acceptance (oracle)

- `python -c "import configparser; c=configparser.ConfigParser(); c.read('alembic.ini'); print(c['alembic']['version_locations'])"`
  contains the 6 newly-added directories (or the recursive flag is on).
- `make migrate` and `Makefile.server::migrate` both invoke `heads`.
- `alembic upgrade heads` on a clean DB with all plugins enabled creates
  every plugin's primary table (`taro_card`, `cms_page`, `conekta_order`,
  `truemoney_*`, …).
- All three new tests green; pre-commit `--full` green.

## Notes

- This is a one-line config fix that prevents a data-integrity bomb.
  Schedule **before** any future plugin enablement in production.
- After this sprint, [[s03]] removes the inline migration from the
  container `CMD` — the two together close the migration story.
- Memory `project_migration_graph_fragmentation.md` notes the deeper
  issue that core migrations are anchored on plugin revisions. That
  remains a separate effort; this sprint does NOT touch revision graph
  topology — §8 no overengineering.
