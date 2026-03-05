# Sprint 23: User Plugins Tab — Secure Cross-Container Plugin Management

## Context

The admin Settings page currently has two plugin management tabs:

| Tab | Data Source | Controls |
|-----|------------|----------|
| **Admin Plugins** | Local JSON files (`admin/plugins/`) via Pinia store | Config, activate/deactivate, uninstall |
| **Backend Plugins** | Backend API (`/api/v1/admin/plugins`) | Config, enable/disable |

Missing: **User Plugins** — managing the frontend plugins on the user app (`landing1`, `checkout`, etc.).

### Challenge

The user app is a **separate container** (after Sprint 22) running nginx + static assets. It has no server-side API. To manage user plugins remotely from the admin UI, we need a **lightweight Node.js API server** inside the user container that:

1. Reads/writes `plugins.json` and plugin config files
2. Exposes REST endpoints for plugin management
3. Is secured against unauthorized access, bots, and brute-force attacks

### Target Architecture

```
Admin App (port 8081)                    User Container (port 8080)
┌─────────────────────┐                 ┌──────────────────────────────┐
│ Settings.vue        │                 │ nginx (port 80)              │
│  └─ User Plugins tab│   HTTP/HTTPS   │  ├─ /          → static SPA  │
│     └─ API calls ───┼────────────────▶│  ├─ /api      → backend     │
│                     │                 │  └─ /_plugins  → node:3001   │
│ UserPluginDetails   │                 │                              │
│  └─ Config forms    │                 │ Node.js API (port 3001)      │
└─────────────────────┘                 │  ├─ HMAC auth middleware     │
                                        │  ├─ Rate limiting            │
                                        │  ├─ GET  /_plugins/          │
                                        │  ├─ GET  /_plugins/:name     │
                                        │  ├─ PUT  /_plugins/:name/cfg │
                                        │  ├─ POST /_plugins/:name/on  │
                                        │  └─ POST /_plugins/:name/off │
                                        └──────────────────────────────┘
```

The admin app calls `http://localhost:8080/_plugins/...` which nginx proxies to the internal Node.js server on port 3001.

---

## Core Requirements (enforced across all tasks)

| Principle | How it applies in this sprint |
|-----------|-------------------------------|
| **TDD-First** | Write failing tests (RED) before implementation (GREEN), then refactor. Tests for Node.js HMAC middleware, plugin config service, admin store, Settings User Plugins tab, and UserPluginDetails page all written before the implementation code. |
| **Security-First** | HMAC-signed requests with shared secret + timestamp. Rate limiting. No plaintext API keys in transit. CORS restricted to admin origin. Timing-safe signature comparison to prevent timing attacks. |
| **DRY** | Reuse admin plugin tab patterns (Settings.vue table, detail page config form). Node.js config store mirrors backend's JSON-based approach. HMAC signing utility is a single shared module used by all API calls. |
| **SOLID — SRP** | Node.js API handles plugin file I/O. HMAC middleware handles authentication only. Rate limiter handles throttling only. Admin store handles HTTP calls. UI components handle display. Each layer has one job. |
| **SOLID — OCP** | Adding new user plugins requires zero changes to the management API or admin UI — plugin discovery is automatic from filesystem. New field types in `admin-config.json` can be added without modifying the config form renderer. |
| **SOLID — LSP** | All plugin tabs (Admin, Backend, User) follow the same interface contract: list view with search/sort/status, detail view with config form. `UserPluginDetails.vue` is interchangeable with `BackendPluginDetails.vue` from the user's perspective. |
| **SOLID — ISP** | Plugin config schema (`config.json`) is separate from admin form layout (`admin-config.json`). Plugins without config files still appear in the list — they just show "No configuration available" in detail view. HMAC auth is a standalone middleware, not coupled to route logic. |
| **SOLID — DIP** | Admin store depends on an API client abstraction (`userPluginApi.ts`), not on direct HTTP calls. Node.js plugin service depends on filesystem abstractions, not on concrete file paths. Views depend on store interface, not on transport details. |
| **Clean Code** | Self-documenting component names (`UserPluginDetails`, `hmac-auth`, `plugin-config`). Consistent `data-testid` attributes on all interactive elements. No magic strings — all labels from i18n. All security parameters (timestamp window, rate limit) are named constants. |
| **Type Safety** | Strict TypeScript on both Node.js server and admin frontend. Shared interfaces for `UserPluginEntry`, `UserPluginDetail`, `PluginConfigField`, `AdminConfigTab`. No `any` types. Props, store state, and API responses fully typed. |
| **Coverage** | 90%+ for HMAC middleware (valid/invalid/expired/missing). 90%+ for plugin config service (CRUD, atomic writes, error handling). 80%+ for admin store (fetch, save, enable/disable, error states). 80%+ for UserPluginDetails (render, config form, lifecycle actions). |
| **Minimal Footprint** | Node.js API uses Express with zero unnecessary dependencies. Only `express`, `express-rate-limit`, `cors`, and `crypto` (built-in). No ORM, no database — JSON files only. |

---

## Security Design

### Authentication: HMAC Request Signing

Every request from admin to the user plugin API must be signed:

```
X-Plugin-Timestamp: 1707600000
X-Plugin-Signature: HMAC-SHA256(secret, "METHOD:PATH:TIMESTAMP:BODY")
```

**Validation rules:**
1. `X-Plugin-Timestamp` must be within ±30 seconds of server time (prevents replay attacks)
2. `X-Plugin-Signature` must match `HMAC-SHA256(PLUGIN_API_SECRET, "METHOD:PATH:TIMESTAMP:BODY_OR_EMPTY")`
3. `PLUGIN_API_SECRET` is a shared env var set in both admin and user containers via docker-compose

**Why HMAC over API key:**
- API key in headers can be sniffed in transit (no TLS in local Docker network)
- HMAC signs the request content, so intercepted requests can't be replayed or tampered with
- Timestamp window prevents captured signatures from being reused

### Rate Limiting

- 30 requests per minute per IP (generous for admin usage, restrictive for brute-force)
- 429 Too Many Requests response with Retry-After header

### CORS

- `Access-Control-Allow-Origin: http://localhost:8081` (admin app only)
- No wildcard origins

### Network Isolation (Future)

- In production, the plugin API should only be accessible from the Docker internal network
- For this sprint, rely on HMAC auth + rate limiting (sufficient for development)

---

## Testing Approach

```bash
# Node.js API server tests
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# Admin frontend tests
cd vbwd-frontend/admin/vue && npx vitest run

# Full pre-commit
cd vbwd-frontend && make test
```

**Test categories for this sprint:**

| Category | What it covers |
|----------|----------------|
| User unit | Node.js plugin API: HMAC validation, CRUD operations, rate limiting, error handling |
| Admin unit | User plugins store actions, Settings User Plugins tab rendering |
| Admin integration | UserPluginDetails page: config form, enable/disable, install/uninstall |

**Existing test counts (must not regress):**
- Admin: 305 tests
- User: 115 tests
- Core: 289 tests
- Backend: 626 tests

---

## Task 1: Node.js Plugin API Server

Create a lightweight Express server inside the user app that manages user plugins.

### Location: `user/server/`

```
user/
  server/
    index.ts              # Express app, starts on port 3001
    middleware/
      hmac-auth.ts        # HMAC signature validation middleware
      rate-limit.ts       # Rate limiting configuration
    routes/
      plugins.ts          # Plugin CRUD routes
    services/
      plugin-config.ts    # Read/write plugins.json, config.json, per-plugin configs
    types.ts              # Shared TypeScript interfaces
```

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/_plugins` | List all user plugins with status, version, description |
| `GET` | `/_plugins/:name` | Plugin detail: config schema, admin-config, saved config |
| `PUT` | `/_plugins/:name/config` | Save plugin configuration |
| `POST` | `/_plugins/:name/enable` | Enable plugin (write to plugins.json) |
| `POST` | `/_plugins/:name/disable` | Disable plugin (write to plugins.json) |
| `POST` | `/_plugins/:name/install` | Mark plugin as installed in plugins.json |
| `POST` | `/_plugins/:name/uninstall` | Mark plugin as uninstalled (keep files) |

### Response Format

Matches backend plugin API format for consistency:

```json
// GET /_plugins
[
  {
    "name": "landing1",
    "version": "1.0.0",
    "description": "Public landing page with tariff plan selection",
    "status": "active",
    "hasConfig": true
  }
]

// GET /_plugins/:name
{
  "name": "landing1",
  "version": "1.0.0",
  "description": "Public landing page with tariff plan selection",
  "author": "",
  "status": "active",
  "dependencies": [],
  "configSchema": { ... },
  "adminConfig": { "tabs": [...] },
  "savedConfig": { ... }
}
```

### Plugin Discovery

Scan `user/plugins/` for directories containing at minimum `index.ts`. If `config.json` and `admin-config.json` also exist, include config data. Plugins without config files still appear in the list but show "No configuration available" in detail view.

### Config Store

Mirror the backend's JSON-based config store:
- `user/plugins.json` — plugin registry (already exists: has `landing1`, `checkout`)
- `user/plugins/config.json` — saved config values per plugin (NEW)
- `user/plugins/<name>/config.json` — per-plugin config schema (NEW, optional)
- `user/plugins/<name>/admin-config.json` — per-plugin admin UI layout (NEW, optional)

Atomic file writes with temp file + rename (same pattern as backend `json_config_store.py`).

### Dependencies

Add to `user/package.json`:
```json
{
  "dependencies": {
    "express": "^4.21.0",
    "cors": "^2.8.5",
    "express-rate-limit": "^7.5.0"
  },
  "devDependencies": {
    "@types/express": "^5.0.0",
    "@types/cors": "^2.8.17"
  }
}
```

### Files:
- NEW: `user/server/index.ts`
- NEW: `user/server/middleware/hmac-auth.ts`
- NEW: `user/server/middleware/rate-limit.ts`
- NEW: `user/server/routes/plugins.ts`
- NEW: `user/server/services/plugin-config.ts`
- NEW: `user/server/types.ts`
- EDIT: `user/package.json` (add dependencies + `start:api` script)

---

## Task 2: HMAC Auth Middleware

### `user/server/middleware/hmac-auth.ts`

```typescript
// Validates incoming requests using HMAC-SHA256 signature
//
// Required headers:
//   X-Plugin-Timestamp: Unix epoch seconds (must be within ±30s of server time)
//   X-Plugin-Signature: HMAC-SHA256(secret, "METHOD:PATH:TIMESTAMP:BODY")
//
// Environment:
//   PLUGIN_API_SECRET: shared secret (required, server refuses to start without it)
//
// Rejection responses:
//   401 { error: "Missing authentication headers" }
//   401 { error: "Request expired" }
//   401 { error: "Invalid signature" }
```

**Implementation notes:**
- Use `crypto.createHmac('sha256', secret)` (Node.js built-in, no extra dependency)
- Compare signatures using `crypto.timingSafeEqual()` to prevent timing attacks
- Log rejected requests at WARN level (IP, timestamp, path) for monitoring
- `PLUGIN_API_SECRET` must be at least 32 characters; server exits with error if missing or too short

### Files:
- NEW: `user/server/middleware/hmac-auth.ts`

---

## Task 3: User Container Dockerfile Update

After Sprint 22 creates the separate user Dockerfile, update it to also run the Node.js API server alongside nginx.

### Approach: Supervisor Process

Use a lightweight process manager to run both nginx and the Node.js API:

```dockerfile
# ... (build stages from Sprint 22) ...

# Build stage - Plugin API server
FROM node:20-alpine AS build-server

WORKDIR /app/server
COPY user/server/package*.json ./
RUN npm install --production
COPY user/server/ ./
RUN npx tsc

# Production stage
FROM node:20-alpine

# Install nginx
RUN apk add --no-cache nginx

# Copy built assets
COPY --from=build-user /app/user/dist /usr/share/nginx/html
COPY --from=build-server /app/server/dist /app/server/dist
COPY --from=build-server /app/server/node_modules /app/server/node_modules

# Copy configs
COPY container/user/nginx.conf /etc/nginx/nginx.conf
COPY container/user/start.sh /start.sh
RUN chmod +x /start.sh

# Plugin data directory (mounted as volume for persistence)
RUN mkdir -p /app/plugins

EXPOSE 80

CMD ["/start.sh"]
```

### `container/user/start.sh`

```bash
#!/bin/sh
# Start Node.js plugin API in background
node /app/server/dist/index.js &

# Start nginx in foreground
nginx -g 'daemon off;'
```

### Nginx Update — Proxy `/_plugins` to Node.js

Add to `container/user/nginx.conf`:

```nginx
# Plugin management API (internal, HMAC-authenticated)
location /_plugins {
    proxy_pass http://127.0.0.1:3001;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

### Docker-Compose Update

Add shared secret and plugin data volume:

```yaml
user-app:
  # ... existing config ...
  environment:
    - VITE_API_URL=/api/v1
    - PLUGIN_API_SECRET=${PLUGIN_API_SECRET}
  volumes:
    - user-plugin-data:/app/plugins

admin-app:
  # ... existing config ...
  environment:
    - VITE_API_URL=/api/v1
    - VITE_USER_APP_URL=http://localhost:8080
    - PLUGIN_API_SECRET=${PLUGIN_API_SECRET}
```

Add `PLUGIN_API_SECRET` to `.env.example`:
```
PLUGIN_API_SECRET=your-secret-key-at-least-32-characters-long
```

### Files:
- EDIT: `container/user/Dockerfile` (add server build stage, switch to node+nginx)
- NEW: `container/user/start.sh`
- EDIT: `container/user/nginx.conf` (add `/_plugins` proxy)
- EDIT: `docker-compose.yaml` (add env vars, volumes)
- NEW or EDIT: `.env.example` (add `PLUGIN_API_SECRET`)

---

## Task 4: Plugin Config Files for User Plugins

Create config and admin-config files for existing user plugins so they're manageable from the admin UI.

### `user/plugins/landing1/config.json`
```json
{
  "heroTitle": {
    "type": "string",
    "default": "Choose Your Plan",
    "description": "Main heading on the landing page"
  },
  "showPrices": {
    "type": "boolean",
    "default": true,
    "description": "Display prices on plan cards"
  },
  "columnsPerRow": {
    "type": "number",
    "default": 3,
    "description": "Number of plan cards per row"
  }
}
```

### `user/plugins/landing1/admin-config.json`
```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        {
          "key": "heroTitle",
          "label": "Hero Title",
          "component": "input",
          "inputType": "text"
        },
        {
          "key": "showPrices",
          "label": "Show Prices",
          "component": "checkbox"
        },
        {
          "key": "columnsPerRow",
          "label": "Columns Per Row",
          "component": "input",
          "inputType": "number",
          "min": 1,
          "max": 4
        }
      ]
    }
  ]
}
```

### `user/plugins/checkout/config.json`
```json
{
  "requireTerms": {
    "type": "boolean",
    "default": true,
    "description": "Require terms acceptance before checkout"
  },
  "allowGuestCheckout": {
    "type": "boolean",
    "default": true,
    "description": "Allow checkout without login"
  }
}
```

### `user/plugins/checkout/admin-config.json`
```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        {
          "key": "requireTerms",
          "label": "Require Terms Acceptance",
          "component": "checkbox"
        },
        {
          "key": "allowGuestCheckout",
          "label": "Allow Guest Checkout",
          "component": "checkbox"
        }
      ]
    }
  ]
}
```

### `user/plugins/config.json` (central saved values)
```json
{
  "landing1": {},
  "checkout": {}
}
```

### Files:
- NEW: `user/plugins/landing1/config.json`
- NEW: `user/plugins/landing1/admin-config.json`
- NEW: `user/plugins/checkout/config.json`
- NEW: `user/plugins/checkout/admin-config.json`
- NEW: `user/plugins/config.json`

---

## Task 5: Admin User Plugins Store

Create a Pinia store in the admin app that communicates with the user container's plugin API.

### `admin/vue/src/stores/userPlugins.ts`

```typescript
// Mirrors the structure of the backend plugins store but targets user container API
//
// State:
//   plugins: UserPluginEntry[]
//   pluginDetail: UserPluginDetail | null
//   loading, error
//
// Actions:
//   fetchPlugins()           → GET http://<USER_APP_URL>/_plugins
//   fetchPluginDetail(name)  → GET http://<USER_APP_URL>/_plugins/:name
//   savePluginConfig(name, config) → PUT http://<USER_APP_URL>/_plugins/:name/config
//   enablePlugin(name)       → POST http://<USER_APP_URL>/_plugins/:name/enable
//   disablePlugin(name)      → POST http://<USER_APP_URL>/_plugins/:name/disable
//   installPlugin(name)      → POST http://<USER_APP_URL>/_plugins/:name/install
//   uninstallPlugin(name)    → POST http://<USER_APP_URL>/_plugins/:name/uninstall
//
// HMAC Signing:
//   All requests include X-Plugin-Timestamp and X-Plugin-Signature headers
//   Signature = HMAC-SHA256(PLUGIN_API_SECRET, "METHOD:PATH:TIMESTAMP:BODY")
//   PLUGIN_API_SECRET injected via VITE_PLUGIN_API_SECRET env var at build time
```

### HMAC Signing Utility

Create `admin/vue/src/utils/hmac.ts`:

```typescript
// signRequest(method: string, path: string, body?: string): { timestamp: string, signature: string }
//
// Uses Web Crypto API (SubtleCrypto) available in all modern browsers
// Falls back to importing the secret from VITE_PLUGIN_API_SECRET env var
```

### API Client

Create `admin/vue/src/api/userPluginApi.ts`:

```typescript
// Dedicated API client for user container plugin management
// Base URL: VITE_USER_APP_URL (default: 'http://localhost:8080')
// Prefix: /_plugins
// All requests auto-signed with HMAC
```

### Files:
- NEW: `admin/vue/src/stores/userPlugins.ts`
- NEW: `admin/vue/src/utils/hmac.ts`
- NEW: `admin/vue/src/api/userPluginApi.ts`

---

## Task 6: User Plugins Tab in Settings.vue

Add a 6th tab "User Plugins" to Settings.vue, after "Backend Plugins".

### Tab Definition

```typescript
type MainTab = 'core' | 'tokens' | 'countries' | 'adminPlugins' | 'backendPlugins' | 'userPlugins';
```

### Template

Same table pattern as Backend Plugins tab:
- Searchable, sortable table with columns: Name, Version, Status, Actions
- Status badges: Active (green), Inactive (grey), Error (red)
- Enable/Disable toggle buttons
- Click plugin name → navigate to `/admin/settings/user-plugins/:pluginName`
- Lazy-load data when tab first selected

### Script

- Import `useUserPluginsStore`
- Add: `userPluginsLoaded`, `userPluginsLoading`, `userPluginsError`, `userPluginSearchQuery`, `userPluginSortKey`, `userPluginSortDir`
- Computed: `filteredUserPlugins`, `sortedUserPlugins`
- Watcher: load user plugins on tab select
- Handlers: `handleUserPluginSort()`, `handleUserPluginEnable()`, `handleUserPluginDisable()`

### Files:
- EDIT: `admin/vue/src/views/Settings.vue`

---

## Task 7: User Plugin Details Page

Create `UserPluginDetails.vue` following the same pattern as `BackendPluginDetails.vue`.

### Route

```typescript
{
  path: 'settings/user-plugins/:pluginName',
  name: 'user-plugin-details',
  component: () => import('@/views/UserPluginDetails.vue')
}
```

### Features (identical to BackendPluginDetails.vue)

- Plugin header: name, version, description, status badge
- Enable/Disable buttons calling user plugin API
- Install/Uninstall buttons (mark in registry, don't delete files)
- Dynamic config tabs from `admin-config.json`
- Config form with input, checkbox, select, textarea fields
- Save configuration
- Back link to Settings (User Plugins tab)

### Files:
- NEW: `admin/vue/src/views/UserPluginDetails.vue`
- EDIT: `admin/vue/src/router/index.ts` (add `user-plugin-details` route)

---

## Task 8: i18n — All Locale Files

Add keys for the User Plugins tab and detail page. Namespace: `userPlugins.*`

```
userPlugins.title           — "User Plugins"
userPlugins.description     — "Manage frontend plugins installed on the user application."
userPlugins.search          — "Search user plugins..."
userPlugins.noPlugins       — "No user plugins found"
userPlugins.columns.name    — "Name"
userPlugins.columns.version — "Version"
userPlugins.columns.status  — "Status"
userPlugins.columns.actions — "Actions"
userPlugins.enable          — "Enable"
userPlugins.disable         — "Disable"
userPlugins.install         — "Install"
userPlugins.uninstall       — "Uninstall"
userPlugins.view            — "View"
userPlugins.active          — "Active"
userPlugins.inactive        — "Inactive"
userPlugins.error           — "Error"
userPlugins.detail.title    — "User Plugin Details"
userPlugins.detail.back     — "Back to User Plugins"
userPlugins.detail.activate — "Activate"
userPlugins.detail.deactivate — "Deactivate"
userPlugins.detail.install  — "Install"
userPlugins.detail.uninstall — "Uninstall"
userPlugins.detail.confirmDeactivate  — "Are you sure you want to deactivate this plugin?"
userPlugins.detail.confirmUninstall   — "Are you sure you want to uninstall this plugin? Plugin files will remain on disk."
userPlugins.detail.configSaved        — "Configuration saved successfully"
userPlugins.detail.saveConfig         — "Save Configuration"
userPlugins.detail.saving             — "Saving..."
userPlugins.detail.noConfig           — "This plugin has no configuration options."
userPlugins.connectionError           — "Cannot connect to user application. Is it running?"
```

### Files:
- EDIT: `admin/vue/src/i18n/locales/en.json`
- EDIT: `admin/vue/src/i18n/locales/de.json`
- EDIT: `admin/vue/src/i18n/locales/fr.json`
- EDIT: `admin/vue/src/i18n/locales/es.json`
- EDIT: `admin/vue/src/i18n/locales/ru.json`
- EDIT: `admin/vue/src/i18n/locales/zh.json`
- EDIT: `admin/vue/src/i18n/locales/ja.json`
- EDIT: `admin/vue/src/i18n/locales/th.json`

---

## Task 9: Tests

### Node.js API Server Tests

NEW: `user/vue/tests/unit/server/hmac-auth.spec.ts`
- Valid signature → 200
- Missing headers → 401
- Expired timestamp → 401
- Invalid signature → 401
- Timing-safe comparison (no timing leak)

NEW: `user/vue/tests/unit/server/plugin-config.spec.ts`
- Read plugins.json → returns plugin list
- Read plugin detail → merges config schema + admin-config + saved config
- Write config → updates config.json atomically
- Enable/disable → updates plugins.json status
- Install/uninstall → adds/removes from plugins.json
- Non-existent plugin → 404

NEW: `user/vue/tests/unit/server/rate-limit.spec.ts`
- Under limit → 200
- Over limit → 429 with Retry-After header

### Admin Frontend Tests

NEW: `admin/vue/tests/unit/stores/userPlugins.spec.ts`
- fetchPlugins → populates state from API
- fetchPluginDetail → loads detail with config
- savePluginConfig → sends PUT with HMAC headers
- enablePlugin/disablePlugin → sends POST with correct path
- Error handling → sets error state on 401/500

NEW: `admin/vue/tests/unit/utils/hmac.spec.ts`
- Generates correct HMAC-SHA256 signature
- Includes timestamp in signing string
- Includes request body for PUT/POST

EDIT: `admin/vue/tests/integration/Settings.spec.ts`
- Add assertion for `tab-userPlugins` existence

NEW: `admin/vue/tests/integration/UserPluginDetails.spec.ts`
- Renders plugin header (name, version, description, status badge)
- Renders config tabs from admin-config
- Form fields render correctly per type
- Save config button calls store
- Enable/disable buttons work
- Connection error shown when API unreachable

### Files:
- NEW: `user/vue/tests/unit/server/hmac-auth.spec.ts`
- NEW: `user/vue/tests/unit/server/plugin-config.spec.ts`
- NEW: `user/vue/tests/unit/server/rate-limit.spec.ts`
- NEW: `admin/vue/tests/unit/stores/userPlugins.spec.ts`
- NEW: `admin/vue/tests/unit/utils/hmac.spec.ts`
- EDIT: `admin/vue/tests/integration/Settings.spec.ts`
- NEW: `admin/vue/tests/integration/UserPluginDetails.spec.ts`

---

## Implementation Order

1. Task 4 — Plugin config files for user plugins (filesystem setup)
2. Task 1 — Node.js plugin API server (core server code)
3. Task 2 — HMAC auth middleware (security layer)
4. Task 3 — User container Dockerfile update (deployment)
5. Task 5 — Admin user plugins store + HMAC utility (data layer)
6. Task 8 — i18n keys (needed by UI)
7. Task 6 — User Plugins tab in Settings.vue (list view)
8. Task 7 — UserPluginDetails page + router (detail view)
9. Task 9 — Tests

---

## File Summary

| Action | File |
|--------|------|
| NEW | `user/server/index.ts` |
| NEW | `user/server/middleware/hmac-auth.ts` |
| NEW | `user/server/middleware/rate-limit.ts` |
| NEW | `user/server/routes/plugins.ts` |
| NEW | `user/server/services/plugin-config.ts` |
| NEW | `user/server/types.ts` |
| NEW | `user/server/package.json` |
| NEW | `user/server/tsconfig.json` |
| NEW | `user/plugins/landing1/config.json` |
| NEW | `user/plugins/landing1/admin-config.json` |
| NEW | `user/plugins/checkout/config.json` |
| NEW | `user/plugins/checkout/admin-config.json` |
| NEW | `user/plugins/config.json` |
| NEW | `admin/vue/src/stores/userPlugins.ts` |
| NEW | `admin/vue/src/utils/hmac.ts` |
| NEW | `admin/vue/src/api/userPluginApi.ts` |
| NEW | `admin/vue/src/views/UserPluginDetails.vue` |
| EDIT | `admin/vue/src/views/Settings.vue` (add User Plugins tab) |
| EDIT | `admin/vue/src/router/index.ts` (add user-plugin-details route) |
| EDIT | `admin/vue/src/i18n/locales/*.json` (8 locale files) |
| EDIT | `container/user/Dockerfile` (add server build stage) |
| NEW | `container/user/start.sh` |
| EDIT | `container/user/nginx.conf` (add /_plugins proxy) |
| EDIT | `docker-compose.yaml` (add env vars, volumes) |
| EDIT | `user/package.json` (add server dependencies) |
| NEW | `user/vue/tests/unit/server/hmac-auth.spec.ts` |
| NEW | `user/vue/tests/unit/server/plugin-config.spec.ts` |
| NEW | `user/vue/tests/unit/server/rate-limit.spec.ts` |
| NEW | `admin/vue/tests/unit/stores/userPlugins.spec.ts` |
| NEW | `admin/vue/tests/unit/utils/hmac.spec.ts` |
| EDIT | `admin/vue/tests/integration/Settings.spec.ts` |
| NEW | `admin/vue/tests/integration/UserPluginDetails.spec.ts` |

---

## Verification

### Automated Tests

```bash
# 1. Node.js server unit tests
cd vbwd-frontend/user && npx vitest run --config vitest.config.js

# 2. Admin unit + integration tests
cd vbwd-frontend/admin/vue && npx vitest run

# 3. Full pre-commit
cd vbwd-frontend && make test

# 4. Core regression
cd vbwd-frontend/core && npx vitest run
```

### Integration Verification

```bash
# Build and start containers with plugin secret
export PLUGIN_API_SECRET="test-secret-key-at-least-32-characters-long-for-hmac"
cd vbwd-frontend && docker compose up -d --build user-app admin-app

# Test plugin API directly (must fail without HMAC)
curl -s http://localhost:8080/_plugins
# Expected: 401 {"error":"Missing authentication headers"}

# Test with valid HMAC (bash example)
TIMESTAMP=$(date +%s)
SIGNATURE=$(echo -n "GET:/_plugins:$TIMESTAMP:" | openssl dgst -sha256 -hmac "$PLUGIN_API_SECRET" -hex | cut -d' ' -f2)
curl -s -H "X-Plugin-Timestamp: $TIMESTAMP" -H "X-Plugin-Signature: $SIGNATURE" http://localhost:8080/_plugins
# Expected: 200 [{"name":"landing1",...},{"name":"checkout",...}]
```

### Manual Smoke Test

1. Open `http://localhost:8081/admin/settings`
2. Verify 6 tabs: Core Settings, Token Bundles, Countries, Admin Plugins, Backend Plugins, **User Plugins**
3. Click **User Plugins** tab
4. Verify `landing1` and `checkout` appear with status badges
5. Click `landing1` → **User Plugin Details** page
6. Verify config form: Hero Title (text), Show Prices (checkbox), Columns Per Row (number)
7. Change a value, click Save → success message
8. Click Disable → status changes to Inactive
9. Click Enable → status changes back to Active
10. Navigate back to Settings, verify status column updated
11. Stop user container → User Plugins tab shows connection error message
12. Restart user container → tab loads again
