# VBWD Developer Guide

A complete reference for developers working on or extending the **vbwd-sdk** SaaS platform.

---

## Table of Contents

1. [Platform Overview](#1-platform-overview)
2. [Repository Structure](#2-repository-structure)
3. [Backend Architecture](#3-backend-architecture)
4. [Backend Plugin System](#4-backend-plugin-system)
5. [Frontend Architecture](#5-frontend-architecture)
6. [Frontend Plugin System](#6-frontend-plugin-system)
7. [Security Architecture](#7-security-architecture)
8. [Data Patterns](#8-data-patterns)
9. [Testing Strategy](#9-testing-strategy)
10. [Development Workflow](#10-development-workflow)

---

## 1. Platform Overview

**vbwd-sdk** is a self-hosted SaaS platform providing:

- Subscription billing with multiple billing periods and trial support
- Hierarchical plan categories with exclusivity rules
- Invoice generation with line items, tax calculation, and PDF export
- Token economy for AI/usage-based features
- Plugin system for payment providers, content management, AI features, and software distribution
- Separate admin and user-facing frontends, both extensible via plugins

**Editions:**
- **CE (Community Edition)** — self-hosted, current focus
- **ME (Marketplace Edition)** — cloud SaaS marketplace, planned

**Tech Stack at a glance:**

| Layer | Technology |
|---|---|
| Backend | Python 3.11, Flask 3.0, SQLAlchemy 2.0 |
| Database | PostgreSQL 16, Redis 7 |
| Migrations | Alembic |
| Frontend | Vue 3.4, Vite 5, Pinia 2, Vue Router 4, TypeScript 5.3 |
| Testing | pytest, Vitest, Playwright |
| Container | Docker, Docker Compose, Gunicorn, Nginx |

---

## 2. Repository Structure

The project is split into four independent Git repositories, co-located for development:

```
vbwd-sdk-2/                        # Monorepo root (development only)
├── vbwd-backend/                  # Python/Flask API
│   ├── src/                       # Application source
│   │   ├── models/                # SQLAlchemy ORM models
│   │   ├── routes/                # Flask blueprints (grouped by domain)
│   │   ├── services/              # Business logic layer
│   │   ├── repositories/          # Data access layer
│   │   ├── plugins/               # Plugin framework (base, manager, config)
│   │   └── extensions.py          # SQLAlchemy, Redis, JWT instances
│   ├── plugins/                   # Installed plugins
│   │   ├── cms/                   # Content management
│   │   ├── ghrm/                  # GitHub Repo Manager
│   │   ├── taro/                  # AI Tarot
│   │   ├── stripe/                # Stripe payments
│   │   ├── paypal/                # PayPal payments
│   │   └── ...
│   ├── alembic/                   # Core DB migrations
│   ├── bin/                       # CLI scripts
│   └── Makefile                   # Development commands
│
├── vbwd-fe-core/                  # Shared Vue component library
│   └── src/
│       ├── plugins/               # Plugin system (SDK, registry, types)
│       ├── api/                   # HTTP client
│       ├── stores/                # Pinia stores (auth, cart, subscription)
│       ├── composables/           # Vue composables
│       ├── components/            # Shared UI components
│       └── guards/                # Vue Router guards
│
├── vbwd-fe-user/                  # User-facing Vue application (port 8080)
│   ├── vue/                       # Core app
│   └── plugins/                   # User-app plugins (cms, checkout, ghrm, taro…)
│
└── vbwd-fe-admin/                 # Admin backoffice Vue application (port 8081)
    ├── src/                       # Core admin app
    └── plugins/                   # Admin plugins (cms-admin, ghrm-admin, taro-admin…)
```

**Critical rules:**
- The **core is agnostic** — `src/` never imports from `plugins/`
- All plugin-specific code lives under `plugins/<name>/`
- `vbwd-fe-user` and `vbwd-fe-admin` depend on `vbwd-fe-core` via git submodule
- Build order: `vbwd-fe-core` must be built before either app can install

---

## 3. Backend Architecture

### 3.1 Layered Architecture

```
HTTP Request
    │
    ▼
Routes (Flask Blueprints)        ← input validation, auth guards, HTTP contract
    │
    ▼
Services                         ← business logic, orchestration
    │
    ▼
Repositories                     ← data access, all DB queries
    │
    ▼
Models (SQLAlchemy)              ← schema definition, serialization
    │
    ▼
PostgreSQL / Redis
```

Each layer has a single responsibility. **Routes never access the database directly.** Services never know about HTTP. Repositories never contain business rules.

### 3.2 Service Pattern

Services are instantiated in factory functions inside `routes.py` using `db.session`. They are **not singletons** — a new instance is created per request, bound to the current session, ensuring clean transaction scope.

```python
# routes.py
def _svc() -> MyService:
    return MyService(
        repo=MyRepository(db.session),
        other_repo=OtherRepository(db.session),
    )

@bp.route("/api/v1/things", methods=["GET"])
def list_things():
    return jsonify(_svc().list())
```

### 3.3 Repository Pattern

All database access goes through repositories. A repository for a given model:
- Has `find_by_id`, `find_by_slug`, `save`, `delete` as baseline methods
- Never raises HTTP errors — raises domain exceptions instead
- Returns model instances or `None`

```python
class MyRepository:
    def __init__(self, session):
        self._session = session

    def find_by_id(self, id: UUID) -> Optional[MyModel]:
        return self._session.query(MyModel).filter_by(id=id).first()

    def save(self, obj: MyModel) -> MyModel:
        self._session.add(obj)
        self._session.flush()
        return obj
```

### 3.4 Model Pattern

All models inherit from `BaseModel`, which provides:
- `id` — UUID primary key (generated server-side)
- `created_at` — creation timestamp
- `updated_at` — last-update timestamp (auto-maintained)
- `version` — integer, used for optimistic locking

```python
from src.models.base import BaseModel
from src.extensions import db

class MyModel(BaseModel):
    __tablename__ = "my_table"

    name = db.Column(db.String(255), nullable=False)
    config = db.Column(db.JSON, nullable=True, default=dict)

    def to_dict(self) -> dict:
        return {
            "id": str(self.id),
            "name": self.name,
            "config": self.config,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
```

Rules:
- UUID columns use `db.Column(db.UUID, db.ForeignKey(...))` — not `Integer`
- `to_dict()` always serializes UUIDs as `str(...)` and datetimes with `.isoformat()`
- Never expose password hashes, sync API keys, or internal flags in `to_dict()`

### 3.5 Dependency Injection

Services are wired via `dependency-injector` in `container.py`. This is used for the application core. Plugin services do **not** use the DI container — they are instantiated directly in their `routes.py` factory functions.

### 3.6 Event System

The platform has two event subsystems that work together:

| System | Location | Purpose |
|---|---|---|
| `DomainEventDispatcher` | `src/events/domain.py` | Typed `IEventHandler` objects for core business logic |
| `EventBus` | `src/events/bus.py` | Callback-based pub/sub for plugins |

**`DomainEventDispatcher`** is used by core services to emit structured domain events:

```python
from src.events.domain import DomainEventDispatcher, IEventHandler, EventResult
from src.events.subscription_events import SubscriptionActivatedEvent

# Register a typed handler (core services only)
dispatcher = DomainEventDispatcher()
dispatcher.register("subscription.activated", MyTypedHandler())

# Emit — runs typed handlers, then forwards to EventBus automatically
dispatcher.emit(SubscriptionActivatedEvent(
    name="subscription.activated",
    data={"user_id": str(user.id), "plan_id": str(plan.id)},
))
```

**`EventBus`** is used by plugins. After `DomainEventDispatcher.emit()` runs its typed handlers, it automatically calls `event_bus.publish(event.name, event.data)` — the bridge requires no call-site changes. Plugins subscribe in `register_event_handlers(bus)` (see §4.3 and §4.9).

```python
from src.events import event_bus

# Subscribe (from a plugin's register_event_handlers)
event_bus.subscribe("subscription.activated", my_callback)

# Publish a plugin-to-plugin event
event_bus.publish("my_plugin.thing_happened", {"item_id": str(item.id)})
```

**Import:**
```python
from src.events import event_bus          # EventBus singleton
from src.events import DomainEventDispatcher, IEventHandler, DomainEvent
```

See `docs/dev_docs/event-bus.md` for the full reference.

### 3.7 Migrations

**Core migrations** live in `/alembic/versions/`. Each plugin maintains its own migrations under `plugins/<name>/migrations/versions/`.

```bash
# Create a migration
docker compose exec api flask db migrate -m "add my column"

# Apply
docker compose exec api flask db upgrade

# Plugin migrations are applied with the same command if registered
```

Migration naming convention: `YYYYMMDD_description.py`

Each plugin migration must set `down_revision` to the previous migration in the plugin's own chain, not the core chain.

---

## 4. Backend Plugin System

### 4.1 Concepts

The plugin system provides a structured way to extend the platform without modifying core code. Plugins:
- Add Flask routes (blueprints)
- Add database models and migrations
- Hook into subscription lifecycle events
- Register plan categories
- Store their own configuration in the database

**The core is agnostic.** `src/` never imports from `plugins/`. Plugins import from `src/` but not from each other (unless declared as dependencies).

### 4.2 Plugin Status Lifecycle

```
DISCOVERED → REGISTERED → INITIALIZED → ENABLED ⇆ DISABLED
                                          │
                                          └── ERROR (on exception)
```

| Status | Meaning |
|---|---|
| `DISCOVERED` | Class instantiated but not yet in registry |
| `REGISTERED` | Added to `PluginManager._plugins` |
| `INITIALIZED` | `initialize(config)` called; configuration merged |
| `ENABLED` | `on_enable()` called; routes active; categories registered |
| `DISABLED` | `on_disable()` called; routes no longer served |
| `ERROR` | An exception occurred during a lifecycle transition |

### 4.3 BasePlugin API

```python
from src.plugins.base import BasePlugin, PluginMetadata

class MyPlugin(BasePlugin):

    # ── Required ──────────────────────────────────────────────────────────────

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="my-plugin",           # Unique ID used everywhere
            version="1.0.0",            # Semver
            author="Your Name",
            description="What it does",
            dependencies=[],            # List of plugin names that must be ENABLED first
        )

    # ── Optional overrides ────────────────────────────────────────────────────

    def initialize(self, config=None) -> None:
        merged = {**DEFAULT_CONFIG}
        if config:
            merged.update(config)
        super().initialize(merged)      # sets self._config and status=INITIALIZED

    def get_blueprint(self):
        from plugins.my_plugin.src.routes import my_bp
        return my_bp

    def get_url_prefix(self) -> str:
        # Return "" if your routes already have absolute paths
        # Return "/api/v1/prefix" if routes use relative paths
        return "/api/v1/my-plugin"

    def register_categories(self) -> list:
        return [
            {"name": "My Category", "slug": "my-cat", "is_single": True, "sort_order": 10}
        ]

    def on_enable(self) -> None:
        """Set up non-event resources (e.g. register email template schemas)."""
        pass

    def on_disable(self) -> None:
        """Clean up resources."""
        pass

    def register_event_handlers(self, bus) -> None:
        """Subscribe to EventBus events.

        Called by PluginManager.enable_plugin() after on_enable().
        Override to subscribe to domain events forwarded by the bridge or
        to plugin-to-plugin events published via event_bus.publish().

        Args:
            bus: The EventBus singleton — call bus.subscribe(event_name, callback).
        """
        pass
```

### 4.4 Plugin Registration

Plugins are declared in two JSON files in `vbwd-backend/plugins/`:

**`plugins.json`** — which plugins to load:
```json
[
  {"name": "cms",  "module": "plugins.cms",  "enabled": true},
  {"name": "ghrm", "module": "plugins.ghrm", "enabled": true},
  {"name": "taro", "module": "plugins.taro", "enabled": true}
]
```

**`config.json`** — per-plugin configuration:
```json
{
  "ghrm": {
    "github_app_id": "",
    "github_private_key": "",
    "oauth_client_id": "",
    "oauth_client_secret": "",
    "software_category_slugs": ["backend", "fe-admin", "fe-user"]
  }
}
```

The application factory (`app.py`) reads these files, instantiates each plugin class from `plugins/<name>/__init__.py`, and calls `register → initialize → enable` for each.

**Important:** The plugin class **must be defined in `__init__.py`**, not imported from a submodule. The loader expects to find a `BasePlugin` subclass in that exact file.

### 4.5 Plugin File Structure

```
plugins/my-plugin/
├── __init__.py                    # Plugin class (MUST live here)
├── config.json                    # Default configuration values
├── src/
│   ├── models/                    # SQLAlchemy models
│   │   └── my_model.py
│   ├── repositories/              # Data access
│   │   └── my_repository.py
│   ├── services/                  # Business logic
│   │   └── my_service.py
│   └── routes.py                  # Flask blueprint
├── migrations/
│   └── versions/
│       └── YYYYMMDD_create_my_tables.py
├── bin/
│   ├── populate-db.sh             # Seed script wrapper
│   └── populate_my_plugin.py      # Idempotent seed data
└── tests/
    ├── conftest.py
    ├── unit/
    └── integration/
```

### 4.6 Dependency System

Dependencies are declared in `PluginMetadata.dependencies` as a list of plugin names. When `enable_plugin()` is called, the manager checks every dependency is already `ENABLED`. If not, the enable call raises `ValueError`.

Disable is blocked if any enabled plugin lists the target as a dependency.

```python
PluginMetadata(
    name="my-advanced-plugin",
    dependencies=["cms", "ghrm"],   # both must be enabled first
    ...
)
```

### 4.7 Route URL Prefix Patterns

There are two patterns for defining routes in a plugin blueprint:

**Pattern A — single prefix (simple plugins):**
```python
# get_url_prefix() returns "/api/v1/myplugin"
# Routes use relative paths:
@bp.route("/", methods=["GET"])      # → GET /api/v1/myplugin/
@bp.route("/<id>", methods=["GET"]) # → GET /api/v1/myplugin/<id>
```

**Pattern B — multiple prefixes (e.g., public + admin):**
```python
# get_url_prefix() returns ""
# Routes use absolute paths:
@bp.route("/api/v1/myplugin/packages", methods=["GET"])
@bp.route("/api/v1/admin/myplugin/packages", methods=["GET"])
```

Use Pattern B whenever your plugin serves both public and admin endpoints under different path prefixes.

### 4.8 Populate Scripts

Each plugin's `bin/populate_<name>.py` is an idempotent seed script — safe to re-run. It creates plans, categories, demo data, and CMS records needed by the plugin.

```bash
# Run inside container
docker compose exec api python plugins/ghrm/src/bin/populate_ghrm.py

# Or via shell script (also handles container exec):
cd vbwd-backend/plugins/ghrm && ./bin/populate-db.sh
```

**Rule:** Demo data for a plugin is populated only by that plugin's own populate script. Never add plugin data to `bin/install_demo_data.py` (which is for core data only).

### 4.9 Subscription Event Hooks

Plugins can subscribe to subscription lifecycle events to implement access control:

| Event | When fired |
|---|---|
| `subscription.activated` | Plan activated (new or trial → paid) |
| `subscription.cancelled` | User cancels |
| `subscription.expired` | Subscription period ends |
| `subscription.payment_failed` | Payment attempt fails |
| `subscription.renewed` | Successful renewal |
| `subscription.paused` | User pauses |
| `subscription.resumed` | User resumes |

Example (from GHRM plugin):
```python
def register_event_handlers(self, bus) -> None:
    """Called by PluginManager after on_enable()."""
    bus.subscribe("subscription.activated", self._grant_github_access)
    bus.subscribe("subscription.cancelled", self._start_grace_period)

def _grant_github_access(self, event_name: str, data: dict) -> None:
    user_id = data.get("user_id")
    plan_id = data.get("plan_id")
    # add GitHub collaborator via GitHub App API

def _start_grace_period(self, event_name: str, data: dict) -> None:
    user_id = data.get("user_id")
    # schedule access revocation after grace_period_days
```

Domain events (`subscription.activated`, `subscription.cancelled`, etc.) are forwarded from `DomainEventDispatcher.emit()` to the `EventBus` automatically — no core code changes are needed. The callback signature is `(event_name: str, data: dict)`, where `data` is the plain dict from the domain event's `.data` attribute.

---

## 5. Frontend Architecture

### 5.1 Three-Tier Frontend

```
vbwd-fe-core   (npm package: vbwd-view-component)
      │
      ├── vbwd-fe-user   (git submodule → vbwd-fe-core)
      └── vbwd-fe-admin  (git submodule → vbwd-fe-core)
```

The core library is built first (`npm run build`), producing a `dist/` directory. Both apps import from the local submodule path, not from npm. This means **every change to core requires a rebuild before it is reflected in the apps**.

### 5.2 Core Library (`vbwd-fe-core`)

The core library (`vbwd-view-component`) exports:

- **Plugin system** — `IPlugin`, `IPlatformSDK`, `PluginRegistry`, `PlatformSDK`
- **API client** — `ApiClient` (Axios-based, with JWT refresh and typed errors)
- **Pinia stores** — `useAuthStore`, `useCartStore`, `useSubscriptionStore`
- **Composables** — `useFeatureAccess`, `usePaymentStatus`
- **Components** — shared UI (buttons, forms, layout, access control)
- **Guards** — `RoleGuard` for Vue Router

**Exports:**
```typescript
import { useAuthStore } from 'vbwd-view-component';
import { PluginRegistry, PlatformSDK } from 'vbwd-view-component';
import type { IPlugin, IPlatformSDK } from 'vbwd-view-component';
```

### 5.3 HTTP Client

`ApiClient` wraps Axios with:
- Automatic `Authorization: Bearer <token>` injection from `localStorage`
- Silent JWT refresh on 401 (using refresh token)
- Event emission on permanent auth failure (`token-expired`) → triggers logout
- Typed error classes: `ApiError`, `NetworkError`, `ValidationError`

```typescript
import { ApiClient } from 'vbwd-view-component';

const client = new ApiClient({ baseURL: '/api/v1' });

// All methods return typed responses or throw typed errors
const user = await client.get<User>('/user/profile');
await client.post('/subscriptions', { tarif_plan_id: planId });
```

### 5.4 State Management (Pinia)

Core stores are provided by the library and shared between plugins:

**`useAuthStore`** — authentication state
```typescript
const auth = useAuthStore();
auth.isAuthenticated   // boolean
auth.user              // User | null
await auth.login({ email, password })
await auth.logout()
```

**`useSubscriptionStore`** — user subscriptions
```typescript
const subs = useSubscriptionStore();
subs.active            // Subscription[]
await subs.fetch()
```

Plugins create their **own private stores** via `sdk.createStore(id, options)` — they do not modify core stores.

### 5.5 Admin App Architecture

`vbwd-fe-admin` uses a **flat structure** — there is no runtime plugin registration. Instead, admin plugins are pre-imported modules that register their routes and nav sections at startup.

```typescript
// src/main.ts (simplified)
import { createApp } from 'vue';
import { cmsAdminPlugin } from '../plugins/cms-admin';
import { ghrmAdminPlugin } from '../plugins/ghrm-admin';

const app = createApp(App);
[cmsAdminPlugin, ghrmAdminPlugin].forEach(p => p.install(app, router));
```

Admin plugins extend the sidebar via `extensionRegistry`:
```typescript
extensionRegistry.register('cms-admin', {
  navSections: [{
    id: 'cms',
    label: 'CMS',
    items: [
      { label: 'Pages',    to: '/admin/cms/pages' },
      { label: 'Images',   to: '/admin/cms/images' },
      { label: 'Layouts',  to: '/admin/cms/layouts' },
    ],
  }],
});
```

### 5.6 User App Architecture

`vbwd-fe-user` uses the **full plugin system** from `vbwd-fe-core`. Plugins are dynamically loaded, registered, installed (routes/stores/translations added to SDK), and activated.

```
app startup
    │
    ▼
pluginLoader.ts loads each plugin module
    │
    ▼
PluginRegistry.register(plugin)       # validate name + version
    │
    ▼
PluginRegistry.installAll(sdk)        # topological order, calls plugin.install(sdk)
    │   └─ sdk.addRoute(...)          # adds to Vue Router
    │   └─ sdk.addTranslations(...)   # merges into vue-i18n
    │   └─ sdk.createStore(...)       # registers Pinia store
    │
    ▼
PluginRegistry.activate(name)         # calls plugin.activate()
    │   └─ register nav items
    │   └─ start polling, etc.
```

**pluginLoader.ts** handles both export patterns:
```typescript
// Tries default export first, then first named export with .install
const mod = await import(pluginPath);
const plugin = mod.default ?? Object.values(mod).find(v => typeof v?.install === 'function');
```

All user-app plugins use **named exports**:
```typescript
export const ghrmPlugin: IPlugin = { name: 'ghrm', version: '1.0.0', install(sdk) { ... } };
```

---

## 6. Frontend Plugin System

### 6.1 Plugin Interface

```typescript
interface IPlugin {
  name: string;                                  // Unique identifier
  version: string;                               // Semver
  description?: string;
  dependencies?: string[] | Record<string, string>;  // name or name→constraint

  install?(sdk: IPlatformSDK): void | Promise<void>;
  activate?(): void | Promise<void>;
  deactivate?(): void | Promise<void>;
  uninstall?(): void | Promise<void>;
}
```

### 6.2 Platform SDK API

The `IPlatformSDK` is passed to `plugin.install()`. It provides:

```typescript
interface IPlatformSDK {
  // Routing
  addRoute(route: IRouteConfig): void;
  getRoutes(): IRouteConfig[];

  // Components (global registration)
  addComponent(name: string, component: ComponentDefinition): void;
  removeComponent(name: string): void;
  getComponents(): Map<string, ComponentDefinition>;

  // State
  createStore(id: string, options: IStoreOptions): void;
  getStores(): Map<string, IStoreOptions>;

  // i18n
  addTranslations(locale: string, messages: Record<string, unknown>): void;
  getTranslations(): Map<string, Record<string, unknown>>;
}
```

### 6.3 Plugin Lifecycle (Frontend)

```
REGISTERED → INSTALLED → ACTIVE ⇆ INACTIVE
```

| Status | Hook | Meaning |
|---|---|---|
| `REGISTERED` | — | Added to registry, not yet installed |
| `INSTALLED` | `install(sdk)` | Routes, stores, translations registered |
| `ACTIVE` | `activate()` | Nav items shown, polling started |
| `INACTIVE` | `deactivate()` | Nav items hidden, polling stopped |

### 6.4 Dependency Resolution

The `PluginRegistry` performs a **topological sort** before calling `installAll()`. This guarantees that a plugin's dependencies are always installed before the plugin itself.

Dependencies can be declared as:
```typescript
// Array — any version accepted
dependencies: ['cms', 'auth']

// Record — with semver constraint
dependencies: { 'cms': '>=1.0.0', 'auth': '^2.0.0' }
```

Circular dependencies throw `Error: Circular dependency detected` at install time.

### 6.5 Translation Convention

Plugins namespace their translations under their plugin name:

```typescript
sdk.addTranslations('en', {
  'ghrm': {
    'title': 'Software Catalogue',
    'connectGithub': 'Connect GitHub',
  }
});

// Usage in Vue template:
// {{ $t('ghrm.title') }}
```

Translations for all locales live in `plugins/<name>/locales/<locale>.json` and are imported in `index.ts`.

### 6.6 Full Plugin Template (User App)

```typescript
// plugins/my-feature/index.ts
import type { IPlugin, IPlatformSDK } from 'vbwd-view-component';
import en from './locales/en.json';

export const myFeaturePlugin: IPlugin = {
  name: 'my-feature',
  version: '1.0.0',
  description: 'Description of my feature',
  dependencies: [],           // declare any plugin dependencies here

  install(sdk: IPlatformSDK) {
    // 1. Routes
    sdk.addRoute({
      path: '/my-feature',
      name: 'my-feature-index',
      component: () => import('./src/views/MyFeatureIndex.vue'),
      meta: { requiresAuth: false },
    });
    sdk.addRoute({
      path: '/my-feature/:id',
      name: 'my-feature-detail',
      component: () => import('./src/views/MyFeatureDetail.vue'),
      meta: { requiresAuth: true },
    });

    // 2. Global components (optional)
    sdk.addComponent('MyWidget', () => import('./src/components/MyWidget.vue'));

    // 3. Store
    sdk.createStore('myFeatureStore', {
      state: () => ({ items: [], loading: false }),
      actions: {
        async fetchItems() { /* ... */ }
      },
    });

    // 4. Translations
    sdk.addTranslations('en', en);
  },

  activate() {
    // Register nav items, start subscriptions, etc.
  },

  deactivate() {
    // Hide nav items, stop subscriptions, etc.
  },
};
```

---

## 7. Security Architecture

### 7.1 Authentication

**JWT-based** with short-lived access tokens and long-lived refresh tokens:

- Access token: 15 minutes lifetime, stored in memory (not localStorage)
- Refresh token: 30 days lifetime, stored in an `httpOnly` cookie
- On 401, the frontend silently calls `POST /api/v1/auth/refresh` to get a new access token
- Permanent failure (refresh also 401) → fires `token-expired` event → logout

```python
# Backend route guard
from src.auth import require_auth

@bp.route("/api/v1/protected", methods=["GET"])
@require_auth
def protected_endpoint():
    user = g.current_user   # injected by require_auth
    ...
```

### 7.2 Role-Based Access Control

Two roles: `USER` and `ADMIN`.

Admin routes are guarded with a separate decorator:
```python
@bp.route("/api/v1/admin/users", methods=["GET"])
@require_auth
@require_admin
def list_users():
    ...
```

Frontend route guards use `RoleGuard` from the core library:
```typescript
sdk.addRoute({
  path: '/admin',
  component: AdminLayout,
  meta: { requiresAuth: true, roles: ['ADMIN'] },
});
```

### 7.3 Input Validation

All user input is validated at the route layer before reaching services:
- Query parameters: explicit type coercion and bounds checking
- Request bodies: schema validation (marshmallow)
- UUIDs: validated with `UUID(id_str)` — raises `ValueError` on invalid format

Never pass raw request data directly to services or repositories.

### 7.4 SQL Injection Prevention

All database access uses SQLAlchemy ORM or parameterized queries. Raw SQL strings with user input are never used.

### 7.5 API Key Security

Plugin sync API keys (`GhrmSoftwarePackage.sync_api_key`) are generated with `secrets.token_urlsafe(32)`. They:
- Are never returned in list endpoints
- Are returned only in admin detail endpoints
- Can be rotated via a dedicated `POST /rotate-key` endpoint
- Are never logged

### 7.6 Rate Limiting

`Flask-Limiter` is applied to sensitive endpoints:
- Auth: 5 login attempts per minute per IP
- Password reset: 3 requests per hour per email
- Plugin sync: 10 requests per minute per API key

### 7.7 CORS

Configured in `app.py` via `Flask-CORS`. In production, only the frontend origins are whitelisted. In development, `localhost:8080` and `localhost:8081` are allowed.

### 7.8 Sensitive Data

- Password hashes use `bcrypt` with cost factor 12
- JWT secret is environment-variable-only — never hardcoded
- Payment provider API keys are stored in environment variables, not in the database
- Plugin configuration stored in DB is not encrypted (do not store secrets there — use env vars)

---

## 8. Data Patterns

### 8.1 UUID Primary Keys

Every table uses a UUID primary key generated server-side:
```python
import uuid
id = db.Column(db.UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
```

Foreign key columns use `db.UUID` (not `db.String`):
```python
user_id = db.Column(db.UUID(as_uuid=True), db.ForeignKey("user.id"), nullable=False)
```

### 8.2 Optimistic Locking

`BaseModel` includes a `version` integer column. Concurrent update conflicts are detected by checking this version, preventing lost updates on subscription and invoice records.

### 8.3 Soft vs Hard Delete

The platform currently uses **hard deletes** for most records. A `RestoreService` exists for recovering deleted users. Future versions will add soft-delete (`deleted_at`) to key entities.

### 8.4 JSON Columns

Plugin-specific configuration, feature flags, and dynamic data are stored as `db.JSON` columns. Always provide a `default` to avoid `None`:
```python
features    = db.Column(db.JSON, nullable=True, default=dict)
screenshots = db.Column(db.JSON, nullable=True, default=list)
```

### 8.5 Enum Columns

All status and type fields use Python `enum.Enum` mapped to a PostgreSQL native enum:
```python
status = db.Column(
    db.Enum(SubscriptionStatus, name="subscriptionstatus", native_enum=True),
    nullable=False,
    default=SubscriptionStatus.PENDING,
)
```

### 8.6 Subscription Categories

`TarifPlanCategory.is_single = True` means a user may have **at most one active subscription** to any plan in that category at a time. This is enforced in `SubscriptionService` at checkout time.

Use `is_single = False` for categories where users can stack multiple subscriptions (e.g., plugin add-ons).

---

## 9. Testing Strategy

### 9.1 Backend Testing

**Unit tests** (`tests/unit/`) use `MagicMock` for repositories. No database required:
```python
def test_credit_tokens():
    balance_repo = MagicMock()
    transaction_repo = MagicMock()
    purchase_repo = MagicMock()
    balance_repo.find_by_user_id.return_value = UserTokenBalance(balance=100)

    svc = TokenService(balance_repo, transaction_repo, purchase_repo)
    svc.credit_tokens(user_id, 50, TokenTransactionType.BONUS)

    assert balance_repo.save.called
```

**Integration tests** (`tests/integration/`) use a real PostgreSQL test database (name appended with `_test`):
```python
# conftest.py pattern
def _test_db_url():
    url = os.environ["DATABASE_URL"]
    return url.rsplit("/", 1)[0] + "/" + url.rsplit("/", 1)[1] + "_test"
```

Run tests:
```bash
make test                    # all tests
make test-unit               # unit only
make test-integration        # integration only
make test-coverage           # with HTML coverage report
```

### 9.2 Frontend Testing

**Unit/component tests** use Vitest + `@testing-library/vue`:
```bash
cd vbwd-fe-user && npm run test
```

**E2E tests** use Playwright against the running application:
```bash
npm run test:e2e             # headless
npm run test:e2e:ui          # with Playwright UI
E2E_BASE_URL=http://localhost:8080 npm run test:e2e
```

**Plugin E2E tests** (Playwright against the platform):
```bash
# Requires backend + fe-admin running (e.g. via vbwd-platform or docker compose)
cd vbwd-fe-admin
E2E_BASE_URL=http://localhost:8081 npx playwright test plugins/<name>/tests/e2e/ --config=playwright.platform.config.ts

# Headed mode (visible browser):
E2E_BASE_URL=http://localhost:8081 npx playwright test plugins/<name>/tests/e2e/ --config=playwright.platform.config.ts --headed

# Single file:
E2E_BASE_URL=http://localhost:8081 npx playwright test plugins/booking/tests/e2e/booking-resources-crud.spec.ts --config=playwright.platform.config.ts
```

Test credentials:
- Admin: `admin@example.com` / `AdminPass123@`
- User: `test@example.com` / `TestPass123@`

### 9.3 Coverage Targets

| Layer | Target |
|---|---|
| Backend services | 95%+ |
| Backend repositories | 90%+ |
| Frontend core library | 90%+ |
| Plugin unit tests | 80%+ |

---

## 10. Development Workflow

### 10.1 First-Time Setup

```bash
# Full setup (all repos + backend)
./recipes/dev-install-ce.sh

# Or manual:
# 1. Start backend
cd vbwd-backend
cp .env.example .env
make up-build
docker compose exec api flask db upgrade
docker compose exec api python bin/install_demo_data.py
docker compose exec api python plugins/cms/src/bin/populate_cms.py
docker compose exec api python plugins/ghrm/src/bin/populate_ghrm.py

# 2. Build core library
cd ../vbwd-fe-core
npm install && npm run build

# 3. Start user app
cd ../vbwd-fe-user
npm install && npm run dev   # http://localhost:8080

# 4. Start admin app
cd ../vbwd-fe-admin
npm install && npm run dev   # http://localhost:8081
```

### 10.2 Total Rebuild

```bash
# From repo root — rebuilds all Docker images + reseeds DB
make total-rebuild
```

### 10.3 Common Backend Commands

```bash
make up              # Start services
make down            # Stop services
make shell           # Bash into API container
make logs            # Tail all service logs
make lint            # black + flake8 + mypy
make pre-commit      # lint + unit + integration
```

### 10.4 Adding a New Backend Plugin

1. Create `plugins/my-plugin/__init__.py` with your `BasePlugin` subclass
2. Create `plugins/my-plugin/src/models/`, `repositories/`, `services/`, `routes.py`
3. Create migration in `plugins/my-plugin/migrations/versions/`
4. Create `plugins/my-plugin/bin/populate_my_plugin.py`
5. Add entry to `plugins/plugins.json` and `plugins/config.json`
6. Run migration: `docker compose exec api flask db upgrade`
7. Write unit + integration tests in `plugins/my-plugin/tests/`

### 10.5 Adding a New Frontend Plugin (User App)

1. Create `vbwd-fe-user/plugins/my-plugin/index.ts` — export `const myPlugin: IPlugin = { ... }`
2. Create `locales/en.json` with translations
3. Create `src/views/`, `src/components/`, `src/stores/` as needed
4. Register the plugin in the app's plugin loader configuration
5. Write E2E tests in `vue/tests/e2e/`

### 10.6 Environment Variables

```ini
# vbwd-backend/.env
DATABASE_URL=postgresql://vbwd:vbwd@postgres/vbwd
REDIS_URL=redis://redis:6379/0
JWT_SECRET_KEY=your-secret-key-here
FLASK_ENV=development

# Payment providers (only set the ones you use)
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
PAYPAL_CLIENT_ID=...
PAYPAL_CLIENT_SECRET=...

# Email
MAIL_SERVER=smtp.example.com
MAIL_USERNAME=...
MAIL_PASSWORD=...
```
