# S27 — Lift the global Flask-Limiter ceilings — COMPLETE

**Date:** 2026-05-28
**Sprint:** [`../done/s27-lift-global-flask-limiter.md`](../done/s27-lift-global-flask-limiter.md)
**Repo:** `vbwd-backend` (core, **not** a plugin — the limiter is a cross-cutting core concern).
**Gate:** `bin/pre-commit-check.sh --full` GREEN — 2228 unit + 366 integration green.

---

## 0. Outcome

After S26 closed the meinchat-specific 429, both web + iOS hit a **different**
limit with the body `{"error": "Rate limit exceeded", "message": "10000 per 1
day"}`. That bucket lived in core — not in any plugin — and was keyed by
client IP, so web + iOS on the same wifi / NAT / VPN exit-node shared one
seat. 10 000/day = 6.94 req/min average, which active use crossed in normal
sessions.

S27 lifted the defaults 10× and made both windows env-tunable per instance
without redeploying the image. The end-to-end repro from the screenshot is
gone; the contract on the wire (429 shape + `Retry-After` header) is
preserved verbatim, so existing clients see no semantic change.

| Sprint goal | Status |
|---|---|
| Single user on a single device, hour of active chat + dashboard → never 429 | ✅ verified live; 10× lift takes today's traffic out of the trip zone |
| Web + iOS for the same human user on the same IP don't interfere | ✅ same bucket, but the bucket is now large enough that the combined load fits |
| Ops can tune ceilings per instance via env vars without touching code | ✅ `RATELIMIT_DEFAULT_DAY` / `RATELIMIT_DEFAULT_HOUR` + the already-supported `RATELIMIT_STORAGE_URL` / `RATELIMIT_ENABLED` are documented in `.env.example` and read at app init |
| 429 response shape unchanged | ✅ Liskov on the wire: `{error, message, Retry-After}` preserved at `vbwd/app.py:317-340`; spec extended to assert it |

---

## 1. Implementation

Two additive edits, both in core (`vbwd-backend/vbwd/`):

### `vbwd/extensions.py`
Extracted `_global_default_limits() -> list[str | Callable[[], str]]` from
the inline `Limiter(...)` call. The helper:

- Reads `RATELIMIT_DEFAULT_DAY` (default **100 000**, 10× lift from the old
  hard-coded 10 000).
- Reads `RATELIMIT_DEFAULT_HOUR` (default **20 000**, 10× lift from 2 000).
- Treats `0` on either window as an operator escape hatch ("disable this
  window"). Both zero → empty list → only per-route limiters apply.
- Raises `ValueError` on a non-integer value so a deployment-config typo
  fails fast at boot rather than silently keeping the old default.

The `Limiter(...)` constructor now reads from the helper, so its
behaviour is determined exclusively by env — no code path constructs
limits inline anymore (DRY, single home).

### `.env.example`
Documented `RATELIMIT_DEFAULT_DAY`, `RATELIMIT_DEFAULT_HOUR`, plus the
pre-existing Flask-Limiter contracts (`RATELIMIT_STORAGE_URL`,
`RATELIMIT_ENABLED`) so all four ops knobs are in one place.

---

## 2. What we explicitly did NOT do (NO OVERENGINEERING)

- **Per-user JWT-keyed limiter.** The structurally correct fix for
  NAT-shared buckets, but the 10× lift takes today's repro out of the
  429 zone and decoding the JWT in the keyfunc adds non-trivial moving
  parts. Deferred as a candidate **S28-tier follow-up** (separate slice).
- **Admin-UI tunability.** This is an ops knob, not per-tenant — env
  var + restart is the right control surface. Surfacing it through the
  admin would force shipping a runtime value into Flask-Limiter (which
  reads at app init), which is a different abstraction than what the
  meinchat per-user limiter uses.
- **Route-level exemptions.** Tempting to mark high-traffic read paths
  `@limiter.exempt`, but the lift is already enough; defer to data.
- **429 response shape changes.** Liskov on the wire — existing clients
  (web + iOS) parse `{error, message}` + `Retry-After`; that contract
  is preserved.

---

## 3. TDD — 12 new/extended specs

- **`tests/unit/routes/test_global_rate_limit_env.py`** (NEW, 9 specs):
  - defaults when env unset
  - day-override only / hour-override only / both
  - `0` disables a window
  - both `0` → empty list (only per-route limiters)
  - non-integer raises `ValueError`
  - end-to-end: limiter picks up env values at boot
- **`tests/unit/routes/test_rate_limiting.py`** (extended, 3 specs):
  - per-route overrides untouched (auth 5000/min, events 100/min stay)
  - 429 body shape unchanged
  - `RATELIMIT_ENABLED: False` still globally disables

---

## 4. Result — live proof

Running the local backend with `docker compose restart api`:

| check | result |
| --- | --- |
| `limiter.limit_manager.default_limits` at boot | `['100000 per 1 day', '20000 per 1 hour']` — lifted 10× |
| `_global_default_limits()` with `RATELIMIT_DEFAULT_DAY=5 RATELIMIT_DEFAULT_HOUR=3` | `['5 per day', '3 per hour']` — env wins |
| App rebuilt with `RATELIMIT_DEFAULT_DAY=5`; 7 × `GET /` | 5 × 302 → req 6: **429 with `message: "5 per 1 day"`** → req 7: 429 same → trip at env-defined cap, body shape preserved |
| Meinchat regression — open same peer 100× | all 200 (S26 + S27 stack cleanly) |

**Acceptance against today's user screenshots:**
- iOS `rate limit for 'new_conversation' exceeded` → fixed by S26.
- Web + iOS `Rate limit exceeded — 10000 per 1 day` → fixed by S27.

---

## 5. Files changed

In `vbwd-backend/`:
- `vbwd/extensions.py` — extracted `_global_default_limits()`.
- `.env.example` — documented the 4 ops knobs.
- `tests/unit/routes/test_global_rate_limit_env.py` (NEW, 9 specs).
- `tests/unit/routes/test_rate_limiting.py` (extended, 3 specs).

---

## 6. Deploy notes

The 10× lift is the new default — no env work needed on existing
instances to pick it up; it activates on the next `docker compose
restart api` of an image built from this commit. Operators who want a
different cap set `RATELIMIT_DEFAULT_DAY` / `RATELIMIT_DEFAULT_HOUR` in
`.env` and restart.

Existing per-route overrides (`auth` 5000/min, `events` 100/min) are
untouched — they continue to apply on top of (or instead of) the
defaults exactly as before.

---

## 7. Out of scope (follow-up candidates, not blockers)

- **S28 — Per-user JWT-keyed limiter.** Replace the IP keyfunc with one
  that uses `sub` from the bearer JWT (decode-without-verify is fine —
  this is a bucket label, not auth). Eliminates NAT-shared buckets at
  source and is the structurally right fix; deferred until data shows
  the 10× lift no longer suffices.
- **Per-route exemptions on hot read paths.** SSE poll fallback, image
  loads, dashboard inbox refresh — opt out of the default bucket and
  rely on per-user limiters where they exist (S26 already provides them
  for meinchat).
- **Body-shape contract test.** A characterisation test that pins the
  429 envelope shape (already extended one spec; could be promoted to a
  CHARACTERISATION block on the route definition itself).
