# S41 — CMS AI Helper (scaffold): `user_input` prompt field at the top of the page editor

**Status:** DRAFT for negotiation — 2026-05-29
**Repos touched:** `vbwd-fe-admin` (new `cms-ai-helper` plugin + a tiny extension seam in `cms-admin`).
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** · **plugin baseline config files** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: fe-admin `npm run lint && npm run test` GREEN on the plugin.

---

## 1. Goal (scaffold only)

Add an **AI helper input** to the CMS page editor: a `user_input` **textarea** with a **"Send" button**, rendered **above the first generic field (Name)** in the "page details" form. The button's `onSubmit` is a **dummy** (no backend, no LLM) in this sprint — it just proves the seam and the UX placement. This establishes the injection point a future sprint will wire to a real AI helper (e.g. *"describe your page → generate content + SEO meta"*, feeding the S40 SEO fields).

This is intentionally a thin, shippable scaffold — no AI, no API, no content generation. Just the field, the button, and a no-op handler.

## 2. Context (verified)

- The CMS page editor is `vbwd-fe-admin/plugins/cms-admin/src/views/CmsPageEditor.vue`. The **first generic field is "Name"** (`form.name`, ~line 60), immediately followed by Slug, content blocks, then the SEO section. The injection point is **above Name**, at the very top of the form body.
- `CmsPageEditor` has **no extension seam today** — adding one (small, agnostic) is part of this sprint so the AI helper lives in its **own plugin**, not bolted into `cms-admin`.
- fe-admin already uses extension registries (`vue/src/plugins/extensionRegistry.ts`, `profileSectionsRegistry`, `userEditTabs`) — mirror that pattern.

## 3. Design

### 3.1 Extension seam (in `cms-admin`, agnostic)

Add a top-of-form extension slot to the CMS page editor that other plugins can fill, without `cms-admin` knowing about AI. Two equivalent options (pick per existing convention):
- **(A) Registry (Recommended, matches fe-admin):** `cms-admin` exports a `cmsPageEditorTopRegistry` (mirroring `profileSectionsRegistry`); `CmsPageEditor.vue` renders `registry.getComponents()` in a `<component :is>` loop **immediately above the Name field**. Plugins register components in their `install()`.
- **(B) Named slot:** `CmsPageEditor` exposes a `<slot name="editor-top">`; the host wires plugin components in. (Registry is cleaner for decoupled plugins.)

The seam passes the editor's reactive `form` (or a typed subset) to contributed components so a future AI helper can populate fields — but in this sprint the dummy handler ignores it.

### 3.2 The `cms-ai-helper` plugin (fe-admin)

New plugin `vbwd-fe-admin/plugins/cms-ai-helper/` (named-export convention):
- Registers a `CmsAiHelperField.vue` into the seam from §3.1, `order` so it sits at the very top.
- `CmsAiHelperField.vue` renders:
  - a `<textarea>` bound to a local `userInput` ref — `data-testid="cms-ai-user-input"`, `name="user_input"`, a label + placeholder (i18n key, e.g. *"Describe what this page should contain…"*).
  - a **"Send"** button — `data-testid="cms-ai-send"` — `@click="onSubmit"`.
  - `onSubmit()` is a **dummy**: no network call. It is a clearly-marked placeholder (e.g. emits a toast / `console.info('[cms-ai-helper] submit (stub)', userInput.value)`), does NOT clear the field, does NOT mutate the page form. A `// TODO(S4x): wire to AI generation` comment marks the future seam.
- **Plugin baseline (BINDING):** ships `config.json` + `admin-config.json`, each with at least a `debug_mode` toggle (per `feedback_plugin_baseline_config_files`). i18n locale files for the label/placeholder/button across the existing fe-admin locale set, following the prevailing convention.

### 3.3 What this sprint deliberately does NOT build (NO OVERENGINEERING)

- No backend, no API endpoint, no LLM/Claude call, no prompt plumbing.
- No content/SEO generation, no writing into `form.*`.
- No streaming, history, or token accounting.
- The seam carries only what a future helper needs; no speculative props.

## 4. TDD plan (RED first)

- `plugins/cms-ai-helper/tests/unit/cms-ai-helper-field.spec.ts`: renders the `user_input` textarea + Send button (by testid); typing updates the local model; clicking Send invokes the dummy `onSubmit` exactly once and does **not** throw, does **not** emit a network request, does **not** mutate the passed `form`.
- Seam spec (in `cms-admin` or the plugin): a component registered in `cmsPageEditorTopRegistry` renders **above** the Name field in `CmsPageEditor` (assert DOM order: the AI field precedes `[data-testid="cms-page-name"]` / the Name input). Empty registry → nothing rendered (Liskov null default; editor unchanged).
- Mirror existing fe-admin/cms-admin test idioms (Vitest, mount with i18n + pinia).

## 5. Files (indicative)

| Action | Path |
|---|---|
| new | `vbwd-fe-admin/plugins/cms-ai-helper/index.ts` — plugin, registers the field into the seam |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/src/components/CmsAiHelperField.vue` |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/{config.json,admin-config.json}` (+ `debug_mode`) |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/locales/*.json` |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/tests/unit/cms-ai-helper-field.spec.ts` |
| edit | `vbwd-fe-admin/plugins/cms-admin/.../CmsPageEditor.vue` — render the top extension seam above Name |
| new/edit | `cms-admin` registry export (`cmsPageEditorTopRegistry`) if option A |

## 6. Acceptance

- Opening the CMS page editor (new or edit) shows, **above the Name field**, a labelled `user_input` textarea + a "Send" button.
- Typing in the textarea and clicking Send runs the dummy handler with no error and no network activity; the page form is untouched.
- With `cms-ai-helper` disabled, the editor renders exactly as before (the seam is empty → no AI field).
- fe-admin `npm run lint && npm run test` GREEN.

## 7. Out of scope (future sprint)

- The real AI helper: a backend endpoint that takes `user_input` + page context, calls Claude, and returns generated `content_html` + SEO meta (`meta_title`/`description`/`og_*`/`schema_json`) to populate the S40 fields. This sprint only lands the input + button + seam so that work has a home.

## 8. Engineering-requirements check

- **Core agnostic:** the seam lives in the `cms-admin` plugin (not fe-admin core); `cms-admin` knows nothing about AI; `cms-ai-helper` declares its dependency on the seam. No core change.
- **SOLID/Liskov:** empty registry → editor unchanged (null default); contributed components are substitutable.
- **NO OVERENGINEERING:** dummy `onSubmit`; no backend/LLM/generation; seam carries only what's needed.
- **Plugin baseline:** `config.json` + `admin-config.json` with `debug_mode` ship with the plugin.
- **TDD-first:** component + seam specs land RED before the field exists.
