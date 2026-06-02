# Sprint 46 — Unified Data Exchange (core import/export for every entity)

**Status:** DRAFT for negotiation — 2026-06-02
**Area:** **core** — `vbwd-backend` (core), `vbwd-fe-core`, `vbwd-fe-admin` (core), plus adapter updates in plugins `cms`, `subscription`, `booking`, `ghrm`, `shop`, `discount/promotions`.
**Context:** Today every entity invents its own export/import. CMS pages have a full bulk UI (`CmsImportExport.vue`, sections + conflict strategy); Settings→Countries has the cleaner **"VBWD-standard JSON"** envelope (`country_io.py`). Two good patterns, zero reuse. This sprint promotes them to **one core abstraction** so import/export is a platform feature inherited by every list, every plugin.

## Engineering requirements (BINDING)

**TDD-first** · **DevOps-first** · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change that satisfies the requirement). The quality guard is **`bin/pre-commit-check.sh --full`** — green on every touched repo (backend + fe-core + fe-admin) = "done". See [`_engineering_requirements.md`](_engineering_requirements.md).

**Non-negotiable architectural rule:** **vbwd core stays agnostic.** Core ships the *registry, the port, the generic routes, the generic UI, and the core entities only* (users, invoices, payment methods, access levels, email templates, countries). Plugins register their own entities into the registry at enable-time via DI — **core never imports `plugins.*`** (enforced by `tests/unit/test_core_agnosticism.py`). This is the same registry/port seam already used for `checkoutSourceRegistry`, `deletion_dependency_registry`, and the line-item handler registry.

## Goal

A single, generic **Data Exchange** subsystem:

1. **One Settings entry → `Import / Export`** — a generic page with two tabs (**Export**, **Import**), modelled on `CmsImportExport.vue` but driven by a server **manifest** so it lists *whatever entities are registered + permitted*, not a hard-coded set.
2. **Every admin list gets Export/Import buttons + bulk export** — a shared fe-core component (`Export selected`, `Export all`, `Import`) wired by an `entityKey`. No per-list bespoke code.
3. **One on-disk format** — the **VBWD-standard JSON envelope** (generalised from `country_io.py`), with a ZIP container for entities that carry binary assets (CMS images) and for multi-entity bundles.
4. **Two-layer, per-entity permissions** — `<entity>.export` and `<entity>.import`. Superadmin bypasses; every other admin needs the grant in their Access Level.
5. **Plugins centralise but can extend** — `cms`, `subscription`, `booking`, `ghrm`, `shop`, `promotions` stop hand-rolling and register an exchanger; they may subclass the base exchanger to add plugin-specific shaping.

## Why now / source

`reports/05-core-gate-fixes-and-countries-export-import.md` shipped countries export/import as a one-off; CMS shipped its own months earlier. The duplication is the trigger — the next entity (email templates, payment methods) would be a third copy. Promote to core before it spreads.

---

## Architecture overview (the seam)

```
            ┌──────────────────────────  CORE  ──────────────────────────┐
            │  DataExchangeRegistry  (DI singleton)                       │
            │    register(EntityExchanger)                                │
            │    list_for(user) -> manifest (perm-filtered)               │
            │    get(entity_key) -> EntityExchanger                       │
            │                                                             │
            │  port  EntityExchanger (ABC)                                │
            │    entity_key / label / group                              │
            │    supports_export / supports_import                        │
            │    export(selector) -> Envelope                             │
            │    import_(payload, strategy) -> ImportResult               │
            │    export_permission / import_permission                    │
            │                                                             │
            │  generic routes  /api/v1/admin/data-exchange/*              │
            │  core exchangers: users, invoices(exp), payment_methods,    │
            │                   access_levels, email_templates, countries │
            └─────────────────────────────────────────────────────────────┘
                         ▲ register() at on_enable() (DI, no core import)
   ┌─────────────────────┼───────────────────────────────────────────────┐
   │ cms        │ subscription │ booking │ ghrm │ shop │ discount         │
   │ pages,…    │ subscriptions│ bookings│  …   │ orders│ promotions       │
   │ images(zip)│ tarif_plans  │         │      │ products│                │
   │            │ add-ons      │         │      │       │                  │
   └────────────────────────────────────────────────────────────────────┘
```

Core owns the contract and the generic surface; each plugin contributes exchangers. The fe-admin UI never names an entity — it renders the manifest.

---

## The VBWD-standard envelope (generalised from `country_io.py`)

**Single entity (JSON):**
```json
{
  "vbwd_export": "users",
  "version": 1,
  "exported_at": "2026-06-02T18:00:00Z",
  "instance": "main",
  "users": [ { /* entity dict, instance-specific fields stripped */ } ]
}
```

**Multi-entity bundle (ZIP)** — `data-exchange.zip` containing one `<entity>.json` envelope per selected entity, plus an `assets/` dir for binary payloads (CMS images), plus a top-level `manifest.json` listing contents + versions. Mirrors CMS's existing bulk ZIP so the CMS migration is mechanical.

**Import result (uniform):** `{ "entity": "users", "created": N, "updated": M, "skipped": K, "errors": [...] }`.

**Conflict strategy** (reuse CMS's vocabulary, applied uniformly): `add` (insert only, skip existing), `index` (upsert by natural key), `drop_all` (replace — **superadmin-only**, guarded). Default `index`.

**Natural key per entity** is declared by the exchanger (e.g. users→`email`, countries→`code`, pages→`slug`, plans→`code`) so imports never depend on instance UUIDs.

---

## Backend design (core, layered + SOLID)

**New package `vbwd/services/data_exchange/`:**

- `port.py` — `class EntityExchanger(ABC)`:
  ```python
  entity_key: str            # "users"
  label: str                 # "Users"
  group: str                 # "Core" / "CMS" / "Sales"
  supports_export: bool
  supports_import: bool
  natural_key: str           # "email"
  def export(self, selector: ExportSelector) -> Envelope: ...
  def import_(self, payload: dict, strategy: str) -> ImportResult: ...
  @property
  def export_permission(self) -> str:  # default f"{entity_key}.export"
  @property
  def import_permission(self) -> str:  # default f"{entity_key}.import"
  ```
  - `ExportSelector` = `{ids: list | None, filters: dict | None}` (`ids=None` ⇒ export all).
  - **Liskov:** an export-only entity (`supports_import=False`) raises `UnsupportedOperationError` from `import_` — never silently no-ops (eng-req #6).
- `registry.py` — `DataExchangeRegistry` (DI singleton); `register()`, `get(key)`, `list_for(user)` → manifest filtered by `user.has_permission(...)` / `is_superadmin`.
- `envelope.py` — build/validate the VBWD-standard envelope + the ZIP bundle (single home, DRY); validates `vbwd_export` + `version`, like `import_countries`.
- `base_model_exchanger.py` — a concrete `EntityExchanger` for the common "one BaseModel + one repository, upsert by natural key" case. Core entities and most plugins just instantiate/subclass this — narrowest change, no per-entity boilerplate.

**Core exchangers (registered by core, in `vbwd/services/data_exchange/core_exchangers.py`):**
| key | export | import | natural key | notes |
|---|---|---|---|---|
| `users` | ✓ | ✓ | `email` | excludes password hash; import never elevates `is_admin` without `settings.system` |
| `invoices` | ✓ | ✗ | `number` | export-only (financial record) |
| `payment_methods` | ✓ | ✓ | `code` | reuse `seed_payment_methods` service for import |
| `access_levels` | ✓ | ✓ | `name` | RBAC roles + permission grants |
| `email_templates` | ✓ | ✓ | `key` | |
| `countries` | ✓ | ✓ | `code` | **migrate `country_io.py` to an exchanger** (delete the one-off route; keep the Settings→Countries buttons working through the generic path) |

**Generic routes — `vbwd/routes/admin/data_exchange.py`** (`@require_auth @require_admin @require_permission(...)`):
- `GET  /api/v1/admin/data-exchange/manifest` — perm-filtered list of registered entities `[{entity_key,label,group,supports_export,supports_import,can_export,can_import}]`. Drives the UI. (gated by `require_admin` only; the can_* flags come from the user's perms.)
- `POST /api/v1/admin/data-exchange/<key>/export` — body `{ids?, filters?}` → JSON envelope download. Gated by the entity's `export_permission`.
- `POST /api/v1/admin/data-exchange/<key>/import` — JSON envelope (or multipart for ZIP) + `strategy` → `ImportResult`. Gated by `import_permission`.
- `POST /api/v1/admin/data-exchange/export` — body `{entities:[...]}` → ZIP bundle. Each entity individually perm-checked; entities the user can't export are dropped + reported.
- `POST /api/v1/admin/data-exchange/import` — multipart ZIP bundle + `strategy` → per-entity `ImportResult[]`.

**Permissions** — auto-derived from the registry: every registered exchanger contributes `<key>.export` (and `<key>.import` when `supports_import`) into the catalog via `collect_permission_catalog()`, grouped under the entity's `group` (so the Access Level form already renders them). No manual `CORE_PERMISSIONS` editing per entity — the registry is the source. **Superadmin bypass** is the existing `is_admin`/superadmin check; a normal admin sees only entities they're granted.

**Instance configurability** — a core config block (e.g. `data_exchange.enabled_entities`) lets an install/instance trim the exposed set. Default = **all registered**. The registry filters its manifest by this allow-list. (Open decision: config file vs Settings toggle — see below.)

---

## Default entity manifest (the list, with owner + capability)

| Entity | Export | Import | Owner | Natural key |
|---|---|---|---|---|
| Users | ✓ | ✓ | **core** | email |
| Subscriptions | ✓ | — | plugin `subscription` | id/ref |
| Invoices | ✓ | — | **core** | number |
| Bookings | ✓ | ✓ | plugin `booking` | ref |
| Shop (orders + products) | ✓ | ✓ | plugin `shop` | sku / order_no |
| Promotions / coupons | ✓ | ✓ | plugin `discount` | code |
| Payment methods | ✓ | ✓ | **core** | code |
| Access levels | ✓ | ✓ | **core** | name |
| Email templates | ✓ | ✓ | **core** | key |
| **CMS** pages | ✓ | ✓ | plugin `cms` | slug |
| **CMS** categories | ✓ | ✓ | plugin `cms` | slug |
| **CMS** images | ✓ | ✓ | plugin `cms` | filename (ZIP — assets) |
| **CMS** layouts | ✓ | ✓ | plugin `cms` | key |
| **CMS** widgets | ✓ | ✓ | plugin `cms` | key |
| **CMS** styles | ✓ | ✓ | plugin `cms` | key |
| **Subscription** tarif plans | ✓ | ✓ | plugin `subscription` | code |
| **Subscription** add-ons | ✓ | ✓ | plugin `subscription` | code |

> GHRM registers its exchanger(s) the same way (ex/im) — entities TBD with the plugin owner. "everything" for CMS = the six rows above, exactly what `CmsImportExport.vue` already exports.

---

## fe-core design (generic, reusable, theme-aware)

All generic UI lives in `vbwd-fe-core` (memory: design-system rule) using `var(--vbwd-*)`, mobile-app-ready.

- **`ImportExportPanel.vue`** — the two-tab page (**Export** / **Import**), generalised from `CmsImportExport.vue`:
  - *Export tab:* entity checklist (from manifest, only `can_export`), "Everything / Custom" toggle, format note → triggers single-entity envelope or bulk ZIP download.
  - *Import tab:* file picker (`.json` / `.zip`), conflict-strategy radio (`add` / `index` / `drop_all`, last disabled unless superadmin), results table (`created/updated/skipped/errors`).
- **`ExportImportButtons.vue`** — the list-page control: `Export selected` (uses the list's checked ids), `Export all`, `Import`. Props: `entityKey`, `selectedIds`, `canExport`, `canImport`. Emits refresh after import.
- **`useDataExchange(entityKey)`** composable + thin api client — `fetchManifest()`, `exportEntity(ids?)`, `exportBundle(keys)`, `importEntity(file, strategy)`, `importBundle(file, strategy)`.
- **`downloadBlob()` / `readJsonFile()`** helpers — single home for the blob-download + file-read dance currently duplicated in `useCmsAdminStore` and `Settings.vue` (DRY).

## fe-admin design (inherits the feature by default)

- **Settings → "Import / Export"** — a new tab in `Settings.vue` (same pattern as Countries) rendering `<ImportExportPanel/>` fed by the manifest. Present for every install (core feature); individual entities appear only if registered + permitted.
- **Per-list buttons** — drop `<ExportImportButtons :entity-key="…">` into the core list views (Users, Invoices, …) and have plugins do the same in their admin list views (CMS pages already has them → re-point to the generic component). Buttons render only when `authStore.hasPermission('<key>.export'|'.import')` or superadmin.
- **No new nav plumbing for plugins** — because the entity comes from the manifest, a plugin enabling its exchanger automatically appears in the Settings panel; the per-list buttons are the only thing the plugin's own admin views add.

---

## Plugin updates (centralise, may extend)

Each plugin **deletes its bespoke export/import route** and instead registers an `EntityExchanger` (subclassing `BaseModelExchanger` where possible) in `on_enable()` via the DI container — exactly the DI-registration pattern from [[project_plugin_di_provider_registration]]:

- **`cms`** — register six exchangers (pages/categories/images/layouts/widgets/styles); images subclass to emit a ZIP with assets. Retire `/admin/cms/*/export|import` once `CmsImportExport.vue` re-points to the generic panel (keep a deprecation shim for one release if external callers exist — open decision).
- **`subscription`** — `subscriptions` (export-only), `tarif_plans`, `add-ons`.
- **`booking`** — `bookings` (ex/im).
- **`ghrm`** — its entities (ex/im).
- **`shop`** — orders + products (full ex/im).
- **`discount`** — promotions/coupons (full ex/im).

Plugin exchangers declare their own `group` (so perms land under the plugin's heading) and may override `export`/`import_` for custom shaping (e.g. subscription bundling) — **extension, not core change**.

---

## Permission model (two layers, superadmin bypass)

- Per entity: **`<entity>.export`** and **`<entity>.import`** (e.g. `users.export`, `users.import`, `invoices.export`).
- **Superadmin** → all entities, all operations, plus `drop_all`.
- **Non-superadmin admin** → must have the specific grant in their **Access Level**; the manifest hides what they can't do and the routes 403 defensively.
- Permissions are **auto-registered from the registry** into `collect_permission_catalog()` — the Access Level form renders them grouped by entity `group` with no per-entity wiring.

## Security

1. Every write path is `require_admin` + the entity's `import_permission`; `drop_all` is superadmin-only and guarded server-side (never trust the client radio).
2. **Users import** must not let a non-superadmin set `is_admin`/elevate roles — strip/ignore privilege fields unless caller has `settings.system`.
3. **Invoices are export-only** (financial integrity) — `import_` raises `UnsupportedOperationError`.
4. Import is transactional per entity; partial failures report in `errors[]` and roll back that entity (no half-imported state).
5. ZIP import: validate `manifest.json`, cap total/extracted size (zip-bomb guard), restrict asset paths to `assets/` (path-traversal guard).
6. Exported envelopes strip secrets (password hashes, tokens, internal ids that aren't the natural key).

## TDD plan (tests FIRST)

- **Backend unit** (MagicMock repos): registry register/get/`list_for` perm-filtering; `BaseModelExchanger` export shape + upsert-by-natural-key for `add`/`index`/`drop_all`; export-only entity raises `UnsupportedOperationError` on import (Liskov); envelope build/validate (bad `vbwd_export`/`version` rejected).
- **Backend integration** (`db` fixture): each core exchanger round-trips (export → wipe → import → equal); manifest endpoint reflects perms (superadmin vs scoped admin vs none → 403); bundle ZIP round-trip incl. CMS images; **countries migration** keeps the existing Settings buttons working (characterisation test against today's `country_io` output).
- **Core-agnosticism oracle:** `test_core_agnosticism.py` still green — no `from plugins.*` in core; plugins register at enable-time.
- **fe-core unit** (vitest/jsdom): `ImportExportPanel` renders manifest, gates `drop_all`, shows results; `ExportImportButtons` emits/uses selected ids, hidden without perm; `useDataExchange` calls right endpoints; `downloadBlob`/`readJsonFile` helpers.
- **fe-admin unit + e2e:** Settings "Import/Export" tab renders; a Users export downloads an envelope; an import reports counts; permission-gated visibility (seed an admin without `users.export` → no button).

## Sub-sprints

- **S46.0 — core registry + port + envelope + generic routes + permission auto-registration** (no entities yet beyond a test fake). `--full` green; oracle green.
- **S46.1 — core exchangers** (users, invoices-exp, payment_methods, access_levels, email_templates) + **migrate countries** off `country_io` one-off.
- **S46.2 — fe-core generic components** (`ImportExportPanel`, `ExportImportButtons`, `useDataExchange`, helpers) + build `dist/`.
- **S46.3 — fe-admin wiring** (Settings tab + per-list buttons on core lists + permission gating).
- **S46.4 — CMS migration** (six exchangers; re-point `CmsImportExport.vue`/`CmsPageList.vue` to the generic path; retire bespoke routes behind a shim).
- **S46.5 — subscription / booking / ghrm / shop / discount exchangers** (one PR per plugin repo; each `--plugin <x> --full` green).
- **S46.6 — instance configurability** (`data_exchange.enabled_entities` allow-list) + docs.

## Open decisions

1. **Bulk format:** ZIP-of-envelopes (chosen, matches CMS) vs one big JSON. ZIP is mandatory anyway for image assets → go ZIP.
2. **CMS legacy routes:** hard-cut to generic vs one-release deprecation shim. Recommend shim if any external tooling hits `/admin/cms/pages/export`.
3. **Instance config surface:** static config file vs a superadmin Settings toggle for `enabled_entities`. Recommend config file now (no UI), toggle later (no-overengineering).
4. **Selector filters:** ship `ids`-only first (matches every current caller) and add `filters` only when a list needs "export current filter" — defer.
5. **GHRM entities:** confirm exact entity set with the plugin owner.
6. **Cross-instance UUIDs:** confirm every importable entity has a stable natural key (users→email assumed unique per instance).

## Definition of done

Settings has an **Import / Export** page listing every registered+permitted entity across two tabs; every core list (and the migrated plugin lists) shows perm-gated Export/Import + bulk export; the default manifest matches the table above; countries + CMS run through the generic path (one-offs retired/shimmed); `<entity>.export`/`.import` permissions appear in the Access Level form and gate access (superadmin bypass); core stays agnostic (oracle green); `bin/pre-commit-check.sh --full` green on `vbwd-backend`, `vbwd-fe-core`, `vbwd-fe-admin`, and each touched plugin repo; envelope/ZIP round-trip integration tests green.
