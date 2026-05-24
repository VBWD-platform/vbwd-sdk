# 2026-05-23 — Daily status

## Theme

fe-user authentication & homepage routing correctness: stop leaking the
authenticated dashboard to dead sessions, and stop bouncing the public
root to `/login`.

## Sprint index

| # | Sprint | Area | Status |
|---|--------|------|--------|
| 01 | [fe-user flashes the dashboard on a stale session](done/01-fe-user-flash-of-dashboard-on-stale-session.md) | fe-user auth | **Done — IMPLEMENTED & E2E-VERIFIED 2026-05-23** |
| 02 | [fe-user homepage must never default-redirect to login](done/02-fe-user-homepage-never-redirects-to-login.md) | fe-user routing | **Done — IMPLEMENTED & E2E-VERIFIED 2026-05-23** |

## Work done today

- **Sprint 01 — no flash of dashboard on a stale session.**
  - New pure module `vue/src/api/token.ts` (`decodeJwtExp`, `isTokenExpired`)
    — signature-blind JWT `exp` read, injectable clock (DI/Liskov).
  - `isAuthenticated()` now means *valid & unexpired*; purges the stale
    token (`clearApiAuth()` also clears `user_permissions`).
  - `App.vue` `showLayout` routed through `isAuthenticated()` (DRY); the
    router guard and `Home.vue` inherit the stricter semantics.
  - `Dashboard.vue` got `data-testid="dashboard-root"` for the no-flash
    assertion.
- **Sprint 02 — homepage never default-redirects to login.**
  - `Home.vue` drops the `/login` fallback: no CMS rule → authed
    `/dashboard`, anon `DEFAULT_PUBLIC_SLUG` (`/home`). Decision: anon
    no-rule fallback is a fixed public slug (user, 2026-05-23).
  - Core router normalises `/index.html` → `{ name: 'home' }` so it flows
    through the routing-rule logic instead of the CMS catch-all (404 on
    slug `"index.html"`).
  - Login redirect for `requiresAuth` routes (the "inner world") left
    unchanged — that is the only place login is reached.

## Verification

- **Unit:** 23/23 relevant green — `token.spec.ts` (11), `auth-state.spec.ts`
  (4), `home-redirect.spec.ts` (4), existing `session-expiry.spec.ts` (4).
- **Lint:** 0 errors in touched files (pre-existing warnings only).
- **Typecheck:** no new errors (pre-existing payment-plugin `resp: unknown`
  errors untouched).
- **E2E:** `vue/tests/e2e/stale-session-no-flash.spec.ts` green against the
  running stack via `E2E_BASE_URL=http://localhost:8080` — protected
  `/dashboard` with an expired token → `/login`, no dashboard flash, token
  purged; public `/` with an expired token → never `/login`.

## Pending — needs user action

- **Commit & push `vbwd-fe-user`.** Today's changes are unpushed:
  `vue/src/api/token.ts` (new), `vue/src/api/index.ts`, `vue/src/App.vue`,
  `vue/src/views/Home.vue`, `vue/src/views/Dashboard.vue`,
  `vue/src/router/index.ts`, plus the three test files.
- **Per-instance content check:** `/home` is only reached when no CMS
  `default` routing rule exists. Confirm each instance has either a default
  routing rule or a CMS page at slug `home`, so the fallback never 404s.

## Blockers

None.

## Follow-ups (deferred, not started)

- Promote `DEFAULT_PUBLIC_SLUG` to `VITE_DEFAULT_PUBLIC_SLUG` only if a
  second instance needs a different public root.
- Optional clock-skew leeway in `isTokenExpired` if field reports show
  premature logouts (server 401 remains the backstop today).
