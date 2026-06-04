# Sprint 49 — GHRM collaborator lifecycle (make repo access actually work)

**Status:** DRAFT for negotiation — 2026-06-03 (decisions D1–D7 locked from the 2026-06-03 negotiation)
**Area:** `vbwd-backend` core (one tiny port extension) + plugin `ghrm` (backend) + `vbwd-fe-user-plugin-ghrm` (GitHub tab). Plugin lives in its own repo ([[feedback_plugins_always_in_own_repos]]).
**Context / trigger:** Live investigation 2026-06-03 — a paying test user never appears in the repo's collaborator list. Root cause: the running stack uses the **mock** GitHub client and the GitHub App is unconfigured, so *nothing ever reaches `api.github.com`*; on top of that several latent bugs would keep it broken even once the real client is enabled.

## Engineering requirements (BINDING)

**TDD-first** (failing test first, red→green→refactor) · **DevOps-first** (local + CI green from cold; schema only via Alembic) · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING**. The guard is **`bin/pre-commit-check.sh --full`** (or `--plugin ghrm --full`) green on every touched repo = "done". See [`_engineering_requirements.md`](_engineering_requirements.md). **vbwd core stays agnostic — and is NOT touched by this sprint at all** (`git diff vbwd/` empty; `test_core_agnosticism.py` green by construction). The entitlement read is a **declared plugin→plugin dependency** (ghrm→subscription), not a core port (revised 2026-06-04 — see S49.0 revision note).

## Root cause (evidence)

| Finding | Evidence |
|---|---|
| **Mock client is live** — `add_collaborator` writes to an in-memory dict, never calls GitHub. | `docker-compose.yaml:21` `GHRM_USE_MOCK_GITHUB=${…:-true}`; container `printenv` = `true`; `MockGithubAppClient.add_collaborator` (`github_app_client.py:100-107`). |
| **GitHub App unconfigured** — real client can't even be built. | `config.json` empty `github_app_id`/`github_installation_id`; **no `github-app.pem`** on disk or in container. |
| **The stored identity is fake.** | DB row `github_username = testuser` = the mock's hard-coded `get_oauth_user` default (`:134`). Real OAuth would store the user's login. |
| **Failures are invisible.** | `_sync_collaborators_for_user` does `except Exception: pass` (`github_access_service.py:279-280`). |
| **Add is not scoped to the purchase.** | `_get_packages_for_user` returns *all active packages* — "for now returns all active packages" (`:257-261`). |
| **Admin endpoints gate on undeclared perms.** | routes use `ghrm.repos.*`; plugin declares `ghrm.packages.*`/`ghrm.access.*` (`__init__.py:54-63`). |
| **GitHub semantics ignored.** | adding an outside collaborator creates a *pending invitation*; the user shows up only after accepting. |

## Locked decisions (2026-06-03 negotiation)

| # | Decision | Consequence |
|---|---|---|
| **D1** *(revised 2026-06-04)* | **Entitlement = events for live changes + a subscription-owned read on connect.** GHRM declares `dependencies=["subscription"]` and resolves `active_plan_ids(user_id) -> List[UUID]` through its **own** `ISubscriptionEntitlements` port, backed by the **subscription plugin's** read model (adapter wired only at the ghrm composition root). Used **only on OAuth-connect**; subscription events drive ongoing add/remove. No periodic reconcile job. | Fixes buy-then-connect ordering; replaces the "all active packages" stub. **Zero core change** — plugin→plugin dependency, not a core port. |
| **D2** | **Per-repo invitation lifecycle: INVITED → ACTIVE on acceptance, verified.** | New `INVITED` membership status; acceptance is verified (lazy check on `/access` load + a client query). |
| **D3** | **No server-minted deploy tokens — guide the user to a fine-grained PAT.** | Remove `create_deploy_token`/`revoke_deploy_token`/`deploy_token` rotation; the install page instructs the collaborator to create their own fine-grained PAT (`contents:read`) and shows the clone command. |
| **D4** | **Verify with a gated live integration test** (env-gated real App + throwaway repo; skipped in CI). | CI stays offline-green on mocks; a real add/remove is proven once with credentials you provide. |
| **D5** | **Align admin routes to the declared taxonomy** (`ghrm.packages.*` for package CRUD, `ghrm.access.*` for access-log + access sync). | The seeded Access-Level permissions actually gate the endpoints. |
| **D6** | **Failures set status `ERROR`, surfaced in the GitHub tab** (replaces silent `except: pass`). | Distinct from INVITED/ACTIVE/GRACE/REVOKED; the user sees "connection error", not a false "connected". |
| **D7** | **Per-(user,package) membership rows.** New table `ghrm_repo_membership(user_id, package_id, status, invitation_id, invited_at, …)`; `GhrmUserGithubAccess` keeps OAuth/identity only. | Correct multi-repo state; the tab lists each package's status. |

## Goal

A subscription-purchased package grants the connected GitHub user **push-collaborator** access to exactly that package's repo (so they can `git clone`), tracked per-repo through a correct invitation lifecycle; expiry removes them; failures are visible; and the whole thing is verifiable against real GitHub. The fix is real (not mock-only), scoped to entitlements, and SOLID.

---

## Membership state machine (per user × package)

```
   (no membership)
        │  entitlement present AND github connected → add_collaborator
        ▼
   PUT /collaborators → 201 (invitation)            → INVITED  (store invitation_id)
                      → 204 (already member/org)     → ACTIVE
   INVITED  ──[acceptance verified: GET collaborators/<u> = 204]──▶ ACTIVE
   ACTIVE/INVITED ──[subscription.cancelled | payment_failed]──▶ GRACE (grace_expires_at)
   GRACE ──[scheduler: grace expired]──▶ remove_collaborator / cancel invite ──▶ REVOKED
   ACTIVE/INVITED/REVOKED ──[subscription.renewed]──▶ re-add ──▶ INVITED/ACTIVE
   any GitHub API failure ──▶ ERROR  (surfaced in the tab; retried on next event/connect)
   disconnect ──▶ remove all memberships + revoke OAuth token
```

`active_status_for_user` is derived from its memberships for display; there is no single per-user collaborator status (D7).

---

## Backend design (layered, SOLID, TDD-first)

### 1. Entitlement read — subscription-owned, reached via a declared dependency (D1, revised — **NO core change**)
**Subscription plugin** (`plugins/subscription/subscription/services/subscription_read_model.py` + its repo):
- Add `active_plan_ids(user_id) -> List[UUID]` → distinct `tarif_plan_id`s of the user's **active** subscriptions (repo accessor `find_active_by_user_list`, ACTIVE+TRIALING).
- **Test first (subscription unit/integration):** active subs → their plan ids; cancelled/expired excluded.

**GHRM plugin:**
- `PluginMetadata.dependencies = ["subscription"]`.
- Own a narrow port `ISubscriptionEntitlements.active_plan_ids(user_id)` (in `plugins/ghrm/src/services/ports.py`); the service depends on it (DIP). The subscription concrete is imported **only** in the composition-root adapter (`__init__.py:_make_access_service`).
- **Test first:** service uses a stubbed `ISubscriptionEntitlements` (no subscription import in unit tests); `metadata.dependencies == ["subscription"]`.

See **[S49.0](s49-0-core-port-and-subscription-impl.md)** for the full rationale (why the core-port design was rejected) and steps. `git diff vbwd/` stays empty for the whole sprint.

### 2. GHRM — data model (D7)
- New `plugins/ghrm/src/models/ghrm_repo_membership.py` — `GhrmRepoMembership(BaseModel)`:
  `user_id` (UUID), `package_id` (UUID FK→ghrm_software_package), `status` (enum `INVITED|ACTIVE|GRACE|REVOKED|ERROR`), `invitation_id` (str?, the GitHub invitation id), `invited_at`, `grace_expires_at`, `last_error` (str?). Unique `(user_id, package_id)`.
- `GhrmUserGithubAccess` — **drop** collaborator-state fields that move to membership (`deploy_token`, the single `access_status`/`grace_expires_at` semantics become identity-only: keep `github_username`, `github_user_id`, `oauth_token`, `oauth_scope`, plus a derived `connected` flag).
- **Migration** `plugins/ghrm/migrations/versions/<=32char>_repo_membership.py` — create `ghrm_repo_membership` (S43 naming), drop the deploy-token column; data-preserving (existing single-status rows → seed memberships if any real ones exist; dev data is mock-only so a clean create is acceptable — guard the down-migration). Registered in `alembic.ini`.
- **Repository** `GhrmRepoMembershipRepository` — `upsert(user_id, package_id, …)`, `find_by_user`, `find_grace_expired(now)`, `find_invited()`.

### 3. GHRM — `GithubAccessService` rewrite (the core of the sprint)
Replace the silent/stub logic with explicit, tested behaviour:

- `handle_oauth_callback(user_id, code)` — exchange + store identity, then **`_grant_entitled(user_id)`**:
  - `plan_ids = self._entitlements.active_plan_ids(user_id)` (D1 — ghrm-owned port, subscription-backed).
  - For each `pkg = package_repo.find_by_tariff_plan_id(plan_id)`: `_ensure_collaborator(membership, pkg, access)`.
- `on_subscription_activated(user_id, plan_id)` — if connected, `_ensure_collaborator` for that one package; if **not** connected, **persist an `INVITED`-pending membership intent is NOT needed** (connect re-resolves via the port, D1) — so just no-op when disconnected.
- `on_subscription_cancelled/payment_failed(user_id, plan_id, trailing_days)` — set that package's membership → `GRACE` with `grace_expires_at`.
- `on_subscription_renewed(user_id, plan_id)` — re-ensure collaborator (back to INVITED/ACTIVE); **no token rotation** (D3).
- `revoke_expired_grace_access()` (scheduler) — for each grace-expired **membership**: `remove_collaborator` (or cancel pending invitation), set `REVOKED`.
- `verify_acceptance(user_id)` — for each `INVITED` membership, `github.is_collaborator(...)`; if true → `ACTIVE`. Called lazily from `GET /access` (D2).
- `_ensure_collaborator(membership, pkg, access)` — calls `github.add_collaborator`; maps `201→INVITED(+invitation_id)`, `204→ACTIVE`; **on exception → `status=ERROR`, `last_error=str(exc)`, log WARN** (D6) — *no bare except* ([[feedback_no_noqa_without_permission]] applies to suppressions too). Re-raises nothing to the caller except as a structured per-package result.
- `disconnect_github(user_id)` — remove every membership's collaborator/invite, then delete identity.

**SOLID notes:** service depends only on the `IGithubAppClient` port + repos + the ghrm-owned `ISubscriptionEntitlements` port (DIP — subscription wired only at the composition root); each handler does one thing (SRP); both client impls honour identical contracts (Liskov); collaborator-ensure logic lives in exactly one private method (DRY).

### 4. GHRM — `IGithubAppClient` additions (D2/D3)
- Add `is_collaborator(owner, repo, username) -> bool` (GET `/collaborators/{u}` → 204 true / 404 false).
- Add `list_repo_invitations(owner, repo)` / `cancel_invitation(owner, repo, invitation_id)` (for grace-expiry on a still-pending invite).
- `add_collaborator` returns a small result `{state: "invited"|"active", invitation_id?: str}` instead of bare `bool` (so the service can set INVITED vs ACTIVE) — update **both** `MockGithubAppClient` and `GithubAppClient` (Liskov: identical signatures + semantics; mock simulates 201-invite vs 204-member).
- **Remove** `create_deploy_token`/`revoke_deploy_token` from the interface and both impls (D3) — and their callers.

### 5. GHRM — install instructions (D3)
- `get_install_instructions(slug, user_id)` — when the user is an `ACTIVE` collaborator: render guidance to **create a fine-grained PAT** (`contents:read` on `owner/repo`) + the `git clone https://<PAT>@github.com/owner/repo.git` command (and an SSH alternative). When `INVITED`: "accept your GitHub invitation first". When none: subscription-required.

### 6. GHRM — permission taxonomy (D5)
- Change admin routes: package CRUD/sync → `ghrm.packages.view|manage`; access-log + `access/sync/<user_id>` → `ghrm.access.view|manage`; widgets → `ghrm.packages.view|manage`. Keep `ghrm.configure` for settings. (Routes currently say `ghrm.repos.*` — undeclared.)
- **Test first:** an admin with `ghrm.packages.manage` but not `ghrm.access.manage` can CRUD packages but gets 403 on access sync, and vice-versa.

### 7. Config / enablement (root-cause fix, ops)
- Document + provide local config to run the **real** client: `GHRM_USE_MOCK_GITHUB=false`, `github_app_id`, `github_installation_id`, PEM mounted at `github_app_private_key_path`, and OAuth `client_id`/`client_secret`. **The GitHub App must have `Administration: write`** on the target repos (required to manage collaborators) + `Contents: read`; OAuth scope stays `read:user`.
- Keep the mock as the **default for dev/CI** (offline-green), but make `_make_github_client` log a clear WARN when the mock is active so it's never silently mistaken for real.

---

## fe-user GitHub tab (`vbwd-fe-user-plugin-ghrm`)

- Render **per-package** membership state from `GET /api/v1/ghrm/access`: `ACTIVE` ("connected — clone instructions"), `INVITED` ("Invitation sent — accept it on GitHub" + link to the repo's invitations), `GRACE` ("access ends <date>"), `REVOKED`, `ERROR` ("connection error — contact support"). (D2/D6/D7)
- Install panel shows the **PAT-creation guidance + clone command** for ACTIVE packages (D3).
- **Vitest:** each status renders the right copy/CTA; ERROR never shows a false "connected".

## TDD plan (tests FIRST, per layer)

- **Subscription unit/integration:** `active_plan_ids` returns active plan ids only (cancelled/expired excluded); `find_active_by_user_list` filters ACTIVE+TRIALING.
- **GHRM port:** `metadata.dependencies == ["subscription"]`; service resolves entitlements via a stubbed `ISubscriptionEntitlements` (no subscription import in unit tests); empty entitlements ⇒ no membership.
- **Core untouched:** `git diff --quiet vbwd/`; `test_core_agnosticism.py` green.
- **GHRM unit (MagicMock repos + `MockGithubAppClient`):**
  - connect with one active entitlement → membership `INVITED` (mock returns invite) / `ACTIVE` (mock returns member); collaborator recorded with the right `(owner, repo, username, permission=push)`.
  - connect with **no** entitlement → no membership, no add.
  - `on_subscription_activated` when disconnected → no-op; when connected → ensures that **one** package only (not all).
  - cancel → `GRACE` + `grace_expires_at`; renew → back to active/invited; grace-expired → `remove`/`cancel` + `REVOKED`.
  - `verify_acceptance`: INVITED + `is_collaborator=true` → ACTIVE.
  - `add_collaborator` raises → membership `ERROR` + `last_error`, **no exception swallowed silently**, WARN logged.
  - disconnect → all memberships removed.
- **GHRM real-client contract (httpx `MockTransport`):** `add_collaborator` issues `PUT /repos/{o}/{r}/collaborators/{u}` with `{"permission":"push"}` + App headers; 201→invited(+id), 204→active, 403/404→`GithubAppClientError`; `is_collaborator` 204/404 mapping; `remove`/`cancel_invitation` requests.
- **GHRM integration (`db`):** migration up/down/up; membership round-trip; permission-taxonomy 403s.
- **Gated live integration (D4):** env-gated (`GHRM_LIVE_TEST=1` + real App creds + throwaway repo) — actually invite a test account, verify pending→accept→active→remove. Skipped in CI.
- **fe-user vitest:** the five states.

## Sub-sprints

Each is a self-contained TDD-first slice; implement in order (later ones depend on earlier).

- **[S49.0 — GHRM→subscription entitlement read](s49-0-core-port-and-subscription-impl.md)** (subscription-owned `active_plan_ids`; ghrm declares `dependencies=["subscription"]` + owns `ISubscriptionEntitlements`; **no core change**). *Depends on: —*
- **[S49.1 — GHRM membership model](s49-1-ghrm-repo-membership-model.md)** (`ghrm_repo_membership` + repo + migration up/down/up; drop deploy-token column). *Depends on: —*
- **[S49.2 — invitation-aware `IGithubAppClient`](s49-2-github-client-invitation-aware.md)** (invite-aware `add_collaborator`, `is_collaborator`, `cancel_invitation`; drop deploy-token methods; both impls + httpx contract tests). *Depends on: —*
- **[S49.3 — `GithubAccessService` rewrite](s49-3-github-access-service-rewrite.md)** (entitlement-scoped add/remove, INVITED lifecycle, ERROR handling, `verify_acceptance`) — the bulk of the unit tests. *Depends on: 49.0, 49.1, 49.2*
- **[S49.4 — routes / permissions / install](s49-4-routes-permissions-install.md)** (taxonomy fix, `/access` lazy verify, PAT+clone install guidance). *Depends on: 49.3*
- **[S49.5 — fe-user GitHub tab](s49-5-fe-user-github-tab.md)** (per-package states + PAT/clone panel). *Depends on: 49.4*
- **[S49.6 — ops + live verification](s49-6-ops-and-live-verification.md)** (mock WARN, real-client runbook, gated live test + manual buy→connect→accept→clone→expire run). *Depends on: 49.2/49.3/49.4*

## Open decisions (small)

- **O1 — migration data:** dev DB has only mock rows (`testuser`); OK to create `ghrm_repo_membership` clean and not back-fill the fake rows? (Recommend yes.)
- **O2 — acceptance verification cadence:** lazy-on-`/access` only (chosen) vs also a small scheduler tick to promote INVITED→ACTIVE in the background. (Recommend lazy-only for v1; the scheduler already runs for grace expiry, so adding promotion there is cheap if you want it.)
- ~~**O3 — GHRM↔subscription dependency**~~ **RESOLVED (2026-06-04):** GHRM **declares `dependencies=["subscription"]`** and depends on the subscription plugin's read (via its own `ISubscriptionEntitlements` port). The core-mediated design was rejected — core must name no plugin domain, and a core port brokering plan/entitlement data between two plugins (with no core consumer) is the leak we're removing. Plugin→plugin deps are the platform's sanctioned pattern (taro→subscription). See S49.0 revision note.

## Definition of done

A connected user with an active package is invited as a push collaborator on **that** repo (and only that repo); accepting the invite flips the tab to ACTIVE with PAT/clone guidance; cancelling starts grace and expiry removes them; every GitHub failure shows as ERROR (never a silent success); admin endpoints gate on the declared `ghrm.packages.*`/`ghrm.access.*`; the mock is clearly logged and the real client is proven by a gated live add/remove against a throwaway repo; **core is untouched (`git diff vbwd/` empty, oracle green)**; `bin/pre-commit-check.sh --plugin ghrm --full` + `--plugin subscription --full` + fe-user vitest/eslint green; migration up/down/up validated.
