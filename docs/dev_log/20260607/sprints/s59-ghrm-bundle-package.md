# Sprint 59 — GHRM bundle packages (one plan → many repos)

**Status:** READY — 2026-06-07
**Area:** `plugins/ghrm` (backend) + `vbwd-fe-admin` GHRM admin plugin (`plugins/ghrm-admin`). Plugin code lives on disk / in its own repo ([[feedback_plugins_always_in_own_repos]]).
**Depends on:** S49 (collaborator lifecycle: INVITED/ACTIVE/GRACE/REVOKED, `ghrm_repo_membership`) · S51 (per-package `collaborator_permission`, `allow_extensive_github_permissions`).
**Trigger:** A software tariff plan today binds to exactly **one** GitHub repo (`GhrmSoftwarePackage.github_owner/github_repo`, with `UNIQUE(tariff_plan_id)` and `UNIQUE(owner, repo)`). A **bundle** plan sells access to **many** repos at once — e.g. the *meinchat* bundle grants every repo under [`orgs/VBWD-platform/repositories?q=meinchat`](https://github.com/orgs/VBWD-platform/repositories?q=meinchat). Buying the bundle must make the customer a collaborator on **all** of the bundle's repos. The admin needs a **mode switch** on the Software tab: *Single repo* (today's behaviour) vs *Bundle*.

## Engineering requirements (BINDING)
TDD-first · DevOps-first (schema only via Alembic) · SOLID · Liskov · DI · DRY · clean code · **NO OVERENGINEERING**. Guard: `bin/pre-commit-check.sh --plugin ghrm --full` (backend) + fe-admin Vitest/ESLint green = "done". See [`_engineering_requirements.md`](_engineering_requirements.md). **Core untouched** and **the subscription plugin's plan model is NOT modified** — a bundle is still **one `GhrmSoftwarePackage` bound to one `tariff_plan_id`**; only GHRM's own model/service/UI change.

## Design note — a bundle is ONE package that resolves to MANY repos
The `UNIQUE(tariff_plan_id)` constraint stays: still one package per plan, so the Software tab, the by-plan endpoint, and the grant/revoke entry points are **unchanged in shape**. What changes is *how many repos a package points at*. We introduce a single seam:

```python
# GhrmSoftwarePackage
def repo_targets(self) -> list[tuple[str, str]]:
    """The (owner, repo) pairs a grant must cover. Deduped, order-preserving."""
    if self.package_kind == "bundle":
        return _dedupe((r["owner"], r["repo"]) for r in self.bundle_repos)
    return [(self.github_owner, self.github_repo)]
```

Every grant/revoke loops `repo_targets()` instead of reading `github_owner/github_repo` directly (Open/Closed: single and bundle become the *same* code path with a length of 1 vs N). `github_owner/github_repo` stays **required in both modes** as the package's **representative repo** — the one whose README/CHANGELOG/screenshots/releases drive the catalogue **detail page and sync** (`GhrmSoftwareSync` stays strictly 1:1 per package; **no content aggregation** — out of scope). For a bundle the representative repo is the showcase repo (e.g. the main `meinchat` repo); the granted set is `bundle_repos`.

**Why an admin-curated explicit list, not a live GitHub query (D2).** The GitHub client (`IGithubAppClient`) has **no repo-listing/search method** — adding one needs a new GitHub-App scope (Metadata: Read) + pagination, and a live `?q=` query makes the granted set **drift silently** (a new matching repo would change entitlements with no audit trail, and grants/revokes would diverge from what was sold). MVP stores the resolved repo list **on the package** (deterministic, auditable, no new scope). The admin uses the org `?q=` URL to *find* the repos and curates the list. A live "resolve query → repos" helper is a clearly-scoped **future fast-follow (S59.1)**, see *Out of scope*.

## Locked decisions
| # | Decision |
|---|---|
| **D1** | **Discriminator `package_kind`** on `GhrmSoftwarePackage`: `"single"` (default) \| `"bundle"`. Stored as a string, validated against `ALLOWED_PACKAGE_KINDS = ("single", "bundle")`. Single source of truth reused by validation. |
| **D2** | **Bundle repos are an explicit, admin-curated list** persisted in `bundle_repos` JSON = `[{"owner": str, "repo": str}, …]`. **No** live GitHub query at grant time (see design note). Required non-empty when `kind == "bundle"`; forced to `[]` when `kind == "single"`. |
| **D3** | **`repo_targets()` is the only repo seam.** Grant/revoke loop it. Single → `[(owner, repo)]`; bundle → deduped `bundle_repos`. `github_owner/github_repo` remains required (representative repo for detail/sync) in both modes. |
| **D4** | **Drop `UNIQUE(owner, repo)` (`uq_ghrm_pkg_owner_repo`).** Bundles inherently let a repo appear in more than one package (sold standalone *and* inside a bundle — the core upsell). `UNIQUE(tariff_plan_id)` and `UNIQUE(slug)` stay. |
| **D5** | **Membership stays one row per (user, package)** — the grace timer is per-subscription, so this is unchanged. Add `repo_grants` JSON = `[{"owner","repo","status","invitation_id"}]` recording the **per-repo** invite/grant. Row-level `status`/`invitation_id` remain as the representative-repo rollup (display + back-compat). **Rejected:** one row per (user, repo) — overengineering; we never query "who is on repo X", and it would split the single grace timer. |
| **D6** | **Revoke is repo-aware (no over-revoke).** Because D4 allows overlap, `_tear_down_membership` removes a collaborator from a repo **only if** the user is not still entitled to that same repo via another live (ACTIVE/INVITED/GRACE) membership. A repo still covered by another bundle/package is left intact. Grant is naturally idempotent (`add_collaborator` on an existing collaborator is a no-op upsert). |
| **D7** | **Future-grants-only on bundle edits** (mirrors S51 D2). Changing `bundle_repos` does **not** retroactively add/remove existing collaborators; the new set applies on the next grant (connect / `on_subscription_activated`). Removing a repo from a bundle therefore does **not** auto-revoke current holders — documented limitation; an optional reconcile job is out of scope. |
| **D8** | **Permission (S51) applies per grant uniformly.** Every repo in `repo_targets()` is granted at `resolve_effective_permission(package, allow_extensive)` — one `collaborator_permission` per package, applied to all its repos. The `allow_extensive_github_permissions` clamp is unchanged. |

## Backend (`plugins/ghrm`)

### Model — `src/models/ghrm_software_package.py`
1. Add `package_kind = db.Column(db.String(16), nullable=False, default="single", server_default="single")`.
2. Add `bundle_repos = db.Column(db.JSON, nullable=False, default=list, server_default="[]")`.
3. Add `ALLOWED_PACKAGE_KINDS = ("single", "bundle")` (single source of truth).
4. Add `repo_targets()` (design note) — deduped, order-preserving; a small module-level `_dedupe` helper.
5. `to_dict()` includes `package_kind` and `bundle_repos`.
6. Remove the `uq_ghrm_pkg_owner_repo` composite unique from `__table_args__` (D4).

### Membership — `src/models/ghrm_repo_membership.py`
7. Add `repo_grants = db.Column(db.JSON, nullable=False, default=list, server_default="[]")`; include in `to_dict()`.

### Validation / service — `src/services/software_package_service.py`
8. `validate_package_kind(value) -> str` (default `"single"`; reject anything outside `ALLOWED_PACKAGE_KINDS`).
9. `validate_bundle_repos(value, *, kind) -> list[dict]` — when `kind == "bundle"`: non-empty list, each item a `{"owner","repo"}` with non-blank, trimmed values, deduped; when `kind == "single"`: returns `[]` regardless of input. Reuse the existing `GhrmValidationError`.
10. Create/update accept + validate `package_kind` + `bundle_repos` alongside the existing `collaborator_permission` validation; persist them.

### Grant/revoke — `src/services/github_access_service.py`
11. **`_ensure_collaborator`** — loop `package.repo_targets()`; call `add_collaborator(owner, repo, username, resolve_effective_permission(package, allow_extensive))` per repo; collect a `repo_grants` entry per repo (`status` = active/invited/error, `invitation_id`). Upsert the membership with the new `repo_grants` plus a **rolled-up** row `status` (ACTIVE if all active, else INVITED if any pending, else ERROR) and the representative repo's `invitation_id`. Per-repo `GithubAppClientError` is recorded in that repo's entry + `last_error`, never aborts the loop (best-effort, mirrors today).
12. **`_tear_down_membership`** — loop the membership's `repo_grants` (fallback to `[(pkg.github_owner, pkg.github_repo)]` for legacy rows). For each repo, **skip** if `repo in self._repos_still_entitled(user_id, excluding=membership)` (D6); otherwise `cancel_invitation` (if INVITED + invitation_id) else `remove_collaborator`. Best-effort GitHub-side error handling unchanged.
13. **New helper** `_repos_still_entitled(user_id, *, excluding) -> set[tuple[str,str]]` — union of `repo_targets()` over the user's other memberships in {ACTIVE, INVITED, GRACE}, resolved via `_membership_repo.find_by_user` + each membership's package. Pure read; no GitHub calls.
14. `on_subscription_activated`, `on_subscription_cancelled`, `_grant_entitled`, `revoke_expired_grace_access` are **unchanged in structure** — they still resolve one package per plan and call the two methods above; only the inner repo loop changed.

### Migration — `plugins/ghrm/migrations/versions/20260607_1000_ghrm_bundle.py`
- `revision = "20260607_1000_ghrm_bundle"`, `down_revision = "20260605_1000_ghrm_pkg_perm"` (current head — verify).
- **up:** add `ghrm_software_package.package_kind` (`server_default='single'`), `ghrm_software_package.bundle_repos` (`server_default='[]'`), `ghrm_repo_membership.repo_grants` (`server_default='[]'`); `op.drop_constraint("uq_ghrm_pkg_owner_repo", "ghrm_software_package", type_="unique")`; **backfill** each existing membership's `repo_grants` to `[{owner: pkg.github_owner, repo: pkg.github_repo, status: row.status, invitation_id: row.invitation_id}]` (data migration over the join). All existing packages backfill to `package_kind='single'`, `bundle_repos=[]` via server_default.
- **down:** re-add `uq_ghrm_pkg_owner_repo`; drop the three columns. (Down is only viable if no repo currently appears twice — acceptable for a reversible additive migration; note it.)
- Validate **up → down → up** against a DB with existing rows.

### Routes — `src/routes.py`
15. `admin_create_package`: add `package_kind` + `bundle_repos` to the parsed body; validate via the new helpers; persist. Representative `github_owner/github_repo` stay required in both modes.
16. `admin_update_package`: add `package_kind` and `bundle_repos` to the updatable set, routed through the validators (kind change to `single` clears `bundle_repos`). No taxonomy change — still `ghrm.packages.manage`.

### TDD (tests FIRST — `plugins/ghrm/tests`)
- **Model:** `repo_targets()` — single → one pair; bundle → deduped `bundle_repos`; `to_dict()` carries both new fields. `package_kind` defaults to `single`.
- **Validation:** bundle with empty `bundle_repos` → error; malformed entry (missing owner/repo) → error; duplicate entries deduped; `single` forces `bundle_repos=[]`; bad `package_kind` → error.
- **Grant (unit, mock client):** activating a **bundle** subscription calls `add_collaborator` **once per bundle repo** at the package's permission; membership `repo_grants` records each; rollup status correct (all-active → ACTIVE, mixed → INVITED). A single-mode package still grants exactly its one repo (characterisation — unchanged).
- **Revoke (unit, mock client):** grace-expiry on a bundle removes the user from **each** bundle repo; **D6** — a repo also covered by another active membership is **not** removed; an INVITED repo is `cancel_invitation`-d, an ACTIVE repo is `remove_collaborator`-d.
- **Integration (`db`):** migration up→down→up; existing rows backfill (`package_kind='single'`, `repo_grants` from the join); create/update round-trip persists `package_kind` + `bundle_repos`; `UNIQUE(owner,repo)` is gone (two packages may share a repo); `UNIQUE(tariff_plan_id)`/`UNIQUE(slug)` still enforced.

## fe-admin (GHRM admin plugin — `vbwd-fe-admin/plugins/ghrm-admin`)
Extend `src/components/GhrmSoftwareTab.vue` (props `planId`, `assignedCategories`; today renders name, owner/repo, description, access-level select, author, icon):

1. **Mode switch** — a segmented control / radio bound to `form.package_kind` (`single` | `bundle`), `data-testid="ghrm-package-kind"`, default `single`.
2. **Single mode** (default) — unchanged: the existing **GitHub Owner / GitHub Repo** fields.
3. **Bundle mode** — keep the **representative** Owner/Repo (relabelled e.g. *"Showcase repo (catalogue & sync)"*) **plus** a repeatable **bundle repo list** editor: rows of `{owner, repo}` with add/remove buttons, bound to `form.bundle_repos` (`data-testid="ghrm-bundle-repo-row-{i}"`, `ghrm-bundle-add-repo`). A hint links to the org `?q=` search URL to help the admin find the repos. Client-side: reject empty list / blank rows before save.
4. **Payload** — include `package_kind` and (bundle only) `bundle_repos` in the create/update body; on load, populate both from the fetched package; switching to `single` sends `bundle_repos: []`.
5. **Permission select (S51)** is unchanged and applies to all repos in the bundle — add a one-line hint in bundle mode ("applies to every repo in the bundle").
6. Generic styles via `var(--vbwd-*)`; add i18n keys to all eight `locales/*.json` under `ghrm.softwareTab`:
   `labelMode`, `modeSingle`, `modeBundle`, `labelShowcaseRepo`, `labelBundleRepos`, `addBundleRepo`, `removeBundleRepo`, `bundleReposHint`, `bundleEmptyError`, `permissionBundleHint`.

### TDD (Vitest — extend `tests/unit/GhrmSoftwareTab.*.spec.ts`)
- Mode switch renders and defaults to `single`; single mode shows owner/repo only.
- Switching to `bundle` reveals the repo-list editor; add/remove rows mutate `form.bundle_repos`.
- Create in bundle mode sends `package_kind: "bundle"` + the `bundle_repos` array; editing a bundle package preselects mode and pre-fills the rows.
- Saving an empty bundle is blocked with the error hint; switching back to `single` clears `bundle_repos`.

## Prerequisite / ops note
The GitHub App must be **installed on every repo in a bundle** (same Administration: Read & Write it already needs for single packages) — the App can only manage collaborators on repos under its installation. Document this in `plugins/ghrm/README.md` alongside the bundle section.

## Out of scope (no overengineering)
- **S59.1 (future) — live query resolution:** a `GET …/packages/<id>/resolve-bundle?q=` helper that lists installation repos matching a query to *populate* `bundle_repos`. Needs a new `IGithubAppClient.list_installation_repos()` (Metadata: Read) + the mock. Grants would still use the persisted list (D2).
- **Multi-repo detail page / content aggregation** — bundle detail still renders the representative repo (sync stays 1:1). Optional later: a "this bundle includes N repositories" list on the detail page (read-only, from `bundle_repos`).
- **Retroactive reconcile** on `bundle_repos` change (D7) — no add/remove loop over current collaborators; a scheduled reconcile is a separate sprint.
- No per-repo permission overrides (one `collaborator_permission` per package — D8). No bundle-of-bundles.

## Definition of done
A package can be created/edited as **Single repo** or **Bundle**; a bundle persists an explicit `bundle_repos` list and grants/revokes every repo in it at the package's permission (verified by grant/revoke unit tests with the mock client); overlap is allowed (`UNIQUE(owner,repo)` dropped) and revoke never removes a repo still covered by another live membership (D6); existing single packages are untouched (characterisation green) and backfilled by an up/down/up-validated migration; the Software tab's mode switch + bundle repo-list editor work with the payload changes; `bin/pre-commit-check.sh --plugin ghrm --full` green (modulo the pre-existing, unrelated sync-endpoint integration failures tracked separately) and fe-admin Vitest + full ESLint green. Core + subscription plugin untouched.
