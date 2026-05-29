# S29 — fe-user `/` no-chrome-flash on return with a valid JWT

**Status:** PLANNED — 2026-05-28. Today on prod the authenticated visitor
reopens `vbwd.cc/` (or has the tab restored there) and — for ~50–200 ms
— sees the `UserLayout` chrome (logo + "Dashboard" sidebar item +
mobile-header burger/cart) wrapping an empty `<div/>` from `Home.vue`,
then `Home.vue` redirects to the CMS public default (`/home`) and
the chrome disappears. The user reads the chrome as "the dashboard
flashed before the public home page replaced it."

**Track:** independent. **Repo:** `vbwd-fe-user` only (host app
`vue/src/`). No backend, no core, no migration.
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID ·
DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** —
[`../../20260525/sprints/_engineering-requirements.md`](../../20260525/sprints/_engineering-requirements.md).
Gate: `npm run test` (unit) + `npm run lint` + the new e2e green
against the running stack on port 8080.

**Diagnosis source:** [`../reports/04-cms-routing-flash-of-dashboard-on-return.md`](../reports/04-cms-routing-flash-of-dashboard-on-return.md)
— full call-chain, the two prior fixes that didn't help, and why.
**Builds on / does NOT regress:**
[2026-05-23/01 stale-session-no-flash](../../20260523/done/01-fe-user-flash-of-dashboard-on-stale-session.md)
and [2026-05-23/02 root-never-/login](../../20260523/done/02-fe-user-homepage-never-redirects-to-login.md).

---

## 1. Requirement (user value)

1. An **authenticated** return visitor opening `vbwd.cc/` (or the
   redirected `/index.html`) lands on `/dashboard` **without** an
   intermediate paint of `UserLayout` chrome around an empty
   `Home.vue`. From the user's eye, no flash of any kind: the
   dashboard either appears immediately or the page stays blank
   for the imperceptible interval of a single synchronous
   `router.replace`.
2. An **anonymous** visitor at `/` still resolves via the CMS
   default routing rule (or `DEFAULT_PUBLIC_SLUG` fallback) and
   still **never** lands on `/login`. The decision lives where it
   already lives — in `Home.vue` — but the layout decision in
   `App.vue` no longer paints chrome around it.
3. The prior 2026-05-23 stale-token contract still holds: an
   expired JWT lands on `/login` and the dashboard is never painted.

## 2. Failure analysis (in one paragraph; full chain in the report)

`App.vue:36-41` computes `showLayout` from auth state alone for any
route without `cmsLayout: true`, `noLayout: true`, or `embed: true`
metadata. `Home.vue` is a *redirect bouncer* mounted on `/` whose
template is literally `<div/>`. So for an authenticated visitor at
`/`, `App.vue` wraps the empty `<div/>` in `UserLayout` for the
duration of `Home.vue`'s async `/cms/routing-rules/middleware`
fetch. The chrome paints; the user reads it as the dashboard. Then
the rule resolves, the destination flips to `/home`, the new route
has `cmsLayout: true`, `showLayout` recomputes to `false`, the
chrome unmounts, and `CmsPage` paints. The "flash" is the
50–200 ms interval of chrome around nothing.

Secondary product-intent defect: `Home.vue:18-39` applies the CMS
*default* routing rule to authenticated visitors too. The default
rule is the **public** default — what an anonymous visitor sees at
`/`. An authenticated visitor has a destination *by definition*
(their dashboard); they should not be shipped to a public page by a
rule designed for anonymous traffic.

## 3. Design

Two narrow, additive edits. No new module, no new API, no new
pathway in `App.vue`. We reuse two mechanisms that already exist:
`route.meta.noLayout` (consulted at `App.vue:39`) and
`isAuthenticated()` (already the single source of truth — sprint 01).

### 3.1 `vue/src/router/index.ts` — mark `/` as layout-free

The home route is a redirect bouncer; it renders no real content.
Wrapping it in `UserLayout` was always wrong, not just for the
flash window. One line on the existing route:

```ts
{
  path: '/',
  name: 'home',
  component: () => import('../views/Home.vue'),
  meta: { requiresAuth: false, noLayout: true },   // ← new
},
```

`App.vue:39` already short-circuits: `if (route.meta.noLayout === true)
return false`. No `App.vue` change needed — that is the DRY win.

`/index.html` redirects to `name: 'home'` and inherits the meta.
No second edit there.

### 3.2 `vue/src/views/Home.vue` — synchronous auth-first short-circuit

The CMS default rule is anonymous-only. Authenticated visitors
should bypass the rules fetch and land on `/dashboard`
synchronously — that removes both the perceived flash and the
unnecessary network round-trip.

```ts
onMounted(async () => {
  // Authenticated visitors go straight to the dashboard. The CMS
  // default routing rule is the *public* default — anonymous-only.
  // Skipping the rules fetch here also avoids the redirect interval
  // where App.vue would paint UserLayout chrome around an empty
  // Home.vue. See docs/dev_log/20260528/reports/04-…flash….md.
  if (isAuthenticated()) {
    router.replace('/dashboard');
    return;
  }

  try {
    const rules: Array<{
      match_type: string;
      target_slug: string;
      is_active: boolean;
      layer: string;
    }> = await api.get('/cms/routing-rules/middleware');

    const defaultRule = rules.find(
      r => r.is_active && r.match_type === 'default',
    );
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

The `isAuthenticated() ? '/dashboard' : DEFAULT_PUBLIC_SLUG`
ternary at the bottom collapses to `DEFAULT_PUBLIC_SLUG` — the
authed branch is unreachable here because the auth check now runs
first. That is the *clean code* simplification, not extra logic.

### 3.3 What we deliberately do NOT build (NO OVERENGINEERING)

- **No `App.vue` change.** The `noLayout` mechanism already exists.
  Adding a new auth-and-route-aware computed property would
  duplicate logic that the route-meta flag already encodes (DRY).
- **No `/auth/verify` preflight.** The JWT `exp` claim already
  answers "valid?" at zero network cost (sprint 01).
- **No skeleton / spinner / transition** in `Home.vue`'s template.
  The redirect bouncer should be blank for the imperceptible
  interval of a synchronous `router.replace` (authed path) or the
  50–200 ms of the rules fetch (anonymous path). If field reports
  ever show the anonymous interval as user-visible, the lightest
  follow-up is a one-line logo+spinner in `Home.vue`'s template —
  deferred until reported.
- **No new layout mode**, no `Suspense`, no router transition
  config, no new computed in `App.vue`.
- **No backend change.** The CMS routing-rules contract is
  unchanged. We are correcting the *fe-user consumer* of those
  rules.
- **No `localStorage` cache of the default rule.** Authenticated
  visitors now never call the rules API; anonymous visitors are
  not the reproducer.

### 3.4 SOLID / DI / DRY / Liskov / clean / core-agnostic

- **SRP** — `App.vue` decides layout from route metadata;
  `Home.vue` decides destination. Each module keeps one reason to
  change. Neither grows.
- **OCP** — adding a new layout mode (e.g. `kiosk`, `embed`) is a
  new meta flag on the route, not a code change in `App.vue`. The
  `noLayout: true` flag is the third mode in this same family;
  consistent.
- **DRY** — `noLayout: true` reuses the existing meta-flag
  mechanism in `App.vue:39`. The `isAuthenticated()` check in
  `Home.vue` calls the single source of truth (the function
  established by sprint 01).
- **Liskov** — the router-guard contract is unchanged. The home
  route still matches `/` and still resolves to a redirect. From
  the router's point of view, behaviour is identical; only the
  visual envelope changes.
- **DI** — `Home.vue` already injects `useRouter()` and
  `isAuthenticated()`. The new short-circuit is a pure read of the
  injected dependency, not a new injection.
- **Clean code** — the authed-branch ternary collapses; no new
  branches; no new constants; no new files.
- **Core agnostic** — both edits live in `vue/src/`. The CMS plugin
  is untouched. No backend, no core, no plugin contract change.

## 4. TDD (RED first)

All tests under `vue/tests/`. Order: amend the unit specs to red
(under the new contract), implement §3.1 + §3.2 to green, then add
the e2e to red against the *unbuilt* image, rebuild, green.

### 4.1 Unit — `vue/tests/unit/views/home-redirect.spec.ts` (amend + add)

**Amend test #1 "redirects to the CMS default routing-rule target
when one exists"** — explicitly set `isAuthenticated()` to `false`.
The CMS default rule applies to anonymous visitors only. Without
this change the test silently passes for both auth states and
keeps baking the defect into the spec.

```ts
it('redirects an anonymous visitor to the CMS default rule target', async () => {
  vi.mocked(isAuthenticated).mockReturnValue(false);    // ← explicit
  vi.mocked(api.get).mockResolvedValue([
    { match_type: 'default', target_slug: 'welcome', is_active: true, layer: 'middleware' },
  ]);
  await mountHome();
  expect(replace).toHaveBeenCalledWith('/welcome');
  expect(replace).not.toHaveBeenCalledWith('/login');
});
```

**New test #5 — the §3.2 invariant:**

```ts
it('redirects an authenticated visitor to /dashboard WITHOUT calling the rules API', async () => {
  vi.mocked(isAuthenticated).mockReturnValue(true);
  await mountHome();
  expect(api.get).not.toHaveBeenCalled();                // pins the perf + no-flash win
  expect(replace).toHaveBeenCalledWith('/dashboard');
  expect(replace).not.toHaveBeenCalledWith('/login');
});
```

Existing tests #2–#4 stay as-is (already explicitly set
`isAuthenticated` for the no-rule branches).

### 4.2 Unit — `vue/tests/unit/router/home-route-meta.spec.ts` (NEW, ~15 LOC)

The `noLayout` flag is the load-bearing piece of §3.1. Pin it in a
spec so a future router refactor doesn't accidentally drop it.

```ts
import { describe, it, expect } from 'vitest';
import router from '../../../src/router';

describe('router: home route meta', () => {
  it('marks `/` as noLayout so App.vue does not paint chrome around the redirect bouncer', () => {
    const route = router.resolve('/');
    expect(route.meta.noLayout).toBe(true);
    expect(route.meta.requiresAuth).toBe(false);
  });
});
```

### 4.3 E2E — `vue/tests/e2e/valid-session-no-chrome-flash.spec.ts` (NEW)

The behavioural guarantee end-to-end. Reuses the existing login
helper.

```ts
import { test, expect } from '@playwright/test';
import { loginViaUi } from './helpers/auth';

test('authenticated visitor at / never paints UserLayout chrome', async ({ page }) => {
  await loginViaUi(page);                                // ends on /dashboard
  await page.goto('/');                                  // the reproducer trigger

  // Sidebar's "Dashboard" link is the visible signature of UserLayout
  // chrome. It must NOT exist while Home.vue is resolving its redirect.
  // The redirect is synchronous for an authed user (§3.2), so the URL
  // flips before paint.
  await expect(page).toHaveURL(/\/dashboard$/);
  // dashboard-root testid only exists in Dashboard.vue (added in
  // sprint 2026-05-23/01).
  await expect(page.getByTestId('dashboard-root')).toBeVisible();
});

test('anonymous visitor at / never paints UserLayout chrome', async ({ page }) => {
  await page.goto('/');                                  // no auth
  // Wait for the redirect to land somewhere; chrome should not appear
  // during the rules fetch because `/` has `noLayout: true` (§3.1).
  await page.waitForURL(url => !url.endsWith('/'), { timeout: 5000 });
  // The UserLayout sidebar has a stable hook on its root.
  await expect(page.locator('.user-layout')).toHaveCount(0);
});
```

### 4.4 No-regression assertion for sprints 01 + 02

`vue/tests/e2e/stale-session-no-flash.spec.ts` stays as-is. Its two
existing assertions ("expired token at protected route → /login,
dashboard never painted" and "expired token at / → not /login")
continue to hold:

- Stale token + `/dashboard` → router guard catches it (sprint 01).
- Stale token + `/` → `isAuthenticated()` returns `false` (sprint
  01), so §3.2's authed branch is skipped; the anonymous branch
  redirects to the CMS rule or `DEFAULT_PUBLIC_SLUG` (sprint 02).
  Neither path goes to `/login`.

Run the existing spec as part of this sprint's gate to prove it.

## 5. Files

| Action | Path |
|---|---|
| edit | `vue/src/router/index.ts` — add `noLayout: true` to the home route meta |
| edit | `vue/src/views/Home.vue` — synchronous `if (isAuthenticated()) router.replace('/dashboard'); return;` ahead of the rules fetch |
| edit | `vue/tests/unit/views/home-redirect.spec.ts` — amend test #1 (anonymous explicit) + add test #5 (authed skips rules) |
| new | `vue/tests/unit/router/home-route-meta.spec.ts` — pin `noLayout: true` |
| new | `vue/tests/e2e/valid-session-no-chrome-flash.spec.ts` — two assertions per §4.3 |

No backend, plugin, or core change. No migration. No new fe-core
import. No CMS plugin change.

## 6. Acceptance

- Reopen `vbwd.cc/` in an authenticated browser → URL flips to
  `/dashboard` before paint; `Dashboard.vue` is the first visible
  surface. The sidebar's "Dashboard" link first appears *as part
  of* the dashboard view, never around an empty content area.
- Reopen `vbwd.cc/` in an anonymous browser → no chrome flash;
  lands on the CMS default rule's slug (or `DEFAULT_PUBLIC_SLUG`).
- Reopen `vbwd.cc/dashboard` in an authenticated browser →
  unchanged from today: `Dashboard.vue` paints directly.
- Stale-token return visitor (sprint 01 case) → unchanged:
  `/dashboard` lands on `/login`, dashboard never painted; `/`
  lands on the CMS rule / `DEFAULT_PUBLIC_SLUG`, never `/login`.
- `npm run test` (unit): the 4 amended + 2 new unit specs green;
  the existing sprint-01 / sprint-02 specs unchanged and green.
- `npm run lint`: 0 errors.
- E2E `valid-session-no-chrome-flash.spec.ts`: both tests green
  against the running stack (`E2E_BASE_URL=http://localhost:8080`).
- `vue/tests/e2e/stale-session-no-flash.spec.ts`: still green
  (no regression of sprints 01 / 02).
- Grep oracle: `grep -n "noLayout: true" vue/src/router/index.ts`
  returns at least one line (pins §3.1 in source).

## 7. Risks & edge cases

- **Anonymous blank interval.** With §3.1 the anonymous visitor
  sees a blank page for the duration of the rules fetch
  (50–200 ms). If field reports flag this, the lightest follow-up
  is a one-line skeleton (logo + spinner) inside `Home.vue`'s
  template. Do **not** add speculatively — the current symptom is
  authed-only.
- **Future change adds an async path before the auth check in
  `Home.vue`.** The §4.1 test #5 asserts `api.get` is **not**
  called for authed users; any future regression that re-introduces
  an async pre-check breaks that test loudly.
- **Brand-new authed user without a profile loaded.** §3.2 sends
  them straight to `/dashboard`; `Dashboard.vue` issues its own
  data requests. No regression vs today (they would have clicked
  "Dashboard" from `/home` anyway).
- **CMS rule with a non-public target slug.** §3.2 makes the rule
  apply to anonymous visitors only. An admin can no longer
  override an authed user's landing page via a CMS rule. Treat as
  feature alignment with product intent, not a regression — authed
  users *have* a destination by definition; the CMS owns the public
  surface.
- **`isAuthenticated()` clock skew.** Unchanged from sprint 01:
  no leeway; if reports show premature logout, add `±30 s` in
  `isTokenExpired` (sprint 01 §7 — one-line change, localised).

## 8. Out of scope

- The 2026-05-23/01 + 02 expired-token / never-/login contracts
  (kept as-is; their tests remain in the gate).
- Backend CMS routing-rules contract.
- The `cms-page` catch-all route (still owns `/:slug(.+)` for
  `/home` and friends).
- iOS / fe-admin / fe-core (no changes).
- Performance polish on the `Home.vue` blank interval for anonymous
  visitors (deferred; see §7).
