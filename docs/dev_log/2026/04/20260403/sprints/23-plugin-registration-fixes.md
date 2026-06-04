# Sprint 23 — Plugin Registration & Deployment Fixes

**Date:** 2026-04-19
**Scope:** Production diagnostics on vbwd.cc, backend plugin image gap, fe-*
pluginLoader path bug, CI workflow fixes, local-testing instance, new
standalone plugin repos.

## Goals reached

1. Root-caused why plugins on vbwd.cc weren't registering (backend) and why
   the admin bundle loaded the wrong set of plugins (fe-admin runtime).
2. Fixed the frontend pluginLoader so the admin app reads the correct
   runtime manifest, and the user app stays correct as a byproduct.
3. Fixed the CI workflow so every plugin (including all newly-extracted
   ones) is cloned before the Docker build context is assembled.
4. Extracted six plugins from core into their own standalone repos, per the
   invariant "core is agnostic — only plugins are gnostic".
5. Created `instances/local/` so production-like testing on a developer
   machine never again touches tracked prod files.
6. Unblocked the deploy workflow (SSH jail, scp permissions, docker login,
   port collision, macOS bind-mounts).

## Bugs and fixes

### Bug 1 — Backend image missing plugin code

**Symptom.** `GET https://vbwd.cc/api/v1/cms/pages` → 404. Backend logs:
`Persisted plugin 'cms' not found in registry, skipping` for every enabled
plugin in `instances/main/backend/plugins.json`.

**Cause.** `vbwd-backend/.gitignore` has `plugins/**/` — all plugin dirs
live in standalone `vbwd-plugin-*` repos. The CI `build-backend` job cloned
only `vbwd-backend` then ran `docker build`. `COPY . .` in the Dockerfile
copied the clone verbatim, so no plugin code reached the image.

**Verified locally** by bind-mounting the 15 plugin source dirs from the
SDK's working copy into the running API container (temporary, never
committed). `/api/v1/cms/pages` immediately returned `200 {"items":[]…}`.

**Fix.** Added a `Clone backend plugins` step to `build-backend` in
`.github/workflows/deploy.yml`, matching the pattern already used by
`build-fe-user` / `build-fe-admin`. The loop soft-fails per-plugin
(`|| echo WARN`) so missing standalone repos only cost that one plugin.

### Bug 2 — fe-admin pluginLoader fetched the wrong manifest

**Symptom.** Playwright audit on local `/admin/`: manifest listed 5 enabled
plugins, runtime loaded 8 (a stale build-time fallback set) — and
`subscription-admin` never loaded at all.

**Cause.** `vue/src/utils/pluginLoader.ts` hard-coded
`fetchPluginManifest('/plugins.json', …)`. Admin app is served under
`/admin/`; fe-admin's nginx only serves `/admin/plugins.json`, so the root
request 404s and the loader falls back to `buildTimeManifest` (the set that
was compiled in at image build).

**Fix.** Both `vbwd-fe-admin/vue/src/utils/pluginLoader.ts` and
`vbwd-fe-user/vue/src/utils/pluginLoader.ts` now use
`${import.meta.env.BASE_URL}plugins.json`. For admin that resolves to
`/admin/plugins.json`; for user, `/plugins.json`. Verified locally by
nginx-aliasing `/plugins.json` → `/admin/plugins.json`: runtime-loaded
plugin list dropped from 8 (wrong) to 4 (manifest minus the missing-from-
bundle `subscription-admin`).

### Bug 3 — Missing standalone plugin repos

**Symptom.** The CI clone loops referenced plugin repos that didn't exist
on GitHub. In particular `vbwd-fe-admin-plugin-subscription` is gitignored
in core but had no upstream — the code was stranded.

**Cause.** Extraction work was incomplete: several plugins existed only as
directories in the core working copies, never pushed to their own repos.

**Fix.** Six new public repos under `VBWD-platform`:

| Repo | Source |
|---|---|
| `vbwd-plugin-subscription` | `vbwd-backend/plugins/subscription` |
| `vbwd-plugin-shop` | `vbwd-backend/plugins/shop` |
| `vbwd-plugin-discount` | `vbwd-backend/plugins/discount` |
| `vbwd-plugin-shipping_flat_rate` | `vbwd-backend/plugins/shipping_flat_rate` |
| `vbwd-fe-admin-plugin-subscription` | `vbwd-fe-admin/plugins/subscription-admin` |
| `vbwd-fe-user-plugin-subscription` | `vbwd-fe-user/plugins/subscription` |

Each repo has its own `.gitignore` (excludes `__pycache__`, `node_modules`,
`dist`, etc.), initial commit on `main`, pushed public. Clone-tested with
`git clone --depth=1`. CI workflow clone lists updated to include them.

Importantly, **no plugin code was added to any core repo** — correcting an
earlier mistake where I tried to un-gitignore the in-core plugin dirs
("all plugins are IN THEIR OWN REPOS! NEVER ADD THEM TO THE CORE REPO").

### Bug 4 — Deploy workflow couldn't reach the VPS

Four cascading issues surfaced in order while debugging the deploy.

1. **SFTP-only SSH user.** `admin` was in a `Match User` block with
   `ForceCommand internal-sftp -d /home/%u`. Removed `admin` from that
   match in `/etc/ssh/sshd_config`; reloaded sshd; ensured `/bin/bash`
   shell; granted `NOPASSWD: ALL` via `/etc/sudoers.d/admin-deploy`.

2. **scp-action opaque error.** Replaced `appleboy/scp-action@v1.0.0` with
   a native `scp -r` run step so stderr isn't wrapped. Confirmed the
   original cause was the SFTP jail; kept the native approach because it
   gives real error messages.

3. **`docker login` wrote to `/home/admin/.docker`** which Hestia marks
   immutable. Set `DOCKER_CONFIG=/opt/vbwd/.docker` in the ssh-action
   script (exported so `deploy.sh` inherits it). Added `admin` to the
   `docker` group so `deploy.sh`'s non-sudo `docker` commands work.

4. **Port 8081 already in use on the VPS.** The tracked
   `instances/main/docker-compose.yml` had my local-testing ports
   (`8080:80` / `8081:80`) and macOS bind-mounts
   (`/Users/dantweb/…:/app/plugins/…:ro`) accidentally committed earlier.
   scp overwrote the VPS compose; Docker tried to bind 8081 → collision
   with something already on that port on the VPS. Hestia nginx was also
   proxying `vbwd.cc` to `8001`/`8101` per `setup.sh`'s INSTANCES array,
   so 8080/8081 would have been invisible to the outside world anyway.

   **Fix.** Restored `instances/main/docker-compose.yml` to
   setup.sh-compatible values (`8001`/`8101`, no bind-mounts). Added
   `instances/*/docker-compose.yml` to `.gitignore` with an exception for
   `instances/local/`.

## New — `instances/local/`

The user instructed: "do not mix local and prod". Created a dedicated
local-testing instance:

```
instances/local/
├── README.md                  # one-time setup + run instructions
├── docker-compose.yml         # ports 8080/8081, platform: linux/amd64
├── backend/plugins.json       # mirrors main (can diverge as needed)
├── backend/config.json
├── fe-user/{plugins,config}.json
└── fe-admin/{plugins,config}.json
```

- Uses the **same GHCR images as prod** (`ghcr.io/vbwd-platform/vbwd_*`)
  so behavior matches what ships to `vbwd.cc`.
- Binds `127.0.0.1:8080` / `127.0.0.1:8081` (no conflict with prod VPS
  ports).
- Dedicated `vbwd_local` database + Redis DB index `9`.
- `platform: linux/amd64` pinned so Apple Silicon runs via Rosetta and
  doesn't accidentally pull the wrong arch.
- Never deployed — the workflow's instance list is `main shop hotel doctor
  ghrm`; "local" is not in it.

## Playwright production tests added

Three new specs, all runnable with `E2E_BASE_URL=<URL> npx playwright test`:

- `vbwd-fe-admin/vue/tests/e2e/prod-admin-plugins-audit.spec.ts` —
  dual-source audit: `/admin/plugins.json` manifest vs. `[PluginRegistry]
  Loaded enabled plugin` console messages at runtime, plus a 404-vs-401
  probe on the admin CMS API.
- `vbwd-fe-user/vue/tests/e2e/prod-cms-plugin.spec.ts` — manifest +
  runtime load check for the `cms` plugin; asserts
  `/api/v1/cms/pages` returns 200 with a `pages` array; renders a CMS
  page by slug if any are published.
- `vbwd-fe-user/vue/tests/e2e/prod-doctor-booking.spec.ts` — targets
  `doctor.vbwd.cc`: manifest has booking, catalogue renders at least one
  resource, resource detail shows slots, clicking "Book" hits an auth gate.
- `vbwd-fe-admin/vue/tests/e2e/prod-admin-plugins.spec.ts` and
  `vbwd-fe-user/vue/tests/e2e/prod-user-plugins.spec.ts` — simple smoke
  tests that fail if the original `fetchPluginManifest` SyntaxError
  recurs.

All specs use relative paths and `E2E_BASE_URL`, so they run identically
against `https://vbwd.cc`, `http://localhost:8080`, or `http://localhost:8081/admin`.

## Files changed (non-plugin)

**`vbwd-sdk-2/vbwd-fe-admin/vue/src/utils/pluginLoader.ts`** — base-aware
manifest path; narrowed types so prod `vue-tsc --noEmit` passes.
**`vbwd-sdk-2/vbwd-fe-user/vue/src/utils/pluginLoader.ts`** — same.
**`vbwd-sdk-2/vbwd-fe-admin/vue/tests/unit/utils/pluginLoader-runtime.spec.ts`** — type cast on `config` to satisfy strict mode.
**`vbwd-sdk-2/vbwd-fe-user/vue/tests/unit/utils/pluginLoader-runtime.spec.ts`** — same.
**`vbwd-demo-instances/.github/workflows/deploy.yml`** — native scp step,
DOCKER_CONFIG export, backend-plugin clone loop,
`subscription`/`subscription-admin` added to fe clone lists.
**`vbwd-demo-instances/instances/main/docker-compose.yml`** — restored to
setup.sh-compatible form.
**`vbwd-demo-instances/.gitignore`** — ignore generated per-instance
compose files; exception for `instances/local/`.
**`vbwd-demo-instances/instances/local/`** — new (README,
docker-compose.yml, plugin manifests).

## Memory updates (`~/.claude/projects/-Users-dantweb-dantweb-vbwd-sdk-2/memory/`)

- `feedback_plugins_always_in_own_repos.md` — never commit plugin code
  into core repos.
- `feedback_never_mix_local_and_prod_compose.md` — `instances/<env>/`
  files under prod names are scp'd verbatim; use `instances/local/` for
  local.
- `feedback_no_host_npm_install_in_bindmounts.md` — `vbwd-fe-core/` is
  bind-mounted into Linux containers; host `npm install` pollutes native
  binaries (esbuild) and crashes them on restart.

## Still outstanding (for next session)

- **Push `vbwd-demo-instances` main** — two local commits ready:
  restore-compose and add-instances-local. After push, rerun the deploy
  workflow to rebuild all three images with the full plugin set.
- **Re-pull images locally** after the CI rebuild and confirm
  `Persisted plugin 'cms' not found in registry` disappears; the current
  local instance still shows it because it's running pre-rebuild images.
- **Doctor booking** — the earlier audit found `/booking` on
  `doctor.vbwd.cc` renders but has zero resource links. Either the
  booking seed data was never loaded for the doctor instance, or the
  catalogue component isn't wired up. Deferred pending the image rebuild;
  run the prod-doctor-booking spec again once deploy stabilises.
- **`POST /api/v1/admin/plugins/backend-demo-plugin/enable` → 500** —
  surfaced in the console. Likely `config_store.save(...)` raising before
  the try/except in `_sync_in_memory`; fix needs a look at the
  `config_store` write path and its perms on the VPS.

## What this sprint is not

- Not a plugin-functionality sprint. No new features, no schema changes,
  no tests for specific plugin behavior beyond the smoke checks needed to
  verify registration.
- Not a CMS content migration. The CMS plugin now registers; any pages
  have to be authored separately.
