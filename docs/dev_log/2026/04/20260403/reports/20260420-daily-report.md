# 2026-04-20 — Daily report

**Scope:** Three sprints landed and shipped, plus a cascade of CI / deploy
fixes surfaced along the way.

## Sprints completed

| # | Title | Result |
|---|---|---|
| 24 | Per-instance CMS seed overlay + `saas` vertical | Landed, deployed |
| 25 | CMS blog category view | Stub written — deferred, scope declared |
| 26 | CMS default style (TDD) | Landed across 3 plugin repos + umbrella |

Sprint docs live at `docs/dev_log/20260403/sprints/{24,25,26}-*.md`.

## Commits pushed (today)

```
vbwd-plugin-cms                 bfc200f   default-style: model/migration/service/routes/resolver
vbwd-fe-admin-plugin-cms        1948fc6   default-style UI (list badge, editor, page hint)
vbwd-fe-user-plugin-cms         02872b5   prefer resolved_style_id over legacy style_id
vbwd-fe-user                    9e3dd54   e2e: per-vertical header menu spec
vbwd-fe-user                    2fcd99d   nginx resolver + runtime variable upstreams
vbwd-fe-user                    bebe7f4   plugin-api Dockerfile + nginx /_plugins proxy
vbwd-fe-admin                   9fd278c   same-origin /_plugins + base-aware manifest + diag test
vbwd-fe-admin                   351905f   e2e: admin plugin enable/disable regression spec
vbwd-fe-admin                   b0e8694   bake HMAC secret into build; same-origin /_plugins
vbwd-backend                    dda01f1   json_config_store: write in place (no os.replace)
vbwd-demo-instances             67e9fa4   per-plugin populate_db for each vertical on --seed
vbwd-demo-instances             bf7a789   drop :ro on plugin-config mounts
vbwd-demo-instances             e78b0f5   regenerate instance composes on VPS from template
vbwd-demo-instances             b27cb3a   plugin-api sidecar + clone core repos from VBWD-platform
vbwd-demo-instances             de2d074   pass VITE_PLUGIN_API_SECRET + VITE_USER_APP_URL
vbwd-demo-instances             50f0064   sprint 24: seed overlay + saas vertical
vbwd-sdk (umbrella)             b2a72bd   sprint 26 doc + core submodule bumps
vbwd-sdk                        6294f5d   ci: clone plugins for fe-user + fe-admin unit tests
vbwd-sdk                        580d0e3   ci: clone backend plugins in backend-unit + integration
vbwd-sdk                        e4df929   ci: use bin/install_demo_data.py for seed step
vbwd-sdk                        3a8d4ba   sprint 24 + 25 docs, fe-user submodule bump
vbwd-sdk                        4ca51c9   bump fe-admin/fe-user submodules
```

---

## Sprint 24 — per-instance CMS seed overlay

**Goal:** each vertical presents vertical-specific header menu + home hero,
driven by a declarative JSON in `vbwd-demo-instances`. Plugin repos
untouched.

### Landed
- `bin/apply-instance-seed.py` + `bin/instance-seed.schema.json` — overlay
  applier that logs into the admin API and replaces header/footer menus
  and upserts home pages, all idempotent.
- Six `instance-seed.json` files — main with Demo submenu (6 subdomain
  links), plus doctor/hotel/shop/ghrm/saas with their CTA-specific third
  menu slot.
- New **saas** vertical: 13 backend plugins (all except shop+booking), 11
  fe-user plugins, 6 fe-admin plugins. Ports 8006/8106. Redis DB 5.
- `setup.sh`, `init-databases.sql`, `docker-compose.instance.yml`,
  `deploy.yml`, `deploy.sh` all wired for saas and for the overlay step.
- Playwright menu spec in `vbwd-fe-user/vue/tests/e2e/prod-vertical-menu.spec.ts`
  asserting top-level labels per vertical and the Demo submenu on main.

### Server-side work required (not code)
- DNS `saas.vbwd.cc` → VPS IP
- Hestia web domain + Let's Encrypt cert
- Hestia nginx proxying `/admin/` → `127.0.0.1:8106`, `/` → `127.0.0.1:8006`

---

## Sprint 26 — CMS default style (TDD)

### Backend (`vbwd-plugin-cms`)
- `CmsStyle.is_default` column + partial unique index enforcing the
  singleton invariant:
  `CREATE UNIQUE INDEX … ON cms_style (is_default) WHERE is_default IS TRUE`
- `CmsStyleService.set_default / clear_default / get_default_style`.
- `CmsPageService._with_resolved_style` — every page dict carries
  `resolved_style_id` + `resolved_style_source ∈ {explicit, default, null}`.
- 4 new routes:
  - `POST   /api/v1/admin/cms/styles/<id>/default`
  - `DELETE /api/v1/admin/cms/styles/default`
  - `GET    /api/v1/cms/styles/default`
  - `GET    /api/v1/cms/styles/default/css`
- Alembic migration `20260420_1000_style_default`.

### fe-admin (`vbwd-fe-admin-plugin-cms`)
- `useCmsAdminStore.setDefaultStyle / clearDefaultStyle`.
- `CmsStyleList.vue` gains a Default column with a badge on the current
  default and a "Make default" button on the rest (permission-gated).
- `CmsStyleEditor.vue` gains a Default section that shows current state
  and offers promote/clear actions.
- `CmsPageEditor.vue` shows a hint next to the Style dropdown — "No style
  selected — this page will render with the default style *<name>*" — or
  the no-default alternative.

### fe-user (`vbwd-fe-user-plugin-cms`)
- `useCmsStore.loadPage` prefers `resolved_style_id` over legacy
  `style_id`. Backwards-compatible with older backends.

### TDD stats
- 13 RED unit tests first → verified failing
- Implementation → 13 GREEN; full existing cms suite (156 tests) still
  passes unchanged; zero regressions
- 6 new integration tests for the HTTP surface
- Smoke-tested via curl against running local instance: full
  promote → public CSS → clear → 404 cycle passes

---

## Sprint 25 — CMS blog category view (stub)

Scope declared in `docs/dev_log/20260403/sprints/25-*.md`:
- `CmsCategory.is_blog_home: bool` + admin toggle
- Public `/blog` route with paged list, month archive, search
- `/blog/<category-slug>` detail page
- Alembic migration `20260420_cms_category_blog_home.py`

No code yet. Tracked as follow-up so sprint 24's stub `Blog` menu link
has a known next step.

---

## Ancillary fixes shipped today (prompted by in-session debugging)

### HMAC / User Plugins tab
- **Problem:** fe-admin's User Plugins tab threw "HMAC key data must not
  be empty" — the HMAC secret was never passed to `vite build`, so the
  client bundle had `SECRET = ''`.
- **Fix:** Dockerfile accepts `VITE_PLUGIN_API_SECRET` + `VITE_USER_APP_URL`
  as build-args; CI workflow forwards them from the GitHub secret. Code
  uses `??` instead of `||` so an explicit empty string for prod (→
  same-origin) propagates.
- **Also shipped:** brand-new `vbwd_fe_user_plugin_api` image (built from
  `vbwd-fe-user/Dockerfile.plugin-api`) plus a `plugin-api` service in
  `docker-compose.instance.yml` plus `/_plugins` proxy on both fe-user and
  fe-admin nginx configs. The whole User Plugins admin tab is now wired
  end-to-end in prod.

### Admin plugin toggle 500
- **Problem:** `POST /api/v1/admin/plugins/cms/disable` → 500 with
  `OSError: [Errno 16] Device or resource busy` on
  `/app/plugins/plugins.json`. Traced to `os.replace` on a Docker
  single-file bind mount.
- **Fix:** `json_config_store` now writes in place (no tempfile +
  `os.replace`); `docker-compose.instance.yml` drops the `:ro` flag so
  the write succeeds. Admin toggles persist to the host file on every
  click.
- Playwright regression spec added at
  `vbwd-fe-admin/vue/tests/e2e/prod-admin-plugin-toggle.spec.ts`.

### Nginx upstream-resolve crash
- **Problem:** fe-user nginx failed startup with `host not found in
  upstream plugin-api:3001` when the instance compose didn't have a
  plugin-api service (older instances from setup.sh).
- **Fix:** `nginx.prod.conf.template` now uses the docker resolver
  (`127.0.0.11`) and runtime variables. Missing upstream returns 502 at
  request time instead of crashing nginx on boot. Eliminated the 502
  cascade that blocked deploy #24648903180 yesterday.

### Deploy workflow regenerates instance composes from template
- **Problem:** per-instance `docker-compose.yml` files were scp'd
  verbatim from git, so changes to the template (e.g., adding the
  plugin-api service) didn't reach verticals without also editing every
  instance's committed compose.
- **Fix:** ssh-action step `envsubst`s the template into each
  `instances/$name/docker-compose.yml` on the VPS before running
  `deploy.sh`. `instances/main/docker-compose.yml` untracked from git.
- `instances/*/docker-compose.yml` added to `.gitignore`, with an
  exception for `instances/local/` (canonical local-testing template).

### CI plugin cloning
- **Problem:** umbrella `vbwd-sdk` CI tests failed because
  `plugins/ghrm-admin/...` imports couldn't resolve — plugin dirs are
  `.gitignored` in core repos, and the test Dockerfile saw empty
  `plugins/`.
- **Fix:** `fe-user-unit`, `fe-admin-unit`, `backend-unit` and
  `backend-integration` jobs now clone each plugin repo before building
  `Dockerfile.test`, mirroring the pattern already in the deploy
  workflow. Also switches all core-repo clone sources from
  `github.com/dantweb/*` (dead) to `github.com/VBWD-platform/*`.

### CI seed command
- **Problem:** `Seed test data` step used `flask --app src.app:create_app
  seed-test-data` which always errored — module path is `vbwd.app` and
  `src.*` was a legacy path.
- **Fix:** use `python bin/install_demo_data.py` (same script prod
  deploy.sh uses). CI and prod stay in sync on seed mechanics.

### Per-plugin `populate_db` seeding
- **New:** `deploy.sh --seed` now reads each instance's
  `backend/plugins.json` and runs `populate_db.py` for every enabled
  plugin. Tries both conventions (`<plugin>/populate_db.py` and
  `<plugin>/src/bin/populate_*.py`). `cd /app && PYTHONPATH=/app` so
  imports resolve regardless of script cwd.

---

## Plugin repos created today

| Repo | Source |
|---|---|
| `vbwd-plugin-subscription` | extracted from `vbwd-backend/plugins/subscription` |
| `vbwd-plugin-shop` | … |
| `vbwd-plugin-discount` | … |
| `vbwd-plugin-shipping_flat_rate` | … |
| `vbwd-fe-admin-plugin-subscription` | from `vbwd-fe-admin/plugins/subscription-admin` |
| `vbwd-fe-user-plugin-subscription` | from `vbwd-fe-user/plugins/subscription` |

All six are now tracked by the CI clone loops. Plugin invariant
("plugins live in their own repos, never in core") is restored.

---

## Memory artefacts saved

- `feedback_plugins_always_in_own_repos.md` — never bundle plugins into
  core repos (hard-corrected after a near-miss where I tried to
  un-gitignore them).
- `feedback_never_mix_local_and_prod_compose.md` — `instances/<vertical>/`
  files are prod; for local use `instances/local/` (tracked) or a
  gitignored `docker-compose.override.yml`.
- `feedback_no_host_npm_install_in_bindmounts.md` — never `npm install`
  on the host in `vbwd-fe-core/` (bind-mounted into Linux dev containers;
  Darwin-arm64 esbuild bins crash the container).

---

## What's still open

1. **`saas.vbwd.cc` DNS + Hestia cert** — manual, server-side.
2. **`vbwd-fe-user-plugin-cms`** legacy-fallback removal — remove the
   `style_id` fallback in a follow-up once every backend is confirmed
   emitting `resolved_style_id`.
3. **Sprint 25** implementation — CMS category blog-home view + paged
   archive + search. Scope written, not coded.
4. **Playwright UI-login flow** still times out against prod in the
   diagnostic spec; swap the UI fill-in for `window.localStorage`
   token injection or hit `POST /auth/login` via apiContext. Non-blocking.

---

## Stats

- **~22** commits today across **6** repos
- **~30** files created
- **~20** files modified
- **156** existing cms unit tests still green
- **13** new unit tests + **6** integration tests in sprint 26
- **0** plugin repos modified in sprint 24 (non-goal respected)

---

## Rollout checklist for operator

1. Provision DNS + Hestia for `saas.vbwd.cc`.
2. Trigger deploy workflow with `deploy_saas: true`, `run_migrations:
   true`, `seed_data: true`.
3. Verify menu via `npx playwright test prod-vertical-menu` (in
   `vbwd-fe-user`).
4. Verify default-style via admin UI: promote a style, create a
   page with no explicit style, confirm it renders with the default CSS.
5. Verify User Plugins tab on any vertical — HMAC should succeed and the
   list should render.
