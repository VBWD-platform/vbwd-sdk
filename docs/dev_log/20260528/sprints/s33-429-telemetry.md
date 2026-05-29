# S33 — 429 telemetry (structured log on every rate-limit trip)

**Status:** PLANNED — 2026-05-28. Follow-up to [S26](s26-meinchat-rate-limits.md)
+ [S27](s27-lift-global-flask-limiter.md). Today's 429 reports were diagnosed
by reading the error string off a user's screenshot. After this sprint, every
429 emits one structured log line — route + bucket key + descriptor — so the
next "users hit the cap" report can be answered with `grep` instead of
guesswork.
**Track:** independent. **Repo:** `vbwd-backend`.
**Engineering requirements (BINDING):** TDD-first · NO OVERENGINEERING.

---

## 1. Goal
Every 429 emitted by either limiter (Flask-Limiter global handler + meinchat
custom `_enforce_rate`) writes a single WARN-level structured log line:
`429 route=<endpoint> key=<bucket_key> descriptor=<which limit tripped>`.

Stops the "I think users are hitting the cap" guesswork from §"Out of scope"
in [report 02](../reports/02-rate-limit-fixes-s26-s27.md). One `grep '"429"'`
on the api log answers: which routes, which buckets, which limits.

## 2. Design
Two single-line `logger.warning(...)` calls, one per limiter:

### 2.1 Flask-Limiter global handler (`vbwd/app.py:ratelimit_handler`)
```python
logger.warning(
    "429 route=%s key=%s descriptor=%s",
    request.endpoint or request.path,
    _rate_limit_key_func(),  # same keyfunc the limiter used
    str(error.description),
)
```

### 2.2 Meinchat custom limiter (`plugins/meinchat/meinchat/routes.py:_enforce_rate`)
```python
logger.warning(
    "429 category=%s user_id=%s retry_after_seconds=%d",
    category,
    g.user_id,
    exc.retry_after_seconds,
)
```

Both use stdlib logging (no new dep). Log level WARN so prod logging
captures it without dialling up verbose mode.

### NO OVERENGINEERING
- No structured-JSON logger / structlog adoption. Stdlib `%` formatting is
  fine; a `grep` user can read it.
- No metrics-emitter hook. If a Prometheus exporter lands later, it'll read
  the same log line.
- No request-id correlation. The route + key already narrows it; a full
  request-id concern is its own sprint.

## 3. TDD
2 specs in `tests/unit/routes/test_global_rate_limit_env.py` (extend) +
2 in `plugins/meinchat/tests/unit/routes/test_start_conversation_rate_limit.py`
(extend):

1. `test_429_emits_warn_log_with_route_key_descriptor` — caplog captures one
   WARN line with the expected fields on a Flask-Limiter trip.
2. `test_meinchat_429_emits_warn_log_with_category_and_user` — caplog
   captures the meinchat-side telemetry line when `_enforce_rate` 429s.

## 4. Files
| Action | Path |
| --- | --- |
| edit | `vbwd-backend/vbwd/app.py` — `ratelimit_handler` adds `logger.warning(...)` |
| edit | `vbwd-backend/plugins/meinchat/meinchat/routes.py` — `_enforce_rate` adds `logger.warning(...)` on the RateLimitExceeded path |
| edit | `vbwd-backend/tests/unit/routes/test_global_rate_limit_env.py` — +1 caplog spec |
| edit | `vbwd-backend/plugins/meinchat/tests/unit/routes/test_start_conversation_rate_limit.py` — +1 caplog spec |

## 5. Acceptance
- 2 new caplog specs green; existing 25 (S27+S28) and 19 (S26+S29 routes)
  stay green.
- `bin/pre-commit-check.sh --full` green.
- Manual: trip a 429 against the running api, `docker compose logs api |
  grep '429'` shows one structured line per trip.
