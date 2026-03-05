# Sprint 07 — Backend Dynamic Route Registration for Plugins

**Priority:** MEDIUM
**Goal:** Plugins declare their own Flask blueprints. `PluginManager` collects them. `app.py` registers them in a loop instead of hard-coding each plugin's blueprint.

**Principles:** TDD-first, SOLID, DRY, Liskov Substitution, DI, Clean Code, No Overengineering

---

## Overview

Current state:
- `analytics_plugin_bp` is imported directly in `app.py` (line 121)
- Blueprint is registered with hard-coded url_prefix (line 206)
- CSRF exemption is hard-coded (line 145)
- Adding a new plugin requires editing 3 places in `app.py`

After this sprint:
- `BasePlugin` gains an optional `get_blueprint()` method (returns `None` by default)
- `AnalyticsPlugin` overrides it to return its blueprint
- `PluginManager` collects blueprints from enabled plugins via `get_plugin_blueprints()`
- `app.py` registers all plugin blueprints in a single loop
- Adding a new plugin requires zero changes to `app.py`

No new endpoints, no new plugins — just move existing wiring from hard-coded to dynamic.

---

## Phase 1: BasePlugin Blueprint Support

### 1.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/plugins/test_plugin_blueprints.py`

```
Tests to write FIRST:

test_base_plugin_get_blueprint_returns_none_by_default
  - Create a minimal BasePlugin subclass (no blueprint override)
  - plugin.get_blueprint() returns None

test_base_plugin_get_url_prefix_returns_none_by_default
  - plugin.get_url_prefix() returns None

test_analytics_plugin_get_blueprint_returns_blueprint
  - plugin = AnalyticsPlugin()
  - bp = plugin.get_blueprint()
  - bp is a Flask Blueprint instance
  - bp.name == "analytics_plugin"

test_analytics_plugin_get_url_prefix_returns_path
  - plugin.get_url_prefix() == "/api/v1/plugins/analytics"

test_manager_get_plugin_blueprints_returns_enabled_only
  - Register 2 plugins (analytics + a mock with no blueprint)
  - Enable only analytics
  - manager.get_plugin_blueprints() returns [(blueprint, prefix)] for analytics only

test_manager_get_plugin_blueprints_skips_plugins_without_blueprint
  - Register plugin with get_blueprint() → None
  - Enable it
  - manager.get_plugin_blueprints() returns empty list

test_manager_get_plugin_blueprints_empty_when_none_enabled
  - Register analytics but don't enable
  - manager.get_plugin_blueprints() returns []
```

### 1.2 Implementation (GREEN)

**File:** `vbwd-backend/src/plugins/base.py` — add 2 optional methods

```python
def get_blueprint(self) -> Optional["Blueprint"]:
    """Return Flask blueprint for this plugin's API routes. None if no routes."""
    return None

def get_url_prefix(self) -> Optional[str]:
    """Return URL prefix for this plugin's blueprint. None if no routes."""
    return None
```

Key decisions:
- **Liskov:** Existing plugins (MockPayment) still work — default returns `None`
- **OCP:** New plugins override these methods to add routes without touching `app.py`
- **No overengineering:** Just 2 methods. No route builder, no middleware injection, no permission system

**File:** `vbwd-backend/src/plugins/providers/analytics_plugin.py` — override methods

```python
def get_blueprint(self) -> Optional["Blueprint"]:
    from src.routes.plugins.analytics import analytics_plugin_bp
    return analytics_plugin_bp

def get_url_prefix(self) -> Optional[str]:
    return "/api/v1/plugins/analytics"
```

**File:** `vbwd-backend/src/plugins/manager.py` — add collection method

```python
def get_plugin_blueprints(self) -> List[tuple]:
    """Get blueprints from all enabled plugins that have routes.
    Returns list of (blueprint, url_prefix) tuples."""
    result = []
    for plugin in self.get_enabled_plugins():
        bp = plugin.get_blueprint()
        if bp:
            result.append((bp, plugin.get_url_prefix()))
    return result
```

---

## Phase 2: app.py Dynamic Registration

### 2.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/test_app.py` — add tests (extend existing)

```
Tests to add:

test_app_has_plugin_manager
  - app.plugin_manager is a PluginManager instance

test_analytics_plugin_route_accessible
  - GET /api/v1/plugins/analytics/active-sessions returns 200 (with admin auth)
  - Verifies blueprint was registered dynamically

test_plugin_blueprint_registered_via_manager
  - app.plugin_manager.get_plugin("analytics") is ENABLED
  - Route exists in app.url_map
```

### 2.2 Implementation (GREEN)

**File:** `vbwd-backend/src/app.py` — replace hard-coded plugin blueprint registration

Remove:
```python
from src.routes.plugins.analytics import analytics_plugin_bp
# ... (line 121)
csrf.exempt(analytics_plugin_bp)
# ... (line 145)
app.register_blueprint(analytics_plugin_bp, url_prefix="/api/v1/plugins/analytics")
# ... (line 206)
```

Replace with (after plugin_manager.enable_plugin):
```python
# Register plugin blueprints dynamically
for bp, prefix in plugin_manager.get_plugin_blueprints():
    csrf.exempt(bp)
    app.register_blueprint(bp, url_prefix=prefix)
```

This is ~3 lines replacing ~3 hard-coded lines. Same result, but now adding a new plugin with routes requires zero `app.py` changes.

---

## Phase 3: Verification

### 3.1 Run All Tests

```bash
# Backend tests (must be in Docker)
cd vbwd-backend && make test-unit

# Verify analytics endpoint still works
cd vbwd-backend && make test-integration
```

### 3.2 Rebuild & Smoke Test

```bash
cd vbwd-backend && make up-build
# flask plugins list → analytics (1.0.0) — ENABLED
# curl localhost:5000/api/v1/plugins/analytics/active-sessions (with admin token) → 200
```

---

## File Plan

### New Files

| File | Purpose |
|------|---------|
| `tests/unit/plugins/test_plugin_blueprints.py` | Blueprint method tests (7 tests) |

### Modified Files

| File | Change |
|------|--------|
| `src/plugins/base.py` | Add `get_blueprint()` and `get_url_prefix()` methods (2 methods, 6 lines) |
| `src/plugins/providers/analytics_plugin.py` | Override `get_blueprint()` and `get_url_prefix()` |
| `src/plugins/manager.py` | Add `get_plugin_blueprints()` method |
| `src/app.py` | Replace 3 hard-coded lines with 3-line dynamic loop |

---

## TDD Execution Order

| Step | Type | Description | Status |
|------|------|-------------|--------|
| 1 | Unit (RED) | Write `test_plugin_blueprints.py` — 7 tests fail | [ ] |
| 2 | Code (GREEN) | Add `get_blueprint()`/`get_url_prefix()` to BasePlugin — 2 tests pass | [ ] |
| 3 | Code (GREEN) | Override in AnalyticsPlugin — 2 more tests pass | [ ] |
| 4 | Code (GREEN) | Add `get_plugin_blueprints()` to PluginManager — remaining tests pass | [ ] |
| 5 | Code | Update `app.py` — replace hard-coded with dynamic loop | [ ] |
| 6 | Unit (RED) | Add `test_app.py` tests — verify they pass with dynamic registration | [ ] |
| 7 | Verify | `make test-unit` — all 504+ tests pass | [ ] |
| 8 | Verify | `make test-integration` — analytics endpoint still works | [ ] |

---

## Definition of Done

- [ ] `BasePlugin.get_blueprint()` returns `None` by default (Liskov — no break)
- [ ] `AnalyticsPlugin.get_blueprint()` returns its blueprint
- [ ] `PluginManager.get_plugin_blueprints()` collects blueprints from enabled plugins
- [ ] `app.py` registers plugin blueprints in a loop (no hard-coded plugin imports)
- [ ] 7+ new unit tests pass
- [ ] All existing 504+ tests pass (no regressions)
- [ ] Analytics endpoint still returns 200 with admin auth
