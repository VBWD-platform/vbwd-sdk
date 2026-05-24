# Report — CMS admin WYSIWYG shows empty: where is the page content?

**Date:** 2026-05-24
**Reporter:** investigation on the live local stack (admin `:8081`, API via proxy)
**Scope:** `vbwd-fe-admin` CMS Pages editor + `vbwd-backend` CMS data +
`vbwd-fe-user` public renderer. **Read-only investigation — no code changed.**

---

## TL;DR (the answer)

**The content is not lost.** It is in the backend `cms_page` table and is
served correctly by the API and the public site. The admin WYSIWYG looks
empty for two *different* reasons, and one of them is a real bug:

1. **Marketing pages** (`enterprise`, `solutions`, `references`,
   `accelerator`) **do have body content** — it lives in the page's
   `content_html` column (e.g. `enterprise` = **4017 characters** of HTML) plus
   a CMS **Style** record. The admin editor fails to load it because of a
   layout-area-name mismatch (see §3). **← real bug.**

2. **Home & functional pages** (`home1`, `shop`, `booking`, `category/*`, …)
   have **no page-level body content at all** (`content_html` null,
   `content_json` empty). Their visible content is composed entirely by the
   **layout's typed areas** (hero / features / cta / vue-mount) — there is
   nothing for the page WYSIWYG to show by design.

In **every** case the per-page `content_json` (the TipTap doc the WYSIWYG is
bound to) is an empty `{"type":"doc","content":[]}`, so the WYSIWYG is blank
even when `content_html` is full.

---

## 1. What we observed (screenshots)

All five screenshots are in [`screenshots/`](screenshots/). Logged in as
`admin@example.com`, CMS → Pages.

| Screenshot | Page | Layout | Style | WYSIWYG | HTML tab |
| --- | --- | --- | --- | --- | --- |
| `home1-editor.png` | `home1` (the homepage) | Home v1 (Hero + Features + CTA) | — none — | **empty** | — |
| `home1-HTML-tab.png` | `home1` | " | " | — | **empty** |
| `enterprise-editor.png` | `enterprise` | Content Page (Header + Content + Footer) | Enterprise — Slate — Full-width | **empty** | — |
| `enterprise-HTML-tab.png` | `enterprise` | " | " | — | **empty** |
| `solutions-editor.png` | `solutions` | Content Page (Header + Content + Footer) | Enterprise — Slate — Full-width | **empty** | — |

The decisive pair is `enterprise`: its WYSIWYG **and** its HTML tab are both
empty in admin, yet the API returns 4 KB of real HTML for that page (below).

`home1` is the actual homepage: the CMS default routing rule
(`match_type=default`) maps `/` → slug `home1`.

---

## 2. What the data actually contains

`GET /api/v1/cms/pages` (20 pages). Every page: `content_json` =
`{"type":"doc","content":[]}` (0 nodes).

```
slug=home1        content_html=NULL   content_blocks={}  layout=Home v1 (Hero+Features+CTA)
slug=enterprise   content_html=4017c  content_blocks={}  layout=Content Page    style=Enterprise-Slate
slug=solutions    content_html=set    content_blocks={}  layout=Content Page    style=Enterprise-Slate
slug=references   content_html=set    content_blocks={}  layout=Content Page    style=…
slug=accelerator  content_html=set    content_blocks={}  layout=Content Page    style=…
slug=shop|booking|category/* …  content_html=NULL  content_blocks={}  layout=… (vue/typed areas)
```

`GET /api/v1/cms/pages/enterprise`:

```
content_html len: 4017
content_html head: '<section class="hero"><span class="hero__eyebrow">For enterprise teams</span>
                    <h1>The SaaS toolkit that adapts to you…'
content_json nodes: 0
style_id: 23ee17f2-…   resolved_style_id: 23ee17f2-…
```

So the marketing content **exists** in `content_html`. It is simply not in
`content_json`.

---

## 3. Root cause — layout content-area name mismatch

### 3.1 The editor builds blocks from the *layout's* content areas

`vbwd-fe-admin/plugins/cms-admin/src/views/CmsPageEditor.vue`

- The WYSIWYG is bound to a **block**, not to the page directly
  (`:107`):
  ```vue
  <TipTapEditor v-model="block.content_json"
                v-model:html-value="block.content_html" … />
  ```
- `rebuildBlocks()` (`:676-727`) derives the editable blocks from the
  selected layout's areas of `type === 'content'`:
  ```ts
  const contentAreas = (layout.areas).filter(a => a.type === 'content');
  // → one editable block per content area, areaName = area.name
  ```
- After load, the page's legacy single-content fields are back-filled into a
  block **only** when there is exactly one block **named literally
  `content`** (`:952-960`):
  ```ts
  if (editableBlocks.value.length === 1 && editableBlocks.value[0].areaName === 'content') {
    const block = editableBlocks.value[0];
    if (!block.content_html && form.value.content_html) {
      block.content_json = form.value.content_json;
      block.content_html = form.value.content_html;   // ← the 4 KB would load HERE
      block.source_css   = form.value.source_css;
    }
  }
  ```

### 3.2 The layouts these pages use

Fetched from `GET /api/v1/admin/cms/layouts`:

```
Home v1 (Hero + Features + CTA)        areas = header:header, hero:hero,
                                               features:three-column, cta:cta-bar, footer:footer
Content Page (Header + Content + Footer) areas = header:header, breadcrumbs:vue,
                                               main:content, footer:footer
```

- **`enterprise` / `solutions` / …** use *Content Page*, whose content area
  is named **`main`** (type `content`). `rebuildBlocks()` creates one block
  with `areaName = "main"`. The back-fill at `:953` requires
  `areaName === "content"`, and `"main" !== "content"`, so **the back-fill is
  skipped** and the page's 4 KB `content_html` is never loaded into the block.
  → both WYSIWYG and HTML tabs are empty. **This is the bug.**

- **`home1`** uses *Home v1*, which has **no `type === 'content'` area** at
  all (only hero / features / cta / header / footer). `rebuildBlocks()` falls
  to its "single default block" branch and seeds from `form.content_html` —
  which is empty for `home1`. So the WYSIWYG is correctly empty: this page has
  no free-text body; its content is the layout's typed areas.

### 3.3 Why the public site still renders correctly

`vbwd-fe-user/plugins/cms/src/views/CmsPage.vue` (`:185-192`) prefers
`content_html`, then falls back to `content_json`:

```ts
const renderedHtml = computed(() => {
  const raw = store.currentPage?.content_html;
  if (raw) return raw;                       // ← marketing pages hit this
  …render content_json…
});
```

and `CmsLayoutRenderer.vue` (`contentBlockHtml`) renders a content area from
`contentBlocks[area]` **or falls back to the page-level `contentHtml`** —
regardless of the area's name. So `main` on the public side picks up the page
`content_html`. The **public renderer has the name-agnostic fallback the
admin editor lacks** — which is exactly why the site is fine but the editor
is blank.

### 3.4 Backend model (for reference)

`vbwd-backend/plugins/cms/src/models/cms_page.py:14-16`:
```py
content_json = db.Column(db.JSON, nullable=False, default=dict)   # TipTap doc
content_html = db.Column(db.Text, nullable=True)                  # raw HTML
source_css   = db.Column(db.Text, nullable=True)
```
Import (`cms_page_service.py` `_apply_data`) stores `content_html` /
`content_json` as provided — the marketing import populates `content_html`
only, leaving `content_json` empty. Nothing transforms one into the other.

---

## 4. Impact

- **No data loss — and no wipe on save.** I checked the save path
  (`CmsPageEditor.vue:840-866`). `payload` starts as `{ ...form.value }`,
  which already carries the loaded `content_html` (4017 chars). For a
  `main`-area page the save takes the **`else`** branch (block name `main` ≠
  `content`) and writes `payload.content_blocks = { main: {…} }` **without
  touching `payload.content_html`**. So the page-level `content_html` is
  preserved, and a no-op save stays harmless: the empty `content_blocks.main`
  is falsy, so `CmsLayoutRenderer.contentBlockHtml('main')`
  (`CmsLayoutRenderer.vue:62-67`) falls back to the page `content_html` and
  the live page keeps rendering.
- **The real harm is editorial, not data.** The marketing content
  (`enterprise`, `solutions`, `references`, `accelerator`) is **invisible and
  uneditable** from the admin editor — you open a blank canvas. If you type
  new content and save, it lands in `content_blocks.main` and **shadows** the
  original `content_html` (which stays in the DB, now orphaned), rather than
  editing it. So the editor both hides the truth and silently diverges the
  storage model on edit.
- **Home/functional pages** behave as designed (layout-driven); the empty
  WYSIWYG there is expected, though confusing UX.

---

## 5. Recommended fix (proposal — not yet implemented)

Make the admin editor's back-fill **name-agnostic**, mirroring the public
renderer's fallback. In `CmsPageEditor.vue` `onMounted` (`:952`), when there
is exactly **one** content block and it is empty, seed it from the page's
`content_html` / `content_json` **whatever the area is named** (the single
content area of a layout *is* the page body):

```ts
if (editableBlocks.value.length === 1) {
  const block = editableBlocks.value[0];
  if (_isEmptyBlock(block) && (form.value.content_html || /* non-empty doc */)) {
    block.content_json = form.value.content_json;
    block.content_html = form.value.content_html;
    block.source_css   = form.value.source_css;
  }
}
```

Secondary hardening:
- Decide on **one** storage model for a single content area. Today a save of
  a `main`-area page leaves the body in page-level `content_html` *and* writes
  an empty `content_blocks.main`; once edited, the new text moves to
  `content_blocks.main` and shadows the original `content_html`, which is left
  orphaned. The fix in §5 (load the body into the single block regardless of
  area name) plus saving that block back through the same field would keep one
  source of truth and avoid the orphan.
- Optional one-off migration: for pages with non-empty `content_html` and an
  empty `content_json`, parse the HTML into a TipTap doc so the structured
  WYSIWYG (not just the HTML tab) shows the legacy content too.

This is a candidate for a sprint; this report is the diagnosis only.

---

## 6. Reproduction

1. `:8081/admin` → login `admin@example.com` / `AdminPass123@`.
2. CMS → Pages → open **VBWD for Enterprise** (slug `enterprise`).
3. WYSIWYG tab: empty. HTML tab: empty.
4. `curl :8081/api/v1/cms/pages/enterprise` → `content_html` has 4017 chars.
5. Visit the page on the user site (`:8080`, slug `enterprise`) → renders
   fully. Content is present everywhere except the admin editor.

---

## 7. Confirmed on production (vbwd.cc) — the homepage itself

The live homepage is the same bug. `vbwd.cc/` → routing rule `default`
→ slug **`home`**.

- **Editor (will show empty):**
  `https://vbwd.cc/admin/cms/pages/b9b10e9f-d886-4a95-a0c2-32ad8eca21ad/edit`
- `GET https://vbwd.cc/api/v1/cms/pages/home`:
  - `content_html` = **5630 chars** — the whole visible page: `<header
    class="vbwd-hero">`, `<div class="vbwd-stats">`, `<div class="vbwd-grid">`
    / `<div class="vbwd-card">` …
  - `content_json` nodes: 0 · `content_blocks`: `{}` · `page_assignments`: `[]`
  - `layout_id` = `7635e826-…` = **Content Page (Header + Content + Footer)**
- `GET https://vbwd.cc/api/v1/cms/layouts/7635e826-…`:
  - areas: `header`(header), `breadcrumbs`(vue), **`main`(content)**, `footer`(footer)
  - `widget_assignments`: `[]`

So the prod homepage content is **not in any widget** — it is the page's own
`content_html`, rendered into the layout's `main` area. Because the content
area is named `main` (≠ `content`), the admin editor's back-fill (`:953`) is
skipped, so the editor at the URL above opens **blank in both the WYSIWYG and
HTML tabs** even though 5630 chars are stored and live. Identical mechanism to
the local `enterprise` page (`enterprise-editor.png` / `enterprise-HTML-tab.png`).

A prod screenshot was not captured: the documented seed login
(`admin@example.com`) is rejected on prod (`success:false, "Invalid
credentials"`), so admin access needs the real production credentials. The
local screenshots show the identical scenario.
