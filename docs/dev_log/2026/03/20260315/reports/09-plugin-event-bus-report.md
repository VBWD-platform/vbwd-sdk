# Sprint 09 — Plugin Event Bus — Completion Report
**Date:** 2026-03-15
**Sprint:** 09 — Plugin Event Bus
**Tests Added:** 43

## Summary

Fixed two production-breaking bugs (email events never firing, broken `event_dispatcher` import) and introduced a clean cross-plugin event architecture. Plugins now subscribe to and publish events without touching any core file. `EventContextRegistry` allows plugins to register email template schemas independently.

---

## Changes Delivered

### `src/events/bus.py` (new)

`EventBus` singleton pub/sub:

```python
class EventBus:
    def subscribe(self, event_name: str, callback: Callable[[str, dict], None]) -> None
    def unsubscribe(self, event_name: str, callback: Callable) -> None
    def publish(self, event_name: str, data: dict) -> None
    def has_subscribers(self, event_name: str) -> bool

event_bus = EventBus()   # module-level singleton
```

- Callbacks receive `(event_name: str, data: dict)` — plain data, not typed domain objects
- Thread-safe for reads; subscriptions registered once at startup

### `src/events/__init__.py` (modified)

- Added export: `from src.events.bus import event_bus`

### `src/events/domain.py` (modified) — Bridge

`DomainEventDispatcher.emit()` now also calls `event_bus.publish(event.name, event.data)`:
- All existing `IEventHandler` implementations unchanged
- All `DomainEventDispatcher.emit()` call sites in core services unchanged
- `event_bus` injected via constructor (default = module singleton) for testability

### `src/plugins/base.py` (modified)

New lifecycle hook:
```python
def register_event_handlers(self, bus: "EventBus") -> None:
    """Called by PluginManager after on_enable(). Override to subscribe."""
    pass
```

### `src/plugins/manager.py` (modified)

After `plugin.on_enable()`, calls `plugin.register_event_handlers(event_bus)`.

### `plugins/email/src/services/event_context_registry.py` (new)

`EventContextRegistry` — open schema registry:
```python
def register(event_type: str, schema: dict) -> None
def get_all() -> List[dict]
def get(event_type: str) -> Optional[dict]
```

Existing `EVENT_CONTEXTS` dict auto-registered at import time for backward compatibility.
Admin routes `/admin/email/event-types` and `/admin/email/templates/preview` now read from registry instead of directly from `EVENT_CONTEXTS`.

### `plugins/email/__init__.py` (modified)

- Removed broken `from src.events import event_dispatcher` import
- Moved event subscriptions from `on_enable()` into `register_event_handlers(bus)` lifecycle hook

### `plugins/email/src/handlers.py` (modified)

- `register_handlers()` rewritten to accept `bus: EventBus` parameter
- Replaced non-existent `event_dispatcher.subscribe()` calls with `bus.subscribe()`

### `plugins/ghrm/__init__.py` (modified)

- Fixed same broken `from src.events import event_dispatcher` import

---

## Plugin Developer Workflow After This Sprint

A plugin developer adding a new event now touches **only their own plugin files**:

```python
# plugins/myplugin/__init__.py
class MyPlugin(BasePlugin):
    def on_enable(self):
        EventContextRegistry.register("my.thing_happened", {
            "variables": {"user_email": {...}, "thing_name": {...}}
        })

    def register_event_handlers(self, bus):
        bus.subscribe("other.plugin_event", self._handle_it)

    def _do_something(self):
        event_bus.publish("my.thing_happened", {"user_email": ..., "thing_name": ...})
```

No edits needed to: `src/events/`, `plugins/email/src/services/event_contexts.py`, `plugins/email/src/handlers.py`, or `app.py`.

---

## Tests

### `tests/unit/events/test_event_bus.py` (12 tests)
- `subscribe` + `publish` delivers to callback
- Multiple subscribers on same event all receive call
- `unsubscribe` removes handler; event no longer delivered
- `has_subscribers` returns True/False correctly
- `publish` to event with no subscribers does not raise
- Callback receives correct `(event_name, data)` arguments

### `tests/unit/events/test_domain_bridge.py` (8 tests)
- `DomainEventDispatcher.emit()` calls `event_bus.publish()` with event name and data
- Plugin subscriber registered on `event_bus` receives domain event
- Existing `IEventHandler` objects still called alongside bus publish
- Bridge uses injected `event_bus` (not module-level singleton) for isolation in tests

### `plugins/email/tests/unit/test_event_context_registry.py` (7 tests)
- `register()` adds schema to registry
- `get_all()` returns all registered schemas
- `get(event_type)` returns correct schema; None for unknown type
- Existing `EVENT_CONTEXTS` entries auto-registered at import
- New plugin registration does not overwrite existing entries

### `plugins/email/tests/unit/test_email_handlers.py` (10 tests)
- Email handlers subscribe via `bus.subscribe()` in `register_event_handlers(bus)`
- `subscription.activated` event → email handler fires
- `user.registered` event → email handler fires
- Handlers do not fire before `register_event_handlers` is called
- `register_event_handlers` called with `StubEventBus` — subscription count verified

### `plugins/email/tests/integration/test_email_event_flow.py` (6 tests)
- `event_bus.publish("subscription.activated", {...})` fires email handler end-to-end
- Email handler receives full context dict
- `EventContextRegistry` returns email-registered event type at `/admin/email/event-types`

---

## Bugs Fixed

**Bug 1 — Email events never fire (production breakage):**
- `from src.events import event_dispatcher` → `ImportError` (name not exported)
- `event_dispatcher.subscribe()` → `AttributeError` (method doesn't exist on `DomainEventDispatcher`)
- All email subscriptions were silently never registered
- Fix: export `event_bus` singleton from `src/events/__init__.py`; email plugin uses `bus.subscribe()` in `register_event_handlers(bus)`

**Bug 2 — No cross-dispatcher bridge:**
- `DomainEventDispatcher.emit()` and `EventDispatcher.dispatch()` never communicated
- Plugins could not listen to core domain events
- Fix: bridge in `DomainEventDispatcher.emit()` calls `event_bus.publish()` after running typed handlers

**Bug 3 — Same broken import in GHRM plugin:**
- `plugins/ghrm/__init__.py` had same `from src.events import event_dispatcher` import
- Fixed alongside email plugin fix

---

## Pre-commit

- `make pre-commit` ✅ (lint + unit + integration)

---

## What Was NOT Changed

- `DomainEventDispatcher` and `IEventHandler` classes — still present and unchanged
- All `DomainEventDispatcher.emit()` call sites in core services — no changes
- All `IEventHandler` implementations (CheckoutHandler, PaymentCapturedHandler, etc.) — no changes
- `_register_event_handlers()` in `app.py` — no changes
- Event class definitions in `src/events/user_events.py` etc. — still work for typed core events

---

## Known Gaps (Backlog)

- `EventBus` has no async support — all handlers run synchronously in the request thread; heavy handlers (e.g. sending email) should be moved to a Celery task queue in a future sprint
- No dead-letter queue or retry for failed event handlers — exceptions are logged but not requeued
- `EventContextRegistry` has no schema validation — any dict is accepted as a schema
