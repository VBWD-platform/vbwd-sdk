# VBWD Host & Routing Configuration

**Date:** 2026-03-14
**Status:** Reference document — routing rules feature NOT yet implemented
**Scope:** Nginx, Docker, CMS default page, language/IP-based routing

---

## Overview

This document covers:

1. How to set a **default page** (e.g. `/home2` shown at `/`)
2. **Language-based routing** (Accept-Language or browser JS)
3. **IP/geo-based routing** (IP range or country code)
4. Where each approach lives in the VBWD stack
5. What is already implemented vs what requires a sprint

---

## Layer Map

```
Browser
  └─► Nginx proxy (nginx.proxy.conf)          ← Layer 1: network-level rules
        └─► vbwd-fe-user (Vue SPA)             ← Layer 2: client-side routing
              └─► /api/v1/cms/routing-rules    ← Layer 3: DB-stored rules (NOT YET BUILT)
                    └─► Flask backend
```

**Rule of thumb:**

| Requirement | Best layer |
|---|---|
| Redirect `/` to a fixed slug permanently | Nginx |
| Language detection via `Accept-Language` header | Nginx `map` |
| IP range routing | Nginx `geo` module |
| Country-based routing (GeoIP2) | Nginx `ngx_http_geoip2_module` |
| Admin-configurable rules via UI | DB-stored rules + backend middleware |
| Client-side language from browser `navigator.language` | Vue Router guard |

---

## 1. Default Page — Setting `/` to Show a CMS Page

### 1a. Nginx redirect (simplest, zero backend changes)

The page lives at `/home2` in the Vue SPA. At `/` we redirect to it.

**`nginx.proxy.conf`:**

```nginx
server {
    listen 80 default_server;
    server_name _;

    # Default page: redirect / to /home2
    location = / {
        return 302 /home2;
        # Use 301 if permanent, 302 if you may change it later
    }

    location /admin {
        proxy_pass http://vbwd_fe_admin:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        proxy_pass http://vbwd_fe_user:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Result:** `http://localhost` → 302 → `http://localhost/home2`

### 1b. Nginx internal rewrite (transparent — URL stays as `/`)

If the admin wants the content of `/home2` to appear at `/` without changing the URL in the browser:

```nginx
location = / {
    rewrite ^ /home2 last;
}
```

> **Caution:** The SPA router will see `/` in the URL bar but load the `/home2` page component.
> This works if the Vue CMS plugin renders based on the API response, not the URL path.
> It does NOT work well with Vue Router's `/:slug` catch-all because the router will try to resolve slug="" or "/".
> **Recommendation: use a redirect (1a), not a rewrite (1b).**

### 1c. Nginx environment variable (configurable without rebuilding image)

Add to `docker-compose.yaml` / `docker-compose.server.yaml`:

```yaml
services:
  nginx:
    image: nginx:alpine
    environment:
      - DEFAULT_PAGE_SLUG=home2
    volumes:
      - ./nginx.proxy.conf.template:/etc/nginx/templates/default.conf.template
```

`nginx.proxy.conf.template`:

```nginx
server {
    listen 80 default_server;
    server_name _;

    location = / {
        return 302 /${DEFAULT_PAGE_SLUG};
    }

    location / {
        proxy_pass http://vbwd_fe_user:80;
        proxy_set_header Host $host;
    }
}
```

The official `nginx:alpine` image runs `envsubst` on `/etc/nginx/templates/*.template` on startup,
populating `${DEFAULT_PAGE_SLUG}` automatically. No image rebuild needed — just change the env var and restart.

---

## 2. Language-Based Routing

### 2a. Nginx `map` on `Accept-Language` header

Simplest server-side approach. No GeoIP database needed.

```nginx
# Map Accept-Language header prefix → locale slug prefix
map $http_accept_language $lang_prefix {
    default         "";         # no redirect for English (default)
    "~^de"          "/de";      # German
    "~^fr"          "/fr";      # French
    "~^es"          "/es";      # Spanish
}

server {
    listen 80 default_server;
    server_name _;

    # Language redirect: / → /de, /fr, etc.
    location = / {
        if ($lang_prefix != "") {
            return 302 ${lang_prefix}/home;
        }
        return 302 /home;
    }

    # Language prefix redirect: /de/* → /home-de (example CMS slug convention)
    # This only fires if the path is bare /de with no trailing content
    location ~ ^/(de|fr|es)$ {
        return 302 $uri/home;
    }

    location /admin {
        proxy_pass http://vbwd_fe_admin:80;
        proxy_set_header Host $host;
    }

    location / {
        proxy_pass http://vbwd_fe_user:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Accept-Language $http_accept_language;
    }
}
```

**CMS slug convention with this approach:**
- English: `/home`, `/features`, `/pricing`
- German: `/de/home`, `/de/features`, `/de/pricing`
- French: `/fr/home`, `/fr/features`

The CMS page `slug` field stores e.g. `de/home` — the Vue SPA's `/:slug(.+)` catch-all handles `/de/home` transparently.

### 2b. Vue Router client-side guard (zero nginx changes)

Add to `vbwd-fe-user/plugins/cms/index.ts`:

```typescript
router.beforeEach((to, _from, next) => {
  const lang = navigator.language?.slice(0, 2).toLowerCase() ?? 'en';
  const langMap: Record<string, string> = { de: 'de', fr: 'fr', es: 'es' };
  const prefix = langMap[lang];

  // Only redirect bare / to the locale home
  if (to.path === '/' && prefix) {
    return next(`/${prefix}/home`);
  }
  next();
});
```

**Pros:** No infrastructure changes. Works in Docker, locally, on any host.
**Cons:** Runs after the page loads in the browser (brief flash at `/` before redirect).
**Recommendation:** Use this for soft language preference. Use nginx map (2a) for hard redirects at the server level.

### 2c. Cookie-based language preference (best UX)

On first visit, use nginx `map` to detect language. Set a cookie. On subsequent visits, read the cookie:

```nginx
map $cookie_vbwd_lang $preferred_lang_prefix {
    default  "";
    "de"     "/de";
    "fr"     "/fr";
}

# Fallback: if no cookie, use Accept-Language
map $http_accept_language $accept_lang_prefix {
    default  "";
    "~^de"   "/de";
    "~^fr"   "/fr";
}

# Merge: cookie wins over Accept-Language
map $preferred_lang_prefix $lang_redirect {
    default  $accept_lang_prefix;
    "~^/"    $preferred_lang_prefix;
}
```

The Vue app sets `document.cookie = 'vbwd_lang=de; path=/; max-age=31536000'` when the user picks a language.

---

## 3. IP-Based Routing

### 3a. Nginx `geo` module (IP range → variable)

Built into nginx. No external module required.

```nginx
# Map IP ranges to routing variables
geo $remote_addr $ip_locale {
    default         "";
    10.0.0.0/8      "internal";
    192.168.1.0/24  "office";
    203.0.113.0/24  "partner-de";    # a specific partner's IP block → German
}

map $ip_locale $ip_prefix {
    default     "";
    "partner-de" "/de";
    "internal"  "/internal";         # internal preview pages
}

server {
    listen 80 default_server;
    server_name _;

    location = / {
        if ($ip_prefix != "") {
            return 302 ${ip_prefix}/home;
        }
        return 302 /home;
    }

    location / {
        proxy_pass http://vbwd_fe_user:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**Pattern: `if IP is X1.X2.X3.* then forward /* to /fr/*`:**

```nginx
geo $remote_addr $force_fr {
    default         0;
    203.0.113.0/24  1;    # X1.X2.X3.*
}

server {
    location / {
        if ($force_fr = 1) {
            # rewrite /anything to /fr/anything
            rewrite ^/(.*)$ /fr/$1 redirect;
        }
        proxy_pass http://vbwd_fe_user:80;
        proxy_set_header Host $host;
    }
}
```

### 3b. Nginx GeoIP2 (country code → locale)

Requires `ngx_http_geoip2_module` and a MaxMind GeoLite2-Country database.

```dockerfile
# Dockerfile.nginx
FROM nginx:alpine
RUN apk add --no-cache nginx-mod-http-geoip2 libmaxminddb
COPY GeoLite2-Country.mmdb /etc/nginx/GeoLite2-Country.mmdb
```

```nginx
load_module modules/ngx_http_geoip2_module.so;

geoip2 /etc/nginx/GeoLite2-Country.mmdb {
    $geoip2_country_code country iso_code;
}

map $geoip2_country_code $geo_prefix {
    default  "";
    DE       "/de";
    FR       "/fr";
    AT       "/de";     # Austria → German
    CH       "/de";     # Switzerland → German (or /fr for French cantons)
}

server {
    location = / {
        if ($geo_prefix != "") {
            return 302 ${geo_prefix}/home;
        }
        return 302 /home;
    }
}
```

> **Note:** MaxMind GeoLite2 requires a free account. Download via `geoipupdate` tool or CI/CD.
> In `docker-compose.server.yaml`, bind-mount the `.mmdb` file as a volume.

---

## 4. Current Docker Compose Setup

**`nginx.proxy.conf`** is mounted into the nginx container. To enable routing rules, edit this file and restart nginx (no full rebuild needed):

```bash
docker compose restart nginx
# or with server compose:
docker compose -f docker-compose.server.yaml restart nginx
```

**To make the default page configurable via `.env`:**

`.env`:
```
DEFAULT_PAGE_SLUG=home2
NGINX_LANG_REDIRECT=true
```

`docker-compose.server.yaml`:
```yaml
services:
  nginx:
    image: nginx:alpine
    environment:
      - DEFAULT_PAGE_SLUG=${DEFAULT_PAGE_SLUG:-home1}
    volumes:
      - ./nginx.proxy.conf.template:/etc/nginx/templates/default.conf.template:ro
      - ./ssl:/etc/nginx/ssl:ro
```

Use `nginx.proxy.conf.template` (with `${VAR}` substitution) instead of `nginx.proxy.conf` (static).

---

## 5. What Is NOT Yet Implemented

The following routing capabilities **do not exist in the current codebase** and require a sprint:

| Feature | Status |
|---|---|
| Default page setting in admin UI | ❌ Not built |
| DB-stored routing rules | ❌ Not built |
| `/api/v1/admin/cms/routing-rules` CRUD | ❌ Not built |
| Nginx config auto-generation from DB rules | ❌ Not built |
| Backend middleware evaluating routing rules per-request | ❌ Not built |
| Language-aware CMS pages (`/de/slug`) API support | ❌ Not built (lang field exists on CmsPage but not indexed/filtered) |
| GeoIP integration | ❌ Not built |
| `CmsPage.language` filtering in `GET /api/v1/cms/pages` | ⚠️ Partial (field exists, not filtered) |

---

## 6. Recommended Architecture for a "CMS Routing Rules" Sprint

Rather than hand-editing nginx config for every routing rule, the recommended approach is a **hybrid**:

```
Admin UI
  └─► POST /api/v1/admin/cms/routing-rules
        └─► CmsRoutingRule table (priority, match_type, match_value, target_slug, redirect_type)
              └─► GET /api/v1/cms/routing-rules  ← polled by nginx Lua / fetched at boot
                    └─► generates nginx map snippets OR
                    └─► Flask before_request middleware evaluates rules
```

### Proposed `CmsRoutingRule` model

```python
class CmsRoutingRule(BaseModel):
    name           = db.Column(db.String(120))          # human label
    is_active      = db.Column(db.Boolean, default=True)
    priority       = db.Column(db.Integer, default=0)   # lower = evaluated first

    # Match conditions (all present conditions must match — AND logic)
    match_type     = db.Column(db.String(32))           # "default", "language", "ip_range", "country", "path_prefix", "cookie"
    match_value    = db.Column(db.String(255))          # e.g. "de", "203.0.113.0/24", "DE,AT", "/old-path"

    # Action
    target_slug    = db.Column(db.String(255))          # CMS page slug or URL pattern
    redirect_code  = db.Column(db.Integer, default=302) # 301 or 302
    rewrite        = db.Column(db.Boolean, default=False) # True = transparent rewrite, False = redirect
```

### Example rules in the DB

| priority | match_type | match_value | target_slug | redirect_code |
|---|---|---|---|---|
| 0 | `default` | — | `home2` | 302 |
| 10 | `language` | `de` | `de/home` | 302 |
| 10 | `language` | `fr` | `fr/home` | 302 |
| 20 | `ip_range` | `203.0.113.0/24` | `fr/home` | 302 |
| 30 | `country` | `DE,AT,CH` | `de/home` | 302 |
| 40 | `path_prefix` | `/old-pricing` | `pricing-embedded` | 301 |

---

## Questions for Sprint Scoping

Before creating a sprint for CMS routing rules, please answer:

1. **Admin UI or config file?** Should the admin be able to manage routing rules through the admin backoffice (Vue UI), or is editing nginx/env files acceptable?

2. **Transparency:** When `/` → `/home2`, should the URL in the browser change to `/home2` (redirect), or stay at `/` while showing home2 content (rewrite/proxy)?

3. **Language detection source:** Accept-Language HTTP header (server-side, nginx), `navigator.language` (client-side, Vue), a language cookie set by the user, or all three with a priority order?

4. **GeoIP:** Do you want country-level routing (e.g. all German IPs → `/de/`) or just raw IP range rules? Country routing requires a MaxMind GeoLite2 database (free with registration).

5. **CMS language pages:** Should CMS pages support a language prefix convention (`/de/slug`, `/fr/slug`) as first-class slugs, or use a separate `language` + `slug` composite key?

6. **Rule evaluation layer:**
   - **Nginx only** (fastest, zero backend latency, but rules require nginx restart to take effect)
   - **Backend middleware** (rules take effect immediately after DB save, small latency ~1ms per request)
   - **Hybrid** (nginx handles geo/IP at network level, backend handles CMS-aware rules)

7. **A/B testing:** Do you need traffic splitting (e.g. 50% see `/home1`, 50% see `/home2`)?

8. **Scope:** Just default page + language, or the full rule engine (IP range, country, path prefix, cookie matching)?
