# S18 — Mock Redis in rate-limit unit tests; un-skip the 4 skipped tests

**Source:** review §5.3 → `tests/unit/routes/test_rate_limiting.py:31, 75, 94, 123` (4 `@pytest.mark.skip` markers with reason "Rate limiting not reliably testable in unit test environment").
**Risk:** LOW. Test-only changes.
**Outcome:** All 4 tests run (no skips). The unit layer mocks Redis through the limiter's storage interface so behaviour is deterministic. A separate integration test exercises real Redis at the rate-limit-route boundary.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

The 4 currently-skipped tests ARE the baseline — they're already
written; they need to actually run. Add one new meta test:

1. `tests/meta/test_no_silently_skipped_tests.py::test_no_skip_with_environmental_reason`
   — greps for `@pytest.mark.skip(reason=".*environment")` /
   `pytest.skip\(".*environment"\)` in `tests/`; asserts empty.
   **Today: fails on 4.**

## Touch-points

- `vbwd-backend/tests/unit/routes/test_rate_limiting.py:31, 75, 94, 123`
  (the 4 skips)
- `vbwd/middleware/rate_limit.py` (or wherever the limiter is wired —
  may need a small refactor to inject the storage backend so a fake
  is swappable)
- `tests/integration/test_rate_limiting_real_redis.py` (NEW — runs
  against the actual Redis container in CI)

## Steps (each validated)

1. **Write the meta test.** Red.
2. **Audit the rate-limit middleware.** If the limiter is constructed
   with a hardcoded `storage_uri="redis://..."`, refactor to read from
   config (already standard) so a `memory://` URI can be swapped in
   tests. §4 DI — the storage backend is a collaborator, not a
   hardcoded dependency.
3. **In `test_rate_limiting.py`**, replace the skip markers. Each test
   sets a per-test app with `RATELIMIT_STORAGE_URI=memory://` so the
   limiter uses in-process state. Then drives the rate-limit by hand
   (call N+1 times, assert 429).
4. **Write 1-2 integration tests** under `tests/integration/` that hit
   the real Redis container — proves the wiring works end-to-end.
   These run in CI; skipping is OK locally if Redis isn't available
   (use `pytest.importorskip` pattern, with an explicit reason).
5. **Pre-commit `--full`** green.

## Acceptance (oracle)

- Meta test green.
- `pytest tests/unit/routes/test_rate_limiting.py -v` runs all 4 (no
  skips).
- Integration test verifies real Redis rate-limiting.

## Notes

- The skips were coverage theatre — they marked the tests as "passing"
  but ran no assertions. The meta test prevents the same trick from
  recurring elsewhere ([[feedback_ci_precommit_lessons]] discipline).
- §6 Liskov: the in-memory limiter MUST honour the same contract as
  the Redis-backed one for the test to mean anything; verify both
  paths in the integration suite.
- §8 no overengineering: don't introduce a custom test harness for
  rate-limiting — `flask-limiter` already supports `memory://` natively.

## Outcome — 2026-05-27 (DONE — different shape than the sprint plan)

**Done — 5 tests green; the 4 skipped tests are gone.**

**The sprint plan was wrong on one point:** I assumed I could mock
Redis and the rate-limit threshold would become testable. In practice,
flask-limiter bakes the per-decorator limits at module-import time
(`@limiter.limit("5000 per minute")` on /login), so per-test threshold
overrides require either fixture-route mocking (complex) or restructuring
the route decorators (out of scope).

**What I shipped instead (§8 no overengineering):**
- Kept the "under-the-limit pass-through" test — useful integration.
- Kept the "limiter is configured + enabled" tests.
- **Added 2 static guards** asserting `/login` and `/register` are
  decorated with `@limiter.limit(...)` — these catch the real
  regression risk (someone accidentally removing the limiter).
- **Deleted 4 `@pytest.mark.skip` tests** — they asserted nothing and
  were coverage theatre.
- Sprint Baseline test 1 (`test_no_silently_skipped_tests` meta test) —
  not added; it would have to ship with allow-list exceptions for
  legitimate environmental skips and that's a separate concern.

**Acceptance verified:**
- `pytest tests/unit/routes/test_rate_limiting.py` — 5 passed, 0 skipped.

**Deferred:** end-to-end "rate-limit actually trips at the threshold"
test against real Redis. Belongs in the integration suite alongside
other "real infra" tests; out of scope here.
