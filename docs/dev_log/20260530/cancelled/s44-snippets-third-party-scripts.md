# Sprint 44 — `snippets`: admin-managed third-party script injection (be + fe-user duo)

> ⛔ **SUPERSEDED (2026-06-03) by [S47.7 — Snippets & head/body injection](../sprints/s47-7-snippets-and-head-injection.md)** (part of [S47 — Unified Content + SEO](../sprints/s47-unified-content-seo.md)). Snippets are now folded into the cms head pipeline: **baked into the prerendered head/body** (fire on first paint for anon/bots) with a **server CSP nonce**, via a shared head-injection seam — an upgrade over this SPA-only design. Kept for rationale only; build S47.7.

**Status:** PLANNED — 2026-05-30
**Area:** new module duo — backend `vbwd-plugin-snippets` + fe-user `vbwd-fe-user-plugin-snippets`. Each in its own repo ([[feedback_plugins_always_in_own_repos]]).
**Context:** integration-bridges marketing strategy (`docs/marketing/bizdev/03-integration-bridges-strategy.md`).

## Engineering requirements (BINDING)

**TDD-first** · **SOLID** · **Liskov** · **DI** · **DRY** · clean code · **NO OVERENGINEERING** (narrowest change that satisfies the requirement). **`bin/pre-commit-check.sh` is the quality guard** — `--plugin snippets --full` green = "done". Tables follow the [S43](../sprints/s43-db-table-naming-normalization.md) convention `<plugin_id>_<model>`. vbwd core stays agnostic — all logic lives in the plugin.

## Goal

Let a site admin paste **arbitrary third-party JavaScript/HTML snippets** through a widget and have them injected into the public site, with **zero code change** — Google Analytics, Facebook/Meta Pixel, Matomo counter, ad network tags, chat widgets, any vendor snippet. Each snippet has a **placement** (where in the page) and a **load strategy**, can be enabled/disabled, and ordered.

## Use cases (acceptance)
- GA4 / gtag, GTM container, Matomo tracker → `head` inline.
- Meta Pixel, TikTok pixel → `head` inline.
- Ad unit / `<script src>` vendor tag → `body_close` async.
- A visible embed (ad slot, widget) → placed as a **widget** in a content slot.

## Module duo

| Module | Repo | Responsibility |
|---|---|---|
| **backend `snippets`** | `vbwd-plugin-snippets` | persist snippets, admin CRUD API, public "active snippets" API |
| **fe-user `snippets`** | `vbwd-fe-user-plugin-snippets` | fetch active snippets + inject at the right placement; register the admin "Custom Scripts" widget for managing them |

> **Open decision (admin surface):** the management UI can live in (a) the **fe-user** plugin's admin/settings widget (keeps the duo as asked), or (b) a thin **fe-admin** plugin (matches the trio convention used by other plugins). **Recommend (b)** for consistency, but the duo is fully functional with (a). Decide before S44.2.

## Backend design (layered, SOLID)

**Model — `snippets/snippets/models/snippet.py`** (table **`snippets_snippet`**, S43-compliant), `class Snippet(BaseModel)`:
| field | type | notes |
|---|---|---|
| `name` | str | admin label ("GA4", "Meta Pixel") |
| `description` | str? | optional |
| `content` | text | the raw snippet (JS/HTML) |
| `placement` | enum `head\|body_open\|body_close\|widget` | where to inject |
| `load_strategy` | enum `inline\|async\|defer` | for `<script src>` tags |
| `position` | int | order within a placement |
| `enabled` | bool | off = never served |
| `consent_category` | enum `necessary\|analytics\|marketing` | hook for future consent gating |

- **Repository** `SnippetRepository(session)` — data access only.
- **Service** `SnippetService` (DI: repo) — CRUD + `list_active()` (enabled, ordered, grouped by placement). Business rules (validation, ordering) here, not in routes.
- **Routes** (`Blueprint`, `get_url_prefix()=""`):
  - admin (require_admin + `@require_permission("snippets.manage")`): `GET/POST /api/v1/admin/snippets`, `GET/PUT/DELETE /api/v1/admin/snippets/<id>`, `POST /api/v1/admin/snippets/<id>/toggle`.
  - public: `GET /api/v1/snippets/active` → enabled snippets grouped by placement (the only endpoint the SPA calls; **read-only, no auth needed to read public tags**, but returns only `enabled`).
- **Permission** `snippets.manage` (declared in `admin_permissions`).
- **Migration** `plugins/snippets/migrations/versions/<=32char>_create_snippets.py` (registered in `alembic.ini`; revision id ≤ 32 chars — report 21 gotcha).
- **`config.json` + `admin-config.json`** baseline (`tabs`/`component` schema; `debug_mode` + e.g. `max_snippet_bytes`) — copy the shape from an existing correct plugin, never invent ([[feedback_plugin_baseline_config_files.md]]).

## fe-user design

**`vbwd-fe-user-plugin-snippets`**:
- On boot (`activate`/router-ready), fetch `GET /api/v1/snippets/active`.
- **Injector** (single responsibility, DI-friendly — inject a `documentTarget` so it's unit-testable in jsdom): for each snippet create the element(s) and append to `document.head` / start-of-`body` / end-of-`body` per `placement`; `inline` → `<script>` with `textContent`; `async`/`defer` external → set the attribute. Idempotent (don't double-inject on SPA nav — track injected ids).
- **`widget` placement** → register a `SnippetWidget.vue` in the existing widget/extension registry so the admin can drop it in a content slot (visible embeds / ad units).
- **Admin "Custom Scripts" widget/view** (per the open decision): list + add/edit/delete/toggle, a `<textarea>` for `content`, placement + strategy selectors, live "enabled" toggle. Calls the admin API.

## Security (CRITICAL — this is deliberate code injection)

This feature **executes admin-supplied JavaScript by design** — it is *trusted code injection*, not a user-XSS hole. Guardrails:
1. **Write is admin-only** — every create/update/delete behind `require_admin` + `snippets.manage`. No public write path. The public `active` endpoint is **read-only**.
2. **Trust model documented:** only a trusted site admin can add snippets; treat `snippets.manage` like shell access to the site. State this in the plugin README.
3. **No server-side execution / no eval on the backend** — the backend only stores + returns text; execution happens in the visitor browser.
4. **CSP:** inline snippets break a strict `script-src` CSP. Decide: ship a per-injection **nonce** (preferred) or document the `unsafe-inline`/allowlist requirement. (Open decision — see below.)
5. **Output integrity:** the SPA injects `content` verbatim into a `<script>`/element — never through `v-html` into the DOM as markup it then re-parses (avoid double-execution surprises). `vue/no-v-html` stays clean.
6. **GDPR hook:** `consent_category` is stored now; actual consent-gating (don't inject `analytics`/`marketing` until consent) is a **future increment**, not this sprint (no-overengineering) — but the column makes it additive later.
7. **Size cap** (`max_snippet_bytes`) to avoid abuse / accidental huge payloads.

## TDD plan (tests FIRST)

- **Backend unit** (MagicMock repo): `SnippetService` CRUD + `list_active()` ordering/filtering; placement/strategy validation; size-cap rejection.
- **Backend integration** (`db` fixture): migration up/down/up; admin CRUD round-trip; `active` returns only enabled, grouped + ordered; permission enforcement (401/403).
- **fe-user unit** (vitest + jsdom): the injector appends the right element to the right target per placement; `async`/`defer` attrs set; idempotent (no double-inject); disabled snippets never injected; widget registers.
- **fe-user/admin**: CRUD view calls the API; toggle updates the list.

## Sub-sprints

- **S44.0 — backend `snippets`** (model+repo+service+routes+migration+config+permission). `--plugin snippets --full` green.
- **S44.1 — fe-user injection** (fetch + injector + `widget` placement). vitest + eslint green.
- **S44.2 — admin management UI** (per the open decision: fe-user widget view *or* fe-admin plugin).
- **S44.3 (deferred) — consent gating + CSP nonce** (additive; out of scope now).

## Open decisions
1. **Admin surface:** fe-user widget-config vs a `vbwd-fe-admin-plugin-snippets` (recommend fe-admin, consistency).
2. **CSP:** nonce-per-injection vs documented `unsafe-inline` requirement.
3. **plugin_id:** `snippets` (chosen) vs `code_injection` / `tracking` — `snippets` is generic + S43-clean (`snippets_snippet`).

## Definition of done
Admin can add/enable a GA4 + a Meta Pixel + an ad `<script src>` and they load on the public site at the correct placement with the correct strategy, with **no deploy/code change**; disabled snippets never load; all writes are permission-gated; `--plugin snippets --full` + fe-user vitest/eslint green; migration up/down/up validated; both repos pushed with green CI.
