# S42 — vbwd-press: a WordPress-style blog built on the CMS plugin (master)

**Status:** DRAFT for negotiation — 2026-05-29
**What it is:** an **agnostic plugin on top of `cms`** that delivers basic WordPress functionality — posts, an extensible taxonomy (terms = categories / tags / plugin-defined types), listing + search widgets, extensible post content types, and optional RSS. SEO is **inherited from S40** (posts are public CMS-grade content).
**Repos (own repos, per platform convention):** `vbwd-plugin-press` (backend → `vbwd-backend/plugins/press/`), `vbwd-fe-user-plugin-press` (→ `vbwd-fe-user/plugins/press/`), `vbwd-fe-admin-plugin-press` (→ `vbwd-fe-admin/plugins/press-admin/`).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate per repo: `bin/pre-commit-check.sh --plugin press --full` (backend); fe `npm run lint && npm run test`.

---

## 1. Why this is feasible on the existing CMS

The linchpin already exists: cms widgets support `widget_type="vue-component"`, resolved from `resolveCmsVueComponent(name)` (`vbwd-fe-user/plugins/cms/src/registry/vueComponentRegistry.ts`) — five plugins already register components this way. So press's **listing and search widgets are just registered Vue components**; an admin drops them into any layout/page area as `vue-component` widgets. No cms core change. Press also reuses cms content rendering (`content_json`/`content_html`), the **S40 SEO seam**, image handling, and public slug routing.

## 2. Architecture decisions (recommended defaults — LOCKED pending your nod)

- **D1 — Post is a separate entity** `vbwd_press_post` (NOT a `cms_page`): posts have author, `published_at`, excerpt, term relationships — a different lifecycle than static pages. It *reuses* cms content + SEO conventions.
- **D2 — Generic taxonomy** `vbwd_press_term` (`term_type` discriminator: `category`, `tag`, …) + `vbwd_press_post_term` junction. **`term_type` is open** — other plugins register new types via a **term-type registry**. Do NOT overload `cms_category` (page-scoped).
- **D3 — Routing** via cms composition: a blog index + `/category/<slug>` + `/tag/<slug>` are **cms pages composed of press widgets**; a post detail renders at its own slug like a cms page (`PressPostDetail`). No bespoke router needed beyond a post-detail route.
- **D4 — Search** = Postgres full-text search (`tsvector` + GIN).
- **D5 — Extensibility via registries** (term-types; post-content-type renderers) — the platform idiom; this is the "WordPress custom taxonomy / post type" story.
- **D6 — Agnostic + declared dep:** `PluginMetadata.dependencies = ["cms"]`. **Likes & comments are OUT OF SCOPE** (FK seams left on the post for a later sprint).

## 3. The DRY core: one generic post list

Every listing surface — by category, by tag, by any term_type, or by search — is a **post query → `PostCard[]`**, rendered by a single `PressPostList`. Each card = title + **configurable** metadata (author, time-ago, tags, …) + excerpt + image. This single component + a shared "post query" service is the spine; the widgets and search are thin sources feeding it.

## 4. Sub-sprints

| # | Sub-sprint | Delivers |
|---|---|---|
| [42.0](s42-0-data-model-terms-crud.md) | Data model + term-type registry + post/term CRUD + admin | `vbwd_press_post`/`term`/`post_term`, term-type registry, repos/services, admin + public read routes, fe-admin editor |
| [42.1](s42-1-post-list-and-term-widget.md) | Generic `PressPostList` + "category/term" widget | the shared list + `PostCard`, post-detail view, the term-list `vue-component` widget |
| [42.2](s42-2-fts-search-and-widget.md) | FTS search + search widget | `tsvector`/GIN, `/press/search`, the search `vue-component` widget (results via `PressPostList`) |
| [42.3](s42-3-content-type-renderer-registry.md) | Extensible content-type renderer registry **+ YouTube-embed example** | type→renderer registry; demo `youtube` post type renders the embed as the **topmost** element of post detail |
| [42.4](s42-4-rss-feeds.md) | RSS feeds (optional) | per category/tag/term RSS 2.0 feeds + autodiscovery |

**Dependency order:** 42.0 → 42.1 → {42.2, 42.3, 42.4 in parallel}. Each is independently shippable.

## 5. SEO inheritance (from S40)

Press does **not** reimplement SEO. Posts carry the same SEO fields as cms pages and:
- register a **sitemap provider** (S40's `ISeoSitemapProvider`) yielding published posts + term archive pages (hreflang via `translation_group_id`);
- emit `Article` JSON-LD (+ `BreadcrumbList` from the term path) via S40's shared meta-builder / per-type mapper;
- are server-delivered for crawlers through S40's render path.

So **S40 should land (at least increments 1–2) before or alongside 42.1** for posts to be crawlable. If S40 isn't ready, posts still work; they're just CSR-only until S40 lands.

## 6. Engineering-requirements check

- **Core agnostic:** all press code in its own plugin repos; depends on `cms` (declared); registers widgets via the existing vue-component registry; no cms/core edits.
- **DRY:** one `PressPostList` + one post-query service feed every source (term, search, RSS).
- **SOLID/Liskov:** term-types + content-type renderers are registry-resolved + substitutable; an unknown type falls back to a safe default renderer.
- **NO OVERENGINEERING:** reuse cms widgets, content rendering, S40 SEO; likes/comments deferred; RSS optional.
