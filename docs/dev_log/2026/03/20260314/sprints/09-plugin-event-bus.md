# Sprint 09 — Plugin Event Bus
**Status:** ⏳ Pending approval
**Date:** 2026-03-15

---

## Problem

The event system has two separate dispatchers that do not communicate, a broken import
that silently prevents all email notifications from firing, and three different files that
must be hand-edited every time a developer adds a new event to a plugin:

### Bug 1 — Email events never fire (production breakage)

`plugins/email/src/handlers.py` does:
```python
from src.events import event_dispatcher          # ImportError — name not exported
event_dispatcher.subscribe("subscription.activated", ...)  # AttributeError — method doesn't exist
```

`src/events/__init__.py` exports `DomainEventDispatcher` (a class), not any instance.
Neither `EventDispatcher` nor `DomainEventDispatcher` has a `.subscribe()` method.
All email event subscriptions are silently never registered.

### Bug 2 — No cross-dispatcher bridge

`DomainEventDispatcher.emit()` (used by core services for payment, subscription, user
events) runs only typed `IEventHandler` objects.
`EventDispatcher.dispatch()` (the plugin pub/sub bus) runs callbacks.
The two systems never communicate — a plugin cannot listen to a core domain event.

### Bug 3 — Adding a plugin event requires editing core

A plugin developer who wants to:
- Fire a new event → must define a class in `src/events/*.py` and export from `src/events/__init__.py`
- Have other plugins subscribe → no working mechanism exists
- Add an email template for it → must edit `plugins/email/src/services/event_contexts.py`
- Register an email handler → must edit `plugins/email/src/handlers.py`

---

## Goal

After this sprint, a plugin developer adding a new event needs to touch **only their own
plugin files**:

```python
# plugins/myplugin/__init__.py
from src.events import event_bus
from plugins.email.src.services.event_context_registry import EventContextRegistry

class MyPlugin(BasePlugin):
    def on_enable(self):
        # Register email template context — no edit to event_contexts.py
        EventContextRegistry.register("my.thing_happened", {
            "description": "Triggered when thing happens",
            "variables": {
                "user_email": {"type": "string", "example": "user@example.com", "description": "Recipient"},
                "thing_name": {"type": "string", "example": "Widget", "description": "Name of thing"},
            }
        })

    def register_event_handlers(self, bus):
        # Subscribe to any event (own or from other plugins) — no edit to handlers.py
        bus.subscribe("other.plugin_event", self._handle_it)

    def _do_something(self):
        # Emit an event — no class definition required for simple events
        event_bus.publish("my.thing_happened", {
            "user_email": user.email,
            "thing_name": thing.name,
        })
```

---

## Design

### Single EventBus (`src/events/bus.py`)

A thin wrapper over `EventDispatcher` with a developer-friendly API:

```python
class EventBus:
    def subscribe(self, event_name: str, callback: Callable[[str, dict], None]) -> None
    def unsubscribe(self, event_name: str, callback: Callable) -> None
    def publish(self, event_name: str, data: dict) -> None
    def has_subscribers(self, event_name: str) -> bool

event_bus = EventBus()   # module-level singleton
```

Callbacks receive `(event_name: str, data: dict)` — simpler than the current `Event` object.
Exported from `src/events/__init__.py` as `event_bus`.

### Bridge: DomainEventDispatcher → EventBus

`DomainEventDispatcher.emit()` currently runs core typed handlers.
After the bridge, it **also** calls `event_bus.publish(event.name, event.data)` so plugin
subscribers receive all domain events without any changes to core emit sites.

No changes to existing `IEventHandler` implementations or call sites.

### EventContextRegistry (`plugins/email/src/services/event_context_registry.py`)

```python
_registry: Dict[str, dict] = {}

def register(event_type: str, schema: dict) -> None: ...
def get_all() -> List[dict]: ...
def get(event_type: str) -> Optional[dict]: ...
```

The existing `EVENT_CONTEXTS` dict in `event_contexts.py` is kept as-is and
auto-registered by calling `EventContextRegistry.register()` for each entry at module
import time.

The email plugin's admin routes (`/admin/email/event-types`, `/admin/email/templates/preview`)
switch from reading `EVENT_CONTEXTS` directly to calling `EventContextRegistry.get_all()`.

Other plugins call `EventContextRegistry.register()` in `on_enable()` with no core touch.

### `BasePlugin.register_event_handlers(bus)` lifecycle hook

```python
class BasePlugin:
    def register_event_handlers(self, bus: "EventBus") -> None:
        """Called by PluginManager after on_enable(). Override to subscribe."""
        pass
```

`PluginManager.enable_plugin()` calls `plugin.register_event_handlers(event_bus)` after
`plugin.on_enable()`.

The email plugin moves its handler subscriptions from the broken `register_handlers(cfg)`
hack into `register_event_handlers(bus)`.

---

## Steps

| # | Where | Description |
|---|-------|-------------|
| 1 | `src/events/bus.py` | Create `EventBus` with `subscribe` / `unsubscribe` / `publish` / `has_subscribers`. Module-level `event_bus = EventBus()` singleton |
| 2 | `src/events/__init__.py` | Export `event_bus` singleton |
| 3 | `src/events/domain.py` | Bridge `DomainEventDispatcher.emit()` → also calls `event_bus.publish(event.name, event.data)`. Inject `event_bus` via constructor (default = module singleton) |
| 4 | `src/plugins/base.py` | Add `register_event_handlers(self, bus: EventBus) -> None` no-op hook |
| 5 | `src/plugins/manager.py` | After `plugin.enable()`, call `plugin.register_event_handlers(event_bus)` |
| 6 | `plugins/email/src/services/event_context_registry.py` | New `EventContextRegistry` module |
| 7 | `plugins/email/src/services/event_contexts.py` | Auto-register all `EVENT_CONTEXTS` entries into registry at import time. Keep dict for backward compat |
| 8 | `plugins/email/src/routes.py` | Replace direct `EVENT_CONTEXTS` reads with `EventContextRegistry.get_all()` / `get()` |
| 9 | `plugins/email/__init__.py` | Move event subscriptions out of `on_enable()` into `register_event_handlers(bus)`. Fix broken import |
| 10 | `plugins/email/src/handlers.py` | Rewrite `register_handlers()` to accept `bus: EventBus` instead of calling the broken `event_dispatcher.subscribe()` |
| 11 | Tests | Unit tests for EventBus; test bridge fires plugin subscribers when DomainEventDispatcher emits; test EventContextRegistry.register(); integration test that email handlers fire on subscription.activated |

---

## Acceptance Criteria

- `event_bus.publish("subscription.activated", {...})` causes the email plugin's handler
  to fire — no core file changes needed
- A new plugin can call `EventContextRegistry.register("my.event", schema)` in `on_enable()`
  and the event type appears in `/admin/email/event-types`
- A new plugin can call `bus.subscribe("any.event", handler)` in `register_event_handlers(bus)`
  and receive events from core or other plugins
- Core services emit `DomainEvent` via `DomainEventDispatcher.emit()` as before — no call
  sites change
- All existing core handlers (`IEventHandler` objects) continue to work unchanged
- `make test` passes (1100+ unit, 80+ integration)

---

## What Stays the Same

- `DomainEventDispatcher` and `IEventHandler` — not removed, core handlers still use them
- All `DomainEventDispatcher.emit()` call sites in core services — no changes
- All `IEventHandler` implementations (CheckoutHandler, PaymentCapturedHandler, etc.) — no changes
- `_register_event_handlers()` in `app.py` — no changes
- Event class definitions in `src/events/user_events.py` etc. — not required for plugin events
  (string names + dict data are sufficient), but still work for typed core events

---

## Notes

- `EventBus` callbacks receive `(event_name: str, data: dict)` not a `DomainEvent` object.
  This is intentional — plugins deal with plain data, not typed domain objects.
- The bridge is one-directional: domain → plugin bus. Plugins publish to the bus,
  not to the domain dispatcher. Core services emit to the domain dispatcher.
- `event_bus` is a module-level singleton (process-wide), safe for Flask threaded/gunicorn
  workers because subscriptions are set up at startup and never removed during a request.
- `EventContextRegistry` is also module-level — thread-safe for reads, registrations happen
  only at startup in `on_enable()`.

---

## Engineering Requirements

| Principle | Rule |
|-----------|------|
| **TDD** | Tests written before or alongside implementation. No step is done without passing tests. |
| **SOLID** | `EventBus` has one job (fanout); `EventContextRegistry` has one job (schema registry). |
| **DI** | `EventBus` instance injected into plugins via `BasePlugin.register_event_handlers(bus)`. No module-level `import event_bus` inside business logic. |
| **DRY** | Plugins call `bus.subscribe()` once in `on_enable()`; no duplicate handler wiring. |
| **Liskov** | All `BaseEventHandler` subclasses honour `handle(event)` signature. |
| **Clean code** | No bare `except: pass`. Log all swallowed exceptions at `WARNING` or above. No `as any`. |
| **No over-engineering** | `EventBus` is a plain dict of lists. No async, no persistence, no retry. |
| **Drop deprecated** | No `event_dispatcher.subscribe()` (doesn't exist). Use `bus.subscribe()` exclusively. |

---

## Pre-commit Checks

Run after every step before marking it done.

### vbwd-backend (`vbwd-backend/`)
```bash
# Lint only (Black + Flake8 + Mypy)
./bin/pre-commit-check.sh --lint

# Lint + unit tests
./bin/pre-commit-check.sh --unit

# Lint + integration tests (requires running PostgreSQL)
./bin/pre-commit-check.sh --integration

# Full (lint + unit + integration)
./bin/pre-commit-check.sh --full
```

All checks must pass before the sprint is considered complete.
