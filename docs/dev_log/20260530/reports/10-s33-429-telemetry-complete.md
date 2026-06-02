# Report 10 — S33: 429 telemetry (structured log on every rate-limit trip)

**Date:** 2026-06-02
**Status:** ✅ **DONE & GREEN.** Every 429 emitted by either limiter now writes
one WARN-level structured log line, so the next "users hit the cap" report is
answerable with `grep` instead of reading an error string off a screenshot.

## What shipped (2 one-line log statements + 2 guard tests)

**Global Flask-Limiter handler** — `vbwd/app.py::ratelimit_handler`:
```
429 route=<endpoint|path> key=<bucket_key> descriptor=<tripped limit>
```
The bucket key uses the limiter's **current** keyfunc (`get_remote_address`).
Added `request` + `flask_limiter.util.get_remote_address` to the imports.

> **Deviation from the sprint doc (§2.1):** the doc's snippet logged the key
> via `_rate_limit_key_func()`, but that helper only exists **after S31** (which
> is on hold pending the JWT-signature-verification decision). To keep S33
> independent, S33 logs the key with the keyfunc actually in use today
> (`get_remote_address`). When S31 lands and swaps the keyfunc, this line picks
> up the per-user key automatically (single point of change).

**Meinchat custom limiter** — `plugins/meinchat/meinchat/routes.py::_enforce_rate`:
```
429 category=<category> user_id=<user_id> retry_after_seconds=<n>
```
Uses `current_app.logger.warning(...)`, matching the file's existing
`current_app.logger.error` usage (no new module-level logger, no new dep).

Both lines are stdlib `%`-formatted at WARN — no structlog, no metrics hook, no
request-id correlation (explicit NO-OVERENGINEERING per the sprint).

## Tests (TDD — RED first, then GREEN)

- `tests/unit/routes/test_rate_limiting.py::TestRateLimitTelemetry` — drives the
  real registered 429 handler via `app.handle_http_exception(TooManyRequests(...))`
  inside a request context and asserts the WARN line carries route + key +
  descriptor. (First attempt registered a throwaway route, but a catch-all rule
  in the url-map shadowed it → 200; `handle_http_exception` is the robust path.)
- `plugins/meinchat/tests/unit/routes/test_start_conversation_rate_limit.py::TestMeinchatRateLimitTelemetry`
  — unit-tests `_enforce_rate` with a patched `_rate_limiter` raising
  `RateLimitExceeded`; asserts the WARN line carries category + user_id.

> **Home note:** the sprint doc suggested extending `test_global_rate_limit_env.py`,
> but that file is explicitly pure-unit (no app boot). The app-boot caplog spec
> belongs in `test_rate_limiting.py` (which already boots apps); placed it there.

## Gate (`bin/pre-commit-check.sh`)

- **Core `--quick`:** Part A static analysis PASS · Part B **2443 passed, 5 skipped** (94s).
- **`--plugin meinchat --quick`:** Part A PASS · Part B **261 passed, 5 skipped**.
- Touched files black + flake8 clean.

## Engineering requirements

TDD-first (both specs RED before the log lines existed), narrowest change
(2 log statements, no new deps/schema), core stays agnostic. **Not committed**
(standing rule).
