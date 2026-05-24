# Sprint 01 — fe-user flashes the dashboard on a stale session

**Status:** IMPLEMENTED & E2E-VERIFIED — 2026-05-23 (unit + lint green;
**e2e green** against the running stack on 2026-05-23 —
`vue/tests/e2e/stale-session-no-flash.spec.ts` **2 passed** via
`E2E_BASE_URL=http://localhost:8080`: protected `/dashboard` with an expired
token → `/login` with no dashboard flash and the token purged). Files:
`vue/src/api/token.ts` (new), `vue/src/api/index.ts`
(`isAuthenticated`/`clearApiAuth`), `vue/src/App.vue` (`showLayout` → DRY),
`vue/src/views/Dashboard.vue` (`data-testid="dashboard-root"`), plus
`token.spec.ts`, `auth-state.spec.ts`, `stale-session-no-flash.spec.ts`.
Unit: 19 passed (incl. existing session-expiry). Lint: 0 errors. Typecheck:
no new errors (pre-existing payment-plugin `resp: unknown` errors untouched).
**Redirect-target correction:** the post-detection destination for the
*root* is governed by [sprint 02](02-fe-user-homepage-never-redirects-to-login.md)
— `/` never goes to `/login`; the e2e here was retargeted to `/dashboard`
(the protected route) to prove the no-flash + login-only-for-inner-world
behaviour.
**App:** `vbwd-fe-user` (port 8080)
**Severity:** Medium-High — protected content (the user dashboard) is
painted for a fraction of a second to a session that is no longer valid,
before the app redirects to login. Perceived as a security/quality bug.
**Repos:** `vbwd-fe-user` only (host app `vue/src/`). No core, no backend.
**Principles:** TDD (tests first), SRP/SOLID, Liskov, DI, DRY, no
overengineering.

---

## 1. Failure analysis (root cause, not symptom)

### Observed

1. Open `vbwd.cc`, log in. → dashboard.
2. Close the browser window/tab.
3. Re-open `vbwd.cc`.
4. The **dashboard renders visibly for a fraction of a second**, then the
   session-expired modal appears / the app redirects to `/login`.

The correct behaviour: a user whose session is no longer valid must land
on `/login` (or the public home) **without ever seeing the dashboard**.

### Why it happens — the exact call chain

The auth token is persisted in `localStorage`, which survives a window
close (it is not `sessionStorage`):

- `vue/src/views/Login.vue:74` — `localStorage.setItem('auth_token', …)`
- `vue/src/api/index.ts:88` — only cleared on explicit logout/expiry.

On re-open:

1. `vue/src/main.ts` boots → `initializeApi()` (`api/index.ts:23-33`)
   reads the **stale** token from `localStorage` and sets it on the
   singleton `ApiClient`.
2. Router guard `beforeEach` (`vue/src/router/index.ts:67-93`) runs.
   `isAuthenticated()` returns `true` and `sessionExpired.value` is
   `false` (it is a fresh page load, the ref is re-initialised to
   `false`). The guard therefore permits navigation.
3. `vue/src/views/Home.vue:34` — `onMounted` falls through to
   `if (isAuthenticated()) router.replace('/dashboard')`.
4. The guard re-runs for `/dashboard` (`requiresAuth: true`), sees the
   token present → **allows it**. `Dashboard.vue` mounts and **paints**.
5. Dashboard's data calls go out with the dead token → backend returns
   `401` → `ApiClient` emits `token-expired`
   (`vbwd-fe-core/src/api/ApiClient.ts:78`) →
   `handleSessionExpiry()` (`api/index.ts:47`) → `sessionExpired = true`
   → modal / redirect.

The flash is the window between **step 4 (paint)** and **step 5 (the 401
round-trip resolves)**.

### The actual defect

`isAuthenticated()` answers the wrong question:

```ts
// vue/src/api/index.ts:95-97
export function isAuthenticated(): boolean {
  return !!localStorage.getItem('auth_token');   // "is there a string?"
}
```

It checks *"does a token string exist?"* — not *"is there a valid,
unexpired session?"*. Our tokens are JWTs (the backend signs with
`JWT_SECRET_KEY`); a JWT carries an `exp` claim that can be read
**client-side at zero network cost**. We never read it. So the app gates
protected UI optimistically and only discovers the truth after a server
round-trip — which is exactly the flash.

### Secondary defect (DRY)

The same question is asked in three places with **two** implementations:

- `router/index.ts:68` → `isAuthenticated()`
- `views/Home.vue:34` → `isAuthenticated()`
- `App.vue:39` → `localStorage.getItem('auth_token')` **directly**
  (`showLayout`), bypassing `isAuthenticated()`.

`App.vue` must go through the single source of truth too, or it will
render the authenticated chrome (`UserLayout`) around an expired session.

---

## 2. Design

### SRP — extract token validity as a pure unit

New module `vue/src/api/token.ts`, two pure functions, no side effects,
no network:

```ts
// Read the `exp` (seconds since epoch) from a JWT payload, or null if the
// token is not a decodable 3-part JWT. Signature-BLIND by design: the
// server still verifies the signature on every request — this is a UX
// gate, not an authorization decision. (Documented in the file header.)
export function decodeJwtExp(token: string): number | null

// `now` is injected for deterministic tests (DI); defaults to Date.now.
export function isTokenExpired(token: string, now?: () => number): boolean
```

### Liskov / DI

`isTokenExpired` takes the clock as a parameter. Any conforming
`() => number` (a frozen fake clock in tests, real `Date.now` in prod) is
substitutable without changing the contract — that is the Liskov point,
made concrete and testable.

### DRY — one source of truth

`isAuthenticated()` becomes: *token present **and** not expired*. When it
detects an expired token it calls `clearApiAuth()` so the stale token is
gone and no later code path fires a doomed request:

```ts
export function isAuthenticated(): boolean {
  const token = localStorage.getItem('auth_token');
  if (!token) return false;
  if (isTokenExpired(token)) {
    clearApiAuth();          // purge stale token → no 401 round-trip later
    return false;
  }
  return true;
}
```

`App.vue:39` `showLayout` switches from the raw `localStorage` read to
`isAuthenticated()`.

The router guard and `Home.vue` need **no change** — they already call
`isAuthenticated()`; they simply inherit the stricter, correct semantics.
That is the payoff of fixing the single source of truth.

### Conservative fallback (correctness, not overengineering)

If `decodeJwtExp` returns `null` (token is absent, malformed, or an opaque
non-JWT), `isTokenExpired` returns `false` → `isAuthenticated()` keeps the
**current** "present ⇒ authed" behaviour and lets the server's `401` be
the backstop. Rationale: never lock out a user holding a token we merely
fail to parse; only act when we can *prove* expiry from the `exp` claim.
The common case (a real, expired JWT) is fixed; the defensive case is
safe.

### What we deliberately do NOT build (no overengineering)

- **No preflight `/auth/verify` call on boot** — it adds a network hop and
  a spinner; the `exp` claim already holds the answer locally.
- **No refresh-token flow, no new Pinia auth store, no router Suspense.**
- **No client-side signature verification** — that is the server's job and
  would require the secret.
- **Keep the existing `401 → token-expired → handleSessionExpiry` path**
  untouched as the backstop for tokens that expire *mid-session* or are
  revoked server-side. We are adding an early, cheap gate, not replacing
  the late one.

---

## 3. TDD plan (write these RED first)

### 3.1 Unit — `vue/tests/unit/api/token.spec.ts` (new)

`decodeJwtExp`:
- returns the `exp` integer for a well-formed 3-part JWT.
- returns `null` for: empty string, non-JWT garbage, 2-part token,
  payload that is not valid base64url JSON, payload without `exp`.

`isTokenExpired` (inject a frozen clock):
- `false` when `exp` is in the future.
- `true` when `exp` is in the past.
- `false` when `decodeJwtExp` is `null` (conservative fallback).
- uses the **injected** `now`, not wall-clock (proves DI/Liskov).

Helper: build test JWTs in-test with
`base64url(JSON.stringify({exp})).` — no signing needed (decoder is
signature-blind).

### 3.2 Unit — `vue/tests/unit/api/auth-state.spec.ts` (new)

`isAuthenticated()`:
- `false` when no token.
- `true` when token's `exp` is in the future.
- `false` **and** `localStorage.auth_token` cleared when `exp` is in the
  past (regression assertion for this sprint).

(Existing `vue/tests/unit/api/session-expiry.spec.ts` stays green — the
mid-session 401 path is unchanged.)

### 3.3 E2E — `vue/tests/e2e/stale-session-no-flash.spec.ts` (new)

The behavioural guarantee:

1. Log in via the UI (reuse the helper used by `auth.spec.ts`).
2. Overwrite `localStorage.auth_token` with a **deliberately expired** JWT
   (`exp` in the past), via `page.evaluate`.
3. `page.goto('/')`.
4. Assert:
   - `await expect(page).toHaveURL(/\/login/)` — we end on login.
   - `await expect(page.getByTestId('dashboard-root')).toHaveCount(0)` —
     the dashboard root was **never attached** to the DOM.

If `Dashboard.vue`'s root lacks a stable hook, add
`data-testid="dashboard-root"` to it (single attribute, no logic change)
so the "never painted" assertion is unambiguous.

---

## 4. Implementation steps (only after the tests are red)

1. Add `vue/src/api/token.ts` (`decodeJwtExp`, `isTokenExpired`).
2. Rewrite `isAuthenticated()` in `vue/src/api/index.ts` to use
   `isTokenExpired` and `clearApiAuth()` on stale tokens.
3. Point `App.vue` `showLayout` (line 39) at `isAuthenticated()`.
4. Add `data-testid="dashboard-root"` to `Dashboard.vue` root if absent.
5. Run `npm run test` (unit) and the new e2e spec; `npm run lint`.

---

## 5. Files

| Action | Path |
| --- | --- |
| new | `vue/src/api/token.ts` |
| edit | `vue/src/api/index.ts` — `isAuthenticated()` |
| edit | `vue/src/App.vue` — `showLayout` uses `isAuthenticated()` |
| edit (maybe) | `vue/src/views/Dashboard.vue` — add `data-testid` |
| new test | `vue/tests/unit/api/token.spec.ts` |
| new test | `vue/tests/unit/api/auth-state.spec.ts` |
| new test | `vue/tests/e2e/stale-session-no-flash.spec.ts` |

No backend, core, or migration changes.

---

## 6. Acceptance criteria

- Re-opening with an **expired** JWT lands directly on `/login`; the
  dashboard is never painted (e2e `toHaveCount(0)` holds).
- A **valid** JWT still shows the dashboard immediately (no regression,
  no extra network hop).
- Mid-session expiry / server-side revocation is still caught by the
  existing `401 → SessionExpiredModal` (and `/checkout/*` reload) path.
- `npm run lint`, unit, and e2e all green; CI green.

---

## 7. Risks & edge cases

- **Clock skew.** If the client clock is behind the server, a valid token
  could be read as not-expired (harmless — server 401 backstop). If ahead,
  a still-valid token could be read as expired (would log the user out
  early). Keep it simple: no leeway initially. If field reports show
  premature logouts, add a small fixed skew allowance (e.g. treat as
  expired only if `exp + 30s < now`) — a one-line change localised to
  `isTokenExpired`. Do not add this speculatively.
- **Opaque / non-JWT tokens.** Covered by the conservative fallback in §2
  — undecodable ⇒ behave as today, server is the backstop.
- **Orphaned `user_permissions`.** Confirmed: `clearApiAuth()`
  (`api/index.ts:86-90`) removes `auth_token` and `user_id` but **not**
  `user_permissions`. After the stale-token purge, `getUserPermissions()`
  / `hasUserPermission()` would still read the dead session's perms. Fix
  in this sprint: add `localStorage.removeItem('user_permissions')` to
  `clearApiAuth()`, and assert it in `auth-state.spec.ts`.
