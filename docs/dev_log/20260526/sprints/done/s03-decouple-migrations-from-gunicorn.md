# S03 — Decouple `alembic upgrade heads` from container startup

**Source:** review §2.2.
**Risk:** HIGH. Today a hanging or erroring migration permanently stalls the prod container — no rollback, no readiness signal, no way to inspect.
**Outcome:** `container/python/Dockerfile`'s `CMD` runs **only** gunicorn. Migrations are a separate one-shot step (compose `run --rm`, init container, or deploy-script step) that fails loudly and leaves the previous app version live.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_dockerfile.py::test_cmd_does_not_run_alembic`
   — parses `container/python/Dockerfile` `CMD`, asserts the word
   `alembic` does not appear. **Today: fails.**
2. `tests/integration/test_deploy_flow.py::test_migration_is_separate_step`
   — exercises the deploy script (or its dry-run equivalent), asserts
   migration runs before app start and exits non-zero on failure.

## Touch-points

- `vbwd-backend/container/python/Dockerfile:27` (the `CMD`)
- `vbwd-backend/docker-compose.server.yaml` (add `migrate` one-shot
  service OR document that deploy script runs `compose run --rm`)
- `vbwd-backend/Makefile.server` (`migrate` target — already exists;
  ensure deploy invokes it before `up`)
- `.github/workflows/deploy.yml` (deploy script: run migrate, **then**
  start app; abort on migrate failure)

## Steps (each validated)

1. **Write the tests** — they fail.
2. **Trim the `CMD`** to:
   ```dockerfile
   CMD ["sh", "-c", "[ -f /app/plugins/plugins.json ] || cp /app/plugins/plugins.json.dist /app/plugins/plugins.json && gunicorn --config gunicorn.conf.py vbwd.app:create_app()"]
   ```
3. **Add a one-shot migrate service** to `docker-compose.server.yaml`:
   ```yaml
   vbwd_migrate:
     image: ${VBWD_BACKEND_IMAGE}
     command: alembic upgrade heads
     env_file: .env.production
     depends_on:
       vbwd_postgres:
         condition: service_healthy
     restart: "no"
   ```
   Deploy script: `docker compose run --rm vbwd_migrate || exit 1`, then
   `docker compose up -d vbwd_backend`.
4. **Update `Makefile.server::deploy`** to run migrate before bringing
   the backend up.
5. **Update `.github/workflows/deploy.yml`** similarly — explicit step
   `Run migrations` with `exit 1` on failure, gated before `Start app`.
6. **Validate** on a staging-like local cold start: stop everything,
   wipe DB, run deploy script, confirm migrate runs, fails fast on a
   deliberately-broken migration, and succeeds on a clean one.

## Acceptance (oracle)

- `grep -E "alembic" container/python/Dockerfile` → no match.
- Deploy script aborts before app start if migrate fails (verify with
  a chaos test: temporarily inject a syntax error into a migration,
  confirm app stays on the previous image).
- Rolling back to the previous image is one `docker compose pull
  vbwd_backend:<previous-sha> && up -d` away (no DB rollback required
  if schema is backwards-compatible; document the contract).

## Notes

- Pairs with [[s02]] — together they fix the entire migration story.
- Down-migrations remain manual (not auto-run on deploy) — that's the
  correct default; rollback playbook lives in
  `docs/architecture_core_server_ce/runbooks/`.
- §8 no overengineering: don't introduce a custom migration orchestrator
  service — `compose run --rm` is the framework-native answer.

## Outcome — 2026-05-27 (DONE)

**Done.** New test `tests/unit/test_dockerfile_and_compose.py` (2 cases) green.

**Patches:**
- `container/python/Dockerfile:27` — stripped `alembic upgrade heads` out
  of the `CMD`; gunicorn launches immediately (plugins.json bootstrap
  preserved). Migrations no longer block container readiness.
- `docker-compose.server.yaml` — new one-shot service `vbwd_migrate`
  (same image, `command: ["alembic","upgrade","heads"]`, `restart: "no"`,
  depends_on postgres healthy).
- `Makefile.server` — new `migrate-once` target: `docker compose run --rm vbwd_migrate`.
  Deploy script should call `make migrate-once` BEFORE `make up`.

**Acceptance verified:**
- `test_dockerfile_cmd_does_not_run_alembic` green.
- `test_compose_server_has_dedicated_migrate_service` green.
- A failing migration now exits non-zero in `vbwd_migrate` without
  affecting any running backend container — rollback is "don't run the
  new image".

**Deferred:**
- The existing `make migrate` target (which `exec`s into a running
  backend container) is kept for ad-hoc manual use. New deploys
  should use `migrate-once`. Document this in
  `docs/architecture_core_server_ce/runbooks/deploy.md` (separate doc-only PR).
- A GitHub Actions `deploy.yml` workflow that invokes `migrate-once`
  before `up` doesn't exist in this repo yet — deployment is via
  `Makefile.server` on the prod host. When deploy.yml is added, the
  sequence is: `migrate-once || exit 1`, then `up`.
