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
| 30 | [load-test code affordances](done/s30-load-test-code-affordances.md) (`flask seed`, `/_routes`, `/_seed_status`) | `vbwd-backend` | ✅ **DONE & GREEN — 2026-06-02** ([report 11](reports/11-s30-load-test-affordances-complete.md)). 3 debug-gated affordances; 26 specs + agnosticism oracle green, `--quick` 2468 passed; core seed-marker migration. Moved to `done/`. Unblocks the harness sprint's nicer path. |
| 29 | [Heavy-load harness fixes](done/s30-heavy-load-harness-fixes.md) (workflow + Locust scenario + thresholds) | `vbwd-platform` | ✅ **DONE & VALIDATED — 2026-06-02** ([report 13](reports/13-heavy-load-validated-engine-speed.md)). §5 gate met: run `26848354627` (50 VU·2m·all) runs end-to-end and fails **only on a real signal** (`/tarif-plans/<slug>` 100%), not harness drift. Engine fast — p95 **88 ms**, p99 330 ms, ~37 req/s, checkout write p50 27 ms / 0 fails. Caught 2 real bugs en route (S30 seed-argv `4f2c8d4`, smoke slash-match `0a1a880`), each fixed + regression-tested. Moved to `done/`. |
| 31 | [Flask-Limiter per-user keying](sprints/s31-flask-limiter-per-user-keying.md) | `vbwd-backend` | Planned — **blocked on keyfunc JWT-signature verification** |
| 32 | [macOS rate-limit overrides](sprints/s32-macos-rate-limit-overrides.md) | `plugins/meinchat` | Planned (non-blocker until Mac Catalyst ships) |
| 33 | [429 telemetry](done/s33-429-telemetry.md) | `vbwd-backend` + `plugins/meinchat` | ✅ **DONE & GREEN — 2026-06-02** ([report 10](reports/10-s33-429-telemetry-complete.md)). Both limiters emit one WARN structured line per 429 (global: `route/key/descriptor`; meinchat: `category/user_id/retry_after`). Core `--quick` 2443 passed, meinchat `--quick` 261 passed. Global key uses `get_remote_address` today (picks up per-user key free once S31 lands). Moved to `done/`. |
| 34 | [Drop legacy meinchat rate keys](sprints/s34-drop-legacy-meinchat-rate-keys.md) | `plugins/meinchat` | **DEFERRED** — gated on S26 in prod everywhere |
| 35 | [iOS cache conv_id, drop 429-retry](sprints/s35-ios-cache-conv-id-drop-retry.md) | `vbwd-ios` | Planned (iOS release-train) |
| 36 | [Discounts & coupons at checkout](done/s36-discounts-at-checkout.md) | backend + fe-core + fe-user + fe-admin | ✅ **DONE & GREEN — 2026-06-02** ([report 07](reports/07-s36-discounts-at-checkout-complete.md)). Coupon island wired into both checkouts via a generic core seam; backend 24 tests, fe-core 6, fe-user 18 unit + **7 Playwright e2e** (public/private/admin-injected), fe-admin 2 e2e; lint + agnosticism oracles green. Moved to `done/`. |
| 37 | [fe-user "Pay Zero" checkout](done/s37-fe-user-pay-zero-checkout.md) | fe-core + fe-user + backend (booking) | ✅ **DONE & GREEN — 2026-06-02** ([report 09](reports/09-pay-zero-ghrm-and-booking.md)). €0 checkout completes with no payment step (invoice PAID + entitlement created) for free GHRM packages **and** free bookings; live-verified on `localhost:8080`. Booking gained a backend zero-total auto-pay via the shared `emit_payment_captured` seam (subscription already auto-paid). Backend booking integration guard + fe-user unit 673 passed; ESLint clean. Moved to `done/`. |
| 40 | [CMS SEO plugin](cancelled/s40-cms-seo.md) | `plugins/cms` | ⛔ **SUPERSEDED by [S47](sprints/s47-unified-content-seo.md)** — moved to `cancelled/` |
| 41 | [CMS AI helper](sprints/s41-cms-ai-helper.md) | `plugins/cms` | **DRAFT for negotiation** |
| 42 | [vbwd-press](cancelled/s42-vbwd-press.md) (parent) + [42.0](cancelled/s42-0-data-model-terms-crud.md)/[42.1](cancelled/s42-1-post-list-and-term-widget.md)/[42.2](cancelled/s42-2-fts-search-and-widget.md)/[42.3](cancelled/s42-3-content-type-renderer-registry.md)/[42.4](cancelled/s42-4-rss-feeds.md) | `plugins/*press*` | ⛔ **SUPERSEDED by [S47](sprints/s47-unified-content-seo.md)** — moved to `cancelled/` |
| 43 | [DB table-naming normalization](sprints/s43-db-table-naming-normalization.md) (plugin-prefix every table) | `vbwd-backend` + plugins meinchat/taro/discount/booking/subscription/toss + ghrm | ✅ **DONE & GREEN — 2026-05-31** (18 tables, data-preserving migrations; [report 03](reports/03-s43-db-table-naming-complete.md)). 7/8 plugin CIs green; booking **backend** green, its **e2e** red = pre-existing auth-harness rot, not S43. |
| 44 | [`snippets` — third-party script injection](cancelled/s44-snippets-third-party-scripts.md) (admin pastes GA/Pixel/Matomo/ads JS → injected on the site) | `plugins/cms` + fe duo | ⛔ **SUPERSEDED by [S47.7](sprints/s47-7-snippets-and-head-injection.md)** — folded into the unified module (baked into prerender + CSP-nonce); moved to `cancelled/` |
| 45 | [`bot-base` + provider adapters — provider-neutral bot bridge](sprints/s45-bot-base-bridge.md) (umbrella; `bot-base` core + `bot-telegram`/`bot-meinchat`/`bot-zapier` adapters; `chat`/`taro` plug in — `/hello-llm` → token-billed LLM chat over any provider). Sub-sprints: [45.0 bot-base](sprints/s45-0-bot-base-foundation.md) · [45.1 telegram](sprints/s45-1-bot-telegram-adapter.md) · [45.2 chat](sprints/s45-2-chat-bot-consumer.md) · [45.3 taro](sprints/s45-3-taro-bot-consumer.md) · [45.4 fe-admin](sprints/s45-4-fe-admin-bot-telegram.md) · [45.5 meinchat](sprints/s45-5-bot-meinchat-adapter.md) · [45.6 zapier](sprints/s45-6-bot-zapier-adapter.md) | new `vbwd-plugin-bot-*` family + fe-admin | **PLANNED — D1–D10 decided (D6/D7/D9/D10 LOCKED 2026-06-06)**, ready to implement (provider abstraction `IMessengerProvider` · dependency-inversion seam · webhook+dev-poll · deep-link+anonymous · encrypted secrets · storefront → [S53](sprints/s53-bot-commerce-storefront.md)/D8) |
| 46 | [Unified Data Exchange](sprints/s46-unified-data-exchange.md) — core import/export for every entity: registry + `EntityExchanger` port + VBWD-standard JSON/CSV/ZIP envelope + generic Settings→Import/Export page + per-list controls (selected/all/filter/import) + CLI + recipe content-packs; per-entity perms (`<entity>.export`/`.import`/`.export.pii`, superadmin bypass); natural-key matching, upsert/dry-run/replace-all; migrate countries+CMS off one-offs; plugins register exchangers (ghrm=packages only) | **core** `vbwd-backend` + `vbwd-fe-core` + `vbwd-fe-admin` + plugins cms/subscription/booking/ghrm/shop/discount | **SPEC RE-LOCKED 2026-06-06** — **depends on S50.1–S50.3** (post-S50 invoice/user seams; S50.4 may run in parallel). Revisions: JSON+CSV+ZIP kept; upsert/dry-run/replace_all kept; **plugin-config exchange DROPPED** (secret-leak risk → no Plugins tab); **CMS keeps its own page** on shared fe-core components (hard-cut reversed); +currencies; settings-cluster uses `settings.view`/`settings.manage`. Ready once S50.1–S50.3 land. |
| 47 | [Unified Content + SEO](sprints/s47-unified-content-seo.md) (master, **supersedes S40 + S42**) + [47.0 data-model+registries+migration](sprints/s47-0-unified-data-model-and-registries.md) / [47.1 SEO pipeline+prerender](sprints/s47-1-seo-pipeline-and-prerender.md) / [47.2 serving cache-bypass](sprints/s47-2-serving-cache-bypass-and-handoff.md) / [47.3 public render+content-types](sprints/s47-3-public-rendering-and-content-types.md) / [47.4 FTS search](sprints/s47-4-fts-search.md) / [47.5 RSS](sprints/s47-5-rss-feeds.md) / [47.6 admin authoring](sprints/s47-6-admin-authoring.md) / [47.7 Custom Code widget](sprints/s47-7-snippets-and-head-injection.md) | **core** `vbwd-backend` (sitemap/robots seam) + `plugins/cms` + `vbwd-fe-user-plugin-cms` + `vbwd-fe-admin-plugin-cms` + nginx | ✅ **IMPLEMENTED & RUNNING — 2026-06-03** ([report 14](reports/14-s47-unified-content-seo-implemented.md)). 9 increments (47.0a–47.7) + 3 live-review rework rounds; gates re-verified by hand (cms **349u/86i** · core gate green · fe-user **102** · fe-admin **512**). Unified `cms_post`(page/post/custom)+`cms_term`(category/tag/custom) via registries; page-only hierarchy; status lifecycle; **one SEO pipeline** (meta-builder + Python prerender + core sitemap/robots seam); **cache-bypass** serving (no SSR tier); **posts = pages** (shared layout/style + 1:1 `CmsContentList`); snippets = **Custom Code widget**; **public `/:slug` cutover LIVE** — 34 pages backfilled, `/sitemap.xml` 28 locs, `/test23` renders (headless-verified). Supersedes S40/S42/S44 (in `cancelled/`). **Not committed.** Next: prerender regen for backfilled posts + full e2e parity + retire `cms_page`. |
| 48 | [Load capacity & resilience](sprints/s48-load-capacity-and-resilience.md) (parent) + [48.0 fair harness](sprints/s48-0-fair-load-harness.md) / [48.1 conn-pool+worker tuning](sprints/s48-1-connection-pool-worker-tuning.md) / [48.2 catalog cache](sprints/s48-2-catalog-read-cache.md) / [48.3 admin query efficiency](sprints/s48-3-admin-query-efficiency.md) / [48.4 pgbouncer+load-env](sprints/s48-4-pgbouncer-and-load-env.md) / [48.5 `/tarif-plans/<slug>` 400 fix](sprints/s48-5-tarif-plan-slug-400-fix.md) | `vbwd-backend` + `vbwd-platform` + infra | **DRAFT for negotiation — 2026-06-03** (from heavy-load 50/100/500 VU; scales near-linear to 100 VU @ p95 110 ms, knee 100–500; real bug found: gunicorn 4×(20+40)=240 conns > PG max 200; `/tarif-plans/<slug>` 400 = ~83% of errors. Measure-driven sequencing, each sub gated on a re-dispatch) |
| 49 | [GHRM collaborator lifecycle](sprints/s49-ghrm-collaborator-lifecycle.md) (parent) + [49.0 core port+sub impl](sprints/s49-0-core-port-and-subscription-impl.md) / [49.1 membership model](sprints/s49-1-ghrm-repo-membership-model.md) / [49.2 invite-aware client](sprints/s49-2-github-client-invitation-aware.md) / [49.3 service rewrite](sprints/s49-3-github-access-service-rewrite.md) / [49.4 routes+perms+install](sprints/s49-4-routes-permissions-install.md) / [49.5 fe-user tab](sprints/s49-5-fe-user-github-tab.md) / [49.6 ops+live verify](sprints/s49-6-ops-and-live-verification.md) — make subscription-gated repo access actually work (live debug: paying user never lands in the collaborator list because the **mock** GitHub client is live + App unconfigured + latent bugs). Entitlement-scoped per-(user,package) membership w/ INVITED→ACTIVE invitation lifecycle; events live + core `ISubscriptionReadModel.active_plan_ids` port on connect; PAT-based clone (no server-minted tokens); ERROR status surfaced; perm taxonomy fix; gated live GitHub test | **core** `vbwd-backend` (1 port method) + `plugins/ghrm` + `vbwd-fe-user-plugin-ghrm` | **SPEC LOCKED — D1–D7 2026-06-03**, ready to implement (S49.0→S49.6; root-caused w/ evidence; core agnostic via read-model port) |
| 50 | [Domain vocabulary leaves core](sprints/s50-domain-voc-leaves-core.md) (50.0 oracle / 50.1 catalog / 50.2 SEO→cms / 50.3 `subscription_read_model`→registry / 50.4 lifecycle→events / 50.6 checkout+SSE / 50.5 oracle-lock) — remove plugin domain vocab (`subscription`/`tarif`/`plan`/`seo`/`catalog`) from `vbwd/`; **core event-aware, not domain-aware** | **core** `vbwd-backend` + plugins subscription/cms/stripe/paypal/yookassa/ghrm/analytics + `vbwd-fe-admin-plugin-subscription` | ✅ **DONE & LOCKED — 2026-06-06** ([validation report](reports/s50-validation-report.html)). 5 Kind-2 ports gone; **money path → fire-and-forget bus events** (payment plugins now subscription-free, renewal→captured preserved byte-for-byte); SEO/sitemap fully in cms; invoice enrichment via generic opaque-dict registry + add-ons endpoint; checkout events + frontend-event whitelist left core; **enforcing AST vocabulary oracle** (`test_core_no_domain_vocabulary.py` — `catalog` dropped as generic; documented allowlist for D4 invoice residuals / core enums / webhook enums / demo seeders). Gates: be `--full` green (528 integ; 9 GHRM tests env-gated on `GHRM_USE_MOCK_GITHUB`=CI default), fe-admin + fe-user `--full` green. Implemented via **vbwd-tdd agents**. **Not committed.** |
| 55 | [CMS per-page content-areas + page widgets on the unified post](sprints/s55-cms-page-areas-and-widgets.md) (55.0 models+migration / 55.1 routes+enrichment / 55.2 fe-admin PostEditor / 55.3 fe-user wiring / 55.4 deferred legacy retirement) — the S47 unification dropped two `cms_page` features; port them onto `cms_post`: **multiple content blocks** (one editor per layout `content` area) + **per-page widget assignment** (widget on the page's edit screen, overrides the layout widget → **no more cloning a layout to change one widget**). The fe-user `CmsLayoutRenderer` already consumes `content_blocks` + `page_assignments`; this feeds them. | `plugins/cms` + `cms-admin` + fe-user `plugins/cms` (no core) | ✅ **DONE (55.0–55.3) & LIVE-VERIFIED — 2026-06-06.** Backend: new `cms_post_widget` + `cms_post_content_block` + migration up/down; `GET/PUT /admin/cms/posts/<id>/widgets`; `content_blocks` in post payload; admin+public post endpoints return `content_blocks` + access-filtered enriched `page_assignments`; per-post widget overrides layout widget. fe-admin `PostEditor`: 1 editor per layout `content` area + a Page-widgets panel (per-area override). fe-user: typed store fields feed the already-capable `CmsLayoutRenderer`. **Live-verified** on layout `efb7dd25` (3 content + 1 widget) → post edit page renders **3 content parts + 1 widget selector**. Gates green: `--plugin cms --full`, fe-admin `--full` (vitest 486), fe-user `--full`. SEO/prerender stays on primary `content_html` (secondary areas client-side — documented). **55.4 retire dead `cms_page*` = deferred.** Via **vbwd-tdd agents**. **Not committed.** |
| 56 | [CMS SEO admin: tabs + editable robots.txt + sitemap config](sprints/s56-cms-seo-admin-robots-sitemap.md) (56.0 backend / 56.1 fe-admin) — turn `/admin/cms/seo` into **3 tabs**: Prerendered content (default, existing Generate/Clean-up), **Robots.txt** (editable, served verbatim; `seo.mode=off` still forces `Disallow:/`), **Sitemap.xml** (include-pages toggle, excluded page slugs, include/exclude **terms**). | `plugins/cms` + `cms-admin` (no core) | ✅ **DONE & LIVE-VERIFIED — 2026-06-07.** Backend: 5 cms config keys; `GET/PUT /admin/cms/seo/settings` (partial PUT **merges**, preserves other cms keys); `robots()` serves custom `robots_txt` when set; `CmsSitemapProvider` filters by include_pages/excluded_slugs/include_terms/exclude_terms (lazy config provider wired in `seo_wiring`). fe-admin: `CmsSeo.vue` 3-tab page + store `fetchSeoSettings`/`saveSeoSettings`/`fetchTerms`. **Live-verified** — 3 tabs render, sitemap term pickers populated, settings round-trip. Gates: `--plugin cms --full` (138 integ) + oracles + fe-admin `--full` (vitest 502). Via **vbwd-tdd agents**. **Not committed.** |

Engineering requirements (binding): [`sprints/_engineering_requirements.md`](sprints/_engineering_requirements.md).

**Not carried (left in `../20260528/`):** S28 epic strategy docs
(master + phase1 + phase2 — the now-delivered web epic record); **S39**
(core RBAC seeding — *implemented backend* 2026-05-29).

## Blockers / notes

- **S33 + S30 + S29** ✅ **DONE & GREEN/VALIDATED 2026-06-02** (rows above). The
  hardened heavy-load harness now produces trustworthy signal at 50 VU (p95 88 ms,
  ~37 req/s).
- **NEW real signal (from S29 run 26848354627):** `GET /api/v1/tarif-plans/<slug>`
  fails **100%** under load while the list endpoint is fine — the detail route's
  currency/tax **pricing-resolution** path likely 500s on seeded data. This is the
  first real reliability ticket the hardened harness surfaced; needs its own
  backend investigation sprint.
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

### 2026-06-06 — S50 done + three-module gate sweep + e2e workflow

- **S50 DONE/LOCKED** (row 50). Core names no plugin domain; enforcing AST
  oracle. Money path rewired to bus events (S50.4) — payment plugins
  subscription-free; renewal→captured preserved. Implemented via **vbwd-tdd
  agents**, orchestrated sub-sprint by sub-sprint. **Validation report:**
  [`reports/s50-validation-report.html`](reports/s50-validation-report.html)
  (self-contained, 15 screenshots).
- **`--full` green on all three modules:** fe-admin (already green), fe-user
  (fixed 11 pre-existing TS errors), backend (528 integ; static+unit green).
  cms `--plugin` black baseline (6 files from `fdf9c12`) reformatted.
- **GHRM `--full`:** 4 of 13 failures were a real bug — `GithubAppClientError`
  now returns **503** (graceful) not 500. The other **9 are env-gated**: they
  need `GHRM_USE_MOCK_GITHUB=true` (the compose/CI default → pass in CI; proven
  25/25 against a mock api). This dev stack is intentionally on **real GitHub**
  (the `github-app.pem`) — env mismatch, not a defect.
- **Money path confirmed:** admin shows 32 subscriptions; `checkout/coupon-public`
  e2e passes; checkout flow renders; subscription/stripe/paypal/yookassa recurring
  + checkout integration green. `subscription.spec.ts` failures = stale-route rot.
- **NEW e2e workflow:** [`vbwd-platform/.github/workflows/e2e.yml`] —
  `workflow_dispatch`, two modes: against a given `target_url`, or build the full
  stack on localhost in-CI (compose up + migrate + `make install-demo-data`) and
  run Playwright vs `:8080`. Default specs = the money-path `checkout/` suite.
  Uploads the HTML report artifact. **Needs committing to the vbwd-platform repo.**
- **fe-user latent bug (deferred):** 5 alt-payment views (conekta / mercado-pago /
  promptpay / toss / truemoney) treat the API client's deserialized body as a
  `fetch` Response — would throw at runtime. Stripe / PayPal / token unaffected.
  Made type-correct; behaviour fix needs a characterisation test.
- **Ops lesson:** do NOT `docker restart` the fe-admin/fe-user **dev** containers —
  the restart re-runs `npm install`, which crashes on host-polluted esbuild in the
  bind-mounted `fe-core/node_modules` (`0.21.5` vs `0.28.0`). Vite HMR already
  serves source edits, so the restart is unnecessary. Recovery: reinstall esbuild
  inside a Linux container, then `docker start`.
- **Not committed** anywhere (plugins gitignored; `e2e.yml` lives in the separate
  `vbwd-platform` repo).
- **S55 drafted + backend landed** (row 55): review found the S47 unification
  dropped legacy `cms_page` multi-content-areas + per-page widgets and never
  ported them to `cms_post`; `cms_page`/`cms_page_content_block`/`cms_page_widget`
  are now **orphaned/dead** (Pages opens the unified PostEditor; legacy routes
  unreachable). S55 ports both features onto `cms_post` (backend done & green;
  fe-admin + fe-user in progress). Fixes the "clone a layout to change one widget"
  pain. Dead `cms_page*` retirement deferred (S55.4).
