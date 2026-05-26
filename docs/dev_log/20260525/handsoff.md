# Handoff — start here, finish the planned sprints

**Date:** 2026-05-25. Read this first, then implement the **planned** sprints in
order. Everything you need (locations, how to run/enable, gotchas) is below.

## TL;DR

- **Done & verified today:** `s9` (CMS link prefetch + SPA nav), `s10` (pay an
  invoice with token balance — backend plugin + fe-user UI). Both unit-tested and
  e2e-verified on the live stack ([report 06](reports/06-s9-s10-e2e-verification.md)).
- **Planned, NOT implemented — DO THESE:**
  1. **`s11`** → [`sprints/s11-token-payment-followups.md`](sprints/s11-token-payment-followups.md) — 3 polish items.
  2. **`s12`** → [`sprints/s12-token-balance-at-checkout.md`](sprints/s12-token-balance-at-checkout.md) — token balance as an instant checkout method.
- Do **s11 → s12** (s12 inherits s11's `new_balance` fix). TDD-first. Verify with
  unit + live e2e. **Do not commit/push or enable in prod without asking the user.**
- Other sprints here (`s1,s4–s7,s9,s10`) are done; older `docs/dev_log/*` folders
  are separate tracks — out of scope.

## Binding requirements (every sprint)
TDD-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **no
overengineering** — [`sprints/_engineering-requirements.md`](sprints/_engineering-requirements.md).
Gate: backend `bin/pre-commit-check.sh --full`; fe-user `npm run lint && npm run test`.

## What exists already (from s10 — reuse it, don't rebuild)

| Thing | Path |
| --- | --- |
| Backend plugin (own git repo, commit `d9bc7d3`) | `vbwd-backend/plugins/token_payment/` |
| — conversion logic (rate, `compute_tokens_needed`, debit/refund) | `token_payment/token_payment/service.py` `TokenPaymentService` |
| — routes (`/quote`, `/pay`) | `token_payment/token_payment/routes.py` |
| — plugin class | `token_payment/__init__.py` |
| — docs (how it works / how to develop) | `token_payment/docs/{human,llm}/` |
| Core token wallet (DO NOT fork) | `vbwd/services/token_service.py` (`get_balance`/`debit_tokens`/`credit_tokens`) |
| Capture seam (invoice→PAID + line items) | `vbwd/plugins/payment_route_helpers.py::emit_payment_captured` → `vbwd/handlers/payment_handler.py` → `vbwd/events/line_item_registry.py` |
| fe-user agnostic seam (invoice detail) | `vbwd-fe-user/vue/src/extensions/invoicePaymentMethods.ts` |
| fe-user plugin (own git repo, commit `63b315d`) | `vbwd-fe-user/plugins/token-payment/` (`src/TokenPaymentPanel.vue`) |
| s9 (prefetch/SPA) | `vbwd-fe-user/plugins/cms/src/{utils/cmsLinkResolver.ts,composables/useCmsSpaLinks.ts,composables/useCmsLinkPrefetch.ts}` + store cache in `stores/useCmsStore.ts` |

## The two sprints (key seams already located)

**s11 — follow-ups**
1. **Core:** `vbwd/handlers/payment_handler.py:43-47` sets status/`payment_ref`/`paid_at`
   but never `payment_method`; set `invoice.payment_method = event.provider` (prefer
   `invoice.mark_paid`). Generic; add regression tests for stripe/paypal.
2. **Plugin:** `token_payment/routes.py` `pay` returns the post-debit balance; re-read
   `TokenService.get_balance` **after** `emit_payment_captured` and return that.
3. **fe-user CSS:** `plugins/token-payment/src/TokenPaymentPanel.vue` — add `gap`/`min-width`
   so rows aren't flush.

**s12 — token balance at checkout** (extends s10)
- Backend: amount-quote `GET /plugins/token-payment/quote?amount=&currency=` (thin over
  `TokenPaymentService`); on `on_enable` upsert a `vbwd_payment_method` `code=token_balance`
  (so `GET /api/v1/payment-methods` lists it and `PaymentMethodsBlock.vue` shows it).
- fe-user: new `vue/src/registries/checkoutPaymentMethods.ts` (mirror s10's
  `invoicePaymentMethods` + the existing `checkout*Registry`); `PaymentMethodsBlock.vue`
  renders the selected method's detail; `PublicCheckoutView.vue` (`:222-232`) calls a
  registered `instantPay(invoiceId)` after invoice creation → confirmation (instant, no gateway).
- plugin: `TokenCheckoutQuote.vue` (balance-now / tokens-to-pay / balance-after, re-quotes
  on cart total) + register `instantPay` reusing `/pay`.

## Local stack — run, enable, test (CRITICAL)

**Bring up / health**
- Backend: `cd vbwd-backend && docker compose up -d api` (postgres+redis usually already up).
  API is proxied at `http://localhost:8081/api/v1`. Health: `curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/api/v1/cms/pages` → 200.
- fe-user: `http://localhost:8080` (Vite dev container). **HMR over the macOS Docker bind
  mount is unreliable** — after adding/enabling a plugin run `cd vbwd-fe-user && docker
  compose restart dev` and wait: `curl -s --fail --retry 40 --retry-delay 2 --retry-all-errors http://localhost:8080/`.

**Credentials**
- Admin: `admin@example.com` / `AdminPass123@` · User: `test@example.com` / `TestPass123@`.

**Enabling plugins (runtime source of truth = the var manifests, NOT repo `plugins.json`)**
- Already enabled this session: `token_payment` in `vbwd-backend/var/plugins/backend-plugins.json`
  (+ rates `{"USD":0.05,"EUR":0.045}` in `backend-plugins-config.json`); `token-payment` in
  `var/plugins/fe-user-plugins.json`.
- A **new** backend plugin must be **discovered** first → it needs a backend restart, then
  `POST /api/v1/admin/plugins/<name>/enable` (admin token) to flip it `active`.
- Rate used: `USD = 0.05` → `tokens = ceil(total / 0.05)`.

**Test data:** user `test@example.com` has a token balance + several **PENDING** invoices
(`GET /api/v1/user/invoices`). Seed more **only via services/API**, never raw SQL.

**Run tests**
- Backend unit: `docker compose run --rm test python -m pytest plugins/token_payment/tests/unit/ -v`
- Backend lint: `docker compose run --rm test flake8 plugins/token_payment --max-line-length=120 --extend-ignore=E203,W503`
- fe-user unit: `npx vitest run <spec paths>` · lint: `npx eslint <files>` · types: `npx vue-tsc --noEmit` (filter to your files — pre-existing payment-plugin errors exist).

**e2e (do it after each sprint, like report 06)**
- Backend: as the user, `GET …/quote` then `POST …/pay` on a small PENDING invoice; assert
  invoice PAID + balance delta. (Pick a NON-token-bundle invoice for a clean −delta; bundle
  invoices credit back.)
- fe-user: Playwright — login as user, drive the invoice panel (s10) / checkout (s12), pay,
  verify. (fe-user has Playwright; write a temp `.mjs`, run with `node`, delete it.)

## Gotchas (save yourself the time I spent)
- **flake8 is `--max-line-length=120`** (not 79). **black excludes `plugins/`** — don't fight it for plugin files.
- **vue-tsc** flags arrow bodies returning `vi.*()` (VitestUtils) — use block bodies in `beforeEach/afterEach`.
- **No `eslint-disable` / `# noqa` / `type: ignore`** without asking the user — fix the root cause.
- The backend `api` container reads plugin enabled state from `var/plugins/backend-plugins.json`, not the repo file.
- After a token payment, `invoice.payment_method` stays the original — that's **s11 item 1**.
- Pure unit tests (mock `TokenService`, no app) run even when the backend mapper is mid-refactor.

## Definition of done (per sprint)
1. Unit tests green (TDD), lint + types clean on each touched repo.
2. Live e2e passes; update the sprint file **Status → IMPLEMENTED**; write a short report in `reports/`.
3. **Ask the user** before committing/pushing the plugin repos (local-only now: `vbwd-plugin-token-payment` `d9bc7d3`, `vbwd-fe-user-plugin-token-payment` `63b315d`; no remotes set) or enabling anything in prod. Don't tag until deployed + smoke-tested.
