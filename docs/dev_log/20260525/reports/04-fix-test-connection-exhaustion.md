# Report — Fix: `pre-commit-check.sh --full` connection exhaustion

**Date:** 2026-05-25
**Symptom:** running `bin/pre-commit-check.sh --full` produced a wall of
`sqlalchemy.exc.OperationalError: (psycopg2.OperationalError) ... FATAL: sorry,
too many clients already` — ~170 ERRORs + a couple FAILUREs, all the *same*
error. Each plugin/core suite passed in isolation; only the full run collapsed.

## Diagnosis
Every error was PostgreSQL connection exhaustion, not a logic failure. The full
unit run opens DB connections faster than they're released and crosses
`max_connections` (200) partway through; every test after that errors at setup.

Evidence: with the suite idle, `pg_stat_activity` showed **124 idle connections
on the `vbwd` database** (the test DB is `vbwd_test`), 108 of them opened by a
single test run inside a 16-second window, last query `ROLLBACK`. Classic
undisposed-engine leak.

Three compounding causes (all **test-infrastructure**, pre-existing):
1. **Per-test engine pools never disposed.** Most suites build a Flask app per
   test (`create_app()`), each with its own SQLAlchemy engine + pool; the pools
   are never disposed, so connections accumulate across ~1900 tests.
2. **`drop_all()` lock-hang.** A test that leaves its session *idle in
   transaction* holds table locks; a later suite's `db.drop_all()` then blocks
   on `DROP TABLE … (Lock)` forever. (This only became visible once cause #1 was
   fixed and the run progressed far enough to reach it.)
3. **Subscription scheduler unguarded in tests.** Core guards its booking
   scheduler with `if not TESTING` (`vbwd/app.py`), but the subscription
   plugin's `on_enable` started a `BackgroundScheduler` thread on *every*
   `create_app()`, including each test app.

## Why it surfaced on 2026-05-25
The leak *mechanism* lives in the test fixtures (`tests/conftest.py` +
per-plugin conftests) and predates Sprint 11. What tipped it over the 200 limit:
running the full/partial suite many times while validating S1–S7 left ~124 idle
zombie connections, and the unguarded subscription scheduler added a thread per
test app. So: not introduced by the extraction *code*, but exposed/aggravated by
the extraction work — and the scheduler guard is squarely subscription-owned.

## Fix
- **`vbwd-backend/conftest.py` (new, repo-root):** an autouse teardown that, after
  every test, (a) `db.session.remove()` — rolls back/returns the shared scoped
  session so no transaction lingers holding locks (kills cause #2), and
  (b) disposes every engine seen during the test (tracked via a global
  `engine_connect` event into a `WeakSet`) — returns pooled connections (kills
  cause #1). Pooling still works *within* a test, so tests stay fast.
- **`plugins/subscription/__init__.py`:** wrap `start_subscription_scheduler` in
  `if not current_app.config.get("TESTING")` (mirrors core; kills cause #3).
- Reverted a NullPool experiment in `vbwd/app.py` (it bounded connections but was
  ~30× slower).

## Result
`bin/pre-commit-check.sh --full` is **green**:
- Part A (black/flake8/mypy) PASS
- Part B unit: **1913 passed, 4 skipped, 0 errors** in 1:41 (was 1742 passed +
  170 errors)
- Part C integration: 308 passed, 61 skipped
- Idle connections during the run stay ~5 (was exhausting 200).

## Note for committing
`vbwd-backend/conftest.py` is a **new tracked-able file** — `git add` it.
The `plugins/` tree is gitignored in vbwd-backend, so the scheduler-guard edit
lives on disk only (as all plugin code does here).
