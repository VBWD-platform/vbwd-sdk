# Sprint 49.1 — GHRM per-(user,package) membership model

**Parent:** [s49-ghrm-collaborator-lifecycle.md](s49-ghrm-collaborator-lifecycle.md) · **Decision:** D7 (+ D3 token removal)
**Status:** READY · **Area:** `plugins/ghrm` (model + repository + migration)
**Depends on:** nothing. **Blocks:** S49.3 (service writes memberships).

## Engineering requirements (BINDING)
TDD-first · SOLID · **Liskov** · DI · DRY · clean code · NO OVERENGINEERING. Guard: `--plugin ghrm --full` green; migration validated **up/down/up**. Schema only via Alembic ([[feedback_migrations_only]]); migration lives in the plugin ([[feedback_plugin_migrations_in_plugin]]); table follows S43 naming `ghrm_<model>`. See [`_engineering_requirements.md`](_engineering_requirements.md).

## Goal
Track collaborator state **per user × package** so a user owning two packages can be `ACTIVE` on one repo and `INVITED` on another, and so failures are recorded per repo. Keep `GhrmUserGithubAccess` as the identity/OAuth record only.

## Data model

### New — `plugins/ghrm/src/models/ghrm_repo_membership.py`
`class GhrmRepoMembership(BaseModel)` → table **`ghrm_repo_membership`**:
| field | type | notes |
|---|---|---|
| `user_id` | UUID | FK→user (DB-level) |
| `package_id` | UUID | FK→`ghrm_software_package.id` |
| `status` | enum `MembershipStatus` | `INVITED \| ACTIVE \| GRACE \| REVOKED \| ERROR` |
| `invitation_id` | str? | GitHub invitation id while pending |
| `invited_at` | datetime? | when the PUT succeeded |
| `grace_expires_at` | datetime? | set on cancel/payment-fail |
| `last_error` | str? | populated when `status=ERROR` |

- Unique constraint `(user_id, package_id)`.
- `to_dict()` — explicit fields + `isoformat()` timestamps + the package slug/name (join or carry) for the fe-user tab.
- `MembershipStatus` enum in the model module (or `models/enums.py` within the plugin).

### Changed — `plugins/ghrm/src/models/ghrm_user_github_access.py`
- **Remove** collaborator-state fields now owned by membership: `deploy_token` (D3), and the per-user `access_status`/`grace_expires_at` collaborator semantics. Keep identity: `github_username`, `github_user_id`, `oauth_token` (EncryptedString), `oauth_scope`.
- `AccessStatus` enum: keep only if still used for "connected" semantics; otherwise delete (don't leave a dead enum — clean code).

### New — `plugins/ghrm/src/repositories/repo_membership_repository.py`
`GhrmRepoMembershipRepository(session)`:
- `upsert(user_id, package_id, **fields)` (find-by-unique-key then set, or insert)
- `find_by_user(user_id) -> List[GhrmRepoMembership]`
- `find_by_user_and_package(user_id, package_id) -> Optional[...]`
- `find_grace_expired(now) -> List[...]` (status=GRACE, grace_expires_at <= now)
- `find_invited() -> List[...]` (status=INVITED)
- `delete_for_user(user_id)`

### Migration — `plugins/ghrm/migrations/versions/<=32char>_repo_membership.py`
- `create_table('ghrm_repo_membership', …)` + unique `(user_id, package_id)` + indexes on `user_id`, `status`.
- Drop `deploy_token` (and removed columns) from `ghrm_user_github_access`.
- **Data:** dev rows are mock-only (`testuser`) — clean create, no back-fill (O1). Down-migration drops the new table + re-adds the old columns (guard so down is safe on empty data).
- Register the version path in `alembic.ini` `version_locations` (already done for ghrm if S43 added it — verify).

## TDD plan (tests FIRST)
- **Unit** (`plugins/ghrm/tests/unit/...`): `MembershipStatus` values; `to_dict()` shape incl. package slug + isoformat; repo `upsert` inserts then updates the same `(user,package)` row (no duplicate); `find_grace_expired`/`find_invited` filters.
- **Integration** (`db`): migration **up→down→up**; create memberships for one user across two packages with different statuses → `find_by_user` returns both; unique constraint rejects a duplicate `(user,package)`.

## Implementation steps
1. Write failing model/repo/migration tests.
2. Add enum + model; add repo; write migration.
3. Trim `GhrmUserGithubAccess`; delete dead enum/fields.
4. `--plugin ghrm` unit + integration green; validate up/down/up.

## Definition of done
`ghrm_repo_membership` exists with per-(user,package) uniqueness + the five statuses; identity record carries OAuth only; deploy-token column gone; repository covered; migration up/down/up validated; `--plugin ghrm --full` green. (Service still uses the old path until S49.3 — keep it compiling; a thin temporary shim is acceptable and removed in S49.3.)
