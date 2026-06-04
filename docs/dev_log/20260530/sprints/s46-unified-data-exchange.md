# Sprint 46 — Unified Data Exchange (core import/export for every entity)

**Status:** DRAFT for negotiation — 2026-06-02 (decisions D1–D11 locked from the 2026-06-02 negotiation; remaining opens at the bottom)
**Area:** **core** — `vbwd-backend` (core), `vbwd-fe-core`, `vbwd-fe-admin` (core), plus exchanger adapters in plugins `cms`, `subscription`, `booking`, `ghrm`, `shop`, `discount/promotions` — **all in this sprint**.
**Context:** Today every entity invents its own export/import. CMS pages have a full bulk UI (`CmsImportExport.vue`, sections + conflict strategy); Settings→Countries has the cleaner **"VBWD-standard JSON"** envelope (`country_io.py`). Two good patterns, zero reuse. This sprint promotes them to **one core abstraction** so import/export is a platform feature inherited by every list, every plugin, the CLI, and the install recipes.

## Engineering requirements (BINDING)

**TDD-first** · **DevOps-first** · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change that satisfies the requirement). The quality guard is **`bin/pre-commit-check.sh --full`** — green on every touched repo (backend + fe-core + fe-admin + each touched plugin) = "done". See [`_engineering_requirements.md`](_engineering_requirements.md).

**Non-negotiable architectural rule:** **vbwd core stays agnostic.** Core ships the *registry, the port, the generic routes, the CLI, the generic UI, and the core entities only* (users, invoices, payment methods, access levels, email templates, countries). Plugins register their own entities into the registry at enable-time via DI — **core never imports `plugins.*`** (enforced by `tests/unit/test_core_agnosticism.py`). Same registry/port seam already used for `checkoutSourceRegistry`, `deletion_dependency_registry`, and the line-item handler registry.

## Goal

A single, generic **Data Exchange** subsystem:

1. **One Settings entry → `Import / Export`** — a generic page with two tabs (**Export**, **Import**), modelled on `CmsImportExport.vue` but driven by a server **manifest** so it lists *whatever entities are registered + enabled + permitted*, not a hard-coded set.
2. **Every admin list gets export/import controls** — a shared fe-core component: **Export selected**, **Export all**, **Export current filter/search**, and an inline **Import** — all wired by an `entityKey`.
3. **One on-disk format** — the **VBWD-standard JSON envelope** (generalised from `country_io.py`), plus **CSV** for flat entities (spreadsheet round-trip), plus a ZIP container for binary assets (CMS images) and multi-entity bundles.
4. **Two/three-layer, per-entity permissions** — `<entity>.export`, `<entity>.import`, and (for entities with personal data) `<entity>.export.pii`. Superadmin bypasses; every other admin needs the grant in their Access Level.
5. **Plugins centralise but can extend** — `cms`, `subscription`, `booking`, `ghrm`, `shop`, `discount` stop hand-rolling and register an exchanger; they may subclass the base exchanger for plugin-specific shaping.
6. **Automation surfaces** — the same service layer is reachable via **CLI** (`flask data-exchange …`) and a **documented REST API**; **install recipes** use import to seed default content packs (countries, email templates, demo data).

## Locked decisions (2026-06-02 negotiation)

| # | Decision | Consequence |
|---|---|---|
| **D1** | **Use cases: all four** — cross-instance migration/cloning, same-instance backup/restore, bulk-edit round-trip, distributable templates/content packs. | The format must be portable AND human-editable AND distributable. |
| **D2** | **Matching: natural key only.** Export strips UUIDs; import matches on the human key (email/slug/code). | Relationships are expressed by **natural key**, not UUID — the exchanger translates FK ⇄ natural key on export/import. Same-instance restore re-links by key (UUIDs not preserved). |
| **D3** | **Formats: JSON + CSV.** JSON = full fidelity (nested `content_json`, relationships); CSV = flat entities only, for spreadsheets. | Each exchanger declares `supported_formats`; nested entities are JSON-only and the UI hides CSV for them. |
| **D4** | **Import behaviour: upsert by default; dry-run preview; superadmin-only replace-all.** | Import endpoint takes `mode` (`upsert` \| `replace_all`) and `dry_run: bool`. Dry-run returns the projected `{create, update, skip}` without writing; the admin confirms. `replace_all` is superadmin-only + double-confirmed. |
| **D5** | **Scope: everything in one sprint** — core + all 6 plugins. | Sub-sprints S46.0→S46.7; "done" only when every touched repo is green. |
| **D6** | **Cross-entity dependency resolution: DEFERRED.** | Bundle export = ZIP of independent per-entity envelopes. Bundle import processes each entity independently; unresolved natural-key references → reported in `errors[]`, never auto-ordered. (Eased because invoices + subscriptions are export-only.) |
| **D7** | **List controls: export-selected + export-all + export-current-filter + inline import.** | `ExportSelector` carries `{ids?, filters?, all?}`; lists need row-selection checkboxes (add where missing) and must surface their filter/search state to the control. |
| **D8** | **Scale: synchronous + row cap for v1.** | Above the cap (default ~10k) the API refuses with "narrow with filters". Async background jobs deferred. |
| **D9** | **Privacy: strip secrets always; separate PII export permission.** | Exchanger declares `secret_fields` (never exported, even for superadmin) and `pii_fields` (redacted unless caller holds `<entity>.export.pii`). **No audit logging in v1.** |
| **D10** | **Per-instance enablement: static allow-list at install (config/env).** Default = all registered. | Registry filters the manifest by `data_exchange.enabled_entities`; no runtime toggle UI. |
| **D11** | **Automation: CLI + documented REST API + recipe seeding.** | Thin `flask data-exchange` wrappers over the same services; default content packs shipped as importable files consumed by `recipes/`. |

---

## Architecture overview (the seam)

```
            ┌──────────────────────────  CORE  ──────────────────────────┐
            │  DataExchangeRegistry  (DI singleton)                       │
            │    register(EntityExchanger)                                │
            │    manifest_for(user) -> perm+config-filtered list          │
            │    get(entity_key) -> EntityExchanger                       │
            │                                                             │
            │  port  EntityExchanger (ABC)                                │
            │    entity_key / label / group / natural_key                 │
            │    supports_export / supports_import / supported_formats    │
            │    secret_fields / pii_fields                               │
            │    export(selector, *, include_pii) -> Envelope             │
            │    import_(payload, *, mode, dry_run) -> ImportResult       │
            │    *_permission properties                                  │
            │                                                             │
            │  generic routes  /api/v1/admin/data-exchange/*              │
            │  CLI  flask data-exchange export|import                     │
            │  core exchangers: users, invoices(exp), payment_methods,    │
            │                   access_levels, email_templates, countries │
            └─────────────────────────────────────────────────────────────┘
                         ▲ register() at on_enable() (DI, no core import)
   ┌─────────────────────┼───────────────────────────────────────────────┐
   │ cms        │ subscription      │ booking │ ghrm │ shop  │ discount    │
   │ pages,…    │ subscriptions(exp)│ bookings│  …   │ orders│ promotions  │
   │ images(zip)│ tarif_plans       │         │      │ products│           │
   │            │ add-ons           │         │      │       │             │
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
  "format": "json",
  "users": [ { /* natural-key fields; UUIDs + secrets stripped; FKs as natural keys */ } ]
}
```

**Single entity (CSV)** — flat header row + one row per record; only for entities whose `supported_formats` includes `csv` (no nested objects). **CSV carries no envelope metadata (D-CSV):** a bare `.csv` is always imported via a specific entity's endpoint/list, so the target entity is known from the **upload context**, not the file. (Inside a bundle ZIP, `manifest.json` still names each file's entity + version.)

**Multi-entity bundle (ZIP)** — `data-exchange.zip` with one `<entity>.json|csv` per selected entity, an `assets/` dir for binary payloads (CMS images), and a top-level `manifest.json` (contents + versions + instance). Mirrors CMS's existing bulk ZIP, so the CMS migration is mechanical. **No cross-entity ordering (D6)** — each file imports independently.

**Import result (uniform):**
```json
{ "entity": "users", "mode": "upsert", "dry_run": true,
  "created": 12, "updated": 30, "skipped": 2, "errors": [ {"row": 5, "reason": "..."} ] }
```

**Conflict / mode (D4):** `mode="upsert"` (default — insert new, update existing by natural key), `mode="replace_all"` (drop-then-import; **superadmin-only**, server-enforced, double-confirmed). `dry_run=true` computes the result **without writing** and rolls back, so the UI can show a preview the admin confirms.

**Natural key per entity (D2)** is declared by the exchanger (users→`email`, countries→`code`, pages→`slug`, plans→`code`, …) so imports never depend on instance UUIDs; FK references serialise as the referent's natural key.

---

## Backend design (core, layered + SOLID)

**New package `vbwd/services/data_exchange/`:**

- `port.py` — `class EntityExchanger(ABC)`:
  ```python
  entity_key: str             # "users"
  label: str                  # "Users"
  group: str                  # "Core" / "CMS" / "Sales"
  natural_key: str            # "email"
  supports_export: bool
  supports_import: bool
  supported_formats: frozenset[str]   # {"json"} or {"json","csv"}
  secret_fields: frozenset[str]       # never exported (password_hash, tokens…)
  pii_fields: frozenset[str]          # redacted unless caller has <entity>.export.pii
  def export(self, selector: ExportSelector, *, include_pii: bool) -> Envelope: ...
  def import_(self, payload: dict, *, mode: str, dry_run: bool) -> ImportResult: ...
  @property
  def export_permission(self) -> str:       # default f"{entity_key}.export"
  @property
  def import_permission(self) -> str:       # default f"{entity_key}.import"
  @property
  def pii_export_permission(self) -> str:   # default f"{entity_key}.export.pii"
  ```
  - `ExportSelector` = `{ids?: list, filters?: dict, all?: bool}` (D7) — `all=True` ⇒ everything (subject to the row cap, D8); `filters` mirrors the list's current filter/search.
  - **Liskov (eng-req #6):** export-only entities (`supports_import=False`) raise `UnsupportedOperationError` from `import_` — never a silent no-op.
- `registry.py` — `DataExchangeRegistry` (DI singleton); `register()`, `get(key)`, `manifest_for(user)` → perm- **and** config-filtered (`data_exchange.enabled_entities`, D10), with `can_export/can_import/can_export_pii` flags computed from the user's grants (superadmin = all).
- `envelope.py` — build/validate the VBWD envelope + ZIP bundle + CSV (de)serialisation (single home, DRY); validates `vbwd_export` + `version` like `import_countries`.
- `base_model_exchanger.py` — concrete `EntityExchanger` for the common "one BaseModel + one repository, upsert by natural key" case (handles secret/PII stripping, CSV flattening, the row cap, FK→natural-key mapping via a declared field map). Core entities and most plugins instantiate/subclass this — narrowest change, no per-entity boilerplate.
- `cli.py` — `flask data-exchange export <entity> [--all|--ids …] [--format json|csv] [-o file]` and `import <entity> <file> [--mode upsert|replace_all] [--dry-run]` (D11), reusing the registry + services.

**Core exchangers** (`vbwd/services/data_exchange/core_exchangers.py`):
| key | export | import | natural key | secrets/PII | notes |
|---|---|---|---|---|---|
| `users` | ✓ | ✓ | `email` | secret: `password_hash`, tokens · PII: `email`,`name`,`phone`,`address` | import never elevates `is_admin`/roles without `settings.system` |
| `invoices` | ✓ | ✗ | `number` | — | **export-only** |
| `payment_methods` | ✓ | ✓ | `code` | secret: provider keys | import reuses `seed_payment_methods` |
| `access_levels` | ✓ | ✓ | `name` | — | roles + permission grants |
| `email_templates` | ✓ | ✓ | `key` | — | content pack candidate |
| `countries` | ✓ | ✓ | `code` | — | **migrate `country_io.py` → an exchanger**; keep Settings→Countries buttons working through the generic path |

**Generic routes — `vbwd/routes/admin/data_exchange.py`** (`@require_auth @require_admin @require_permission(...)`):
- `GET  /api/v1/admin/data-exchange/manifest` — perm+config-filtered entity list with `can_*` flags. Drives the UI.
- `POST /api/v1/admin/data-exchange/<key>/export` — body `{ids?, filters?, all?, format?}` → JSON/CSV download. Gated by `export_permission`; PII redacted unless caller has `pii_export_permission`.
- `POST /api/v1/admin/data-exchange/<key>/import` — JSON/CSV (or multipart) + `{mode, dry_run}` → `ImportResult`. Gated by `import_permission`; `replace_all` additionally requires superadmin.
- `POST /api/v1/admin/data-exchange/export` — `{entities:[…], format?}` → ZIP bundle; each entity perm-checked, un-permitted ones dropped + reported.
- `POST /api/v1/admin/data-exchange/import` — multipart ZIP + `{mode, dry_run}` → per-entity `ImportResult[]` (independent, D6).

**Permissions** — **auto-derived from the registry**: each exchanger contributes `<key>.export`, `<key>.import` (when importable), and `<key>.export.pii` (when `pii_fields`) into `collect_permission_catalog()`, grouped by the entity's `group`. No manual `CORE_PERMISSIONS` editing per entity. Superadmin bypass = existing check.

**Row cap (D8)** — default **10,000** rows per entity per operation, a core constant (config-overridable per instance/entity); exports exceeding it 4xx with a "narrow with filters" message; the UI surfaces it.

---

## Default entity manifest (owner + capability)

| Entity | Export | Import | Owner | Natural key | Formats |
|---|---|---|---|---|---|
| Users | ✓ | ✓ | **core** | email | json, csv |
| Invoices | ✓ | — | **core** | number | json, csv |
| Subscriptions | ✓ | — | plugin `subscription` | ref | json |
| Bookings | ✓ | ✓ | plugin `booking` | ref | json |
| Shop (orders + products) | ✓ | ✓ | plugin `shop` | sku / order_no | json (csv for products) |
| Promotions / coupons | ✓ | ✓ | plugin `discount` | code | json, csv |
| Payment methods | ✓ | ✓ | **core** | code | json |
| Access levels | ✓ | ✓ | **core** | name | json |
| Email templates | ✓ | ✓ | **core** | key | json |
| **CMS** pages | ✓ | ✓ | plugin `cms` | slug | json (nested) |
| **CMS** categories | ✓ | ✓ | plugin `cms` | slug | json, csv |
| **CMS** images | ✓ | ✓ | plugin `cms` | filename | zip (assets) |
| **CMS** layouts | ✓ | ✓ | plugin `cms` | key | json |
| **CMS** widgets | ✓ | ✓ | plugin `cms` | key | json |
| **CMS** styles | ✓ | ✓ | plugin `cms` | key | json |
| **Subscription** tarif plans | ✓ | ✓ | plugin `subscription` | code | json, csv |
| **Subscription** add-ons | ✓ | ✓ | plugin `subscription` | code | json, csv |
| **GHRM** packages | ✓ | ✓ | plugin `ghrm` | code | json, csv |

> **Export-only:** invoices, subscriptions. **GHRM** registers **`packages` only** for v1 (other GHRM data deferred). "Everything" for CMS = the six rows above (exactly what `CmsImportExport.vue` already does).

---

## fe-core design (generic, reusable, theme-aware)

All generic UI lives in `vbwd-fe-core` (design-system rule) using `var(--vbwd-*)`, mobile-app-ready.

- **`ImportExportPanel.vue`** — the two-tab page (**Export** / **Import**), generalised from `CmsImportExport.vue`:
  - *Export tab:* entity checklist (manifest, only `can_export`), Everything/Custom toggle, **format selector** (json/csv per entity capability) → single-entity or bundle ZIP download.
  - *Import tab:* file picker (`.json`/`.csv`/`.zip`), **mode** (`upsert` default; `replace_all` shown only to superadmin, double-confirmed), a **Dry-run / Preview** action that shows the projected `{create, update, skip, errors}` table, then a **Confirm import** button.
- **`ExportImportControls.vue`** — the list-page control (D7): **Export selected** (checked ids), **Export all**, **Export current filter**, **Import**. Props: `entityKey`, `selectedIds`, `filterState`, `canExport`, `canImport`, `canExportPii`, `isSuperadmin`. Emits refresh after import. Renders only the actions the user is permitted.
- **`useDataExchange(entityKey)`** composable + thin api client — `fetchManifest()`, `exportEntity({ids?,filters?,all?,format})`, `exportBundle(keys,format)`, `importEntity(file,{mode,dryRun})`, `importBundle(file,{mode,dryRun})`.
- **`downloadBlob()` / `readImportFile()`** helpers — single home for the blob-download + file-read dance currently duplicated in `useCmsAdminStore` and `Settings.vue` (DRY).

## fe-admin design (inherits the feature by default)

- **Settings → "Import / Export"** — a new tab in `Settings.vue` (same pattern as Countries) rendering `<ImportExportPanel/>` from the manifest. Present on every install (core feature); entities appear only if registered + enabled + permitted.
- **Per-list controls** — drop `<ExportImportControls :entity-key="…" :selected-ids :filter-state>` into core list views (Users, Invoices); plugins do the same in their admin lists (CMS pages re-points its existing buttons to this control). **Lists need row-selection checkboxes** where missing (D7) — a small per-list enhancement tracked in the relevant sub-sprint.
- **No new nav plumbing for plugins** — because entities come from the manifest, enabling a plugin's exchanger auto-surfaces it in the Settings panel; the per-list control is the only thing a plugin's admin views add.

---

## Plugin updates (centralise, may extend)

Each plugin **deletes its bespoke export/import route** and registers an `EntityExchanger` (subclassing `BaseModelExchanger` where possible) in `on_enable()` via the DI container — the registration pattern from [[project_plugin_di_provider_registration]]:

- **`cms`** — six exchangers; images subclass to emit a ZIP with assets. **Hard-cut (D-shim):** delete `/admin/cms/*/export|import` outright; `CmsImportExport.vue`/`CmsPageList.vue` re-point to the generic panel/control — single code path, no shim.
- **`subscription`** — `subscriptions` (export-only), `tarif_plans`, `add-ons`.
- **`booking`** — `bookings` (ex/im).
- **`ghrm`** — **`packages` only** for v1 (the billable plan-like entity, full ex/im); other GHRM data deferred.
- **`shop`** — orders + products (full ex/im).
- **`discount`** — promotions/coupons (full ex/im).

Plugin exchangers declare their own `group` (perms land under the plugin heading) and may override `export`/`import_` for custom shaping — **extension, not core change**.

---

## Permission model (D9)

- Per entity: **`<entity>.export`**, **`<entity>.import`**, and — where the entity has personal data — **`<entity>.export.pii`**.
- An admin with `users.export` but **not** `users.export.pii` exports users with PII fields **redacted**; secret fields are **never** exported (any role).
- **Superadmin** → all entities, all operations (incl. `replace_all` + PII).
- **Non-superadmin admin** → exactly the grants in their Access Level; the manifest hides what they can't do and routes 403 defensively.
- Permissions auto-registered from the registry into `collect_permission_catalog()`, grouped by entity `group`.

## Security

1. Every write path is `require_admin` + the entity's `import_permission`; `replace_all` is superadmin-only, enforced server-side (never trust the client).
2. **Secret-stripping is mandatory** (D9) — password hashes, tokens, provider keys never leave, even for superadmin.
3. **PII redaction** unless `<entity>.export.pii` held (D9).
4. **Users import** must not elevate `is_admin`/roles without `settings.system`.
5. **Invoices/subscriptions are export-only** — `import_` raises `UnsupportedOperationError`.
6. Import is transactional per entity; partial failure → rolled back for that entity, reported in `errors[]`. `dry_run` always rolls back.
7. ZIP import: validate `manifest.json`, cap total/extracted size (zip-bomb guard), restrict asset paths to `assets/` (path-traversal guard).
8. **Row cap** (D8) bounds export size; CSV import bounded the same way.

## TDD plan (tests FIRST)

- **Backend unit** (MagicMock repos): registry register/get/`manifest_for` perm+config filtering; `BaseModelExchanger` export shape, upsert vs replace_all, dry-run rolls back; export-only raises `UnsupportedOperationError`; secret never serialised; PII redacted without the perm; CSV flatten/parse round-trip; FK→natural-key mapping; row-cap enforcement; envelope validate (bad `vbwd_export`/`version` rejected).
- **Backend integration** (`db` fixture): each core exchanger round-trips (export → wipe → import → equal); manifest reflects perms (superadmin vs scoped admin vs none → 403); ZIP bundle round-trip incl. CMS images; dry-run writes nothing; replace_all gated to superadmin; **countries characterisation test** — existing Settings buttons keep working through the generic path; **CLI** export/import a fixture file.
- **Core-agnosticism oracle:** `test_core_agnosticism.py` green — no `from plugins.*`; plugins register at enable-time.
- **fe-core unit** (vitest/jsdom): `ImportExportPanel` renders manifest, gates `replace_all` to superadmin, shows dry-run preview then confirm; `ExportImportControls` emits selected/all/filter exports, hidden actions without perm; `useDataExchange` calls correct endpoints; download/read helpers.
- **fe-admin unit + e2e:** Settings "Import/Export" tab renders; Users export downloads an envelope; import dry-run → preview → confirm reports counts; permission-gated visibility (admin without `users.export` → no control; without `users.export.pii` → PII redacted).
- **Recipes:** a fresh `dev-install` imports the default content packs (countries + email templates) and the instance boots with them (DevOps-first, cold-start green).

## Sub-sprints

- **S46.0 — core seam** (registry + port + envelope + CSV + ZIP + base exchanger + generic routes + permission auto-registration + row cap). `--full` + oracle green.
- **S46.1 — core exchangers** (users w/ PII split, invoices-exp, payment_methods, access_levels, email_templates) + **migrate countries** off `country_io`.
- **S46.2 — CLI** (`flask data-exchange export|import`) + **content-pack files** (countries, email templates, demo data) consumed by `recipes/`.
- **S46.3 — fe-core components** (`ImportExportPanel`, `ExportImportControls`, `useDataExchange`, helpers) + build `dist/`.
- **S46.4 — fe-admin wiring** (Settings tab + per-list controls on core lists + row-selection checkboxes where missing + permission/PII gating).
- **S46.5 — CMS migration** (six exchangers; re-point CMS admin views; retire/shim bespoke routes).
- **S46.6 — subscription / booking / ghrm (packages) / shop / discount exchangers** (one PR per plugin repo; each `--plugin <x> --full` green).
- **S46.7 — docs** (REST API reference + CLI + content-pack authoring + per-instance `enabled_entities`).

## Resolved follow-up decisions (2026-06-02)

| # | Decision | Resolution |
|---|---|---|
| **D-CSV** | How CSV identifies its entity (no envelope metadata). | **Upload context** — a bare `.csv` is imported via a specific entity endpoint; entity inferred from where it's uploaded. Inside a bundle, `manifest.json` names each file. |
| **D-shim** | CMS legacy routes on migration. | **Hard-cut** — delete the bespoke `/admin/cms/*/export\|import` routes; single generic code path, no shim. |
| **D-pii-scope** | PII permission granularity. | **Per-entity** (`users.export.pii`, …) — fine-grained; no global modifier. |
| **D-rowcap** | Synchronous cap. | **10,000** rows per entity per operation; config-overridable per instance/entity. |
| **GHRM** | Entity set for v1. | **`packages` only** (billable plan-like entity, full ex/im); other GHRM data deferred. |

_All negotiation decisions are now locked. No open questions remain for S46._

## Definition of done

Settings has an **Import / Export** page listing every registered+enabled+permitted entity across two tabs; every core list (and migrated plugin lists) shows perm-gated Export-selected/all/filter + Import; default manifest matches the table; countries + CMS run through the generic path (one-offs retired/shimmed); JSON + CSV + ZIP round-trip; upsert/dry-run/replace-all behave per D4; secrets stripped + PII gated per D9; `<entity>.export`/`.import`/`.export.pii` appear in the Access Level form and gate access (superadmin bypass); CLI + REST API documented; recipes seed default content packs on a cold install; core stays agnostic (oracle green); `bin/pre-commit-check.sh --full` green on `vbwd-backend`, `vbwd-fe-core`, `vbwd-fe-admin`, and every touched plugin repo.
