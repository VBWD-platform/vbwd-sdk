# Plugin management — server-side, single-source-of-truth

**Status:** canonical architecture as of 2026-04-23. Replaces the earlier
per-browser `localStorage.vbwd_admin_plugin_state` override scheme.

## What "plugin" means here

VBWD ships three pluggable runtime hosts:

| Host | Plugin type | Manifest path |
|---|---|---|
| `vbwd-backend` (Flask) | Python plugin (blueprint + models + services) | `backend-plugins.json` + `backend-plugins-config.json` |
| `vbwd-fe-admin` (Vue SPA) | Frontend plugin (routes, nav, components) | `fe-admin-plugins.json` + `fe-admin-plugins-config.json` |
| `vbwd-fe-user` (Vue SPA) | Frontend plugin (routes, checkout hooks, widgets) | `fe-user-plugins.json` + `fe-user-plugins-config.json` |

Each host reads exactly one pair of files (manifest + config) to decide
which plugins to instantiate at boot.

## Single source of truth: `${VAR_DIR}/plugins/`

Every deployment maintains one directory **outside every container**:

```
${VAR_DIR}/plugins/
├── backend-plugins.json
├── backend-plugins-config.json
├── fe-admin-plugins.json
├── fe-admin-plugins-config.json
├── fe-user-plugins.json
└── fe-user-plugins-config.json
```

All three containers bind-mount this directory. The **backend is the only
writer**. Both frontends mount the files read-only as the `plugins.json` /
`config.json` their SPA loads at boot.

`VAR_DIR` is an env var:

- **SDK dev** (`vbwd-sdk-2/`): defaults to `./var/` at the repo root.
- **vbwd-platform**: `${VBWD_VAR_DIR:-./var}` at the platform root.
- **Per-vertical instance** (`hotel`, `shop`, `doctor`, `ghrm`, `main`,
  `saas`): `VAR_DIR=/opt/vbwd/instances/<name>/var` in the instance's
  `.env`, created by `setup.sh` and re-verified on every deploy.

## Admin API surface

All endpoints are gated by `@require_auth + @require_admin +
@require_permission("settings.system")`. Only SUPER_ADMIN can toggle.

```
GET  /api/v1/admin/frontend-plugins/<app>
POST /api/v1/admin/frontend-plugins/<app>/<plugin>/enable
POST /api/v1/admin/frontend-plugins/<app>/<plugin>/disable
```

`<app>` resolves to `admin` | `user` | `backend` via env vars:

| app | env var |
|---|---|
| `admin` | `VBWD_FE_ADMIN_PLUGINS_JSON` |
| `user`  | `VBWD_FE_USER_PLUGINS_JSON`  |
| `backend` | `VBWD_BACKEND_PLUGINS_JSON` |

Unconfigured apps return `404 Unknown or unconfigured frontend app`, so
deployments can opt out per-app (e.g. a locked-down marketplace edition
that refuses any plugin toggling).

## Toggle flow

1. Admin clicks **Deactivate** on `/admin/settings/plugins/<name>`.
2. fe-admin's `pluginsStore.deactivatePlugin(name)` calls
   `POST /api/v1/admin/frontend-plugins/admin/<name>/disable`.
3. Backend resolves the env var, rewrites the file in place.
4. Backend returns `{enabled: false, updated_path: ...}`.
5. fe-admin calls `location.reload()`.
6. On the new boot, the fe-admin Vite dev server / nginx serves the
   updated `plugins.json`; the pluginLoader reads it; the plugin is
   skipped. Every other browser sees the same state on their next
   reload. No localStorage. No per-browser drift.

## Migration from the legacy layout

Before today, each container had its own `plugins.json` bind-mounted
individually (`./backend/plugins.json`, `./fe-admin/plugins.json`,
`./fe-user/plugins.json`) and the fe-admin cached a parallel copy in
`localStorage.vbwd_admin_plugin_state`.

The migration performed by `setup.sh` and the deploy workflow:

1. Create `${VAR_DIR}/plugins/`.
2. Copy `backend/plugins.json` → `backend-plugins.json`, etc. for all
   six files (idempotent — never overwrites an existing file).
3. Rewrite the instance's `docker-compose.yml` from the updated template.
4. Restart containers.

The fe-admin's `pluginLoader` also auto-removes the legacy
`localStorage.vbwd_admin_plugin_state` key on boot and logs a one-time
info message.

## Why not WebSocket push?

Every browser reloads on click. Plugin routes/stores/components register
at boot time and can't cleanly be unmounted mid-session, so a reload is
unavoidable on the tab that clicked. Broadcasting to other tabs is
possible but rarely worth it — toggles are infrequent and the next
person to reload sees the new state.

If there's a future need (multi-admin live dashboards), add a
WebSocket layer on top — the backend already broadcasts domain events
via `event_bus`. The file-on-disk contract stays the same.

## Testing

Backend unit tests live at
`vbwd-backend/tests/unit/routes/test_admin_frontend_plugins.py`.
They cover: GET, 404-unknown-app, 404-unknown-plugin, 401-unauth,
enable/disable round-trip, and response shape. All use `tmp_path` +
`patch(MANIFEST_PATHS, ...)`, no real filesystem dependency.

The fe-admin E2E `plugins-page-plugins.spec.ts` should be updated to
exercise the full reload flow once the backend endpoint is wired into
CI fixtures.
