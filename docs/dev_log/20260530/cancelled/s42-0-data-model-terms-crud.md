# S42.0 — vbwd-press data model + term-type registry + post/term CRUD + admin

**Parent:** [S42 — vbwd-press](s42-vbwd-press.md) · **Status:** DRAFT — 2026-05-29
**Repos:** `vbwd-plugin-press` (backend), `vbwd-fe-admin-plugin-press` (admin UI).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin press --full` GREEN; fe-admin `npm run lint && npm run test` GREEN.

---

## 1. Goal

The data foundation: posts, an extensible taxonomy, the admin to manage them, and public read endpoints the later widgets consume. No widgets, no search, no public rendering yet (those are 42.1+).

## 2. Backend — `vbwd-backend/plugins/press/` (new-convention `plugins/press/press/`)

### 2.1 Models (`plugins/press/press/models/`)
- **`vbwd_press_post`** (`BaseModel`): `slug` (unique, indexed), `title`, `excerpt` (Text), `content_json` (JSON, TipTap — reuse cms convention), `content_html` (Text), `author_id` (UUID FK `vbwd_user.id`, `ondelete SET NULL`), `is_published` (bool), `published_at` (tz datetime, nullable), `language` (str, default `en`), `sort_order`. **SEO fields mirroring `cms_page`** (`meta_title/description/keywords`, `og_*`, `canonical_url`, `robots` default `index,follow`, `schema_json`) + `translation_group_id` (UUID, nullable, indexed — S40 hreflang). `to_dict()` explicit + isoformat timestamps.
- **`vbwd_press_term`** (`BaseModel`): `slug` (indexed), `name`, `term_type` (str, indexed — `category`/`tag`/plugin-defined), `parent_id` (self-FK, nullable → hierarchy for categories; flat for tags), `description` (Text, nullable), `sort_order`. **Unique on `(term_type, slug)`** (a slug is unique within its type).
- **`vbwd_press_post_term`**: junction `(post_id, term_id)`, both FK + `ondelete CASCADE`, unique together.

Migration in **`plugins/press/migrations/versions/`** (register path in `alembic.ini`); chains off a CMS or core revision that resolves standalone (avoid anchoring on an unrelated plugin — see migration-graph fragmentation note).

### 2.2 Term-type registry (agnostic extensibility)
`plugins/press/press/services/term_type_registry.py` — `register_term_type(TermType(key, label, hierarchical: bool))` + `list_term_types()`. Press registers built-ins **`category`** (hierarchical) + **`tag`** (flat). Other plugins register more (the "custom taxonomy" story). Validation: a term's `term_type` must be registered (fail-fast on unknown type at create). This registry is the seam other plugins extend — **no press code change** to add a taxonomy.

### 2.3 Repositories + services
`PostRepository` (by slug, by term, paginated published, by id), `TermRepository` (by type, by slug, children), `PostTermRepository`. `PostService` (create/update/publish/unpublish, slug uniqueness + 301-history hook left for later, term assignment), `TermService` (CRUD, type validation via the registry). DI through factory functions in `routes.py` using `db.session`.

### 2.4 Routes (`plugins/press/press/routes.py`, blueprint, absolute paths)
- **Admin** (`require_permission("press.manage")` — register the perm via the plugin's `admin_permissions` so S39 RBAC picks it up): `GET/POST /api/v1/admin/press/posts`, `GET/PUT/DELETE /api/v1/admin/press/posts/<id>`, publish/unpublish; `GET/POST /api/v1/admin/press/terms`, `PUT/DELETE /api/v1/admin/press/terms/<id>`; `GET /api/v1/admin/press/term-types` (from the registry).
- **Public read** (the later widgets/RSS consume these): `GET /api/v1/press/posts` (published, paginated, `?term_type=&term_slug=` filter), `GET /api/v1/press/posts/<slug>` (single published), `GET /api/v1/press/terms?type=`.

### 2.5 Plugin wiring
`__init__.py` `BasePlugin` (`metadata.dependencies = ["cms"]`, `admin_permissions = ["press.view","press.manage"]`); `on_enable` registers repos as DI providers + the built-in term-types + (S40) a sitemap provider stub (filled in 42.1). `populate_db.py` (idempotent demo: 2 categories, 3 tags, ~5 posts via the service layer — not raw SQL). `config.json`+`admin-config.json` with `debug_mode` + `posts_per_page` default.

## 3. fe-admin — `vbwd-fe-admin/plugins/press-admin/`
- Posts list + `PressPostEditor.vue` (reuse cms-admin's TipTap editor + the S40 SEO fields/SERP preview; author, publish toggle, term pickers for category + tag).
- Terms manager (`PressTermList`/editor) grouped by `term_type` (types from `/admin/press/term-types`).
- Nav entries via the fe-admin nav registry; routes under `/admin/press/*`. Named-export plugin; `config.json`+`admin-config.json`(+`debug_mode`); locales.

## 4. TDD (RED first)
- **Backend unit:** model `to_dict`; term `(term_type, slug)` uniqueness; term-type registry (register/list, unknown type rejected at term create — Liskov/fail-fast); PostService create/publish/term-assign (MagicMock repos); slug uniqueness.
- **Backend integration:** post + terms persisted; cascade on post delete clears junction but not terms; published filter; pagination.
- **fe-admin:** editor renders + binds fields; term pickers populate from the API; save posts payload shape.

## 5. Acceptance
- Admin can CRUD posts + terms; assign categories/tags; publish/unpublish.
- `GET /api/v1/press/posts?term_type=category&term_slug=news` returns published posts in that category, paginated.
- A second plugin can `register_term_type("series", hierarchical=False)` and it appears in `/admin/press/term-types` with **zero** press changes.
- `--plugin press --full` GREEN; fe-admin lint+test GREEN.

## 6. Out of scope
Public rendering/widgets (42.1), search (42.2), content-type renderers (42.3), RSS (42.4), likes/comments, slug-change 301 history (seam only).

## 7. Engineering-requirements check
- **Core agnostic:** own plugin; declares `cms` dep; term-types extensible by others via registry.
- **DI/DRY:** repos via container; one TermService validates against the one registry.
- **DevOps-first:** Alembic migration in-plugin, resolves standalone; demo via services; CI cold-start green.
- **NO OVERENGINEERING:** posts reuse cms content + S40 SEO; no bespoke editor; likes/comments deferred.
