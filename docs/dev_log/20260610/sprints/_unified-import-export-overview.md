# Unified Import/Export — plugin onboarding (overview + shared design)

**Date:** 2026-06-10
**Goal:** Make the **booking**, **subscription**, **ghrm**, and **shop** plugins expose their
catalog models through **core's unified data-exchange framework** — the same registry,
the same generic admin routes, and the **same core Vue Import/Export components** that CMS and
core (payment methods, currencies) already use. After this, tarif plans + their categories +
add-ons, GHRM-extended software plans, booking resources + their categories, and shop products +
their categories all import/export through **one UI**, in one envelope format, with FK links
carried by **natural key (slug)** so data is portable across instances.

These sprints are **planning artifacts**. No code is written until the user approves.

---

## Binding engineering requirements (restated — apply to every sprint below)
TDD-first · DevOps-first · SOLID · DI · DRY · **Liskov** · clean code · **NO OVERENGINEERING**
(narrowest change that satisfies the requirement). **`bin/pre-commit-check.sh` is the quality
gate** — `--plugin <name> --full` must be green on every touched plugin = "done"; `--quick`
while iterating. Canonical statement: `docs/dev_log/20260526/sprints/_engineering-requirements.md`.
Use the **vbwd-tdd** subagent for the implementation (write the failing test first, narrowest
green, run the gate, never commit). Core stays agnostic — plugins inject into core's registry;
core is never modified for a plugin.

## The core framework these sprints build on (do NOT change core)
- `vbwd/services/data_exchange/port.py` — `EntityExchanger` (ABC): `entity_key`, `label`,
  `cluster`, `natural_key`, `supports_export/import`, `supported_formats`, `secret_fields`,
  `pii_fields`; abstract `export(selector, include_pii)→Envelope`, `import_(payload, mode, dry_run)→ImportResult`,
  `export_zip(...)`. Clusters: `CLUSTER_SALES`, `CLUSTER_SETTINGS`.
- `vbwd/services/data_exchange/base_model_exchanger.py` — `BaseModelExchanger(entity_key, label,
  cluster, natural_key, model_class, repository, session, public_fields, pii_fields=…,
  fk_natural_key_map=…, row_cap=…)`. Generic single-model upsert-by-natural-key; export honours
  the selector + row cap.
  - ⚠️ **`fk_natural_key_map` is EXPORT-ONLY** (verified in code): `_serialise_row` rewrites a FK
    column to the referent's natural key, but `_import_row` / `_build_instance` write the row
    values **straight onto the model** — there is **no slug→id resolution on import**. So writing
    a FK as a slug needs a **thin subclass** that, on import, resolves the slug back to the local
    id before persisting (skip-with-error if the referent is absent). This is exactly why the CMS
    post/term exchangers are custom subclasses. **Every FK/M2M-by-slug below — booking
    resource↔category + category parent, plan↔category, addon↔plan, product↔category, ghrm
    package→plan — therefore requires a subclass, not `fk_natural_key_map` alone.**
- `vbwd/services/data_exchange/registry.py` — `data_exchange_registry.register(exchanger)`;
  `manifest_for(user, enabled_entities)` → perm- and config-filtered, clustered list.
- `vbwd/routes/admin/data_exchange.py` — generic `/api/v1/admin/data-exchange/{manifest,
  export/<key>, import/<key>}`; resolves the exchanger by `entity_key`, never names a plugin.
- **fe-admin**: the core `ImportExport.vue` view is **manifest-driven** — any registered entity
  the user may export/import **appears automatically**. So "use the same Vue components" is
  satisfied by **backend registration alone**; no per-plugin import view is built. Each sprint's
  fe-admin task is limited to: confirm the entity shows in the unified view, and remove/retire any
  bespoke per-plugin import UI it replaces.

## Established pattern to replicate (reference: `plugins/cms/.../data_exchange/cms_exchangers.py`)
1. `plugins/<p>/.../services/data_exchange/<p>_exchangers.py`:
   - `build_<p>_exchangers(session) -> List[EntityExchanger]` — constructs the exchangers.
   - `register_<p>_exchangers(session) -> None` — `for e in build_…: data_exchange_registry.register(e)`.
2. Call `register_<p>_exchangers(db.session)` from the plugin's `on_enable` →
   `_register_data_exchangers()` (booking + cms already have this hook; subscription/ghrm/shop add it).
3. Only a **link-free** entity (no FK/M2M to carry by slug) can be a plain `BaseModelExchanger`.
   **Any entity that references another by slug** — a self-referential `parent`, a single FK, an
   M2M, or nested 1:M children — needs a **thin subclass** that overrides row serialise (export the
   referent slug) **and** the row-apply/build (resolve slug→id on import). Model the override on the
   CMS post/term exchangers. (See the `fk_natural_key_map`-is-export-only note above.)

## Import ordering (cross-entity dependency — documented per sprint, enforced in the data sprint)
Parents/referents must import before children. Global order for a full instance import:
`tarif_plan_categories → tarif_plans → addons → ghrm_software_packages` (ghrm extends a plan by
slug) ; `booking_categories → booking_resources` ; `shop_product_categories → shop_products`.
The unified ZIP import already imports in a deterministic, dependency-aware section order; each
exchanger must tolerate a missing referent (skip-with-error row, never crash — Liskov).

## Reconciliation with S46 (what already exists on disk — 2026-06-10)
S46 already shipped most of these exchangers; **these sprints are gap-fills, not greenfield.**
Current registered entity keys (verified):

| Plugin | Already on disk (S46) | Gap these sprints fill |
|---|---|---|
| cms | posts, terms, images, layouts, styles, widgets | — complete |
| core | currencies, payment_methods | — |
| discount | discount_rules, discount_coupons | — complete (demo coupons already exchangeable) |
| **ghrm** | **`ghrm_packages`** (entity, perms, secret-stripping) | plan link is a **raw UUID** → make it slug-portable (s63) |
| **subscription** | **`subscription_plans`, `subscription_addons`** (no slug-carried links) | **add `subscription_categories`** + slug-link plan↔category / addon↔plan (s62) |
| **shop** | **`shop_products`** (no category link) | **add `shop_product_categories`** + slug-link product↔category (s64) |
| **booking** | **`bookings` (reservations) only** | **add `booking_categories` + `booking_resources`** — the whole catalog (s61) |

So booking is the only true greenfield; the rest add a missing **category** exchanger and/or fix a
**link** to travel by slug (each via the export-only-`fk_natural_key_map` subclass pattern above).

## Sprint set (write order — corrected scope)
- **s61** — booking: **new** `booking_categories` + `booking_resources` (full catalog; replaces the
  bespoke `/admin/booking/import`). The one genuinely-new exchanger pair.
- **s62** — subscription: **add `subscription_categories`**; make the **existing** `subscription_plans`
  carry `category_slugs` and `subscription_addons` carry `tarif_plan_slugs` (subclass on import).
- **s63** — ghrm: **fix only** — `ghrm_packages` exists; change the plan link from raw
  `tariff_plan_id` UUID to a slug-resolved `tariff_plan_slug`.
- **s64** — shop: **add `shop_product_categories`**; make the **existing** `shop_products` carry the
  category by slug (subclass on import); optional nested variants/images.
- **s65** — prod demo-data import (depends on s61–s64 deployed): author per-vertical JSON
  envelopes, deploy, import via the unified UI, configure discounts/coupons + Stripe, and produce
  the Playwright checkout walkthrough report.
