# S61 — Booking → unified import/export

**Plugin:** `booking` · **Depends on:** core data-exchange framework (exists) · **Blocks:** S65
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, no overengineering;
`bin/pre-commit-check.sh --plugin booking --full` green = done. See `_unified-import-export-overview.md`
and `docs/dev_log/20260526/sprints/_engineering-requirements.md`.

> **Reconciliation (2026-06-10, verified):** S46 shipped only the `bookings` (reservations)
> exchanger for this plugin — the catalog (`BookableResourceCategory`, `BookableResource`) is
> **genuinely absent**. So s61 is the **one true greenfield** of the set (not a duplicate of S46).
> ⚠️ `BaseModelExchanger.fk_natural_key_map` is **export-only** (no slug→id resolution on import) —
> so **every** link below (resource↔category M2M *and* the category self-referential `parent`)
> needs a **thin subclass** that resolves the slug on import, not `fk_natural_key_map` alone.

## Problem
Booking registers only the `bookings` (reservations) exchanger. The **catalog** —
`BookableResourceCategory` and `BookableResource` — is **not** in the unified framework. The only
catalog import today is the bespoke `POST /api/v1/admin/booking/import/<entity>` + `ImportService`,
which **drops `availability` and the category link** for resources (sets `availability={}`, no
category) → imported resources are uncategorised and unbookable. This is why "upload via the UI"
can't build a working catalogue.

## Goal
Add unified exchangers for booking **categories** and **resources** (export + import, JSON), with
the resource↔category many-to-many carried by **category slug**, so the catalogue imports correctly
through the core unified Import/Export UI. Retire the lossy bespoke import path.

## Scope / exchangers
New file `plugins/booking/booking/services/data_exchange/booking_exchangers.py` (extend the
existing one): add to `build_booking_exchangers(session)`:

1. **`booking_categories`** (`BookableResourceCategory`) — plain `BaseModelExchanger` **if** the
   demo uses flat categories; a **thin subclass if `parent_id` is used** (self-referential):
   - `cluster=CLUSTER_SALES`, `natural_key="slug"`, label "Booking Categories".
   - `public_fields=[name, slug, description, image_url, config, sort_order, is_active]`.
   - **`parent_id` (self-reference):** `fk_natural_key_map={"parent_id": <parent slug>}` only
     covers EXPORT. To import a hierarchy, the subclass must resolve the parent slug → local id on
     row-apply (skip-with-error if the parent slug is unknown / not yet imported). If the demo
     categories are flat (no parents), keep it a plain exchanger and drop `parent_id` — simplest.
   - perms: `booking.manage` / `booking.view` (reuse the booking admin perms).
2. **`booking_resources`** (`BookableResource`) — **thin subclass** of `BaseModelExchanger`
   (M2M categories need custom shaping):
   - `natural_key="slug"`, label "Booking Resources", `cluster=CLUSTER_SALES`.
   - `public_fields=[name, slug, description, capacity, slot_duration_minutes, price, currency,
     price_unit, availability, custom_fields_schema, image_url, config, is_active, sort_order]`
     (`availability` is a JSON column → round-trips verbatim).
   - **Override `_serialise_row`** to add `category_slugs: [slug,…]` from the resource's
     `categories` M2M; **override the row-apply** to resolve `category_slugs` → category ids
     (skip-with-error if a slug is unknown, never crash). `custom_schema_id` is exported as the
     schema's natural key if schemas are in scope, else omitted (out of scope this sprint — note it).
   - `Decimal` price serialised as string (mirror the model's `to_dict`).

`register_booking_exchangers(session)` already exists — just register the two new ones too
(idempotent replace-by-key). It is already called from `BookingPlugin._register_data_exchangers()`.

## Retire the lossy path
- Remove the bespoke `ImportService.import_categories/import_resources` import behaviour and the
  `POST /api/v1/admin/booking/import/<entity>` route (keep `export/<entity>` if still used by reports,
  or migrate it too — decide in TDD). Remove the **Import** button in fe-admin
  `plugins/booking/.../views/ResourceList.vue` (the unified Import/Export view replaces it).
  Update/retire `ImportService` unit tests accordingly.

## TDD test plan (write first — `plugins/booking/tests/unit/.../test_booking_catalog_exchangers.py`)
- **Round-trip**: create category + resource (resource in the category) → `export()` → `import_()`
  into a clean session → category + resource recreated, resource linked to the category **by slug**,
  `availability` + `price` + `price_unit` preserved byte-for-byte.
- **FK by slug**: export a resource, change the category id (simulate another instance), import →
  resolves the category by slug, not id.
- **Upsert**: re-import the same envelope → `updated` (not duplicated) by slug.
- **Missing referent**: import a resource whose `category_slugs` includes an unknown slug → row
  recorded as error in `ImportResult.errors`, import does not raise, other rows still applied.
- **dry_run=True** → no DB writes, `ImportResult` reports would-be created/updated.
- **Hierarchy**: category with `parent_id` exports the parent slug, imports resolved.
- **Manifest/perms**: with `booking.view`/`booking.manage`, the two entities appear in
  `manifest_for(user)`; without, they don't.
- **Envelope validity**: `validate_envelope` accepts the produced JSON for each entity_key.

## fe-admin
- Confirm `booking_categories` + `booking_resources` appear in the core `ImportExport.vue`
  (manifest-driven) under the Sales cluster; no new view. Remove the ResourceList Import button.
- Light e2e (optional, if the booking-admin e2e suite is green locally): unified view lists the two
  entities.

## Acceptance
- `--plugin booking --full` green (unit + integration + lint).
- Export of a seeded catalogue → import into an empty DB reproduces categories + resources with
  links + availability; the public `/api/v1/booking/resources` then renders them in the catalogue.
- The bespoke lossy import is gone; the unified UI is the single catalogue import path.

## Risks / notes
- M2M categories + `availability` JSON are the only non-trivial bits — covered by the subclass +
  the round-trip test. `custom_schema_id` (custom field schemas) deferred; note it if any seed
  resource uses one. Keep `Booking` (reservations) exchanger untouched.
