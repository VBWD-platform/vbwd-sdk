# S47.6 — fe-admin: unified type-aware post editor + term manager + SEO authoring

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Depends on:** [S47.0](s47-0-unified-data-model-and-registries.md) (SEO fields meaningful with [47.1](s47-1-seo-pipeline-and-prerender.md)) · **Status:** DRAFT — 2026-06-03
**Repos:** `vbwd-fe-admin-plugin-cms` (`cms-admin`).
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · clean code · **core agnostic** · **NO OVERENGINEERING** · **plugin baseline config files** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: fe-admin `npm run lint && npm run test` GREEN; authoring e2e GREEN.

---

## 1. Goal

One **type-aware** authoring surface for every `post` (page / post / custom type) and the taxonomy — replacing the separate cms-page and (planned) press-post editors. Authors get the SEO controls that actually move the needle (SERP preview, exclude-from-search), driven by the 47.0 registries so a new post-type/term-type needs **no admin change**.

## 2. fe-admin — `vbwd-fe-admin/plugins/cms-admin/`

### 2.1 Post editor (`PostEditor.vue`)
- **Type-aware:** the `type` comes from `/admin/cms/post-types` (registry). Common fields (title, slug, excerpt, body, author, language, term pickers) + **type-specific fields** rendered from the type's `type_data` schema.
- **Status control:** `draft · pending · scheduled · published · private · trash` (replaces a bare publish toggle), with a **`published_at` picker** for **scheduled** publishing.
- **Parent picker** — shown **only for `hierarchical` types** (e.g. pages), choosing the parent page (drives the nested URL `/about/team`).
- **Body:** reuse the existing TipTap editor for the `richtext` block; the block list maps to `content_json` (47.3). (Rich per-type block-builder UI is deferred — minimal block add here.)
- **SEO panel** (the full 47.1 field set): meta title/description/keywords, og/twitter, canonical, robots, `schema_json`, plus:
  - **Live SERP preview** (title + URL + description with char-count warnings) — highest real-world ROI.
  - **"Exclude from search engines" toggle** (`seo_excluded`), with the **effective** state shown (e.g. *"noindex — inherited from category X"* when a term excludes it).
  - **hreflang / "translation of →" picker** (writes `translation_group_id`).

### 2.2 Term manager (`TermManager.vue`)
- CRUD terms grouped by `term_type` (types from `/admin/cms/term-types`); hierarchy for hierarchical types; per-term **`seo_excluded`** toggle (inheritance surfaced on the post editor).

### 2.3 Wiring
Nav entries via the fe-admin nav registry; routes under `/admin/cms/*`. Named-export plugin; `config.json`+`admin-config.json`(+`debug_mode`); locales (baseline rule).

## 3. TDD (RED first)
- `PostEditor`: renders + binds common fields; `type` drives type-specific fields; term pickers populate from the API; save payload shape (incl. `content_json`, SEO fields, `translation_group_id`).
- **SERP preview** reflects field values + char-count thresholds.
- **Exclude toggle** writes `seo_excluded`; **inherited** state shown when a selected term is excluded.
- `TermManager`: CRUD by type; hierarchy for hierarchical types; `seo_excluded` per term.

## 4. Acceptance
- An author creates/edits a `page`, a `post`, and (with an extension plugin installed) a custom type from the **same** editor; assigns categories/tags; sets **status** (incl. **scheduling** a future `published_at`); sets a **parent** for a hierarchical page (nested URL); the parent picker is hidden for non-hierarchical types.
- The SERP preview updates live; the exclude toggle (page- and category-level) is reflected, with inheritance surfaced.
- A new registered post-type/term-type appears in the editor pickers with **zero** cms-admin change.
- fe-admin lint+test GREEN; authoring e2e GREEN.

## 5. Out of scope
Rich block-builder UI for every content type (minimal authoring here), media library overhaul, revisions/scheduling UI, likes/comments moderation.

## 6. Engineering-requirements check
- **DRY:** one editor for all types; SEO panel reused across types; pickers driven by the registries.
- **Core agnostic / OCP:** new types surface via the registry endpoints; no cms-admin edit to support them.
- **NO OVERENGINEERING:** reuse the TipTap editor + SEO fields; defer the per-type block-builder.
