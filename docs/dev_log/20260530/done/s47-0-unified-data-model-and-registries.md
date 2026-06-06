# S47.0 — Unified data model + post-type & term-type registries + CRUD + cms_page migration

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Status:** DRAFT — 2026-06-03
**Repos:** `vbwd-plugin-cms` (backend). *(fe-admin authoring is 47.6; public render is 47.3.)*
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** · **plugin baseline config files** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin cms --full` GREEN.

---

## 1. Goal

The foundation: the unified `post` entity (typed), the unified `term` taxonomy (typed), the two registries that make both extensible, the repos/services, the admin + public read routes the later sprints consume, and the **data migration** that folds the live `cms_page`/`cms_category` rows into the new tables. **No public rendering, no SEO pipeline, no widgets yet.**

## 2. Backend — `plugins/cms/src/` (cms keeps the `src/` convention)

### 2.1 Models (`plugins/cms/src/models/`)
- **`cms_post`** (`BaseModel`): `type` (str, indexed — `page`/`post`/custom), `slug` (indexed), `title`, `excerpt` (Text), `content_json` (JSON — block body, S47.3), `content_html` (Text — server-rendered narrative, the crawlable body), `type_data` (JSON, nullable — type-specific fields), `author_id` (UUID FK `vbwd_user.id`, `ondelete SET NULL`), `parent_id` (self-FK, nullable, indexed — **hierarchical post-types only**), `status` (str/enum, indexed — `draft·pending·scheduled·published·private·trash`, default `draft`), `published_at` (tz dt, null), `language` (str, default `en`), `translation_group_id` (UUID, null, indexed — hreflang), `sort_order`. **SEO columns mirrored from `cms_page`:** `meta_title/description/keywords`, `og_*`, `canonical_url`, `robots` (default `index,follow`), `schema_json`, **`seo_excluded`** (bool, default `False`). `to_dict()` explicit + isoformat timestamps. **Unique on `(type, slug)`** (a slug is unique within its type).
- **`cms_term`** (`BaseModel`): `term_type` (str, indexed — `category`/`tag`/custom), `slug` (indexed), `name`, `parent_id` (self-FK, null → hierarchy for categories; flat for tags), `description` (Text, null), `seo_excluded` (bool, default `False`), `sort_order`. **Unique on `(term_type, slug)`**.
- **`cms_post_term`**: junction `(post_id, term_id)` both FK + `ondelete CASCADE`, unique together.

Migration in **`plugins/cms/migrations/versions/`** (register path in `alembic.ini`); revision id ≤ 32 chars; resolves standalone.

### 2.2 Registries (agnostic extensibility — the OCP seam)
- `plugins/cms/src/services/post_type_registry.py` — `register_post_type(PostType(key, label, routable: bool, hierarchical: bool = False, default_template: str|None))` + `list_post_types()`. cms registers built-ins **`page`** (`hierarchical=True`) + **`post`** (`hierarchical=False`). A post's `type` must be registered (fail-fast on unknown at create — Liskov); **`parent_id` is rejected unless the type is `hierarchical`**, the parent must itself be a hierarchical-type post, and **parent cycles are refused**. Hierarchical pages resolve **nested URLs** by walking the parent chain (`/about/team`).
- `plugins/cms/src/services/term_type_registry.py` — `register_term_type(TermType(key, label, hierarchical: bool))` + `list_term_types()`. cms registers **`category`** (hierarchical) + **`tag`** (flat). Other plugins register more — **zero cms change** to add a taxonomy or a post type.

### 2.3 Repositories + services
`PostRepository` (by `(type, slug)`, by nested path, by term, paginated by status, by id), `TermRepository` (by type, by slug, children), `PostTermRepository`. `PostService` (create/update; **status transitions** `draft ↔ pending ↔ scheduled ↔ published ↔ private → trash` with validation; slug uniqueness within type; **parent/hierarchy validation**; term assignment; type validation via the registry; **any status change or content edit fires a `content.changed` hook** consumed by the 47.1 prerender writer), `TermService` (CRUD, type validation via the registry). DI via factory functions in `routes.py` using `db.session`; **`on_enable` registers all repos as DI providers** on the container, **plus a TESTING-guarded scheduler tick** that publishes due `scheduled` posts (`published_at` passed → `status=published` + fire `content.changed`) — `if not current_app.config.get("TESTING")` (platform scheduler-guard pattern).

### 2.4 Routes (`plugins/cms/src/routes.py`, blueprint, absolute paths)
- **Admin** (`require_permission("cms.manage")`; declared via the plugin's `admin_permissions` so RBAC picks it up): `GET/POST /api/v1/admin/cms/posts`, `GET/PUT/DELETE /api/v1/admin/cms/posts/<id>`, publish/unpublish; `GET/POST /api/v1/admin/cms/terms`, `PUT/DELETE /api/v1/admin/cms/terms/<id>`; `GET /api/v1/admin/cms/post-types`, `GET /api/v1/admin/cms/term-types` (from the registries).
- **Public read** (status **`published`** only; **`private`** requires an authorized session; `draft`/`pending`/`scheduled`/`trash` never public): `GET /api/v1/cms/posts` (paginated, `?type=&term_type=&term_slug=`), `GET /api/v1/cms/posts/<path:slug>?type=` (single; resolves **nested page paths** like `/about/team` via the parent chain for hierarchical types), `GET /api/v1/cms/terms?type=`.

### 2.5 Plugin wiring
`__init__.py` `BasePlugin` (`admin_permissions=["cms.view","cms.manage"]`); `on_enable` registers repos as DI providers + built-in post-types + term-types + (47.1) the sitemap provider stub. `config.json`+`admin-config.json` with `debug_mode` + `posts_per_page` (plugin baseline rule). Seeder + JSON import/export move to the unified model — see §2.6.

### 2.6 Seeder + JSON import/export migrated to the unified model (REQUIRED — breaks demo instances otherwise)
cms already ships **two** content-population paths keyed to the OLD entities; both must move with the schema or live/demo instances and existing exports break:
- **Seeder `src/bin/populate_cms.py`** (NOT `populate_db.py`) — rewrite to seed `cms_post`/`cms_term` **via services, not raw SQL**; idempotent; cold-CI-safe (2 categories, 3 tags, a couple `page`s + `post`s).
- **`CmsImportExportService`** — today a ZIP of per-section JSON (`pages.json` = `CmsPage.to_dict()` + category/layout/style slugs, plus `categories.json`/`styles.json`/`widgets.json`/`layouts.json`/`routing_rules.json`/`images.json`). Update to the unified entity: emit **`posts.json`** (typed) + **`terms.json`** (typed) under a **versioned `manifest.json`** (`format_version` bump), AND ship a **legacy-format importer** that ingests old `pages.json` → `cms_post(type=page)` and `categories.json` → `cms_term(term_type=category)`. This back-compat adapter is the linchpin — it lets existing instance exports **and** the whole `docs/imports/*.json` seed tree keep loading with **zero hand-editing**.
- **`docs/imports/` seed tree** (`pages/*.json` — solutions, pricing-native, references, features, enterprise, landing2/3, ghrm-software-*, …; `layouts/*.json`; `theme-styles.json`) — the live demo content. Kept **as-is** initially, ingested through the legacy adapter above (so vbwd.cc-class instances populate unchanged). Optional later: a one-shot re-export into the new typed format — **not** a blocker.

## 3. Migration / backfill (live data)
Two surfaces move together:
- **DB backfill** — a service-layer, idempotent step (own migration or a `flask cms backfill` command): `cms_page → cms_post(type=page)` (copy SEO columns 1:1, `content_html`/`content_json`; map `is_published` → `status` `published`/`draft`; `parent_id=null` unless page nesting is known), `cms_category → cms_term(term_type=category)`, preserve page↔image links. Keep a **read shim** so any un-migrated caller resolving `cms_page` still works for one release. Runs cold in CI from an empty DB **and** against a seeded cms_page set.
- **JSON side** — the import/export service + the `docs/imports/*.json` seed tree migrate via the **§2.6 legacy adapter** (no mass hand-edit of seed files); the seeder `src/bin/populate_cms.py` is rewritten to the unified model.

## 4. TDD (RED first)
- **Unit:** `to_dict`; `(type, slug)` + `(term_type, slug)` uniqueness; **post-type/term-type registries** (register/list, `hierarchical` flag, unknown type rejected at create — fail-fast/Liskov); **hierarchy**: `parent_id` rejected for non-hierarchical types, parent must be a hierarchical-type post, **parent cycle refused**, nested path `/about/team` resolves; **status transitions**: legal moves validated, `scheduled→published` via the tick when `published_at` passes, `→private`, `→trash` soft-delete (absent from public list); `PostService` create/term-assign + slug uniqueness within type (MagicMock repos); the `content.changed` hook fires on **every status change + content edit**.
- **Integration (real PG):** post + terms persisted; cascade on post delete clears junction not terms; published filter; pagination; **backfill**: a seeded `cms_page` becomes a `cms_post(type=page)` with SEO columns intact and is idempotent on re-run.
- **Seeder + import/export (§2.6):** `populate_cms.py` seeds the unified model idempotently (re-run creates nothing new); export → import **round-trips** posts+terms in the new typed format; a **legacy** `pages.json`/`categories.json` imports → `cms_post(type=page)`/`cms_term(term_type=category)`; a **real `docs/imports/pages/*.json` fixture** loads through the legacy adapter unchanged.
- **URL & slug parity — PROD-SAFETY REGRESSION GATE (the "nothing is lost" test):** seed the **current** page set (the real `docs/imports/pages/*.json` **and** a prod-representative fixture); **snapshot BEFORE** migration for every published page: `{slug, resolved public URL, canonical_url, content_html hash, sitemap loc}` + the routing-engine resolutions (contextual→canonical). Run the backfill. **Snapshot AFTER** from `cms_post(type=page)` and assert:
  1. **slug set identical** — count parity + set equality (no slug added / dropped / silently changed);
  2. **every prior public URL still resolves to the same page** — 200, same `canonical_url`, same content hash; **zero 404s, zero unintended redirects**;
  3. **prerendered file exists at the same path** for each published page (anon `GET` → 200, serving side — 47.2);
  4. **sitemap `loc` set unchanged**; routing rules resolve the same contextual→canonical (47.1 §4.1);
  5. any slug collision under the new `(type, slug)` namespace resolves via a **301** (activating the slug-change seam) — **never** a 404 or a dropped page.
  On any divergence the test **fails loud, listing the exact differing URLs**. This test is the definition-of-done for the migration.
- A second plugin can `register_post_type("event", routable=True)` / `register_term_type("series", hierarchical=False)` and it shows in the `/…-types` endpoints with **zero** cms change.

## 5. Acceptance
- Admin CRUD posts (any registered type) + terms; assign categories/tags; move through statuses (draft → scheduled → published → private → trash).
- A **page** can have a parent page and resolve at a **nested URL** (`/about/team`); a **non-hierarchical** type (`post`) **rejects** a parent.
- A **scheduled** post auto-publishes when its `published_at` passes (scheduler tick); a **trashed** post disappears from public reads; a **private** post is hidden from anon and visible to an authorized session.
- `GET /api/v1/cms/posts?type=post&term_type=category&term_slug=news` → **published** posts in that category, paginated.
- Existing cms_page content is reachable as `cms_post(type=page)` after backfill; the live page set is intact.
- A prior cms ZIP export **and** the existing `docs/imports/*.json` seed tree still import (via the legacy adapter); `populate_cms.py` populates the unified model idempotently — demo instances come up unchanged.
- **NOTHING IS LOST ON PROD (hard release gate):** after the backfill, the set of public page URLs, their canonicals, their sitemap locs, and their prerendered availability are **identical** to pre-migration — every existing link still 200s to the same content; **zero 404s, zero silent slug changes**. Run in CI against the `docs/imports` set **and as a preflight against a real prod DB dump** before the deploy. The migration is **reversible** (down-migration + the read shim) so a bad deploy rolls back with **no data loss**. No deploy without this green.
- `register_post_type`/`register_term_type` from another plugin works with no cms edit.
- `--plugin cms --full` GREEN.

## 6. Out of scope
SEO pipeline/prerender (47.1), serving (47.2), public render/widgets/content-blocks (47.3), search (47.4), RSS (47.5), fe-admin editor (47.6), likes/comments, slug-change 301 history (seam only).

## 7. Engineering-requirements check
- **Core agnostic / OCP:** post-types + term-types extensible by other plugins via registries; no core edit.
- **No EAV:** typed columns + `content_json`/`type_data` JSON.
- **DI/DRY:** repos via the container; one `TermService`/`PostService` validate against the one registry each.
- **DevOps-first:** in-plugin migration resolving standalone; backfill + demo via services; CI cold-start green.
- **NO OVERENGINEERING:** evolve cms; reuse SEO columns + `content_html`; one entity, one taxonomy.
