# Sprint 08 — CMS Routing Rules — Completion Report
**Date:** 2026-03-15
**Sprint:** 08 — CMS Routing Rules
**Tests Added:** 49

## Summary

Full CMS routing rules engine implemented across backend, fe-admin, and fe-user. Admins can configure URL redirects and rewrites through the backoffice with zero SSH access. Rules are evaluated at two layers: nginx (geo/IP/language at network level) and Flask middleware (CMS-slug rules, no nginx reload). `useLocale` composable added to fe-user for cookie-based language detection.

---

## Changes Delivered

### Backend — `vbwd-backend/plugins/cms/`

**Model — `src/models/cms_routing_rule.py`** (new):
- `CmsRoutingRule` extends `BaseModel` (UUID PK, timestamps, version)
- Fields: `name`, `is_active`, `priority`, `match_type`, `match_value`, `target_slug`, `redirect_code`, `is_rewrite`, `layer`
- `layer`: `"nginx"` (network-level) or `"middleware"` (Flask before_request)

**Repository — `src/repositories/routing_rule_repository.py`** (new):
- `ICmsRoutingRuleRepository` Protocol + SQLAlchemy implementation
- `find_all_active()`, `find_by_id()`, `find_ordered()`, `save()`, `delete()`

**Matchers — `src/services/routing/matchers.py`** (new):
- `RequestContext` frozen dataclass: `path`, `accept_language`, `remote_addr`, `geoip_country`, `cookie_lang`
- `RedirectInstruction` frozen dataclass: `location`, `code`, `is_rewrite`
- 6 matcher classes all implementing `matches(rule, ctx) -> bool`:
  - `DefaultMatcher` — always true
  - `LanguageMatcher` — cookie lang > Accept-Language header
  - `IpRangeMatcher` — `ipaddress.ip_network` CIDR check, graceful on invalid IP
  - `CountryMatcher` — comma-separated ISO 3166-1, requires `geoip_country`
  - `PathPrefixMatcher` — `ctx.path.startswith(rule.match_value)`
  - `CookieMatcher` — `vbwd_lang=<value>` cookie match
- `matcher_for(match_type)` dict-based registry

**Nginx Conf Generator — `src/services/routing/nginx_conf_generator.py`** (new):
- `generate(rules, default_slug) -> str` — builds `geo` + `map` blocks
- `write_and_validate(conf_str, path)` — writes to temp, runs `nginx -t` (skipped gracefully if nginx not found), writes to target
- `NginxConfInvalidError` raised on non-zero `nginx -t` exit

**Nginx Reload Gateway — `src/services/routing/nginx_reload_gateway.py`** (new):
- `INginxReloadGateway` Protocol
- `SubprocessNginxReloadGateway` — runs `nginx -s reload` via subprocess
- `StubNginxReloadGateway` — test double, records `reload_count`; used when `TESTING=true`

**Service — `src/services/routing/routing_service.py`** (new):
- Constructor-injected: `rule_repo`, `conf_generator`, `nginx_gateway`, `config`
- `list_rules()`, `create_rule(data)`, `update_rule(rule_id, data)`, `delete_rule(rule_id)`
- `sync_nginx()` — generate → write_and_validate → reload; if validate raises, reload is NOT called
- `evaluate(ctx)` — iterates rules ordered by priority, returns first matching `RedirectInstruction`
- `create_rule()` / `update_rule()` / `delete_rule()` call `sync_nginx()` only when `layer="nginx"`

**Middleware — `src/middleware/routing_middleware.py`** (new):
- `CmsRoutingMiddleware.before_request()` Flask hook
- Passthrough prefixes: `/api/`, `/admin/`, `/uploads/`, `/_vbwd/`
- Rewrite path: returns response with `X-Accel-Redirect` header
- Redirect path: returns `Flask.redirect()` with rule's redirect code

**Alembic migration — `alembic/versions/20260315_create_cms_routing_rules.py`** (new):
- Creates `cms_routing_rules` table
- Indexes on `priority` and `layer` columns

**API Routes — 7 endpoints added to `src/routes.py`:**

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/v1/admin/cms/routing-rules` | admin | List all rules (ordered by priority) |
| `POST` | `/api/v1/admin/cms/routing-rules` | admin | Create rule |
| `GET` | `/api/v1/admin/cms/routing-rules/<id>` | admin | Get single rule |
| `PUT` | `/api/v1/admin/cms/routing-rules/<id>` | admin | Update rule |
| `DELETE` | `/api/v1/admin/cms/routing-rules/<id>` | admin | Delete rule |
| `POST` | `/api/v1/admin/cms/routing-rules/reload` | admin | Force nginx reload |
| `GET` | `/api/v1/cms/routing-rules` | public | Rules for `layer=nginx` |

Input validation: `match_type` in allowed set; `redirect_code` must be 301 or 302; `priority` ≥ 0; `target_slug` non-empty.

### fe-admin — `vbwd-fe-admin/vue/src/`

**`stores/routingRules.ts`** (new):
- `RoutingRule` interface with all model fields
- Pinia store: `rules`, `loading`, `error`, `lastReloadAt`
- Actions: `fetchRules`, `createRule`, `updateRule`, `deleteRule`, `reloadNginx`

**`views/RoutingRules.vue`** (new):
- Table: Priority, Name, Match, Value, Target, Code, Layer, Active, Actions
- Layer filter `<select>` (all / nginx / middleware)
- "Apply & Reload Nginx" button with spinner and toast feedback
- Modal: opens `RoutingRuleForm` for create/edit

**`views/RoutingRuleForm.vue`** (new):
- `match_value` field hidden via `v-if` when `match_type === 'default'`
- Contextual placeholders per match type: `language` → `"de"`, `ip_range` → `"203.0.113.0/24"`, `country` → `"DE,AT,CH"`, `path_prefix` → `"/old-pricing"`, `cookie` → `"vbwd_lang=de"`
- Emits `saved` with form data; emits `cancel`
- Edit mode pre-fills all fields from `rule` prop; shows "Update" button label

**Router + nav**: route `/admin/cms/routing-rules` added; sidebar nav link under CMS section.

### fe-user — `vbwd-fe-user/vue/src/`

**`composables/useLocale.ts`** (new):
- `getCookieLang()` — reads `vbwd_lang` cookie
- `getBrowserLang()` — `navigator.language.slice(0, 2).toLowerCase()`
- `useLocale()` — `currentLang` ref (initialised from cookie → browser → `'en'`); `setLang(lang)` writes cookie with 1-year max-age, SameSite=Lax

---

## Tests

### Backend unit tests (35 tests across 4 files):
- `test_routing_matchers.py` — all 6 matchers, edge cases (invalid IP, null geoip, comma-list countries)
- `test_routing_service.py` — evaluate priority order, skip inactive rules, sync_nginx gate on NginxConfInvalidError, create/delete CRUD
- `test_nginx_conf_generator.py` — geo block output, map block output, empty rules, NginxConfInvalidError on bad conf
- `test_routing_middleware.py` — passthrough paths, 302 redirect response, rewrite response (X-Accel-Redirect), None on no match

### fe-admin unit tests (8 tests across 2 files):
- `routingRules.spec.ts` — fetchRules, createRule, deleteRule, updateRule, reloadNginx (5 tests)
- `RoutingRuleForm.spec.ts` — match_value hidden for "default", visible for "language"/"ip_range", submit emits saved, edit mode shows "Update" + pre-fills name (6 tests)

### fe-user unit tests (6 tests):
- `useLocale.spec.ts` — getCookieLang null when no cookie, reads existing cookie, getBrowserLang 2-char regex, setLang updates ref, setLang writes cookie, initialises from cookie

---

## Bugs Fixed

- **RoutingRuleForm submit test (emitted was falsy)**: Used `trigger('click')` on submit button — jsdom form validation blocked the submit handler. Fixed by using `w.find('form').trigger('submit')` instead.
- **Vitest mock hoisting `ReferenceError`**: `const mockFn = vi.fn()` declared before `vi.mock()` factory was hoisted. Fixed with `vi.fn()` inline in factory + `vi.mocked()` after import.

---

## Pre-commit

- `make pre-commit-quick` ✅ (backend lint + unit)
- `make test-integration` ✅ (routing API integration tests)
- `npm run test` fe-admin ✅
- `npm run test` fe-user ✅
- `npm run lint` fe-admin ✅
- `npm run lint` fe-user ✅

---

## Known Gaps (Backlog)

- GeoIP extension (`src/extensions/geoip.py`) is implemented but not wired into the CMS plugin's `on_enable()` (behind config flag — requires MaxMind mmdb file)
- fe-user CMS plugin "Routing" settings tab (language detection priority UI) is not yet built — `useLocale` composable is ready but not connected to a settings screen
- `nginx.proxy.conf.template` and shared `nginx_conf` Docker volume not yet applied to `docker-compose.server.yaml` — nginx integration is functional locally but production deploy still uses static conf
- No E2E test for the full redirect flow end-to-end
