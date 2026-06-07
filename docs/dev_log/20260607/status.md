# 2026-06-07 — Dev day status

> Forward backlog. The **planned/unfinished** sprints from [`../20260530/status.md`](../20260530/status.md)
> were carried here; everything **done** stays archived under `../20260530/done/`
> (S29/S30/S33/S36/S37/S47/**S50/S52/S54/S55/S56** …). `done/` and `reports/`
> here are empty until this day produces them.

## Theme

CMS is now feature-complete for authoring + SEO (S47 unified model, S50 core
made domain-agnostic, S55 per-page content-areas + page widgets, S56 SEO admin
tabs). The next big rock is **S46 Unified Data Exchange** — now **unblocked** by
S50 and **realigned to reality** (see its 2026-06-07 alignment section). Parallel
tracks available: the **S45 bot bridge** epic and the **S48 load/resilience** epic.

## Sprints

| # | Sprint | Area | Status |
|---|--------|------|--------|
| 41 | [CMS AI Helper — prompt-driven content & SEO generation in the editor](sprints/s41-cms-ai-helper.md) | `plugins/cms-ai` + `cms-admin` | **DRAFT for negotiation** (rewritten 2026-06-06) |
| 45 | [bot-base + provider adapters — provider-neutral bot bridge (umbrella)](sprints/s45-bot-base-bridge.md) + [45.0 foundation](sprints/s45-0-bot-base-foundation.md) / [45.1 telegram](sprints/s45-1-bot-telegram-adapter.md) / [45.2 chat consumer](sprints/s45-2-chat-bot-consumer.md) / [45.3 taro consumer](sprints/s45-3-taro-bot-consumer.md) / [45.4 fe-admin](sprints/s45-4-fe-admin-bot-telegram.md) / [45.5 meinchat](sprints/s45-5-bot-meinchat-adapter.md) / [45.6 zapier](sprints/s45-6-bot-zapier-adapter.md) | new `vbwd-plugin-bot-*` + fe-admin | **PLANNED — D1–D10 decided** (45.0–45.5 ready to implement; **45.6 zapier DEFERRED**) |
| 46 | [Unified Data Exchange — core import/export for every entity](done/s46-unified-data-exchange.md) · [architecture doc](../../architecture/data-exchange.md) | **core** `vbwd-backend` + `vbwd-fe-core` + `vbwd-fe-admin` + plugins cms/subscription/booking/ghrm/shop/discount | ✅ **DONE (S46.0–S46.7) — 2026-06-07.** Seam (registry/port/envelope JSON·CSV·ZIP/`BaseModelExchanger`/`/admin/data-exchange/*` routes/perm-catalog/row cap) · 7 core exchangers · email templates → `var/assets/<owner>/…` · fe-core components · fe-admin **Import/Export = last item in the SETTINGS sidebar group** (`/admin/import-export`, R12-gated) + per-list controls (Users/Invoices/Payment-methods/Access-levels) · 6 cms exchangers (posts carry S55 content_blocks/page_assignments; images base64/ZIP) · 5 plugin sets (subscription/booking/ghrm/shop/discount) · `flask data-exchange` CLI · architecture doc. Each repo `--full` green (only unrelated ghrm-503 env failures remain). **Follow-ups (flagged):** `core_settings` exchanger (after S57 ✅) · content-packs recipe wiring · fe-admin CMS tab · land fe-core `ApiClient.responseType` in the `vbwd-fe-core` repo · retire bespoke cms/access legacy routes. **Not committed.** |
| 48 | [Load capacity & resilience (umbrella)](sprints/s48-load-capacity-and-resilience.md) + [48.0 fair harness](sprints/s48-0-fair-load-harness.md) / [48.00 measurement tool](sprints/s48-00-measurement-tool.md) / [48.1 pool/worker](sprints/s48-1-connection-pool-worker-tuning.md) / [48.2 catalog cache](sprints/s48-2-catalog-read-cache.md) / [48.3 admin queries](sprints/s48-3-admin-query-efficiency.md) / [48.4 pgbouncer+env](sprints/s48-4-pgbouncer-and-load-env.md) / [48.5 tarif-slug 400](sprints/s48-5-tarif-plan-slug-400-fix.md) | `vbwd-backend` + `vbwd-platform` + infra | **DRAFT** (umbrella). **48.00 measurement tool BUILT**; 48.0/48.1/48.2/48.3/48.5 PLANNED; 48.4 DRAFT. Measure-driven — each sub gated on a re-dispatch. |
| 51 | [GHRM per-package GitHub permission level](sprints/s51-ghrm-per-package-permission-level.md) | `plugins/ghrm` + `vbwd-fe-user-plugin-ghrm` | **READY — 2026-06-05** |
| 52 | [User API Keys — core mechanism + CMS content-ingestion consumer](done/s52-user-api-key.md) | `vbwd-backend` + `plugins/cms` | ✅ **DONE — 2026-06-07 (owner-confirmed)** (a copy is archived in `../20260530/done/`; consider removing the planned copy here) |
| 53 | [bot commerce storefront — `subscription` over the messenger bridge](sprints/s53-bot-commerce-storefront.md) | `plugins/subscription` + bot bridge | **PLANNED — 2026-06-06** (carved out of S45; depends on the bot bridge) |
| 57 | [Persist core settings (file-backed `var/core/vbwd_settings.json`)](done/s57-persist-core-settings.md) | **core** `vbwd-backend` | ✅ **DONE — 2026-06-07.** File-backed `core_settings_store` (atomic write, defaults-merge, known-key whitelist); route rewired (API/UI unchanged); `var/core/*.json` gitignored. Fixes the latent restart-wipe + multi-worker bug. Gate: core `--full` (Part A/B) + oracles green; 7 unit + 8 integration tests. Unblocks the S46 `core_settings` fast-follow. **Not committed.** |
| 58 | [Unified `FilesystemManager` for `${VBWD_VAR_DIR}` (and uploads) tree](sprints/s58-unified-var-filesystem-manager.md) | **core** `vbwd-backend` | **PLANNED — 2026-06-07** (D1–D8 proposed; ratify before 58.0). Generalizes the `var/core` + `var/assets/<owner>/…` conventions established in S57/S46. |
| 59 | [GHRM bundle packages (one plan → many repos)](sprints/s59-ghrm-bundle-package.md) | `plugins/ghrm` + fe | ✅ **READY — 2026-06-07** |
| 60 | [Contact form → meinchat (optional, bot-sender)](sprints/s60-contact-form-to-meinchat.md) | `plugins/meinchat` + cms/contact | **DRAFT for negotiation — 2026-06-07** |
| 59 | [GHRM bundle packages — one plan → many repos (Single/Bundle mode switch)](sprints/s59-ghrm-bundle-package.md) | `plugins/ghrm` + `vbwd-fe-admin` (`ghrm-admin`) | **READY — 2026-06-07.** Bundle = one `GhrmSoftwarePackage` (still `UNIQUE(tariff_plan_id)`) resolving to many repos via a new `repo_targets()` seam + admin-curated `bundle_repos` JSON; grant/revoke loop it (revoke is overlap-aware, D6); drops `UNIQUE(owner,repo)` (D4); membership gains per-repo `repo_grants` (D5). Software tab gets a Single/Bundle switch + repo-list editor. Live `?q=` query resolution deferred to **S59.1**. Depends on S49 + S51. |

Engineering requirements (binding): [`sprints/_engineering_requirements.md`](sprints/_engineering_requirements.md).

## Recommended next

1. **S46 Unified Data Exchange** — the highest-leverage core feature, now unblocked.
   Start S46.0 (the registry/port/envelope/ZIP/base-exchanger + generic routes),
   then S46.1 core exchangers (**skip `core_settings`**), S46.3/4 fe-core+fe-admin.
   **Before S46.5:** rewrite the CMS section to the unified `cms_post`/`cms_term` +
   wrap the existing `post_import_export_service` (CMS already implements the
   VBWD-standard envelope — it's adapter work, not greenfield).
2. **S51 GHRM per-package permission** — small, READY, self-contained.
3. **S45 bot bridge** — large epic; 45.0–45.5 decided. Independent of S46.

## Notes / decisions

- **S46 `core_settings` → [S57](done/s57-persist-core-settings.md) (decided 2026-06-07).**
  Descoped from S46 v1. Core-settings persistence (`var/core/vbwd_settings.json`) is its
  own READY sprint (S57) that also fixes a latent prod bug (`vbwd/routes/admin/settings.py`
  is still an in-memory `_settings` dict — wiped on restart, inconsistent across workers);
  the `core_settings` exchanger then becomes an S46 fast-follow.
- **S46 is the only one re-validated against current code today.** S41/S45/S48/S51/
  S53 statuses are carried from their docs and **not** re-checked against the
  post-S50/S55/S56 codebase — re-verify each before implementing (esp. S41 CMS-AI,
  which touches the unified CMS model).
- **Ship-to-prod reminder:** all recently-shipped CMS/core/nginx changes (S50, S55,
  S56, the sitemap/robots nginx proxy) are **on disk only** (plugins gitignored;
  nginx/docs uncommitted). They must be committed to their standalone repos
  (`vbwd-plugin-cms`, the `cms-admin` fe repo, `vbwd-fe-user`) and the images
  rebuilt (deploy with `skip_build=false`) to reach prod. See
  [`../20260530/reports/15-domain-vocab-cms-seo-sprints-done.md`](../20260530/reports/15-domain-vocab-cms-seo-sprints-done.md).
- **S45.6 (Zapier adapter)** is explicitly DEFERRED (documented future adapter).
