# S42.3 — Extensible post content-type renderer registry (worked example: YouTube embed)

**Parent:** [S42 — vbwd-press](s42-vbwd-press.md) · **Depends on:** [S42.0](s42-0-data-model-terms-crud.md), [S42.1](s42-1-post-list-and-term-widget.md) · **Status:** DRAFT — 2026-05-29
**Repos:** `vbwd-fe-user-plugin-press` (registry + default renderer), **new** `vbwd-fe-user-plugin-press-youtube` (the example extension), `vbwd-plugin-press` (store the typed block).
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** · **plugin baseline config files** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: fe `npm run lint && npm run test` GREEN; `--plugin press --full` GREEN.

---

## 1. Goal

Make a post's content **composed of typed blocks** whose rendering is **extensible by other plugins** (the "WordPress custom post type / block" story). Ship the registry + a default rich-text renderer in press, then **prove extensibility with a separate `press-youtube` plugin** that renders an embedded YouTube video as the **topmost element** of the post detail.

## 2. Content model (press)

A post's body is an ordered list of **content blocks** (stored in `content_json` as `{ blocks: [{ type, data, position }] }`, or a `vbwd_press_post_block` child table if richer querying is wanted — start with `content_json`, NO OVERENGINEERING). Each block has:
- `type` (str — `richtext` default; `youtube`, `gallery`, `video`, … from plugins),
- `data` (type-specific JSON),
- `position` (int — render order; **position 0 = topmost**).

The default `richtext` block carries the existing TipTap/`content_html` (back-compat: a post with no blocks renders its `content_html` as a single implicit `richtext` block).

## 3. The renderer registry (press, fe-user)

`vbwd-fe-user/plugins/press/src/registry/contentTypeRegistry.ts`:
- `registerPostContentType(type: string, component: Component, opts?: { placement?: 'top' | 'inline' | 'bottom' })`
- `resolvePostContentType(type) -> { component, opts } | undefined`

`PressPostDetail` (42.1) renders blocks by: resolve each block's `type` → component; **unknown type → a safe fallback** (render nothing / a quiet "unsupported block" notice — Liskov: never crash). **Placement rule:** blocks with `placement: 'top'` render **above** the in-flow blocks regardless of position among them (and ordered by `position` within the top zone) — this is how a hero embed pins to the top. `inline` blocks render in `position` order in the body; `bottom` after.

Press registers the built-in **`richtext`** renderer (`placement: 'inline'`).

## 4. The example extension — `press-youtube` (separate plugin)

A **standalone plugin** (`vbwd-fe-user-plugin-press-youtube`) to prove cross-plugin extensibility with **zero press changes**:
- In `install()`, calls `registerPostContentType('youtube', YouTubeEmbed, { placement: 'top' })`.
- `YouTubeEmbed.vue`: takes block `data = { video_id | url, title? }`, renders a **responsive, privacy-friendly** embed (`youtube-nocookie.com`, `loading="lazy"`, 16:9 aspect-ratio box, `title` for a11y). Because it registers as `placement: 'top'`, any post with a `youtube` block shows the video **as the topmost element of the post detail**, above the article body — the requested behavior.
- Ships `config.json`+`admin-config.json` (+`debug_mode`) + locales (plugin baseline rule).
- (Authoring: press-admin's editor gains a "YouTube" block option only if we want admin UI now; minimally, the block can be added via the post JSON / a small admin field. Admin UX for arbitrary block types can be its own follow-up — keep 42.3 about the **render** seam.)

This doubles as the template for future types (`gallery`, `video`, `audio`, `code`, …): a plugin registers a renderer; press is untouched.

## 5. TDD (RED first)
- **Registry:** register/resolve by type; unknown type → fallback (no throw — Liskov); `placement` honored.
- **`PressPostDetail`:** renders blocks in `position` order; a `top`-placement block renders above in-flow blocks; back-compat (no blocks → `content_html` as one richtext block).
- **`press-youtube`:** registers `youtube` on install; `YouTubeEmbed` builds the correct `youtube-nocookie` src from `video_id` and from a full URL; lazy + aspect-ratio; a post with a youtube block shows the embed as the **first/topmost** element.
- Backend: post `content_json.blocks` round-trips; default block back-compat.

## 6. Acceptance
- A post with `blocks: [{type:'youtube', data:{video_id:'abc'}, position:0}, {type:'richtext', ...}]` renders the **YouTube embed at the very top** of the post detail, article body below.
- Installing/uninstalling `press-youtube` adds/removes youtube rendering with **no press code change**; an unknown block type never breaks the page.
- A post with only legacy `content_html` still renders unchanged.
- Gates GREEN.

## 7. Out of scope
Rich admin block-builder UI for every type (minimal authoring only here), server-side oEmbed resolution, non-YouTube providers (each is its own extension plugin), comments/likes.

## 8. Engineering-requirements check
- **Core agnostic / OCP:** new content types via a registry from **separate plugins**; press (and cms/core) untouched. The `press-youtube` plugin is the proof.
- **Liskov:** unknown type → safe fallback; every renderer honors the same block contract.
- **DRY:** one registry + one block-rendering loop in `PressPostDetail`.
- **NO OVERENGINEERING:** blocks in `content_json` (no new table yet); one example provider; admin block-builder deferred.
