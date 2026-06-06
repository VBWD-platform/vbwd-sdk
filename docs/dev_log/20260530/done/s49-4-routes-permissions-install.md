# Sprint 49.4 — Routes, permission taxonomy, install instructions

**Parent:** [s49-ghrm-collaborator-lifecycle.md](s49-ghrm-collaborator-lifecycle.md) · **Decisions:** D5, D2, D3, D6
**Status:** READY · **Area:** `plugins/ghrm` (`src/routes.py`)
**Depends on:** **S49.3** (service surface). **Blocks:** S49.5 (tab consumes `/access` shape).

## Engineering requirements (BINDING)
TDD-first · SOLID · DI · DRY · clean code · NO OVERENGINEERING. Guard: `--plugin ghrm --full` green. See [`_engineering_requirements.md`](_engineering_requirements.md).

## Goal
Expose the rewritten service correctly: fix the **permission taxonomy mismatch** (D5), make `GET /access` return per-package membership + lazily verify acceptance (D2), and turn install instructions into **fine-grained-PAT guidance** (D3). No new endpoints beyond what the flow needs (no-overengineering).

## Changes

### Permission taxonomy (D5) — align routes to the **declared** `admin_permissions`
Declared in `__init__.py`: `ghrm.packages.view|manage`, `ghrm.access.view|manage`, `ghrm.configure`. Re-map the admin routes (currently `ghrm.repos.*`, undeclared):
| Route | New permission |
|---|---|
| `GET/POST/PUT/DELETE /admin/ghrm/packages…`, `…/rotate-key`, `…/sync`, `…/preview/<f>`, `…/sync/<f>` | `ghrm.packages.view` (reads) / `ghrm.packages.manage` (writes) |
| `GET /admin/ghrm/access-log`, `POST /admin/ghrm/access/sync/<user_id>` | `ghrm.access.view` / `ghrm.access.manage` |
| `GET/PUT /admin/ghrm/widgets…` | `ghrm.packages.view` / `ghrm.packages.manage` |

### `GET /api/v1/ghrm/access` (user)
- Call `verify_acceptance(g.user_id)` (lazy promote INVITED→ACTIVE, D2), then return `{connected, github_username, memberships: [{package_slug, package_name, status, invited_at, grace_expires_at, last_error?}]}`.
- `GithubNotConfiguredError` → `{connected: False}` (200) as today.

### `GET /api/v1/ghrm/packages/<slug>/install` (D3)
- Resolve the user's membership for the package:
  - `ACTIVE` → return PAT guidance: steps to create a **fine-grained PAT** (`Contents: read` on `owner/repo`) + `git clone https://<USERNAME>:<PAT>@github.com/owner/repo.git` and an SSH alternative.
  - `INVITED` → 200 with `{state: "invited", message: "Accept your GitHub invitation first", invitations_url}`.
  - none/REVOKED → `GhrmSubscriptionRequiredError` → 403.
- Drop the `deploy_token` plumbing from the route (it no longer exists, D3).

### Callback / errors (D6)
- Keep the OAuth callback returning identity on success; **do not** add a callback warning field (D6 chose status surfacing, not callback warnings). Failures show up as `ERROR` memberships via `/access`.

## TDD plan (tests FIRST — integration with `db` + auth harness)
- **Permissions:** admin with `ghrm.packages.manage` only → can create a package but `POST /admin/ghrm/access/sync/<u>` → 403; admin with `ghrm.access.manage` only → reverse. Superadmin → all.
- **`/access`:** connected user with one INVITED membership where `is_collaborator` now True → response shows `ACTIVE` (lazy verify ran); ERROR membership surfaces `last_error`.
- **Install:** ACTIVE → PAT+clone instructions present (assert the clone URL + PAT step); INVITED → "accept invitation"; none → 403.

## Implementation steps
1. Write failing permission + `/access` + install tests.
2. Re-map `@require_permission` strings; wire `verify_acceptance` into `/access`; rewrite install payload.
3. `--plugin ghrm --full` green.

## Definition of done
Admin endpoints gate on the declared `ghrm.packages.*`/`ghrm.access.*` (no `ghrm.repos.*` left); `/access` returns per-package status and self-heals INVITED→ACTIVE; install returns PAT+clone guidance per membership state; `--plugin ghrm --full` green.
