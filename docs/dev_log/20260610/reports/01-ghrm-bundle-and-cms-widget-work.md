# Report 01 — GHRM software-categories refactor, GHRM bundle packages (S59), CMS widget bugs (S68)

**Date:** 2026-06-10 (session spanning 06-07 → 06-10)
**Areas:** `plugins/ghrm` + `vbwd-fe-admin` (`ghrm-admin`, core settings renderer) · `plugins/cms` (specs)
**Status:** GHRM settings refactor + **S59 implemented** and gated green (modulo pre-existing env failures); **S68 specced** (not implemented). **Nothing committed** (standing rule).

---

## 1. GHRM software categories — single source of truth + dual-list selector

**Problem.** The "Software" tab on a tariff plan was gated by a **hardcoded** `SOFTWARE_CATEGORY_SLUGS = ['backend','fe-user','fe-admin']` in `vbwd-fe-admin/plugins/ghrm-admin/index.ts`, duplicating the backend `software_category_slugs` setting. Changing the backend setting didn't move the gate. The setting itself was a free-text comma string.

**Done.**
- New core, domain-agnostic **`vbwd-fe-admin/vue/src/components/DualListSelector.vue`** (generic two-panel selector: `modelValue: string[]` + `options`).
- New generic **`dual-list` config-field type** in `vue/src/views/BackendPluginDetails.vue` that fetches its options from a declared endpoint — core stays agnostic; any plugin can reuse it.
- Backend **`plugins/ghrm/admin-config.json`**: `software_category_slugs` → `component: "dual-list"`, `optionsEndpoint: /admin/tarif-plan-categories`, `valueKey: slug`, `labelKey: name`. (Backend passes unknown field keys through untouched — no `plugins.py` change.)
- **`plugins/ghrm-admin/index.ts`**: removed the hardcode; registers the Software tab with safe defaults, then fetches `/admin/plugins/ghrm` and **re-registers** with the saved slugs. The extension registry is `reactive`, so `PlanForm.visiblePlanTabs` recomputes automatically.
- **`PlanForm.vue`** gate semantic clarified: `requiredCategorySlugs === undefined` → always show; an explicit (even empty) list gates on a match (so zero software categories hides the tab everywhere, instead of showing it on all plans).

**Verify.** `vue-tsc` 0 errors · ESLint clean · Vitest: `BackendPluginDetails` (10) + PlanForm/extension-registry/`subscription-agnostic`/`no-dead-subscription-core` suites (76) green — confirming no domain leak into core.

---

## 2. S59 — GHRM bundle packages (one plan → many repos)

**Spec:** [`../../20260607/sprints/s59-ghrm-bundle-package.md`](../../20260607/sprints/s59-ghrm-bundle-package.md) (authored, then implemented).
**Idea:** a bundle is still **one `GhrmSoftwarePackage` on one plan**, but resolves to **many** repos; buying it makes the customer a collaborator on all of them.

**Backend (`plugins/ghrm`).**
- Model: `package_kind` (`single`|`bundle`, default single), `bundle_repos` JSON, and the **`repo_targets()`** seam (single → 1 pair; bundle → deduped list). `to_dict()` carries both. Dropped `UNIQUE(owner,repo)` (D4) so a repo can be sold standalone *and* in a bundle; kept `UNIQUE(tariff_plan_id)`/`UNIQUE(slug)`.
- Membership: per-repo **`repo_grants`** JSON (D5); row status stays the rollup.
- Service: `_ensure_collaborator` grants every repo in `repo_targets()` at the package's permission and records per-repo results; **`_tear_down_membership` is overlap-aware** — won't remove a repo still covered by another live membership (D6, via new `_repos_still_entitled`).
- Validators `validate_package_kind` / `validate_bundle_repos` wired into create + update; switching to single clears `bundle_repos`.
- Migration **`20260607_1000_ghrm_bundle`** (down_revision `20260605_1000_ghrm_pkg_perm`): additive columns + drop constraint + backfill `repo_grants` from each package's repo; up→down→up validated. **Applied to the local stack** (`alembic upgrade heads`; columns + dropped constraint verified in psql).

**fe-admin (`ghrm-admin`).** Single | Bundle **mode switch** on the Software tab; bundle mode adds a representative "showcase repo" + a repeatable `{owner, repo}` list editor with an org `?q=` search hint and an empty/blank-row guard. Payload sends `package_kind` always and `bundle_repos` (bundle) / `[]` (single). i18n keys added to all 8 locales.

**Gate.** Backend `bin/pre-commit-check.sh --plugin ghrm --full`: Part A (black/flake8/mypy) green, 183 unit green, integration 68 passed / 3 skipped / **10 pre-existing failures** — 9 sync-endpoint 503s (container runs `GHRM_USE_MOCK_GITHUB=false`, no real creds) + 1 `fe-admin` category-seed gap; both excluded by the spec's DoD and causally independent of these changes. fe-admin: Vitest **641 green** (18 on `GhrmSoftwareTab`, incl. new `GhrmSoftwareTab.bundle.spec.ts`), `vue-tsc` 0, ESLint clean.

**Follow-up tweak.** The bundle "Remove" control was a full-width red button; reworked to a **small square icon button (`×`)** inline to the right of each row's fields (`ghrm-icon-btn`, flex row). Vitest 10 green, `vue-tsc`/ESLint clean.

---

## 3. Browser verification + a tooling root cause

- **Walkthrough screenshots** (Playwright, clean browser at `http://localhost:8081`): [`s59-bundle-walkthrough/`](../../20260607/reports/s59-bundle-walkthrough/) — single mode, bundle empty, bundle filled, the empty-bundle guard, the icon-button layout, and a stamped live-URL proof frame.
- **Recurring dev-server gotcha (diagnosed + fixed twice):** edits to `vbwd-fe-core`/plugin sources weren't appearing in the browser. Root cause = **Vite's optimized-deps / module cache going stale** (the errored `?v=9fba674d` matched the cached `browserHash`), because **Vite's file watcher misses bind-mount events on macOS Docker**, so HMR never reloads. Fix: `docker compose exec dev sh -c 'rm -rf node_modules/.vite' && docker compose restart dev`, then a hard browser refresh. Worth turning into a make target (`rebuild-core`) to kill the foot-gun.

---

## 4. S68 — CMS widget admin bugs (specced, not implemented)

**Spec:** [`../sprints/s68-cms-widget-menu-export.md`](../sprints/s68-cms-widget-menu-export.md). Two confirmed defects in the widget admin:

- **Bug A — menu export drops items.** Menu items live in a separate **`cms_menu_item`** table (FK `widget_id`, self-ref `parent_id`), not in `config`/`content_json`. The unified S46 `cms_widgets` exchanger only serializes scalar `public_fields` → exported menu widgets are empty and import is lossy. Fix: a thin `_CmsWidgetsExchanger(BaseModelExchanger)` (the S61 `booking_resources` precedent) that carries `menu_items`, reusing the already-correct `CmsMenuItemRepository.find_tree_by_widget` / `replace_tree`.
- **Bug B — deletion fails.** `cms_layout_widget`, `cms_page_widget`, `cms_post_widget` FK `cms_widget` with **`ondelete="RESTRICT"`**; `delete_widget()` only guards layout assignments (so page/post-assigned widgets → raw FK `IntegrityError` → **500**), and `bulk_delete()` has no guard → 500. Nav widgets are always layout-assigned → never deletable. Fix: complete the in-use check across all three tables (clear 409), add `?force=true` to detach-then-delete in one transaction, harden bulk, and an `IntegrityError` backstop so no path 500s. No schema change.

---

## Net state
- **Implemented & gate-green (not committed):** GHRM software-categories refactor (dual-list + single source of truth + gate fix); S59 GHRM bundle packages (backend + fe-admin + migration, applied locally); the Remove icon-button tweak.
- **Specced only:** S68 (CMS widget export + deletion).
- **Open follow-ups:** S59.1 (live `?q=` repo resolution — needs a new GitHub-App scope); a `rebuild-core` make target for the Vite cache; implement S68.