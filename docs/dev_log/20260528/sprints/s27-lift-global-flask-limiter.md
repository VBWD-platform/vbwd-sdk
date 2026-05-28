# S27 — Lift the global Flask-Limiter ceilings (env-configurable)

**Status:** PLANNED — 2026-05-28. After S26 fixed the meinchat-specific 429,
both web and iOS now hit a **different** 429 with the body
`{"error": "Rate limit exceeded", "message": "10000 per 1 day"}`. The message
format is Flask-Limiter's, not the meinchat custom limiter — see
`vbwd/extensions.py:15-20`:

```python
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["10000 per day", "2000 per hour"],
    storage_uri=get_redis_url(),
)
```

That bucket is **shared per remote IP across the entire API**. Web + iOS on the
same wifi, mobile-carrier NAT, office network, or VPN exit-node share one
seat. Active app use (chat fetches, paging, inbox refresh, SSE → REST poll
fallback, image loads) crosses 6.94 req/min on average — easy to exceed.
**Track:** independent of S26. **Repo:** `vbwd-backend` (core, not a plugin).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI ·
DRY · Liskov · clean code · **core agnostic** (this IS the core; we touch
core because the limiter IS a core concern) · **NO OVERENGINEERING** —
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).
Gate: `bin/pre-commit-check.sh --full` green on `vbwd-backend`.

---

## 1. Goal (user value)

Normal app use never trips the global Flask-Limiter on a logged-in instance.
Specifically:

- A single user on a single device, actively using the chat + dashboard for an
  hour, never hits 429.
- Web + iOS for the same human user on the same IP do not interfere with each
  other.
- Ops can tune the ceilings per instance (vbwd.cc vs a private deployment vs a
  high-traffic exhibition mode) **via env vars** without touching code or
  redeploying the image — just edit `.env` and `docker compose restart api`.

Target defaults (subject to env override):

| limit          | today      | new default | env var                    |
| ---            | ---        | ---         | ---                        |
| per day        | 10 000     | 100 000     | `RATELIMIT_DEFAULT_DAY`    |
| per hour       | 2 000      | 20 000      | `RATELIMIT_DEFAULT_HOUR`   |
| storage        | redis URL  | unchanged   | `RATELIMIT_STORAGE_URL` (already supported by Flask-Limiter)  |
| enabled?       | always on  | env toggle  | `RATELIMIT_ENABLED` (already supported by Flask-Limiter — pinning that contract) |

The 10× lift reflects the actual usage pattern (six clients refreshing an
inbox at 1 Hz is normal, not abusive). Per-IP keying is **kept** — switching
to per-user keying is the right long-term fix but is out of scope for this
sprint (sketched as a follow-up in §7).

## 2. Current flow (grounded)

- **Where it lives.** `vbwd/extensions.py:15-20` constructs `Limiter(...)` with
  hardcoded `default_limits` and `key_func=get_remote_address`. Init in
  `vbwd/app.py:126` (`limiter.init_app(app)`).
- **What it covers.** Flask-Limiter applies `default_limits` to **every** view
  function the blueprint registers, unless that view has its own
  `@limiter.limit(...)` decorator. Today the only overrides are:
  - `vbwd/routes/auth.py` — 5 routes at `5000 per minute` (looser; tuned for
    brute-force protection on login).
  - `vbwd/routes/events.py:69` — `100 per minute` (the public webhook
    listener — already capped tighter than the default).
  - Everything else (user dashboard, invoices, plans, plugins, meinchat,
    cms, …) inherits the default `2000/h + 10000/day`.
- **Storage.** Redis via `storage_uri=get_redis_url()` (`vbwd/extensions.py:18`).
  Keys are namespaced `LIMITS/<key_func_result>/<route_name>/<window>`.
- **429 response shape.** Customised at `vbwd/app.py:317-340` — JSON body
  `{"error": "Rate limit exceeded", "message": "<descriptor>"}` plus a
  `Retry-After` header parsed from the descriptor when present. We DO NOT
  change this shape (it's already on prod; iOS + web parsers expect it).
- **Tests already in place.** `tests/unit/routes/test_rate_limiting.py`
  (12 specs) covers the contract — they're our regression net for the lift.
  Plugin conftests already set `RATELIMIT_ENABLED: False` in test apps so
  per-plugin unit tests don't accidentally hit the limiter — that contract
  has to keep working.

## 3. Design

Two additive edits. Nothing renamed; no public contract changes.

### 3.1 Env-driven defaults (`vbwd/extensions.py`)

Read defaults from env at module import time, fall back to the new
documented numbers:

```python
import os

from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

from vbwd.config import get_redis_url


def _global_default_limits() -> list[str]:
    """Read per-instance ceilings from env. Each is an integer count; the
    window unit is fixed (per day / per hour) so ops can tune the number
    without learning Flask-Limiter's mini-DSL. Values <= 0 → that window
    is omitted (operator can disable the day cap by setting it to 0)."""
    per_day = int(os.environ.get("RATELIMIT_DEFAULT_DAY", "100000"))
    per_hour = int(os.environ.get("RATELIMIT_DEFAULT_HOUR", "20000"))
    limits: list[str] = []
    if per_day > 0:
        limits.append(f"{per_day} per day")
    if per_hour > 0:
        limits.append(f"{per_hour} per hour")
    return limits


limiter = Limiter(
    key_func=get_remote_address,
    default_limits=_global_default_limits(),
    storage_uri=get_redis_url(),
    strategy="fixed-window",
)
```

That's it. The Flask-Limiter contract that `RATELIMIT_ENABLED` (read from
`app.config`) and `RATELIMIT_STORAGE_URL` (read from env at app init) **already
exist** in upstream — we don't reimplement them, we just pin their usage.

### 3.2 Document the env vars (`.env.example` if present, otherwise leave
the docstring carrying the contract)

```dotenv
# Global API rate limits (Flask-Limiter, per-IP). Bump for active deployments;
# zero disables that window. See vbwd/extensions.py:_global_default_limits.
RATELIMIT_DEFAULT_DAY=100000
RATELIMIT_DEFAULT_HOUR=20000

# Storage backend for the limiter (must be the same Redis your stack already
# runs). Flask-Limiter contract — passed through unchanged.
# RATELIMIT_STORAGE_URL=redis://redis:6379/1

# Master kill-switch for the global limiter. "False" / "false" / "0" disables.
# RATELIMIT_ENABLED=True
```

### 3.3 What we explicitly DO NOT do (NO OVERENGINEERING)

- **No per-user keying.** Real fix for "two devices on one wifi share a
  bucket" is to key by JWT subject when present. Adds a JWT-decode-without-
  verification dependency on every request (cheap but non-trivial). Tracked
  as a follow-up sprint in §7. The 10× lift alone takes today's repro out
  of the 429 zone.
- **No new admin UI.** This is an ops-level knob, not a per-tenant plugin
  setting. Setting it through fe-admin would require shipping the value into
  Flask-Limiter at request time (it reads at app init), which is a larger
  change for marginal value. Env var + restart is fine.
- **No exemption of high-traffic routes.** Tempting to add `@limiter.exempt`
  on the meinchat read paths (since S26's custom limiter already guards
  abuse on POSTs), but that's a per-route policy change we don't need yet
  if the new ceiling is high enough. Defer to data.
- **No change to the 429 response shape** or the `Retry-After` parser at
  `vbwd/app.py:317-340` — prod clients already parse this; respect Liskov.
- **No change to per-route overrides** (auth `5000/min`, events `100/min`).
  They are tighter or looser than the default for documented reasons; leave
  them alone.

### SOLID / DI / DRY / Liskov

- **SRP:** `_global_default_limits()` does one thing — read env into a list
  of descriptor strings. Limiter construction is one expression.
- **OCP:** new windows or new env vars = add another `os.environ.get` +
  append; no caller change.
- **DRY:** the day/hour numbers live in env only. No magic numbers in
  routes (the existing `@limiter.limit` literals are deliberate per-route
  overrides, which is a different concern).
- **Liskov:** `limiter` object's public interface is unchanged — every
  existing test, every existing `@limiter.limit(...)` decorator, every
  `RATELIMIT_ENABLED: False` test fixture keeps working.

## 4. TDD (RED first)

All tests in `vbwd-backend/tests/unit/routes/test_rate_limiting.py` (extend)
or new sibling module `test_global_rate_limit_env.py` for the env-driven
construction. Pure stdlib + Flask test client; the Redis backend is replaced
with `memory://` in the test app config (the conftest already does this).

### 4.1 Env-driven construction (`test_global_rate_limit_env.py`)

1. `test_defaults_when_env_unset` — clear `RATELIMIT_DEFAULT_DAY` +
   `RATELIMIT_DEFAULT_HOUR` from env; call `_global_default_limits()` →
   `["100000 per day", "20000 per hour"]`.
2. `test_env_overrides_day` — set `RATELIMIT_DEFAULT_DAY=42` →
   first descriptor is `"42 per day"`.
3. `test_env_overrides_hour` — set `RATELIMIT_DEFAULT_HOUR=7` →
   second descriptor is `"7 per hour"`.
4. `test_zero_day_disables_that_window` — set `RATELIMIT_DEFAULT_DAY=0`
   → result list contains only the hour entry, not a `"0 per day"` string.
5. `test_zero_hour_disables_that_window` — symmetric.
6. `test_non_integer_env_raises_at_construction` — set
   `RATELIMIT_DEFAULT_DAY=abc` → `ValueError` (fail fast — bad config
   should crash app startup, not silently fall through to ridiculous
   defaults).

### 4.2 Integration regression (extend `test_rate_limiting.py`)

7. `test_existing_per_route_overrides_unchanged` — assert that auth routes
   (`/api/v1/auth/login` etc.) still carry their `@limiter.limit("5000 per
   minute")` decorator and that the events webhook keeps `100 per minute`.
   (Pin the no-regression contract — the lift only touches the default.)
8. `test_429_response_shape_unchanged` — when the limiter does fire, body
   is still `{"error": "Rate limit exceeded", "message": "<descriptor>"}`
   and `Retry-After` is set when extractable. (Liskov check on the prod
   client contract.)
9. `test_ratelimit_enabled_false_still_disables` — `RATELIMIT_ENABLED:
   False` in app config → no 429 even at >100k requests. (Pin the test-
   harness contract that plugin conftests rely on.)

### 4.3 Live-prod negation (manual, after deploy)

Reproduce today's report: log in on web and iOS, both as the same user, on
the same wifi. Use the app actively for an hour (chat, dashboard, inbox).
No 429 from the global limiter. If a 429 appears, the body's `message` must
now reference the lifted number (`100000 per day` etc.), not the old
`10000 per day`.

## 5. Files

| Action | Path |
| --- | --- |
| edit | `vbwd-backend/vbwd/extensions.py` — extract `_global_default_limits()` from env; build `Limiter` from its result |
| edit | `vbwd-backend/.env.example` (if exists) — document the 3 env vars (see §3.2) |
| edit | `vbwd-demo-instances/instances/*/docker-compose.yml` (prod compose files for the public deployments) — set `RATELIMIT_DEFAULT_DAY=100000` + `RATELIMIT_DEFAULT_HOUR=20000` in the api service's env block. **Per memory `feedback_never_mix_local_and_prod_compose`: prod compose files are scp'd to VPS; only edit the prod files for variables that need to ship.** Confirm with the operator before touching them. |
| new  | `vbwd-backend/tests/unit/routes/test_global_rate_limit_env.py` — §4.1 (6 specs) |
| edit | `vbwd-backend/tests/unit/routes/test_rate_limiting.py` — §4.2 (3 specs) |

Out of code scope: fe-user / fe-admin / iOS — none. The 429 response shape
is unchanged, so all clients keep parsing it as-is.

## 6. Acceptance

- Today's prod repro stops 429-ing: web + iOS on the same IP, same user,
  active for an hour → no `"Rate limit exceeded"` from the global limiter.
- `RATELIMIT_DEFAULT_DAY` / `RATELIMIT_DEFAULT_HOUR` env vars take effect
  after `docker compose restart api` (Flask-Limiter reads them at app
  construction). Verified by setting `RATELIMIT_DEFAULT_DAY=5` in a local
  shell and seeing 429 after 6 requests.
- All 9 new/extended tests green.
- Existing 12 specs in `tests/unit/routes/test_rate_limiting.py` still
  green (no contract regression).
- `bin/pre-commit-check.sh --full` green on `vbwd-backend`.
- The 429 body shape `{"error": "...", "message": "..."}` and the
  `Retry-After` header are unchanged.
- `RATELIMIT_ENABLED: False` still disables the limiter (plugin conftest
  contract preserved).

## 7. Out of scope (follow-ups)

- **Per-user keying (S28 candidate).** Replace `get_remote_address` with a
  `_key_func` that decodes the JWT from `Authorization: Bearer …`
  (without signature verification — only used as a bucket label) and
  returns `f"user:{sub}"` if present, else `f"ip:{remote_addr}"`. Eliminates
  the NAT-shared-bucket class of bug. Requires PyJWT (already a dep via
  flask-jwt-extended) and a couple of route-level tests. Defer until after
  the lift lands — the lift alone resolves today's report.
- **Exempt the meinchat / cms read paths.** S26 already provides a per-user
  custom limiter for the meinchat routes that have real abuse vectors;
  having the global IP-limiter on top is belt-and-suspenders. If the lift
  isn't enough for the most active instances, add `@limiter.exempt` per
  route. Tracked as candidate S29.
- **Per-route configurability** (turn `5000 per minute` on auth into an env
  knob too). Not needed yet — those numbers are deliberately tuned for
  brute-force protection, and ops haven't asked.
- **429 telemetry.** Log every 429 with route + key + descriptor to
  Loki/Sentry so the next "users hit the cap" report is data-driven.
  Out of scope here.
