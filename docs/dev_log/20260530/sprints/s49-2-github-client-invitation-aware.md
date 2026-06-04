# Sprint 49.2 — Invitation-aware `IGithubAppClient` (+ drop deploy tokens)

**Parent:** [s49-ghrm-collaborator-lifecycle.md](s49-ghrm-collaborator-lifecycle.md) · **Decisions:** D2, D3, D4 (contract tests)
**Status:** READY · **Area:** `plugins/ghrm` (the GitHub client port + both impls)
**Depends on:** nothing. **Blocks:** S49.3 (service consumes the new client result shape).

## Engineering requirements (BINDING)
TDD-first · SOLID · **Liskov** (mock and real impls honour identical signatures + semantics) · DI · DRY · clean code · NO OVERENGINEERING. Guard: `--plugin ghrm --full` green; the real client is exercised via **httpx `MockTransport` contract tests** (no network in CI). See [`_engineering_requirements.md`](_engineering_requirements.md).

## Goal
Make the client model GitHub's real collaborator semantics: a `PUT` for an outside collaborator returns a **pending invitation** (`201`), not instant membership; an existing member returns `204`. Expose acceptance + invitation-cancel queries. Remove the fake deploy-token methods (D3).

## Contract changes — `IGithubAppClient` (`github_app_client.py`)
- `add_collaborator(owner, repo, username, permission="push") -> AddCollaboratorResult`
  where `AddCollaboratorResult` is a small dataclass `{state: "invited"|"active", invitation_id: str|None}`.
  Maps `201`→`invited` (capture `resp.json()["id"]`), `204`→`active`; `403/404/...`→raise `GithubAppClientError`.
- `is_collaborator(owner, repo, username) -> bool` — `GET /repos/{o}/{r}/collaborators/{u}` → `204` true / `404` false; other → raise.
- `list_repo_invitations(owner, repo) -> list[dict]` — `GET /repos/{o}/{r}/invitations`.
- `cancel_invitation(owner, repo, invitation_id) -> None` — `DELETE /repos/{o}/{r}/invitations/{id}` (`204`/`404` ok).
- `remove_collaborator(...)` — unchanged.
- **Remove** `create_deploy_token` + `revoke_deploy_token` from the interface (D3).

## Implementations (Liskov-paired)
### `MockGithubAppClient`
- `add_collaborator`: default → `invited` with a synthetic id; allow a test toggle (`members_already` set) → `active`; honour `raise_on_add_collaborator`.
- `is_collaborator`: returns from a configurable `accepted` set (simulates the user accepting).
- `list_repo_invitations`/`cancel_invitation`: in-memory.
- Drop deploy-token attrs/methods. Replace the hard-coded `get_oauth_user` default (`{"login":"testuser",...}`) is fine to keep for tests **but** add a clear docstring that it is a test fixture (this value is what masked the live bug).

### `GithubAppClient` (real, `github_app_client_real.py`)
- Implement the four methods with the documented status mapping; keep installation-token auth + `X-GitHub-Api-Version` headers.
- `add_collaborator` body stays `{"permission": "push"}`; parse `201` invitation id.
- Delete deploy-token methods.

## TDD plan (tests FIRST)
- **Contract tests** (`plugins/ghrm/tests/unit/services/test_github_client_contract.py`, httpx `MockTransport`):
  - `add_collaborator` issues `PUT /repos/o/r/collaborators/u` with `{"permission":"push"}` + bearer + api-version headers; `201`→`AddCollaboratorResult(invited, id)`, `204`→`active`, `403`→`GithubAppClientError` (message includes body), `404`→raise.
  - `is_collaborator`: `204`→True, `404`→False.
  - `cancel_invitation`: `DELETE …/invitations/<id>` issued; `204`/`404` ok.
- **Liskov tests:** the same test matrix asserted against `MockGithubAppClient` (state transitions: invited→ then `accepted` set → `is_collaborator` True).
- **Regression:** existing GHRM tests referencing deploy-token methods updated/removed.

## Implementation steps
1. Write contract + mock-parity failing tests.
2. Introduce `AddCollaboratorResult`; update interface; implement both clients; delete deploy-token methods.
3. Fix all references (service/routes) enough to compile (full rewrite is S49.3).
4. `--plugin ghrm --full` green.

## Definition of done
Both clients expose invitation-aware `add_collaborator` + `is_collaborator` + invitation cancel, with identical contracts proven by paired tests; deploy-token methods gone; contract tests assert exact HTTP requests/responses; CI offline-green.
