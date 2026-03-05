# Sprint 09 — Backend Plugin Auto-Discovery

**Priority:** LOW
**Goal:** Plugins in `src/plugins/providers/` are discovered and registered automatically. No manual imports in `app.py`. Adding a new plugin = drop a file in the directory.

**Principles:** TDD-first, SOLID, DRY, Liskov Substitution, DI, Clean Code, No Overengineering

**Depends on:** Sprint 07 (dynamic route registration), Sprint 08 (DB config persistence)

---

## Overview

Current state:
- `app.py` manually imports each plugin: `from src.plugins.providers.analytics_plugin import AnalyticsPlugin`
- Each new plugin requires editing `app.py` to import and register it
- Plugin count is small (2: MockPayment + Analytics), but the pattern doesn't scale

After this sprint:
- `PluginManager.discover(path)` scans a directory for `BasePlugin` subclasses
- All discovered plugins are registered automatically
- `app.py` calls `plugin_manager.discover("src/plugins/providers")` instead of manual imports
- DB persistence (Sprint 08) controls which are enabled — discovery only registers
- `MockPaymentPlugin` and `AnalyticsPlugin` are auto-discovered

Architecture doc reference: `docs/architecture_core_server_ce/plugin-system.md` lines 238-268

---

## Phase 1: Discovery Method

### 1.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/plugins/test_plugin_discovery.py`

```
Tests to write FIRST:

test_discover_finds_analytics_plugin
  - manager.discover("src/plugins/providers")
  - manager.get_plugin("analytics") is not None

test_discover_finds_mock_payment_plugin
  - manager.discover("src/plugins/providers")
  - manager.get_plugin("mock-payment") is not None

test_discover_returns_count_of_discovered_plugins
  - count = manager.discover("src/plugins/providers")
  - count >= 2 (analytics + mock_payment)

test_discover_skips_non_plugin_modules
  - __init__.py should not be loaded as a plugin
  - modules without BasePlugin subclass should be skipped

test_discover_skips_abstract_classes
  - PaymentProviderPlugin is abstract — should not be instantiated
  - Only concrete subclasses are registered

test_discover_skips_already_registered_plugins
  - Register analytics manually
  - discover() finds it but doesn't duplicate — no ValueError
  - Still only 1 "analytics" plugin

test_discover_handles_import_errors_gracefully
  - If a module has import errors, skip it and log warning
  - Other plugins still discovered

test_discover_empty_directory_returns_zero
  - manager.discover("nonexistent/path")
  - Returns 0, no error

test_discover_initializes_discovered_plugins
  - After discover(), all plugins have status INITIALIZED (ready to enable)
```

### 1.2 Implementation (GREEN)

**File:** `vbwd-backend/src/plugins/manager.py` — add `discover()` method

```python
import importlib
import pkgutil
import inspect
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

class PluginManager:
    # ... existing code ...

    def discover(self, package_path: str) -> int:
        """
        Discover and register plugins in a Python package directory.

        Scans for modules containing concrete BasePlugin subclasses.
        Discovered plugins are registered and initialized (but not enabled).

        Args:
            package_path: Dotted module path (e.g., "src.plugins.providers")
                          or filesystem path (e.g., "src/plugins/providers")

        Returns:
            Number of newly discovered plugins.
        """
        count = 0
        module_path = package_path.replace("/", ".")

        try:
            package = importlib.import_module(module_path)
        except ImportError as e:
            logger.warning(f"Cannot import plugin package '{module_path}': {e}")
            return 0

        package_dir = Path(package.__file__).parent

        for _, module_name, _ in pkgutil.iter_modules([str(package_dir)]):
            full_module = f"{module_path}.{module_name}"
            try:
                module = importlib.import_module(full_module)
            except Exception as e:
                logger.warning(f"Failed to import plugin module '{full_module}': {e}")
                continue

            for _, obj in inspect.getmembers(module, inspect.isclass):
                if (
                    issubclass(obj, BasePlugin)
                    and obj is not BasePlugin
                    and not inspect.isabstract(obj)
                    and obj.__module__ == full_module  # Only classes defined in this module
                ):
                    try:
                        plugin = obj()
                        name = plugin.metadata.name
                        if name not in self._plugins:
                            self.register_plugin(plugin)
                            self.initialize_plugin(name)
                            count += 1
                            logger.info(f"Discovered plugin: {name} ({plugin.metadata.version})")
                        else:
                            logger.debug(f"Plugin '{name}' already registered, skipping")
                    except Exception as e:
                        logger.warning(f"Failed to instantiate plugin from {obj.__name__}: {e}")

        return count
```

Key decisions:
- **No overengineering:** No `plugin.yaml` files — metadata comes from the class itself (already exists via `PluginMetadata`)
- **No overengineering:** No recursive scanning, no entry points, no config-driven paths — just one directory
- **Liskov:** Uses `issubclass(obj, BasePlugin)` — any proper subclass is discovered
- **Defensive:** `inspect.isabstract(obj)` skips abstract bases like `PaymentProviderPlugin`
- **Defensive:** `obj.__module__ == full_module` prevents re-registering imported base classes
- **DRY:** Discovered plugins go through same `register_plugin` + `initialize_plugin` path as manual ones

---

## Phase 2: Wire in app.py

### 2.1 Unit Tests (RED)

**File:** `vbwd-backend/tests/unit/test_app.py` — extend existing

```
Tests to add:

test_app_discovers_plugins_automatically
  - create_app()
  - app.plugin_manager.get_plugin("analytics") is not None
  - app.plugin_manager.get_plugin("mock-payment") is not None

test_app_enables_plugins_from_db
  - Pre-seed DB with analytics=enabled
  - create_app()
  - app.plugin_manager.get_plugin("analytics").status == ENABLED
```

### 2.2 Implementation (GREEN)

**File:** `vbwd-backend/src/app.py` — replace manual imports with discovery

Remove:
```python
from src.plugins.providers.analytics_plugin import AnalyticsPlugin

# ...
analytics_plugin = AnalyticsPlugin()
plugin_manager.register_plugin(analytics_plugin)
plugin_manager.initialize_plugin("analytics")
```

Replace with:
```python
# Discover all plugins in providers directory
plugin_manager.discover("src.plugins.providers")

# Restore enabled states from DB
plugin_manager.load_persisted_state()

# First run: enable default plugins if nothing in DB
if not plugin_manager.get_enabled_plugins():
    plugin_manager.enable_plugin("analytics")
```

That's it. Three lines. Any new plugin dropped into `src/plugins/providers/` is auto-discovered on next restart.

---

## Phase 3: Verification

### 3.1 Run All Tests

```bash
# Backend tests
cd vbwd-backend && make test-unit
cd vbwd-backend && make test-integration
```

### 3.2 Discovery Test (manual)

```bash
cd vbwd-backend && make shell
flask plugins list
# Expected output:
# analytics (1.0.0) — ENABLED
# mock-payment (1.0.0) — INITIALIZED
```

### 3.3 New Plugin Test (manual, optional)

Create a trivial test plugin to verify discovery works for new plugins:

```bash
# Create a new file
cat > src/plugins/providers/hello_plugin.py << 'EOF'
from src.plugins.base import BasePlugin, PluginMetadata

class HelloPlugin(BasePlugin):
    @property
    def metadata(self):
        return PluginMetadata(name="hello", version="0.1.0", author="Test", description="Hello world plugin")
EOF

# Restart and verify
flask plugins list
# Expected: hello (0.1.0) — INITIALIZED (discovered but not enabled)
flask plugins enable hello
flask plugins list
# Expected: hello (0.1.0) — ENABLED

# Clean up
rm src/plugins/providers/hello_plugin.py
```

---

## File Plan

### New Files

| File | Purpose |
|------|---------|
| `tests/unit/plugins/test_plugin_discovery.py` | Discovery tests (9 tests) |

### Modified Files

| File | Change |
|------|--------|
| `src/plugins/manager.py` | Add `discover()` method (~40 lines) |
| `src/app.py` | Replace manual plugin imports with `plugin_manager.discover()` call |

---

## TDD Execution Order

| Step | Type | Description | Status |
|------|------|-------------|--------|
| 1 | Unit (RED) | Write `test_plugin_discovery.py` — 9 tests fail | [ ] |
| 2 | Code (GREEN) | Implement `discover()` in PluginManager — tests pass | [ ] |
| 3 | Code | Update `app.py` — replace manual imports with `discover()` | [ ] |
| 4 | Unit | Extend `test_app.py` — verify auto-discovery in app factory | [ ] |
| 5 | Verify | `make test-unit` — all tests pass | [ ] |
| 6 | Verify | `flask plugins list` shows both plugins | [ ] |

---

## Definition of Done

- [ ] `PluginManager.discover()` finds all `BasePlugin` subclasses in a package directory
- [ ] Abstract classes and non-plugin modules are skipped
- [ ] Already-registered plugins are not duplicated
- [ ] Import errors are logged and skipped (one bad plugin doesn't break the rest)
- [ ] `app.py` uses `discover()` instead of manual imports
- [ ] DB persistence (Sprint 08) controls which plugins are enabled after discovery
- [ ] 9+ new unit tests pass
- [ ] All existing tests pass (no regressions)
- [ ] `flask plugins list` shows all discovered plugins with correct status
