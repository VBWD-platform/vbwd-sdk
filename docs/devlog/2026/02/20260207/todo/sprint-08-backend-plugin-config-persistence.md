# Sprint 08 — Backend Plugin Config Persistence (DB)

**Priority:** MEDIUM
**Goal:** Plugin enabled/disabled state and configuration survive app restarts. Store in PostgreSQL via `plugin_config` table. `PluginManager` loads state on startup and saves on enable/disable.

**Principles:** TDD-first, SOLID, DRY, Liskov Substitution, DI, Clean Code, No Overengineering

---

## Overview

Current state:
- Plugin state is in-memory only (`PluginManager._plugins` dict)
- All plugins are hard-coded in `app.py` with explicit `register → initialize → enable` calls
- Restarting the app resets all plugin state

After this sprint:
- `plugin_config` table stores plugin name, enabled status, and JSON config
- `PluginConfigRepository` provides CRUD access
- `PluginManager` reads DB state on startup to restore previously-enabled plugins
- `PluginManager` writes DB state on `enable_plugin()` / `disable_plugin()`
- CLI `flask plugins enable/disable` persists state automatically

Architecture doc reference: `docs/architecture_core_server_ce/plugin-system.md` lines 1039-1053

---

## Phase 1: Database Model + Migration

### 1.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/plugins/test_plugin_config_model.py`

```
Tests to write FIRST:

test_plugin_config_model_has_required_columns
  - PluginConfig has: id, plugin_name, status, config, enabled_at, disabled_at, created_at, updated_at

test_plugin_config_default_status_is_disabled
  - PluginConfig(plugin_name="test") → status == "disabled"

test_plugin_config_stores_json_config
  - PluginConfig(plugin_name="test", config={"key": "value"})
  - config["key"] == "value"

test_plugin_config_name_is_unique
  - Two PluginConfigs with same name → IntegrityError
```

### 1.2 Implementation (GREEN)

**File:** `vbwd-backend/src/models/plugin_config.py`

```python
from src.extensions import db
from sqlalchemy.dialects.postgresql import JSONB
import uuid
from datetime import datetime

class PluginConfig(db.Model):
    __tablename__ = "plugin_config"

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    plugin_name = db.Column(db.String(100), unique=True, nullable=False)
    status = db.Column(db.String(20), nullable=False, default="disabled")
    config = db.Column(JSONB, default=dict)
    enabled_at = db.Column(db.DateTime, nullable=True)
    disabled_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
```

Key decisions:
- **SRP:** Model only holds data, no business logic
- **No overengineering:** No `version` column (plugin code already has version), no `priority` column, no `error_log`. Only what's needed to persist enable/disable state + config.

**Migration:**
```bash
docker-compose exec api flask db migrate -m "add plugin_config table"
docker-compose exec api flask db upgrade
```

---

## Phase 2: Repository

### 2.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/plugins/test_plugin_config_repository.py`

```
Tests to write FIRST:

test_get_by_name_returns_config
  - Save PluginConfig(plugin_name="analytics")
  - repo.get_by_name("analytics") returns it

test_get_by_name_returns_none_for_missing
  - repo.get_by_name("nonexistent") returns None

test_get_all_returns_all_configs
  - Save 2 configs
  - repo.get_all() returns both

test_get_enabled_returns_only_enabled
  - Save 2 configs (one enabled, one disabled)
  - repo.get_enabled() returns only enabled

test_save_creates_new_config
  - repo.save("analytics", "enabled", {"key": "val"})
  - DB has 1 row with correct data

test_save_updates_existing_config
  - repo.save("analytics", "disabled", {})
  - repo.save("analytics", "enabled", {"updated": True})
  - DB still has 1 row, config is updated

test_save_enabled_sets_enabled_at
  - repo.save("analytics", "enabled", {})
  - config.enabled_at is not None

test_save_disabled_sets_disabled_at
  - repo.save("analytics", "disabled", {})
  - config.disabled_at is not None

test_delete_removes_config
  - repo.save("analytics", "enabled", {})
  - repo.delete("analytics")
  - repo.get_by_name("analytics") returns None
```

### 2.2 Implementation (GREEN)

**File:** `vbwd-backend/src/repositories/plugin_config_repository.py`

```python
class PluginConfigRepository:
    def __init__(self, session):
        self._session = session

    def get_by_name(self, name: str) -> Optional[PluginConfig]:
        return self._session.query(PluginConfig).filter_by(plugin_name=name).first()

    def get_all(self) -> List[PluginConfig]:
        return self._session.query(PluginConfig).all()

    def get_enabled(self) -> List[PluginConfig]:
        return self._session.query(PluginConfig).filter_by(status="enabled").all()

    def save(self, name: str, status: str, config: dict) -> PluginConfig:
        existing = self.get_by_name(name)
        if existing:
            existing.status = status
            existing.config = config
            existing.updated_at = datetime.utcnow()
            if status == "enabled":
                existing.enabled_at = datetime.utcnow()
            elif status == "disabled":
                existing.disabled_at = datetime.utcnow()
        else:
            existing = PluginConfig(plugin_name=name, status=status, config=config)
            if status == "enabled":
                existing.enabled_at = datetime.utcnow()
            self._session.add(existing)
        self._session.flush()
        return existing

    def delete(self, name: str) -> None:
        config = self.get_by_name(name)
        if config:
            self._session.delete(config)
            self._session.flush()
```

Key decisions:
- **DI:** Session injected via constructor (same pattern as all other repositories)
- **SRP:** Repository only does CRUD, no business logic
- **DRY:** `save()` handles both create and update (upsert pattern)

---

## Phase 3: PluginManager Persistence Integration

### 3.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/plugins/test_plugin_manager_persistence.py`

```
Tests to write FIRST:

test_enable_plugin_persists_to_db
  - Create manager with mock repo
  - register + initialize + enable "analytics"
  - repo.save was called with ("analytics", "enabled", {})

test_disable_plugin_persists_to_db
  - enable then disable "analytics"
  - repo.save was called with ("analytics", "disabled", {})

test_load_enabled_plugins_from_db
  - Mock repo.get_enabled() returns [PluginConfig(plugin_name="analytics", status="enabled", config={})]
  - manager.load_persisted_state()
  - Plugin "analytics" is ENABLED

test_load_skips_unknown_plugins
  - DB has config for "nonexistent-plugin"
  - manager.load_persisted_state() does not crash
  - Only registered plugins are affected

test_manager_works_without_repo
  - Create manager with repo=None (backwards compatible)
  - register + initialize + enable works (in-memory only)
  - No errors thrown
```

### 3.2 Implementation (GREEN)

**File:** `vbwd-backend/src/plugins/manager.py` — extend constructor + methods

```python
class PluginManager:
    def __init__(self, event_dispatcher=None, config_repo=None):
        self._plugins: Dict[str, BasePlugin] = {}
        self._event_dispatcher = event_dispatcher or EventDispatcher()
        self._config_repo = config_repo  # Optional — None means in-memory only

    def enable_plugin(self, name: str) -> None:
        # ... existing logic ...
        plugin.enable()
        event = Event(name="plugin.enabled", data={"plugin_name": name})
        self._event_dispatcher.dispatch(event)
        # Persist if repo available
        if self._config_repo:
            self._config_repo.save(name, "enabled", plugin._config)

    def disable_plugin(self, name: str) -> None:
        # ... existing logic ...
        plugin.disable()
        event = Event(name="plugin.disabled", data={"plugin_name": name})
        self._event_dispatcher.dispatch(event)
        # Persist if repo available
        if self._config_repo:
            self._config_repo.save(name, "disabled", plugin._config)

    def load_persisted_state(self) -> None:
        """Load and restore plugin states from DB. Call after all plugins are registered."""
        if not self._config_repo:
            return
        for config in self._config_repo.get_enabled():
            plugin = self.get_plugin(config.plugin_name)
            if plugin and plugin.status == PluginStatus.INITIALIZED:
                try:
                    if config.config:
                        plugin._config.update(config.config)
                    plugin.enable()
                except Exception as e:
                    logger.warning(f"Failed to restore plugin '{config.plugin_name}': {e}")
```

Key decisions:
- **Liskov:** `config_repo=None` preserves backwards compatibility — all existing tests pass unchanged
- **SRP:** Manager delegates persistence to repo, doesn't know about SQL/sessions
- **No overengineering:** No retry logic, no config versioning, no migration of old configs

---

## Phase 4: Wire in app.py

### 4.1 Implementation

**File:** `vbwd-backend/src/app.py` — pass repo to PluginManager

```python
# After container setup, before plugin registration:
from src.repositories.plugin_config_repository import PluginConfigRepository

with app.app_context():
    config_repo = PluginConfigRepository(db.session)
    plugin_manager = PluginManager(config_repo=config_repo)
    app.plugin_manager = plugin_manager

    # Register all known plugins
    analytics_plugin = AnalyticsPlugin()
    plugin_manager.register_plugin(analytics_plugin)
    plugin_manager.initialize_plugin("analytics")

    # Restore previously-enabled plugins from DB
    plugin_manager.load_persisted_state()

    # If no persisted state, enable defaults
    if not plugin_manager.get_enabled_plugins():
        plugin_manager.enable_plugin("analytics")
```

Key decisions:
- **First run:** If DB is empty, analytics plugin is enabled by default
- **Subsequent runs:** DB state is restored — manually disabled plugins stay disabled
- **DI:** Repository injected into manager via constructor

---

## Phase 5: Verification

### 5.1 Run All Tests

```bash
# Run migration
cd vbwd-backend && docker-compose exec api flask db upgrade

# Backend unit tests
cd vbwd-backend && make test-unit

# Backend integration tests
cd vbwd-backend && make test-integration
```

### 5.2 Persistence Test (manual)

```bash
cd vbwd-backend && make shell
flask plugins list           # analytics (1.0.0) — ENABLED
flask plugins disable analytics
flask plugins list           # analytics (1.0.0) — DISABLED
# Restart container
exit
make down && make up
make shell
flask plugins list           # analytics (1.0.0) — DISABLED (persisted!)
flask plugins enable analytics
```

---

## File Plan

### New Files

| File | Purpose |
|------|---------|
| `src/models/plugin_config.py` | PluginConfig SQLAlchemy model |
| `src/repositories/plugin_config_repository.py` | CRUD repository |
| `tests/unit/plugins/test_plugin_config_model.py` | Model tests (4 tests) |
| `tests/unit/plugins/test_plugin_config_repository.py` | Repository tests (9 tests) |
| `tests/unit/plugins/test_plugin_manager_persistence.py` | Manager persistence tests (5 tests) |
| Alembic migration | `plugin_config` table |

### Modified Files

| File | Change |
|------|--------|
| `src/plugins/manager.py` | Add `config_repo` param, persist on enable/disable, add `load_persisted_state()` |
| `src/app.py` | Create repo, pass to PluginManager, call `load_persisted_state()` |

---

## TDD Execution Order

| Step | Type | Description | Status |
|------|------|-------------|--------|
| 1 | Unit (RED) | Write `test_plugin_config_model.py` — 4 tests fail | [ ] |
| 2 | Code (GREEN) | Create `plugin_config.py` model + migration — tests pass | [ ] |
| 3 | Unit (RED) | Write `test_plugin_config_repository.py` — 9 tests fail | [ ] |
| 4 | Code (GREEN) | Create `plugin_config_repository.py` — tests pass | [ ] |
| 5 | Unit (RED) | Write `test_plugin_manager_persistence.py` — 5 tests fail | [ ] |
| 6 | Code (GREEN) | Extend `PluginManager` with persistence — tests pass | [ ] |
| 7 | Code | Wire repo in `app.py` | [ ] |
| 8 | Verify | `make test-unit` — all tests pass | [ ] |
| 9 | Verify | `make test-integration` — analytics endpoint still works | [ ] |
| 10 | Verify | Manual persistence test (disable → restart → still disabled) | [ ] |

---

## Definition of Done

- [ ] `plugin_config` table exists with Alembic migration
- [ ] `PluginConfigRepository` provides get/save/delete operations
- [ ] `PluginManager` persists state on enable/disable when repo is provided
- [ ] `PluginManager.load_persisted_state()` restores plugin states on startup
- [ ] `PluginManager` still works without repo (backwards compatible, Liskov)
- [ ] 18+ new unit tests pass
- [ ] All existing 504+ tests pass (no regressions)
- [ ] Manual test: disable plugin → restart → plugin stays disabled
