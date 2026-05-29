# S31 — Flask-Limiter per-user keying (NAT-shared bucket fix)

**Status:** PLANNED — 2026-05-28. Follow-up to [S27](s27-lift-global-flask-limiter.md).
S27 lifted the global ceilings 10× (10k → 100k/day, 2k → 20k/hour) so today's
prod 429 stopped reproducing. But the keyfunc is still `get_remote_address`,
so users behind shared NAT (mobile-carrier CGNAT, office wifi, VPN exits)
still **share one bucket per IP**. This sprint switches the keyfunc to prefer
the authenticated user when a JWT is present, falling back to IP only when
no token is on the request — closing the NAT-shared-bucket bug class.
**Track:** independent of S26 / S29 / S30. **Repo:** `vbwd-backend` (core).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID ·
DI · DRY · Liskov · clean code · NO OVERENGINEERING —
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).
Gate: `bin/pre-commit-check.sh --full` green.

---

## 1. Goal
A logged-in user gets their own quota bucket regardless of how many other
users (or other devices of theirs) share their IP. Unauthenticated routes
(login, register, password-reset) keep IP-keying — that is the only way to
protect them from per-IP brute-force.

## 2. Current flow (grounded)
- `vbwd/extensions.py:55` — `Limiter(key_func=get_remote_address, …)`.
- JWT payload: HS256, holds `user_id` (UUID string) — see
  `vbwd/services/auth_service.py:113-133`. `Authorization: Bearer <jwt>` is
  the standard header (`vbwd/middleware/auth.py:28-37`).
- PyJWT (`import jwt`) is already a dep (used by auth_service + meinchat
  stream_token + ghrm).

## 3. Design
One new helper, one line edit to swap the keyfunc.

```python
def _rate_limit_key_func() -> str:
    """Prefer authenticated user when JWT is present, fall back to IP.

    Decodes the JWT *without* signature verification — we only use the
    payload as a bucket label. Forging a JWT lets an attacker spend
    someone else's quota, not impersonate them; the actual auth check
    runs later in @require_auth and uses signed verification.
    """
    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        token = auth_header.split(None, 1)[1].strip()
        try:
            payload = jwt.decode(
                token, options={"verify_signature": False}
            )
            user_id = payload.get("user_id")
            if isinstance(user_id, str) and user_id:
                return f"user:{user_id}"
        except jwt.PyJWTError:
            pass
        except (ValueError, AttributeError):
            pass
    return f"ip:{get_remote_address()}"
```

Then `Limiter(key_func=_rate_limit_key_func, …)`. No other change.

### What we explicitly do NOT do (NO OVERENGINEERING)
- No signature verification in the keyfunc — wastes ~50µs per request for
  zero gain on this surface.
- No JWT-claims caching beyond what PyJWT does. Decoding is cheap.
- No env switch between IP-keying and user-keying — the hybrid (user when
  present, IP otherwise) is strictly better; no operator should want plain
  IP-only after this lands.

### SOLID / DI / DRY / Liskov
- **SRP**: helper does one thing — pick a bucket label.
- **OCP**: future "shared org bucket for SSO tenants" plugs in by reading a
  different claim from the payload; no caller change.
- **DRY**: bucket prefix is the only source of truth (`user:` / `ip:`).
- **Liskov**: keyfunc return type is unchanged (`str`); all per-route
  `@limiter.limit(...)` decorators keep working unchanged.

## 4. TDD (RED first)
All in new `vbwd-backend/tests/unit/extensions/test_rate_limit_key_func.py`:

1. `test_returns_ip_when_no_auth_header` — `Authorization` absent → `"ip:<remote>"`.
2. `test_returns_ip_when_non_bearer_scheme` — `Authorization: Basic …` →
   `"ip:<remote>"`.
3. `test_returns_user_when_bearer_jwt_present_with_user_id` — forge a JWT
   carrying `{"user_id": "<uuid>"}` → `"user:<uuid>"`.
4. `test_returns_ip_when_bearer_token_is_garbage` — `Authorization: Bearer
   not-a-jwt` → `"ip:<remote>"` (no crash).
5. `test_returns_ip_when_jwt_lacks_user_id_claim` — JWT with empty payload
   → `"ip:<remote>"`.
6. `test_signature_not_verified` — JWT signed with WRONG secret but valid
   shape → still extracts `user_id` and returns `"user:<uuid>"` (proves we
   skip signature verification deliberately).
7. `test_case_insensitive_bearer_scheme` — `Authorization: BEARER <jwt>` →
   `"user:<uuid>"`.

## 5. Files
| Action | Path |
| --- | --- |
| edit | `vbwd-backend/vbwd/extensions.py` — add `_rate_limit_key_func`; pass it to `Limiter(...)` |
| new  | `vbwd-backend/tests/unit/extensions/test_rate_limit_key_func.py` |

## 6. Acceptance
- 7 new specs green.
- Existing `tests/unit/routes/test_rate_limiting.py` (16 specs including
  S27's) still green.
- `bin/pre-commit-check.sh --full` green.
- Live proof in running api: send two GETs with two different JWTs from the
  same IP → two distinct buckets (no quota interference).
