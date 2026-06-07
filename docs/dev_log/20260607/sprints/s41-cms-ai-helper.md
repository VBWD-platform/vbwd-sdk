# S41 — CMS AI Helper: prompt-driven content & SEO generation in the editor

**Status:** DRAFT for negotiation — rewritten 2026-06-06 (supersedes the earlier "dummy scaffold" draft).
**Repos touched:** `vbwd-backend` (new `cms-ai-helper` plugin — the LLM proxy) · `vbwd-fe-admin` (new `cms-ai-helper` plugin + small extension seams in `cms-admin`).
**Engineering requirements (BINDING):** TDD-first · DevOps-first · SOLID · DI · DRY · **Liskov** · clean code · **core agnostic (only plugins are gnostic)** · **NO OVERENGINEERING** (narrowest change that satisfies the req) · **plugin baseline config files** — see [`_engineering_requirements.md`](_engineering_requirements.md). **Gate: `bin/pre-commit-check.sh` GREEN on every touched repo (`--full` = done; `--quick` while iterating).**

---

## 1. Goal

Give the CMS editor an **AI helper** that turns a natural-language prompt (plus the page's own context: excerpt, title, existing content) into structured content + SEO, written back into the editor form fields the operator can then review and save.

Two surfaces in the editor:

1. **An `AI ✨` button with a drop-down of actions** in the editor header action bar (next to Save), with at least:
   - **Write an article from excerpt** — generate `content_html` (and optionally title/excerpt) from the excerpt; leave SEO fields untouched unless asked.
   - **Re-generate all SEO fields** — from the current title + content, (re)fill `meta_title`, `meta_description`, `meta_keywords`, `og_title`, `og_description`, `schema_json`.
   - **Restyle the page** — generate/replace `source_css` (the editor's CSS tab) from a prompt (P1) or a reference image/PDF (P2, *"style like this"*).
2. **A collapsible AI panel** rendered immediately **below the editor header** (above the form body) containing:
   - A **prompt textarea** — 3 rows tall by default, vertically stretchable — for free-form instructions (e.g. *"write me an article about astronomy, but do not fill SEO fields"*).
   - A **"Read excerpt" checkbox** — when checked, the page's `excerpt` field is sent as input context. (Default-on when the user triggers *Write an article from excerpt* / first generate.)
   - A **Generate** button + inline status/error.

The helper can also **rewrite the page/post CSS** (`source_css`): a free-form prompt like *"give this page a dark, minimalist hero"* generates CSS, and in **P2** uploading a reference image/PDF with *"I want a page styled like this"* lets the model derive `source_css` (and optionally `content_html`) from the reference.

The request to the LLM **and the response** are **JSON**: the model returns a structured object of CMS fields (some intentionally left empty per the prompt), and the helper writes only the non-empty fields into the form. The LLM is **OpenAI- and Anthropic-protocol compatible**, configured (endpoint, key, model, parameters) **server-side** in the plugin config and editable in admin settings.

### Decisions locked (2026-06-06)

- **Backend-proxied.** The browser never holds the LLM key. fe-admin posts to a new backend `cms-ai-helper` endpoint; endpoint/key/model/params live in the backend plugin config (admin-editable). Mirrors the existing `chat` plugin.
- **Phased.** **P1 = text-only** (prompt + excerpt → article/SEO, JSON I/O, dual protocol, config UI). **P2 = file uploads** (images + documents to the LLM). This sprint specifies both; **P1 is the shippable unit**, P2 follows.
- **Provider JSON mode + schema.** Force valid JSON (OpenAI `response_format=json_object` / Anthropic tool-use), validate against a fixed CMS-field schema, reject/repair malformed output.

## 2. Context (verified against the code)

- **One unified editor.** `vbwd-fe-admin/plugins/cms-admin/src/views/PostEditor.vue` is the live editor for **both posts and pages** (`form.type === 'page' | 'post'`); `CmsPageEditor.vue` is retired. The AI helper attaches to `PostEditor.vue` and therefore covers both. (Earlier draft wrongly targeted `CmsPageEditor.vue`.)
- **Header action bar** is `.post-editor__actions` (`PostEditor.vue:9–45`) — the `AI ✨` dropdown sits here, before the Save button. The collapsible panel mounts between `.post-editor__header` (`:3–46`) and `.post-editor__body` (`:55`).
- **All target fields already exist on `form`** (`PostEditor.vue:693–751`) and on the backend `CmsPost` model (`vbwd-backend/plugins/cms/src/models/cms_post.py:69–112`): `content_html`, `content_json`, `excerpt`, `meta_title`, `meta_description`, `meta_keywords`, `og_title`, `og_description`, `og_image_url`, `canonical_url`, `robots`, `schema_json`. **No model/migration change** — the helper only populates existing fields.
- **Existing LLM adapter to reuse/generalize:** `vbwd-backend/plugins/chat/src/llm_adapter.py` — OpenAI-compatible (`Bearer` auth, `/chat/completions`, reads `choices[0].message.content`), with `DEFAULT_CONFIG` holding `llm_api_endpoint/llm_api_key/llm_model` (`plugins/chat/__init__.py:9–20`) and url prefix `/api/v1/plugins/chat`. It does **not** yet speak Anthropic `/v1/messages`, JSON mode, or multimodal — S41 adds those in its own adapter (do **not** mutate the chat plugin; DRY by pattern, not by shared import across plugins).
- **fe-admin extension pattern:** `vbwd-fe-admin/vue/src/plugins/extensionRegistry.ts` (`ExtensionRegistry` with `register(pluginName, ext)` / typed `get*()` accessors; `AdminExtension` interface at `:115–139`). `cms-admin` already registers nav sections in its `install()` (`plugins/cms-admin/index.ts:46–58`). The editor itself has **no** extension slot yet — S41 adds two small, AI-agnostic seams.
- **Naming caution:** `vbwd-backend/plugins/cms-ai/` already exists and is an **unrelated** content-automation/looping framework. The new plugin is **`cms-ai-helper`** (both repos) — do not extend `cms-ai`.

## 3. Design

### 3.1 Backend plugin `cms-ai-helper` (YAML-template LLM proxy)

New plugin `vbwd-backend/plugins/cms-ai-helper/` (plugin-ID source dir convention; class in `__init__.py`). **No models, no migration, no DB** — stateless generate (token billing/history out of scope).

**loopai relationship (decided 2026-06-06): adopt the YAML request format + port the proven core; do NOT import the engine.** The vendored loopai at `vbwd-backend/plugins/cms-ai/cms-ai/loopai/core` is a *partial* copy of a standalone Flask app — it does not import (absolute `core.*`/`web.*` imports; `app_global_config` + `web/` absent; every executor extends `SessionDependent` with its own thread-local session, `db`/`loops` table, per-user filesystem dirs). Embedding it would drag that coupling in and threaten the pre-commit gate (NO OVERENGINEERING). What we **reuse by porting** (small, self-contained, well-proven):
- its **YAML request-template format** (`action: { model, system_content, prompt, temperature }` + variables) — the user-facing "LLM request structure in YAML";
- its **dual-protocol switch** — `FeatherlessService` already does OpenAI **and** Anthropic, branching on a `claude-*` model prefix (`featherless_service.py:6-7,18`);
- its **JSON-with-retry/repair loop** — `is_valid_json` / `clean_json_string` / `fix_json` + re-prompt-on-invalid (`llm_executor.py:36-141`).

The plugin is layered: **route → service → template engine → LLM adapter** (DI/factory per the `chat` plugin's actual wiring — verify before coding; register providers in `on_enable` per [[project_plugin_di_provider_registration]] if the container is used).

**(a) Template engine — `PromptTemplateEngine`.** Loads an action's YAML template, resolves `{{variables}}` from the merged variable scope (§3.1b), and produces the concrete `{system_content, user_content, model, temperature}` request. Pure/clean — no network, no session, no DB. The YAML template format (loopai-derived, single step):
```yaml
# templates/article.yaml
action:
  model: "{{ llm_model }}"            # from admin config (default per provider)
  temperature: "{{ temperature }}"
  system_content: |
    You are a CMS content writer. Reply with ONE JSON object matching this schema
    (omit or null any field you are told not to fill): {{ json_schema }}
    Requested fields for this action: {{ requested_fields }}.
  prompt: |
    {{ user_prompt }}
    {% if read_excerpt %}Source excerpt: {{ excerpt }}{% endif %}
    Page title: {{ title }}
    {% if existing_content %}Existing content (HTML): {{ content_html }}{% endif %}
```
- **Variables come from two scopes** (the user's "variables from user's or admin config"): **admin/operator config** (`llm_model`, `temperature`, `json_schema`, `requested_fields` for the action) and **the editor/user request** (`user_prompt`, `read_excerpt`, `title`, `excerpt`, `content_html`, `source_css`). Rendering uses the templating lib already present in the backend (Jinja2 if available — verify; else a minimal safe `{{var}}` substituter — NO new heavy dep).
- Unknown/missing variables render empty (never raise) so a partial context still works.

**(b) Template store — plugin files, admin-overridable** (decided). Defaults ship in `cms-ai-helper/templates/*.yaml` (`article.yaml`, `seo.yaml`, `restyle.yaml`, `freeform.yaml`). An operator may override/add templates in the shared plugin var dir — `${VBWD_VAR_DIR}/plugins/cms-ai-helper/templates/<action>.yaml` (same single-source-of-truth dir pattern as plugin config; resolver prefers VAR_DIR, falls back to the shipped file). So prompts are tunable per instance **without code changes**; the user's free-form text is just the `user_prompt` variable.

**(c) LLM adapter — `CmsAiLlmAdapter`, OpenAI + Anthropic** (ported dual-protocol switch; Liskov: one `generate(system_content, user_content, *, model, temperature, json_schema) -> dict` surface):
  - **OpenAI:** `POST {endpoint}/chat/completions`, `Authorization: Bearer`, `response_format={"type":"json_object"}`, parse `choices[0].message.content`.
  - **Anthropic** (`model` starts `claude-`): `POST {endpoint}/v1/messages`, headers `x-api-key` + `anthropic-version`, JSON forced via a single tool (`tool_choice`) or system instruction, parse tool-use input / `content[0].text`.
  - Wraps the result in the **ported JSON-repair/retry loop** (re-prompt up to N times on invalid JSON). Endpoint-normalization mirrors `chat`'s adapter. Raises typed `CmsAiError` on transport/non-200/unparseable.

**(d) Service — `CmsAiHelperService`.** Orchestrates: pick template for `action` → build the variable scope from request + config (excerpt included only if `read_excerpt`; `json_schema`/`requested_fields` from §3.3 per action) → `PromptTemplateEngine.render` → `CmsAiLlmAdapter.generate` → **validate** output against the §3.3 schema (drop unknown keys, enforce types, `schema_json` must be an object, sanitise `source_css`) → return the **patch** (only model-filled keys).

**(e) Route (admin-only, mirrors chat's prefix).**
  - `POST /api/v1/plugins/cms-ai-helper/generate` — `@require_admin` (permission `cms.manage`, matching the editor's `canManage`).
    Request: `{ action: "article"|"seo"|"restyle"|"freeform", prompt, read_excerpt, context: { title, excerpt, content_html, source_css, type } }`.
    Response: `{ patch: { <cms field>: value, ... }, provider, model }`. Errors → 4xx/5xx with a safe message (**never echo the key**).

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
    "json_retry_max": 3,           # ported from loopai's repair loop
}
```
**Plugin baseline (BINDING):** `config.json` + `admin-config.json` exposing a settings tab — `llm_api_endpoint`, `llm_api_key` (**password component**), `llm_model`, `temperature`, `max_tokens`, `timeout`, `json_retry_max`, `debug_mode`. Per [[feedback_plugin_baseline_config_files]]. **Attribution:** ported code carries a comment crediting `plugins/cms-ai/.../loopai` as the origin (DRY-by-port, not by cross-plugin import — keeps both plugins independent).

**Future seam (NOT this sprint):** because actions are single-step YAML loops, a later sprint can swap `PromptTemplateEngine`+adapter for the real loopai `LoopController` to run *multi-step* pipelines (e.g. article → SEO → image) once loopai is packaged as an importable lib. The YAML format is forward-compatible by design.

### 3.2 Editor seams in `cms-admin` (AI-agnostic)

`cms-admin` (host of `PostEditor.vue`) exposes two extension slots so the helper lives in its **own** plugin and `cms-admin` knows nothing about AI. Mirror the existing registry style (local `cmsEditorExtensionRegistry` in `cms-admin`, or two arrays added to `AdminExtension` — pick per prevailing convention; local registry keeps `AdminExtension` lean).

- **`cmsEditorHeaderActions`** — rendered inside `.post-editor__actions` (before Save) via `<component :is>`. Hosts the `AI ✨` dropdown button.
- **`cmsEditorPanels`** — rendered between header and body. Hosts the collapsible AI panel.

Both slots receive a single, typed **editor context** prop (NOT the raw internals — narrowest surface):
```ts
interface CmsEditorContext {
  form: Ref<PostForm>;                  // reactive form (read title/excerpt/content_html/type)
  applyPatch(patch: Partial<PostForm>): void;  // write back only filled fields
  getContext(opts: { readExcerpt: boolean }): { title; excerpt; content_html; type };
}
```
`PostEditor.vue` provides this context object and renders both slots. **Empty registry → editor renders exactly as today** (Liskov null default). This is the only change to `cms-admin`/`PostEditor.vue`; it stays AI-unaware.

### 3.3 The CMS-field JSON contract (single source of truth)

The schema the model fills and the service validates — only **AI-authorable** fields (URLs/robots/canonical are NOT model-invented):
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
- `null`/omitted → field left untouched in the form. Non-null → written via `applyPatch`.
- Action → requested-field set: **article** = `{content_html, title?, excerpt?}` (SEO/CSS null unless prompt says otherwise); **seo** = `{meta_*, og_title, og_description, schema_json}`; **restyle** = `{source_css, content_html?}`; **freeform** = model decides from the prompt (e.g. *"…but do not fill SEO fields"* → those stay null; *"style like this"* → `source_css`).
- `source_css` is sanitised/validated server-side as a CSS string before it reaches the form's CSS tab (no `<script>`, treated as plain stylesheet text).
- The same schema literal is shared by FE (typing) and BE (validation) by **convention** (documented here), not a cross-plugin import.

### 3.4 fe-admin plugin `cms-ai-helper`

New plugin `vbwd-fe-admin/plugins/cms-ai-helper/` (named-export convention; registers into the §3.2 seams in `install()`):
- **`CmsAiMenuButton.vue`** → `cmsEditorHeaderActions`. An `AI ✨` button (`data-testid="cms-ai-menu"`) opening a dropdown of actions (`data-testid="cms-ai-action-article"`, `…-seo`, `…-restyle`). Selecting an action sets the panel's intent (and toggles "Read excerpt" on for *article*) and opens the panel, or fires generate directly.
- **`CmsAiPanel.vue`** → `cmsEditorPanels`. Collapsible (`<details>`/toggle, `data-testid="cms-ai-panel"`). Contains the prompt `<textarea>` (`rows="3"`, `resize:vertical`, `data-testid="cms-ai-prompt"`), the **Read excerpt** checkbox (`data-testid="cms-ai-read-excerpt"`), and a **Generate** button (`data-testid="cms-ai-generate"`). On generate: builds the request from `getContext({readExcerpt})` + prompt + action, `POST`s to the backend endpoint via the admin api client, then `applyPatch(response.patch)`. Shows loading + error inline; **never auto-saves** — the operator reviews and clicks Save.
- **Plugin baseline:** `config.json` + `admin-config.json` (at least `debug_mode`) per [[feedback_plugin_baseline_config_files]]. i18n `locales/*.json` for labels/placeholders/actions across the existing fe-admin locale set (`en,de,es,fr,ja,ru,th,zh`), wired via `sdk.addTranslations` like `cms-admin`.

### 3.5 P2 — file uploads (next increment, specified, not built in P1)

- Panel gains an upload control (images + documents). Files post (multipart or base64) to the same endpoint; the adapter attaches them as provider-native multimodal blocks (OpenAI `image_url` / Anthropic `image` base64; documents extracted server-side or passed as supported doc blocks). Validation: type/size caps from config.
- **"Style like this" flow:** an uploaded image/PDF + a prompt drives the **restyle** action — the model derives `source_css` (and optionally `content_html`) from the visual reference. Same JSON contract (§3.3), same `applyPatch` into the form's CSS tab.
- **P2 is a separate gate-green increment.**

### 3.6 Deliberately NOT built (NO OVERENGINEERING)

No token billing/accounting, no generation history/persistence, no streaming, no auto-save, no new DB tables/migrations, no agentic multi-step loops (that's the separate `cms-ai/` framework). The seam carries only `form` + `applyPatch` + `getContext` — no speculative props. P1 is text-only.

## 4. TDD plan (RED first)

**Backend (`vbwd-backend`, pytest):**
- `template_engine`: loads an action's YAML; resolves `{{variables}}` from the merged scope (admin config + editor context); `read_excerpt=false` omits the excerpt block; missing variable → empty, never raises; **VAR_DIR override wins** over the shipped template when present.
- `adapter`: OpenAI path builds the right payload (`response_format` json) + parses `choices[0].message.content`; Anthropic path (model `claude-*`) uses `x-api-key`/`anthropic-version` + parses tool-use; **JSON-repair/retry** re-prompts on invalid JSON up to `json_retry_max` then raises `CmsAiError`; transport/non-200 → `CmsAiError`. (`requests`/SDK mocked — no network.)
- `service`: picks the template per `action`; sets `requested_fields`/`json_schema` per §3.3; **validates** model output (drops unknown keys, rejects non-object `schema_json`, sanitises `source_css`, leaves `null` fields out of the patch). Engine + adapter mocked.
- `route`: `POST /generate` requires admin (403 without `cms.manage`); happy path returns `{patch,...}`; adapter error → 5xx with no key leakage.

**fe-admin (Vitest, mount with i18n + pinia):**
- `CmsAiPanel`: renders prompt textarea (3 rows) + read-excerpt checkbox + generate button by testid; generate posts the built request (api client mocked) and calls `applyPatch` with the response patch; null fields not applied; error renders inline; does **not** mutate fields the patch omits and does **not** save.
- `CmsAiMenuButton`: dropdown shows the actions; selecting *article* turns read-excerpt on + opens panel.
- **Seam spec** (in `cms-admin` or the plugin): a component registered in `cmsEditorHeaderActions`/`cmsEditorPanels` renders in the editor (assert DOM placement: header action in `.post-editor__actions`; panel between header and body). **Empty registry → editor unchanged.**

Mirror existing fe-admin/cms-admin test idioms; backend mirrors the `chat` plugin's test layout.

## 5. Files (indicative)

| Action | Path |
|---|---|
| new | `vbwd-backend/plugins/cms-ai-helper/__init__.py` — `CmsAiHelperPlugin` (+ `DEFAULT_CONFIG`) |
| new | `vbwd-backend/plugins/cms-ai-helper/cms_ai_helper/template_engine.py` — `PromptTemplateEngine` (loopai YAML format + VAR_DIR resolver) |
| new | `vbwd-backend/plugins/cms-ai-helper/cms_ai_helper/llm_adapter.py` — dual-protocol `CmsAiLlmAdapter` (+ ported JSON-repair/retry) |
| new | `vbwd-backend/plugins/cms-ai-helper/cms_ai_helper/services/cms_ai_helper_service.py` |
| new | `vbwd-backend/plugins/cms-ai-helper/cms_ai_helper/routes.py` — `POST /api/v1/plugins/cms-ai-helper/generate` |
| new | `vbwd-backend/plugins/cms-ai-helper/templates/{article,seo,restyle,freeform}.yaml` — default action templates |
| new | `vbwd-backend/plugins/cms-ai-helper/{config.json,admin-config.json}` (+ LLM settings, `json_retry_max`, `debug_mode`) |
| new | `vbwd-backend/plugins/cms-ai-helper/tests/{unit,integration}/...` (+ `conftest.py`) |
| edit | `vbwd-backend/plugins/plugins.json` + `plugins/config.json` — register & enable |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/index.ts` — registers into the editor seams |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/src/components/{CmsAiMenuButton,CmsAiPanel}.vue` |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/{config.json,admin-config.json}` (+ `debug_mode`) |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/locales/*.json` |
| new | `vbwd-fe-admin/plugins/cms-ai-helper/tests/unit/*.spec.ts` |
| edit | `vbwd-fe-admin/plugins/cms-admin/src/views/PostEditor.vue` — provide `CmsEditorContext`, render the two seams |
| new/edit | `cms-admin` editor extension registry (`cmsEditorHeaderActions` / `cmsEditorPanels`) |

## 6. Acceptance (P1)

- The editor (new or edit, page **or** post) shows an **`AI ✨` dropdown** in the header (Write-article / Re-generate-SEO) and a **collapsible AI panel** below the header with a 3-row stretchable prompt textarea, a **Read excerpt** checkbox, and a **Generate** button.
- *Write an article from excerpt* with **Read excerpt** on sends the excerpt + prompt to the backend, which calls the configured LLM (OpenAI **or** Anthropic) and returns JSON; `content_html` (and optionally title/excerpt) is filled, **SEO fields untouched**.
- *Re-generate all SEO fields* fills `meta_*`/`og_*`/`schema_json` from current title+content; body untouched.
- *Restyle the page* with a prompt fills/replaces `source_css` (the CSS tab); body and SEO untouched. (Reference image/PDF → CSS is the same action under P2.)
- A free-form prompt like *"…but do not fill SEO fields"* leaves those fields `null`/untouched.
- The API key is **never** present in the browser/network payload; it lives only in backend config.
- With `cms-ai-helper` (either repo) disabled, the editor renders exactly as before (seams empty).
- **`bin/pre-commit-check.sh --full` GREEN on both `vbwd-backend` and `vbwd-fe-admin`.**

## 7. Out of scope (this sprint)

- **P2 file uploads** (images/documents) — specified in §3.5, shipped as the next increment.
- Token billing, generation history, streaming, auto-save, agentic loops, fe-user surfaces.

## 8. Engineering-requirements check

- **Core agnostic:** both new plugins are self-contained; `cms-admin`/`PostEditor.vue` gain only AI-unaware seams (empty registry → no change); no `vbwd/` core edit. [[project_s01_core_agnosticism_oracle]]
- **SOLID/Liskov:** one `generate()` adapter surface, two protocol impls (substitutable); template engine is pure (no network/session); empty seam = null default; service validates against one schema.
- **DI/DRY:** layered route→service→engine→adapter via the plugin's DI/factory ([[project_plugin_di_provider_registration]]); OpenAI/Anthropic logic + JSON-repair live once (ported from loopai with attribution, **not** cross-plugin-imported, so both plugins stay independent); prompts live in YAML templates, not duplicated in code; the JSON field schema is one documented contract.
- **NO OVERENGINEERING:** loopai engine deliberately **not** embedded (its session/DB/filesystem coupling + missing `app_global_config`/`web.*` would threaten the gate) — only its YAML format + dual-protocol + JSON-repair are ported; no DB/migration, no billing/history/streaming; P1 text-only; seam carries only `form`+`applyPatch`+`getContext`.
- **Declarative, admin-tunable:** action prompts are YAML templates with config/context variables, overridable per instance in `${VBWD_VAR_DIR}/plugins/cms-ai-helper/templates/` — no code change to retune.
- **Plugin baseline:** `config.json` + `admin-config.json` (incl. `debug_mode`) ship in both plugins; LLM settings admin-editable, key as password. [[feedback_plugin_baseline_config_files]]
- **TDD-first / gate:** adapter/service/route + component/seam specs land RED first; `bin/pre-commit-check.sh --full` green on both repos = done. Implementation delegated to the **`vbwd-tdd`** agent. [[feedback_use_tdd_agent_for_implementation]]
- **Plugins in own dirs / migrations rule:** plugin code in `plugins/<name>/`; no migration needed (no new tables). [[feedback_plugins_always_in_own_repos]]
