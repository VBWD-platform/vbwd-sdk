# S04 — Secret hygiene: required env vars + stop tracking `.env`

**Source:** review §2.5 + §2.6.
**Risk:** CRITICAL (security). Compose silently substitutes a known-public
"dev-secret-key-change-in-production" if the env var is missing, and the
`.env` file with these placeholder secrets is checked into git.
**Outcome:** `docker-compose.yaml` and `docker-compose.server.yaml` use
the **required** form `${VAR:?error}` for `FLASK_SECRET_KEY`,
`JWT_SECRET_KEY`, and every DB / API-provider password. `.env` is
untracked. A pre-commit check rejects PRs that add `.env`.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md).

## Baseline (E1)

1. `tests/unit/test_compose_secrets.py::test_no_default_for_required_secret`
   — parses both compose files, asserts every var matching `*_SECRET*`,
   `*_PASSWORD*`, `*_API_KEY*` uses `${VAR:?…}` form (required), not
   `${VAR:-default}`. **Today: fails on `FLASK_SECRET_KEY`, `JWT_SECRET_KEY`.**
2. `tests/unit/test_repo_hygiene.py::test_no_env_file_tracked`
   — `git ls-files vbwd-backend/.env` returns empty. **Today: fails.**

## Touch-points

- `vbwd-backend/docker-compose.yaml` (FLASK_SECRET_KEY, JWT_SECRET_KEY lines)
- `vbwd-backend/docker-compose.server.yaml` (same)
- `vbwd-backend/docker-compose.production.yaml` (verify)
- `vbwd-backend/.env` (delete from tracking)
- `vbwd-backend/.env.example` (ensure complete + accurate)
- `.github/workflows/deploy.yml` (verify GH Secrets are exported into
  the deploy env before compose runs)

## Steps (each validated)

1. **Write the two tests.** They fail.
2. **Audit env vars referenced in compose.** Build the full list of
   secret-shaped variables; for each, decide: required (`${V:?msg}`) or
   genuinely optional (`${V:-safe_default}` — must be safe even in prod).
3. **Replace** `${FLASK_SECRET_KEY:-dev-secret-key-change-in-production}`
   → `${FLASK_SECRET_KEY:?FLASK_SECRET_KEY must be set; generate with: python -c \"import secrets; print(secrets.token_hex(32))\"}`.
   Same for `JWT_SECRET_KEY`, `VBWD_DB_PASSWORD`, payment-provider API
   keys, SMTP creds.
4. **Remove `.env` from tracking:** `git rm --cached vbwd-backend/.env`.
   Confirm `.env` is in `.gitignore` (it is). Add `.env.production`,
   `.env.local`, `.env.*.local` patterns explicitly.
5. **Update `.env.example`** with every variable from step 2 + a
   comment line documenting how to generate each (`openssl rand -hex 32`).
6. **Add `make secrets` target** to `Makefile.server`:
   ```makefile
   secrets:
       @echo "VBWD_FLASK_SECRET=$$(python -c 'import secrets; print(secrets.token_hex(32))')"
       @echo "VBWD_JWT_SECRET=$$(python -c 'import secrets; print(secrets.token_hex(32))')"
   ```
7. **Verify GH Actions** — `deploy.yml` must export the GH Secrets into
   the env before `docker compose ... up`. If a secret is missing, the
   required-form compose now aborts immediately (good).
8. **Rotate the committed secrets.** Generate fresh prod secrets,
   update GitHub Secrets, restart prod. The committed values are
   public — treat as compromised.

## Acceptance (oracle)

- Both tests green.
- `docker compose -f docker-compose.server.yaml config` with no env
  set aborts with the helpful error string.
- `git log --all --full-history -- vbwd-backend/.env` is non-empty (the
  file existed) but the file is no longer tracked.
- A fresh `git clone` does NOT contain `vbwd-backend/.env`.
- Prod secrets rotated (verified out-of-band).

## Notes

- This sprint does NOT do git history rewriting (BFG / `filter-branch`)
  — the leaked secrets are dev placeholders and will be rotated. If
  any rotated secret was ever real, history rewrite becomes a separate
  effort.
- Adds friction for first-time setup (you can no longer `docker compose
  up` blind) — that's the point; document in `README.md` that step 1
  is `make secrets >> .env`.
- §8 no overengineering: do NOT introduce HashiCorp Vault / SOPS yet —
  env vars + GH Secrets is the right scale for the current ops setup.
