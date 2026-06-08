# Unified Data Exchange (import/export for every entity)

**Sprint:** S46 (2026-06-07). **Status:** implemented (S46.0–S46.7); follow-ups listed at the end.

One core abstraction so import/export is a platform feature inherited by every list, every plugin, the CLI, and the install recipes — instead of each entity inventing its own. Entity **data** only; **plugin configuration is explicitly out of scope** (config blobs hold Stripe/provider/OAuth secrets and the GHRM key path — exporting them would exfiltrate secrets).

## The seam (core, agnostic)

`vbwd/services/data_exchange/`:

- **`port.py`** — `EntityExchanger(ABC)`: `entity_key`, `label`, `cluster` (`"sales"|"settings"|"content"`), `natural_key`, `supports_export/import`, `supported_formats` (`{"json"}` or `{"json","csv"}`), `secret_fields`, `pii_fields`, `export(selector, *, include_pii) -> Envelope`, `import_(payload, *, mode, dry_run) -> ImportResult`, and `export_permission`/`import_permission`/`pii_export_permission`. Export-only exchangers raise `UnsupportedOperationError` from `import_` (Liskov). Plus `ExportSelector`/`Envelope`/`ImportResult` dataclasses.
- **`registry.py`** — `DataExchangeRegistry` DI singleton `data_exchange_registry`: `register`/`unregister`/`clear`/`get`/`all` + `manifest_for(user)` (perm- and config-filtered, clustered, with `can_export`/`can_import`/`can_export_pii`; superadmin bypasses).
- **`envelope.py`** — VBWD envelope build/validate + CSV (de)serialise + ZIP bundle (single DRY home), with zip-bomb + path-traversal guards.
- **`base_model_exchanger.py`** — generic `BaseModelExchanger` for the common "one model + repo, upsert by natural key" case (UUID/secret strip, PII redaction, FK→natural-key, row cap, CSV flatten). Core + plugins subclass it.

**Core never imports `plugins.*`.** Core ships the registry, port, generic routes, CLI, and the core entities; plugins register their own exchangers at `on_enable()` via DI. Enforced by `tests/unit/test_core_agnosticism.py` + `test_core_no_domain_vocabulary.py`.

## The VBWD envelope

**JSON** (natural-key fields; UUIDs + secrets stripped; FKs serialised as the referent's natural key):
```json
{ "vbwd_export": "currencies", "version": 1, "exported_at": "…", "instance": "main",
  "format": "json", "currencies": [ { "code": "EUR", "name": "Euro", … } ] }
```
**CSV** — flat header + one row per record; only for entities whose `supported_formats` includes `csv`. A bare CSV carries no envelope metadata — the target entity comes from the upload context (the entity's endpoint/CLI arg).
**ZIP bundle** — `manifest.json` (contents + versions + instance) + one `<entity>.json|csv` per entity + an `assets/` dir for binaries (e.g. CMS images). No cross-entity ordering — each entity envelope is independent; unresolved refs land in `errors[]`.

**Import result:** `{ entity, mode, dry_run, created, updated, skipped, errors:[{row, reason}] }`.

**Modes:** `upsert` (default — insert new / update existing by natural key) · `replace_all` (drop-then-import; **superadmin-only** via the API, server-enforced) · `dry_run=true` computes the counts **without writing** (rolls back) for a preview-then-confirm UX.

## REST API (`/api/v1/admin/data-exchange/`, `require_admin`)

| Endpoint | Body | Returns |
|---|---|---|
| `GET /manifest` | — | clustered, perm+config-filtered entities with `can_*` flags |
| `POST /<key>/export` | `{ids?, filters?, all?, format?}` | JSON/CSV download; PII redacted unless caller holds the PII perm |
| `POST /<key>/import` | JSON/CSV or multipart + `{mode, dry_run}` | `ImportResult`; `replace_all` requires superadmin |
| `POST /export` | `{entities:[…], format?}` | ZIP bundle (un-permitted entities dropped + reported) |
| `POST /import` | multipart ZIP + `{mode, dry_run}` | per-entity `ImportResult[]` |

## CLI (`flask data-exchange …`)

```
flask data-exchange list
flask data-exchange export <entity> [--all | --ids id1,id2,…] [--format json|csv] [--include-pii] [-o FILE]
flask data-exchange import <entity> <FILE> [--mode upsert|replace_all] [--dry-run]
```
A thin adapter over the same exchangers + envelope the routes use. `replace_all` is allowed from the CLI (operator tool) but prints a loud warning. Runs in the app context, so all core + plugin exchangers are registered.

## Frontend (fe-admin)

- **`Settings` sidebar group → "Import / Export"** (last item, route `/admin/import-export`, perm `settings.view`) renders the fe-core `ImportExportPage` (General tab: Export + Import blocks, grouped by cluster; plus any tabs contributed via the `dataExchangeTabs` extension slot).
- **Per-list controls** — `ImportExportControls` on Users, Invoices, Payment methods, Access levels (Export selected/all/filter + Import). Components live in `vbwd-fe-core` (`useDataExchange`, `downloadBlob`/`readImportFile`, the `DataExchangeApi` port); fe-admin supplies a `DataExchangeApi` adapter over its `ApiClient`.
- **Permission gating (binding):** no permission ⇒ no nav/burger entry **and** the route is guarded (redirect/403) — fe-admin and fe-user alike.

## Permissions

- **sales** entities (`users`, `invoices`, plugin sales entities): per-entity `<key>.export` / `.import` / `.export.pii`. Export without `.export.pii` ⇒ PII (incl. nested `users.details`) redacted; secrets never exported (any role).
- **settings** entities (countries, currencies, access_levels, email_templates, payment_methods): reuse `settings.view` (export) / `settings.manage` (import).
- **Plugin** entities reuse the plugin's existing permission names (e.g. cms uses `cms.pages.view/manage`, `cms.images.*`; subscription uses `subscription.plans.view/manage`; etc.).
- Permissions are auto-derived from the registry into `collect_permission_catalog()` (grouped by cluster) and appear in the **Access Level form**. **Superadmin** bypasses (all entities, all operations, incl. `replace_all` + PII).

## Per-instance enablement

A static allow-list `data_exchange.enabled_entities` filters the manifest (default = all). Lets an instance expose only the entities it wants.

## Security

Secret-stripping is mandatory (password hashes, tokens, provider keys, GHRM key, Stripe keys — never leave, even for superadmin). PII redacted unless the PII perm is held. Invoices/subscriptions/shop-orders are **export-only**. Import is transactional per entity (partial failure rolled back, reported); `dry_run` always rolls back. ZIP import validates `manifest.json`, caps extracted size (zip-bomb), restricts assets to `assets/` (path-traversal). Row cap (default 10,000/entity/op, config-overridable) bounds export/CSV-import size.

## Registered entities (current)

**Core (7):** `users` (+nested `details`, PII-gated, role-change requires `settings.system`), `invoices` (export-only), `payment_methods` (secret `config` stripped), `access_levels` (`Role` + permission grants), `email_templates` (file-backed → `var/assets/core/email/templates/`), `currencies`, `countries` (wraps `country_io`).
**cms (6):** `cms_posts` (+ S55 `content_blocks` + `page_assignments`), `cms_terms`, `cms_layouts`, `cms_widgets`, `cms_styles`, `cms_images` (binary via base64 / ZIP `assets/`).
**subscription:** `subscription_plans`, `subscription_addons`, `subscriptions` (export-only). **booking:** `bookings`. **ghrm:** `ghrm_packages` (v1). **shop:** `shop_products`, `shop_orders` (export-only). **discount:** `discount_rules`, `discount_coupons`.

## Extending — add an exchanger from a plugin

```python
# plugins/<name>/.../data_exchange/<name>_exchangers.py
class MyThingExchanger(BaseModelExchanger):  # or subclass EntityExchanger directly
    entity_key = "my_things"; cluster = "sales"; natural_key = "code"
    # secret_fields / pii_fields / supported_formats; override export_permission/import_permission
    # to reuse the plugin's existing perms; delegate to existing services where they exist (DRY)

# in the plugin's on_enable():
register_my_exchangers(db.session)  # registers into data_exchange_registry (idempotent/clear-safe)
```
A fe-admin tab for the plugin's entities is added by registering into the `dataExchangeTabs` extension slot (`vue/src/plugins/extensionRegistry.ts`). The entities also appear automatically on the General tab via the manifest.

## Follow-ups (flagged, not in S46 v1)

- **`core_settings` exchanger** — deferred to after **[S57](../dev_log/20260607/sprints/s57-persist-core-settings.md)** (core settings now persist to `var/core/vbwd_settings.json`); add the exchanger as an S46 fast-follow.
- **Content packs for recipes** — the CLI is the mechanism; decide whether content packs replace or supplement the existing idempotent seeders (`flask seed-countries`, etc.) before wiring `recipes/`.
- **fe-admin CMS `dataExchangeTabs` tab** — CMS entities already appear on the General tab; a dedicated CMS tab is optional polish.
- **fe-core `ApiClient.responseType`** — the small addition enabling blob export must land in the **`vbwd-fe-core` repo** to reach prod.
- **Retire bespoke routes** — CMS `/admin/cms/*/export|import` and Access-levels legacy export/import coexist with the generic path (kept for e2e); retire later.
