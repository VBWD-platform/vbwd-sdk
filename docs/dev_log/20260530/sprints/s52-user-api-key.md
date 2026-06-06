# S52 — User API Keys (core mechanism + CMS content-ingestion consumer)

**Date:** 2026-06-06
**Repos touched:** `vbwd-backend` (**core** `vbwd/`), `vbwd-fe-core` (shared
`ApiKeysManager` component), `vbwd-fe-admin` (default User-edit tab),
`vbwd-fe-user` (permission-gated "Manage API" page + nav item), `plugins/cms`
(consumer only).
**Status:** PLANNED
**Supersedes:** the 2026-06-05 draft that built API keys *inside* the cms plugin.
**Related:** **S50 — Domain vocabulary leaves core** (this sprint conforms to and
reinforces S50's decision rule; see *Relationship to S50* below).

## Goal

API keys become a **core platform feature**, not a CMS plugin feature. A user can
hold scoped, IP-restricted API keys; **plugins register the scopes** their
endpoints require and authenticate those endpoints with the core guard. CMS is the
first consumer: it registers a `cms:posts:create` scope and exposes an ingestion
endpoint that creates a post/page **owned by the key's user**.

Two human surfaces, **one shared UI**:
- **fe-admin** ships a **default "API" tab** on the User edit page (alongside the
  existing native *Account* / *Invoices* tabs). An admin manages **any** user's
  keys.
- **fe-user** ships a **permission-gated "Manage API" page**. A user holding the
  **`manage_api`** permission sees a **"Manage API"** item **immediately before
  "Profile"** in the dashboard user-dropdown, opening a page that is **identical
  to the fe-admin API tab** (same `vbwd-fe-core` component) where the user
  **creates and deletes their own** keys.
- A key holder `POST`s a payload to the **cms** ingestion endpoint —
  `type` (`post`|`page`), `title`, `slug`, `categories`, `tags`, SEO fields,
  base64 `image` — and a `cms_post` is created, authored as the key's user.

## Why this is core (and still agnostic)

API-key authentication is an **auth mechanism**, the same class of cross-cutting
concern as JWT in `vbwd/middleware/auth.py`. The mechanism is generic; only the
**scope strings** and the **protected endpoints** are domain-specific, and those
live in plugins.

Core owns the *mechanism*; plugins own the *meaning*:

| Concern | Owner | Agnostic? |
|---|---|---|
| `api_key` model / hashing / token format | core | yes — no domain fields |
| `ApiKeyService` (generate/verify/scope/IP) | core | yes |
| `require_api_key(scope)` guard | core | yes — scope is an opaque string |
| **Available scopes** (catalogue) | **plugins**, via a core *scope registry* | core ships **zero** domain scopes |
| Key-management UI (`ApiKeysManager`) | core (fe-core, reused by admin+user) | yes — scope checkboxes from the registry endpoint |
| `manage_api` / `api_keys.manage` permissions | core | yes — about API keys, not a domain |
| `cms:posts:create` scope + ingestion endpoint | **cms plugin** | gnostic (correct) |

The scope registry mirrors the **existing** `vbwd/services/permission_catalog.py`
pattern verbatim: "core + each enabled plugin's declared scopes, collected
through the injected `plugin_manager` — never by importing a plugin module."

## Relationship to S50 (domain vocabulary leaves core)

S50's decision rule: **"A port in core is fine when core only ROUTES through it;
it is a leak when core READS a domain field through it."** S52 sits cleanly on the
*allowed* side:

- **`api_scope_registry` is a Kind-1 generic registry** (S50's "STAY" column,
  same class as `deletion_dependency_registry` / `demo_data_registry`): core routes
  a generic question ("what scopes exist?") and forwards **opaque scope dicts it
  never interprets**. Core never parses `cms:posts:create`; it only string-matches
  a key's allow-list against the scope an endpoint demands.
- **Vocabulary:** `api_key`, `scope`, `ip_whitelist`, `manage_api` are
  domain-neutral. They are **not** in S50's banned set (`subscription`, `tarif`,
  `plan`, `seo`, `sitemap`, `catalog`), so S50.5's `test_core_no_domain_vocabulary.py`
  allowlist needs **no** change — provided the core scope code never hardcodes a
  plugin term (`cms`, `posts`). The RED tests below assert that.
- **Sequencing:** S52 only **adds** generic core files; S50 only **removes**
  domain files. No file conflicts → S52 can land independently of / in parallel
  with S50. Both oracles must stay green at every step: `test_core_agnosticism.py`
  (no `from plugins.*` in `vbwd/`) **and** S50's `test_core_no_domain_vocabulary.py`
  (when present, in report-or-enforcing mode).

## Binding engineering requirements (restated — non-negotiable)

TDD-first (RED → GREEN → refactor, every increment) · DevOps-first (schema only
via Alembic; the **core** `api_key` migration lives in `vbwd-backend/alembic/versions/`
and **must resolve standalone** — chained off a core revision, never anchored on a
plugin head; up/down/up validated) · **SOLID** · **DI** (repos/services injected;
no globals) · **DRY** (one core `ApiKeyService`/guard; **one** shared fe-core
`ApiKeysManager` component reused by admin+user; cms reuses its own
`PostService`/`TermService`/`CmsImageService`) · **Liskov** (`require_api_key` is
substitutable for `require_auth` — sets the same `g.user_id`/`g.user`) · **clean
code** (full readable names) · **NO OVERENGINEERING** (narrowest change that
satisfies the requirement). Quality guard: `bin/pre-commit-check.sh` — `--full`
green on every touched repo = "done". **Build order:** `vbwd-fe-core` builds first
(generates `dist/`) before fe-admin / fe-user can import `ApiKeysManager`.
Canonical statement: `docs/dev_log/20260525/sprints/_engineering-requirements.md`.

## Architecture & decisions

### Core: the mechanism

- **Model** `vbwd/models/api_key.py` — table **`api_key`** (renamed from the old
  `cms_api_key`; no CMS-specific column).
- **Repository** `vbwd/repositories/api_key_repository.py` — `ApiKeyRepository`
  (`find_by_hash`, `find_by_user`, `find_by_id`, `save`, `revoke`, `delete`).
- **Service** `vbwd/services/api_key_service.py` — `ApiKeyService` (generate /
  hash / verify / scope / IP). Pure logic, no Flask import (SRP/testability); repo
  injected.
- **Guard** `vbwd/middleware/api_key_auth.py` — `require_api_key(scope)`.
  **Liskov:** on success it sets `g.user_id` **and** `g.user` exactly like
  `require_auth`, so `require_permission(...)` and every downstream handler are
  auth-mechanism-agnostic. Marks `decorated_function.requires_auth = True` for the
  S30 route catalogue.
- **Scope registry** `vbwd/services/api_scope_registry.py` —
  `collect_api_scopes(*, plugin_manager=None)`; returns `{"core": [], "<plugin>":
  [{key, label, description, user_grantable}, ...]}`. Core list is **empty**. A
  plugin declares `api_scopes` (same shape as `admin_permissions`) and the registry
  reads it via `plugin_manager.get_enabled_plugins()`. **DRY**: same collector
  shape as `permission_catalog.py`. `user_grantable` lets a scope be self-granted
  on the user page (admins may grant any registered scope).
- **Permissions** added to `CORE_PERMISSIONS` (`vbwd/routes/admin/access.py`):
  - `api_keys.manage` — admin manages **any** user's keys (admin routes/tab).
  - `manage_api` — user self-services **own** keys (gates the fe-user nav item,
    page route, and the user self-service backend routes — defence-in-depth, never
    FE-only). Grantable to user roles by an admin.
- **Routes** `vbwd/routes/api_keys.py` (user self-service) +
  `vbwd/routes/admin/api_keys.py` (admin). Registered in the core route map.
- **Migration** `vbwd-backend/alembic/versions/20260606_xxxx_create_api_key.py` —
  chains off the current **core** head (`20260602_1000_seed_marker`); resolves with
  **no plugins** present (per the migration-graph-fragmentation rule).

### Shared UI: `ApiKeysManager` in `vbwd-fe-core`

One presentational component, `vbwd-fe-core/src/components/ui/ApiKeysManager.vue`,
exported through `ui/index.ts` → `vbwd-view-component`. It is **data-in /
events-out** (the prevailing fe-core pattern — like `Table.vue`), so it owns no
HTTP:

- **Props:** `keys: ApiKey[]`, `availableScopes: ApiScope[]`,
  `canDelete: boolean` (admin+user: true), `loading`, `error`, `createdPlaintext?`
  (the one-time secret to reveal after a create).
- **Emits:** `create({ label, scopes, ipWhitelist })`, `revoke(id)`,
  `delete(id)`, `dismiss-plaintext`.
- Renders: a keys table (prefix, label, scopes, IP whitelist, active,
  last-used), a create form (label, scope checkboxes from `availableScopes`,
  IP-whitelist textarea), and a one-time plaintext reveal with a copy affordance.
- Styling via `var(--vbwd-*)` design tokens; dark-mode aware.

Each app wraps it with its **own** store/endpoints, so the admin tab and the user
page are **literally the same component** → "identical" by construction (DRY).

### Core (fe-admin): default "API" tab

`UserEdit.vue` already renders native hardcoded tabs (*Account*, *Invoices*) then
the `extensionRegistry.getUserEditTabs()` loop. The API tab is added as **one more
native tab** (hardcoded button + `v-show="activeTab === 'api'"` panel) — **not** a
registry contribution, so it ships by default. The panel renders the fe-core
`ApiKeysManager`, wired to a core store `stores/apiKeys.ts` (admin actions) that
calls the `api` singleton (`/admin/users/<id>/api-keys`, scopes from
`/admin/api-keys/scopes`). The tab is shown only to admins with `api_keys.manage`.

### Core (fe-user): permission-gated "Manage API" page + nav item

- **Nav item:** in `vue/src/layouts/UserLayout.vue`, insert a `<router-link
  to="/dashboard/api-keys" class="user-dropdown-item">{{ $t('nav.manage_api')
  }}</router-link>` **immediately before** the hardcoded "Profile" link, guarded
  `v-if="hasUserPermission('manage_api')"` (helper from `@/api`).
- **Route:** `vue/src/router/index.ts` —
  `{ path: '/dashboard/api-keys', name: 'manage-api', component: () =>
  import('../views/ManageApi.vue'), meta: { requiresAuth: true,
  requiredUserPermission: 'manage_api' } }`. The existing `beforeEach` guard
  enforces both auth and the permission (redirects to `/dashboard` otherwise).
- **View:** `ManageApi.vue` renders the **same** fe-core `ApiKeysManager`, wired to
  a core store `stores/apiKeys.ts` (user self-service: own keys, scopes from
  `/api/v1/api-keys/scopes`). The user can **create and delete** own keys (and
  revoke). Server-side, the routes are current-user-scoped + `manage_api`-gated.

> Decision: this **replaces** the earlier "profile card" idea — a dedicated,
> permission-gated page reusing the admin component is cleaner, satisfies
> "identical to the fe-admin tab", and keeps `/dashboard/profile` focused on
> identity. `profileSectionsRegistry` is untouched.

### CMS plugin: the consumer

- Declares its scope on the cms plugin object:
  `api_scopes = [{"key": "cms:posts:create", "label": "Create CMS posts/pages",
  "description": "…", "user_grantable": True}]` (read by the core scope registry).
- **Ingestion endpoint** `POST /api/v1/cms/api/posts` in `plugins/cms/src/routes.py`,
  decorated with the **core** `require_api_key("cms:posts:create")`; reads
  `g.user_id` as the author.
- `ContentIngestService` (plugin) **composes** `PostService.create_post`,
  `TermService` find-or-create, `CmsImageService.upload_image` — owns **no**
  persistence (SRP/DRY).

### Data model — `api_key` (core, generic)
| column | type | notes |
|---|---|---|
| id | UUID PK | BaseModel |
| user_id | UUID FK → vbwd_user.id, ON DELETE CASCADE, indexed | the **owner**; protected calls act as this user |
| label | String(120) | human label ("CI pipeline") |
| key_hash | String(64), unique, indexed | **sha256 of the token** — plaintext never stored |
| key_prefix | String(16) | first chars of the token (e.g. `vbwdk_ab12`) for list display + lookup hint |
| scopes | JSON (list[str]) | explicit allow-list of scope keys (e.g. `["cms:posts:create"]`) |
| ip_whitelist | JSON (list[str]) | exact IPs and/or CIDRs; empty = any IP |
| is_active | Boolean, default true | revoke = set false (audit row kept) |
| created_by_user_id | UUID, nullable | admin who created it, else == user_id (self-service) |
| last_used_at | DateTime, nullable | stamped by the guard |
| created_at / updated_at / version | BaseModel | |

**Token format:** `vbwdk_` + `secrets.token_urlsafe(32)` (generic core prefix).
Returned **once** at creation; thereafter only `key_prefix` is shown. Lookup by
`key_hash = sha256(presented)`. **Scope semantics:** `has_scope` = exact
membership; empty `scopes` ⇒ no scoped action authorized (deny). No "default set".

### Endpoints

**Core — key management** (mechanism only):
| method | path | auth | purpose |
|---|---|---|---|
| GET | `/api/v1/admin/api-keys/scopes` | `require_auth` + `require_permission('api_keys.manage')` | scopes catalogue for the admin tab |
| GET | `/api/v1/admin/users/<user_id>/api-keys` | admin | list a user's keys |
| POST | `/api/v1/admin/users/<user_id>/api-keys` | admin | create key for a user → plaintext once |
| POST | `/api/v1/admin/api-keys/<id>/revoke` | admin | deactivate |
| DELETE | `/api/v1/admin/api-keys/<id>` | admin | delete |
| GET | `/api/v1/api-keys/scopes` | `require_auth` + `require_permission('manage_api')` | user-grantable scopes for the Manage-API page |
| GET | `/api/v1/api-keys` | `require_auth` + `manage_api` | list own keys |
| POST | `/api/v1/api-keys` | `require_auth` + `manage_api` | create own key → plaintext once |
| POST | `/api/v1/api-keys/<id>/revoke` | `require_auth` + `manage_api` + owner check | revoke own |
| DELETE | `/api/v1/api-keys/<id>` | `require_auth` + `manage_api` + owner check | delete own |

**CMS plugin — protected by the core guard:**
| method | path | auth | purpose |
|---|---|---|---|
| **POST** | **`/api/v1/cms/api/posts`** | **`require_api_key('cms:posts:create')`** | **ingestion** |

### Ingestion payload (`POST /api/v1/cms/api/posts`)
```jsonc
{
  "type": "post",                     // optional, default "post" — "post" | "page" or any registered post type
  "title": "My headline",             // required
  "slug": "my-headline",              // optional → slugified from title
  "excerpt": "…",                     // optional
  "content_html": "<p>…</p>",         // optional
  "source_css": ".x{}",               // optional (CSS tab)
  "categories": ["News", "Tech"],     // optional — find-or-create by name
  "tags": ["saas", "vue"],            // optional — find-or-create by name
  "seo": { "meta_title": "…", "meta_description": "…", "og_image_url": "…", "canonical_url": "…", "robots": "index,follow" },
  "image": { "base64": "<data>", "filename": "hero.jpg", "mime_type": "image/jpeg" },
  "status": "draft"                   // optional, default "draft" (see security note)
}
```
Response `201`: `{ "id", "slug", "type", "status", "featured_image_url" }`.
Errors: `401` (no/invalid key), `403` (IP not whitelisted / scope missing),
`400` (bad payload / unknown post type / undecodable image).
**Default status = `draft`** (API content reviewed before going public).

---

## Sub-sprints (each: RED tests first → narrowest GREEN → `--full` gate)

### S52.0 — core `api_key` model + repository + migration
**RED (unit, MagicMock):** `to_dict` shape (no `key_hash` leak — only
`key_prefix`); repo `find_by_hash`, `find_by_user`, `find_by_id`, `save`,
`revoke`, `delete`.
**RED (integration, real PG):** persist + `find_by_hash`; cascade delete with the
owning user; migration **up/down/up** (mirror an existing core migration test).
**GREEN:** `vbwd/models/api_key.py`, `ApiKeyRepository`, core migration chaining
off `20260602_1000_seed_marker`, resolving plugin-free. Both oracles green.

### S52.1 — core `ApiKeyService` (generate / hash / verify / scope / IP)
**RED (unit, no DB):** `generate()` (plaintext once, hash persisted, `vbwdk_`
prefix); `verify(token)` (hash match + active, constant-time);
`is_ip_allowed` (empty ⇒ true, exact, CIDR via `ipaddress`); `has_scope` (exact
membership, empty ⇒ deny); `touch`; `revoke(id, owner_id=None)` (owner-guarded).
**GREEN:** `vbwd/services/api_key_service.py` — `secrets` + `hashlib.sha256` +
`hmac.compare_digest` + `ipaddress`; repo injected; no Flask import.

### S52.2 — core scope registry + scopes endpoints
**RED (unit):** `collect_api_scopes(plugin_manager=fake)` → `{"core": [],
"<plugin>": [...]}`; core empty; a plugin's `api_scopes` surfaced; **no plugin
import**; **no hardcoded `cms`/`posts` string** in `vbwd/` (vocab oracle).
**RED (integration):** `GET /api/v1/admin/api-keys/scopes` (gated `api_keys.manage`)
and `GET /api/v1/api-keys/scopes` (gated `manage_api`, returns only
`user_grantable` scopes). **GREEN:** `vbwd/services/api_scope_registry.py` mirroring
`permission_catalog.py`; both endpoints.

### S52.3 — core `require_api_key(scope)` guard (Liskov-substitutable)
**RED (unit, Flask test client + fake service):** blank/missing `X-API-Key`
(and `Authorization: Bearer`) → 401; unknown/inactive → 401; IP not whitelisted →
403; scope missing → 403; on pass `g.user_id` **and** `g.user` set (parity with
`require_auth`) + `last_used_at` stamped once; trusted-proxy `X-Forwarded-For`
honoured only behind the configured proxy.
**GREEN:** `vbwd/middleware/api_key_auth.py`; resolves via `ApiKeyService`; never
logs the token; `requires_auth = True`.

### S52.4 — core permissions + key-management routes
**RED (integration):** `api_keys.manage` + `manage_api` present in the core
permission catalogue/seeder; admin CRUD on any user; user self-service is
`manage_api`-gated **and** owner-scoped (acting on another user's key → 403/404; a
user without `manage_api` → 403); plaintext only on create; revoke flips
`is_active`; delete removes.
**GREEN:** `manage_api`/`api_keys.manage` in `CORE_PERMISSIONS` + RBAC seeder;
`vbwd/routes/api_keys.py` + `vbwd/routes/admin/api_keys.py` (factory-instantiated
services with `db.session`); permission + owner guards.

### S52.5 — fe-core shared `ApiKeysManager` component *(build first)*
**RED (vitest, fe-core):** renders a keys list from `keys` prop; create form emits
`create({label, scopes, ipWhitelist})`; scope checkboxes come from
`availableScopes`; one-time plaintext reveal shows `createdPlaintext` with a copy
button then emits `dismiss-plaintext`; `revoke`/`delete` emit ids; respects
`loading`/`error`. (Mirror `tests/unit/components/ui/Input.spec.ts`.)
**GREEN:** `vbwd-fe-core/src/components/ui/ApiKeysManager.vue` (presentational,
props-in/events-out, `var(--vbwd-*)` tokens) + export via `ui/index.ts`. Build
`dist/` so the apps can import it.

### S52.6 — fe-admin default "API" tab (consumes the shared component)
**RED (vitest):** a **native** API tab renders on `UserEdit.vue` by default (no
registry needed), visible with `api_keys.manage`; it mounts `ApiKeysManager` and
wires its events to the admin store (create/revoke/delete the **target** user's
keys); scopes loaded from `/admin/api-keys/scopes`.
**GREEN:** hardcoded tab button + `v-show` panel in `UserEdit.vue` (alongside
Account/Invoices); `stores/apiKeys.ts` (admin) calling the `api` singleton.

### S52.7 — fe-user "Manage API" page + permission-gated nav item
**RED (vitest):**
- The "Manage API" `router-link` to `/dashboard/api-keys` renders in the
  user-dropdown **immediately before** "Profile" **iff**
  `hasUserPermission('manage_api')` is true; hidden without the permission.
- `ManageApi.vue` (route `meta.requiredUserPermission = 'manage_api'`) mounts the
  **same** `ApiKeysManager` and wires its events to the user store — user
  **creates and deletes** own keys (and revokes); scopes from
  `/api/v1/api-keys/scopes`.
- Router guard redirects `/dashboard/api-keys` → `/dashboard` when the permission
  is absent.
**GREEN:** nav `v-if` insert in `UserLayout.vue`; route in `router/index.ts`;
`views/ManageApi.vue`; `stores/apiKeys.ts` (user self-service); `nav.manage_api`
i18n key.

### S52.8 — cms consumer: scope registration + ingestion service + endpoint
**RED (unit):** cms plugin exposes `api_scopes` containing `cms:posts:create`
(asserted via the core registry with a fake manager). `ContentIngestService.ingest(payload, user_id)`:
`title` required → 400; categories/tags find-or-create by name (reuse `TermService`,
no dup); `image.base64` (data-URL tolerated) → `CmsImageService.upload_image` →
`featured_image_url`, bad base64 → 400; SEO mapped; `source_css` carried;
`author_id = g.user_id`; `status` default `draft`; created via
`PostService.create_post` (slug/type validation inherited; `type: "page"`
supported; unknown type → 400).
**RED (integration):** `POST /api/v1/cms/api/posts` with a real core key scoped
`cms:posts:create` → 201 + post/page + terms + image persisted; key missing the
scope → 403; no key → 401.
**GREEN:** declare `api_scopes` on the cms plugin; ingestion route decorated with
the **core** `require_api_key("cms:posts:create")`; thin `ContentIngestService`
that **owns no DB writes**.

### S52.9 — docs, example, gate
README/curl example (`X-API-Key` + payload for a post **and** a page); report
under `docs/dev_log/.../reports/`; `bin/pre-commit-check.sh --full` green on
**backend + fe-core + fe-admin + fe-user** (build fe-core first).

---

## Security (must-haves, in scope)
- **Never store or log plaintext keys.** Store sha256; show plaintext once.
- **Constant-time** hash compare on lookup (`hmac.compare_digest` on hashes).
- **IP whitelist** enforced before scope; CIDR via stdlib `ipaddress`; trust
  forwarded-for only behind the configured proxy.
- **Owner isolation + permission gate:** user routes only touch the caller's keys
  **and** require `manage_api` server-side (FE gating is UX, not security); a user
  may only self-grant `user_grantable` scopes; admins may grant any registered
  scope.
- **Revoke is immediate** (guard checks `is_active` every request).
- **No privilege escalation via scope:** a scope authorizes a plugin endpoint, not
  admin permissions; `require_permission` still gates admin routes.

## Explicitly OUT of scope (no overengineering)
- Per-key rate limiting / quotas (future sprint; flask-limiter seams exist).
- Key rotation automation, expiry dates (add `expires_at` only if asked).
- Nested/hierarchical RBAC for scopes (flat string keys only).
- Bulk ingestion / async jobs (single post per request).
- Editing/deleting posts via API (create-only in v1).
- Migrating any *other* plugin onto the core guard (cms is the only consumer; the
  seam is ready for others).

## SOLID / DI / Liskov / DRY mapping
- **S**: core `api_key` model ↔ repo ↔ `ApiKeyService` ↔ guard ↔ routes are
  separate; the scope registry is its own collector; `ApiKeysManager` is pure UI;
  cms `ContentIngestService` composes, never persists.
- **O**: scopes are **data** declared by plugins, not code — a new scope/consumer
  needs no core change. New surfaces reuse `ApiKeysManager` unchanged.
- **L**: `require_api_key` mirrors `require_auth`'s contract (same `g.user_id`/
  `g.user`), so downstream code and `require_permission` are mechanism-agnostic.
- **I**: narrow ports — cms ingest depends only on `create_post`, term
  find-or-create, `upload_image`; the guard depends only on `ApiKeyService`;
  `ApiKeysManager` depends only on its props/emits.
- **D**: services take repos/collaborators by constructor injection; the scope
  registry takes `plugin_manager` injected (never imports a plugin); each app
  injects its own store into the shared component.
- **DRY**: one core `ApiKeyService` for admin + user + guard; **one** fe-core
  `ApiKeysManager` makes the admin tab and the user page identical; scope registry
  reuses the `permission_catalog` collector shape; zero duplication of
  post/term/image logic in cms.