# Sprint 56 — CMS SEO admin: tabs + editable robots.txt + sitemap config

**Status:** DONE — 2026-06-07 (implemented + live-verified).
**Repos:** `vbwd-backend` (`plugins/cms`: config keys + settings endpoints + editable robots + sitemap filtering) · `vbwd-fe-admin` (`plugins/cms-admin`: turn `CmsSeo.vue` into 3 tabs). **No core change** (all in the cms trio; [[feedback_core_never_depends_on_plugins]]).
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · core agnostic · **NO OVERENGINEERING** · [[feedback_plugin_baseline_config_files]]. Gate: `bin/pre-commit-check.sh --plugin cms --full` (backend) + `npm run lint && npm run test` (fe-admin).

## Problem
The `/admin/cms/seo` page (`CmsSeo.vue`) has only the Prerendered-content Generate/Clean-up buttons. `robots.txt` is a hard-coded template (`seo_routes.py`) and `sitemap.xml` blindly lists every search-visible published post — neither is admin-configurable.

## Design — 3 tabs on `/admin/cms/seo`
1. **Prerendered content** (DEFAULT, unchanged) — the existing Generate + Clean-up section.
2. **Robots.txt** — a textarea to edit the served robots.txt. Empty ⇒ the current default template. `seo.mode=off` still forces `Disallow: /` (safety override).
3. **Sitemap.xml** — config: **include pages** (yes/no), **excluded page slugs** (list), **terms to include** (only posts carrying ≥1), **terms to exclude** (drop posts carrying any).

## Backend (`plugins/cms`)
- **Config keys** (DEFAULT_CONFIG in `__init__.py`): `robots_txt: ""`, `sitemap_include_pages: True`, `sitemap_excluded_slugs: []`, `sitemap_include_terms: []`, `sitemap_exclude_terms: []` (term **slugs**). Stored in the cms config_store (same blob as `seo_prerender_enabled`).
- **Endpoints** (`cms_bp`, perm `cms.manage`):
  - `GET /api/v1/admin/cms/seo/settings` → the five keys from `_cms_config()`.
  - `PUT /api/v1/admin/cms/seo/settings` → **read-modify-write MERGE** into the cms config then `config_store.save_config("cms", merged)` (must NOT clobber the other cms keys — `save_config` replaces the plugin blob).
- **robots()** (`seo_routes.py`): if `seo.mode==off` → `Disallow: /` (unchanged). Else if `_cms_config().robots_txt` is non-empty → serve it **verbatim** (`text/plain`). Else the current default template.
- **Sitemap filtering** (`CmsSitemapProvider`): inject a lazy `sitemap_config_provider()` (mirroring `public_base_url_provider`) reading the four sitemap keys; in `sitemap_entries()`, after the search-visible predicate, also drop a post when: `not include_pages and post.type=='page'`; `post.slug in excluded_slugs`; `include_terms` non-empty and the post shares none; the post shares any `exclude_terms`. (Provider already has `terms_for(post)` → use term **slugs**.) Wire the config provider in `seo_wiring.register_seo_pipeline`.

## fe-admin (`CmsSeo.vue` + `useCmsContentStore`)
- Tab bar (`data-testid` per tab): `tab-prerender` (default), `tab-robots`, `tab-sitemap`.
- **Robots tab:** `<textarea data-testid="robots-editor">` + Save.
- **Sitemap tab:** include-pages checkbox; excluded-slugs editor (comma/line list or chips); include/exclude term multi-selects from the existing category/tag term fetch; Save.
- Store: `fetchSeoSettings()` / `saveSeoSettings(payload)` → GET/PUT `/admin/cms/seo/settings`. Load on mount.

## TDD
- **backend unit:** robots serves custom text when set, default when empty, `Disallow:/` when mode off; sitemap provider filters by include_pages / excluded_slugs / include_terms / exclude_terms (MagicMock loader). settings PUT merges (other cms keys preserved).
- **backend integration (`db`):** PUT settings → GET returns them; `/robots.txt` reflects a saved custom body; `/sitemap.xml` omits an excluded slug / an excluded-term post / pages when include_pages=false.
- **fe-admin vitest:** 3 tabs render, default = prerender; robots textarea loads + saves; sitemap controls load + save; term pickers populate.

## Sub-sprints
- **S56.0 backend** (config + endpoints + robots + sitemap filter). `--plugin cms --full` green.
- **S56.1 fe-admin** (3 tabs + store). `--full` green.

## DoD
`/admin/cms/seo` has 3 tabs (Prerendered default); robots.txt is editable + served; sitemap.xml honors include-pages + excluded-slugs + include/exclude-terms; settings persist via merge (no cms-config clobber); `seo.mode=off` still wins; gates green; core untouched. Not committed.
