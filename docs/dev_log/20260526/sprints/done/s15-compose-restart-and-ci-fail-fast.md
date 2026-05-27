# S15 — `restart: always` on backend; fail-fast plugin clone in CI

**Source:** review §2.7 (`docker-compose.server.yaml`) + §2.8 (`.github/workflows/tests.yml:87-89`).
**Risk:** LOW. Two small ops fixes that together close a "silent broken state" class of bug.
**Outcome:** Prod backend container restarts on crash. CI fails immediately if any plugin clone fails (no more green CI on a half-cloned plugin tree).

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_compose_server.py::test_backend_service_restarts_always`
   — parses `docker-compose.server.yaml`, asserts
   `services.vbwd_backend.restart == "always"`. **Today: fails (key missing).**
2. `tests/unit/test_ci_plugin_clone.py::test_clone_loop_exits_on_failure`
   — greps `.github/workflows/tests.yml` for the plugin clone loop;
   asserts `|| exit 1` (or `set -e` at the loop top) is present.
   **Today: fails.**

## Touch-points

- `vbwd-backend/docker-compose.server.yaml` (service: vbwd_backend)
- `vbwd-backend/.github/workflows/tests.yml:87-89` (plugin clone loop)
- `vbwd-backend/.github/workflows/plugin-tests.yml` (same pattern —
  verify)
- `vbwd-backend/.github/workflows/deploy.yml` (verify any plugin-clone
  steps also fail fast)

## Steps (each validated)

1. **Write the two Baseline tests.**
2. **Add `restart: always`** to `vbwd_backend` (and any other prod
   service missing it: do a sweep — postgres, redis, nginx, fe-user,
   fe-admin all have it; verify).
3. **Edit the CI clone loop:**
   ```yaml
   - name: Clone plugins
     run: |
       set -euo pipefail
       for plugin in analytics chat cms ...; do
         git clone --depth=1 \
           https://github.com/VBWD-platform/vbwd-plugin-${plugin}.git \
           plugins/${plugin} \
           || { echo "::error::Failed to clone plugin ${plugin}"; exit 1; }
       done
   ```
4. **Run the CI workflow** on a branch with a deliberately-broken
   plugin name (e.g. `vbwd-plugin-does-not-exist`) — CI must fail at
   the clone step with a clear error.

## Acceptance (oracle)

- Both Baseline tests green.
- Manual chaos test: `docker compose kill vbwd_backend` → container
  restarts within seconds.
- Manual chaos test: PR with a bogus plugin name → CI fails at clone,
  not at a confusing later step.

## Notes

- The fail-fast in CI also helps [[s02]] / [[s03]] (migration discovery
  + execution can fail loudly without being masked).
- §8 no overengineering: don't introduce a centralised "plugin manifest"
  YAML yet — the loop in tests.yml is fine for now; consolidate when
  more plugins arrive.

## Outcome — 2026-05-27 (DONE)

**Done.** 2 oracle tests green.

**Investigation finding:** `vbwd_backend` already had `restart: always`
(line 42 of `docker-compose.server.yaml`). That side of the sprint was
already correct — only added the permanent test guard.

**Patches:**
- `.github/workflows/tests.yml` — both `Install plugins` steps wrapped
  in `set -euo pipefail` and each `git clone` line gets
  `|| { echo "::error::Failed to clone plugin ${plugin}"; exit 1; }`.
  A deleted or private plugin repo now aborts CI at the clone step
  with a clear GitHub Actions error annotation, instead of letting
  tests proceed on a partial tree.

**Acceptance verified:**
- Both oracle tests green.
- `restart: always` guard prevents future drift.
- Manual chaos test (suggested for ops): push a PR with a bogus plugin
  name in the loop → CI now fails at the clone step within seconds.
