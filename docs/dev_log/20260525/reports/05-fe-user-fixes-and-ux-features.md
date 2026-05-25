# Report — 2026-05-25 session: Sprint 11 complete + fe-user fixes & UX features

This report covers the full day's work: it wraps up the Sprint 11 subscription
extraction and then the round of **live fe-user fixes + UX features** that came
out of hands-on testing once the extraction was in place.

Read order for the day:
1. [`02-sprint11-day2-backend-complete.md`](02-sprint11-day2-backend-complete.md) — backend extraction (S4/S5/S1/S7-backend).
2. [`03-sprint11-day2-fe-and-oracles-complete.md`](03-sprint11-day2-fe-and-oracles-complete.md) — S6 (FE) + S7 oracles + decision log.
3. [`04-fix-test-connection-exhaustion.md`](04-fix-test-connection-exhaustion.md) — `--full` gate connection-leak fix.
4. **this file** — fe-user runtime fixes + two UX features.

---

## 1. Headline

Sprint 11 ("models leave core") is **complete (S1–S7)** and the backend quality
gate `bin/pre-commit-check.sh --full` is **green**. On top of that, four real
problems surfaced during manual fe-user testing were diagnosed and fixed, and
two requested UX features shipped. Everything was verified — backend via the
pre-commit gate, frontend via Playwright against the live dev server
(`localhost:8080`).

No commits were made by me (standing rule). The user committed the vbwd/ core
changes (`f63c550` / `a5378c5`); `plugins/` is gitignored in each repo, so all
plugin code lives on disk only.

---

## 2. Sprint 11 — subscription extraction (recap)

Core now keeps **only** `user`, `user_details`, `token*`, `invoice`,
`invoice_line_item`. The five subscription model classes live in the plugin; the
core invoice has no subscription/plan FK (link = the SUBSCRIPTION line item);
payment plugins use the `ISubscriptionLifecycle` port + line-item registry; both
FE apps' core invoice views/stores are subscription-agnostic; all three
agnosticism oracles are flipped; the decision log records A superseded / R3 / R4
resolved. Details in reports 02–03. Green across backend (1913 unit / 308
integration), fe-admin (441), fe-user (478).

---

## 3. Bug: `--full` connection exhaustion (report 04)

`pre-commit-check.sh --full` collapsed with a wall of `FATAL: sorry, too many
clients already`. Root cause: test apps leak SQLAlchemy engine pools (never
disposed) + a `drop_all()` lock-hang from sessions left idle-in-transaction +
the subscription scheduler started per test app with no `TESTING` guard.
**Fixed** with a repo-root `conftest.py` (dispose engines + `db.session.remove()`
after each test) and a `TESTING` guard on the subscription scheduler. Result:
unit phase 1742-passed-with-170-errors → **1913 passed, 0 errors** in ~1:41;
connections stay ~5 instead of exhausting 200.

---

## 4. fe-user runtime fixes (found via manual testing)

### 4a. Admin locked out of the whole fe-user app
Logged into fe-user as `admin@example.com` (SUPER_ADMIN), **every** nav item
(Subscription / Invoices / Add-ons / Plans / Tokens) silently did nothing.
Diagnosed with Playwright: directly visiting each route worked (pages render,
zero errors) — only the **nav click** failed. Cause: the router guard
redirects to `/dashboard` when a route's `requiredUserPermission` is missing,
and **admin's `user_permissions` was `[]`** — user-facing permissions were
computed only from access levels, with no admin bypass (unlike the admin-facing
`effective_permissions`, which already returns `["*"]` for SUPER_ADMIN).
**Fix:** `vbwd/models/user.py` — `effective_user_permissions` /
`has_user_permission` now return `["*"]` for SUPER_ADMIN (and ADMIN with no user
access level). Verified: admin login now returns `user_permissions: ["*"]` and
all nav navigates. Regression test: `tests/unit/test_admin_user_permissions.py`.

### 4b. Regular users couldn't open their own Subscription page
For a normal USER, the **Subscription** nav did nothing. The
`/dashboard/subscription` route required `subscription.manage`, which the
baseline "Logged In" access level doesn't grant — so a user couldn't even *view*
their own subscription. **Fix:** the route now requires the baseline
`subscription.plans.view` (every logged-in user has it); management actions in
the page can be gated separately. Verified with Playwright (regular user opens
the page, h1 "Subscription", shows active subs + Cancel).

---

## 5. UX features

### 5a. "Added to cart" toast
Adding a token bundle or add-on now shows a disappearing popup
(e.g. "✓ 100 Tokens added to cart" / "✓ Extra Storage — 50 GB added to cart")
that auto-dismisses after 3s (click to dismiss early). Built as a reusable
`ToastHost.vue` (mounted in `UserLayout`) driven by the shared fe-core event bus
(`AppEvents.NOTIFICATION_SHOW`) — works from both the core Tokens view and the
plugin Add-Ons view, with no fe-core rebuild (the `eventBus`/`AppEvents` exports
are already in the built dist). i18n key `cart.addedToCart` in core `en.json`
(other locales fall back). Verified with Playwright (both cases appear + auto-
dismiss).

### 5b. Add-ons list on the Subscription page
`/dashboard/subscription` now has an **Add-ons** card: an "Active add-ons" table
(Add-on · Price · Renews · Status) and a "Previous add-ons" table for
cancelled/expired ones, with rows linking to the add-on detail. Store gained a
`fetchAddons()` action (the `activeAddons`/`inactiveAddons` getters already
existed); the backend `GET /api/v1/user/addons` endpoint was already present.
i18n under `subscription.addons.*`. Verified live — shows the test user's active
"Extra Storage — 200 GB · $14.99 / MONTHLY · ACTIVE". (PENDING/awaiting-payment
add-ons are intentionally excluded from both lists.)

---

## 6. Method note

The fe-user issues were all **runtime/behavioural** (permission guards, missing
sections), invisible to unit tests. Driving a real browser with Playwright
against the live dev server — clicking nav, capturing console/page errors,
comparing direct-navigation vs click, and inspecting `localStorage` /the login
API — was what pinpointed each root cause quickly (e.g. proving routes/components
were fine and the failure was purely the permission guard).

## 7. To commit / ship
- Tracked, needs `git add`: `vbwd-backend/conftest.py`,
  `vbwd-backend/tests/unit/test_admin_user_permissions.py`.
- Tracked (already in vbwd/): `vbwd/models/user.py`.
- Gitignored plugin/FE trees (live on disk; ship via each app's build):
  subscription scheduler guard, fe-user `ToastHost.vue` + `UserLayout` mount,
  `Tokens.vue` / `AddOns.vue` / `Subscription.vue` + store + locale edits,
  the `/dashboard/subscription` route permission change.

## 8. Still open / optional
- **S8** (cosmetic): rename core token/invoice permissions out of the
  `subscription.*` namespace. Deferred.
- **A2**: extract the initial subscription table DDL from the core monolith
  migration. Deferred, prod-gated.
- Optional UX: a "Pending / awaiting payment" add-ons group; localise the new
  i18n keys beyond `en`; gate Subscription-page management actions behind
  `subscription.manage`.
