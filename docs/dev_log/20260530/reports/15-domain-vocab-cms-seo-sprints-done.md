# Report 15 — S50 / S52 / S54 / S55 / S56 done + moved to `done/`

**Date:** 2026-06-07. **Author:** orchestrated via `vbwd-tdd` agents (per [[feedback_use_tdd_agent_for_implementation]]).
**Scope:** five sprints marked done and relocated `sprints/ → done/`; status-table links updated. **Nothing committed** — all backend/plugin/fe code is on disk (plugins are gitignored); docs + nginx files on disk for review.

## Summary

| Sprint | What | Status | Verified by |
|---|---|---|---|
| **S50** Domain vocabulary leaves core | Remove `subscription`/`tarif`/`plan`/`seo`/`catalog` from `vbwd/`; money path → bus events; enforcing AST oracle | ✅ DONE & LOCKED | **me** (implemented + gated + report `s50-validation-report.html`) |
| **S55** CMS per-page content-areas + page widgets | Port the dropped legacy `cms_page` features onto `cms_post` (N content blocks per layout `content` area + per-page widget override) | ✅ DONE (55.0–55.3) & LIVE-VERIFIED | **me** (implemented + gated + screenshots) |
| **S56** CMS SEO admin tabs | `/admin/cms/seo` → 3 tabs: Prerendered / Robots.txt (editable) / Sitemap.xml (include-pages + excluded slugs + include/exclude terms) | ✅ DONE & LIVE-VERIFIED | **me** (implemented + gated + screenshot) |
| **S54** CMS bulk-assign layout + default-layout | bulk "Assign layout" + render-time `default_layout_id` fallback | ✅ DONE (owner-confirmed) | **owner** (I shipped the bulk "⊘ Unset layout/category" extension; the `default_layout_id` + bulk-assign appear present, but I did not implement/verify the full sprint) |
| **S52** User API Keys (+ CMS ingestion) | programmatic per-user API-key auth + CMS content-ingestion consumer | ✅ DONE (owner-confirmed) | **owner** (not implemented/verified in this session) |

> **Honesty note:** S50, S55, S56 I implemented and verified this session (gates + live checks below). **S52 and S54 I am marking done on the owner's explicit instruction** — their docs read PLANNED/DRAFT and I have no session evidence of full implementation. Verify before tagging a release.

## S50 — Domain vocabulary leaves core (LOCKED)
Shipped via S50.1 (catalog port deleted), S50.2 (SEO/sitemap → cms, routes on `cms_bp` at root), S50.3 (`subscription_read_model` → generic opaque-dict `invoice_extra_fields_registry` + add-ons endpoint + fe-admin tab), S50.4 (`subscription_lifecycle` → 5 fire-and-forget bus events; **payment plugins now subscription-free**; renewal→`payment.captured` preserved byte-for-byte), S50.6 (checkout events → subscription plugin; frontend-event whitelist → extensible registry), S50.5 (oracle lock — `tests/unit/test_core_no_domain_vocabulary.py`, AST-based, `catalog` dropped as generic, documented allowlist). Gates: backend `--full` green (528 integ; **9 GHRM tests env-gated** on `GHRM_USE_MOCK_GITHUB`=CI default — pass in CI, proven 25/25 vs a mock api; a real 503-vs-500 GHRM bug was fixed), fe-admin + fe-user `--full` green. Money-path e2e: coupon-public passes; admin shows 32 subscriptions; checkout renders. Full detail + 15 screenshots: [`s50-validation-report.html`](s50-validation-report.html). Memory: [[project_s50_done_and_gate_e2e_lessons]].

## S55 — per-page content-areas + page widgets on `cms_post`
The S47 unification had dropped legacy `cms_page` multi-content-areas + per-page widgets and never ported them; `cms_page`/`cms_page_content_block`/`cms_page_widget` were left orphaned. S55 ports both onto `cms_post`:
- **Backend:** new `cms_post_widget` + `cms_post_content_block` + plugin migration (up/down verified); `GET/PUT /admin/cms/posts/<id>/widgets`; `content_blocks` in the post payload; admin + public post endpoints return `content_blocks` + access-filtered, widget-enriched `page_assignments`; a per-post widget **overrides** a layout widget for the same area.
- **fe-admin `PostEditor`:** one editor per layout `content` area (primary → `content_html`, extras → blocks, labeled by area) + a **Page-widgets panel** restricted to `page-widget`-type areas (per-area override).
- **fe-user:** typed store fields feed the already-capable `CmsLayoutRenderer` (renderer was unchanged).
- **Live-verified:** post on layout `efb7dd25` ("3 conent + 1 widget") renders exactly **3 content parts + 1 widget selector**.
- Gates: `--plugin cms --full` (115 integ), fe-admin `--full` (vitest 488), fe-user `--full`.
- **SEO scope:** prerender/search/RSS stay on the primary `content_html`; secondary areas + page widgets render client-side (documented).
- **S55.4 (retire the dead `cms_page*` tables/routes/`CmsPageEditor.vue`) is deferred** — tracked, not done.

## S56 — CMS SEO admin tabs + editable robots + sitemap config
`/admin/cms/seo` is now 3 tabs:
1. **Prerendered content** (default) — existing Generate / Clean-up.
2. **Robots.txt** — editable; served **verbatim** when set; `seo.mode=off` still forces `Disallow: /`.
3. **Sitemap.xml** — **include pages** (yes/no), **excluded page slugs**, **include terms** / **exclude terms** (term slugs from categories+tags).
- **Backend:** 5 cms config keys; `GET/PUT /admin/cms/seo/settings` (partial PUT **merges** — never clobbers other cms keys); `robots()` override; `CmsSitemapProvider` filters by include_pages/excluded_slugs/include_terms/exclude_terms via a lazy config provider wired in `seo_wiring`.
- **fe-admin:** `CmsSeo.vue` 3-tab page + store `fetchSeoSettings`/`saveSeoSettings`/`fetchTerms`.
- Gates: `--plugin cms --full` (138 integ) + oracles + fe-admin `--full` (vitest 502). Live-verified (3 tabs, term pickers populated, round-trip).

## Adjacent fix this session (not a sprint) — sitemap/robots served via nginx
`/sitemap.xml` + `/robots.txt` 404'd at `:8080`: the fe-user nginx never proxied those root paths (they're **dynamic backend routes**, not files), so they fell to the SPA. Added proxy blocks to `vbwd-fe-user/nginx.dev.conf` + `nginx.prod.conf.template`; verified `200 application/xml` / `text/plain`. Documented in `plugins/cms/docs/seo/nginx-prerender.md` (§2b). (macOS single-file-mount gotcha: restart the nginx container, don't `nginx -s reload`.)

## Ship-to-prod checklist (BINDING — nothing is committed)
All of this lives on disk only (plugins gitignored; nginx/docs uncommitted). To deploy:
1. Commit the cms changes to **`vbwd-plugin-cms`** (backend image clones plugins at build) → rebuild `vbwd_backend` image.
2. Commit the **`cms-admin`** fe-admin plugin + the fe-admin store/PostEditor/CmsSeo changes to their repo → rebuild `vbwd_fe_admin` image.
3. Commit `nginx.prod.conf.template` to **`vbwd-fe-user`** → rebuild `vbwd_fe_user` image (template is `COPY`'d into the image; envsubst at container start — **no server edit, no `vbwd-demo-instances` change**).
4. Deploy with **`skip_build = false`** so the new images are built (skip_build=true ships the old images).
5. Plugin migration `cms_post_widget` + `cms_post_content_block` runs via the normal alembic upgrade on deploy.

## Files relocated
`sprints/ → done/`: `s50-domain-voc-leaves-core.md`, `s52-user-api-key.md`, `s54-cms-bulk-assign-layout.md`, `s55-cms-page-areas-and-widgets.md`, `s56-cms-seo-admin-robots-sitemap.md`. Status-table links repointed; S52 + S54 rows added to the index.
