# Sprint 46 — Unified Data Exchange (core import/export for every entity)

**Status:** **LOCKED 2026-06-06** — entity-data exchange across core + plugins. **Plugin-config exchange is explicitly OUT of scope** (secret-leak risk — see R6). Two tabs collapsed to one **General** tab (+ extension-contributed tabs). All 2026-06-02 + 2026-06-06 negotiation points resolved; one implementation dependency flagged (core-settings persistence).
**Area:** **core** — `vbwd-backend` (core), `vbwd-fe-core`, `vbwd-fe-admin` (core), plus exchanger adapters in plugins `cms`, `subscription`, `booking`, `ghrm`, `shop`, `discount/promotions`.
**Context:** Today every entity invents its own export/import. CMS pages have a full bulk UI (`CmsImportExport.vue`, sections + `add`/`index`/`drop_all` strategy); Settings→Countries has the cleaner **"VBWD-standard JSON"** envelope (`country_io.py`). Two good patterns, zero reuse. This sprint promotes them to **one core abstraction** so import/export is a platform feature inherited by every list, every plugin, the CLI, and the install recipes.

## Engineering requirements (BINDING)

**TDD-first** · **DevOps-first** · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change that satisfies the requirement). The quality guard is **`bin/pre-commit-check.sh --full`** — green on every touched repo (backend + fe-core + fe-admin + each touched plugin) = "done". See [`_engineering_requirements.md`](_engineering_requirements.md).

**Non-negotiable architectural rule:** **vbwd core stays agnostic.** Core ships the *registry, the port, the generic routes, the CLI, the generic UI, and the core entities only* (users+details, invoices, payment methods, access levels, email templates, countries, currencies, core settings). Plugins register their own entities into the registry at enable-time via DI — **core never imports `plugins.*`** (enforced by `tests/unit/test_core_agnosticism.py`). Same registry/port seam already used for `checkoutSourceRegistry`, `deletion_dependency_registry`, the line-item handler registry, and the fe-admin `extensionRegistry`.

---

## 2026-06-06 resolutions (read first — these are final)

| R | Decision | Effect |
|---|----------|--------|
| **R1** | **Entity data only.** One `EntityExchanger` family, one `DataExchangeRegistry`, one Settings page. | no config family |
| **R2** | **UI = one built-in "General" tab** (Export + Import blocks, entities grouped by **clusters** `sales` / `settings`) **+ any tabs extensions contribute** (R7). | replaces the old "Export tab / Import tab" |
| **R3** | **CMS keeps its own page** (rebuilt on the core fe-core components, scoped to CMS entities) **and** its entities also appear on the General tab + per-list controls. | **overturns D-shim (hard-cut)** |
| **R4** | **Formats = JSON + CSV + ZIP** (CSV kept). | **D3 stands** |
| **R5** | **Modes = `upsert` (default) + `replace_all` (superadmin) + `dry_run` preview.** | **D4 stands** |
| **R6** | **NO plugin-configuration exchange.** Config blobs hold Stripe keys, provider/OAuth secrets, the GHRM key path — export would exfiltrate secrets. **Dropped entirely** (no Plugins tab, no `ConfigExchanger`). | NEW — out of scope |
| **R7** | **Extensions can inject tabs** into the Import/Export page via a new fe-admin `dataExchangeTabs` extension slot. | NEW |
| **R8** | **Currencies** added as a core exchanger (`vbwd_currency`, key `code`). **UserDetails nested inside the `users` envelope** (1:1, all-PII), not a standalone cluster row. | extends core entities |
| **R9** | **Clusters** (`sales`, `settings`) are a UI grouping each exchanger declares (the old `group` field → `cluster`). | refines manifest |
| **R10** | **"general config" = core settings** (Settings→Core: provider info / address / bank). Exchanger key `core_settings`. **Dependency:** core settings are an **in-memory stub today** (`routes/admin/settings.py`) — must be **persisted first** (small DB table or config-store entry) or its export/import is meaningless. | resolves old Q-1 |
| **R11** | **Permission granularity:** **sales** entities → per-entity `<entity>.export` / `.import` / `.export.pii`; **settings** cluster → coarse **`settings.view`** (export) / **`settings.manage`** (import). All such permissions are **registered into the permission catalog and appear in the Access Level form** (`/admin/settings/access/<id>`). | resolves old Q-4 |
| **R12** | **Permission gating (UX), BINDING:** no permission ⇒ **no burger-menu entry AND no page** (route guard → redirect/403). Applies to **fe-admin and fe-user** alike — never render a nav item or route a user can't use. | NEW |

---

## Locked decisions (2026-06-02) — final status

| # | Decision | Status |
|---|----------|--------|
| **D1** | Use cases: cross-instance migration/cloning, backup/restore, bulk-edit round-trip, distributable templates/content packs. | kept |
| **D2** | Matching: **natural key only**; export strips UUIDs; FKs serialise as the referent's natural key. | kept |
| **D3** | Formats: **JSON + CSV** (+ ZIP container). | **kept (R4)** |
| **D4** | Import: **upsert default; dry-run preview; superadmin-only replace_all**. | **kept (R5)** |
| **D5** | Scope: core + all 6 plugins in one sprint (sub-sprints S46.0→S46.7). | kept |
| **D6** | Cross-entity dependency resolution DEFERRED; bundle = ZIP of independent per-entity envelopes; unresolved refs → `errors[]`. | kept |
| **D7** | List controls: export-selected + export-all + export-current-filter + inline import. | kept |
| **D8** | Scale: synchronous + row cap (~10k). | kept |
| **D9** | Privacy: strip secrets always; separate PII export permission. | kept |
| **D10** | Per-instance enablement: static allow-list `data_exchange.enabled_entities`; default = all. | kept |
| **D11** | Automation: CLI + documented REST API + recipe seeding. | kept |
| **D-shim** | CMS legacy routes: hard-cut. | **OVERTURNED → R3** (CMS keeps its page on core components) |
| **D-pii-scope** | PII permission per-entity. | kept |
| **D-rowcap** | 10,000 rows/entity/op; config-overridable. | kept |
| **GHRM** | v1 = `packages` only. | kept |
| ~~plugin config~~ | (2026-06-06 vision floated a Plugins tab.) | **DROPPED → R6** |

No open questions remain. The only sequencing dependency is **R10** (persist core settings before its exchanger).

---

## Architecture overview (the seam)

```
            ┌──────────────────────────  CORE  ──────────────────────────┐
            │  DataExchangeRegistry  (DI singleton)                       │
            │    register(EntityExchanger)                                │
            │    manifest_for(user) -> perm+config-filtered, clustered    │
            │    get(entity_key) -> EntityExchanger                       │
            │                                                             │
            │  port  EntityExchanger (ABC)                                │
            │    entity_key / label / cluster / natural_key               │
            │    supports_export / supports_import / supported_formats    │
            │    secret_fields / pii_fields                               │
            │    export(selector, *, include_pii) -> Envelope             │
            │    import_(payload, *, mode, dry_run) -> ImportResult       │
            │    *_permission properties                                  │
            │                                                             │
            │  generic routes  /api/v1/admin/data-exchange/*              │
            │  CLI  flask data-exchange export|import                     │
            │  core exchangers: users(+details), invoices(exp),           │
            │    payment_methods, access_levels, email_templates,         │
            │    countries, currencies, core_settings                     │
            └─────────────────────────────────────────────────────────────┘
                         ▲ register() at on_enable() (DI, no core import)
   ┌─────────────────────┼───────────────────────────────────────────────┐
   │ cms        │ subscription      │ booking │ ghrm │ shop  │ discount    │
   │ pages,…    │ subscriptions(exp)│ bookings│  …   │ orders│ promotions  │
   │ images(zip)│ tarif_plans/addons│         │      │products│            │
   │ + own page │                   │         │      │       │             │
   └────────────────────────────────────────────────────────────────────┘
```

Core owns the contract + the generic surface; each plugin contributes exchangers. The fe-admin UI never names an entity — it renders the manifest.

---

## The VBWD-standard envelope (generalised from `country_io.py`)

**Single entity (JSON)** — natural-key fields, UUIDs + secrets stripped, FKs as natural keys:
```json
{ "vbwd_export": "users", "version": 1, "exported_at": "...", "instance": "main", "format": "json",
  "users": [ { "email": "...", "details": { /* nested 1:1 PII */ }, /* … */ } ] }
```

**Single entity (CSV)** — flat header + one row per record; only for entities whose `supported_formats` includes `csv` (no nested objects). **CSV carries no envelope metadata (D-CSV):** the target entity comes from the **upload context** (a bare `.csv` is imported via a specific entity's endpoint/list). Inside a bundle ZIP, `manifest.json` names each file's entity + version.

**Multi-entity bundle (ZIP)** — `data-exchange.zip` with one `<entity>.json|csv` per entity, an `assets/` dir for binaries (CMS images), and a top-level `manifest.json` (contents + versions + instance). Mirrors CMS's existing bulk ZIP — the CMS migration is mechanical. **No cross-entity ordering (D6).**

**Import result (uniform):**
```json
{ "entity": "users", "mode": "upsert", "dry_run": true,
  "created": 12, "updated": 30, "skipped": 2, "errors": [ {"row": 5, "reason": "…"} ] }
```

**Modes (D4/R5):** `upsert` (default — insert new, update existing by natural key), `replace_all` (drop-then-import; **superadmin-only**, server-enforced, double-confirmed). `dry_run=true` computes `{create, update, skip, errors}` **without writing** (rolls back) so the UI shows a preview the admin confirms.

**Natural key per entity (D2):** users→`email`, countries→`code`, currencies→`code`, pages→`slug`, plans→`code`, … FK references serialise as the referent's natural key.

---

## Backend design (core, layered + SOLID)

**New package `vbwd/services/data_exchange/`:**

- `port.py` — `EntityExchanger(ABC)`: `entity_key`, `label`, **`cluster`**, `natural_key`, `supports_export/import`, `supported_formats` (`{"json"}` or `{"json","csv"}`), `secret_fields`, `pii_fields`, `export(selector, *, include_pii)`, `import_(payload, *, mode, dry_run)`, and `export_permission` / `import_permission` / `pii_export_permission` properties. `ExportSelector = {ids?, filters?, all?}` (D7). **Liskov:** export-only entities raise `UnsupportedOperationError` from `import_`.
- `registry.py` — `DataExchangeRegistry` (DI singleton): `register`, `get`, `manifest_for(user)` → perm- **and** config-filtered (`data_exchange.enabled_entities`, D10), **clustered**, with `can_export/can_import/can_export_pii` flags (superadmin = all).
- `envelope.py` — build/validate the VBWD envelope + ZIP bundle + **CSV (de)serialisation** (single home, DRY); validates `vbwd_export` + `version` like `import_countries`.
- `base_model_exchanger.py` — concrete `EntityExchanger` for the common "one BaseModel + one repository, upsert by natural key" case (secret/PII stripping, CSV flattening, row cap, FK→natural-key mapping via a declared field map). Core entities and most plugins subclass this.
- `cli.py` — `flask data-exchange export <entity> [--all|--ids …] [--format json|csv] [-o file]` / `import <entity> <file> [--mode upsert|replace_all] [--dry-run]` (D11).

**Core exchangers** (`core_exchangers.py`):

| key | export | import | cluster | natural key | secrets / PII | notes |
|---|---|---|---|---|---|---|
| `users` | ✓ | ✓ | sales | `email` | secret: `password_hash`, tokens · PII: email, name, phone, address, **nested `details`** | import never elevates admin/roles without `settings.system`; user-details nested (R8) |
| `invoices` | ✓ | ✗ | sales | `number` | — | **export-only** |
| `countries` | ✓ | ✓ | settings | `code` | — | **migrate `country_io.py` → exchanger**; Settings→Countries buttons keep working through the generic path |
| `currencies` | ✓ | ✓ | settings | `code` | — | `vbwd_currency` (R8); json + csv |
| `access_levels` | ✓ | ✓ | settings | `name` | — | roles + permission grants |
| `email_templates` | ✓ | ✓ | settings | `key` | — | content-pack candidate |
| `payment_methods` | ✓ | ✓ | settings | `code` | secret: provider keys | import reuses `seed_payment_methods` |
| `core_settings` | ✓ | ✓ | settings | (singleton) | secret: bank/API where applicable | **R10 — depends on persisting core settings first** (today an in-memory stub) |

**Generic routes — `vbwd/routes/admin/data_exchange.py`:**
- `GET  /api/v1/admin/data-exchange/manifest` — clustered, perm+config-filtered, `can_*` flags. Drives the UI.
- `POST /api/v1/admin/data-exchange/<key>/export` — `{ids?, filters?, all?, format?}` → JSON/CSV download. PII redacted unless caller has `pii_export_permission`.
- `POST /api/v1/admin/data-exchange/<key>/import` — JSON/CSV (or multipart) + `{mode, dry_run}` → `ImportResult`. `replace_all` requires superadmin.
- `POST /api/v1/admin/data-exchange/export` — `{entities:[…], format?}` → ZIP bundle; un-permitted entities dropped + reported.
- `POST /api/v1/admin/data-exchange/import` — multipart ZIP + `{mode, dry_run}` → per-entity `ImportResult[]` (independent, D6).

**Permissions (R11)** — auto-derived from the registry into `collect_permission_catalog()` (`vbwd/services/permission_catalog.py`), grouped by `cluster`:
- **sales** exchangers contribute `<key>.export`, `<key>.import` (when importable), `<key>.export.pii` (when `pii_fields`).
- **settings** exchangers reuse the existing **`settings.view`** (export) / **`settings.manage`** (import) — no new per-entity perms.
- All appear in the **Access Level form** (`/admin/settings/access/<id>`). Superadmin bypass = existing check.

**Row cap (D8):** default 10,000 rows/entity/op, config-overridable; over-cap exports 4xx with "narrow with filters".

---

## fe-core design (generic, reusable, theme-aware)

All generic UI in `vbwd-fe-core` (design-system rule, `var(--vbwd-*)`, mobile-app-ready).

- **`ImportExportPage.vue`** — a **tabbed shell**. Built-in: **General** tab; renders any extra tabs contributed via `dataExchangeTabs` (R7).
  - **General tab** — one page, two blocks: an **Export** block and an **Import** block, each rendering the manifest **grouped by cluster** (Sales, Settings).
    - *Export:* per-entity checkboxes (only `can_export`), Everything/Custom, **format selector** (json/csv per capability) → single-entity or bundle ZIP download.
    - *Import:* file picker (`.json`/`.csv`/`.zip`), **mode** (`upsert` default; `replace_all` superadmin-only, double-confirmed), a **Dry-run / Preview** action showing the projected `{create, update, skip, errors}`, then **Confirm import**.
- **`ImportExportControls.vue`** — the list-page control (D7): Export selected / all / current-filter + Import. Props: `entityKey`, `selectedIds`, `filterState`, `canExport`, `canImport`, `canExportPii`, `isSuperadmin`. Renders only permitted actions; emits refresh after import. (Used by both core lists and the CMS list pages.)
- **`useDataExchange(entityKey?)`** composable + thin api client — `fetchManifest`, `exportEntity({ids?,filters?,all?,format})`, `exportBundle(keys,format)`, `importEntity(file,{mode,dryRun})`, `importBundle(file,{mode,dryRun})`.
- **`downloadBlob()` / `readImportFile()`** helpers — single home for the blob-download + file-read dance duplicated today in `useCmsAdminStore` + `Settings.vue` (DRY).

## fe-admin design (inherits the feature by default)

- **Settings → "Import / Export"** — a new Settings tab rendering `<ImportExportPage/>`. Present on every install; entities appear only if registered + enabled + permitted.
- **Per-list controls** — drop `<ImportExportControls :entity-key …>` into Users, Invoices, Payment methods, Access levels, Email templates; plugins do the same. Lists need row-selection checkboxes where missing (D7).
- **Tab injection (R7)** — new `dataExchangeTabs` key in `vue/src/plugins/extensionRegistry.ts` (mirrors `userEditTabs`/`accessLevelTabs`): `{ id, label, component, order?, requiredPermission? }`; `ImportExportPage` renders core tabs + sorted contributed tabs.
- **Permission gating (R12)** — the Settings entry, every per-list control, and every contributed tab use `requiredPermission`: **no permission ⇒ the nav/burger entry is not rendered and the route is guarded** (redirect/403). The same rule is binding in **fe-user** for any permission-gated surface.

---

## Plugin updates (centralise, may extend)

Each plugin registers an `EntityExchanger` (subclassing `BaseModelExchanger` where possible) in `on_enable()` via DI ([[project_plugin_di_provider_registration]]):

- **`cms` (R3 — keeps its page)** — six entity exchangers (images subclass to emit ZIP+assets) so CMS entities appear on the **General tab** and via **per-list `ImportExportControls`** on each CMS list. **Keeps `cms/import-export`**, rebuilt to render the core components scoped to CMS entities — **one code path, two entry points**. Bespoke `/admin/cms/*/export|import` routes replaced by the generic ones.
- **`subscription`** — `subscriptions` (export-only), `tarif_plans`, `add-ons`.
- **`booking`** — `bookings` (ex/im).
- **`ghrm`** — **`packages` only** for v1.
- **`shop`** — orders + products.
- **`discount`** — promotions/coupons.

Plugin exchangers declare their `cluster` (perms land under that heading) and may override `export`/`import_` for custom shaping — **extension, not core change**.

---

## Permission model (R11/R12)

- **Sales** (`users`, `invoices`): per-entity `<entity>.export` / `.import` / `.export.pii`. Users export without `.export.pii` → PII (incl. nested details) redacted; secrets never exported (any role).
- **Settings** (countries, currencies, access levels, email templates, payment methods, core_settings): `settings.view` (export) / `settings.manage` (import).
- **Superadmin** → all entities, all operations (incl. `replace_all` + PII).
- All permissions auto-registered into `collect_permission_catalog()` (grouped by cluster) and **selectable in the Access Level form**.
- **Gating (R12):** missing permission ⇒ no burger entry + guarded route, in fe-admin **and** fe-user.

## Security

1. Every write path is `require_admin` + the entity's `import_permission`; `replace_all` is superadmin-only, server-enforced.
2. **Secret-stripping mandatory** (D9) — password hashes, tokens, provider keys never leave, even for superadmin.
3. **PII redaction** unless `<entity>.export.pii` held.
4. **Users import** must not elevate admin/roles without `settings.system`.
5. **Invoices/subscriptions export-only** — `import_` raises `UnsupportedOperationError`.
6. Import transactional per entity; partial failure rolled back, reported in `errors[]`; `dry_run` always rolls back.
7. ZIP import: validate `manifest.json`, cap total/extracted size (zip-bomb guard), restrict asset paths to `assets/` (path-traversal guard).
8. **Row cap** (D8) bounds export size; CSV import bounded the same way.
9. **No plugin-config export/import (R6)** — config blobs (secrets) never flow through this subsystem.

## TDD plan (tests FIRST)

- **Backend unit** (MagicMock): registry register/get/`manifest_for` (perm+config+cluster filtering); `BaseModelExchanger` export shape, upsert vs replace_all, dry-run rolls back; export-only raises; secret never serialised; PII redacted without perm; **CSV flatten/parse round-trip**; FK→natural-key; row cap; envelope validate (bad `vbwd_export`/`version` rejected).
- **Backend integration** (`db`): each core exchanger round-trips (export → wipe → import → equal), incl. **users with nested details** and **currencies**; manifest reflects perms (superadmin vs scoped vs none → 403); ZIP bundle round-trip incl. CMS images; dry-run writes nothing; replace_all gated to superadmin; **countries characterisation test** (existing Settings buttons keep working); CLI export/import.
- **Core-agnosticism oracle** green — no `from plugins.*`.
- **fe-core unit:** `ImportExportPage` renders General clusters + contributed `dataExchangeTabs`; gates `replace_all` to superadmin; dry-run preview then confirm; `ImportExportControls` emits selected/all/filter, hides un-permitted actions; `useDataExchange` hits correct endpoints; download/read helpers.
- **fe-admin unit + e2e:** Settings "Import/Export" tab renders; Users export downloads an envelope; import dry-run → preview → confirm reports counts; **permission gating (R12)** — admin without the perm sees **no nav entry and is blocked from the route**; without `.export.pii` → PII redacted; CMS page still works on the shared components.
- **Recipes:** fresh `dev-install` imports default content packs (countries, currencies, email templates); instance boots green (DevOps-first cold start).

## Sub-sprints

- **S46.0 — core seam** (registry + port + envelope + CSV + ZIP + base exchanger + generic routes + permission auto-registration + row cap). `--full` + oracle green.
- **S46.1 — core exchangers** (users+details w/ PII split, invoices-exp, payment_methods, access_levels, email_templates, **currencies**) + **migrate countries**. *(Includes the small prerequisite to **persist core settings**, then the `core_settings` exchanger — R10.)*
- **S46.2 — CLI + content packs** (`flask data-exchange …`; countries/currencies/email-template files for `recipes/`).
- **S46.3 — fe-core components** (`ImportExportPage` w/ General tab + tab slot, `ImportExportControls`, `useDataExchange`, helpers) + build `dist/`.
- **S46.4 — fe-admin wiring** (Settings tab + per-list controls on core lists + `dataExchangeTabs` slot + row-selection checkboxes + **R12 gating** + PII gating).
- **S46.5 — CMS migration (R3)** (six exchangers; CMS page + list controls rebuilt on core components; bespoke routes retired).
- **S46.6 — subscription / booking / ghrm(packages) / shop / discount exchangers** (one PR per plugin repo; each `--plugin <x> --full` green).
- **S46.7 — docs** (REST API + CLI + content-pack authoring + per-instance `enabled_entities`).

## Definition of done

Settings has an **Import / Export** page with a **General** tab (Export + Import blocks, clustered Sales/Settings) plus any tabs extensions contribute; every core list (Users, Invoices, Payment methods, Access levels, Email templates) and migrated plugin lists show perm-gated Export-selected/all/filter + Import via the shared control; **CMS keeps its own page** built on the same components and its entities also appear on the General tab; default manifest matches the tables; **JSON + CSV + ZIP** round-trip; **upsert / dry-run / replace_all** behave per D4; secrets stripped + PII gated per D9; **no plugin-config export exists (R6)**; sales permissions (`<entity>.export`/`.import`/`.export.pii`) and the settings `settings.view`/`settings.manage` usage appear in the **Access Level form** and gate access (superadmin bypass); **R12 gating holds — no permission ⇒ no burger entry, no page — in fe-admin and fe-user**; CLI + REST API documented; recipes seed default content packs on cold install; core stays agnostic (oracle green); `bin/pre-commit-check.sh --full` green on `vbwd-backend`, `vbwd-fe-core`, `vbwd-fe-admin`, and every touched plugin repo.
