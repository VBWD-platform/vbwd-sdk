# S05 — Encrypt GHRM OAuth + deploy tokens at rest

**Source:** review §5.4 → `plugins/ghrm/src/services/github_access_service.py:98, 199` (two `# TODO: encrypt in production` markers).
**Risk:** CRITICAL (security). GitHub OAuth tokens grant repo access; deploy tokens grant write to deployment surfaces. Both currently stored in plaintext SQL.
**Outcome:** Tokens are encrypted before persistence and decrypted only at point-of-use. The two TODO markers are gone. The DB column type is `BYTEA` (or `TEXT` for base64). The encryption key is loaded from env, never logged, and rotation is a documented procedure.

**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · no overengineering — see [`_engineering-requirements.md`](_engineering-requirements.md). Gate: `bin/pre-commit-check.sh --full` green on `vbwd-backend`; new tests assert encrypted-at-rest.

## Baseline (E1)

1. `plugins/ghrm/tests/unit/test_token_encryption.py::test_token_stored_encrypted`
   — stores a token via the service, fetches the raw row via SQL,
   asserts the stored bytes do NOT equal the plaintext token. **Today: fails.**
2. `plugins/ghrm/tests/unit/test_token_encryption.py::test_token_round_trip`
   — stores then reads via the service, asserts the decrypted value equals
   the original plaintext.
3. `tests/unit/test_no_encrypt_todos.py::test_no_encrypt_todo_in_ghrm`
   — greps `plugins/ghrm/` for `TODO.*encrypt`, asserts empty. **Today: fails.**
4. Optional: `tests/integration/test_token_not_logged.py` — captures
   logs through the token-write path, asserts plaintext token does not
   appear.

## Touch-points

- `plugins/ghrm/src/services/github_access_service.py:98` (OAuth token write)
- `plugins/ghrm/src/services/github_access_service.py:199` (deploy token write)
- `plugins/ghrm/src/models/` (token-holding model; column type)
- `plugins/ghrm/migrations/versions/` (new migration to:
  (a) add new encrypted column, (b) backfill from old, (c) drop old)
- `plugins/ghrm/__init__.py` (config: encryption-key env var)
- `vbwd/utils/crypto.py` (NEW — symmetric envelope encryption helper;
  see §5/DRY note below)

## Steps (each validated)

1. **Write the 3-4 tests above.** Red.
2. **Add the shared crypto helper** at `vbwd/utils/crypto.py`:
   ```python
   class TokenCipher:
       def __init__(self, key: bytes): ...  # 32 bytes from env
       def encrypt(self, plaintext: str) -> bytes: ...
       def decrypt(self, ciphertext: bytes) -> str: ...
   ```
   Backed by `cryptography.fernet.Fernet` (already a transitive
   dependency; pin in `requirements.txt`). One home for the encryption
   primitive (§5 DRY) — every plugin uses it.
3. **Add `VBWD_TOKEN_ENCRYPTION_KEY`** to `.env.example` with a
   `Fernet.generate_key()` example. Update [[s04]] secret list — this
   is also a required secret in prod (`${VBWD_TOKEN_ENCRYPTION_KEY:?...}`).
4. **Migration:** add `oauth_token_encrypted BYTEA NULL`, `deploy_token_encrypted BYTEA NULL`,
   backfill via a data migration that reads existing plaintext through
   `TokenCipher.encrypt`, then drop the old columns. Reversible
   downgrade reads back through `decrypt` (acceptable risk — the
   downgrade is exceptional, not a regular path).
5. **Service layer:** inject `TokenCipher` via the container (DI §3).
   Replace direct column reads/writes with `cipher.encrypt(token)` and
   `cipher.decrypt(row.oauth_token_encrypted)`. Delete the two TODO
   comments.
6. **Logging guard.** Add a log filter (or audit existing
   `LoggerAdapter`) that redacts `token=…` / `Bearer …` substrings.
7. **Rotation runbook.** Document key rotation: generate new key,
   set `VBWD_TOKEN_ENCRYPTION_KEY_NEW`, run a one-shot script that
   `decrypt(old).encrypt(new)` for every row, swap envs, delete old.
   (Defer the multi-key code path unless rotation is imminent — §8 no
   overengineering.)

## Acceptance (oracle)

- All tests green; pre-commit `--full` green on `vbwd-backend`.
- Raw SQL select on `ghrm_*` token tables returns binary (not the
  plaintext token).
- `grep -rn "TODO.*encrypt" plugins/ghrm/` → empty.
- Logs through a token-write flow do not contain the plaintext.
- Runbook in `docs/architecture_core_server_ce/runbooks/ghrm-token-rotation.md`.

## Notes

- Until this lands, **the `ghrm` plugin must not be enabled in
  production** — block via a `production` config flag if needed.
- Crypto helper lives in `vbwd/utils/` so other plugins (chat, taro
  AI keys, future OAuth integrations) reuse it. §5 DRY.
- §8: no per-row key derivation, no HSM integration — Fernet + single
  rotation-capable key is the right scale.
