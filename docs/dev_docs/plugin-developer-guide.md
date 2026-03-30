# Plugin Developer Guide

How to create a new plugin for the vbwd platform. Covers backend (Python/Flask) and frontend (Vue.js) plugins.

## Principles

1. **Core is agnostic, plugins are gnostic.** Never modify core files (`vbwd/`, `vue/src/`) for plugin functionality.
2. All plugin code goes in `plugins/<name>/`.
3. Plugins communicate with core and each other via the event bus, line item registry, and extension registry.

---

## Backend Plugin

### Directory Structure

New plugins use the plugin ID as the source directory name (not `src/`):

```
plugins/<name>/
├── __init__.py               # Plugin class (MUST be defined here)
├── config.json               # Default configuration (optional)
├── populate_db.py            # Demo data, idempotent (optional)
├── <name>/                   # Source code directory
│   ├── __init__.py
│   ├── models/               # SQLAlchemy models
│   │   └── __init__.py
│   ├── repositories/         # Data access layer
│   │   └── __init__.py
│   ├── services/             # Business logic
│   │   └── __init__.py
│   ├── handlers/             # Line item handlers, event handlers
│   │   └── __init__.py
│   └── routes.py             # Flask Blueprint
└── tests/
    ├── conftest.py           # Test fixtures (DB, app factory)
    ├── unit/
    │   └── __init__.py
    └── integration/
        └── __init__.py
```

### Plugin Class

Every plugin must define a class inheriting `BasePlugin` in `__init__.py`:

```python
"""My Plugin -- short description."""
from vbwd.plugins.base import BasePlugin, PluginMetadata


DEFAULT_CONFIG = {
    "setting_one": "value",
    "setting_two": 42,
}


class MyPlugin(BasePlugin):
    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="my-plugin",
            version="1.0.0",
            author="VBWD",
            description="Short description of the plugin",
            dependencies=[],  # Other plugin names this depends on
        )

    def initialize(self, config=None):
        merged = {**DEFAULT_CONFIG}
        if config:
            merged.update(config)
        super().initialize(merged)

    def get_blueprint(self):
        from plugins.my_plugin.my_plugin.routes import my_bp
        return my_bp

    def get_url_prefix(self) -> str:
        # Single prefix: return "/api/v1/my-plugin"
        # Multiple prefixes (public + admin): return ""
        return ""

    def on_enable(self):
        pass

    def on_disable(self):
        pass
```

### Route Patterns

Create a Flask Blueprint in `<name>/routes.py`:

```python
from flask import Blueprint, jsonify, request, g
from vbwd.extensions import db
from vbwd.middleware.auth import require_auth, require_admin

my_bp = Blueprint("my_plugin", __name__)

# Public route
@my_bp.route("/api/v1/my-plugin/items", methods=["GET"])
def list_items():
    return jsonify({"items": []}), 200

# Authenticated route
@my_bp.route("/api/v1/my-plugin/items", methods=["POST"])
@require_auth
def create_item():
    data = request.get_json() or {}
    # ... create item ...
    return jsonify({"item": {}}), 201

# Admin route
@my_bp.route("/api/v1/admin/my-plugin/items", methods=["GET"])
@require_auth
@require_admin
def admin_list_items():
    return jsonify({"items": []}), 200
```

**Convention:** When a plugin has both public and admin routes, `get_url_prefix()` returns `""` and routes use absolute paths.

### Models

Inherit from `BaseModel` which provides UUID primary key, `created_at`, `updated_at`, `version`:

```python
from vbwd.models.base import BaseModel
from vbwd.extensions import db


class MyItem(BaseModel):
    __tablename__ = "my_item"

    name = db.Column(db.String(255), nullable=False)
    slug = db.Column(db.String(255), unique=True, nullable=False)
    user_id = db.Column(db.UUID, nullable=False, index=True)
    is_active = db.Column(db.Boolean, default=True)
    metadata_json = db.Column(db.JSON, default=dict)

    def to_dict(self):
        return {
            "id": str(self.id),
            "name": self.name,
            "slug": self.slug,
            "user_id": str(self.user_id),
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
```

### Repositories

Repositories encapsulate all database queries:

```python
class MyItemRepository:
    def __init__(self, session):
        self._session = session

    def find_by_id(self, item_id):
        return self._session.query(MyItem).get(item_id)

    def find_by_slug(self, slug):
        return self._session.query(MyItem).filter_by(slug=slug).first()

    def save(self, item):
        self._session.add(item)
        self._session.commit()
        return item

    def delete(self, item):
        self._session.delete(item)
        self._session.commit()
```

### Services

Services hold business logic and depend on repositories (injected via constructor):

```python
class MyItemService:
    def __init__(self, repository, event_bus=None):
        self._repo = repository
        self._event_bus = event_bus

    def create_item(self, name, user_id):
        # Business logic here
        item = MyItem(name=name, user_id=user_id, slug=slugify(name))
        self._repo.save(item)

        if self._event_bus:
            self._event_bus.publish("my_plugin.item_created", {
                "item_id": str(item.id),
            })

        return item
```

### Database Migrations

Always use Alembic. Never modify the database with raw SQL.

```bash
# Create a migration
docker compose exec api flask db migrate -m "create_my_item_table"

# Run migrations
docker compose exec api flask db upgrade
```

Place migration files in `alembic/versions/` with a descriptive name like `20260329_create_my_item_table.py`.

### Event Bus

Subscribe to events in `register_event_handlers()`:

```python
def register_event_handlers(self, event_bus):
    event_bus.subscribe("order.created", self._on_order_created)
    event_bus.subscribe("subscription.activated", self._on_subscription_activated)

def _on_order_created(self, event_name, data):
    order_id = data["order_id"]
    # React to the event
```

Publish events from services:

```python
event_bus.publish("my_plugin.something_happened", {
    "item_id": str(item.id),
    "user_id": str(user_id),
})
```

**Event naming convention:** `plugin_name.action_past_tense` (e.g., `stock.blocked`, `order.created`).

### Line Item Handlers

If your plugin sells something via invoices, implement `ILineItemHandler`:

```python
from vbwd.events.line_item_registry import ILineItemHandler, LineItemContext, LineItemResult
from vbwd.models.enums import LineItemType


class MyLineItemHandler(ILineItemHandler):
    def can_handle_line_item(self, line_item, context):
        return (
            line_item.item_type == LineItemType.CUSTOM
            and (line_item.extra_data or {}).get("plugin") == "my-plugin"
        )

    def activate_line_item(self, line_item, context):
        # Payment captured -- deliver the product/service
        return LineItemResult(success=True, data={"delivered": True})

    def reverse_line_item(self, line_item, context):
        # Refund -- revoke access / cancel order
        return LineItemResult(success=True, data={})

    def restore_line_item(self, line_item, context):
        # Refund reversed -- re-grant access
        return LineItemResult(success=True, data={})
```

Register in the plugin class:

```python
def register_line_item_handlers(self, registry):
    from plugins.my_plugin.my_plugin.handlers.line_item_handler import MyLineItemHandler
    handler = MyLineItemHandler(session_factory=db.session, event_bus=event_bus)
    registry.register(handler)
```

### Shipping Providers

If your plugin provides shipping, implement `IShippingProvider`:

```python
def register_shipping_providers(self, registry):
    from plugins.my_plugin.my_plugin.provider import MyShippingProvider
    provider = MyShippingProvider(self._config)
    registry.append(provider)
```

See the [ecommerce developer guide](ecommerce-developer-guide.md#creating-a-shipping-plugin) for the full `IShippingProvider` interface.

### Registration

#### plugins.json

Add an entry in `plugins/plugins.json`:

```json
{
  "my-plugin": {
    "enabled": true,
    "version": "1.0.0",
    "installedAt": "",
    "source": "local"
  }
}
```

#### config.json

Add default config in `plugins/config.json` (if the plugin has configuration):

```json
{
  "my-plugin": {
    "setting_one": "value",
    "setting_two": 42
  }
}
```

#### .gitignore

If the plugin generates files (uploads, caches), add entries to `.gitignore`.

### Testing

#### Unit Tests

Unit tests use `MagicMock()` for repositories -- no database needed:

```python
from unittest.mock import MagicMock

def test_create_item():
    repo = MagicMock()
    service = MyItemService(repository=repo)

    item = service.create_item("Test Item", user_id=uuid4())

    repo.save.assert_called_once()
    assert item.name == "Test Item"
```

#### Integration Tests

Integration tests use a real PostgreSQL test database:

```python
# tests/conftest.py
import pytest

def _test_db_url():
    """Append _test to the database name."""
    base = os.environ.get("DATABASE_URL", "postgresql://vbwd:vbwd@localhost:5432/vbwd")
    return base.rsplit("/", 1)[0] + "/" + base.rsplit("/", 1)[1] + "_test"
```

#### Running Tests

```bash
# Unit tests
docker compose run --rm test pytest plugins/my_plugin/tests/unit/ -v

# Integration tests
docker compose run --rm test pytest plugins/my_plugin/tests/integration/ -v

# With coverage
docker compose run --rm test pytest plugins/my_plugin/tests/ --cov=plugins.my_plugin -v
```

---

## Frontend Plugin -- fe-admin

### Directory Structure

```
plugins/<name>/
├── index.ts                  # Plugin entry (IPlugin)
├── config.json               # Default config values
├── admin-config.json         # Admin settings panel schema
├── locales/
│   ├── en.json               # English (required)
│   ├── de.json               # German
│   ├── fr.json               # French
│   ├── es.json               # Spanish
│   ├── it.json               # Italian
│   ├── pt.json               # Portuguese
│   ├── ru.json               # Russian
│   └── zh.json               # Chinese
├── src/
│   ├── views/                # Page components
│   ├── stores/               # Pinia stores
│   └── components/           # Reusable components
└── tests/
    └── unit/
```

### Plugin Entry (index.ts)

```typescript
import type { IPlugin, IPlatformSDK } from 'vbwd-view-component';
import { extensionRegistry } from '../../vue/src/plugins/extensionRegistry';

export const myAdminPlugin: IPlugin = {
  name: 'my-admin',
  version: '1.0.0',
  description: 'Admin UI for my plugin',

  install(sdk: IPlatformSDK) {
    // Register routes (paths are relative to /admin/)
    sdk.addRoute({
      path: 'my-plugin/items',
      name: 'my-items',
      component: () => import('./src/views/Items.vue'),
    });

    // Register dashboard widget
    sdk.addComponent(
      'MyWidget',
      () => import('./src/components/MyWidget.vue') as Promise<{ default: unknown }>
    );
  },

  activate() {
    extensionRegistry.register('my-admin', {
      // Option A: Add items to an existing core section
      sectionItems: {
        sales: [
          {
            label: 'My Plugin',
            to: '/admin/my-plugin/items',
            id: 'my-plugin',
            position: 'after:invoices',  // or 'before:users', 'start', 'end'
            children: [
              { label: 'Items', to: '/admin/my-plugin/items' },
              { label: 'Settings', to: '/admin/my-plugin/settings' },
            ],
          },
        ],
      },

      // Option B: Add a standalone sidebar section
      navSections: [
        {
          id: 'my-section',
          label: 'My Section',
          items: [
            { label: 'Dashboard', to: '/admin/my-plugin/dashboard' },
          ],
        },
      ],

      // Option C: Hide core nav items
      hiddenItems: ['/admin/some-core-page'],
    });
  },

  deactivate() {
    extensionRegistry.unregister('my-admin');
  },
};
```

### Sidebar Navigation Options

The `extensionRegistry` supports:

| Property | Description |
|----------|-------------|
| `navSections` | Standalone sidebar sections (appended after core sections) |
| `sectionItems` | Inject items into existing core sections (e.g., `sales`, `settings`) |
| `hiddenItems` | Array of route paths to hide from the sidebar |
| `sectionComponents` | Inject Vue components into section slots |
| `planTabSections` | Add tabs to the plan edit page |
| `userDetailsSections` | Add sections to the user detail page |

**Position control** for `sectionItems`:
- `'start'` -- insert at beginning of section
- `'end'` -- insert at end (default)
- `'before:targetId'` -- insert before the item with `id: 'targetId'`
- `'after:targetId'` -- insert after the item with `id: 'targetId'`

### Dashboard Widgets

Register via `sdk.addComponent()`:

```typescript
sdk.addComponent(
  'MyWidget',
  () => import('./src/components/MyWidget.vue') as Promise<{ default: unknown }>
);
```

The dashboard page renders all registered widget components.

---

## Frontend Plugin -- fe-user

### Directory Structure

```
plugins/<name>/
├── index.ts                  # Plugin entry (named export)
├── config.json               # Default config values
├── admin-config.json         # Admin settings panel schema
├── <name>/                   # Source code directory
│   ├── views/
│   ├── stores/
│   └── components/
└── tests/
    └── unit/
```

### Plugin Entry (index.ts)

All fe-user plugins use **named exports** (not default exports):

```typescript
import type { IPlugin, IPlatformSDK } from 'vbwd-view-component';

export const myPlugin: IPlugin = {
  name: 'my-plugin',
  version: '1.0.0',
  description: 'User-facing features for my plugin',

  install(sdk: IPlatformSDK) {
    // Routes use absolute paths with meta.requiresAuth
    sdk.addRoute({
      path: '/my-plugin',
      name: 'my-page',
      component: () => import('./my_plugin/views/MyPage.vue'),
      meta: { requiresAuth: false },
    });

    sdk.addRoute({
      path: '/my-plugin/dashboard',
      name: 'my-dashboard',
      component: () => import('./my_plugin/views/Dashboard.vue'),
      meta: { requiresAuth: true },
    });

    // Translations
    sdk.addTranslations('en', {
      myPlugin: {
        title: 'My Plugin',
      },
    });
  },

  activate() {
    // fe-user does not use extensionRegistry
    // Navigation is handled by the layout
  },

  deactivate() {
    // Cleanup if needed
  },
};
```

### Plugin Lifecycle

```
install(sdk) ──► Routes, stores, translations registered
    │
    ▼
activate()   ──► Extension registry populated, event listeners attached
    │
    ▼
deactivate() ──► Extension registry cleaned up
```

---

## Configuration Files

### config.json

Default values for the plugin. These are loaded at startup and can be overridden in the admin settings panel.

```json
{
  "items_per_page": 20,
  "feature_enabled": true
}
```

### admin-config.json

Defines the admin settings panel UI. Each tab contains fields:

```json
{
  "tabs": [
    {
      "id": "general",
      "label": "General",
      "fields": [
        {
          "key": "items_per_page",
          "label": "Items Per Page",
          "component": "input",
          "inputType": "number",
          "min": 5,
          "max": 100
        },
        {
          "key": "feature_enabled",
          "label": "Enable Feature",
          "component": "checkbox"
        },
        {
          "key": "display_mode",
          "label": "Display Mode",
          "component": "select",
          "options": [
            { "value": "grid", "label": "Grid" },
            { "value": "list", "label": "List" }
          ]
        }
      ]
    }
  ]
}
```

**Available field components:** `input`, `checkbox`, `select`, `textarea`.

---

## Internationalization (i18n)

All user-facing text must be translated. The platform requires **8 languages**:

| File | Language |
|------|----------|
| `en.json` | English (required, fallback) |
| `de.json` | German |
| `fr.json` | French |
| `es.json` | Spanish |
| `it.json` | Italian |
| `pt.json` | Portuguese |
| `ru.json` | Russian |
| `zh.json` | Chinese |

Place locale files in `locales/` and register them in `install()`:

```typescript
sdk.addTranslations('en', { myPlugin: { title: 'My Plugin' } });
sdk.addTranslations('de', { myPlugin: { title: 'Mein Plugin' } });
```

---

## Pre-commit and CI

### pre-commit-check.sh

The CI pipeline runs `pre-commit-check.sh` which:
1. Lints (black, flake8, mypy for backend; ESLint for frontend)
2. Runs unit tests
3. Runs integration tests

**Key lessons:**
- Always `bash -n` after editing shell scripts
- Use `plugins/<name>/` filter for Vitest, not deep paths
- Always `npm run lint` (full project), never scoped `npx eslint plugins/<name>/`
- Plugin CI must install ALL plugins (vue-tsc needs full project context)
- Never delete `package-lock.json` on CI

### Running checks locally

```bash
# Backend
cd vbwd-backend
make pre-commit        # Full check (lint + unit + integration)
make pre-commit-quick  # Quick check (lint + unit)

# Frontend
cd vbwd-fe-admin   # or vbwd-fe-user
npm run lint
npm run test
```

---

## Checklist: New Plugin

### Backend

- [ ] Create `plugins/<name>/__init__.py` with plugin class
- [ ] Create `plugins/<name>/<name>/` source directory
- [ ] Add models in `<name>/models/`
- [ ] Add repositories in `<name>/repositories/`
- [ ] Add services in `<name>/services/`
- [ ] Add routes in `<name>/routes.py`
- [ ] Add Alembic migration in `alembic/versions/`
- [ ] Register in `plugins/plugins.json`
- [ ] Add config to `plugins/config.json` (if needed)
- [ ] Write unit tests in `tests/unit/`
- [ ] Write integration tests in `tests/integration/`
- [ ] Add `populate_db.py` for demo data (idempotent)

### Frontend (fe-admin)

- [ ] Create `plugins/<name>/index.ts` with IPlugin
- [ ] Add views in `src/views/`
- [ ] Add stores in `src/stores/`
- [ ] Add `config.json` with defaults
- [ ] Add `admin-config.json` with settings panel schema
- [ ] Add locale files (8 languages)
- [ ] Register sidebar nav via extensionRegistry
- [ ] Add dashboard widget if applicable
- [ ] Write unit tests

### Frontend (fe-user)

- [ ] Create `plugins/<name>/index.ts` with **named export**
- [ ] Add views in `<name>/views/`
- [ ] Add stores in `<name>/stores/`
- [ ] Add `config.json` with defaults
- [ ] Add `admin-config.json` with settings panel schema
- [ ] Add locale files (8 languages)
- [ ] Set `meta.requiresAuth` on routes
- [ ] Write unit tests
