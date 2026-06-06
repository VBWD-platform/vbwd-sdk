# S47.7 — Site-level snippets & third-party script injection (head/body) — folds in S44

**Parent:** [S47 — Unified Content + SEO](s47-unified-content-seo.md) · **Depends on:** [S47.1](s47-1-seo-pipeline-and-prerender.md) (prerender head), [S47.2](s47-2-serving-cache-bypass-and-handoff.md) (serving), [S47.3](s47-3-public-rendering-and-content-types.md) (widget registry), [S47.6](s47-6-admin-authoring.md) (admin) · **Status:** DRAFT — 2026-06-03 · **Supersedes** [S44 — snippets](../cancelled/s44-snippets-third-party-scripts.md).
**Repos:** `vbwd-plugin-cms` (model + admin + the injection seam), `vbwd-fe-user-plugin-cms` (injector + widget), `vbwd-fe-admin-plugin-cms` (manager UI).
**Engineering requirements (BINDING):** TDD-first · SOLID · DI · DRY · Liskov · clean code · **core agnostic** · **NO OVERENGINEERING** · **plugin baseline config files** — [`_engineering_requirements.md`](_engineering_requirements.md). Gate: `bin/pre-commit-check.sh --plugin cms --full` GREEN; fe-user + fe-admin `npm run lint && npm run test` GREEN.

---

## 1. Goal & why it belongs in S47

Let a site admin paste **arbitrary third-party JS/HTML** (GA4 / GTM / Matomo / Meta Pixel / TikTok / ad tags / chat widgets) through a widget and have it injected at the right **placement** with the right **load strategy** — zero code change. **Folded into S47 because snippets *are* head/body injections, and S47 owns the head pipeline + the prerender + serving.** Concretely, this fold is an upgrade over the old SPA-only S44:

- **Baked into the prerendered head/body (47.1/47.2)** → analytics/pixels fire on **first paint** for anon + bots (served the static file), not only after the SPA boots.
- **CSP becomes clean:** the server emits a **per-render nonce** on inline snippets + a matching `Content-Security-Policy` header → strict `script-src` with **no `unsafe-inline`** (impossible with client-injected inline scripts).
- **DRY:** snippets and SEO meta share **one** head-assembly path.

## 2. The head/body injection seam (the reusable spine)

`plugins/cms/src/services/head_injection_registry.py` — `register_head_injection(provider)`; each provider yields `Injection(placement ∈ {head, body_open, body_close, widget}, content, load_strategy ∈ {inline, async, defer}, position, consent_category)`. The **prerender writer (47.1)** assembles `<head>` / start-of-`body` / end-of-`body` from the **meta-builder + every registered provider**; the **SPA (47.2)** applies the same set idempotently. **Snippets is the built-in provider**; other plugins (a consent manager, per-plugin tags) can register more — cms/core untouched (SOLID/OCP, mirrors the sitemap-provider pattern).

## 3. Backend — `plugins/cms/src/` (snippets model)

- **Model `cms_snippet`** (`BaseModel`, table **`cms_snippet`** — S43-compliant): `name`, `description?`, `content` (Text), `placement` (enum `head|body_open|body_close|widget`), `load_strategy` (enum `inline|async|defer`), `position` (int), `enabled` (bool), `consent_category` (enum `necessary|analytics|marketing`). `to_dict()` explicit.
- **`SnippetRepository`** (data access) + **`SnippetService`** (DI: repo) — CRUD + `list_active()` (enabled, ordered, grouped by placement); validation + size cap here, not in routes.
- **Routes** (blueprint):
  - **admin** (`require_admin` + `@require_permission("cms.snippets.manage")`): `GET/POST /api/v1/admin/cms/snippets`, `GET/PUT/DELETE /api/v1/admin/cms/snippets/<id>`, `POST …/<id>/toggle`.
  - **public** (read-only, no auth): `GET /api/v1/cms/snippets/active` → enabled snippets grouped by placement.
- **Permission** `cms.snippets.manage` (declared in `admin_permissions`). **Migration** in `plugins/cms/migrations/versions/` (rev id ≤ 32 chars). Config baseline adds `max_snippet_bytes`.
- Snippets registers itself as the built-in **head-injection provider** in `on_enable`.

## 4. Prerender + serving integration (47.1 / 47.2)

- **Bake at prerender time:** `head`/`body_open`/`body_close` snippets are emitted into **every** prerendered file (via the §2 seam). Inline snippets carry a **per-render `nonce`**; the served response sets a matching `Content-Security-Policy`.
- **Site-wide invalidation:** a snippet **create/update/delete/toggle fires a prerender refresh** (snippets affect every page) — **reuses the 47.2 refresh/re-stamp hook** (the same machinery as the asset re-stamp; snippets change rarely, so the cost is bounded). Documented in `plugins/cms/docs/seo/nginx-prerender.md`.
- **SPA application (logged-in / CSR nav):** the fe-user injector fetches `GET /cms/snippets/active` and applies the same set **idempotently** (track injected ids; no double-inject on SPA nav). Inline → `<script>` `textContent`; `async`/`defer` external → set the attribute; **never via `v-html`**. This covers logged-in users (who bypass the prerender) + client-side navigation.

## 5. fe-user widget + fe-admin manager

- **`widget` placement** → a `SnippetWidget.vue` registered in the 47.3 `vueComponentRegistry`, so an admin can drop a visible embed / ad slot into a content area.
- **fe-admin (47.6):** a **"Custom Scripts / Snippets"** manager — list + add/edit/delete/toggle, a `<textarea>` for `content`, placement / strategy / consent selectors, enabled toggle.

## 6. Security (deliberate, trusted code injection — folded from S44, improved)

1. **Write is admin-only** (`require_admin` + `cms.snippets.manage`); the public `active` endpoint is **read-only**.
2. **Trust model documented** — `cms.snippets.manage` ≈ shell access to the site (README).
3. **No server-side execution / no eval** — backend stores + returns text; execution is in the visitor browser.
4. **CSP: nonce-based** (the S47 fold's win) — per-render nonce + header; strict `script-src`, no `unsafe-inline`.
5. **Output integrity** — injected verbatim into a `<script>`/element, **never** `v-html` (`vue/no-v-html` stays clean).
6. **GDPR hook** — `consent_category` stored; actual consent-gating (don't inject `analytics`/`marketing` until consent) is a **deferred** additive increment.
7. **Size cap** (`max_snippet_bytes`).

## 7. TDD (RED first)
- **Backend unit:** `SnippetService` CRUD + `list_active()` ordering/grouping; placement/strategy validation; size-cap rejection.
- **Backend integration:** migration up/down/up; admin CRUD round-trip; `active` returns only enabled, grouped + ordered; permission 401/403; **the head-injection provider yields the right `Injection`s**.
- **Prerender (47.1):** enabled `head`/`body_*` snippets are **baked into the prerendered file at the right placement with a nonce**; a snippet **toggle triggers a prerender refresh**; disabled snippets are **never** emitted; the CSP header matches the emitted nonces.
- **fe-user unit (jsdom):** injector appends the right element to the right target per placement; `async`/`defer` attrs set; **idempotent** (no double-inject on nav); disabled never injected; widget registers.
- **fe-admin:** manager CRUD calls the API; toggle updates the list.

## 8. Acceptance
- An admin adds a **GA4** + a **Meta Pixel** + an ad `<script src>` → they load on the public site at the correct placement/strategy, **present in the prerendered HTML** (anon first paint) **and** applied by the SPA for logged-in users — with **no deploy/code change**.
- Disabled snippets never load; a snippet change **refreshes the prerender**; the served CSP is **nonce-based** (no `unsafe-inline`); all writes are permission-gated.
- `--plugin cms --full` + fe-user/fe-admin lint+test GREEN; migration up/down/up validated.

## 9. Out of scope
Consent-gating **enforcement** (`consent_category` column only), GTM server-side container, per-snippet A/B, non-admin authoring.

## 10. Engineering-requirements check
- **Core agnostic / OCP:** the head-injection seam is cms-level; other plugins register providers; core untouched.
- **DRY:** one head-assembly path serves SEO meta **and** snippets; the prerender-refresh reuses the 47.2 hook.
- **SOLID/Liskov:** injection providers substitutable; an unknown placement is skipped, never crashes.
- **NO OVERENGINEERING:** reuse the prerender + widget registry + admin shell; consent enforcement + GTM-server deferred.
