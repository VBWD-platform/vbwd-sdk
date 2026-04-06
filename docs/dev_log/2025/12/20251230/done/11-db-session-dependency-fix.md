# Sprint 11: Container.db_session Dependency Fix

**Priority:** HIGH (Startup Error)
**Duration:** 30 minutes
**Focus:** Fix DI container initialization order during app startup

> **Core Requirements:** TDD-first, SOLID, DI, Clean Code

---

## Problem Description

### Symptom
Backend logs showed repeated warnings during startup:
```
Failed to register event handlers: Dependency "Container.db_session" is not defined
```

### Root Cause Analysis
In `src/app.py`, the event handler registration was called **before** the `db_session` dependency was properly overridden:

```python
# Original flow (BROKEN):
container = Container()                    # 1. Container created
app.container = container                  # 2. Attached to app

@app.before_request
def inject_db_session():                   # 3. Override happens here (too late!)
    container.db_session.override(db.session)

_register_event_handlers(app, container)   # 4. Called BEFORE any request
                                           #    -> db_session not available!
```

The `_register_event_handlers` function needs `container.password_reset_service()` which depends on `db_session`. Since `db_session` is only overridden in `before_request` hook (which runs per-request), it's not available during app initialization.

---

## TDD Approach

### Step 1: Write Failing Tests

Added tests in `tests/unit/test_app.py`:

```python
class TestEventHandlerRegistration:
    """Test cases for event handler registration during app startup."""

    def test_event_handlers_register_without_dependency_error(self, caplog):
        """Event handlers should register without db_session dependency errors."""
        import logging
        from src.app import create_app
        from src.config import get_database_url

        caplog.set_level(logging.WARNING)

        app = create_app({
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": get_database_url(),
            "SQLALCHEMY_TRACK_MODIFICATIONS": False,
            "RATELIMIT_ENABLED": False,
        })

        # Check that no dependency errors were logged
        dependency_errors = [
            record for record in caplog.records
            if 'Dependency' in record.message and 'not defined' in record.message
        ]

        assert len(dependency_errors) == 0, (
            f"Expected no dependency errors, but found: "
            f"{[r.message for r in dependency_errors]}"
        )

    def test_event_dispatcher_has_handlers_registered(self):
        """Event dispatcher should have password reset handlers registered."""
        from src.app import create_app
        from src.config import get_database_url

        app = create_app({
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": get_database_url(),
            "SQLALCHEMY_TRACK_MODIFICATIONS": False,
            "RATELIMIT_ENABLED": False,
        })

        dispatcher = app.container.event_dispatcher()

        # Check that handlers are registered for security events
        assert "security.password_reset.request" in dispatcher._handlers
        assert "security.password_reset.execute" in dispatcher._handlers
```

### Step 2: Verify Tests Fail

```bash
$ docker-compose --profile test run --rm test pytest tests/unit/test_app.py::TestEventHandlerRegistration -v

FAILED test_event_handlers_register_without_dependency_error
  AssertionError: Expected no dependency errors, but found:
  ['Failed to register event handlers: Dependency "Container.db_session" is not defined']

FAILED test_event_dispatcher_has_handlers_registered
  AssertionError: assert 'security.password_reset.request' in {}
```

---

## Solution

### Step 3: Implement Fix

Modified `src/app.py` to override `db_session` within an app context **before** registering event handlers:

```python
# Fixed flow:
container = Container()
app.container = container

# Override db_session for app initialization (required for event handlers)
with app.app_context():
    container.db_session.override(db.session)

@app.before_request
def inject_db_session():
    """Inject db session into container for each request."""
    container.db_session.override(db.session)

# Register event handlers (now db_session is available)
with app.app_context():
    _register_event_handlers(app, container)
```

### Step 4: Verify Tests Pass

```bash
$ docker-compose --profile test run --rm test pytest tests/unit/test_app.py::TestEventHandlerRegistration -v

tests/unit/test_app.py::TestEventHandlerRegistration::test_event_handlers_register_without_dependency_error PASSED
tests/unit/test_app.py::TestEventHandlerRegistration::test_event_dispatcher_has_handlers_registered PASSED

============================== 2 passed in 0.46s ===============================
```

### Step 5: Full Test Suite

```bash
$ docker-compose --profile test run --rm test pytest tests/unit/ -v

============================= 450 passed in 4.36s ==============================
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/app.py` | Added `app_context()` wrapping for `db_session.override()` and `_register_event_handlers()` |
| `tests/unit/test_app.py` | Added `TestEventHandlerRegistration` test class with 2 tests |

---

## Verification

After restart, backend logs no longer show the dependency error:

```bash
$ docker-compose restart api && docker-compose logs --tail=20 api

api_1  | [2025-12-30 09:46:52 +0000] [1] [INFO] Starting gunicorn 21.2.0
api_1  | [2025-12-30 09:46:52 +0000] [1] [INFO] Listening at: http://0.0.0.0:5000 (1)
api_1  | [2025-12-30 09:46:52 +0000] [1] [INFO] Using worker: sync
api_1  | [2025-12-30 09:46:52 +0000] [7] [INFO] Booting worker with pid: 7
# No "Failed to register event handlers" warnings!
```

---

## Summary

- **Issue:** `Container.db_session` not available during app initialization
- **Cause:** Dependency was only overridden in `before_request` hook
- **Fix:** Override dependency in `app_context()` before event handler registration
- **Tests:** 2 new tests added, 450 unit tests passing
