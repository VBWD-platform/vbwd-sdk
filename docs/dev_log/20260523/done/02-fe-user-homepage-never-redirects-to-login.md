# Sprint 02 — fe-user homepage must never default-redirect to login

**Status:** IMPLEMENTED & E2E-VERIFIED — 2026-05-23 (unit + lint green;
**e2e green** against the running stack on 2026-05-23 — the "public root with
an expired token → never `/login`" case in
`vue/tests/e2e/stale-session-no-flash.spec.ts` **passed** via
`E2E_BASE_URL=http://localhost:8080`). Builds on / corrects the redirect
target chosen in
[sprint 01](01-fe-user-flash-of-dashboard-on-stale-session.md).
**App:** `vbwd-fe-user` (port 8080)
**Severity:** Medium — public visitors (and anyone with an expired session)
hitting the site root were bounced to `/login` instead of the public
homepage; `/index.html` 404'd instead of resolving the homepage.
**Repos:** `vbwd-fe-user` only. No backend, no core.
**Principles:** TDD, SRP/SOLID, DRY, no overengineering.

---

## 1. Requirement

The CMS plugin owns **routing rules** (single source of truth for where the
root resolves). The homepage is a *public* page:

- `<domain>/` → resolves via CMS routing rules to a public page.
- `<domain>/index.html` → same resolution as `/`.
- The root must **never** redirect to `/login` by default.
- A redirect to `/login` happens **only** when an unauthenticated user
  requests a protected "inner-world" route (dashboard & friends).

## 2. Failure analysis (root cause)

### 2.1 `Home.vue` fell back to `/login`

`vue/src/views/Home.vue` fetched `/cms/routing-rules/middleware`, and when
**no** `default` rule was configured (or the call failed) it ran:

```ts
if (isAuthenticated()) router.replace('/dashboard');
else                   router.replace('/login');   // ← wrong
```

So any anonymous visitor — or any returning user whose JWT had expired
(see sprint 01) — was sent to the login screen from the site root. The root
is public; this is the defect.

### 2.2 `/index.html` never reached the homepage logic

`Home.vue` is bound to the route `/` only. nginx serves the SPA for
`/index.html` (`try_files … /index.html`), but Vue Router had **no**
`/index.html` route, so it fell into the CMS plugin catch-all
`/:slug(.+)` (`vbwd-fe-user/plugins/cms/index.ts`) as the literal slug
`"index.html"` → `GET /api/v1/cms/pages/index.html` → 404. The
routing-rule resolution never ran for `/index.html`.

### 2.3 Login redirect for protected routes was already correct

`vue/src/router/index.ts:76-81` redirects to `login` only when
`to.meta.requiresAuth && !authenticated`. That is exactly "login only for
the inner world" — left unchanged.

## 3. Design

### 3.1 `Home.vue` — drop the `/login` fallback (DRY with the guard)

The root never decides "login"; that decision belongs solely to the router
guard. New fallback when no CMS rule resolves:

- authenticated → `/dashboard`
- anonymous → `DEFAULT_PUBLIC_SLUG` (`/home`)

```ts
// The homepage is a PUBLIC page — the root never bounces to /login.
const DEFAULT_PUBLIC_SLUG = '/home';
…
router.replace(isAuthenticated() ? '/dashboard' : DEFAULT_PUBLIC_SLUG);
```

`DEFAULT_PUBLIC_SLUG` is a single named constant — no env plumbing, no
config service (no overengineering). It is the destination **only** when
the CMS has no `default` routing rule; in production a rule exists and wins
first.

> **Decision (user, 2026-05-23):** when no routing rule resolves, an
> anonymous visitor is redirected to a fixed public slug (`/home`), rather
> than rendering a built-in landing or staying on a blank `/`.

### 3.2 `/index.html` → normalise to `/`

Add a declarative redirect in the core router so `/index.html` flows
through the same homepage routing-rule logic instead of the CMS catch-all:

```ts
{ path: '/index.html', redirect: { name: 'home' } }
```

Static paths outrank the `/:slug(.+)` param route in Vue Router's match
ranking, so this wins deterministically.

### 3.3 Interaction with sprint 01

Sprint 01 made `isAuthenticated()` reject an expired JWT before the
dashboard paints. Its first-draft e2e asserted the root went to `/login`
for an expired token — which **contradicts this sprint**. Corrected: the
no-flash guarantee is asserted on the protected route (`/dashboard`), and a
new assertion proves the root never lands on `/login`.

## 4. TDD

### Unit — `vue/tests/unit/views/home-redirect.spec.ts` (new, 4 tests)
- default rule present → redirect to its target slug; not `/login`.
- no rule + authed → `/dashboard`; not `/login`.
- no rule + anon → `/home`; not `/login`.
- rules call throws → `/home`; not `/login`.

### E2E — `vue/tests/e2e/stale-session-no-flash.spec.ts` (updated)
- protected route + expired token → `/login`, `dashboard-root` count 0,
  token purged.
- root `/` + expired token → **not** `/login`.

## 5. Files

| Action | Path |
| --- | --- |
| edit | `vue/src/views/Home.vue` — drop `/login` fallback, add `DEFAULT_PUBLIC_SLUG` |
| edit | `vue/src/router/index.ts` — `/index.html` → `{ name: 'home' }` |
| new test | `vue/tests/unit/views/home-redirect.spec.ts` |
| edit test | `vue/tests/e2e/stale-session-no-flash.spec.ts` |

## 6. Acceptance criteria

- `/` and `/index.html` resolve to a public page via CMS routing rules; with
  no rule, anon → `/home`, authed → `/dashboard`. Never `/login`.
- Unauthenticated access to a `requiresAuth` route still redirects to
  `/login` (unchanged guard).
- Unit + lint green. (`npm run test`: home-redirect 4/4; sprint-01 api
  suites still green. Lint: 0 errors.)

## 7. Notes / follow-ups

- The frontend only consumes the `match_type === 'default'` rule for the
  homepage; other rule types (`path_prefix`, `language`, `country`, …) are
  evaluated by the backend middleware / nginx layer, not here. Out of scope.
- If `/home` should be a different slug per instance, promote
  `DEFAULT_PUBLIC_SLUG` to `VITE_DEFAULT_PUBLIC_SLUG` later — deferred until
  a second instance actually needs it.
