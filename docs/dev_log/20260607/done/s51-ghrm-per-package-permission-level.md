# Sprint 51 — GHRM per-package GitHub permission level

**Status:** READY — 2026-06-05
**Area:** `plugins/ghrm` (backend) + `vbwd-fe-admin` GHRM admin plugin. Plugin code lives on disk / in its own repo ([[feedback_plugins_always_in_own_repos]]).
**Depends on:** S49 (collaborator lifecycle, the `pull` default). **Trigger:** the granted GitHub permission is a single hard-coded constant; admins need it configurable **per package** so different tariff plans grant different access (e.g. basic → read, pro → read & write).

## Engineering requirements (BINDING)
TDD-first · DevOps-first (schema only via Alembic) · SOLID · Liskov · DI · DRY · clean code · **NO OVERENGINEERING**. Guard: `bin/pre-commit-check.sh --plugin ghrm --full` (backend) + fe-admin Vitest/ESLint green = "done". See [`_engineering_requirements.md`](_engineering_requirements.md). **Core untouched** — all changes are in the ghrm plugin + the fe-admin ghrm plugin; the subscription plugin's plan model is NOT modified (agnostic boundary — see design note).

## Design note — why the permission lives on the PACKAGE, not the plan
The natural phrasing is "the plan's config decides the permission," but tariff plans live in the **subscription plugin** (core stays agnostic; GHRM merely depends on it). GHRM must not add fields to another plugin's model. `GhrmSoftwarePackage` already carries `tariff_plan_id` (the 1:1 plan binding) — so it **is** GHRM's per-plan entity. The permission policy belongs there. From the admin's view this is still "per plan": editing the package bound to the Basic plan sets read; the package bound to Pro sets write.

## Locked decisions
| # | Decision |
|---|---|
| **D1** | **Full GitHub permission set** exposed: Read=`pull`, Triage=`triage`, Write=`push`, Maintain=`maintain`, Admin=`admin`. Stored as the raw GitHub permission **string** (extensible; validated against the allowed set). Default = `pull` (least privilege). |
| **D2** | **Future-grants-only.** Changing a package's level does NOT re-sync existing collaborators; the new level applies on the next grant (connect / `on_subscription_activated` / renew). No re-PUT loop over current memberships (lower blast radius, no overengineering). |
| **D3** *(security guardrail, 2026-06-05)* | **Write+ access is gated behind a plugin config flag `allow_extensive_github_permissions` (default `false`).** When OFF, only `pull` (Read) is permitted — so no admin can grant write by mistake. Enforced at THREE layers (the backend is authoritative; the UI is convenience): **(1) Validation** — create/update rejects any value other than `pull` with a clear 400 when the flag is off. **(2) Grant clamp** — `_ensure_collaborator` grants `pull` regardless of the stored value when the flag is off (covers a value stored while the flag was on, then turned off). **(3) UI** — fe-admin shows only Read (others disabled/hidden with a hint) when the flag is off. The flag is a boolean in `config.json` + a toggle in `admin-config.json` (labelled with a security warning), and is exposed so fe-admin can read it. |

## Backend (`plugins/ghrm`)
1. **Model** — add `collaborator_permission = db.Column(db.String(16), nullable=False, default="pull")` to `GhrmSoftwarePackage` (`src/models/ghrm_software_package.py`); include it in `to_dict()`.
2. **Allowed values** — a single source of truth (e.g. `ALLOWED_COLLABORATOR_PERMISSIONS = ("pull", "triage", "push", "maintain", "admin")`) reused by validation. Anything else → validation error on create/update.
3. **Migration** — `plugins/ghrm/migrations/versions/<=32char>_pkg_collaborator_permission.py`, ADDITIVE: add the column with `server_default='pull'` so existing rows backfill to read; down drops it. down_revision = the current ghrm head (`20260604_1000_ghrm_drop_token`). Validate up/down/up. Register path already in alembic.ini (verify).
4. **Service / routes** — `software_package_service` create/update accept + validate `collaborator_permission` (default `pull` when omitted); persist it. Admin package routes already gate on `ghrm.packages.manage` (S49.4) — no taxonomy change.
5. **Grant uses it** — `github_access_service._ensure_collaborator` (already has `pkg` in scope, line ~282) passes `pkg.collaborator_permission or DEFAULT_COLLABORATOR_PERMISSION` instead of the bare constant. Keep `DEFAULT_COLLABORATOR_PERMISSION = "pull"` as the fallback for null.

### TDD (tests FIRST)
- **Unit (model/service):** valid permission persists; invalid value (e.g. `"owner"`) → validation error; omitted → defaults to `pull`. `to_dict()` includes `collaborator_permission`.
- **Unit (grant):** tighten the S49 guard — `_ensure_collaborator` sends `pkg.collaborator_permission` to `add_collaborator` (e.g. a `push` package → grant `push`; a package with no value → `pull`). This supersedes the fixed-`pull` assertion.
- **Integration (`db`):** migration up→down→up; existing rows backfill to `pull`; CRUD round-trip persists the chosen level.

## fe-admin (GHRM admin plugin — `vbwd-fe-admin/plugins/ghrm-admin`)
- Package create/edit form: add a **"GitHub Access Level"** `<select>` bound to `collaborator_permission` with the five options (label → value): Read → `pull`, Triage → `triage`, Write → `push`, Maintain → `maintain`, Admin → `admin`. Default Read. Send it in the create/update payload; populate from the package on edit.
- (Optional, low cost) show the level as a column/badge in the packages list.
- Generic styles via `var(--vbwd-*)`.

### TDD (Vitest)
- The select renders the five options; editing a package preselects its current level; saving sends `collaborator_permission` in the payload; default is `pull` on create.

## Out of scope (no overengineering)
- No re-sync of existing collaborators on change (D2). No UI to bulk-change levels. No per-user override (level is per package/plan only).

## Definition of done
A package's GitHub access level is admin-configurable across the full GitHub set (default Read); new grants use the package's level (verified by the grant guard test); existing collaborators are untouched on change (D2); migration up/down/up validated with existing rows backfilled to `pull`; `--plugin ghrm --full` green (modulo the pre-existing, unrelated sync-endpoint integration failures tracked separately); fe-admin Vitest + full ESLint green. Core + subscription plugin untouched.
