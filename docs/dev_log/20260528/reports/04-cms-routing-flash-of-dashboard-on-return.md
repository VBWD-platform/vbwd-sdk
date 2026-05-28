# fe-user — "flash of dashboard then public home" on return with a valid JWT

**Date:** 2026-05-28
**Repo:** `vbwd-fe-user` (`vue/src/` + `plugins/cms/`)
**Status:** **Diagnosed; fix proposed, not yet applied.** Not a regression
of [2026-05-23 / sprint 01](../../20260523/done/01-fe-user-flash-of-dashboard-on-stale-session.md)
or [2026-05-23 / sprint 02](../../20260523/done/02-fe-user-homepage-never-redirects-to-login.md)
— this is a **distinct, third defect** with the same surface symptom.

---

## 0. TL;DR

The user reopens the browser on `vbwd.cc/` (or has the tab restored
to `/`) while still holding a **valid** JWT. They see what looks like
the dashboard for a few hundred milliseconds, then the public home
page replaces it.

What they actually see is **`UserLayout` chrome** (the VBWD logo, the
sidebar, the Dashboard nav item, the mobile-header burger + cart) —
not the real dashboard content. The chrome paints because
`App.vue`'s `showLayout` resolves to `true` for any authenticated
visitor, regardless of which route is matched. `Home.vue` —
mounted on `/` — emits an empty `<div/>` while it awaits
`/api/v1/cms/routing-rules/middleware`. The user sees: authed chrome
wrapping nothing, for the duration of that fetch. Then the redirect
fires and `CmsPage` takes over with its own layout, the chrome
vanishes, and the public home renders.

Two clean defects, both in the route's design contract:

1. **Layout decision is auth-only, not route-aware.** `App.vue`
   shows `UserLayout` for *any* authenticated visitor, even on `/`
   while Home is still figuring out where to send them. So the
   half-redirect interval paints authed chrome.
2. **Home.vue applies the CMS default routing rule to authenticated
   users too.** The "default" rule is a *public* default — what
   anonymous visitors see at `/`. But the current code redirects
   even authenticated users to the rule's target, so a return
   visitor on `/` gets shipped to `/home` instead of `/dashboard`.

Either fix alone removes the perceived flash; both together also
restores correctness ("authed users see the dashboard at `/`").

---

## 1. Why the two prior fixes do not address this

| Sprint | What it fixed | Why it leaves this open |
|---|---|---|
| [2026-05-23 /01](../../20260523/done/01-fe-user-flash-of-dashboard-on-stale-session.md) — stale-session no-flash | Made `isAuthenticated()` parse the JWT `exp` claim so a return visitor with an **expired** token never paints the dashboard. | Today's reproducer holds a **valid** JWT. `isAuthenticated()` correctly returns `true`. The guard correctly allows `/dashboard`. The flash is not auth-gating — it is `UserLayout` chrome flickering during a decision that happens *after* `App.vue` paints. |
| [2026-05-23 /02](../../20260523/done/02-fe-user-homepage-never-redirects-to-login.md) — root never goes to `/login` | Replaced the `/login` fallback in `Home.vue` with `DEFAULT_PUBLIC_SLUG`; added the `/index.html` → `home` redirect. | This sprint **kept** the design that the CMS "default" routing rule wins at `/` for everyone. It only changed the *fallback when no rule exists*. The visitor's auth state is never considered when a rule resolves. |

The prior sprints solved expiry and login-bounce; neither sprint
audited the layout contract for the interval *between Home.vue
mounting and Home.vue's first navigation*, and neither audited
whether the CMS default rule should apply to authenticated users.

---

## 2. Exact call chain (grounded in code)

### Setup

- Auth token persisted in `localStorage` (line `Login.vue:74`); survives
  window close.
- `vue/src/factory.ts:42` calls `initializeApi()` on bootstrap →
  `ApiClient` token rehydrated.

### Reopen on `/` (the reproducer URL)

1. Browser hits `vbwd.cc/`. nginx serves `index.html` (SPA shell).
2. `factory.ts` runs through plugin install, addRoute, activate, then
   `await router.replace(location.pathname + …)` (factory.ts:94)
   — for `/` this is `replace('/')`. The router resolves
   `route.name === 'home'`, matching `Home.vue`.
3. `factory.ts` returns; `main.ts` calls `mount()`. Vue mounts
   `App.vue`.
4. `App.vue:36-41` computes `showLayout`:
   ```ts
   if (isEmbedRoute.value) return false;
   if (isCmsLayoutRoute.value) return false;     // home route has no `cmsLayout`
   if (route.meta.noLayout === true) return false; // home route has no `noLayout`
   return isAuthenticated() || route.meta.publicLayout === true;
   ```
   `isAuthenticated() === true` for our valid JWT → `showLayout = true`.
5. `App.vue:7-9` renders `<UserLayout><router-view /></UserLayout>`.
6. `UserLayout.vue:7-93` paints the chrome: mobile header (logo + cart
   button), sidebar (VBWD logo + Dashboard nav item + plugin nav
   items). Inside `<router-view>` lives `Home.vue` (`<div/>`).
7. `Home.vue:18` `onMounted` fires. It `await`s
   `api.get('/cms/routing-rules/middleware')`. For the duration of
   this fetch (typically 50–200 ms over the network plus Flask
   request), step 6 stays on screen.
8. Fetch resolves. A `default` rule exists in CMS pointing at
   `/home` → `Home.vue:31` calls `router.replace('/home')`.
9. `/home` matches the CMS plugin's catch-all `/:slug(.+)`
   (`plugins/cms/index.ts:31`), `meta.cmsLayout = true`.
10. `App.vue`'s `showLayout` re-computes:
    `isCmsLayoutRoute = true` → returns `false`. `UserLayout` is
    unmounted; the bare `<router-view />` renders `CmsPage.vue`.
11. The user sees the chrome disappear and the public home page
    replace it.

The visible "dashboard" is the **chrome of steps 5–10** — the sidebar
with a "Dashboard" link is what the eye reads as "I'm on the
dashboard."

### Reopen on `/dashboard` (browser tab restore)

Some browsers restore the last URL exactly. In that case `/dashboard`
is hit, the guard accepts it (valid JWT), `Dashboard.vue` mounts and
paints, and there is no flash. The reproducer flash only happens on
URLs that go through `Home.vue` — i.e. `/` and the redirected
`/index.html`.

---

## 3. The exact defects

### 3.1 `App.vue` — layout decision is auth-only

`vue/src/App.vue:36-41`:

```ts
const showLayout = computed(() => {
  if (isEmbedRoute.value) return false;
  if (isCmsLayoutRoute.value) return false;
  if (route.meta.noLayout === true) return false;
  return isAuthenticated() || route.meta.publicLayout === true;
});
```

The home route (`name: 'home'`) is a *redirect bouncer*. It never
shows real content — its template is literally `<div/>`. So
wrapping it in `UserLayout` is wrong in every case, not just for
authenticated users. There is no UX gain to showing chrome around
an empty `<div/>` for 50–200 ms.

### 3.2 `Home.vue` — CMS default rule fires for authenticated users too

`vue/src/views/Home.vue:18-39`:

```ts
onMounted(async () => {
  try {
    const rules = await api.get('/cms/routing-rules/middleware');
    const defaultRule = rules.find(r => r.is_active && r.match_type === 'default');
    if (defaultRule) {
      await router.replace(slug);   // ← runs for authed users too
      return;
    }
  } catch { /* fall through */ }
  router.replace(isAuthenticated() ? '/dashboard' : DEFAULT_PUBLIC_SLUG);
});
```

The auth check is only consulted in the **fallback** branch (no rule
resolved). When a rule resolves, every visitor — anonymous **or
authenticated** — is shipped to the rule target. So an authenticated
return visitor at `/` is sent to `/home` instead of `/dashboard`.

This is a **product-intent contradiction** with the sprint-02 test
in `vue/tests/unit/views/home-redirect.spec.ts:37-44`:

```ts
it('redirects to the CMS default routing-rule target when one exists', async () => {
  vi.mocked(api.get).mockResolvedValue([
    { match_type: 'default', target_slug: 'welcome', is_active: true, layer: 'middleware' },
  ]);
  await mountHome();
  expect(replace).toHaveBeenCalledWith('/welcome');
});
```

The test doesn't set `isAuthenticated()`, so it implicitly asserts
that the rule wins regardless of auth state. That assertion baked
the defect into the spec. The fix has to update this test too.

---

## 4. The fix

Two small, additive changes. No new module, no new API, no nginx
change, no schema change.

### 4.1 Mark the home route as layout-free (`vue/src/router/index.ts`)

Add one line to the existing `/` route record:

```ts
{
  path: '/',
  name: 'home',
  component: () => import('../views/Home.vue'),
  meta: { requiresAuth: false, noLayout: true },   // ← add noLayout
},
```

`App.vue:39` already short-circuits on `route.meta.noLayout === true`.
The chrome no longer paints around `Home.vue`. The user sees a blank
page (or a tiny spinner if you prefer — see §6) for the duration of
the routing-rules fetch. That blank is *expected for a redirect
bouncer*.

This change alone removes the **perceived** flash, even if §4.2 is
not done.

### 4.2 Skip the routing-rules fetch for authenticated users (`vue/src/views/Home.vue`)

The CMS "default" rule is a public default. Authenticated users have
a dashboard; they should land on it directly without paying for a
network round-trip first.

```ts
onMounted(async () => {
  // Authenticated users go straight to the dashboard. The CMS default
  // routing rule is a *public* default — anonymous-only. Skipping the
  // rules fetch here also eliminates the redirect-interval where
  // App.vue would paint chrome around an empty Home.vue (see §3.1 of
  // 20260528/04-cms-routing-flash-…).
  if (isAuthenticated()) {
    router.replace('/dashboard');
    return;
  }

  try {
    const rules = await api.get('/cms/routing-rules/middleware');
    const defaultRule = rules.find(r => r.is_active && r.match_type === 'default');
    if (defaultRule) {
      const slug = defaultRule.target_slug.startsWith('/')
        ? defaultRule.target_slug
        : `/${defaultRule.target_slug}`;
      await router.replace(slug);
      return;
    }
  } catch {
    /* fall through */
  }
  router.replace(DEFAULT_PUBLIC_SLUG);
});
```

Net effect: authed return visitor on `/` → synchronous
`router.replace('/dashboard')` before paint → `/dashboard` resolves
→ `Dashboard.vue` mounts. The `UserLayout` chrome is unambiguously
correct (it is *the* dashboard, not an interlude).

### 4.3 TDD: tests to add / amend

`vue/tests/unit/views/home-redirect.spec.ts`:

- **Amend test #1** ("redirects to the CMS default routing-rule
  target when one exists") to explicitly set
  `isAuthenticated()` to `false`. The CMS default rule applies
  to anonymous visitors *only*.
- **New test** `redirects an authenticated user to /dashboard
  without consulting the rules API`: assert that `api.get` is
  **not** called, and that `replace('/dashboard')` is the only
  navigation. Pins the §4.2 invariant.

`vue/tests/e2e/stale-session-no-flash.spec.ts` (extend or new sibling
spec `valid-session-no-chrome-flash.spec.ts`):

- Log in via UI (the existing helper).
- `page.goto('/')` (the trigger URL).
- Within the first 50 ms, assert that
  `page.getByText('Dashboard', { exact: true })` (the sidebar link)
  is **not** rendered — i.e. the `UserLayout` chrome never painted at
  `/` during the redirect. Then `expect(page).toHaveURL(/\/dashboard$/)`
  to confirm the final destination.

### 4.4 What we deliberately do NOT build

- **No `/auth/verify` preflight on boot** — the JWT `exp` already
  answers "valid?" at zero network cost.
- **No layout-thrash debouncer / Suspense / transition** — the goal
  is to never show the wrong chrome in the first place, not to
  paper over the visual with an animation.
- **No backend change.** The CMS routing-rules contract is
  unchanged. We are correcting the *fe-user consumer* of those
  rules, not the rules themselves.
- **No "fast path" cache of the default rule in localStorage** —
  authenticated users now never call the rules API; anonymous
  users are not the reproducer.

---

## 5. SOLID / DI / DRY / clean / agnostic

- **SRP** — `App.vue` decides layout from route metadata; `Home.vue`
  decides destination from auth state + (only when needed) the CMS
  default rule.
- **OCP** — adding a new layout mode (e.g. `embed`, `cmsLayout`,
  future `kiosk`) is metadata on the route, not code in `App.vue`.
- **DRY** — `noLayout: true` reuses the existing meta-flag mechanism
  in `App.vue:39`; no new pathway introduced.
- **Liskov** — the router-guard contract is unchanged; the home
  route's behaviour from the *router's* point of view is identical
  (it still resolves and redirects). Only the visual envelope
  changes.
- **Core agnostic** — both changes live in the fe-user host
  (`vue/src/`); the CMS plugin is untouched.

---

## 6. Risks & edge cases

- **Blank page interval for anonymous visitors.** With §4.1
  (`noLayout: true` on `/`) anonymous visitors see a blank page for
  the 50–200 ms while the routing-rules fetch runs. If this is
  noticed in field reports, the lightest fix is to add a one-line
  skeleton (logo + spinner) directly in `Home.vue`'s template, which
  is still less surface than `UserLayout`. Do not add this
  speculatively.
- **Brand-new authed user without a profile loaded.** §4.2 sends
  them straight to `/dashboard`; `Dashboard.vue` will issue its own
  data requests. No regression vs today (where they would hit
  `/home` then click "Dashboard" anyway).
- **CMS rule with a non-public target slug.** The §4.2 change makes
  rules apply only to anonymous visitors, so an admin can no longer
  override an authed user's landing page via a CMS rule. Treat as
  feature, not a regression — authed users *have* a destination
  (their dashboard) by definition; the CMS owns the public surface
  only.

---

## 7. Acceptance

- Open `vbwd.cc/` in an authenticated browser → `Dashboard.vue` paints
  directly, with no intermediate chrome flash of any kind. The
  sidebar's "Dashboard" link first appears as part of the actual
  dashboard view, never around an empty content area.
- Open `vbwd.cc/` in an anonymous browser → no chrome flash; goes
  to the CMS-rule target (or `/home` fallback).
- The original 2026-05-23 stale-token guarantees still hold: an
  expired JWT lands on `/login`, the dashboard is never painted.
- Unit + e2e green (`home-redirect.spec.ts` updated to the new
  contract; new e2e asserts no chrome at `/` during the auth
  redirect).

---

## 8. Files (when implementing)

| Action | Path |
|---|---|
| edit | `vue/src/router/index.ts` — add `noLayout: true` to the home route |
| edit | `vue/src/views/Home.vue` — synchronous `if (isAuthenticated()) router.replace('/dashboard')` before the rules fetch |
| edit | `vue/tests/unit/views/home-redirect.spec.ts` — amend test #1 (anonymous only); add the "skips rules + replaces to /dashboard" test |
| new (or extend) | `vue/tests/e2e/valid-session-no-chrome-flash.spec.ts` — UI-side assertion |

No backend, plugin, or core change. No migration.
