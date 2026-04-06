# Report 13 — GHRM Plugin Implementation

**Sprint:** 02 — GitHub Repo Manager
**Date:** 2026-03-11
**Status:** Complete — all 23 steps done

---

## Overview

The GHRM (GitHub Repo Manager) plugin adds a self-hosted software catalogue to the vbwd platform. Subscribers with an active tariff plan can connect their GitHub account via OAuth, gain read-only collaborator access to private repositories, and receive personalised install commands (NPM / Pip / Git / Composer). The catalogue itself is public — no auth required to browse.

The plugin spans all three layers of the stack:

| Layer | Scope |
|---|---|
| `vbwd-backend` | Flask plugin with 17 API routes, 4 SQLAlchemy models, 4 repositories, 2 services, APScheduler grace-period job, real `httpx` GitHub client, Alembic migration, `bin/populate_ghrm.py` |
| `vbwd-fe-admin` | `extensionRegistry` extension with `PlanTabSection`, conditional "Software" tab on `PlanForm.vue`, `ghrm-admin` plugin with `GhrmSoftwareTab.vue` |
| `vbwd-fe-user` | `ghrm` plugin with store, API client, 5 routes, 8 components/views, 19 E2E tests |

---

## Architecture Decisions

### 1. TDD-First
Tests written before implementation for both services (`GithubAccessService`, `SoftwarePackageService`). 24 backend unit tests written as failing specs; implementation driven by making them green.

### 2. GitHub Sync via GitHub Action + Server Pull
Sync is triggered by a GitHub Action calling `GET /api/v1/ghrm/sync?package=<slug>&key=<api_key>`. The server then pulls README, CHANGELOG, releases, docs, and screenshots directly from the GitHub API. This avoids any inbound webhooks requiring public IP configuration.

Each package has an auto-generated `sync_api_key` (`secrets.token_urlsafe(32)`) stored as the GitHub Actions secret `VBWD_SYNC_KEY`.

### 3. Liskov-Compliant GitHub Client
`IGithubAppClient` ABC defines the contract. Both `MockGithubAppClient` (test-only, configurable via attributes) and `GithubAppClient` (real, httpx) implement it. Services depend on `IGithubAppClient` only — zero import of the real client in service files.

### 4. Admin Overrides Never Clobbered
`GhrmSoftwareSync` has parallel `cached_*` / `override_*` columns. `sync_package()` updates only `cached_*` columns. `get_package()` returns `override_*` when set, `cached_*` otherwise. This is enforced by unit tests (`test_does_not_overwrite_admin_overrides`).

### 5. `ghrm_` Table Prefix
All 4 tables use the `ghrm_` prefix to avoid collisions in the shared PostgreSQL schema:
- `ghrm_software_package`
- `ghrm_software_sync`
- `ghrm_user_github_access`
- `ghrm_access_log`

### 6. OAuth Security
JWT-encoded state parameter signed with `JWT_SECRET_KEY` + Redis nonce (TTL 10 min) for CSRF protection. After callback, nonce is deleted from Redis.

### 7. Grace Period
`AccessStatus.GRACE` — when a subscription is cancelled, the collaborator is not immediately removed. APScheduler runs a daily cron (`revoke_expired_grace_access`) that removes expired grace-period entries and calls `remove_collaborator` on GitHub. Grace duration is configurable.

### 8. Conditional "Software" Tab in fe-admin
`extensionRegistry` was extended with a new `PlanTabSection` interface. `PlanForm.vue` computes `visiblePlanTabs` by intersecting the plan's assigned category slugs with `requiredCategorySlugs` from each registered tab section. The "Software" tab only appears when the plan belongs to `backend`, `fe-user`, or `fe-admin` categories.

### 9. CMS Integration in fe-user
The GHRM catalogue pages use `CmsLayoutRenderer` and `CmsWidgetRenderer` from the CMS plugin. `bin/populate_ghrm.py` seeds two CMS layouts (`ghrm-catalogue`, `ghrm-package-detail`) and three category pages. The plugin declares `dependencies: ['cms']` in its plugin manifest.

---

## Files Created

### Backend — `vbwd-backend/plugins/ghrm/`

```
plugins/ghrm/
├── __init__.py                          # GhrmPlugin(BasePlugin)
├── config.json                          # Plugin config schema
├── admin-config.json                    # Admin UI config
├── bin/
│   └── populate_ghrm.py                 # Seeds CMS layouts + category pages
├── src/
│   ├── models/
│   │   ├── ghrm_software_package.py     # Package model (sync_api_key auto-generated)
│   │   ├── ghrm_software_sync.py        # Sync model (cached_* + override_* columns)
│   │   ├── ghrm_user_github_access.py   # Access model + AccessStatus constants
│   │   └── ghrm_access_log.py           # Log model + SyncAction constants
│   ├── repositories/
│   │   ├── ghrm_software_package_repo.py
│   │   ├── ghrm_software_sync_repo.py
│   │   ├── ghrm_user_github_access_repo.py  # find_grace_expired(now)
│   │   └── ghrm_access_log_repo.py
│   ├── services/
│   │   ├── github_app_client.py         # IGithubAppClient ABC + MockGithubAppClient
│   │   ├── github_app_client_real.py    # GithubAppClient(httpx)
│   │   ├── github_access_service.py     # OAuth, subscription lifecycle, grace
│   │   └── software_package_service.py  # Catalogue, sync, install instructions
│   ├── routes.py                        # 17 endpoints
│   └── scheduler.py                     # revoke_expired_grace_access()
└── tests/unit/services/
    ├── test_github_access_service.py    # 12 tests
    └── test_software_package_service.py # 12 tests
```

**Alembic migration:** `alembic/versions/20260311_create_ghrm_tables.py`

### Backend API Endpoints (17 routes)

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/api/v1/ghrm/packages` | none | List packages (paginated, filterable) |
| `GET` | `/api/v1/ghrm/packages/<slug>` | none | Package detail (increments download count) |
| `GET` | `/api/v1/ghrm/packages/<slug>/related` | none | Related packages |
| `GET` | `/api/v1/ghrm/packages/<slug>/install-instructions` | JWT | Install commands (requires active subscription) |
| `GET` | `/api/v1/ghrm/sync` | API key | Trigger sync from GitHub |
| `GET` | `/api/v1/ghrm/github/oauth-url` | JWT | Get GitHub OAuth redirect URL |
| `GET` | `/api/v1/ghrm/github/callback` | state JWT | Handle OAuth callback |
| `DELETE` | `/api/v1/ghrm/github/disconnect` | JWT | Disconnect GitHub account |
| `GET` | `/api/v1/ghrm/access-status` | JWT | Get current access status + deploy token |
| `GET` | `/api/v1/admin/ghrm/packages` | admin | List all packages |
| `POST` | `/api/v1/admin/ghrm/packages` | admin | Create package |
| `GET` | `/api/v1/admin/ghrm/packages/<id>` | admin | Get package |
| `PUT` | `/api/v1/admin/ghrm/packages/<id>` | admin | Update package |
| `DELETE` | `/api/v1/admin/ghrm/packages/<id>` | admin | Delete package |
| `POST` | `/api/v1/admin/ghrm/packages/<id>/rotate-key` | admin | Rotate sync API key |
| `POST` | `/api/v1/admin/ghrm/packages/<id>/sync` | admin | Manual sync trigger |
| `GET` | `/api/v1/admin/ghrm/access-log` | admin | Access log |

### fe-admin — Changes and New Files

| File | Change |
|---|---|
| `vue/src/plugins/extensionRegistry.ts` | Added `PlanTabSection` interface + `getPlanTabSections()` |
| `vue/src/views/PlanForm.vue` | Added `visiblePlanTabs` computed + plugin tab bar |
| `plugins/ghrm-admin/index.ts` | New — registers "Software" tab with `requiredCategorySlugs` |
| `plugins/ghrm-admin/src/components/GhrmSoftwareTab.vue` | New — GitHub repo config + sync controls |
| `plugins/ghrm-admin/config.json` | New (schema format) |
| `plugins/ghrm-admin/admin-config.json` | New |

### fe-user — New Plugin Files

```
plugins/ghrm/
├── index.ts                             # ghrmPlugin (named export), 5 routes
├── config.json
├── admin-config.json
└── src/
    ├── api/ghrmApi.ts                   # Typed API client
    ├── stores/useGhrmStore.ts           # Pinia composition store
    ├── views/
    │   ├── GhrmCategoryIndex.vue        # Category listing page
    │   ├── GhrmPackageList.vue          # Package grid
    │   ├── GhrmPackageDetail.vue        # 6-tab detail page
    │   ├── GhrmSearch.vue               # Search page
    │   └── GhrmOAuthCallback.vue        # OAuth callback handler
    └── components/
        ├── GhrmMarkdownRenderer.vue     # Zero-dependency markdown renderer
        ├── GhrmGithubConnectButton.vue  # OAuth initiation button
        └── GhrmInstallInstructions.vue  # Install commands display
```

### E2E Tests

| File | Tests | Coverage |
|---|---|---|
| `vue/tests/e2e/ghrm-lifecycle.spec.ts` | 6 | Connect button, OAuth redirect, callback exchange, active/grace/revoked install tab states |
| `vue/tests/e2e/ghrm-catalogue.spec.ts` | 13 | Public access, package list, card nav, search, detail tabs, version badge, CTA, checkout redirect, related strip |

All E2E tests mock backend responses via `page.route()` — no live server or GitHub app required.

---

## Unit Test Results

### Backend (Docker)
```
24/24 unit tests passing
- test_github_access_service.py: 12/12
- test_software_package_service.py: 12/12
```

### fe-user
All pre-existing unit tests continue to pass. Two bugs fixed during this sprint:

1. **`bin/pre-commit-check.sh` exit code swallowing** — `npx vitest run ... | tail -20` caused `tail`'s exit code (always 0) to be used, masking test failures. Fixed by capturing output to a variable and checking `$?` separately.

2. **`checkout.spec.ts` cart item type casing** — Test mocks used lowercase types (`'plan'`, `'token_bundle'`, `'addon'`) but the store filters by uppercase (`'PLAN'`, `'TOKEN_BUNDLE'`, `'ADD_ON'`). Fixed in the test mocks.

---

## Data Flow Summary

```
GitHub Action (on push to release branch)
  └── GET /api/v1/ghrm/sync?package=<slug>&key=<api_key>
        └── SoftwarePackageService.sync_package(api_key)
              ├── Verify api_key → find package
              ├── GithubAppClient.fetch_readme()
              ├── GithubAppClient.fetch_changelog()
              ├── GithubAppClient.fetch_releases()
              ├── GithubAppClient.fetch_docs()
              ├── GithubAppClient.fetch_screenshots()
              └── GhrmSoftwareSyncRepo.save(sync)
                    └── cached_* fields updated
                        override_* fields untouched

User subscribes to plan with category in ['backend', 'fe-user', 'fe-admin']
  └── on_subscription_created event
        └── GithubAccessService.on_subscription_created(user_id, plan_id)
              └── Create GhrmUserGithubAccess(status=ACTIVE)

User clicks "Connect GitHub"
  └── GET /api/v1/ghrm/github/oauth-url
        └── JWT state + Redis nonce → GitHub OAuth URL
  └── User authorizes → GitHub redirects to /software/github/callback?code=&state=
  └── POST /api/v1/ghrm/github/callback
        └── Validate state JWT + Redis nonce
        └── GithubAppClient.exchange_code(code) → github_token
        └── GithubAppClient.get_user(token) → github_username
        └── GithubAppClient.add_collaborator(owner, repo, username)
        └── Save github_token + github_username to GhrmUserGithubAccess
        └── Log SyncAction.ADD_COLLABORATOR

User cancels subscription
  └── on_subscription_cancelled event
        └── AccessStatus → GRACE (grace_expires_at = now + grace_days)

APScheduler daily cron
  └── GhrmUserGithubAccessRepo.find_grace_expired(now)
        └── For each: GithubAppClient.remove_collaborator()
        └── AccessStatus → REVOKED
        └── Log SyncAction.REMOVE_COLLABORATOR
```

---

## Configuration

### Backend `plugins/config.json` entry
```json
{
  "software_category_slugs": ["backend", "fe-user", "fe-admin"],
  "software_detail_cms_layout_slug": "ghrm-package-detail",
  "grace_period_days": 7,
  "github_app_id": "",
  "github_private_key_path": ""
}
```

### fe-user `plugins/ghrm/config.json`
```json
{
  "catalogue_route_prefix": { "type": "string", "default": "/software" },
  "packages_per_page": { "type": "number", "default": 20 },
  "related_packages_limit": { "type": "number", "default": 4 },
  "show_in_nav": { "type": "boolean", "default": true }
}
```

---

## Known Limitations / Future Work

- **Screenshots tab** is wired to display `sync.cached_screenshots` (from GitHub `docs/screenshots/`) merged with `sync.admin_screenshots` (CMS uploads). The admin upload UI for screenshots is not yet implemented in `GhrmSoftwareTab.vue` — currently read-only.
- **Documentation tab** renders `sync.override_docs ?? sync.cached_docs` as markdown. Docs synced from GitHub `docs/` folder are the single markdown file at `docs/README.md` — multi-file docs navigation is a future enhancement.
- **Composer support** — the install instructions service returns `composer: null` for now; detection logic (checking for `composer.json` in the repo root) can be added to the sync step.
- **E2E tests against live stack** — the current E2E suite mocks all API responses. A separate `--integration` E2E suite running against a real backend + test GitHub App is a future step.
