# S63 — GHRM import/export: make the plan link slug-portable

**Plugin:** `ghrm` · **Depends on:** S62 (subscription plans importable by slug) · **Blocks:** S65
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering;
`bin/pre-commit-check.sh --plugin ghrm --full` green = done. See the overview +
`_engineering-requirements.md`.

> **Reconciliation (2026-06-10):** S46 already shipped the `ghrm_packages` exchanger — it
> is **on disk** (`plugins/ghrm/src/services/data_exchange/ghrm_exchangers.py`,
> registered from `GhrmPlugin.on_enable`). So this sprint is **NOT** "build the exchanger";
> it is a **narrow fix** to the one thing that's broken: the link to the subscription plan
> is exported as a **raw UUID** instead of the plan's **slug**, so the extension does not
> survive cross-instance import.

## The extension, and why it's currently not portable
A GHRM "software" plan = a subscription `TarifPlan` (the **base**) extended 1:1 by a
`GhrmSoftwarePackage` (`tariff_plan_id` FK, `UNIQUE`) carrying GitHub `owner`/`repo`/
`collaborator_permission`/`package_kind`/`bundle_repos`. In the unified flow GHRM exposes a
**separate** `ghrm_packages` exchanger (its own `BaseModelExchanger`), registered into the
same core registry as `subscription_plans` — core-agnostic, ghrm only declares
`dependencies=["subscription"]`. That composition is correct.

**The bug:** the exchanger lists `tariff_plan_id` directly in `public_fields`:
```python
public_fields=[ "slug","name","tariff_plan_id", … ]   # raw instance-local UUID
# and there is NO mapping of that FK to the plan's natural key
```
`tariff_plan_id` is the plan's **local UUID**. `subscription_plans` imports by slug and mints
**new** UUIDs on the target, so the package's exported `tariff_plan_id` points at a UUID that
doesn't exist there → the extension re-attaches to nothing (or FK-violates). Everything else
(`ghrm_packages` entity, reused `ghrm.packages.view/manage` perms, secret-stripping of
`sync_api_key`/`github_installation_id`) is already correct.

## Mechanism note (verified — drives the design)
`BaseModelExchanger.fk_natural_key_map` is **export-only**: `_serialise_row` rewrites the FK to
the natural value, but `_import_row` / `_build_instance` write row values **straight onto the
model** with no slug→id resolution. **Therefore a slug-carried FK needs a thin subclass that
resolves on import.** (Same reason cms_posts is a custom subclass for its layout/style slugs.)
This correction also applies to s61/s62/s64 and the overview — the booking/plan/product
category links need the same import-side resolution, not `fk_natural_key_map` alone.

## Scope (the only change)
Turn the existing `ghrm_packages` exchanger into a thin subclass
`_GhrmPackageExchanger(_PermissionMappedModelExchanger)` that round-trips the plan link by slug:

1. **Drop** `tariff_plan_id` from `public_fields`.
2. **Export** — override `_serialise_row` to add `tariff_plan_slug = <slug of pkg.tariff_plan>`
   (look the plan up via the subscription `TarifPlan` model / a `find_by_id`), alongside the
   existing fields. No raw UUID leaves the instance.
3. **Import** — override `_import_row` (or `_build_instance`) to **pop `tariff_plan_slug`,
   resolve it to the local plan id** (`TarifPlan` lookup by slug) and set `tariff_plan_id`
   before writing. If the slug resolves to no plan → append a skip-with-error row (no crash,
   no FK violation) so a GHRM import *after* the S62 plan import succeeds and a stray package
   is reported, not fatal.
4. Keep `natural_key="slug"`, the reused perms, `secret_fields`, and CSV+JSON support exactly
   as they are. Cross-plugin lookup of `TarifPlan` is fine — ghrm already
   `dependencies=["subscription"]` and imports subscription models elsewhere (not a core leak).

## Import ordering
`subscription_plans` (S62) **must** import before `ghrm_packages`. Documented + enforced by the
S65 envelope/section order; a standalone package import whose `tariff_plan_slug` is absent →
error row (per step 3), never a 500.

## TDD test plan (write first — extend `plugins/ghrm/tests/unit/.../test_ghrm_exchangers.py`)
- **Portability round-trip (the core fix):** plan + package → `export()` → the row carries
  `tariff_plan_slug`, **not** `tariff_plan_id` → import into a session where the same-slug plan
  has a **different** UUID → package recreated and linked to the **local** plan id by slug;
  `github_owner/repo`, `collaborator_permission`, `package_kind`, `bundle_repos`, `is_active`
  preserved.
- **Missing plan:** import a package whose `tariff_plan_slug` is absent → one error row, import
  doesn't raise, other rows still applied.
- **Secrets still stripped:** exported row contains neither `sync_api_key` nor
  `github_installation_id`.
- **bundle package:** `package_kind="bundle"` + `bundle_repos=[…]` round-trips verbatim.
- **Upsert** by `slug`; **dry_run** writes nothing.
- **Manifest/perms** unchanged (view→`ghrm.packages.view`, manage→`ghrm.packages.manage`).
- **Regression:** the existing `ghrm_packages` export/import tests stay green (only the plan
  link representation changes).

## fe-admin
No change — `ghrm_packages` already appears in the core `ImportExport.vue` (manifest-driven).

## Acceptance
- `--plugin ghrm --full` green.
- Exporting GHRM packages from one instance and importing them (after the S62 plans) into another
  reproduces the software plans **correctly linked to the local plans**; connecting GitHub then
  grants the right repos.

## Risks / notes
- Cross-instance was silently broken before (raw UUID) — the round-trip test is the guard.
- `GhrmSoftwarePackage` already has a `slug` (its own natural key); only the **plan FK** changes
  representation. No change to grant/sync runtime logic; only the exchanger is touched.
