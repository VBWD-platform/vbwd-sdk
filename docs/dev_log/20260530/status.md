# 2026-05-30 — Daily status

> Wrap-up: [`reports/01-daily-wrapup-2026-05-30.md`](reports/01-daily-wrapup-2026-05-30.md).
> Carried forward from [`../20260528/status.md`](../20260528/status.md) (S26/S27/S28/S29/S38 resolved there).

## Theme

S28 meinchat-plus E2E **hardening completed** (skipped-key cache, thumbnails,
signed-prekey rotation, crypto audit, e2e smoke — 156 specs, tsc-clean), then a
**live-debug session** on the running localhost stack fixed a prod-class
migration 500 (`conversation.protocol`), image rendering (`.webp` → `image/webp`),
and large-image upload limits (nginx + meinchat config). Planned sprints carried
into this folder.

## Done today

| Item | Area | Status |
|------|------|--------|
| S28 meinchat-plus hardening (skipped-key cache, thumbnails, SPK rotation, crypto audit, e2e smoke, type cleanup) | `vbwd-fe-user/plugins/meinchat{,-plus}` | **DONE & GREEN** — 156 specs, eslint + tsc clean ([report 20](../20260528/reports/20-meinchat-plus-hardening-audit-e2e.md)) |
| Live 500 `conversation.protocol` — DB never migrated | `vbwd-backend` (alembic) | **FIXED** — `alembic upgrade heads` (+widened `alembic_version` to 255) ([report 21](../20260528/reports/21-localhost-meinchat-demo-and-protocol-500-fix.md)) |
| Images served as `octet-stream` → wouldn't render | `plugins/cms` `serve_upload` | **FIXED** — register `.webp`/`.avif`/`.svg` + explicit mimetype → `image/webp` |
| Allow large image files | `nginx.{dev,prod}` + `plugins/meinchat` config | **DONE** — nginx `client_max_body_size 40m`; `attachment_max_bytes` 25 MB, dim 4096 |
| Bob ↔ Alice browser demo (conversation / token / image) | `plugins/meinchat` e2e | **3/3 PASSED** on localhost:8080 + screenshots |

Regression gate: `plugins/meinchat` + `plugins/cms` tests **192 passed**.
**Not committed** (standing rule).

## Done 2026-05-31 → 06-01 (continued)

| Item | Area | Status |
|------|------|--------|
| **S43** DB table-naming normalization (18 tables, data-preserving migrations) | `vbwd-backend` + 8 plugins | ✅ **DONE & GREEN** ([report 03](reports/03-s43-db-table-naming-complete.md)); all 8 plugin CIs green incl. booking |
| Booking **e2e** red root-caused + fixed — CI ran `alembic upgrade head` (singular) on the multi-head graph, masked by `\|\| true` → empty DB → no admin → login timeout | `vbwd-plugin-booking` CI | ✅ **FIXED** — `create_all` + loud seed; **18/18 e2e green** ([report 04](reports/04-booking-e2e-investigation.md)) |
| Core `pre-commit-check.sh --full` **fully GREEN** — RBAC test-fixture `user_roles`/access-level cleanup (14 errors), `test_infrastructure` made plugin-agnostic, foundational seeding (`seed-rbac/countries/payment-methods/test-data`) wired into the integration gate + **new `seed_payment_methods` service+CLI** | `vbwd-backend` | ✅ **GREEN** — A: lint, B: 2424 unit, C: 337 integration ([report 05](reports/05-core-gate-fixes-and-countries-export-import.md)) |
| **Countries manual export/import** (VBWD-standard JSON, 2 buttons on Settings→Countries) | `vbwd-backend` + `vbwd-fe-admin` | ✅ **SHIPPED** — be 9 unit + 5 integration, fe 4 unit, e2e round-trip verified ([report 05](reports/05-core-gate-fixes-and-countries-export-import.md)) |
| Local fe-user test-user degraded (no token widgets, store routes bounce) — **access levels had 0 permission grants**; `subscription.tokens.view` ungranted | local DB (seeding gap) | ✅ **FIXED** — granted subscription user-perms to basic/pro via admin service; dashboard now matches prod (screenshot). `seed_user_access_levels` still grants none → **durable fix = bake into demo_seed (offered, pending)** |
| **Super admin can delete system access levels** (the `admin` role + system user-levels) | `vbwd-backend` + `vbwd-fe-admin` | ✅ **SHIPPED** — be 4 unit + live-verified, fe 3 unit, screenshot as `admin@vbwd.local` ([assets](reports/assets/superadmin-delete/)) |
| **S36** discounts-at-checkout — diagnosis re-verified against live tree | backend + fe-core/user/admin | ✅ **RE-VERIFIED READY** — unblocked once the 3 §9 decisions are made (see sprint doc §0) |

**Not committed** (standing rule). Plugin-repo fixes (booking/meinchat/subscription
S43 CI) were pushed; core + fe-admin changes left uncommitted on disk.

## Planned sprints (carried into `sprints/`)

| # | Sprint | Area | Status |
|---|--------|------|--------|
| 28.6 | [iOS meinchat app update](sprints/s28-6-ios-meinchat-app-update-plan.md) | `vbwd-ios` | Planned (iOS app, separate) |
| 28.7 | [iOS meinchat-plus plugin](sprints/s28-7-ios-meinchat-plus-plugin-plan.md) | `vbwd-ios` | Planned (iOS app, separate) |
| 30 | [Heavy-load harness fixes](sprints/s30-heavy-load-harness-fixes.md) + [load-test code affordances](sprints/s30-load-test-code-affordances.md) | platform + `vbwd-backend` | Planned |
| 31 | [Flask-Limiter per-user keying](sprints/s31-flask-limiter-per-user-keying.md) | `vbwd-backend` | Planned — **blocked on keyfunc JWT-signature verification** |
| 32 | [macOS rate-limit overrides](sprints/s32-macos-rate-limit-overrides.md) | `plugins/meinchat` | Planned (non-blocker until Mac Catalyst ships) |
| 33 | [429 telemetry](sprints/s33-429-telemetry.md) | `vbwd-backend` + `plugins/meinchat` | Planned (recommended pre-v1) |
| 34 | [Drop legacy meinchat rate keys](sprints/s34-drop-legacy-meinchat-rate-keys.md) | `plugins/meinchat` | **DEFERRED** — gated on S26 in prod everywhere |
| 35 | [iOS cache conv_id, drop 429-retry](sprints/s35-ios-cache-conv-id-drop-retry.md) | `vbwd-ios` | Planned (iOS release-train) |
| 36 | [Discounts & coupons at checkout](done/s36-discounts-at-checkout.md) | backend + fe-core + fe-user + fe-admin | ✅ **DONE & GREEN — 2026-06-02** ([report 07](reports/07-s36-discounts-at-checkout-complete.md)). Coupon island wired into both checkouts via a generic core seam; backend 24 tests, fe-core 6, fe-user 18 unit + **7 Playwright e2e** (public/private/admin-injected), fe-admin 2 e2e; lint + agnosticism oracles green. Moved to `done/`. |
| 37 | [fe-user "Pay Zero" checkout](done/s37-fe-user-pay-zero-checkout.md) | fe-core + fe-user + backend (booking) | ✅ **DONE & GREEN — 2026-06-02** ([report 09](reports/09-pay-zero-ghrm-and-booking.md)). €0 checkout completes with no payment step (invoice PAID + entitlement created) for free GHRM packages **and** free bookings; live-verified on `localhost:8080`. Booking gained a backend zero-total auto-pay via the shared `emit_payment_captured` seam (subscription already auto-paid). Backend booking integration guard + fe-user unit 673 passed; ESLint clean. Moved to `done/`. |
| 40 | [CMS SEO plugin](sprints/s40-cms-seo.md) | `plugins/cms` | **DRAFT for negotiation** |
| 41 | [CMS AI helper](sprints/s41-cms-ai-helper.md) | `plugins/cms` | **DRAFT for negotiation** |
| 42 | [vbwd-press](sprints/s42-vbwd-press.md) (parent) + [42.0](sprints/s42-0-data-model-terms-crud.md)/[42.1](sprints/s42-1-post-list-and-term-widget.md)/[42.2](sprints/s42-2-fts-search-and-widget.md)/[42.3](sprints/s42-3-content-type-renderer-registry.md)/[42.4](sprints/s42-4-rss-feeds.md) | `plugins/*press*` | **DRAFT for negotiation** |
| 43 | [DB table-naming normalization](sprints/s43-db-table-naming-normalization.md) (plugin-prefix every table) | `vbwd-backend` + plugins meinchat/taro/discount/booking/subscription/toss + ghrm | ✅ **DONE & GREEN — 2026-05-31** (18 tables, data-preserving migrations; [report 03](reports/03-s43-db-table-naming-complete.md)). 7/8 plugin CIs green; booking **backend** green, its **e2e** red = pre-existing auth-harness rot, not S43. |
| 44 | [`snippets` — third-party script injection](sprints/s44-snippets-third-party-scripts.md) (be + fe-user duo: admin pastes GA/Pixel/Matomo/ads JS into a widget → injected on the site) | new `vbwd-plugin-snippets` + `vbwd-fe-user-plugin-snippets` | **PLANNED — 2026-05-30** (TDD-first; security: trusted admin-only code injection + CSP/consent hooks) |
| 45 | [`telegram_connect` — Telegram bot bridge](sprints/s45-telegram-connect.md) (backend: exported outbound `TelegramService` + inbound command dispatch; `chat`/`taro` plug in — `/hello-llm` → token-billed LLM chat in Telegram) | new `vbwd-plugin-telegram-connect` + fe-admin trio | **PLANNED — D1–D5 LOCKED 2026-06-02**, ready to implement (dependency-inversion seam · webhook+dev-poll · deep-link+anonymous · encrypted token · fe-admin trio @ 45.5) |
| 46 | [Unified Data Exchange](sprints/s46-unified-data-exchange.md) — core import/export for every entity: registry + `EntityExchanger` port + VBWD-standard envelope/ZIP + generic Settings→Import/Export page + per-list buttons; two-layer perms (`<entity>.export`/`.import`, superadmin bypass); migrate countries+CMS off one-offs; plugins register exchangers | **core** `vbwd-backend` + `vbwd-fe-core` + `vbwd-fe-admin` + plugins cms/subscription/booking/ghrm/shop/discount | **DRAFT for negotiation — 2026-06-02** (generalizes the CMS `CmsImportExport.vue` + countries `country_io` patterns; core stays agnostic via the registry seam) |

Engineering requirements (binding): [`sprints/_engineering_requirements.md`](sprints/_engineering_requirements.md).

**Not carried (left in `../20260528/`):** S28 epic strategy docs
(master + phase1 + phase2 — the now-delivered web epic record); **S39**
(core RBAC seeding — *implemented backend* 2026-05-29).

## Blockers / notes

- **S31** must not be implemented as drafted — the keyfunc skips JWT signature
  verification (DoS-via-forged-JWT). Verify HS256 in the keyfunc first.
- **S34** deferred by design.
- **S36** ✅ **DONE & GREEN 2026-06-02** (discounts/coupons wired into both
  checkouts; 7 e2e green; report 07).
- **S37** ✅ **DONE & GREEN 2026-06-02** (Pay Zero: €0 checkout completes with no
  payment step for free GHRM packages + free bookings; report 09). Moved to `done/`.
- **S40 / S41 / S42** carry open product questions / are pre-negotiation drafts.
- **fe-user e2e rot (pre-existing, NOT S36):** the `navigateToCheckout` helper
  targets `/checkout/:slug` but the real route is `/dashboard/checkout/:slug` —
  this stale helper is why many legacy checkout e2e fail. S36's new specs use the
  correct routes. Fixing the legacy suite is a separate cleanup.
- **S43 follow-up:** the local test-user permission grant is live but not durable
  — `seed_user_access_levels` (subscription demo_seed) still grants no perms, so a
  DB reset loses it. Bake the grant into demo_seed (offered) to make it survive.
- Small follow-ups from today: shorten the two >32-char meinchat migration ids;
  reconcile `image_max_size_bytes` (admin) vs `attachment_max_bytes` (service).
