# Architecture Guidelines for vbwd-sdk

**Date**: February 16, 2026
**Priority**: CRITICAL - All developers must follow these principles

---

## Core Principle: Complete Separation of Concerns

### Rule #1: Core ≠ Plugins
- **Core** (backend `/src/` + frontend `/core/src/`) = **Completely agnostic**
- **Plugins** = **Self-contained applications**
- **Zero coupling** between core and plugins
- Plugins can be added, removed, or updated without touching core

### Rule #2: Both Backend AND Frontend Follow Same Pattern
This is NOT just a backend rule. The plugin architecture applies identically to:
- Backend: `/vbwd-backend/plugins/`
- Frontend User App: `/vbwd-frontend/user/plugins/`
- Frontend Admin App: `/vbwd-frontend/admin/plugins/`

---

## Mandatory Plugin Structure

**Every plugin** (backend and frontend) must include:

```
plugins/{plugin-name}/
├── src/                       ← Source code (primary)
├── assets/                    ← Static files (optional, recommended)
├── tests/                     ← Tests (mandatory)
├── locales/                   ← Translations (mandatory if UI)
├── alembic/                   ← Migrations (backend only, if needed)
├── config.json                ← Plugin settings (mandatory)
└── admin-config.json          ← Admin UI config (backend, optional)
```

### Detailed Structure

#### Backend Plugin: `/vbwd-backend/plugins/{name}/`

```
src/
├── routes.py                  ← API endpoints (plugin-specific)
├── services/                  ← Business logic
│   ├── __init__.py
│   └── {feature}_service.py   ← NO generic services
├── repositories/              ← Data access layer
│   └── {entity}_repository.py
├── models/                    ← Domain models
│   ├── __init__.py
│   └── {entity}.py
├── events.py                  ← Domain events
└── bin/                       ← Scripts & utilities
    ├── __init__.py
    ├── populate_data.py
    └── migrate_data.py

assets/
├── images/
└── (any static files)

tests/
├── unit/
│   └── services/
│   └── repositories/
└── integration/

alembic/
├── env.py
├── script.py.mako
└── versions/

locales/
├── en.json
├── de.json
└── (other languages)

config.json                    ← Plugin settings
admin-config.json              ← Admin UI fields
```

#### Frontend Plugin: `/vbwd-frontend/{user|admin}/plugins/{name}/`

```
src/
├── components/                ← Vue components
│   ├── Main.vue
│   └── (feature components)
├── stores/                    ← Pinia stores
│   └── {feature}.ts
├── services/                  ← Business logic
│   └── {feature}_service.ts
├── utils/                     ← Utilities
│   └── helpers.ts
├── routes.ts                  ← Route definitions
├── index.ts                   ← Plugin entry point
└── types.ts                   ← TypeScript types

assets/
├── images/
└── (SVGs, icons, etc.)

tests/
├── unit/
└── e2e/

locales/
├── en.json
├── de.json
└── (other languages)

config.json                    ← Plugin settings
admin-config.json              ← Admin UI configuration
```

---

## Anti-Patterns (DO NOT DO)

### ❌ Wrong: Plugin-specific code in core

```bash
# WRONG ❌
/src/services/taro_service.py
/src/models/arcana.py
/core/src/stores/taro.ts
```

### ❌ Wrong: Generic code in plugin

```bash
# WRONG ❌
/plugins/taro/src/services/payment_service.py
/plugins/taro/src/utils/auth_helper.ts
```

### ❌ Wrong: Incomplete plugin structure

```bash
# WRONG ❌
/plugins/taro/
├── src/
└── tests/
# Missing: locales/, config.json, admin-config.json
```

### ❌ Wrong: Importing from other plugins

```python
# WRONG ❌
from plugins.chat.src.services import ChatService
```

---

## Correct Patterns

### ✅ Right: Plugin-specific services in plugin

```bash
# CORRECT ✅
/plugins/taro/src/services/arcana_interpretation_service.py
/plugins/taro/src/models/arcana.py
/plugins/taro/src/stores/taro.ts
```

### ✅ Right: Generic utilities in core

```bash
# CORRECT ✅
/src/services/auth_service.py          (core - used by all plugins)
/src/models/user.py                    (core - shared)
/core/src/stores/auth.ts               (core - shared)
/core/src/utils/http_client.ts         (core - shared)
```

### ✅ Right: Complete plugin structure

```bash
# CORRECT ✅
/plugins/taro/
├── src/
├── assets/
├── tests/
├── locales/
├── alembic/
├── config.json
└── admin-config.json
```

### ✅ Right: Inter-plugin communication via API

```typescript
// CORRECT ✅
// Plugin A calls Plugin B via HTTP API
const response = await fetch('/api/v1/plugin-b/endpoint')
```

---

## Key Rules

### Rule: Database Migrations
- **Backend only**: Each plugin can have `/alembic/` migrations
- Migrations are plugin-scoped
- Core migrations live in `/alembic/` at project root

### Rule: Localization
- **Both backend and frontend**: Each plugin has `/locales/{lang}.json`
- Core shares translations in `/locales/`
- Plugin locales are independent

### Rule: Configuration
- **Both**: `config.json` for plugin settings
- **Backend only**: `admin-config.json` for admin panel
- Config files are plugin-local, not shared

### Rule: Service/Repository Design
- **Backend**: Services use dependency injection
  ```python
  class TaroSessionService:
      def __init__(self, repo: TaroSessionRepository):
          self.repo = repo  # Injected dependency
  ```
- **Frontend**: Services are instance-based or factory functions
  ```typescript
  class TaroService {
      constructor(private http: HttpClient) {}
  }
  ```

### Rule: LLM Integration (and all external APIs)
- **Always in plugin**, never in core
- Each plugin configures its own API clients
- Core provides only HTTP client infrastructure

### Rule: Testing
- **Unit tests**: For services, repositories, utils
- **Integration tests**: For routes, full flows
- Backend: Tests in `/tests/unit/` and `/tests/integration/`
- Frontend: Tests in `/tests/unit/` and `/tests/e2e/`

---

## Implementation Checklist for New Plugins

- [ ] Create `/plugins/{name}/` directory
- [ ] Create all required subdirectories (src, assets, tests, locales)
- [ ] Create `config.json` with plugin metadata
- [ ] Create `admin-config.json` if backend plugin
- [ ] Create translation files (at least en.json)
- [ ] Create test files (even if empty initially)
- [ ] Create backend `/alembic/` if database tables needed
- [ ] Add plugin to registry (core plugin system)
- [ ] Update documentation with plugin details
- [ ] No imports from other plugins
- [ ] No plugin-specific code in core directories
- [ ] All business logic in plugin `/src/`

---

## Common Questions

### Q: Can a plugin import from core?
**A**: ✅ YES, always. Plugins should use core utilities, models, services.

### Q: Can core import from a plugin?
**A**: ❌ NO, never. Core must be plugin-agnostic.

### Q: Can Plugin A import from Plugin B?
**A**: ❌ NO, never. Communicate via API calls instead.

### Q: Where do shared utilities go?
**A**: In core (`/src/utils/` for backend, `/core/src/utils/` for frontend).

### Q: Where does plugin-specific business logic go?
**A**: In plugin (`/plugins/{name}/src/services/`).

### Q: Can a plugin override core routes?
**A**: ❌ NO. Plugins add NEW routes at `/api/v1/{plugin-name}/`.

### Q: Where do LLM calls go?
**A**: In plugin service (`/plugins/{name}/src/services/{feature}_service.py`).

### Q: Can multiple plugins share a database table?
**A**: ❌ NO. Each plugin manages its own tables. Share data via API.

---

## Migration Examples

### Example: Moving plugin-specific code to correct location

**Before (WRONG)**:
```
/src/services/taro_session_service.py  ❌
/src/models/arcana.py                  ❌
/core/src/stores/taro.ts               ❌
```

**After (CORRECT)**:
```
/plugins/taro/src/services/taro_session_service.py  ✅
/plugins/taro/src/models/arcana.py                  ✅
/plugins/taro/src/stores/taro.ts                    ✅
```

### Example: Identifying core vs plugin code

**Core (agnostic)**:
- Authentication service
- Token/payment system
- User management
- HTTP client
- Base models (User, Invoice, etc.)

**Plugin (specific)**:
- Taro: Card data, interpretation, session logic
- Chat: Message models, conversation service, LLM integration
- Analytics: Analytics events, reporting logic

---

## Enforcement

These rules are **non-negotiable**:
1. **Code reviews** must verify structure compliance
2. **CI/CD pipeline** should validate structure
3. **New contributors** must read these guidelines
4. **Architecture decisions** require team consensus

---

**Last Updated**: February 16, 2026
**Approved By**: Architecture Review
**Status**: Active - In Effect
