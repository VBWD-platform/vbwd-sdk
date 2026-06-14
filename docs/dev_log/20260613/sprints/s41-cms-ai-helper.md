# S41 — CMS AI Helper: LoopForge-driven content & SEO generation in the editor

**Status:** DRAFT for negotiation — rewritten 2026-06-13 (supersedes the 2026-06-06 "cms-ai-helper / port-loopai" draft; folds in the LoopForge engine + S77 custom-fields integration).
**Repos touched:** `vbwd-backend` (the **`cms-ai`** plugin — gains the LoopForge engine + the editor-generate proxy) · `vbwd-fe-admin` (new `cms-ai` fe plugin + small AI-agnostic seams in `cms-admin`).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · **Liskov** · clean code · **core agnostic (only plugins are gnostic)** · **NO OVERENGINEERING** (narrowest change that satisfies the req) · **plugin baseline config files** — see [`_engineering_requirements.md`](_engineering_requirements.md). **Gate: `bin/pre-commit-check.sh` GREEN on every touched repo (`--full` = done; `--quick` while iterating).**

---

## 1. Goal

Give the CMS editor an **AI helper** that turns a natural-language prompt (plus the page's own context: excerpt, title, existing content) into structured content + SEO + (admin-configured) custom fields, written back into the editor form fields the operator then reviews and saves.

Two surfaces in the editor:

1. **An `AI ✨` button with a drop-down of actions** in the editor header action bar (next to Save), with at least:
   - **Write an article from excerpt** — generate `content_html` (and optionally title/excerpt) from the excerpt; leave SEO fields untouched unless asked.
   - **Re-generate all SEO fields** — from the current title + content, (re)fill `meta_title`, `meta_description`, `meta_keywords`, `og_title`, `og_description`, `schema_json`.
   - **Restyle the page** — generate/replace `source_css` (the editor's CSS tab) from a prompt (P1) or a reference image/PDF (P2, *"style like this"*).
2. **A collapsible AI panel** rendered immediately **below the editor header** (above the form body) containing:
   - A **prompt textarea** — 3 rows tall by default, vertically stretchable — for free-form instructions (e.g. *"write me an article about astronomy, but do not fill SEO fields"*).
   - A **"Read excerpt" checkbox** — when checked, the page's `excerpt` field is sent as input context. (Default-on for *Write an article from excerpt* / first generate.)
   - A **"Generate only image from the prompt" checkbox** — when ON, clicking Generate/Send runs **image generation** (§3.7) instead of field generation: the prompt becomes an image-generation prompt, an image is generated (Replicate / Black Forest Labs FLUX), **immediately uploaded to the global CMS image gallery**, and an `<img>` referencing that gallery image is appended to `content_html`.
   - A **Generate** button + inline status/error.

The request to the LLM **and the response** are **JSON**. The model returns a structured object of CMS fields (some intentionally left empty per the prompt); the helper writes only the non-empty fields into the form. **Which fields are sent into the request and which the model populates is admin-configured** (a *field manifest*, §3.4), not hard-coded — so an operator can extend it to **S77 custom fields** without code changes. The LLM is **OpenAI- and Anthropic-protocol compatible**, configured (endpoint, key, model, parameters) **server-side** in the plugin config and editable in admin settings.

### Decisions locked (2026-06-13)

- **One plugin — `cms-ai`.** This feature is built **inside the existing `cms-ai` plugin** (`vbwd-backend/plugins/cms-ai/`, where loopai is vendored). There is **no** separate `cms-ai-helper` plugin (reverses the 2026-06-06 draft).
- **New engine — LoopForge (built fresh, not loopai).** A clean, abstract, **multi-step** pipeline engine, written TDD/SOLID/Liskov, as a **self-contained, import-clean sub-package** (`plugins/cms-ai/loopforge/`) with **zero Flask / SQLAlchemy / session / web imports**, so it can ship later as a **pip dependency or git submodule**. loopai (`plugins/cms-ai/cms-ai/loopai/`) is **concept reference only** — not imported, not ported, not run (its `app_global_config` / `web.*` / `SessionDependent` / `db` coupling is exactly what LoopForge avoids).
- **Backend-proxied.** The browser never holds the LLM key. fe-admin posts to a `cms-ai` backend endpoint; endpoint/key/model/params live in the backend plugin config (admin-editable).
- **Stateless generate; the user owns persistence.** `generate` returns a **patch**; nothing is written server-side. The FE fills the editor form (core fields **and** the S77 custom-field inputs); values persist **only on Save** — core fields via the post save, custom fields via **S77's editor save path**, exactly as if the operator had typed them.
- **Manifest-driven fields.** Request-context fields and response (model-populated) fields are declared in an admin-editable manifest on the unified core filesystem (§3.4), not in code. Extensible by other developers.
- **Phased.** **P1** = text generation (prompt + excerpt → article/SEO/CSS/custom-fields, JSON I/O, dual protocol, config + manifest UI) **+ image generation** (prompt → Replicate/FLUX → global gallery → `content_html`). **P2 = file uploads** (images + documents *into* the model). This sprint specifies all; **P1 is the shippable unit**.
- **Image generation via Replicate (Black Forest FLUX).** Ported clean into LoopForge as a `ReplicateImageAdapter` (concept from loopai's `ReplicateExecutor` + `black-forest-labs/flux-schnell`); the generated asset is uploaded to the **global CMS image gallery** via CMS's own service, then referenced from `content_html`. Replicate token is server-side only.
- **Provider JSON mode + schema.** Force valid JSON (OpenAI `response_format=json_object` / Anthropic tool-use), validate against the manifest's field schema, repair/retry malformed output.

## 2. Context (verified against the code)

- **One unified editor.** `vbwd-fe-admin/plugins/cms-admin/src/views/PostEditor.vue` is the live editor for **both posts and pages** (`form.type === 'page' | 'post'`); `CmsPageEditor.vue` is retired. The AI helper attaches to `PostEditor.vue` and therefore covers both.
- **Header action bar** is `.post-editor__actions` (`PostEditor.vue:9–45`) — the `AI ✨` dropdown sits here, before Save. The collapsible panel mounts between `.post-editor__header` (`:3–46`) and `.post-editor__body` (`:55`).
- **All core target fields already exist on `form`** (`PostEditor.vue:693–751`) and on the backend `CmsPost` model (`vbwd-backend/plugins/cms/src/models/cms_post.py:69–112`): `content_html`, `content_json`, `excerpt`, `meta_title`, `meta_description`, `meta_keywords`, `og_title`, `og_description`, `og_image_url`, `canonical_url`, `robots`, `schema_json`. **No model/migration change** — the helper only populates existing fields. Excluded from AI authorship: `type`, `layout`, `style` (structural, operator-owned).
- **Unified core filesystem (admin-editable assets).** `vbwd/services/asset_storage.py` resolves `${VBWD_VAR_DIR:-/app/var}/assets/<owner>/...` (host-mounted, admin-editable). This is the *same* pattern as `var/assets/core/email/templates` (`email_service.py:93`, `core_exchangers.py:575`). The LoopForge config triple (§3.4) lives here under owner `cms-ai`. The richer `vbwd/services/filesystem/` (`FilesystemManager`) is available if directory listing/write is needed for the admin editor.
- **S77 (Tags & Custom Fields) is the persistence owner for custom fields.** S77 registers `cms_post` as an entity type and mounts a **custom-fields editor** on the post editor (`get_field_defs("cms_post")`, `set_custom_fields`). cms-ai **fills** those inputs from the model output; S77's save persists them. cms-ai has a **soft dependency** on S77 for the custom-field path (declared in `PluginMetadata.dependencies`); absent S77, the manifest simply carries core fields only.
- **LoopForge owns the LLM adapter outright.** Dual-protocol (OpenAI + Anthropic) + JSON-repair are written **fresh inside LoopForge** — **no** other plugin's adapter is referenced, imported, or copied (DRY by clean design within LoopForge, not cross-plugin reuse). Keeping LoopForge self-contained is what makes it extractable as a pip dep / git submodule.
- **fe-admin extension pattern:** `vbwd-fe-admin/vue/src/plugins/extensionRegistry.ts` (`ExtensionRegistry` with `register(pluginName, ext)` / typed `get*()`; `AdminExtension` at `:115–139`). `cms-admin` registers nav sections in `install()` (`plugins/cms-admin/index.ts:46–58`). The editor has **no** extension slot yet — S41 adds two small, AI-agnostic seams.

## 3. Design

### 3.0 LoopForge — the clean pipeline engine (`plugins/cms-ai/loopforge/`)

A fresh, import-clean Python package: **no Flask, no SQLAlchemy, no thread-local session, no vbwd-core import.** It is the reusable pipeline engine inspired by loopai's *concepts* (step template, dual-protocol LLM call, JSON-repair, multi-step looping) but rebuilt to SOLID/Liskov so it extracts cleanly to a pip dep / git submodule later. It is unit-tested in isolation (pure, no DB).

```
plugins/cms-ai/loopforge/
├── __init__.py            # public surface: run_flow(), StepTemplate, Flow, LlmAdapter, LoopForgeError
├── template.py            # StepTemplate: render {system_content, user_content, model, temperature} from vars
├── flow.py                # Flow + FlowRunner: ordered multi-step pipeline; each step's output feeds the next scope
├── adapter.py             # LlmAdapter (ABC) + OpenAiAdapter + AnthropicAdapter (one generate() surface)
├── image.py               # ImageAdapter (ABC) + ReplicateImageAdapter — prompt → image bytes (Black Forest FLUX)
├── json_io.py             # is_valid_json / clean / repair + validate-against-schema + retry loop
├── errors.py              # LoopForgeError (+ subtypes)
└── tests/                 # pure unit tests (no network: SDK clients mocked)
```

- **`StepTemplate.render(scope) -> RenderedStep`** — pure substitution (Jinja2 if present in the backend, else a minimal safe `{{var}}` substituter; **no new heavy dep**). Unknown/missing vars render empty, never raise.
- **`LlmAdapter.generate(system_content, user_content, *, model, temperature, json_schema) -> dict`** — **one Liskov-substitutable surface**, two impls, **each using its provider's official Python SDK** (not hand-rolled HTTP):
  - **Provider is chosen by model name** (the only discriminator): `model` starting `claude-` → `AnthropicAdapter`; everything else → `OpenAiAdapter`. A small `select_adapter(model)` factory in `adapter.py` encapsulates this so callers never branch on provider. (Endpoint/key still come from config; the model string decides which SDK client is built.)
  - **`OpenAiAdapter`** — the **`openai` SDK** (`OpenAI(base_url=endpoint, api_key=key)`, `client.chat.completions.create(..., response_format={"type":"json_object"})`); reads `choices[0].message.content`. `base_url` lets it also drive OpenAI-compatible endpoints.
  - **`AnthropicAdapter`** — the **`anthropic` SDK** (`Anthropic(api_key=key, base_url=endpoint)`, `client.messages.create(model=…, system=…, messages=…, max_tokens=…)`); JSON forced via a single tool + `tool_choice` (or a system instruction), reads the tool-use input / `content[0].text`.
  - Both are wrapped in the **JSON validate/repair/retry** loop (re-prompt up to N on invalid JSON), then `LoopForgeError` on SDK/transport error or unparseable output. **Never echoes the key.** The two SDKs (`openai`, `anthropic`) are LoopForge's only runtime deps beyond stdlib — declared in its package metadata so extraction carries them.
- **`ImageAdapter.generate(prompt, *, model, width, height) -> bytes`** — **one Liskov-substitutable surface** for text-to-image; `ReplicateImageAdapter` uses the **`replicate` SDK** (`replicate.Client(api_token=…).run(model, input={prompt,width,height})`), normalises the response (URL / `FileOutput` / list / dict — as loopai's `ReplicateExecutor` does), downloads, and returns **JPEG bytes** (default model `black-forest-labs/flux-schnell` — *Black Forest Labs FLUX on Replicate*). Errors → `LoopForgeError`. Returns raw bytes only — **no gallery, no DB, no filesystem** (that stays in the plugin, keeping the adapter extractable). The provider/model are config, so a different Replicate model or another image provider is a new adapter behind the same surface.
- **`FlowRunner.run(flow, scope) -> dict`** — executes an ordered list of steps; each step renders against the accumulating scope, calls the relevant adapter (LLM **or** image), validates, and merges its output back into the scope for downstream steps. A **single-step flow is just a flow of length 1** (Liskov: the editor actions are single-step today; *article → SEO → image* is the same runner with an image step appended, P2+).
- **Config in, data out.** LoopForge receives endpoint/key/model/params and the template/flow/manifest **as plain data** (the plugin reads them from asset-storage and passes them in). The engine never touches the filesystem itself — that keeps it extractable.
- **Attribution:** package docstring credits loopai (`plugins/cms-ai/cms-ai/loopai`) as the conceptual origin; **no import** from it.

### 3.1 Backend `cms-ai` plugin wiring (route → service → LoopForge)

The editor-generate feature is added to the existing `cms-ai` plugin, layered **route → service → LoopForge** (DI/factory per the plugin's wiring; register providers in `on_enable` per [[project_plugin_di_provider_registration]] if the container is used). **No models, no migration, no DB** for this path — stateless generate (token billing/history out of scope).

**(a) Asset loader.** Resolves the active template/flow/manifest from `${VBWD_VAR_DIR}/assets/cms-ai/prompts/` via `asset_storage.py` (owner `cms-ai`), falling back to defaults shipped in the plugin. So prompts/flows/manifests are tunable per instance **without code changes**.

**(b) Service — `CmsAiGenerateService`.** Orchestrates: pick template/flow + manifest for the `action` → build the variable scope from request + config + the **manifest's request-context fields** (excerpt included only if `read_excerpt`) → derive `json_schema` + `requested_fields` from the **manifest's response fields** → `FlowRunner.run` → **validate** output against the manifest schema (drop unknown keys, enforce types, `schema_json` must be an object, sanitise `source_css`) → return the **patch** (only model-filled keys). The service is the only layer that knows about vbwd config/asset-storage/S77 def-fetching; LoopForge stays pure.

**(c) S77 awareness (custom-field response targets).** When the manifest's response set names custom-field keys, the service enriches the LLM instruction with those defs' types/options via the S77 port (`get_field_defs("cms_post")`) so the model produces valid values. It **does not persist** them — they ride back in the patch and land in the S77 editor inputs (§3.3 / §3.5).

**(d) Route (admin-only).**
- `POST /api/v1/plugins/cms-ai/generate` — `@require_admin` (permission `cms.manage`, matching the editor's `canManage`).
  Request: `{ action, prompt, read_excerpt, context: { title, excerpt, content_html, source_css, type, custom_fields? } }`.
  Response: `{ patch: { <field>: value, ... }, provider, model, steps? }`. Errors → 4xx/5xx with a safe message (**never echo the key**).
- *(Optional, admin)* `GET|PUT /api/v1/plugins/cms-ai/prompts/<file>` — read/write the asset-storage triple for the in-admin editor (gated `settings.manage`). May be deferred to a follow-up if the files are edited host-side initially.

**Config (server-side, `DEFAULT_CONFIG` merged on `initialize`):**
```python
DEFAULT_CONFIG = {
    "debug_mode": False,
    "llm_api_endpoint": "",        # base URL or full path
    "llm_api_key": "",
    "llm_model": "gpt-4o-mini",    # provider inferred from model prefix (claude-* → Anthropic)
    "temperature": 0.7,
    "max_tokens": 4000,
    "timeout": 60,
    "json_retry_max": 3,           # LoopForge JSON-repair loop
    "prompts_dir": "",             # optional override; default → ${VBWD_VAR_DIR}/assets/cms-ai/prompts
    # image generation (Replicate / Black Forest FLUX) — §3.7
    "image_enabled": True,
    "replicate_api_token": "",     # Replicate API token (separate from the LLM key)
    "image_model": "black-forest-labs/flux-schnell",
    "image_width": 1024,
    "image_height": 1024,
}
```
**Plugin baseline (BINDING):** `config.json` + `admin-config.json` exposing a settings tab — `llm_api_endpoint`, `llm_api_key` (**password component**), `llm_model`, `temperature`, `max_tokens`, `timeout`, `json_retry_max`, `image_enabled`, `replicate_api_token` (**password component**), `image_model`, `image_width`, `image_height`, `debug_mode`. Per [[feedback_plugin_baseline_config_files]].

### 3.2 Editor seams in `cms-admin` (AI-agnostic)

`cms-admin` (host of `PostEditor.vue`) exposes two extension slots so the helper lives in its **own** fe plugin and `cms-admin` knows nothing about AI. Mirror the existing registry style (local `cmsEditorExtensionRegistry` in `cms-admin`, keeping `AdminExtension` lean).

- **`cmsEditorHeaderActions`** — rendered inside `.post-editor__actions` (before Save) via `<component :is>`. Hosts the `AI ✨` dropdown.
- **`cmsEditorPanels`** — rendered between header and body. Hosts the collapsible AI panel.

Both slots receive one typed **editor context** prop (narrowest surface):
```ts
interface CmsEditorContext {
  form: Ref<PostForm>;                          // reactive form (read title/excerpt/content_html/type)
  applyPatch(patch: Partial<PostForm>): void;   // write back only filled fields (core + S77 custom-field inputs)
  getContext(opts: { readExcerpt: boolean }): { title; excerpt; content_html; type; custom_fields? };
}
```
`PostEditor.vue` provides this context object and renders both slots. **Empty registry → editor renders exactly as today** (Liskov null default). This is the only change to `cms-admin`/`PostEditor.vue`; it stays AI-unaware.

### 3.3 The CMS-field JSON contract (manifest-derived)

The schema the model fills and the service validates is **derived from the field manifest** (§3.4), not a hard-coded literal. Its **default** contribution is the core, AI-authorable `CmsPost` fields (URLs/robots/canonical/type/layout/style are NOT model-invented):
```jsonc
{
  "content_html":     "string|null",   // article body, HTML
  "source_css":       "string|null",   // page/post-scoped CSS (the CSS tab)
  "excerpt":          "string|null",
  "title":            "string|null",
  "meta_title":       "string|null",
  "meta_description": "string|null",
  "meta_keywords":    "string|null",
  "og_title":         "string|null",
  "og_description":   "string|null",
  "schema_json":      "object|null"     // JSON-LD
}
```
- The manifest may **add** entries (e.g. S77 custom-field keys, with the def's type/options) or **remove** them — that is the admin's "add/remove request & response fields" knob.
- `null`/omitted → field left untouched. Non-null → written via `applyPatch` (core field) **or** into the matching S77 custom-field input.
- Action → requested-field set (manifest-overridable): **article** = `{content_html, title?, excerpt?}`; **seo** = `{meta_*, og_title, og_description, schema_json}`; **restyle** = `{source_css, content_html?}`; **freeform** = model decides from the prompt.
- `source_css` is sanitised/validated server-side as a CSS string (no `<script>`, plain stylesheet text).

### 3.4 The field manifest + LoopForge config triple (admin-editable, unified core FS)

Stored under `${VBWD_VAR_DIR}/assets/cms-ai/prompts/` (owner `cms-ai`), resolved by `asset_storage.py`, host-mounted and **admin-editable** — same convention as core email templates. Three files, the loopai-native shape, rebuilt for LoopForge:

- **`template-1.json`** — a **step template** (`{ model, temperature, system_content, prompt }` with `{{variables}}`). The user's free-form text is just the `{{ user_prompt }}` variable.
  ```jsonc
  {
    "model": "{{ llm_model }}",
    "temperature": "{{ temperature }}",
    "system_content": "You are a CMS content writer. Reply with ONE JSON object matching this schema (omit/null any field you are told not to fill): {{ json_schema }}. Requested fields: {{ requested_fields }}.",
    "prompt": "{{ user_prompt }}\n{% if read_excerpt %}Source excerpt: {{ excerpt }}{% endif %}\nPage title: {{ title }}\n{% if existing_content %}Existing content (HTML): {{ content_html }}{% endif %}"
  }
  ```
- **`loopforge-flow-1.yaml`** — the **flow** (ordered steps). P1 ships single-step flows per action; the format is multi-step-ready (e.g. `article → seo → image`) for a later increment.
  ```yaml
  flow:
    name: article
    steps:
      - template: template-1.json
        vars: template-1-vars.json
  ```
- **`template-1-vars.json`** — the **field manifest**: which fields go **into** the request as context, and which fields the model **populates** in the response (the add/remove-fields knob).
  ```jsonc
  {
    "request_context": ["title", "excerpt", "content_html", "type"],
    "response_fields": {
      "content_html": { "type": "string" },
      "title":        { "type": "string" },
      "excerpt":      { "type": "string" }
      // admin adds S77 custom-field keys here, e.g.:
      // "reading_time": { "type": "number", "custom_field": true }
    }
  }
  ```

The service composes these into LoopForge inputs; **retuning prompts, flows, or the in/out field sets is a file edit, no code change**. Other developers extend by shipping additional template/flow/manifest sets.

### 3.5 fe-admin plugin `cms-ai`

New fe plugin `vbwd-fe-admin/plugins/cms-ai/` (named-export convention; registers into the §3.2 seams in `install()`):
- **`CmsAiMenuButton.vue`** → `cmsEditorHeaderActions`. `AI ✨` button (`data-testid="cms-ai-menu"`) opening a dropdown (`cms-ai-action-article`, `…-seo`, `…-restyle`). Selecting an action sets the panel intent (toggles "Read excerpt" on for *article*) and opens the panel, or fires generate.
- **`CmsAiPanel.vue`** → `cmsEditorPanels`. Collapsible (`<details>`, `data-testid="cms-ai-panel"`). Contains the prompt `<textarea>` (`rows="3"`, `resize:vertical`, `cms-ai-prompt`), the **Read excerpt** checkbox (`cms-ai-read-excerpt`), the **"Generate only image from the prompt"** checkbox (`cms-ai-image-only`, shown only when `image_enabled`), and **Generate** (`cms-ai-generate`). On generate: if **image-only** is ON → `POST` to `…/generate-image` and `applyPatch({content_html})` (image already in the gallery, §3.7); else → build the request from `getContext({readExcerpt})` + prompt + action, `POST` to `…/generate`, then `applyPatch(response.patch)` — routing core keys to form fields and custom-field keys to the **S77 custom-field inputs**. Shows loading + error inline; **never auto-saves the post** — the operator reviews and clicks Save.
- **Reuse default core styles (BINDING).** Both components style **only** through the **`vbwd-fe-core` design system** — existing shared classes + `var(--vbwd-*)` custom properties for buttons, inputs, the textarea, checkbox, dropdown, and panel. **No bespoke colours, spacing, or one-off CSS**; the `AI ✨` button and panel must visually match the editor's existing controls and inherit the active theme (theme-switcher / dark mode work for free). If a needed primitive (e.g. a dropdown menu or collapsible panel shell) isn't in fe-core yet, add it **to fe-core** and consume it — do not fork a local style. Per the fe-core design-system rule ([[project_fe_core_design_system]]).
- **Plugin baseline:** `config.json` + `admin-config.json` (at least `debug_mode`) per [[feedback_plugin_baseline_config_files]]. i18n `locales/*.json` across the fe-admin locale set (`en,de,es,fr,ja,ru,th,zh`), wired via `sdk.addTranslations`.

### 3.6 Save path (who persists what)

1. `generate` returns a patch; **nothing is persisted server-side**.
2. `applyPatch` writes core fields onto `form` and custom-field values into the **S77 custom-fields editor** inputs (mounted on the post editor by S77).
3. The operator reviews and clicks **Save**. Core fields persist via the post save; **custom fields persist via S77's editor save path — exactly as if the operator had typed them.** cms-ai writes no custom-field value directly.

### 3.7 Image generation (Replicate / Black Forest FLUX — prompt → gallery → content)

A first-class action driven by the **"Generate only image from the prompt"** checkbox. Unlike text generation (stateless, returns a patch), the image path **does persist** — it writes the asset to the global gallery immediately, by the operator's explicit intent.

**Flow (backend `POST /api/v1/plugins/cms-ai/generate-image`, `@require_admin` `cms.manage`):**
1. **Generate** — `LoopForge ReplicateImageAdapter.generate(prompt, model=image_model, width, height)` → JPEG **bytes** (Replicate, Black Forest FLUX). LoopForge does only this; it touches no DB/gallery.
2. **Upload to the global gallery** — the plugin service hands the bytes to **CMS's `CmsImageService.upload_image(file_data, filename, mime_type="image/jpeg", caption=<prompt>)`** (the same global media gallery as `POST /api/v1/admin/cms/images/upload`). Returns the gallery image dict (`id`, `slug`, `url_path`, `caption`). This is a **declared `cms` plugin dependency** (`PluginMetadata.dependencies`); cms-ai is a CMS companion, so a narrow declared dep + service reuse is the narrowest option (no duplicate upload logic). [[feedback_core_never_depends_on_plugins]]
3. **Return a patch** — `{ patch: { content_html: <appended> }, image: { id, slug, url_path } }`. The service appends an `<img src="{url_path}" alt="{caption}" data-cms-image="{slug}">` (the canonical "image from the global gallery" markup the renderer already understands) to the **current** `content_html` and returns it.
4. **FE** — `applyPatch` writes the new `content_html` into the editor body. **The image asset is already persisted in the gallery** (step 2); only the **post content reference** waits for the operator to click **Save** (consistent with §3.6 — generate never auto-saves the post). If the operator discards the post, the gallery image simply remains in the gallery (reusable), which is the intended global-gallery behaviour.

**Notes:** `image_enabled=false` (or empty `replicate_api_token`) → the checkbox is hidden/disabled and the endpoint 4xx's with a safe message. The token is **never** sent to the browser. This action is also the `image` **step** referenced by the multi-step `article → seo → image` flow (§3.0/§3.4) — same adapter, reached programmatically instead of via the checkbox.

### 3.8 P2 — file uploads (next increment, specified, not built in P1)

- Panel gains an upload control (images + documents). Files post (multipart/base64) to the same endpoint; LoopForge's adapter attaches them as provider-native multimodal blocks (OpenAI `image_url` / Anthropic `image` base64; documents extracted server-side or passed as supported doc blocks). Validation: type/size caps from config.
- **"Style like this":** an uploaded image/PDF + a prompt drives the **restyle** action — the model derives `source_css` (and optionally `content_html`) from the visual reference. Same JSON contract, same `applyPatch`.
- **P2 is a separate gate-green increment.**

### 3.9 Deliberately NOT built (NO OVERENGINEERING)

No token billing/accounting, no generation history/persistence, no streaming, no post auto-save, no new DB tables/migrations, no server-side custom-field writes (S77 owns that), no in-editor image editing/cropping (the gallery owns resize). LoopForge ships only what the editor actions need (single-step text + single-shot image in P1; the multi-step flow format is forward-compatible, not exercised yet). The seam carries only `form` + `applyPatch` + `getContext`. P1 text generation is text-in/JSON-out; image generation is text-prompt-in/asset-out (no file uploads *into* the model — that's P2).

## 4. TDD plan (RED first)

**LoopForge (pure unit, no network/DB):**
- `template`: renders `{system_content,user_content,model,temperature}` from a var scope; `read_excerpt=false` omits the excerpt block; missing var → empty, never raises.
- `adapter`: `select_adapter(model)` returns `AnthropicAdapter` for `claude-*` and `OpenAiAdapter` otherwise (the model-name discriminator); OpenAI path calls `client.chat.completions.create` with `response_format` json + parses `choices[0].message.content`; Anthropic path calls `client.messages.create` with the tool + `tool_choice` + parses tool-use input; **JSON-repair/retry** re-prompts on invalid JSON up to N then `LoopForgeError`; SDK/transport error → `LoopForgeError`. (**SDK clients mocked** — no network.)
- `image`: `ReplicateImageAdapter.generate` calls `replicate.Client.run` with `{prompt,width,height}`, normalises URL / `FileOutput` / list / dict responses, downloads, returns **JPEG bytes**; SDK/download error → `LoopForgeError`. (**`replicate` client + HTTP mocked** — no network.)
- `flow`: a single-step flow returns that step's validated output; a **two-step** flow feeds step-1 output into step-2 scope and merges both (multi-step proof, even if P1 wires only single-step).

**Backend `cms-ai` plugin (pytest):**
- `asset loader`: prefers `${VBWD_VAR_DIR}/assets/cms-ai/prompts/<file>` over the shipped default.
- `service`: builds scope from the **manifest's request_context** (excerpt only if `read_excerpt`); derives `json_schema`/`requested_fields` from **manifest response_fields**; **validates** model output (drops unknown keys, rejects non-object `schema_json`, sanitises `source_css`, leaves `null` out of the patch); custom-field keys in the manifest get the S77 def type/options injected into the instruction (S77 port mocked). LoopForge mocked.
- `route`: `POST /generate` requires admin (403 without `cms.manage`); happy path returns `{patch,...}`; adapter error → 5xx, **no key leakage**.
- `image route/service`: `POST /generate-image` requires admin; generates bytes (LoopForge mocked) → calls `CmsImageService.upload_image` (mocked) → returns `{patch:{content_html}, image:{url_path,...}}` with the `<img …data-cms-image>` appended to the prior `content_html`; `image_enabled=false` / empty token → 4xx; token never in the response. (`CmsImageService` mocked — no real upload.)

**fe-admin (Vitest, mount with i18n + pinia):**
- `CmsAiPanel`: renders prompt textarea (3 rows) + read-excerpt checkbox + **image-only checkbox** + generate button; generate posts the built request (api client mocked) and calls `applyPatch` with the patch; null fields not applied; custom-field keys routed to the S77 inputs; error renders inline; does **not** mutate omitted fields and does **not** save. **Image-only ON** → posts to `…/generate-image` and applies the returned `content_html` (with the appended `<img>`); image-only checkbox hidden when `image_enabled` is false.
- `CmsAiMenuButton`: dropdown shows actions; selecting *article* turns read-excerpt on + opens panel.
- **Seam spec**: a component registered in `cmsEditorHeaderActions`/`cmsEditorPanels` renders in the editor (assert DOM placement). **Empty registry → editor unchanged.**

## 5. Files (indicative)

| Action | Path |
|---|---|
| new | `vbwd-backend/plugins/cms-ai/loopforge/{__init__,template,flow,adapter,image,json_io,errors}.py` — the LoopForge engine (import-clean, pip/submodule-ready) |
| new | `vbwd-backend/plugins/cms-ai/loopforge/tests/...` — pure engine unit tests (incl. `ReplicateImageAdapter`) |
| new | `vbwd-backend/plugins/cms-ai/cms-ai/services/cms_ai_generate_service.py` — asset loader + manifest + LoopForge orchestration + validation |
| new | `vbwd-backend/plugins/cms-ai/cms-ai/services/cms_ai_image_service.py` — image gen → `CmsImageService.upload_image` → `content_html` `<img>` patch |
| new | `vbwd-backend/plugins/cms-ai/cms-ai/routes.py` (or extend) — `POST /api/v1/plugins/cms-ai/generate` + `POST …/generate-image` (+ optional prompts read/write) |
| new | `vbwd-backend/plugins/cms-ai/templates/prompts/{template-1.json,loopforge-flow-1.yaml,template-1-vars.json}` — shipped defaults (copied to asset-storage on first run / overridable there) |
| edit | `vbwd-backend/plugins/cms-ai/__init__.py` — `DEFAULT_CONFIG` (LLM + image/Replicate + `json_retry_max` + `prompts_dir`), declare soft **S77** dep + **`cms`** dep (gallery) in `PluginMetadata.dependencies` |
| new | `vbwd-backend/plugins/cms-ai/{config.json,admin-config.json}` (+ LLM + image settings, `debug_mode`) |
| new | `vbwd-backend/plugins/cms-ai/tests/{unit,integration}/...` (+ `conftest.py`) |
| edit | `vbwd-backend/plugins/plugins.json` + `plugins/config.json` — register & enable |
| new | `vbwd-fe-admin/plugins/cms-ai/index.ts` — registers into the editor seams |
| new | `vbwd-fe-admin/plugins/cms-ai/src/components/{CmsAiMenuButton,CmsAiPanel}.vue` |
| new | `vbwd-fe-admin/plugins/cms-ai/{config.json,admin-config.json}` (+ `debug_mode`) |
| new | `vbwd-fe-admin/plugins/cms-ai/locales/*.json` |
| new | `vbwd-fe-admin/plugins/cms-ai/tests/unit/*.spec.ts` |
| edit | `vbwd-fe-admin/plugins/cms-admin/src/views/PostEditor.vue` — provide `CmsEditorContext`, render the two seams |
| new/edit | `cms-admin` editor extension registry (`cmsEditorHeaderActions` / `cmsEditorPanels`) |
| new | `docs/dev_log/20260613/walkthrough/s41-WALK-REPORT-cms-ai.html` + screenshots — Playwright-generated live proof (DoD) |
| new | `vbwd-backend/plugins/cms-ai/docs/developer/` — LoopForge + manifest developer docs (md **and** html, with screenshots) |

## 6. Acceptance (P1)

- The editor (new or edit, page **or** post) shows an **`AI ✨` dropdown** in the header and a **collapsible AI panel** below it with a 3-row stretchable prompt textarea, a **Read excerpt** checkbox, and a **Generate** button.
- *Write an article from excerpt* with **Read excerpt** on sends excerpt + prompt to the backend, which calls the configured LLM (OpenAI **or** Anthropic) via LoopForge and returns JSON; `content_html` (and optionally title/excerpt) is filled, **SEO untouched**.
- *Re-generate all SEO fields* fills `meta_*`/`og_*`/`schema_json` from current title+content; body untouched.
- *Restyle the page* fills/replaces `source_css`; body and SEO untouched.
- A free-form prompt like *"…but do not fill SEO fields"* leaves those fields `null`/untouched.
- An admin who **adds an S77 custom-field key to `template-1-vars.json`** sees the model fill that field; it lands in the S77 custom-field input and persists **only** when the operator clicks Save (via S77).
- With **"Generate only image from the prompt"** ON, clicking Generate produces an image (Replicate / Black Forest FLUX), **uploads it to the global CMS image gallery immediately**, and appends an `<img …data-cms-image>` (referencing the gallery image) to `content_html`. The image is in the gallery before Save; the post content reference persists on Save. The Replicate token is **never** in the browser/network payload.
- The API key is **never** present in the browser/network payload.
- With `cms-ai` (either repo) disabled, the editor renders exactly as before (seams empty).
- **LoopForge is import-clean** (no Flask/SQLAlchemy/session/vbwd-core import) — provable by its standalone test run.
- The AI button + panel **reuse the `vbwd-fe-core` design system** (shared classes + `var(--vbwd-*)`), visually match the editor's existing controls, and inherit the active theme — **no bespoke/one-off CSS**.
- **`bin/pre-commit-check.sh --full` GREEN on both `vbwd-backend` and `vbwd-fe-admin`.**

## 7. Definition of Done

- All §6 acceptance met; **`bin/pre-commit-check.sh --full` GREEN** on `vbwd-backend` and `vbwd-fe-admin`; LoopForge unit suite green in isolation.
- **Live proof — Playwright HTML walkthrough report with real screenshots** at `docs/dev_log/20260613/walkthrough/s41-WALK-REPORT-cms-ai.html` (mirroring the s84/s81/s77 walkthroughs), driving the running stack:
  - **fe-admin (8081):** open the post editor, show the `AI ✨` dropdown + AI panel; run each action (article / SEO / restyle) and screenshot the populated fields.
  - **Image generation:** tick **"Generate only image from the prompt"**, enter an image prompt, Generate → screenshot (a) the new `<img>` in the editor body and (b) the same image now present in the **global image gallery** (`/admin/cms/images`).
  - **Live test (headline):** operator enters the prompt *"make me a page which looks like this https://backlinko.com/google-analytics-alternatives and it is a post about VBWD. Override styles"* → Generate → Save.
  - **fe-user (8080):** screenshot the rendered page **next to the reference URL** as side-by-side proof it looks similar (proof-of-work, human-judged — **not** a pixel-diff assertion; hard asserts stay on mechanics: fields populated, page renders, `source_css` applied).
  - Each step captioned with the action + observed result; real screenshots, not mockups.
- **Developer docs (md AND html, with screenshots)** under `vbwd-backend/plugins/cms-ai/docs/developer/`: how LoopForge works (template/flow/LLM-adapter/**image-adapter**/json-repair, the import-clean boundary, how to add a step, an LLM provider, or an **image provider**), how **image generation → global gallery → `content_html`** is wired (Replicate/FLUX + `CmsImageService`), and how to author/extend the **field manifest** (request_context + response_fields, adding S77 custom fields, shipping a new template set). The html mirrors the md and embeds the screenshots.
- Not committed ([[feedback_no_commit_without_ask]]).

## 8. Out of scope (this sprint)

- **P2 file uploads** (images/documents *into* the model) — specified in §3.8, next increment. (Image *generation* — §3.7 — IS in P1.)
- Token billing, generation history, streaming, auto-save, fe-user authoring surfaces.
- Multi-step flow *execution* in the editor (the LoopForge format + a two-step engine test prove it; the editor actions stay single-step in P1).
- Extracting LoopForge to its own repo (it ships import-clean *in place*, ready for later extraction).

## 9. Engineering-requirements check

- **Core agnostic:** both plugins self-contained; `cms-admin`/`PostEditor.vue` gain only AI-unaware seams (empty registry → no change); no `vbwd/` core edit. [[project_s01_core_agnosticism_oracle]]
- **SOLID/Liskov:** one `LlmAdapter.generate()` surface (two protocol impls) + one `ImageAdapter.generate()` surface (Replicate impl) — all substitutable; single-step = a flow of length 1 (same runner); template engine pure; empty seam = null default; service validates against the manifest schema.
- **DI/DRY:** layered route→service→LoopForge ([[project_plugin_di_provider_registration]]); OpenAI/Anthropic + JSON-repair + Replicate image-gen live once in LoopForge (built fresh, **not** cross-plugin-imported); the gallery upload **reuses** CMS's `CmsImageService` (declared `cms` dep — no duplicate upload logic); prompts/flows/fields live in admin-editable assets, not duplicated in code.
- **NO OVERENGINEERING:** loopai **not** embedded/ported (its session/DB/web coupling would threaten the gate) — LoopForge is the minimal clean engine the feature needs; no DB/migration of its own (image assets reuse the existing gallery), no billing/history/streaming; server-side custom-field writes deferred to S77; P1 = single-step text + single-shot image.
- **Declarative, admin-tunable:** template + flow + field-manifest are admin-editable files on the unified core filesystem — no code change to retune prompts or the in/out field sets.
- **Reuse default core styles:** the AI button + panel style only through the `vbwd-fe-core` design system (shared classes + `var(--vbwd-*)`), inherit the active theme, and add any missing primitive **to fe-core** — no bespoke/one-off CSS. [[project_fe_core_design_system]]
- **Plugin baseline:** `config.json` + `admin-config.json` (incl. `debug_mode`) in both plugins; LLM settings admin-editable, key as password. [[feedback_plugin_baseline_config_files]]
- **TDD-first / gate:** LoopForge + adapter/service/route + component/seam specs land RED first; `bin/pre-commit-check.sh --full` green on both repos = done. Implementation delegated to the **`vbwd-tdd`** agent. [[feedback_use_tdd_agent_for_implementation]]
- **Reusable engine:** LoopForge is import-clean and packaged as a bounded sub-package, ready to become a pip dep / git submodule.
- **Plugin deps declared:** `PluginMetadata.dependencies` notes the soft **S77** dep (custom-field path) and the **`cms`** dep (global image gallery for image generation). [[feedback_core_never_depends_on_plugins]]
