# S87 — Cookie / GDPR-DSGVO consent popup (fe-user CMS extension, standalone repo)

**Status:** DRAFT for negotiation — 2026-06-13.
**Repos touched:** **one NEW standalone repo** `vbwd-fe-user-plugin-cookie-consent` (an `vbwd-fe-user` plugin). **No core change, no backend change, no other plugin change.**
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · **Liskov** · clean code · **core agnostic (only plugins are gnostic)** · **NO OVERENGINEERING** (narrowest change that satisfies the req) · **plugin baseline config files** · **reuse the `vbwd-fe-core` design system** — see [`_engineering_requirements.md`](_engineering_requirements.md). **Gate: the fe-user quality gate GREEN — Vitest + ESLint + `vue-tsc` (`bin/pre-commit-check.sh` where wired).**

---

## 1. Goal

A site-wide **cookie / GDPR (DSGVO) consent popup** on the public `vbwd-fe-user` storefront. On first visit it blocks the page with an overlay offering exactly two actions:

- **Accept all** — consent granted; cookies/analytics allowed; **login and purchase enabled**. Popup closes; the decision is remembered.
- **Reject all** — consent denied; **the visitor cannot log in or buy** (auth + commerce routes are gated). Public CMS content stays browsable. A small persistent **"Cookie settings"** affordance lets them re-open the popup and change their mind (Accept → login/buy re-enabled).

It ships as **one new standalone plugin repo** (per [[feedback_plugins_always_in_own_repos]]), is a **named-export fe-user plugin**, mounts **without any core change**, and styles **only** through the `vbwd-fe-core` design system (theme-aware, mobile-app-ready).

### Decisions locked (2026-06-13)

- **fe-user only, one new repo.** `vbwd-fe-user-plugin-cookie-consent` (naming mirrors `vbwd-fe-user-plugin-cms-youtube`). No `vbwd/` core, no backend, no fe-admin, no other plugin edited.
- **Two buttons only — Accept all / Reject all.** No granular per-category toggles in P1 (NO OVERENGINEERING). Granular categories are an explicit future increment (§7).
- **Reject ⇒ no login, no buy.** Enforced by a plugin-registered **router guard** (`sdk.addRouterGuard`) over the auth + checkout routes. This is a deliberate **"no non-essential flows without consent"** stance — stricter than the GDPR *strictly-necessary* exemption — and it is what the product owner asked for. An admin toggle (`block_auth_and_commerce_on_reject`, default **true**) can relax it later without code change.
- **Self-mounting overlay (zero core change).** `App.vue` exposes no plugin overlay slot and the old site-wide `GlobalWidgets` seam is retired, so the plugin **mounts its own Teleport-to-body overlay in `activate()`** and tears it down in `deactivate()`. No SDK/core extension needed — the constraint *is* the design.
- **Client-side only.** Consent state lives in `localStorage` (versioned). No backend storage, no audit-log endpoint in P1 (§7 notes the upgrade path).

## 2. Context (verified against the code)

- **fe-user plugin shape:** named-export `IPlugin` from `vbwd-view-component` with `install(sdk)` / `activate()` / `deactivate()`, `locales/*.json` wired via `sdk.addTranslations`, `config.json` + `admin-config.json`, each plugin its **own git repo** (e.g. `plugins/theme-switcher/.git`, `plugins/cms-youtube`). [[feedback_plugins_always_in_own_repos]]
- **SDK surface** (`vbwd-fe-core/src/plugins/PlatformSDK.ts`): `addRoute`, `createStore`, `addTranslations`, **`addRouterGuard`**. There is **no** `addGlobalComponent` — confirming the **self-mount** approach for a persistent overlay.
- **Global-overlay precedent:** `vue/src/components/SessionExpiredModal.vue` and `vbwd-fe-core/src/components/ui/Modal.vue` both render via `<Teleport to="body">`; `App.vue` mounts global chrome itself and offers **no** plugin slot (and a test notes the site-wide `GlobalWidgets` mechanism was abandoned). So a plugin overlay must self-attach to `document.body`.
- **Auth route:** core `vue/src/router/index.ts` — `path: '/login'`, `name: 'login'`, `meta.requiresAuth: false`.
- **Commerce ("buy") routes:** checkout plugin — `name: 'checkout-public'` (`/checkout`), `'checkout-confirmation'`; subscription — `name: 'checkout-cart'` (`/dashboard/checkout/cart`), `/dashboard/checkout/:planSlug`; (shop checkout likewise routes under `/checkout*`). The guard matches a **configurable** set (route names + path-prefixes), so it stays decoupled from any specific commerce plugin.
- **Design system:** `vbwd-fe-core` owns generic UI + `var(--vbwd-*)` custom properties (theme-switcher / dark-mode aware, mobile-app-ready). [[project_fe_core_design_system]]
- **No existing consent/cookie code** anywhere in fe-user/fe-core — clean slate.

## 3. Design

### 3.1 The plugin (`vbwd-fe-user-plugin-cookie-consent`)

```
plugins/cookie-consent/                # standalone repo, dropped in as a fe-user plugin
├── index.ts                           # named export `cookieConsentPlugin` (install/activate/deactivate)
├── src/
│   ├── consentStore.ts                # pinia store via sdk.createStore('cookieConsent', …) — state + persistence
│   ├── consentGuard.ts                # the router guard factory (gates auth + commerce routes)
│   ├── mountOverlay.ts                # self-mount/unmount the body overlay (activate/deactivate)
│   ├── components/
│   │   ├── CookieConsentPopup.vue     # the blocking overlay (Accept all / Reject all)
│   │   └── CookieSettingsButton.vue   # persistent re-open affordance after a decision
│   └── policy.ts                      # consent version + storage key
├── locales/{en,de,es,fr,ja,ru,th,zh}.json
├── config.json
├── admin-config.json
├── tests/unit/*.spec.ts
├── README.md
└── LICENSE
```

`index.ts`:
```ts
export const cookieConsentPlugin: IPlugin = {
  name: 'cookie-consent',
  version: '1.0.0',
  description: 'Cookie / GDPR (DSGVO) consent popup; gates login + checkout until accepted',
  _active: false,
  install(sdk) {
    createConsentStore(sdk);                 // sdk.createStore('cookieConsent', …)
    sdk.addRouterGuard(makeConsentGuard());  // blocks login/checkout when not accepted
    addAllLocales(sdk);                      // 8 locales
  },
  activate()  { this._active = true;  mountOverlay(); },     // attach Teleport-to-body overlay
  deactivate(){ this._active = false; unmountOverlay(); },   // remove it; remove the guard's effect
};
```

### 3.2 Consent state (`consentStore.ts`, persisted)

A pinia store created via `sdk.createStore('cookieConsent', …)`, hydrated from `localStorage` and written back on every decision:

```jsonc
// localStorage key: "vbwd_cookie_consent"
{
  "status":  "undecided" | "accepted" | "rejected",
  "version": 1,            // bump → re-prompt everyone after a policy change
  "decidedAt": "2026-06-13T12:00:00Z"
}
```
- `undecided` (no record, or stored `version` < current) → **show the blocking popup**.
- `accepted` → overlay hidden; guard allows everything; analytics/marketing scripts (if any future consumer asks) may run.
- `rejected` → overlay hidden; guard **blocks** auth + commerce (§3.4); only the **"Cookie settings"** button remains.
- Getters: `isDecided`, `isAccepted`, `isBlocked` (= decided && !accepted && `block_auth_and_commerce_on_reject`).

### 3.3 The overlay (self-mounted, design-system styled)

- **`CookieConsentPopup.vue`** — a blocking modal built on the fe-core **`Modal.vue`** / design-system primitives (`var(--vbwd-*)`, theme-aware, mobile-first). Content: title, the consent/privacy copy (i18n; with a configurable **privacy-policy link**), and two buttons: **Accept all** (`data-testid="cookie-accept-all"`) and **Reject all** (`data-testid="cookie-reject-all"`). Shown only when `status === undecided`. No close-X (a decision is required) — but **Reject all** is a valid dismissal.
- **`CookieSettingsButton.vue`** — a small persistent corner button (`data-testid="cookie-settings"`) shown **after** a decision, re-opening the popup so a `rejected` visitor can later **Accept** (and unlock login/buy).
- **`mountOverlay.ts`** — on `activate()`, create `<div id="vbwd-cookie-consent-root">`, append to `document.body`, mount a tiny Vue root rendering the popup + settings button, **reusing the app's i18n instance and the `cookieConsent` pinia store** (single source of truth, shared with the guard). `deactivate()` unmounts and removes the node. **No App.vue / core edit** — the whole lifecycle is owned by the plugin.

### 3.4 The gate (`consentGuard.ts` via `sdk.addRouterGuard`)

A global `beforeEach`-style guard:
```
if store.isBlocked and target matches a GATED route:
    redirect to the last public route (or '/'), and open the consent popup with the
    "accept cookies to log in or purchase" message.
else:
    allow.
```
- **Gated set (configurable, admin-config):** route **names** `['login', 'checkout-public', 'checkout-cart', 'checkout-confirmation']` **+** path-prefixes `['/checkout', '/dashboard/checkout']`. Defaults cover the verified auth + checkout routes; the prefix match also catches shop/other commerce plugins without naming them (decoupled).
- Because every "buy" path is a route under `/checkout*`, navigation is the natural choke point — a plan/product "Buy" button that routes to checkout is blocked the same way; no per-button coupling needed.
- When `block_auth_and_commerce_on_reject` is **false**, `isBlocked` is always false → the guard is a no-op (Liskov null behaviour): popup still informs, but nothing is gated.

### 3.5 Config (plugin baseline — BINDING)

`config.json` + `admin-config.json` (settings tab) per [[feedback_plugin_baseline_config_files]]:
- `debug_mode` (baseline).
- `privacy_policy_url` (text) — linked from the popup body.
- `block_auth_and_commerce_on_reject` (bool, **default true**) — the "reject ⇒ no login/buy" switch.
- `gated_route_names` (text/CSV) + `gated_path_prefixes` (text/CSV) — the gate set, defaulted as §3.4 (admin-config selects are static-only per [[reference_admin_config_select_static_only]], so these are text fields, not live route pickers).
- `consent_version` (number) — bump to re-prompt after a policy change.

### 3.6 i18n

`locales/{en,de,es,fr,ja,ru,th,zh}.json` (the fe-user locale set), wired via `sdk.addTranslations`: title, body copy, **Accept all**, **Reject all**, the "accept to log in or buy" gate message, the "Cookie settings" label, and the privacy-policy link text.

### 3.7 Registration

- The repo is dropped into `vbwd-fe-user/plugins/cookie-consent/` (install recipe / submodule), enabled in `plugins/plugins.json` (`"cookie-consent": { "enabled": true, … }`).
- **Disabled / not installed → the storefront behaves exactly as today** (no overlay, no guard): the plugin's `activate()` never runs, so there is literally no footprint (Liskov null default).

## 4. TDD plan (RED first) — Vitest, mount with i18n + pinia

- **`consentStore`**: hydrates `undecided` when storage empty or `version` stale; `acceptAll()` → `accepted` + persisted; `rejectAll()` → `rejected` + persisted; `isBlocked` true only when `rejected` **and** `block_auth_and_commerce_on_reject`.
- **`consentGuard`**: with `isBlocked`, navigation to a gated **name** or **path-prefix** (`/login`, `/checkout`, `/dashboard/checkout/x`) is redirected + opens the popup; a public CMS path is allowed; with `accepted` everything is allowed; with the toggle off the guard is a no-op.
- **`CookieConsentPopup`**: renders only when `undecided`; **Accept all** calls `acceptAll` + hides; **Reject all** calls `rejectAll` + hides; buttons by `data-testid`; uses fe-core design-system classes (no bespoke colours); privacy link from config.
- **`CookieSettingsButton`**: hidden when `undecided`, shown after a decision; click re-opens the popup.
- **`mountOverlay`**: `activate()` appends `#vbwd-cookie-consent-root` to body and mounts; `deactivate()` removes it; idempotent (double-activate doesn't duplicate).
- **lifecycle**: `install` registers store + guard + locales; **plugin disabled → no overlay, no guard effect** (editor/storefront unchanged).

## 5. Files (indicative — all in the new repo)

| Action | Path |
|---|---|
| new | `index.ts` — named export `cookieConsentPlugin` |
| new | `src/consentStore.ts` · `src/consentGuard.ts` · `src/mountOverlay.ts` · `src/policy.ts` |
| new | `src/components/CookieConsentPopup.vue` · `src/components/CookieSettingsButton.vue` |
| new | `locales/{en,de,es,fr,ja,ru,th,zh}.json` |
| new | `config.json` · `admin-config.json` (`debug_mode`, `privacy_policy_url`, `block_auth_and_commerce_on_reject`, `gated_route_names`, `gated_path_prefixes`, `consent_version`) |
| new | `tests/unit/*.spec.ts` · `README.md` · `LICENSE` |
| edit | (install-time only) `vbwd-fe-user/plugins/plugins.json` — register & enable |

## 6. Acceptance (P1)

- **First visit** shows a blocking, theme-styled popup with exactly **Accept all** and **Reject all** (and a privacy-policy link).
- **Accept all** → popup closes, decision remembered; the visitor can **navigate to `/login`** and **proceed to checkout**.
- **Reject all** → popup closes; navigating to `/login` **or** any `/checkout*` route is **blocked** (redirected, with an "accept cookies to log in or purchase" message); public CMS pages stay browsable. The **"Cookie settings"** button is present.
- **Re-open → Accept** unblocks login + checkout immediately.
- The decision **survives reload** (localStorage); bumping `consent_version` re-prompts.
- The popup + settings button **reuse the `vbwd-fe-core` design system** (shared classes + `var(--vbwd-*)`), match the storefront theme, and are mobile-responsive — **no bespoke/one-off CSS**.
- With the plugin **disabled/uninstalled**, the storefront behaves exactly as today (no overlay, no gate).
- **No `vbwd/` core, backend, fe-admin, or other-plugin file is modified.**
- **fe-user quality gate GREEN** — Vitest + ESLint + `vue-tsc`.

## 7. Definition of Done

- All §6 acceptance met; **fe-user gate GREEN** (Vitest + ESLint + `vue-tsc`).
- **Live proof — Playwright HTML walkthrough with real screenshots** at `docs/dev_log/20260613/walkthrough/s87-WALK-REPORT-cookie-consent.html` (mirroring the s84/s81/s77 walkthroughs), on the running storefront (port 8080): (1) first-visit popup; (2) **Reject all** → attempt `/login` blocked + message, attempt checkout blocked; (3) **Cookie settings → Accept all** → `/login` reachable + checkout proceeds; (4) reload showing the decision persisted; each step captioned with the action + observed result (real screenshots, not mockups).
- **README** in the new repo: what it does, the two-button consent model, the reject-gates-auth/commerce stance + the relax toggle, the config keys, and the self-mount note (no core change).
- Repo created and pushed to its own `main` ([[feedback_no_temp_branches]]); **not committed into any core/host repo** ([[feedback_plugins_always_in_own_repos]], [[feedback_no_commit_without_ask]] — get the owner's go-ahead before creating/pushing the repo, as that is an outward action).

## 8. Out of scope (this sprint)

- **Granular per-category consent** (necessary / preferences / analytics / marketing toggles + a "Save preferences") — P1 is Accept-all / Reject-all only.
- **Server-side consent record / audit log** (a backend endpoint storing proof-of-consent for compliance) — P1 is client-side localStorage only; the store is the seam to add this later.
- **Conditional script-loading** (actually gating analytics/marketing `<script>` tags on consent) — the store exposes `isAccepted` for a future consumer; no script orchestration built now.
- fe-admin surface, backend, other plugins.

## 9. Engineering-requirements check

- **Core agnostic / one repo:** a single new standalone fe-user plugin repo; **zero** edits to `vbwd/` core, backend, fe-admin, or any other plugin; disabled → no footprint. [[feedback_plugins_always_in_own_repos]]
- **SOLID/Liskov:** store / guard / overlay are separate single-responsibility units; guard is a no-op when the toggle is off (null behaviour); plugin disabled = exact prior behaviour.
- **DI/DRY:** consent state is one pinia store shared by overlay + guard (single source of truth); the gate set is config-driven, not duplicated per commerce plugin; UI reuses fe-core primitives.
- **NO OVERENGINEERING:** two buttons (no category matrix); client-side only (no backend); self-mount (no SDK/core extension); guard reuses the existing `addRouterGuard` seam.
- **Reuse default core styles:** popup + button style only through the `vbwd-fe-core` design system (`var(--vbwd-*)`), theme-aware, mobile-ready; any missing primitive is added **to fe-core**, not forked. [[project_fe_core_design_system]]
- **Plugin baseline:** `config.json` + `admin-config.json` (incl. `debug_mode`) ship; admin-config selects stay static. [[feedback_plugin_baseline_config_files]] [[reference_admin_config_select_static_only]]
- **TDD-first / gate:** store/guard/overlay/component specs land RED first; fe-user gate green = done. Implementation delegated to the **`vbwd-tdd`** agent where backend-adjacent; fe-user work mirrors existing plugin test idioms. [[feedback_use_tdd_agent_for_implementation]]
- **Git discipline:** plugin lives in `vbwd-fe-user-plugin-cookie-consent`, work committed to its own `main`, no temp branches, never into a core repo. [[feedback_no_temp_branches]] [[feedback_work_in_sdk_dirs]]

> **Compliance note (non-blocking):** under GDPR/ePrivacy, *strictly-necessary* cookies (session/auth/cart) are exempt from prior consent. Gating login/checkout on **Accept all** is a stricter, product-chosen posture (no non-essential flows without consent). The `block_auth_and_commerce_on_reject` toggle exists so legal can dial this to the strictly-necessary model later without code change.
