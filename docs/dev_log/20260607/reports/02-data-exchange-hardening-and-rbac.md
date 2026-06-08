# Report 02 (2026-06-07 → 06-08) — Data-Exchange hardening, legacy retirement, CSV, styling + RBAC "user" role removal

**Continues** [report 01](01-data-exchange-and-core-settings.md) (S46 Unified Data Exchange + S57). This covers the follow-on bug fixes, the retirement of all legacy export/import, UI polish, two git reconciliations, and a core RBAC cleanup. **Method:** mostly direct hands-on edits + a few `vbwd-tdd` agents; gate-verified per change. **Nothing committed by me;** the user committed/pushed fe-core (see "Git" below).

## Summary

| Area | Change | State |
|---|---|---|
| **Export bug** | "Export selected" exported **empty files** | ✅ fixed — `selector.ids` now matches primary UUID (or natural key) across all exchangers |
| **cms_images ZIP** | "export as zip" produced an invalid file ("unsupported format") | ✅ fixed — real `assets/` image files + manifest; round-trip import |
| **subscriptions 500** | export 500'd (`SubscriptionStatus` enum not JSON-serializable) | ✅ fixed — enum→`.value` in the exchanger + defensively in `BaseModelExchanger` |
| **CSV everywhere** | all **sales** entities now export json **or** csv | ✅ already in code (`rows_to_csv` handles nested cells) — activated by restart |
| **Legacy retirement** | removed **all** old export/import (backend routes + fe UI + the `CmsImportExport` page) | ✅ unified framework is the only path (one documented exception) |
| **CMS list controls** | added the unified control to Layouts/Widgets/Styles/Images + Terms | ✅ "Export selected" on every CMS list |
| **GDPR** | removed bulk export on Users (Export all / Export selected) | ✅ |
| **Export current filter** | removed the button everywhere | ✅ deleted from the fe-core control |
| **Styling** | `.import-export-view` now matches `.payment-methods-view` | ✅ white card + same `.page-header` |
| **Docs** | backend + cms developer guides for import/export | ✅ |
| **RBAC** | removed the redundant `user` system role (ambiguous in the access-levels UI) | ✅ seeder + migration + tests |

## Bug fixes (backend data-exchange)

- **Export-selected was empty:** `BaseModelExchanger._select_rows` matched `selector.ids` against the **natural key** (`code`/`slug`/`email`), but the UI sends the rows' **primary UUIDs**. Fixed to match **id OR natural key** (stringified) in `BaseModelExchanger` and every custom exchanger (`users`/`invoices`/`access_levels`, cms posts/terms/images, shop orders, booking) — via the `vbwd-tdd` agent, with regression tests. (`booking` selection override removed as redundant.)
- **cms_images ZIP:** the per-entity export route had **no `zip` branch** → it returned JSON saved as `.zip`. Added an optional `EntityExchanger.export_zip()`/`attach_assets()` contract (defaults preserve behavior); the route now builds a real `application/zip` via `build_bundle(..., assets=...)`; `CmsImagesExchanger` emits real image files under `assets/` (not base64) and round-trips on import. `export_bundle` also includes real assets now.
- **subscriptions 500:** `SubscriptionsExchanger` emitted the `status` SQLAlchemy enum, which Flask `jsonify` can't serialize. Fixed: enum→`.value` in `_serialise`, and **defensively in core `BaseModelExchanger._serialise_row`** so no entity can 500 on an enum field. Verified live (200, 33 rows, `status` is a string).
- **CSV for all sales:** every sales exchanger already declared `{"json","csv"}` and `rows_to_csv` already JSON-encodes nested cells (e.g. `users.details`); a backend restart surfaced CSV in the manifest for all 11 sales entities. (Default selector currently shows CSV first — flagged: JSON is the safer default.)

## Legacy export/import retirement (the "one framework" rule)

Removed every pre-S46 export/import path so the **unified data-exchange framework is the only one**:
- **Backend routes deleted** (~22): core `access` (4) + `countries` (2); `email/templates/import`; cms `pages`/`images`/`layouts`/`widgets`/`styles`/`terms` export+import + the full-CMS `/cms/export|import` ZIP. Exchanger-backing services (`post_/term_import_export_service`, `country_io`) kept; dependent tests removed/migrated.
- **fe-admin/cms-admin UI deleted:** AccessLevels + Settings→Countries buttons, cms store `exportCms`/`importCms` + per-entity methods, `CmsContentList` old buttons + `exportContent`, `CmsBulkBar` "Export selected", the 4 cms lists' old buttons, term export/import. **Deleted the whole `CmsImportExport.vue` page + its route + nav.** TermManager got the unified `cms_terms` control. Orphaned i18n removed; no-leftovers grep clean; fe-user verified clean.
- **One deliberate exception (FLAGGED):** `GET/POST /admin/cms/posts/export|import` kept — the marketing content-ingestion scripts (`docs/marketing/cms-imports/bin/{import,restore-home}.sh`) drive them via `curl`. The UI no longer calls them. To fully retire: migrate those scripts to `flask data-exchange import cms_posts`.

## UI changes (fe-admin / fe-core)

- **CMS lists:** unified `ImportExportControls` added to Layouts/Widgets/Styles/Images (entity keys `cms_*`, selection-fed `selectedIds`, manifest-derived caps). Posts/Pages + Users/Invoices/Payment-methods/Access-levels already had it.
- **GDPR (Users):** `:allow-export-all="false" :allow-export-selected="false"` — no bulk user export.
- **"Export current filter" removed everywhere:** deleted the button + handler + label + `allowExportFiltered` prop from the fe-core control; spec updated (15 pass); dist rebuilt. Verified via screenshot (Payment Methods now shows only Export selected · Export all · CSV · Import).
- **Styling parity:** `ImportExport.vue` `.import-export-view` now uses the same white card (`background:white; padding:20px; border-radius:8px`) + `.page-header` + dark `h2` as `.payment-methods-view`. Screenshots confirm.

## Docs

- `vbwd-backend/docs/developer/import-export.md` — the data-exchange system + how to extend with a plugin exchanger (the `EntityExchanger` contract, `BaseModelExchanger`, registration in `on_enable`, permissions, worked examples from core `currencies` + cms `cms_posts`/`cms_images`).
- `vbwd-backend/plugins/cms/docs/developer/import-export.md` — cms-specific: the 6 exchangers, UI/CLI usage, `content_blocks`/`page_assignments` + image-binary handling, the retained posts routes, gotchas.

## RBAC — removed the redundant "user" system role

The access-levels UI listed three RBAC roles (`super_admin`/`admin`/**`user`**); the `user` role had **0 permissions, 0 assignments, and is never checked** (regular accounts are identified by the `UserRole.USER` **enum**, and admin auth is enum-backward-compatible). It only created ambiguity.
- **Seeder** (`rbac_seeder.py`): dropped `user` from `DEFAULT_ROLES` → seeds only `super_admin` + `admin`.
- **Migration** (`alembic/versions/20260608_1000_remove_user_role.py`): deletes the `user` system role (clears stray links) for deployed DBs; chains off the core head `20260607_1000_add_bot_role`; reversible downgrade.
- **Tests** updated (13 pass); black/flake8 clean. Live dev DB now has only `admin` + `super_admin`; admin access verified (200s).

## Git reconciliations

1. **fe-core submodule divergence** (admin submodule `c3582de` vs remote `5bdf865`): `origin/main` was a strict superset (cluster fix + `responseType` + coupons); the local commit was the inferior duplicate → adopted `origin/main` (recoverable via reflog).
2. **fe-core push rejected** (local `e9d37e6` vs remote `94c8a8d`): identical source, differing only in regenerated `dist/` + a +57-line test. Adopted remote `dist` (valid build of the identical source), re-applied the test on top → clean fast-forward push (`7e076e2`). Submodule fast-forwarded. **All repos in sync.**

## Gates

Backend: per-plugin + core `--full` green for every touched area (the only standing failures are the known **GHRM `GHRM_USE_MOCK_GITHUB` 503** env tests). fe-admin `--full` green (eslint 0, vue-tsc, vitest 513/527 unit). fe-core: dataExchange specs + build green (2 pre-existing unrelated specs fail on baseline). RBAC: 13 unit tests + lint green.

## Cautions / lessons

- **A test wiped the dev DB:** running `tests/unit/services/test_rbac_seeder.py` emptied the **dev** `vbwd` DB's RBAC tables (the test hit the dev DB, not a `_test` DB). Restored by re-running the seeder. **Test-isolation hazard — the backend suite can clobber dev data.** Worth fixing the test DB isolation. [[feedback_ci_precommit_lessons]]
- **fe-core dist/.vite staleness** kept causing "missing button / page won't render" — every fe-core change needs: rebuild top-level dist (in a container) → clear `.vite` → restart fe-admin → hard-refresh. [[project_fe_core_dist_vite_cache_staleness]]
- **Default export format** is currently CSV for csv-capable entities (csv sorts first); JSON is the lossless default — open one-line flip.

## Follow-ups (open)

`cms_routing_rules` exchanger (nav item exists, no exchanger) · migrate marketing posts scripts → CLI, then drop the last `cms/posts` routes · flip default export format to JSON · investigate the test→dev-DB isolation bug.
