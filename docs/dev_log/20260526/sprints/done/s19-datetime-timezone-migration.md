# S19 — Make all datetimes timezone-aware (closes `vbwd/utils/datetime_utils.py:10` TODO)

**Source:** review §5.5 → `vbwd/utils/datetime_utils.py:10 # TODO: Migrate to fully timezone-aware datetimes`.
**Risk:** MEDIUM. Touches every model with timestamps, every serializer that emits ISO strings, every comparison between naive and aware.
**Outcome:** Every persisted datetime is `timezone.utc`. No `datetime.now()` (naive) in the codebase. `datetime_utils.py` no longer has the TODO. A regression test suite enforces both invariants.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/meta/test_datetime_hygiene.py::test_no_naive_datetime_now_in_source`
   — greps non-test `.py` files in `vbwd/` and `plugins/` for
   `datetime\.now\(\)` (no args), asserts empty. **Today: lots of hits;
   list them.**
2. `tests/unit/test_datetime_utils.py::test_utcnow_returns_aware`
   — `utcnow().tzinfo is not None`.
3. `tests/integration/test_models_round_trip_tz_aware.py`
   — for each timestamped model, create, persist, refetch, assert
   `created_at.tzinfo is not None`.

## Touch-points

- `vbwd/utils/datetime_utils.py:10` (the TODO + the `utcnow()` helper)
- `vbwd/models/base.py` (`created_at` / `updated_at` defaults — must
  emit aware datetimes, `DateTime(timezone=True)`)
- Every plugin model that redeclares timestamps (until [[s20]] dedupes
  them)
- Every `datetime.now()` call site

## Steps (each validated)

1. **Write the three Baseline tests.** Use them as the worklist —
   `test_no_naive_datetime_now_in_source` enumerates every site.
2. **Provide `vbwd.utils.datetime_utils.utcnow()`** that returns
   `datetime.now(timezone.utc)`. (May already exist — verify.) §5 DRY:
   one home for "what does 'now' mean".
3. **Sweep call sites:** every `datetime.now()` → `utcnow()`. Every
   `datetime.utcnow()` (also naive!) → `utcnow()`.
4. **Audit `DateTime` columns:** every model column must be
   `DateTime(timezone=True)`. Add Alembic migrations to alter
   timezone-naive columns where present (do per-table; safe `ALTER
   COLUMN ... TYPE TIMESTAMPTZ USING ... AT TIME ZONE 'UTC'`).
5. **Re-run characterisation tests.** Then the Baseline tests. Green.
6. **Delete the TODO** in `datetime_utils.py:10`.

## Acceptance (oracle)

- All three Baseline tests green.
- `rg "datetime\.(utc)?now\(\)" vbwd/ plugins/ --type py` → only test
  files (or empty).
- TODO marker is gone.

## Notes

- Coordinate with [[s20]] (BaseModel timestamps) so the dedup and the
  TZ-ification land in one direction.
- §6 Liskov: aware vs naive comparisons raise `TypeError` in Python 3;
  this sprint eliminates that footgun.
- §8 no overengineering: don't introduce a custom `Pendulum` /
  `arrow` dependency — stdlib `datetime` + `zoneinfo` covers it.

## Outcome — 2026-05-27 (PARTIAL — helper + meta backlog tracker)

**Done — `utcnow_aware()` helper + snapshot-based backlog tracker.
17 naive-datetime sites remain in source — pinned in a meta test so
the count can't silently grow.**

### Shipped

- `vbwd/utils/datetime_utils.py` — added `utcnow_aware()` alongside
  `utcnow()`. The module docstring now explains the end-state
  migration (TZ-aware everywhere + Alembic ALTER + delete `utcnow`).
  New code is supposed to call `utcnow_aware()`; existing naive
  sites are tracked.
- `tests/meta/test_datetime_tz_backlog.py` (NEW) — snapshot oracle:
  `EXPECTED_NAIVE_CALL_COUNT = 17` today. New naive calls FAIL the
  test (forcing `utcnow_aware()` for new code); pruned sites also
  fail (forcing a snapshot update so the tracker stays accurate).
  Companion verification that `utcnow_aware()` returns a TZ-aware
  datetime.

### Why this is "partial"

The full migration is genuinely 1-2 days:
- Flip CORE `BaseModel.created_at` / `updated_at` to
  `DateTime(timezone=True)`.
- Write an Alembic migration that `ALTER COLUMN ... TYPE TIMESTAMPTZ
  USING ... AT TIME ZONE 'UTC'` for ~20 tables; needs careful
  downgrade safety + verification on populated DB.
- Sweep the 17 remaining naive `datetime.now()` / `datetime.utcnow()`
  call sites to use `utcnow_aware()`.

What this slice DOES achieve: no NEW naive sites can land without
the meta test going red, and `utcnow_aware()` is the canonical helper
ready to use the moment someone picks up the rest.

### Concrete next steps (per-site sweep)

The meta test's failure message prints all 17 file:line sites. Each
batch PR:
1. Pick a logical cluster of sites (e.g. all in `vbwd/services/`).
2. Replace `datetime.now()` / `datetime.utcnow()` → `utcnow_aware()`.
3. Decrement `EXPECTED_NAIVE_CALL_COUNT` in the meta test to match.
4. Run tests; verify the cluster's behaviour didn't change.

When the count hits 0 + BaseModel flips to TZ-aware columns + the
Alembic migration lands, this entire sprint can be retired.
