# S77 — Generic Tags & Custom Fields framework (core BE + fe-admin FE)

**Area:** **core** `vbwd-backend` (framework + port) + `vbwd-fe-admin` (reusable components) + consumers `subscription`/`shop`/`booking` (opt-in) · **Depends on:** core models + data-exchange (exist) · **Part of:** Shopware-parity follow-ups ([report 01](../reports/01-shopware-vs-vbwd-user-product-comparison.md)).
**Engineering requirements:** TDD-first, SOLID/DI/DRY/Liskov, **no overengineering**; core stays agnostic (entities opt in via a port/mixin; core never imports a plugin). Guard: core `--full` + touched `--plugin … --full` + fe-admin Vitest/ESLint green. **Not committed.**

## Problem
"Tagging" and ad-hoc attributes are reinvented per entity via opaque JSONB (`UserDetails.config`, `Product.product_metadata`, plan `features`). Shopware has first-class **tags** and a **custom-fields** framework reusable across entities. vbwd needs the same: a generic, entity-agnostic way to attach **tags** and **typed custom fields** to **users and products** (and, opt-in, plans / booking resources) with admin UI and import/export.

custom fields network shall be abstract for all entities - for tarifs, adoo-on, products, bookings - for any invoice line item

## Locked decisions
| # | Decision |
|---|---|
| **D1 — Polymorphic, slug/key-addressed, core-owned.** | Two small core subsystems keyed by `(entity_type, entity_id)` where `entity_type` is a registered string (e.g. `"user"`, `"shop_product"`). No core→plugin imports; plugins **register** their entity type + opt in. |
| **D2 — Tags.** | `tag` (`vbwd_tag`: slug unique, name, color nullable) + `entity_tag` (`vbwd_entity_tag`: entity_type, entity_id, tag_slug, PK all three). M2M; a tag is reusable across entity types. |
| **D3 — Custom fields.** | `custom_field_def` (`vbwd_custom_field_def`: key unique-per-entity_type, entity_type, label, `type` ∈ {text, number, bool, date, select, multiselect}, `options` JSON for select, `sort_order`, `is_active`) + `custom_field_value` (`vbwd_custom_field_value`: entity_type, entity_id, field_key, value JSON, PK (entity_type, entity_id, field_key)). Values validated against the def's type/options on write. |
| **D3b — No schema change per consumer.** | Adding tags/CF to an entity needs **no migration on that entity's table** — values live in the central tables, addressed by `(entity_type, id)`. |
| **D4 — One narrow core port + a serialization mixin.** | `ITagsAndCustomFields` (resolve from container): `get_tags/set_tags(entity_type, id, slugs)`, `get_custom_fields/set_custom_fields(entity_type, id, {key:value})` (idempotent, validated). A tiny `to_dict()` helper so a consumer's serializer can append `tags: [...]` + `custom_fields: {...}` without importing the models. |

## Scope
**Core backend:**
- Models + repos + `TagService` / `CustomFieldService` (CRUD for defs/tags; get/set values; validation) under `vbwd/models/` + `vbwd/services/`.
- The port `ITagsAndCustomFields` + default impl + `register/resolve_*` (mirror the entitlement-provider registry); an `entity_type` registry so only registered types are accepted.
- Admin routes: tag catalog CRUD + custom-field-def CRUD (gated `settings.manage`); generic value endpoints `GET|PUT /api/v1/admin/<entity_type>/<id>/tags` and `…/custom-fields` (gated by the entity's own manage permission, passed in by the consumer).
- **Data-exchange:** `tags` + `custom_field_defs` exchangers (json+csv); entity exports may include `tags`/`custom_fields` (opt-in extension of the entity's exchanger).

**fe-admin (reusable components):**
- `vue/src/components/TagPicker.vue` (create/select tags, chips) and `vue/src/components/CustomFieldsEditor.vue` (renders inputs from field defs by type). Both bind to the generic value endpoints.
- A **catalog manager** page (under Settings) to manage the tag catalog + custom-field definitions per entity type.
- **Wire into consumers:** a **Tags** + **Custom fields** block on `UserEdit.vue` (entity_type `user`) and `ProductForm.vue` (entity_type `shop_product`); leave plan/resource opt-in for later.
- i18n keys (all locales).

## TDD
- **Core:** tag CRUD + attach/detach by `(entity_type,id)` idempotent; custom-field def CRUD; value set/get validated against type/options (bad value/type → error; unknown entity_type rejected); tags/CF exchangers json+csv round-trip; deleting a tag/def cascades its rows.
- **fe-admin (Vitest):** `TagPicker` adds/removes tags and saves; `CustomFieldsEditor` renders per-type inputs from defs and saves values; the catalog manager CRUD; User edit + Product form show and persist tags + custom fields.

## Definition of done
A generic, core-owned tags + custom-fields framework keyed by `(entity_type, entity_id)` exists with admin catalog management, reusable `TagPicker`/`CustomFieldsEditor` components wired into the **user** and **product** edit pages, json/csv import/export, and a narrow port so consumers opt in without core importing plugins and without per-entity migrations; core `--full` + touched plugins `--full` + fe-admin Vitest/ESLint green. Not committed ([[feedback_no_commit_without_ask]]).
