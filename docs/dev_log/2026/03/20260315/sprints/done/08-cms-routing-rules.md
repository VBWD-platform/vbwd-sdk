# Sprint 08 — CMS Routing Rules

**Status:** ⏳ Pending approval
**Date:** 2026-03-14
**Principles:** TDD · SOLID · DRY · Liskov · Clean Code · DI · DevOps-first

---

## Goal

Implement a **CMS Routing Rules engine** that lets an admin configure URL routing behaviour
(default page, language-based redirects, IP/country redirects, path rewrites) through the
admin backoffice UI — with zero SSH access required and zero downtime on rule changes.

Rules are stored in PostgreSQL, evaluated at two layers:
- **Nginx** handles geo/IP/language rules (network level, zero Python overhead)
- **Backend Flask middleware** handles CMS-slug rules (instant, no nginx reload needed)

The admin configures *which detection methods to enable* (cookie priority, Accept-Language
header, `navigator.language`, GeoIP2, raw IP ranges) through the **fe-user CMS plugin
settings tab** — not hardcoded.

---

## Decisions Baked In

| Question | Decision |
|----------|----------|
| Rule management | Admin backoffice UI → DB → nginx conf generation |
| URL transparency | Configurable per-rule: redirect (URL changes) or rewrite (URL stays) |
| Language detection | Cookie > Accept-Language header > `navigator.language` — priority configurable in fe-user CMS settings |
| GeoIP | Both raw IP ranges and MaxMind GeoLite2 country codes — chosen per-rule, GeoIP method configurable in settings |
| Slug convention | One page = one language; `/de/home` stored as `slug="de/home"`; translation pages are independent |
| Rule evaluation | Hybrid — nginx for geo/IP/language, Flask middleware for CMS slug rules |
| A/B testing | Out of scope (will use GA raw-code injection later) |

---

## Architecture

```
Admin UI (fe-admin cms-routing tab)
  └─► POST /api/v1/admin/cms/routing-rules        (CRUD)
        └─► CmsRoutingRuleRepository.save()
              └─► CmsRoutingService.generate_nginx_conf()  → writes cms_routing.conf
                    └─► NginxReloadGateway.reload()         → nginx -s reload (graceful)

Incoming HTTP request
  └─► nginx (geo/IP/language map blocks in cms_routing.conf)
        └─► 301/302 if nginx rule matches
        └─► OR: proxy_pass → vbwd-fe-user
                  └─► CmsRoutingMiddleware.before_request()  (Flask)
                        └─► CmsRoutingService.evaluate(request_context)
                              └─► IRuleMatcher chain (priority order)
                                    └─► redirect() or continue
```

---

## Component Breakdown

### 1. Backend — `plugins/cms/`

#### 1.1 Model — `CmsRoutingRule`

```python
# plugins/cms/src/models/cms_routing_rule.py

class CmsRoutingRule(BaseModel):
    name            = db.Column(db.String(120), nullable=False)
    is_active       = db.Column(db.Boolean, default=True, nullable=False)
    priority        = db.Column(db.Integer, default=0, nullable=False)  # lower = first

    # Match condition
    match_type  = db.Column(db.String(32), nullable=False)
    # Values per type:
    #   "default"     → match_value = None  (always matches, lowest priority)
    #   "language"    → "de" | "fr" | "es"
    #   "ip_range"    → "203.0.113.0/24" | "10.0.0.0/8"
    #   "country"     → "DE" | "DE,AT,CH"  (comma-separated ISO 3166-1)
    #   "path_prefix" → "/old-pricing"
    #   "cookie"      → "vbwd_lang=de"
    match_value = db.Column(db.String(255), nullable=True)

    # Action
    target_slug     = db.Column(db.String(255), nullable=False)  # CMS slug or absolute URL
    redirect_code   = db.Column(db.Integer, default=302, nullable=False)  # 301 | 302
    is_rewrite      = db.Column(db.Boolean, default=False, nullable=False)
    # is_rewrite=True → transparent proxy (URL stays), False → redirect (URL changes)

    # Evaluation layer
    layer = db.Column(db.String(16), default="middleware", nullable=False)
    # "nginx"      → written into nginx conf, evaluated at network layer
    # "middleware" → evaluated by Flask before_request
```

**`to_dict()`** fields: all columns + `created_at.isoformat()`.

#### 1.2 Repository — `CmsRoutingRuleRepository`

Interface + SQLAlchemy implementation. Constructor-injected `db.session`.

```python
class ICmsRoutingRuleRepository(Protocol):
    def find_all_active(self) -> List[CmsRoutingRule]: ...
    def find_by_id(self, rule_id: str) -> Optional[CmsRoutingRule]: ...
    def save(self, rule: CmsRoutingRule) -> CmsRoutingRule: ...
    def delete(self, rule_id: str) -> None: ...
    def find_ordered(self) -> List[CmsRoutingRule]: ...
    # Returns all active rules ordered by priority ASC
```

#### 1.3 Matchers — `IRuleMatcher` + implementations

Liskov-safe: every matcher implements the same interface; `evaluate()` is the only public method.

```python
# plugins/cms/src/services/routing/matchers.py

class IRuleMatcher(Protocol):
    def matches(self, rule: CmsRoutingRule, ctx: RequestContext) -> bool: ...

@dataclass(frozen=True)
class RequestContext:
    path: str
    accept_language: str        # from HTTP header
    remote_addr: str
    geoip_country: Optional[str]  # None if GeoIP not configured
    cookie_lang: Optional[str]    # value of vbwd_lang cookie

class DefaultMatcher:
    def matches(self, rule, ctx) -> bool:
        return rule.match_type == "default"

class LanguageMatcher:
    def matches(self, rule, ctx) -> bool:
        if rule.match_type != "language":
            return False
        target_lang = rule.match_value.lower()
        # priority: cookie > Accept-Language header
        if ctx.cookie_lang and ctx.cookie_lang.lower() == target_lang:
            return True
        header_lang = ctx.accept_language[:2].lower() if ctx.accept_language else ""
        return header_lang == target_lang

class IpRangeMatcher:
    def matches(self, rule, ctx) -> bool:
        if rule.match_type != "ip_range":
            return False
        import ipaddress
        try:
            return ipaddress.ip_address(ctx.remote_addr) in \
                   ipaddress.ip_network(rule.match_value, strict=False)
        except ValueError:
            return False

class CountryMatcher:
    def matches(self, rule, ctx) -> bool:
        if rule.match_type != "country" or not ctx.geoip_country:
            return False
        countries = [c.strip().upper() for c in rule.match_value.split(",")]
        return ctx.geoip_country.upper() in countries

class PathPrefixMatcher:
    def matches(self, rule, ctx) -> bool:
        if rule.match_type != "path_prefix":
            return False
        return ctx.path.startswith(rule.match_value)

class CookieMatcher:
    def matches(self, rule, ctx) -> bool:
        if rule.match_type != "cookie":
            return False
        k, _, v = rule.match_value.partition("=")
        return ctx.cookie_lang == v.strip() if k.strip() == "vbwd_lang" else False
```

#### 1.4 Nginx Conf Generator — `NginxConfGenerator`

Single responsibility: turns a list of `CmsRoutingRule` objects into a valid nginx `.conf` snippet.
Validates with `nginx -t` before writing.

```python
# plugins/cms/src/services/routing/nginx_conf_generator.py

class NginxConfGenerator:
    """Generates /etc/nginx/conf.d/cms_routing.conf from active nginx-layer rules."""

    def generate(self, rules: List[CmsRoutingRule], default_slug: str) -> str:
        # Builds: geo $remote_addr $cms_ip_route { ... }
        #         map $http_accept_language $cms_lang_route { ... }
        #         map $cookie_vbwd_lang $cms_cookie_lang { ... }
        # Returns nginx config string
        ...

    def write_and_validate(self, conf_str: str, path: str) -> None:
        # 1. Write to a temp file
        # 2. Run: nginx -t -c <tempfile>  — raises NginxConfInvalidError on failure
        # 3. Write to target path
        ...
```

**`NginxConfInvalidError`** — raised when `nginx -t` exits non-zero, message includes nginx stderr.

#### 1.5 Nginx Reload Gateway — `INginxReloadGateway`

Interface + two implementations (real + stub for testing).

```python
class INginxReloadGateway(Protocol):
    def reload(self) -> None: ...

class SubprocessNginxReloadGateway:
    """Calls `nginx -s reload` via subprocess. Inject reload_command via config."""
    def __init__(self, reload_command: str = "nginx -s reload"): ...
    def reload(self) -> None:
        result = subprocess.run(self.reload_command.split(), capture_output=True)
        if result.returncode != 0:
            raise NginxReloadError(result.stderr.decode())

class StubNginxReloadGateway:
    """Test double. Records reload calls."""
    reload_count: int = 0
    def reload(self) -> None:
        self.reload_count += 1
```

#### 1.6 Service — `CmsRoutingService`

Orchestrates: rule CRUD, middleware evaluation, nginx conf generation.

```python
class CmsRoutingService:
    def __init__(
        self,
        rule_repo: ICmsRoutingRuleRepository,
        conf_generator: NginxConfGenerator,
        nginx_gateway: INginxReloadGateway,
        config: dict,           # cms plugin config dict
    ): ...

    # Admin CRUD
    def list_rules(self) -> List[dict]: ...
    def create_rule(self, data: dict) -> dict: ...
    def update_rule(self, rule_id: str, data: dict) -> dict: ...
    def delete_rule(self, rule_id: str) -> None: ...

    # Nginx sync — called after every create/update/delete
    def sync_nginx(self) -> None:
        rules = self.rule_repo.find_all_active_for_layer("nginx")
        conf = self.conf_generator.generate(rules, self.config["default_slug"])
        self.conf_generator.write_and_validate(conf, self.config["nginx_conf_path"])
        self.nginx_gateway.reload()

    # Middleware evaluation — called by Flask before_request
    def evaluate(self, ctx: RequestContext) -> Optional[RedirectInstruction]:
        rules = self.rule_repo.find_all_active_for_layer("middleware")
        # rules ordered by priority ASC
        for rule in rules:
            matcher = _matcher_for(rule.match_type)
            if matcher.matches(rule, ctx):
                return RedirectInstruction(
                    location=f"/{rule.target_slug}",
                    code=rule.redirect_code,
                    is_rewrite=rule.is_rewrite,
                )
        return None

@dataclass(frozen=True)
class RedirectInstruction:
    location: str
    code: int           # 301 | 302
    is_rewrite: bool    # True → X-Accel-Redirect (nginx internal), False → HTTP redirect
```

#### 1.7 Middleware — `CmsRoutingMiddleware`

Registered in CMS plugin's `on_enable()` as a Flask `before_request` hook.

```python
# plugins/cms/src/middleware/routing_middleware.py

class CmsRoutingMiddleware:
    def __init__(self, routing_service: CmsRoutingService): ...

    def before_request(self) -> Optional[Response]:
        # Skip admin, API, static paths
        if _is_passthrough(request.path):
            return None
        ctx = RequestContext(
            path=request.path,
            accept_language=request.headers.get("Accept-Language", ""),
            remote_addr=request.remote_addr,
            geoip_country=g.get("geoip_country"),   # set by GeoIP extension if enabled
            cookie_lang=request.cookies.get("vbwd_lang"),
        )
        instruction = self.routing_service.evaluate(ctx)
        if instruction is None:
            return None
        if instruction.is_rewrite:
            # Transparent: set X-Accel-Redirect and let nginx serve
            # (only works when nginx is the upstream — falls back to redirect in dev)
            return _rewrite_response(instruction.location)
        return redirect(instruction.location, code=instruction.code)

def _is_passthrough(path: str) -> bool:
    return path.startswith(("/api/", "/admin/", "/uploads/", "/_vbwd/"))
```

#### 1.8 GeoIP Extension (optional, enabled by config)

```python
# plugins/cms/src/extensions/geoip.py

class GeoIpExtension:
    """Reads MaxMind GeoLite2-Country.mmdb and sets g.geoip_country per request."""
    def __init__(self, mmdb_path: str): ...
    def init_app(self, app: Flask) -> None:
        app.before_request(self._set_country)
    def _set_country(self):
        import maxminddb
        with maxminddb.open_database(self._mmdb_path) as reader:
            result = reader.get(request.remote_addr)
            g.geoip_country = result["country"]["iso_code"] if result else None
```

Enabled only when `config["geoip"]["enabled"] is True` and `mmdb_path` exists.

#### 1.9 API Routes — `/api/v1/admin/cms/routing-rules`

```
GET    /api/v1/admin/cms/routing-rules           → list all rules (ordered by priority)
POST   /api/v1/admin/cms/routing-rules           → create rule
GET    /api/v1/admin/cms/routing-rules/<id>      → get single rule
PUT    /api/v1/admin/cms/routing-rules/<id>      → update rule (triggers sync_nginx if layer=nginx)
DELETE /api/v1/admin/cms/routing-rules/<id>      → delete rule (triggers sync_nginx if layer=nginx)
POST   /api/v1/admin/cms/routing-rules/reload    → force nginx reload (admin action button)
GET    /api/v1/cms/routing-rules                 → public: rules for layer=nginx (used by nginx watcher on boot)
```

All admin routes: `@require_admin`.
Input validation: `match_type` must be in allowed set; `redirect_code` must be 301 or 302;
`target_slug` must not be empty; `priority` must be a non-negative integer.

#### 1.10 Alembic Migration

`alembic/versions/20260314_create_cms_routing_rules.py`

```python
def upgrade():
    op.create_table(
        "cms_routing_rules",
        sa.Column("id", sa.UUID(), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("is_active", sa.Boolean(), default=True, nullable=False),
        sa.Column("priority", sa.Integer(), default=0, nullable=False),
        sa.Column("match_type", sa.String(32), nullable=False),
        sa.Column("match_value", sa.String(255), nullable=True),
        sa.Column("target_slug", sa.String(255), nullable=False),
        sa.Column("redirect_code", sa.Integer(), default=302, nullable=False),
        sa.Column("is_rewrite", sa.Boolean(), default=False, nullable=False),
        sa.Column("layer", sa.String(16), default="middleware", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("version", sa.Integer(), default=0, nullable=False),
    )
    op.create_index("ix_cms_routing_rules_priority", "cms_routing_rules", ["priority"])
    op.create_index("ix_cms_routing_rules_layer", "cms_routing_rules", ["layer"])
```

#### 1.11 Plugin Config additions

`plugins/cms/config.json`:
```json
{
  "routing": {
    "enabled": true,
    "default_slug": "home1",
    "default_redirect_code": 302,
    "nginx_conf_path": "/etc/nginx/conf.d/cms_routing.conf",
    "nginx_reload_command": "nginx -s reload",
    "nginx_enabled": true,
    "geoip": {
      "enabled": false,
      "mmdb_path": "/etc/nginx/GeoLite2-Country.mmdb"
    }
  }
}
```

---

### 2. DevOps

#### 2.1 `nginx.proxy.conf` → `nginx.proxy.conf.template`

Rename existing file. Replace with an envsubst-compatible template:

```nginx
# nginx.proxy.conf.template
# Generated routing rules are included from /etc/nginx/conf.d/cms_routing.conf
# That file is written by the backend on rule save.

server {
    listen 80 default_server;
    server_name _;

    # Include generated routing rules (geo blocks, map blocks, location rules)
    include /etc/nginx/conf.d/cms_routing.conf;

    location /admin {
        proxy_pass         http://vbwd_fe_admin:80;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass         http://vbwd_fe_user:80;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   Accept-Language   $http_accept_language;
        proxy_set_header   X-Cookie-Lang     $cookie_vbwd_lang;
    }
}
```

#### 2.2 `cms_routing.conf` initial (empty, valid nginx include)

```nginx
# cms_routing.conf — managed by vbwd-backend CmsRoutingService
# Do not edit manually. Changes will be overwritten on next rule save.
# Generated: never (no rules yet)
```

Committed to repo. The backend overwrites it on first rule save.

#### 2.3 Docker Compose — shared volume for nginx conf

`docker-compose.yaml`:
```yaml
services:
  api:
    volumes:
      - .:/app
      - nginx_conf:/etc/nginx/conf.d    # write generated conf here

  nginx:
    image: nginx:alpine
    volumes:
      - ./nginx.proxy.conf.template:/etc/nginx/templates/default.conf.template:ro
      - nginx_conf:/etc/nginx/conf.d    # read generated conf here
      - ./cms_routing.conf:/etc/nginx/conf.d/cms_routing.conf  # initial empty file
    environment:
      - DEFAULT_PAGE_SLUG=${DEFAULT_PAGE_SLUG:-home1}

volumes:
  nginx_conf:
  postgres_data:
```

`docker-compose.server.yaml` — same volume pattern + SSL cert mounts.

#### 2.4 `.env` additions

```
DEFAULT_PAGE_SLUG=home1
GEOIP_MMDB_PATH=/etc/nginx/GeoLite2-Country.mmdb
NGINX_CONF_DIR=/etc/nginx/conf.d
NGINX_RELOAD_COMMAND=nginx -s reload
```

#### 2.5 GitHub Actions — nginx config validation

`.github/workflows/nginx-validate.yml`:
```yaml
name: Validate nginx config template
on: [pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          docker run --rm \
            -v $PWD/nginx.proxy.conf.template:/etc/nginx/templates/default.conf.template:ro \
            -v $PWD/cms_routing.conf:/etc/nginx/conf.d/cms_routing.conf:ro \
            nginx:alpine nginx -t
```

---

### 3. fe-admin — `plugins/cms-routing/`

New admin plugin following the existing flat structure of fe-admin.

#### 3.1 API Client additions (`src/api/index.ts`)

```typescript
// Routing rules
getRoutingRules(): Promise<RoutingRule[]>
createRoutingRule(data: RoutingRulePayload): Promise<RoutingRule>
updateRoutingRule(id: string, data: RoutingRulePayload): Promise<RoutingRule>
deleteRoutingRule(id: string): Promise<void>
reloadNginx(): Promise<{ reloaded: boolean; message: string }>
```

#### 3.2 Store (`src/stores/routingRules.ts`)

Pinia store. State: `rules: RoutingRule[]`, `loading`, `error`, `lastReloadAt`.
Actions: `fetchRules`, `createRule`, `updateRule`, `deleteRule`, `reloadNginx`.

#### 3.3 Views

**`RoutingRules.vue`** — main list view:
- Table columns: Priority | Name | Match Type | Match Value | Target Slug | Redirect | Layer | Active | Actions
- Row actions: Edit, Delete, toggle Active
- Top bar: "Add Rule" button + "Apply & Reload Nginx" button (with spinner + success/error toast)
- Filter by layer (nginx / middleware / all)

**`RoutingRuleForm.vue`** — create/edit modal:

| Field | Input | Notes |
|-------|-------|-------|
| Name | text | required |
| Priority | number | 0 = highest |
| Match Type | select | default / language / ip_range / country / path_prefix / cookie |
| Match Value | text | hidden when match_type = "default" |
| Target Slug | text + slug preview link | required |
| Redirect Code | radio: 301 / 302 | |
| Transparent rewrite | checkbox | |
| Layer | radio: nginx / middleware | nginx rules trigger sync_nginx on save |
| Active | toggle | |

Match value field shows contextual placeholder per match_type:
- `language` → "de" (ISO 639-1 code)
- `ip_range` → "203.0.113.0/24"
- `country` → "DE,AT,CH" (comma-separated ISO 3166-1)
- `path_prefix` → "/old-pricing"
- `cookie` → "vbwd_lang=de"

#### 3.4 Router entry

```typescript
{ path: '/routing-rules', name: 'RoutingRules', component: () => import('./views/RoutingRules.vue') }
```

#### 3.5 Navigation

Add "Routing Rules" to the CMS section of the admin sidebar nav.

---

### 4. fe-user — CMS Plugin Settings Tab

#### 4.1 New settings section: "Routing" in the CMS plugin settings tab

Settings stored in plugin config (persisted to backend `plugins/config.json` via existing
plugin config API).

```typescript
interface CmsRoutingSettings {
  defaultPageSlug: string               // slug shown at /
  defaultRedirectCode: 301 | 302
  languageDetection: {
    enabled: boolean
    methods: Array<'cookie' | 'accept-language' | 'navigator'>
    priority: Array<'cookie' | 'accept-language' | 'navigator'>  // ordered list
  }
  geoip: {
    enabled: boolean
    method: 'ip_range' | 'country' | 'both' | 'none'
    mmdbPath: string                    // shown read-only, set via server env
  }
}
```

UI components in settings panel:
- **Default page slug** — text input with live CMS page autocomplete
- **Default redirect type** — radio: redirect (URL changes) / rewrite (URL stays)
- **Language detection** — checkboxes for each method; drag-handle to reorder priority
- **GeoIP method** — select: none / IP ranges / Country codes (GeoIP2) / Both
  - If "Country codes" selected: show info box "Requires MaxMind GeoLite2-Country.mmdb at `GEOIP_MMDB_PATH`"
- **Save Settings** → persists to plugin config, triggers sync_nginx for nginx-layer rules

#### 4.2 Language picker cookie (`useLocale.ts` composable)

```typescript
// vbwd-fe-user/src/composables/useLocale.ts
export function useLocale() {
  const currentLang = ref(getCookieLang() ?? getBrowserLang() ?? 'en')

  function setLang(lang: string) {
    document.cookie = `vbwd_lang=${lang}; path=/; max-age=31536000; SameSite=Lax`
    currentLang.value = lang
  }

  return { currentLang, setLang }
}

function getCookieLang(): string | null { ... }
function getBrowserLang(): string | null {
  return navigator.language?.slice(0, 2).toLowerCase() ?? null
}
```

Language switcher component reads `currentLang` and calls `setLang()`.
Vue Router `beforeEach` guard reads the cookie and redirects if language detection is enabled
and `navigator`-based detection is in the priority list.

---

## Test Plan (TDD)

### Backend unit tests — `plugins/cms/tests/unit/`

#### `test_routing_matchers.py`

| Test | Assertion |
|------|-----------|
| `DefaultMatcher` always matches any context | `True` |
| `LanguageMatcher` matches cookie lang "de" | `True` |
| `LanguageMatcher` matches Accept-Language "de-DE" | `True` |
| `LanguageMatcher` does not match "fr" when lang is "de" | `False` |
| `IpRangeMatcher` matches IP inside range | `True` |
| `IpRangeMatcher` does not match IP outside range | `False` |
| `IpRangeMatcher` handles invalid IP gracefully | `False` (no exception) |
| `CountryMatcher` matches single country "DE" | `True` |
| `CountryMatcher` matches comma-list "DE,AT,CH" | `True` |
| `CountryMatcher` returns `False` when geoip_country is None | `False` |
| `PathPrefixMatcher` matches `/old-pricing/details` against `/old-pricing` | `True` |
| `PathPrefixMatcher` does not match `/pricing` against `/old-pricing` | `False` |
| `CookieMatcher` matches `vbwd_lang=de` | `True` |

#### `test_routing_service.py`

| Test | Assertion |
|------|-----------|
| `evaluate()` returns `None` when no rules match | `None` |
| `evaluate()` returns highest-priority matching rule | correct `RedirectInstruction` |
| `evaluate()` skips inactive rules | next match returned |
| `evaluate()` returns `is_rewrite=True` when rule has `is_rewrite=True` | `True` |
| `sync_nginx()` calls `conf_generator.generate()` + `nginx_gateway.reload()` | both called |
| `sync_nginx()` does NOT call `reload()` when `generate()` raises `NginxConfInvalidError` | `reload()` not called |
| `create_rule()` calls `sync_nginx()` when `layer="nginx"` | called |
| `create_rule()` does NOT call `sync_nginx()` when `layer="middleware"` | not called |
| `delete_rule()` raises `CmsRoutingRuleNotFoundError` for unknown id | raised |

#### `test_nginx_conf_generator.py`

| Test | Assertion |
|------|-----------|
| IP range rules produce valid `geo` block | string contains `geo $remote_addr` |
| Language rules produce valid `map $http_accept_language` block | correct map |
| Empty rules produce valid empty conf (no syntax error) | passes `nginx -t` (mocked) |
| `write_and_validate()` raises `NginxConfInvalidError` on bad conf | raised |

#### `test_routing_middleware.py`

| Test | Assertion |
|------|-----------|
| `/api/v1/...` paths are skipped | returns `None` |
| `/admin/...` paths are skipped | returns `None` |
| Matching rule returns 302 redirect response | HTTP 302 |
| Matching rule with `is_rewrite=True` returns rewrite response | no Location redirect |
| Non-matching rule returns `None` | `None` |

### Backend integration tests — `plugins/cms/tests/integration/`

#### `test_cms_routing_api.py`

| Test | Status Code |
|------|-------------|
| `GET /api/v1/admin/cms/routing-rules` without auth | 401 |
| `GET /api/v1/admin/cms/routing-rules` as admin (empty) | 200, `[]` |
| `POST /api/v1/admin/cms/routing-rules` with valid payload | 201 |
| `POST` with invalid `match_type` | 422 |
| `POST` with invalid `redirect_code` (e.g. 200) | 422 |
| `PUT /api/v1/admin/cms/routing-rules/<id>` updates name | 200 |
| `DELETE /api/v1/admin/cms/routing-rules/<id>` | 204 |
| `DELETE` unknown id | 404 |
| `POST /api/v1/admin/cms/routing-rules/reload` | 200, `{"reloaded": true}` |
| `GET /api/v1/cms/routing-rules` (public) | 200, only `layer="nginx"` rules |

### fe-admin unit tests (`plugins/cms-routing/tests/`)

| Component | Test |
|-----------|------|
| `routingRules` store | `fetchRules` populates `rules` |
| `routingRules` store | `deleteRule` removes from `rules` array |
| `RoutingRuleForm.vue` | match_value hidden when match_type = "default" |
| `RoutingRuleForm.vue` | saves with correct payload |
| `RoutingRules.vue` | "Apply & Reload Nginx" button calls `reloadNginx()` |

### fe-user unit tests

| Composable | Test |
|-----------|------|
| `useLocale` | `setLang("de")` sets `vbwd_lang` cookie |
| `useLocale` | `getCookieLang()` reads existing cookie |
| `useLocale` | `getBrowserLang()` returns first 2 chars of `navigator.language` |

---

## Step-by-Step Implementation Order

| Step | What | Layer | TDD |
|------|------|-------|-----|
| 1 | `CmsRoutingRule` model + Alembic migration | backend | — |
| 2 | `ICmsRoutingRuleRepository` + SQLAlchemy impl | backend | unit |
| 3 | `RequestContext` + `IRuleMatcher` + 6 matcher classes | backend | unit |
| 4 | `RedirectInstruction` + `CmsRoutingService.evaluate()` | backend | unit |
| 5 | `NginxConfGenerator.generate()` | backend | unit |
| 6 | `INginxReloadGateway` + `SubprocessNginxReloadGateway` + `StubNginxReloadGateway` | backend | unit |
| 7 | `CmsRoutingService.sync_nginx()` + CRUD methods | backend | unit |
| 8 | `CmsRoutingMiddleware.before_request()` | backend | unit |
| 9 | API routes (CRUD + reload) + input validation | backend | integration |
| 10 | GeoIP extension (optional, behind config flag) | backend | unit |
| 11 | `nginx.proxy.conf` → `nginx.proxy.conf.template` | devops | CI validate |
| 12 | `cms_routing.conf` initial empty file | devops | — |
| 13 | `docker-compose.yaml` — shared `nginx_conf` volume | devops | — |
| 14 | `.env` additions + `docker-compose.server.yaml` | devops | — |
| 15 | GitHub Actions nginx validation workflow | devops | CI |
| 16 | fe-admin: API client additions + TypeScript types | fe-admin | — |
| 17 | fe-admin: `routingRules` Pinia store | fe-admin | unit |
| 18 | fe-admin: `RoutingRuleForm.vue` | fe-admin | unit |
| 19 | fe-admin: `RoutingRules.vue` + router entry + nav link | fe-admin | unit |
| 20 | fe-user: `useLocale.ts` composable | fe-user | unit |
| 21 | fe-user: CMS plugin settings "Routing" tab | fe-user | unit |
| 22 | Full integration smoke test: create rule → nginx reloads → redirect works | all | integration |

---

## Files Created / Modified

### New files
```
vbwd-backend/
  alembic/versions/20260314_create_cms_routing_rules.py
  plugins/cms/src/models/cms_routing_rule.py
  plugins/cms/src/repositories/routing_rule_repository.py
  plugins/cms/src/services/routing/matchers.py
  plugins/cms/src/services/routing/nginx_conf_generator.py
  plugins/cms/src/services/routing/nginx_reload_gateway.py
  plugins/cms/src/services/routing/routing_service.py
  plugins/cms/src/middleware/routing_middleware.py
  plugins/cms/src/extensions/geoip.py           (optional)
  plugins/cms/tests/unit/services/test_routing_matchers.py
  plugins/cms/tests/unit/services/test_routing_service.py
  plugins/cms/tests/unit/services/test_nginx_conf_generator.py
  plugins/cms/tests/unit/middleware/test_routing_middleware.py
  plugins/cms/tests/integration/test_cms_routing_api.py
  nginx.proxy.conf.template                     (replaces nginx.proxy.conf)
  cms_routing.conf                              (initial empty include)
  .github/workflows/nginx-validate.yml

vbwd-fe-admin/
  src/stores/routingRules.ts
  src/views/RoutingRules.vue
  src/views/RoutingRuleForm.vue
  tests/unit/stores/routingRules.spec.ts
  tests/unit/views/RoutingRules.spec.ts
  tests/unit/views/RoutingRuleForm.spec.ts

vbwd-fe-user/
  src/composables/useLocale.ts
  tests/unit/composables/useLocale.spec.ts
```

### Modified files
```
vbwd-backend/
  plugins/cms/src/routes.py                  (add routing-rules routes)
  plugins/cms/src/__init__.py                (register middleware + GeoIP extension)
  plugins/cms/config.json                    (add routing config block)
  docker-compose.yaml                        (nginx_conf volume, nginx service)
  docker-compose.server.yaml                 (same volume pattern)
  .env.example                               (new env vars)

vbwd-fe-admin/
  src/api/index.ts                           (routing rule methods)
  src/router/index.ts                        (RoutingRules route)
  src/components/AppNav.vue                  (Routing Rules nav link)

vbwd-fe-user/
  plugins/cms/src/views/CmsPluginSettings.vue  (add Routing tab)
```

---

## Pre-commit Checklist

- [ ] `make test-unit` → all new unit tests pass
- [ ] `make test-integration` → all routing API integration tests pass
- [ ] `make lint` → Black ✓ Flake8 ✓ Mypy ✓
- [ ] fe-admin: `npm run test` → all Vitest tests pass
- [ ] fe-admin: `npm run lint` → ESLint ✓ TypeScript ✓
- [ ] fe-user: `npm run test` → all Vitest tests pass
- [ ] GitHub Actions: nginx config validation workflow passes
- [ ] Manual smoke test: create middleware rule → visit `/` → redirect fires
- [ ] Manual smoke test: create nginx rule → "Apply & Reload" → nginx reload logged

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before or alongside implementation. No step is done without passing tests. |
| **SOLID** | Single responsibility per component/service. Open for extension, closed for modification. |
| **DI** | Backend: services receive repositories via constructor, no `db.session` inside service methods. Frontend: composables and stores inject dependencies. |
| **DRY** | Reuse existing middleware and route resolver patterns. No duplicate routing logic. |
| **Liskov** | All routing rule implementations honour the `IRoutingRule` contract. |
| **Clean code** | No `console.log`, no `as any`, no bare `except: pass`. Explicit types everywhere. |
| **No over-engineering** | Minimum complexity for the current task. No speculative abstractions. |
| **Drop deprecated** | Use current Flask, SQLAlchemy 2.0, and Vue 3 APIs only. |

---

## Pre-commit Checks

Run after every step before marking it done.

### vbwd-backend (`vbwd-backend/`)
```bash
# Lint only (Black + Flake8 + Mypy)
./bin/pre-commit-check.sh --lint

# Lint + unit tests
./bin/pre-commit-check.sh --unit

# Lint + integration tests (requires running PostgreSQL)
./bin/pre-commit-check.sh --integration

# Full (lint + unit + integration)
./bin/pre-commit-check.sh --full
```

### fe-user (`vbwd-fe-user/`)
```bash
./bin/pre-commit-check.sh --style
./bin/pre-commit-check.sh --unit
./bin/pre-commit-check.sh --all
```

### fe-admin (`vbwd-fe-admin/`)
```bash
./bin/pre-commit-check.sh --style
./bin/pre-commit-check.sh --unit    # runs vue/tests/unit/ plugins/
./bin/pre-commit-check.sh --all
```

All checks must pass before the sprint is considered complete.
