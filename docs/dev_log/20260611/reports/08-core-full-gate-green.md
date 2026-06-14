# Report 08 — `core --full` green (follow-up to S69)

**Date:** 2026-06-12 · **Repo:** `vbwd-backend` · Follow-up to [report 07 (S69)](07-s69-plan-addon-driven-permissions.md), addressing the "core `--full` not fully green" caveat raised there.

## Result

`bin/pre-commit-check.sh --full` is **GREEN both ways** — the CI / in-container path **and** the verbatim host script (after the host-path hardening below, committed `fda435d`). The CI-path numbers below are the original verification; the host script now reports **838 integration passed / 0 failed** (see "Host path also hardened").

| Part | Result |
|---|---|
| A — static analysis (black / flake8 / mypy on `vbwd/ tests/`) | **PASS** |
| B — unit (`tests/unit/ plugins/*/tests/unit/`) | **3806 passed, 5 skipped, 0 failed** |
| C — integration (`tests/integration/ plugins/*/tests/integration/`) | **672 passed, 170 skipped, 0 failed, 0 errors** |

Run in-container via the `test` service on a freshly-dropped DB with `GHRM_USE_MOCK_GITHUB=true` (the CI default — the local `.env` sets it `false`, which spuriously reddens ghrm).

## What was actually wrong (and what wasn't)

Investigating the earlier "core `--full` is red" reports surfaced four separate things; only one was a genuine test fix:

1. **The two core meta-ratchets are not in the gate's scope.** `tests/meta/test_repository_coverage.py` (flagging `seed_marker_repository`, committed since S30, + the uncommitted-S66 `device_token_repository`) and `tests/meta/test_datetime_tz_backlog.py` (an ambient booking `datetime.utcnow()` site) only fail under `pytest tests/` (which picks up `testpaths`). The gate passes explicit paths `tests/unit/ ...` that **override** `testpaths`, so `tests/meta/` never runs in `core --full`. No fix needed for the gate; these remain real backlog for whoever runs the whole tree.

2. **The cross-plugin integration cascade was dirty-DB residue.** The `CREATE TYPE userstatus already exists` wall came from stale `_test` databases left by prior aborted runs. Dropping them and re-running clean → the cascade vanishes (the integration suite goes 0-error). CI starts from a fresh DB, so it never sees it.

3. **The only genuine fix — two taro config tests.** `plugins/taro/tests/integration/test_real_llm_language.py::TestLLMConfigurationLoading` asserted that the **aggregate** `plugins/config.json` carries a populated `taro` section, but that file is an environment-built artifact (dev-install merges each plugin's `config.json`) and on a minimal local config it only has `cms`. The tests already skip on `FileNotFoundError`; they now also skip when the taro section is absent/empty — the same "config not available in this environment" condition, matching the skip-when-unconfigured idiom already used elsewhere in that file. The plugin's own tracked `plugins/taro/config.json` is unchanged and complete. (Plugin code is gitignored, so this lives on disk.)

4. **A transient from parallel S72.4 work.** During the session the `price_display_mode` (netto/brutto) feature landed on disk mid-implementation — for a few minutes its unit tests and the subscription schema-fingerprint guard were red. Once that work completed, all of it went green on the CI path (unit climbed 3776 → 3806). Not S69, not part of this follow-up.

## Host path also hardened — verbatim script is green (2026-06-12 follow-up)

Run **on the host (macOS)**, `bin/pre-commit-check.sh --full` takes the non-`IN_DOCKER` branch for integration (script line ~52): it `flask seed-*`'s data and runs the whole suite via the `test-integration` compose profile. Run together that way, the plugin integration suites — which **share one `vbwd_test` database** — collided: the per-test `create_all()`/`drop_all()` in the **booking** and **ghrm** conftests stranded standalone PG ENUM types (`MetaData.drop_all()` doesn't drop them) → a later `create_all()` hit `CREATE TYPE userstatus ... already exists`, and a sibling's `drop_all()` removed a shared table another suite needed → `relation "vbwd_user" does not exist`. That cascaded to 53 + 10 setup errors.

**Fix (committed `fda435d`):** new core helper `vbwd/testing/integration_db.py` — `reset_schema_and_create_all()` (one `DROP SCHEMA public CASCADE` + `create_all()` per session, clearing tables **and** enums) and `truncate_all_tables()` (per-test isolation), the same approach the cms/shop suites already use. The booking and ghrm conftests (gitignored plugin trees, on disk) now build the schema once per session and isolate per test by TRUNCATE instead of per-test create/drop.

**Verified:** the verbatim `GHRM_USE_MOCK_GITHUB=true bin/pre-commit-check.sh --full` is now **green end-to-end** — Part A PASS, Part B **3813 unit passed**, Part C **838 integration passed, 0 failed, 0 errors** → "SUCCESS: All checks passed! Ready to commit." (The `vbwd/testing/` helper is committed; the two conftest edits live on disk like all plugin code in this repo.)

## How to reproduce the green run

```bash
# drop stale test DBs first (CI starts fresh; local runs accumulate them)
docker compose exec -T postgres psql -U vbwd -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datname LIKE '%test%';" \
  | xargs -I{} docker compose exec -T postgres psql -U vbwd -d postgres -c 'DROP DATABASE IF EXISTS {};'
# CI-equivalent unit + integration (in-container, mock GitHub)
GHRM_USE_MOCK_GITHUB=true docker compose run --rm -T -e GHRM_USE_MOCK_GITHUB=true test \
  python -m pytest tests/unit/ plugins/*/tests/unit/ tests/integration/ plugins/*/tests/integration/ -q
```
