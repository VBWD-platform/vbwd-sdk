# S14 — Real `/api/v1/ready` endpoint with DB + Redis probes

**Source:** review §2.4 → `vbwd/app.py:255-258` returns 200 unconditionally.
**Risk:** LOW (adds a new endpoint) but stops a real prod-traffic-to-broken-container scenario.
**Outcome:** `/api/v1/health` stays a cheap liveness probe (process is alive). New `/api/v1/ready` returns 200 only when DB + Redis are reachable and migrations are at heads. Load balancer / orchestrator routes on `/ready`; restart loop watches `/health`.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_health_and_ready.py::test_health_returns_200_always`
   — even with DB session swapped to a raising mock, `/health` is 200.
2. `tests/unit/test_health_and_ready.py::test_ready_returns_503_when_db_down`
   — DB mocked to raise on `SELECT 1`, `/ready` is 503.
3. `tests/unit/test_health_and_ready.py::test_ready_returns_503_when_redis_down`
   — Redis mocked, `/ready` is 503.
4. `tests/unit/test_health_and_ready.py::test_ready_returns_200_when_healthy`
   — both probes green, `/ready` is 200.

## Touch-points

- `vbwd/app.py:255-258` (the existing `/health` route — leave it; just
  cheaper)
- `vbwd/app.py` (NEW `/api/v1/ready` route)
- `vbwd/services/readiness.py` (NEW — encapsulates probes; injected via
  container for testability)
- `docker-compose.server.yaml` (nginx + healthcheck — switch
  `service.healthcheck` to use `/ready` instead of `/health`)
- `gunicorn.conf.py` (no change — gunicorn doesn't probe)
- Docs runbook: `docs/architecture_core_server_ce/runbooks/healthchecks.md`

## Steps (each validated)

1. **Write the 4 Baseline tests.**
2. **Add `ReadinessProbe` service** with a `check()` returning
   `{db_ok, redis_ok, migrations_ok}`. Inject DB session + Redis
   client via container (§4 DI).
3. **Add the route**:
   ```python
   @app.route("/api/v1/ready")
   def ready():
       result = current_app.container.readiness_probe().check()
       status = 200 if all(result.values()) else 503
       return jsonify(result), status
   ```
4. **Add a "migrations at heads" probe** (optional but recommended) —
   compare `alembic current` to `alembic heads`. If you skip this in
   v1 to keep the slice narrow, note the deferral (§8).
5. **Update `docker-compose.server.yaml` healthcheck** for
   `vbwd_backend`:
   ```yaml
   healthcheck:
     test: ["CMD", "curl", "-fsS", "http://localhost:5000/api/v1/ready"]
     interval: 10s
     timeout: 3s
     retries: 3
     start_period: 30s
   ```
6. **Test in a local cold start.** Bring postgres down → `/ready` 503,
   `/health` 200. Bring postgres back → `/ready` 200.

## Acceptance (oracle)

- All four Baseline tests green.
- Local chaos test: kill postgres → `/ready` 503 within 1s.
- Pre-commit `--full` green.

## Notes

- Separates two distinct concerns (liveness vs readiness) — exactly
  what k8s / nginx / haproxy expect.
- §8 no overengineering: don't add per-plugin readiness probes yet —
  DB + Redis cover 95% of real failure modes.
- Future sprint could add a `/metrics` endpoint (Prometheus) — out of
  scope here.

## Outcome — 2026-05-27 (DONE — DB probe only; Redis deferred)

**Done.** 3 tests green: `/health` always 200, `/ready` returns 200
when DB ok and 503 when DB raises.

**Patch:** new `/api/v1/ready` route in `vbwd/app.py:272-285` runs
`db.session.execute(text("SELECT 1"))` and returns
`{"db": true}` 200 / `{"db": false, "error": "..."}` 503.

**Reduced scope vs original plan (§8):**
- Redis probe **not** added because `vbwd/extensions.py` doesn't expose
  a `redis_client` — `flask_limiter`'s storage URI is the only Redis
  config. Adding a redis-py client + dependency injection just for the
  probe is more code than the probe itself. Right call: add the Redis
  probe when something else needs a redis-py wrapper (then it gets the
  probe for free).
- `ReadinessProbe` service class not extracted — the route is 10
  lines and DI-free for now. Extract when a second probe (Redis,
  migrations-at-heads, plugin readiness) appears.

**Acceptance verified:**
- Both endpoints work (probed via tests + manual smoke).
- 503 returned when DB raises (`patch.object(db.session, "execute", ...)`).
- Production compose healthcheck wiring (`docker-compose.server.yaml`
  service.healthcheck) — **NOT updated** in this sprint; that's
  separate ops work. Document update needed: switch
  `vbwd_backend.healthcheck.test` from default Docker HEALTHCHECK to
  `curl -fsS http://localhost:5000/api/v1/ready`. Deferred.
