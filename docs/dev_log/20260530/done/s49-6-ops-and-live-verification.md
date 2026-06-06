# Sprint 49.6 — Ops config + gated live GitHub verification

**Parent:** [s49-ghrm-collaborator-lifecycle.md](s49-ghrm-collaborator-lifecycle.md) · **Decisions:** D4 (+ root-cause ops)
**Status:** READY (needs your GitHub App + throwaway repo for the live run) · **Area:** `plugins/ghrm` (config/docs/test) + `vbwd-backend` compose
**Depends on:** **S49.2/S49.3/S49.4** (real client + service + routes). **Blocks:** nothing — this is the proof.

## Engineering requirements (BINDING)
DevOps-first (works real + offline) · clean code · NO OVERENGINEERING. CI stays offline-green; the live test is **opt-in and skipped without creds**. No secrets committed. See [`_engineering_requirements.md`](_engineering_requirements.md).

## Goal
Close the loop that started this sprint: prove a real GitHub user is invited→added→removed against a real repo, and make it impossible to mistake the mock for the real client again.

## Ops changes (root-cause fixes)
- **Mock visibility:** `_make_github_client` logs a clear **WARN** ("[GHRM] using MOCK GitHub client — no real API calls") whenever `GHRM_USE_MOCK_GITHUB=true`, so the live bug (silent mock) can't recur. Mock stays the **default for dev/CI**.
- **Real-client runbook** (`plugins/ghrm/README.md` or `docs/`): the exact steps + env/config to go live:
  - `GHRM_USE_MOCK_GITHUB=false`
  - `github_app_id`, `github_installation_id`, PEM mounted at `github_app_private_key_path` (`/app/plugins/ghrm/github-app.pem`)
  - OAuth App `github_oauth_client_id` / `github_oauth_client_secret`, redirect URI
  - **GitHub App permissions required:** `Administration: write` (manage collaborators) + `Contents: read`; OAuth scope `read:user`.
  - App must be **installed** on the org/account that owns the package repos.
- Confirm the PEM is provided via a **mounted secret / ignored path** (never committed).

## Gated live integration test (D4)
- `plugins/ghrm/tests/integration/test_github_live.py` — `@pytest.mark.skipif` unless `GHRM_LIVE_TEST=1` **and** real App creds + `GHRM_LIVE_TEST_REPO` (a throwaway repo) + `GHRM_LIVE_TEST_GITHUB_USER` are present.
- Flow it asserts against real GitHub:
  1. `add_collaborator(owner, repo, test_user, "push")` → `invited` + invitation id (or `active` if already a member).
  2. `list_repo_invitations` contains it.
  3. (manual or PAT-accept step documented) → `is_collaborator` → True.
  4. `remove_collaborator` / `cancel_invitation` → cleaned up; `is_collaborator` → False.
- The test cleans up after itself (idempotent, leaves no collaborator behind).

## Manual acceptance (your one-time run)
1. Bring up a workspace stack with real creds (per [[feedback_no_writes_to_install_tree]] — fresh stack from the workspace dir, not an install tree).
2. As the test user: buy a GHRM package → dashboard → invoice line item → GitHub tab → connect.
3. Verify: tab shows **INVITED**; GitHub sends the invite; accept it; tab flips to **ACTIVE**; clone with a fine-grained PAT works.
4. Cancel/expire the subscription → user removed from collaborators; tab shows GRACE→REVOKED.
5. Capture screenshots into `reports/assets/`.

## TDD / verification plan
- CI: live test **skipped** (no creds) — green offline.
- Local with creds: live test passes; manual flow screenshots attached to the closing report.

## Definition of done
The mock logs a loud WARN; the runbook documents the real setup incl. `Administration: write`; the gated live test exists, is skipped in CI, and passes against a throwaway repo with self-cleanup; the manual buy→connect→invite→accept→clone→expire→remove flow is verified once and reported (the original symptom is gone). No secrets committed.
