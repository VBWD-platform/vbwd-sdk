# Sprint 02 — GitHub Repo Manager (GHRM) Plugin

**Date:** 2026-03-02
**Dependencies:**
- Backend: `cms` plugin (backend)
- fe-user: `cms` plugin (fe-user), `theme-switcher` plugin (fe-user), `checkout` plugin (fe-user)
- fe-admin: `cms` plugin (fe-admin), `theme-switcher` plugin (fe-admin)

---

## Core Requirements

### TDD-First
Every class is written test-first. No production code exists before a failing test demands it.
Tests live in `plugins/ghrm/tests/unit/` (no DB) and `tests/integration/` (real DB, mock GitHub client).

### SOLID
- **Single Responsibility** — each service/repository does one thing; sync logic, access control, and catalogue browsing are separate services
- **Open/Closed** — `IGithubAppClient` interface allows swapping real vs mock client without touching service code
- **Liskov Substitution** — `MockGithubAppClient` is a full drop-in for `GithubAppClient` in all tests
- **Interface Segregation** — repository interfaces expose only the methods their consumers need
- **Dependency Inversion** — services depend on interfaces (`ISoftwarePackageRepository`, `IGithubAppClient`), never on concrete classes

### Dependency Injection
All service dependencies are injected via constructor. No `import`-time instantiation of DB sessions, GitHub clients, or config values inside service methods.

### Liskov Substitution (expanded)
`MockGithubAppClient` must satisfy every contract of `IGithubAppClient`:
same method signatures, same return types, same exception types on failure.
Tests must pass with either implementation without modification.

### DRY
Shared DTOs, pagination helpers, and error classes live in `plugins/ghrm/src/` and are reused across services, routes, and tests. No copy-pasted validation or serialisation logic.

### Clean Code
- Methods ≤ 50 lines; single abstraction level per method
- No magic strings — use constants or enums (`AccessStatus`, `SyncAction`)
- All public methods have docstrings
- Routes contain no business logic — delegate to services immediately

---

## Testing Approach

Each sub-project has `bin/pre-commit-check.sh` with selectable scopes via arguments.
Run the narrowest scope during development; run full before committing.

### Backend (`vbwd-backend`)

```bash
bin/pre-commit-check.sh          # default: lint + unit tests only
bin/pre-commit-check.sh --full   # lint + unit + integration tests (requires running DB)
```

| Scope | What runs |
|---|---|
| _(default)_ | black, flake8, mypy, pytest unit |
| `--full` | all of the above + pytest integration (real PostgreSQL, `MockGithubAppClient`) |

### Frontend (`vbwd-fe-admin`, `vbwd-fe-user`)

```bash
bin/pre-commit-check.sh --unit          # Vitest unit tests only
bin/pre-commit-check.sh --style         # ESLint + type-check
bin/pre-commit-check.sh --integration   # Playwright component/integration tests
bin/pre-commit-check.sh --user          # fe-user E2E tests (Playwright, port 8080)
bin/pre-commit-check.sh --admin         # fe-admin E2E tests (Playwright, port 8081)
```

Arguments are combinable:

```bash
bin/pre-commit-check.sh --unit --style                    # fast pre-commit
bin/pre-commit-check.sh --unit --style --integration      # CI default
bin/pre-commit-check.sh --unit --style --user --admin     # full E2E run
```

---

## Overview

A software catalogue where each software package maps to a tariff plan. The catalogue is public (no login required). Active subscribers are granted access to a protected branch of the package's GitHub repo. Access is revoked (with grace period) on subscription cancellation or payment failure.

Split across:
- **Backend plugin** — GitHub App integration, collaborator lifecycle, models, migrations, sync API
- **fe-user plugin** — CMS-compatible software catalogue (list + detail pages)
- **fe-admin plugin** — extends the tariff plan edit page with a "Software" tab

---

## Architecture Decisions

| Concern | Decision |
|---|---|
| GitHub App auth | GitHub App (per-installation token, fine-grained repo permissions) |
| GitHub user identity | **GitHub OAuth** — verified via OAuth callback, not manual entry |
| Repo model | Public repo + protected `release` branch (collaborator gets access) |
| Access revocation | Grace period before removal (matches plan `trailing_days`) |
| Package managers | npm, composer, pip, git — all supported |
| Related software | Manually curated by admin (related packages per package) |
| Software categories | One or more tariff plan categories marked as "software" in plugin settings |
| Catalogue visibility | Public — no login required to browse packages |
| CMS integration | fe-user uses CMS renderer and CMS layouts/widgets for all catalogue pages |
| fe-admin integration | Extends tariff plan edit with "Software" tab (conditional on category) |
| GitHub data sync | Triggered by GitHub Action on tag push → server pulls from GitHub API |
| Sync auth | Auto-generated API key per package (stored as GitHub Action secret) |
| Cached GitHub data | README, CHANGELOG, releases, screenshots stored in DB; admin can override |
| Detail page layout | One global CMS layout defined in GHRM plugin settings (applies to all packages) |

---

## Access Control Design

### Why public repo + protected branch?

```
Public repo:
  main branch    → open source, anyone can read
  release branch → protected, only collaborators can pull tagged releases

Subscriber gets:
  - Added as collaborator with read access to release branch
  - Can pull/clone specific release tags via any package manager

Non-subscriber sees:
  - Public repo (main branch only)
  - Cannot pull release tags
  - Can browse catalogue (no login required)
```

### Package Manager Integration

Each package detail page shows install instructions per manager for active subscribers:

```bash
# npm
npm install git+https://<github-token>@github.com/owner/repo.git#release

# composer
composer require owner/package:dev-release --prefer-source

# pip
pip install git+https://<github-token>@github.com/owner/repo.git@release

# git
git clone -b release https://<github-token>@github.com/owner/repo.git
```

The `<github-token>` is a **scoped deploy token** generated per user via GitHub App.
Tokens are stored encrypted in `user_github_access` and rotated on renewal.

Each version entry in the versions list also shows:
- Direct GitHub release asset download URLs (`.zip` / `.tar.gz`)
- Package manager install commands scoped to that specific version tag

---

## GitHub Data Sync Flow

```
New version tag pushed to GitHub
    │
    ▼
GitHub Action runs:
  curl "https://<vbwd-host>/api/v1/ghrm/sync?package=<tarif-plan-slug>&key=<api-key>"
    │
    ▼
Backend GHRM plugin verifies API key → finds software_package record
    │
    ▼
Server pulls from GitHub API (using GitHub App token):
  - Latest release tag name, date, release notes
  - All releases list (tag, date, notes summary)
  - README.md (overview content)
  - CHANGELOG.md (if exists)
  - docs/README.md (documentation)
  - docs/screenshots/ (image list)
    │
    ▼
Updates ghrm_software_sync record:
  - cached_readme, cached_changelog, cached_docs, cached_releases, cached_screenshots
  - last_synced_at = now()
    │
    ▼
Admin-overridden fields are NOT overwritten (override_readme, override_changelog, etc.)
```

**API key lifecycle:**
- Auto-generated when software_package is created in admin
- Shown in "Software" tab of tariff plan edit (read-only + copy)
- Added manually by developer as `VBWD_SYNC_KEY` GitHub Action secret
- Rotatable via "Regenerate Key" button (invalidates old key immediately)

---

## Backend Plugin

### Models & Migrations

#### `ghrm_software_package`
```
id                  UUID PK
tariff_plan_id      UUID FK → tarif_plan UNIQUE NOT NULL
name                VARCHAR(255) NOT NULL
slug                VARCHAR(64) UNIQUE NOT NULL
author_name         VARCHAR(255)
icon_url            VARCHAR(512)             -- CMS image URL (admin-uploaded)
github_owner        VARCHAR(128) NOT NULL    -- GitHub org or user
github_repo         VARCHAR(128) NOT NULL    -- repository name
github_protected_branch  VARCHAR(64) DEFAULT 'release'
github_installation_id   VARCHAR(64)        -- GitHub App installation ID
sync_api_key        VARCHAR(128) NOT NULL    -- auto-generated, used by GitHub Action
tech_specs          JSONB                    -- arbitrary key/value pairs
related_slugs       JSONB                    -- manually curated list of package slugs
download_counter    INT DEFAULT 0
is_active           BOOLEAN DEFAULT TRUE
sort_order          INT DEFAULT 0
created_at          TIMESTAMP
updated_at          TIMESTAMP

UNIQUE(github_owner, github_repo)
```

#### `ghrm_software_sync`
```
id                      UUID PK
software_package_id     UUID FK → ghrm_software_package UNIQUE NOT NULL
latest_version          VARCHAR(64)           -- latest tag name
latest_released_at      TIMESTAMP

-- Cached from GitHub (overwritten on each sync)
cached_readme           TEXT                  -- raw markdown from README.md
cached_changelog        TEXT                  -- raw markdown from CHANGELOG.md
cached_docs             TEXT                  -- raw markdown from docs/README.md
cached_releases         JSONB                 -- [{tag, date, notes, assets:[{name,url}]}]
cached_screenshots      JSONB                 -- [{url, caption}] from docs/screenshots/

-- Admin overrides (NULL = use cached; non-NULL = use this instead)
override_readme         TEXT
override_changelog      TEXT
override_docs           TEXT

-- Admin-uploaded screenshots (merged with cached_screenshots on render)
admin_screenshots       JSONB                 -- [{cms_image_url, caption}]

last_synced_at          TIMESTAMP
created_at              TIMESTAMP
updated_at              TIMESTAMP
```

#### `ghrm_user_github_access`
```
id                  UUID PK
user_id             UUID FK → user UNIQUE
github_username     VARCHAR(128) NOT NULL   -- verified via OAuth, never manual
github_user_id      VARCHAR(32) NOT NULL    -- GitHub numeric user ID (immutable)
oauth_token         TEXT                    -- encrypted OAuth access token
oauth_scope         VARCHAR(256)            -- scopes granted (e.g. "read:user")
deploy_token        TEXT                    -- encrypted, scoped GitHub deploy token
token_expires_at    TIMESTAMP
access_status       VARCHAR(32)             -- active | grace | revoked
grace_expires_at    TIMESTAMP               -- NULL if not in grace period
last_synced_at      TIMESTAMP
created_at          TIMESTAMP
updated_at          TIMESTAMP
```

> **Why store `github_user_id`?** GitHub usernames can be renamed. The numeric
> `github_user_id` is permanent and is used as the stable identity key when
> calling the collaborator API. `github_username` is kept for display only.

#### `ghrm_access_log`
```
id              UUID PK
user_id         UUID FK → user
package_id      UUID FK → ghrm_software_package
action          VARCHAR(32)     -- add_collaborator | remove_collaborator | grace_started | token_rotated
triggered_by    VARCHAR(64)     -- subscription_event | manual | scheduler | sync
subscription_id UUID FK → subscription (nullable)
meta            JSONB
created_at      TIMESTAMP
```

---

### Repository Layer (DI interfaces)

```
ISoftwarePackageRepository
  find_by_slug(slug) → GhrmSoftwarePackage
  find_by_tariff_plan_id(plan_id) → GhrmSoftwarePackage | None
  find_all(page, per_page, category_slug, query) → PaginatedResult
  find_by_slugs(slugs) → List[GhrmSoftwarePackage]
  save(package) → GhrmSoftwarePackage
  delete(id) → None
  increment_downloads(slug) → None
  find_by_sync_key(api_key) → GhrmSoftwarePackage | None

ISoftwareSyncRepository
  find_by_package_id(package_id) → GhrmSoftwareSync | None
  save(sync) → GhrmSoftwareSync

IGhrmUserGithubAccessRepository
  find_by_user_id(user_id) → GhrmUserGithubAccess | None
  find_grace_expired(now) → List[GhrmUserGithubAccess]
  save(access) → GhrmUserGithubAccess
  delete(id) → None

IGhrmAccessLogRepository
  log(user_id, package_id, action, triggered_by, meta) → None
  find_by_user(user_id, page, per_page) → PaginatedResult
```

---

### Service Layer

```
IGithubAppClient                           -- DI interface
  add_collaborator(owner, repo, username, branch) → bool
  remove_collaborator(owner, repo, username) → bool
  create_deploy_token(owner, repo, username) → str
  revoke_deploy_token(token) → None
  get_installation_token(installation_id) → str
  fetch_readme(owner, repo) → str                        -- raw markdown
  fetch_changelog(owner, repo) → str | None              -- raw markdown or None
  fetch_docs_readme(owner, repo) → str | None            -- docs/README.md or None
  fetch_releases(owner, repo) → List[ReleaseDTO]         -- [{tag, date, notes, assets}]
  fetch_screenshot_urls(owner, repo) → List[str]         -- docs/screenshots/ file URLs

GithubAppClient(IGithubAppClient)          -- real implementation (PyGithub / httpx)

MockGithubAppClient(IGithubAppClient)      -- test double


SoftwarePackageService(
    package_repo: ISoftwarePackageRepository,
    sync_repo: ISoftwareSyncRepository,
    github: IGithubAppClient,
    software_category_slugs: List[str]     -- from plugin config
)
  list_packages(params) → PaginatedResult[SoftwarePackageDTO]
  get_package(slug) → SoftwarePackageDTO             -- merged cached + override fields
  get_related(slug) → List[SoftwarePackageDTO]
  get_versions(slug) → List[VersionDTO]              -- from cached_releases
  get_install_instructions(slug, user_id) → InstallInstructionsDTO
  sync_package(api_key) → SoftwareSyncDTO            -- called by sync endpoint


GithubAccessService(
    access_repo: IGhrmUserGithubAccessRepository,
    log_repo: IGhrmAccessLogRepository,
    package_repo: ISoftwarePackageRepository,
    github: IGithubAppClient
)
  # Called by subscription event handlers
  on_subscription_activated(user_id, plan_id) → None
  on_subscription_cancelled(user_id, plan_id) → None
  on_subscription_payment_failed(user_id, plan_id) → None
  on_subscription_renewed(user_id, plan_id) → None

  # Grace period scheduler (called by cron)
  revoke_expired_grace_access() → int      -- returns count revoked

  # OAuth flow
  get_oauth_url(user_id, redirect_uri) → str          -- builds github.com/login/oauth/authorize URL
  handle_oauth_callback(user_id, code, state) → GhrmUserGithubAccessDTO
    # 1. POST github.com/login/oauth/access_token → oauth_token
    # 2. GET api.github.com/user → github_username, github_user_id
    # 3. Upsert user_github_access (username + user_id + oauth_token)
    # 4. If user has active subscription → add_collaborator for all their packages

  disconnect_github(user_id) → None                   -- revoke token, remove collaborator, clear row

  # User-facing
  get_access_status(user_id) → GhrmUserGithubAccessDTO
  get_install_token(user_id, package_slug) → str
```

---

### Subscription Event Wiring

The backend plugin hooks into the existing vbwd event system:

```python
# plugin on_enable():
event_dispatcher.subscribe('subscription.activated',      github_access_service.on_subscription_activated)
event_dispatcher.subscribe('subscription.cancelled',      github_access_service.on_subscription_cancelled)
event_dispatcher.subscribe('subscription.payment_failed', github_access_service.on_subscription_payment_failed)
event_dispatcher.subscribe('subscription.renewed',        github_access_service.on_subscription_renewed)
```

### Grace Period Flow

```
subscription.cancelled / payment_failed
    ↓
GithubAccessService.on_subscription_cancelled()
    ↓
access_status = 'grace'
grace_expires_at = now + plan.trailing_days
log(action='grace_started')
    ↓
Scheduler (daily cron) → revoke_expired_grace_access()
    ↓
  IF grace_expires_at < now:
    github.remove_collaborator(owner, repo, username)
    github.revoke_deploy_token(token)
    access_status = 'revoked'
    log(action='remove_collaborator')
```

---

### GitHub OAuth Flow

```
User clicks "Connect GitHub" (GhrmGithubConnectButton)
  │
  ▼
GET /api/v1/ghrm/auth/github  (backend, requires_auth)
  │  Builds URL:
  │    https://github.com/login/oauth/authorize
  │      ?client_id=<oauth_client_id>
  │      &redirect_uri=<oauth_redirect_uri>
  │      &scope=read:user
  │      &state=<signed JWT: user_id + nonce>   ← CSRF protection
  │
  ▼ 302 redirect → github.com
  │
  ▼ User approves → github.com redirects to:
GET /ghrm/auth/github/callback  (fe-user route, no layout)
  │  Reads ?code=<code>&state=<state> from URL
  │  POSTs them to backend:
  │
  ▼
POST /api/v1/ghrm/auth/github/callback  (backend, requires_auth)
  │  1. Verify state JWT (user_id + nonce) → CSRF guard
  │  2. POST github.com/login/oauth/access_token → oauth_token
  │  3. GET api.github.com/user → { login, id }
  │  4. Upsert user_github_access:
  │       github_username = login
  │       github_user_id  = id        (stable, rename-proof)
  │       oauth_token     = encrypted(token)
  │  5. If user has active subscription:
  │       add_collaborator for each subscribed package repo
  │
  ▼ 200 { username, access_status }
  │
fe-user callback page → redirect to /dashboard/settings#github
```

**State parameter (CSRF):** Signed with `JWT_SECRET_KEY`, contains `user_id` and a
one-time `nonce` stored in Redis with 10-minute TTL. Callback verifies signature +
nonce presence before proceeding.

---

### API Endpoints

```
# Public sync (called by GitHub Action — no user auth, API key auth)
GET  /api/v1/ghrm/sync                            trigger sync (?package=slug&key=api_key)

# Public catalogue (no auth required)
GET  /api/v1/ghrm/packages                        list (paginated, category_slug, search)
GET  /api/v1/ghrm/packages/<slug>                 package detail (merged cached+override)
GET  /api/v1/ghrm/packages/<slug>/related         related packages
GET  /api/v1/ghrm/packages/<slug>/versions        versions list (from cached_releases)

# Subscriber-only
GET  /api/v1/ghrm/packages/<slug>/install         install instructions (active sub required)

# GitHub OAuth (user profile)
GET  /api/v1/ghrm/auth/github                     redirect to github.com/login/oauth/authorize
POST /api/v1/ghrm/auth/github/callback            exchange code, store verified username
DELETE /api/v1/ghrm/auth/github                   disconnect GitHub (revoke token + access)

# User profile
GET  /api/v1/ghrm/access                          current user's github access status

# Admin
GET  /api/v1/admin/ghrm/packages                  list all packages
POST /api/v1/admin/ghrm/packages                  create (auto-generates sync_api_key)
PUT  /api/v1/admin/ghrm/packages/<id>             update (name, author, icon, related_slugs, overrides)
DEL  /api/v1/admin/ghrm/packages/<id>             delete
POST /api/v1/admin/ghrm/packages/<id>/rotate-key  regenerate sync_api_key
POST /api/v1/admin/ghrm/packages/<id>/sync        manual sync trigger (server pulls from GitHub)
GET  /api/v1/admin/ghrm/access-log                audit log (paginated)
POST /api/v1/admin/ghrm/access/sync/<user_id>     manual access sync for a user
```

---

### Plugin Config (`plugins/config.json`)

```json
{
  "ghrm": {
    "github_app_id": "12345",
    "github_app_private_key_path": "/app/plugins/ghrm/github-app.pem",
    "github_installation_id": "67890",
    "github_oauth_client_id": "Ov23liXXXXXXXXX",
    "github_oauth_client_secret": "secret",
    "github_oauth_redirect_uri": "http://localhost:8080/ghrm/auth/github/callback",
    "software_category_slugs": ["backend", "fe-user", "fe-admin"],
    "software_detail_cms_layout_slug": "ghrm-software-detail",
    "grace_period_fallback_days": 7
  }
}
```

---

### Tests (TDD — write first)

```
tests/unit/services/
  test_software_package_service.py
    - test_list_filters_by_category_slug
    - test_get_package_merges_cached_and_override_readme
    - test_get_package_uses_cached_readme_when_no_override
    - test_get_package_increments_download_counter
    - test_get_install_instructions_requires_active_subscription
    - test_get_related_returns_curated_list
    - test_sync_package_verifies_api_key
    - test_sync_package_pulls_and_stores_github_data
    - test_sync_does_not_overwrite_admin_overrides

  test_github_access_service.py
    - test_handle_oauth_callback_stores_verified_username_and_user_id
    - test_handle_oauth_callback_adds_collaborator_if_active_subscription
    - test_handle_oauth_callback_raises_on_github_api_error
    - test_disconnect_revokes_token_and_removes_collaborator
    - test_on_activation_adds_collaborator_when_github_connected
    - test_on_activation_skips_when_github_not_connected
    - test_on_cancellation_sets_grace_status
    - test_on_cancellation_uses_plan_trailing_days
    - test_revoke_expired_removes_collaborator_and_token
    - test_on_renewal_extends_access_and_rotates_token
    - test_payment_failed_starts_grace_period

tests/unit/repositories/
  test_software_package_repository.py
  test_ghrm_user_github_access_repository.py

tests/integration/
  test_ghrm_packages_api.py
  test_ghrm_access_api.py
  test_ghrm_sync_api.py
  test_github_access_service_integration.py  -- uses MockGithubAppClient
```

---

### `bin/populate_ghrm.py`

Creates demo data and CMS structures needed for the catalogue to work out of the box:

```
CMS Layouts:
  - ghrm-category-list   (layout for /category/<slug>)
  - ghrm-software-detail (layout for /category/<slug>/<package-slug>)

CMS Widgets:
  - ghrm-software-list   (HTML widget embedding the fe-user package list component)
  - ghrm-software-detail-content (HTML widget embedding the fe-user detail component)

CMS Pages:
  - /category/backend    (uses ghrm-category-list layout, ghrm-software-list widget)
  - /category/fe-user    (uses ghrm-category-list layout, ghrm-software-list widget)
  - /category/fe-admin   (uses ghrm-category-list layout, ghrm-software-list widget)

Demo software packages (tied to demo tariff plans if present):
  - vbwd-cms    (slug: vbwd-cms, category: fe-admin)
  - vbwd-taro   (slug: vbwd-taro, category: fe-user)
```

---

## fe-admin Plugin

### What it does

Extends the standard tariff plan edit page with a **"Software" tab**. The tab is
conditionally rendered: it appears only when the tariff plan belongs to a category
that is marked as "software" in the GHRM plugin settings
(`software_category_slugs`), or any parent category is so marked.

### "Software" Tab Fields

```
GitHub Repo URL      text input  "owner/repo" format (e.g. vbwd/vbwd-cms)
Author / Maintainer  text input  Display name shown on detail page
Software Icon        image upload  (uses CMS image upload, stored as CMS image URL)
Sync API Key         read-only text + copy button + "Regenerate" button
                     → shown once package record exists in backend
Last Synced          read-only timestamp (from ghrm_software_sync.last_synced_at)
Sync Now button      → POST /api/v1/admin/ghrm/packages/<id>/sync
```

### Theme

The fe-admin GHRM plugin is **theme-switcher compatible** — follows the same
appearance tokens as all other admin panels.

---

## fe-user Plugin

### CMS Integration

The fe-user GHRM plugin is **CMS-compatible**:
- Uses the same `CmsLayoutRenderer` + `CmsWidgetRenderer` from the CMS plugin
- Catalogue pages (`/category/<slug>`) render a CMS layout chosen by the page content
- Software detail pages (`/category/<slug>/<package-slug>`) render the global CMS layout
  defined in `software_detail_cms_layout_slug` plugin setting
- All CMS widget styles apply — source_css defined in widgets affects GHRM pages too
- Catalogue is public (no authentication required)

### Routes

```
/category                               GhrmCategoryIndex.vue
/category/:category_slug                GhrmPackageList.vue       (rendered inside CMS layout)
/category/:category_slug/:package_slug  GhrmPackageDetail.vue     (rendered inside CMS layout)
/search                                 GhrmSearch.vue
/ghrm/auth/github/callback              GhrmOAuthCallback.vue     (no layout)
```

### Components

```
GhrmCategoryIndex.vue
  - Grid of category cards (from plugin config software_category_slugs)
  - Each card → /category/:slug

GhrmPackageList.vue
  - Toggle: list view ↔ card/grid view
  - Sortable columns: name, downloads, updated_at
  - Pagination + quicksearch within category
  - Each row/card → package detail page
  - "Get Package" CTA → checkout plugin (if not subscribed)
  - Uses CmsLayoutRenderer for page chrome

GhrmPackageDetail.vue
  Header area (always visible):
    Software icon | Name | Author | Latest version badge | GitHub link

  Tabbed content:
    Tab 1 — Overview
      Renders: override_readme ?? cached_readme (markdown → HTML)
    Tab 2 — Screenshots
      Renders: admin_screenshots merged with cached_screenshots (gallery)
    Tab 3 — Changelog
      Renders: override_changelog ?? cached_changelog (markdown → HTML)
              + GitHub Releases list (tag, date, notes summary)
    Tab 4 — Documentation
      Renders: override_docs ?? cached_docs (markdown → HTML, from docs/README.md)
    Tab 5 — Versions
      Table: tag name | release date | notes summary | download links
        Each row: GitHub asset URLs (.zip, .tar.gz)
                  + package manager commands for that version tag
    Tab 6 — Install  (visible only to active subscribers)
      Shows deploy token (copy button)
      Shows generic install commands (npm / composer / pip / git) using deploy token

  Below tabs:
    Related Software — horizontally scrollable card strip (manually curated)

  Non-subscriber CTA:
    "Get Package" button → checkout plugin with tariff_plan_id

GhrmSearch.vue
  - Global search across all packages (name, description, slug)
  - List view of results (same card/row as GhrmPackageList)

GhrmGithubConnectButton.vue    -- embedded in user profile settings page
  State A — not connected:
    "Connect GitHub" button → GET /api/v1/ghrm/auth/github (server redirects to OAuth)
  State B — connected:
    "Connected as @username ✓" + access_status badge (active | grace | revoked)
    "Disconnect" link → DELETE /api/v1/ghrm/auth/github

GhrmOAuthCallback.vue          -- /ghrm/auth/github/callback (no layout)
  Reads ?code=&state= from URL
  POSTs to POST /api/v1/ghrm/auth/github/callback
  On success → redirect to /dashboard/settings#github
  On error   → redirect to /dashboard/settings?github_error=1
```

### Store (`useGhrmStore`)

```typescript
state: {
  categories: Category[]
  packages: PaginatedResult<SoftwarePackage>
  currentPackage: SoftwarePackageDetail | null   // includes sync data (readme, changelog, etc.)
  relatedPackages: SoftwarePackage[]
  versions: VersionEntry[]                        // [{tag, date, notes, assets, installCmds}]
  searchResults: PaginatedResult<SoftwarePackage>
  installInstructions: InstallInstructions | null
  accessStatus: GhrmUserGithubAccessStatus | null
  loading: boolean
  error: string | null
}
actions:
  fetchCategories()
  fetchPackages(categorySlug, params)
  fetchPackage(categorySlug, packageSlug)
  fetchRelated(packageSlug)
  fetchVersions(packageSlug)
  fetchInstallInstructions(packageSlug)
  search(query, params)
  fetchAccessStatus()
```

---

## Implementation Order (TDD)

```
Backend:
1.  Write failing tests for GithubAccessService (mock GitHub client + mock OAuth)
2.  Write failing tests for SoftwarePackageService (mock GitHub client, sync logic)
3.  Implement models + migrations:
      ghrm_software_package, ghrm_software_sync, ghrm_user_github_access, ghrm_access_log
4.  Implement MockGithubAppClient (test double — includes fetch_readme, fetch_releases, etc.)
5.  Implement GithubAppClient (real — PyGithub + httpx)
6.  Implement repositories
7.  Implement GithubAccessService (OAuth + subscription handlers + grace) → tests go green
8.  Implement SoftwarePackageService (list, get, sync, versions, install) → tests go green
9.  Wire subscription event handlers in plugin on_enable()
10. Implement grace period scheduler (cron / APScheduler)
11. Implement sync endpoint: GET /api/v1/ghrm/sync
12. Implement OAuth endpoints (GET/POST auth/github, DELETE auth/github)
13. Implement public catalogue endpoints (packages, versions, install)
14. Implement admin endpoints (CRUD, rotate-key, manual sync, access-log)
15. bin/populate_ghrm.py (layouts, widgets, pages, demo packages)

fe-admin:
16. GhrmSoftwareTab.vue — conditional tab on tariff plan edit page
      Fields: github_owner/repo, author, icon, sync_api_key, last_synced, sync now

fe-user:
17. useGhrmStore (Pinia) + API client
18. GhrmCategoryIndex + GhrmPackageList (list + card mode, CMS layout wrapper)
19. GhrmPackageDetail (header + 6 tabs + related strip + CTA)
20. GhrmSearch
21. GhrmGithubConnectButton + GhrmOAuthCallback route

E2E:
22. subscribe → connect GitHub (OAuth) → view install token → cancel → grace → revoke
23. public: browse catalogue without login → see packages → click "Get Package" → redirect to checkout
```
