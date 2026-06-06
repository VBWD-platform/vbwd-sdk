# Sprint 49.3 — `GithubAccessService` rewrite (the core fix)

**Parent:** [s49-ghrm-collaborator-lifecycle.md](s49-ghrm-collaborator-lifecycle.md) · **Decisions:** D1, D2, D6, D7 (+ D3)
**Status:** READY · **Area:** `plugins/ghrm` (service + event handlers + scheduler hook)
**Depends on:** **S49.0** (port), **S49.1** (membership model), **S49.2** (client). **Blocks:** S49.4 (routes), S49.5 (tab copy).

## Engineering requirements (BINDING)
TDD-first · SOLID (SRP per handler, DIP on ports) · **Liskov** · DI · DRY (one `_ensure_collaborator`) · clean code (**no bare `except: pass`** — [[feedback_no_noqa_without_permission]]) · NO OVERENGINEERING. Guard: `--plugin ghrm --full` green. See [`_engineering_requirements.md`](_engineering_requirements.md).

## Goal
Rewrite the service so collaborator grant/revoke is **entitlement-scoped**, **per-(user,package)**, models the **INVITED→ACTIVE** lifecycle, and makes failures visible as **ERROR** — eliminating the three latent bugs (`all active packages` stub, silent `except: pass`, single per-user status).

## Constructor / DI
`GithubAccessService(access_repo, membership_repo, log_repo, package_repo, github, entitlements, oauth_*)` — drop the deploy-token deps; add `membership_repo` **and `entitlements: ISubscriptionEntitlements`** (the ghrm-owned port from S49.0, constructor-injected — DIP). Entitlement resolution calls `self._entitlements.active_plan_ids(user_id)`; the subscription concrete is wired only at the composition root via the adapter (S49.0 §3). Update the factory in `plugins/ghrm/__init__.py:_make_access_service` (build + inject the `_SubscriptionEntitlementsAdapter`) + `routes._access_svc`.

> **Revised from S49.0:** entitlement resolution is **not** the core `resolve_subscription_read_model()` (that core port is being removed). It is the ghrm-owned `ISubscriptionEntitlements` port backed by the subscription plugin — a declared plugin→plugin dependency, zero core involvement.

## Behaviour (each method = one responsibility, all tested)
- **`handle_oauth_callback(user_id, code)`** — exchange + store identity (unchanged), then `_grant_entitled(user_id)`:
  - `plan_ids = self._entitlements.active_plan_ids(user_id)` (D1, via the ghrm-owned port).
  - For each `pkg = package_repo.find_by_tariff_plan_id(plan_id)` (skip None) → `_ensure_collaborator(user_id, pkg, access)`.
  - Return identity dict + a per-package summary (used by S49.4 callback response is **not** required — D6 chose status, not callback warning).
- **`on_subscription_activated(user_id, plan_id)`** — resolve the one `pkg`; if user connected → `_ensure_collaborator`; if not connected → **no-op** (connect re-resolves via the port, D1).
- **`on_subscription_cancelled / on_subscription_payment_failed(user_id, plan_id, trailing_days)`** — set that package's membership → `GRACE`, `grace_expires_at = now + (trailing_days or fallback)`.
- **`on_subscription_renewed(user_id, plan_id)`** — `_ensure_collaborator` again (restores INVITED/ACTIVE); **no token rotation** (D3).
- **`revoke_expired_grace_access()`** (scheduler, `scheduler.py` unchanged caller) — for each grace-expired **membership**: if `ACTIVE` → `github.remove_collaborator`; if `INVITED` → `github.cancel_invitation`; set `REVOKED`; log. Returns count.
- **`verify_acceptance(user_id)`** — for each `INVITED` membership → `github.is_collaborator(...)`; if true → `ACTIVE`, clear `invitation_id`. (Called from `GET /access`, S49.4.) (D2)
- **`disconnect_github(user_id)`** — for each membership: remove collaborator / cancel invite; delete memberships; delete identity.
- **`get_access_status(user_id)`** — identity `connected` flag + the list of memberships (`to_dict`) for the tab (D7).

### `_ensure_collaborator(user_id, pkg, access)` (single home — DRY)
```
try:
    result = github.add_collaborator(pkg.github_owner, pkg.github_repo, access.github_username, "push")
    status = ACTIVE if result.state == "active" else INVITED
    membership_repo.upsert(user_id, pkg.id, status=status,
                           invitation_id=result.invitation_id, invited_at=utcnow(), last_error=None)
    log_repo.log(user_id, str(pkg.id), ADD_COLLABORATOR, triggered_by)
except GithubAppClientError as exc:
    membership_repo.upsert(user_id, pkg.id, status=ERROR, last_error=str(exc))
    logger.warning("[GHRM] add_collaborator failed for %s/%s: %s", pkg.github_owner, pkg.github_repo, exc)
```
**No bare except** — only `GithubAppClientError` is caught; anything else propagates (D6). Status `ERROR` is the surfaced signal.

## TDD plan (tests FIRST — MagicMock repos + `MockGithubAppClient`, stub `ISubscriptionEntitlements` — no subscription import in unit tests)
- connect, one entitlement, mock→invited ⇒ membership `INVITED` (+invitation_id); add called once with `(owner,repo,username,"push")`.
- connect, one entitlement, mock→member ⇒ `ACTIVE`.
- connect, **no** entitlement ⇒ no membership, `add` not called (kills the "all packages" bug).
- connect, two entitlements ⇒ two memberships; an unrelated active package the user didn't buy ⇒ **not** added.
- `on_subscription_activated` disconnected ⇒ no-op; connected ⇒ exactly that package.
- cancel ⇒ `GRACE` + expiry; renew ⇒ back to active/invited.
- grace-expired ACTIVE ⇒ `remove_collaborator` + `REVOKED`; grace-expired INVITED ⇒ `cancel_invitation` + `REVOKED`.
- `verify_acceptance`: INVITED + `is_collaborator`=True ⇒ `ACTIVE`.
- `add_collaborator` raises `GithubAppClientError` ⇒ membership `ERROR` + `last_error`, **not** swallowed, WARN logged, no exception escapes the handler.
- disconnect ⇒ all memberships removed + identity deleted.
- **Empty-entitlement contract:** stubbed `entitlements.active_plan_ids → []` ⇒ connect creates no membership (a user with no active plan gets no access).

## Implementation steps
1. Write the failing service tests above.
2. Rewrite the service; update `__init__.py`/`routes` factories (drop deploy deps, add membership_repo).
3. Delete the old `_get_packages_for_user` stub + `_sync_collaborators_for_user` `except: pass`.
4. `--plugin ghrm --full` green.

## Definition of done
Grant/revoke is scoped to the user's actual entitlements, per-(user,package), with INVITED→ACTIVE verified and failures recorded as ERROR; zero silent exception swallowing; the three root-cause latent bugs are gone and covered by tests; `--plugin ghrm --full` green.
