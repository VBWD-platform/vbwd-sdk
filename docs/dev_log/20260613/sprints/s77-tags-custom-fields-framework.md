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
| **D2 — Tags.** | `tag` (`vbwd_tag`: `slug` **globally unique**, `name`, `parent_entity_type` **nullable**, `meta_data` JSON, `color` nullable) + `entity_tag` (`vbwd_entity_tag`: entity_type, entity_id, tag_slug, PK all three; `tag_slug` FK → `vbwd_tag.slug` `ON DELETE CASCADE`). M2M. `parent_entity_type` scopes where a tag may be applied: **NULL = global** (any entity type), non-null = that type only. The `TagPicker` on an entity edit page offers tags where `parent_entity_type IS NULL OR = <entity_type>`. **Usage stats:** `tags_repo.get_stats(slug) -> int` = `COUNT(*)` of `entity_tag` rows for that slug (any entity that references it); the catalog list uses `get_stats_bulk(slugs) -> {slug:int}` (one grouped query, served by the D6 reverse index — never N+1). |
| **D3 — Custom fields.** | `custom_field_def` (`vbwd_custom_field_def`: key unique-per-entity_type, entity_type, label, `type` ∈ {text, number, bool, date, select, multiselect}, `options` JSON for select, `sort_order`, `is_active`) + `custom_field_value` (`vbwd_custom_field_value`: entity_type, entity_id, field_key, value JSON, PK (entity_type, entity_id, field_key)). Values validated against the def's type/options on write. |
| **D3b — No schema change per consumer.** | Adding tags/CF to an entity needs **no migration on that entity's table** — values live in the central tables, addressed by `(entity_type, id)`. |
| **D4 — One narrow core port + a serialization mixin.** | `ITagsAndCustomFields` (resolve from container): `get_tags/set_tags(entity_type, id, slugs)`, `get_custom_fields/set_custom_fields(entity_type, id, {key:value})` (idempotent, validated). A tiny `to_dict()` helper so a consumer's serializer can append `tags: [...]` + `custom_fields: {...}` without importing the models. |
| **D5 — This is EAV; only the point-lookup path is in scope.** | The `(entity_type, entity_id, field_key)→value` layout is Entity-Attribute-Value (WordPress `wp_postmeta`, Magento `catalog_product_entity_*`, spatie `taggables`). EAV is cheap for *"give me the tags/fields of THIS entity (by id)"* and dangerous for *"find all entities WHERE cf=X / tagged A AND B, sorted, paged"*. The port exposes **only the by-id path** (+ a batch variant). Catalog **filtering/faceting by CF or tag is explicitly out of scope** and must NOT be served by ad-hoc joins on these tables — it goes through a denormalized read projection / search index (see §Scaling). |
| **D6 — Batch reads are first-class; no per-row N+1.** | Listing 100 products must not fire 100 value queries. The port ships bulk variants (`get_custom_fields_bulk`, `get_tags_bulk`) returning `{id: …}`; serializers/exchangers use them. Field defs + tag catalog are small, hot, and cached per `entity_type`. Bulk import (data-exchange of N rows) uses set-based `INSERT … ON CONFLICT`, never per-row service calls. |
| **D7 — Tags become core; categories stay plugin-owned.** | "Tag" = a generic, cross-entity label → **core** owns the single catalog (`vbwd_tag`). "Category" = a structural/navigational, often hierarchical, SEO-bearing domain concept → **stays in each plugin**, untouched. **Audit (2026-06-13):** the *only* existing tag implementation is **CMS** (`cms_term` rows with `term_type='tag'`, linked via `cms_post_term`); shop / booking / subscription / ghrm expose **categories only** (kept as-is). So "rewire tags across all modules" reduces to **one** consumer (CMS) plus the two ingestion paths that write tags (content-ingest, wp-import). Migration = **reimport old tags into the core tables, then drop the old tag rows** (categories in `cms_term` are left intact). |

## Interface & registry spec (D1/D4/D5/D6)

Modeled on the existing core seams: `vbwd/services/entitlement.py` (port + register/resolve), `vbwd/services/deletion_dependency_registry.py` / `invoice_extra_fields_registry.py` (registry), CMS `term_type_registry.py` (dataclass registration). Two pieces with different lifetimes.

**(a) Entity-type registry** — `vbwd/services/entity_type_registry.py`. Global register/resolve; plugins register their type strings on enable, unregister on disable. An unregistered `(entity_type, id)` is rejected, so a disabled plugin's type stops being addressable and core hard-codes no plugin domain.

```python
@dataclass(frozen=True)
class EntityTypeRegistration:
    entity_type: str            # polymorphic key, e.g. "shop_product"
    label: str                  # human label for the admin catalog UI
    manage_permission: str      # permission the value endpoints enforce on write

register_entity_type(reg) / unregister_entity_type(entity_type) / clear_entity_types()
is_registered(entity_type) -> bool
get_entity_type(entity_type) -> EntityTypeRegistration | None
list_entity_types() -> list[EntityTypeRegistration]   # drives the catalog type picker
```

Core registers `user` at startup; e.g. shop in `on_enable`: `register_entity_type(EntityTypeRegistration("shop_product", "Product", "shop.manage"))`, undone in `on_disable`.

**(b) Port `ITagsAndCustomFields`** — `vbwd/services/tags_and_custom_fields.py`. Resolved from the DI container (`container.tags_and_custom_fields()`). **Core owns the tables, so the default impl IS the production impl** — there is no no-op fallback (unlike entitlement). Only the by-id (point-lookup) and by-id-batch paths exist (D5/D6).

```python
class UnknownEntityTypeError(ValueError): ...
class UnknownCustomFieldError(ValueError): ...
class CustomFieldValidationError(ValueError): ...

class ITagsAndCustomFields(ABC):
    # tags (free-form slugs, reusable across entity types)
    def get_tags(self, entity_type: str, entity_id: UUID) -> list[str]: ...
    def get_tags_bulk(self, entity_type: str, ids: list[UUID]) -> dict[UUID, list[str]]: ...   # D6
    def set_tags(self, entity_type: str, entity_id: UUID, slugs: list[str]) -> None: ...        # REPLACE full set; idempotent; unknown slugs auto-created

    # custom fields (typed, defined per entity type)
    def get_field_defs(self, entity_type: str) -> list[dict]: ...                               # the schema: [{key,label,type,options,sort_order}], cached
    def get_custom_fields(self, entity_type: str, entity_id: UUID) -> dict[str, Any]: ...
    def get_custom_fields_bulk(self, entity_type: str, ids: list[UUID]) -> dict[UUID, dict]: ... # D6
    def set_custom_fields(self, entity_type: str, entity_id: UUID, values: dict[str, Any]) -> None: ...  # UPSERT given keys (partial); None clears; validated vs def type/options

    def list_applicable_tags(self, entity_type: str) -> list[dict]: ...   # catalog rows where parent_entity_type IS NULL OR = entity_type — drives the TagPicker
```

`TagService` additionally exposes catalog stats for the admin list (not on the hot per-entity port): `get_stats(slug) -> int` and `get_stats_bulk(slugs) -> {slug:int}` (one grouped `COUNT` over `entity_tag`, via the D6 reverse index).

`set_tags` is **full-replace** (PUT of the chip set); `set_custom_fields` is **partial upsert** (a form submits only the fields it knows; `None`=clear). `register_tags_and_custom_fields` / `clear_tags_and_custom_fields` / `resolve_tags_and_custom_fields` mirror entitlement; container: `tags_and_custom_fields = providers.Singleton(resolve_tags_and_custom_fields)`.

**(c) Serialization helper** (D4 graft, no model import by the consumer):

```python
def append_tags_and_custom_fields(data: dict, entity_type: str, entity_id: UUID) -> dict:
    port = resolve_tags_and_custom_fields()
    data["tags"] = port.get_tags(entity_type, entity_id)
    data["custom_fields"] = port.get_custom_fields(entity_type, entity_id)
    return data
# list serializers MUST use the *_bulk variants instead (D6).
```

`CustomFieldService` / `TagService` (def + catalog CRUD, validation) sit *behind* the default impl; the port is only the value-access seam.

## Scaling analysis — 1M products / resources (what other platforms taught us)

**The pattern is EAV, and EAV's failure mode is well-documented.** Booking *resources* (rooms/staff/equipment) are O(10²–10⁴) — not a scale concern. The scale target is **products** at ~1M SKUs, each potentially with 10–50 custom fields + several tags → `vbwd_custom_field_value` at **10M–50M rows**, `vbwd_entity_tag` at single-digit millions. Prior art:

- **WordPress `wp_postmeta`** `(post_id, meta_key, meta_value LONGTEXT)` — identical shape. Point reads by `post_id` are fine; the killer is `meta_query` (filter/sort by `meta_value`): `meta_value` is unindexable text, multi-condition queries self-JOIN postmeta once per condition → near-quadratic. WooCommerce's answer at scale was **denormalized lookup tables** (`wc_product_meta_lookup`) and **HPOS** (move orders off postmeta into dedicated typed tables).
- **Magento EAV** splits values by type (`*_varchar/int/decimal/text/datetime`) so a column *can* be indexed — but reads need many joins, so Magento serves the storefront from **flat/indexed projections** + **Elasticsearch**, never raw EAV.
- **Laravel spatie `taggables`** = our `entity_tag` exactly. Fine for "tags of this model"; "all models with tag X" across millions needs the reverse composite index and still benefits from a read projection.
- **Amazon-scale catalogs** don't relational-EAV the storefront at all: source-of-truth is a document store, **all attribute/facet filtering is an inverted index** (search service), SQL is never on the hot filter path.

**Consensus lesson → exactly D5:** keep EAV as the *system of record* and for *by-id* access; **never** serve catalog filtering/faceting from it. Our spec already enforces this by only exposing by-id methods.

**Optimizations baked into this sprint (cheap, do now):**
1. **Indexes that match the only two access paths.** `custom_field_value` PK `(entity_type, entity_id, field_key)` already serves "fields of this entity" + point reads. `entity_tag` PK `(entity_type, entity_id, tag_slug)` serves "tags of this entity"; add the **reverse** index `(tag_slug, entity_type, entity_id)` so "entities with tag X" (admin tooling/export) is an index range, not a scan.
2. **Bulk methods (D6)** — the single highest-value item. The natural list serializer is an N+1 trap; `*_bulk` collapse a page of 100 into one `WHERE entity_id = ANY(:ids)` query.
3. **Cache defs + tag catalog** per `entity_type` — small, hot, read on every validate/serialize; invalidate on def/tag CRUD. Avoids a def lookup per write.
4. **Set-based import** — data-exchange of 1M rows uses `INSERT … ON CONFLICT DO UPDATE` (or `COPY` to a staging table), never `set_custom_fields` per row. Defs validated once up front, not per row.

**Deferred until a consumer actually needs catalog filtering (out of scope here, flagged so it isn't reinvented as a postmeta-style JOIN):**
5. **Read projection for faceting** — when product listing must filter/sort by CF/tag, build a denormalized projection (a per-entity-type wide/lookup table refreshed on write, or push to Postgres GIN/FTS, Meilisearch, or Elasticsearch). EAV stays source-of-truth; the projection serves reads. This is the WooCommerce-lookup / Magento-flat / Amazon-search move.
6. **Partition `custom_field_value` by `entity_type`** (Postgres declarative partitioning) once one type dominates row count, so a hot type's autovacuum/scans don't drag the others.
7. **Batched cascade deletes** — deleting a def/tag that owns millions of value/link rows is a long-locking `DELETE`; do it in chunks (or detach-then-drop a partition) rather than one statement.

**Net:** as specified, the framework scales to 1M SKUs on the **by-id read/write and import** paths (point lookups on a covering PK + bulk + set-based import). It deliberately does **not** attempt cross-catalog filtering — that's a documented boundary (D5), to be served later by a read projection, exactly as WooCommerce/Magento/Amazon converged on.

## Entity wiring — every edit page, card, and invoice

Tags + CF are **core**, so *every* entity opts in through the same three steps — no per-entity bespoke code, no core→plugin import:

1. **Register the type** (plugin `on_enable`, core for `user`): `register_entity_type(EntityTypeRegistration(<entity_type>, <label>, <manage_permission>))`.
2. **Serialize** — the entity's existing serializer appends tags/CF via the D4 helper (`append_tags_and_custom_fields`) for a single record, or the `*_bulk` variants for lists (D6). No new column, no model import.
3. **Render** — admin **edit page** mounts the two editors; public **card/detail** mounts the two read-only display components.

**Coverage matrix** (entity_type slug · admin edit page gets editors · public card/detail gets read-only display):

| Entity | `entity_type` | Owner | Edit page (editors) | Card / detail (read-only) |
|---|---|---|---|---|
| User | `user` | core | `UserEdit.vue` | profile/admin detail |
| Shop product | `shop_product` | shop | `ProductForm.vue` | product page + product card |
| Tarif plan | `tarif_plan` | subscription | `PlanForm.vue` | **tarif card** |
| Add-on | `addon` | subscription | addon edit | **add-on card** |
| Booking resource | `booking_resource` | booking | resource edit | resource detail |
| GHRM software package | `ghrm_software_package` | ghrm | package edit | package card |
| CMS page | `cms_page` | cms | page edit | page render |
| CMS post | `cms_post` | cms | post edit | post render |
| **Invoice line item** | `invoice_line_item` | core (invoice) | invoice line detail (admin) | invoice line render |

**Two reusable component pairs** (built once, used everywhere):
- **Editors** (fe-admin, bind to the generic `GET|PUT …/<entity_type>/<id>/{tags,custom-fields}` endpoints): `TagPicker.vue` + `CustomFieldsEditor.vue`. Each edit page passes only its `entity_type` and `manage_permission`; the components fetch applicable tags (`list_applicable_tags`) + field defs (`get_field_defs`) and render generically. Each edit page therefore gains a **"Tags"** block + a **"Custom fields"** block with **zero** entity-specific logic.
- **Read-only display** (live in **`vbwd-fe-core`** so cards in fe-user *and* fe-admin share them — per the fe-core design-system rule): `TagChips.vue` (renders `tags[]` as chips) + `CustomFieldsDisplay.vue` (renders `custom_fields{}` as a labelled spec list, formatted by the def's `type`). Cards/detail pages just read the `tags`/`custom_fields` keys already on the serialized payload — no extra fetch.

**Invoices — snapshot, do NOT live-join.** An invoice is a historical document; a product's CF/tags may change after billing. So `invoice_line_item` is its **own** registered entity type: at line-item creation the issuer **copies** the source item's tags/CF onto the line item (`set_tags`/`set_custom_fields` on the `invoice_line_item` id). The invoice serializer then appends each line's *frozen* tags/CF via the bulk helper — it never reads the live product. This keeps invoices immutable and is consistent with core owning invoices while the line's *source* lives in a plugin (no plugin import — just a `(entity_type, id)` copy).

## fe-admin — Settings → "Custom Fields" (catalog manager)

A new Settings entry **"Custom Fields"**, sibling of **"Taxes & Countries"**. One page, two tabs. Both tables are sortable, with a **quick-search** box, **filters**, row **checkboxes for bulk operations**, and core **unified import/export** buttons (the D-data-exchange `tags` / `custom_field_defs` exchangers, json+csv).

**Tab 1 — "Custom fields"** (manages `custom_field_def` rows; gated `settings.manage`):
- **Filters:** by **parent entity** (`entity_type`, from `list_entity_types()`) and by **data type** (text/number/bool/date/select/multiselect).
- **Toolbar:** quick-search · Import · Export · **"Create CF"** button (opens a def form: key, label, parent entity_type, type, options for select/multiselect, sort_order, is_active).
- **Table columns:** ☐ (bulk) · key · label · parent entity_type · type · options · sort_order · is_active.
- **Bulk operations:** delete selected (cascades that def's values, batched — §Scaling #7), activate / deactivate selected, export selected.

**Tab 2 — "Global tags"** (manages the `vbwd_tag` catalog):
- **Tag fields:** `slug`, `name`, `parent_entity_type` (nullable — NULL = global), `meta_data` (JSON).
- **Filters:** by `parent_entity_type` (incl. an "All / global" option) · quick-search over slug+name.
- **Toolbar:** quick-search · Import · Export · **"Create tag"**.
- **Table columns:** ☐ (bulk) · **name** · **slug** · **parent type** (shown only when non-null) · **stats**.
- **Stats column** = usage count across *every* entity referencing the tag. The list issues **one** `TagService.get_stats_bulk(slugs)` grouped-`COUNT` over `entity_tag` (D6 reverse index) for the visible page — never one `get_stats` per row. `get_stats(slug) -> int` exists for single-tag views.
- **Bulk operations:** delete selected (cascades `entity_tag` rows via the FK `ON DELETE CASCADE`, batched), export selected. (Merge-tags is a tempting bulk op but **deferred** — out of scope here.)

i18n keys for both tabs in all locales.

## Migration — fold existing tags into core, drop the old ones (D7)

**Inventory (what exists today):**

| Module | Tag mechanism today | Action |
|---|---|---|
| **CMS** | `cms_term` rows where `term_type='tag'` (slug, name) + `cms_post_term` M2M (post↔term) | **MIGRATE → core, then drop the tag rows + tag links** |
| CMS content-ingest (`content_ingest_service`) | payload `tags:[…]` → `TermService.find_or_create('tag', …)` | **Rewire** to write via core tag port |
| WP import (`wp_import`) | classified RSS terms → `find_or_create('tag', …)` | **Rewire** to write via core tag port (category classification unchanged) |
| CMS categories (`cms_term` `term_type='category'`, legacy `cms_category`) | hierarchical taxonomy | **KEEP — untouched** |
| shop / booking / subscription / ghrm | **categories only** (`*_category` tables); no tags | **KEEP — untouched** |

So there is exactly **one** data set to move (CMS tags) and **two** write paths to redirect. Nothing else in the platform owns a tag.

**Rewire — CMS:**
1. CMS registers `register_entity_type(EntityTypeRegistration("cms_post", "Post", "cms.pages.manage"))` (and `cms_page` if pages carry tags). Categories continue through `cms_term`/`TermService` exactly as now.
2. **Deregister the `tag` term type** from `term_type_registry` (keep `category` and any plugin custom types). `TermManager.vue` loses its **"Tag"** tab automatically (tabs come from the registry); tag management now lives in **Settings → Custom Fields → Global tags**.
3. Post **serialization**: tags come from the core port (`get_tags`/`get_tags_bulk` on `cms_post`), not from `cms_post_term`. `terms` in the post payload now carries **categories only**; a separate `tags:[…]` key is appended by the D4 helper.
4. **Post-by-tag listing** (`GET /cms/posts?term_type=tag&…`, `CmsTagCloud`): re-point to the core path — list/count via `entity_tag` (entity_type `cms_post`) + `get_stats`. CMS post volumes are O(10³–10⁴), so this small-N reverse-index lookup is the *bounded* exception D5 explicitly allows (it is **not** the 1M-SKU catalog-filter path). Category filtering stays on `cms_term`/`cms_post_term`.
5. **Ingestion paths** (`content_ingest_service`, `wp_import`): `categories[]` → unchanged (`find_or_create('category')`); `tags[]` → `set_tags("cms_post", post.id, slugs)` via the port (idempotent, auto-creates catalog rows).

**Reimport + drop (one-shot, idempotent, set-based — D6):** packaged as a **CMS-plugin Alembic migration** that runs *after* the core `vbwd_tag`/`entity_tag` migration (anchored on that core revision):
- **Reimport:** `INSERT … ON CONFLICT DO NOTHING` from `cms_term WHERE term_type='tag'` → `vbwd_tag` with **`parent_entity_type = 'cms_post'`** (locked decision below — migrated tags stay blog-scoped); then `INSERT … ON CONFLICT` from the matching `cms_post_term` rows → `entity_tag` (`entity_type='cms_post'`, `entity_id=post_id`, `tag_slug=slug`).
- **Verify count** (migrated `entity_tag` rows == old tag `cms_post_term` rows) inside the migration; abort if mismatched.
- **Drop:** delete `cms_post_term` rows whose term is a tag, then delete `cms_term WHERE term_type='tag'`. `cms_post_term` and `cms_term` (now categories-only) **remain**. Batched delete if large (§Scaling #7).
- **down()** best-effort reverses (recreate tag terms + links from `entity_tag`); note it in the migration docstring.

This is a schema+data migration, so Alembic is the right vehicle ([[feedback_migrations_only]]); the reimport uses the same upsert semantics as the `tags` exchanger, so re-running is safe.

**Decision (locked 2026-06-13): CMS-migrated tags are SCOPED to `cms_post`** (`parent_entity_type='cms_post'`). They keep today's "blog tags" semantics — offered only on CMS post/page editors and the CMS tag cloud, **hidden** from product/plan/other TagPickers (which see only global tags + their own scope). New cross-entity tags can still be created as global from the catalog manager; this decision concerns only the data carried over from CMS.

## Scope
**Core backend:**
- Models + repos + `TagService` / `CustomFieldService` (CRUD for defs/tags; get/set values; validation) under `vbwd/models/` + `vbwd/services/`.
- The port `ITagsAndCustomFields` + default impl + `register/resolve_*` (mirror the entitlement-provider registry); an `entity_type` registry so only registered types are accepted.
- Admin routes: tag catalog CRUD + custom-field-def CRUD (gated `settings.manage`); generic value endpoints `GET|PUT /api/v1/admin/<entity_type>/<id>/tags` and `…/custom-fields` (gated by the entity's own manage permission, passed in by the consumer).
- **Data-exchange:** `tags` + `custom_field_defs` exchangers (json+csv); entity exports may include `tags`/`custom_fields` (opt-in extension of the entity's exchanger).

**fe-core (read-only display, shared by fe-user cards + fe-admin):**
- `TagChips.vue` + `CustomFieldsDisplay.vue` — render the `tags`/`custom_fields` keys already on the serialized payload (no fetch). Consumed by tarif/add-on/product cards, page/post renders, invoice line render.

**fe-admin (reusable editors + catalog manager):**
- `vue/src/components/TagPicker.vue` (create/select tags, chips) and `vue/src/components/CustomFieldsEditor.vue` (renders inputs from field defs by type). Both bind to the generic value endpoints; each host passes only `entity_type` + `manage_permission`.
- **Settings → "Custom Fields"** page (sibling of "Taxes & Countries"), two tabs — **"Custom fields"** (def catalog) + **"Global tags"** (tag catalog) — each a sortable table with quick-search, filters, bulk operations, unified import/export, and (tags) a `get_stats_bulk`-backed **stats** column. Full layout in §fe-admin.
- **Wire into every consumer edit page** (Tags + Custom fields block): user, shop_product, tarif_plan, addon, booking_resource, ghrm_software_package, cms_page, cms_post — see §Entity wiring matrix. Each plugin registers its `entity_type` in `on_enable`.
- i18n keys (all locales).

**Invoices (core):** register `invoice_line_item`; **snapshot** the source item's tags/CF onto each line item at issue time (no live join, no plugin import — §Entity wiring).

**Migration (CMS, D7):** rewire CMS tags onto the core port (deregister the `tag` term type; ingestion/wp-import `tags[]` → `set_tags`; post-by-tag listing → `entity_tag`); a CMS-plugin Alembic migration **reimports** `cms_term('tag')` + tag links into `vbwd_tag`/`entity_tag` then **drops** the old tag rows/links. Categories untouched everywhere. Full plan in §Migration.

## TDD
- **Core:** tag CRUD + attach/detach by `(entity_type,id)` idempotent; `parent_entity_type` scoping (`list_applicable_tags`: global tag offered everywhere, scoped tag only to its type); `get_stats`/`get_stats_bulk` count `entity_tag` rows correctly (incl. zero) in one grouped query; custom-field def CRUD; value set/get validated against type/options (bad value/type → error; unknown entity_type rejected); `*_bulk` reads return per-id maps with no N+1; tags/CF exchangers json+csv round-trip; deleting a tag/def cascades its rows; **invoice line-item snapshot** freezes source CF/tags (later change to the source does not mutate the invoice).
- **fe-core (Vitest):** `TagChips` / `CustomFieldsDisplay` render from payload keys, formatting each value by def `type`.
- **fe-admin (Vitest):** `TagPicker` adds/removes tags and saves (only applicable tags offered); `CustomFieldsEditor` renders per-type inputs from defs and saves values; **Custom Fields settings page** — both tabs: filter by parent entity + data type, quick-search, bulk delete/activate, import/export, and the **tags stats column** renders `get_stats_bulk` counts; representative consumer edit pages (user, product, tarif) show and persist tags + custom fields; `TermManager` no longer shows a **Tag** tab (registry-driven).
- **Migration (CMS, D7):** the reimport migration moves every `cms_term('tag')` + tag link into `vbwd_tag`/`entity_tag` with matching counts (idempotent on re-run); afterwards `cms_term` holds **categories only** and tag links are gone; CMS post serialization exposes categories under `terms` + tags under `tags`; `set_tags` from content-ingest/wp-import lands in `entity_tag`; post-by-tag listing returns the same posts as before via the core path.

## Definition of done
A generic, core-owned tags + custom-fields framework keyed by `(entity_type, entity_id)` exists with: the **Settings → "Custom Fields"** catalog page (Custom-fields tab + Global-tags tab with filters, quick-search, bulk ops, unified import/export, and a usage **stats** column on tags); reusable `TagPicker`/`CustomFieldsEditor` editors + fe-core `TagChips`/`CustomFieldsDisplay`; **Tags + Custom-fields blocks wired into every entity edit page** (user, product, tarif, add-on, booking resource, ghrm package, page, post) and **cards/detail/invoice-line** renders; invoice line items carry a **snapshot**; **existing CMS tags reimported into the core tables and the old `cms_term('tag')` rows + links dropped** (categories untouched everywhere — D7); json/csv import/export; a narrow port so consumers opt in without core importing plugins and without per-entity migrations; core `--full` + touched plugins `--full` + fe-core/fe-admin Vitest/ESLint green.

**Live proof — HTML walkthrough report with real screenshots on localhost** (`docs/dev_log/20260613/walkthrough/s77-WALK-REPORT-tags-custom-fields.html`, mirroring the s84/s81 walkthroughs). Captures the running stack — **fe-admin** (port 8081): the Settings → "Custom Fields" page (both tabs, the tag **stats** column populated, the def filters/quick-search), creating a tag + a custom-field def, and an entity edit page (e.g. product) showing the **Tags** + **Custom fields** blocks with values saved; **fe-user** (port 8080): a card/detail render (e.g. product or post) showing the saved **tags as chips** + **custom fields** via the fe-core display components. Real screenshots (not mockups), each step captioned with the action + observed result.

Not committed ([[feedback_no_commit_without_ask]]).
