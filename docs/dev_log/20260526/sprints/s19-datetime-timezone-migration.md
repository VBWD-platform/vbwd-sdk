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
