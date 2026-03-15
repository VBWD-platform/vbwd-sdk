# EventBus — Plugin Event System

Complete reference for the EventBus introduced in Sprint 09. Covers the two legacy problems it solves, the architecture, the bridge to core domain events, and the plugin hooks.

---

## Table of Contents

1. [Background — Two Problems](#1-background--two-problems)
2. [Architecture Overview](#2-architecture-overview)
3. [EventBus API](#3-eventbus-api)
4. [Domain Event Bridge](#4-domain-event-bridge)
5. [BasePlugin.register_event_handlers](#5-basepluginregister_event_handlers)
6. [EventContextRegistry](#6-eventcontextregistry)
7. [Code Examples](#7-code-examples)
8. [What Stays the Same](#8-what-stays-the-same)

---

## 1. Background — Two Problems

### Problem 1 — Two disconnected event systems

Before Sprint 09 there were two separate event subsystems that could not talk to each other:

| System | Location | Purpose | Consumers |
|---|---|---|---|
| `DomainEventDispatcher` | `src/events/domain.py` | Typed `IEventHandler` objects for core business logic | Core services only |
| `EventDispatcher` | `src/events/dispatcher.py` | Callback-based pub/sub bus passed to `PluginManager` | Plugins only |

Plugins registered callbacks on the `EventDispatcher` instance. Core services emitted events through `DomainEventDispatcher.emit()`. Because these were separate objects, **plugin callbacks never received domain events** — a plugin could not react to `subscription.activated` even though the core fired it.

### Problem 2 — Broken email plugin import

The email plugin's `handlers.py` attempted to import the dispatcher as:

```python
from src.events import event_dispatcher
```

No such name existed in `src/events/__init__.py`. The import raised `ImportError` at startup, silently disabling all transactional email dispatch.

---

## 2. Architecture Overview

Sprint 09 introduces a third object — `EventBus` — and wires it between the two existing systems:

```
                     ┌─────────────────────────────────────┐
                     │  src/events/bus.py                  │
                     │                                     │
                     │  EventBus (singleton: event_bus)    │
                     │  ──────────────────────────────     │
                     │  subscribe(event_name, callback)    │
                     │  unsubscribe(event_name, callback)  │
                     │  publish(event_name, data)          │
                     │  has_subscribers(event_name)        │
                     └─────────────┬───────────────────────┘
                                   ▲ publish()
                                   │
        ┌──────────────────────────┴──────────────────────────┐
        │  DomainEventDispatcher.emit()  (src/events/domain.py) │
        │                                                       │
        │  1. Run typed IEventHandler objects (unchanged)       │
        │  2. Call event_bus.publish(event.name, event.data)    │
        └───────────────────────────────────────────────────────┘
                     ▲ emit()
                     │
             Core services (unchanged call sites)

                     │ subscribe()
                     ▼
        ┌─────────────────────────────────┐
        │  Plugin.register_event_handlers │
        │  (called after on_enable())     │
        └─────────────────────────────────┘
```

**Key properties:**
- `EventBus` is a simple pub/sub singleton — no async, no persistence, no retry.
- Callbacks receive `(event_name: str, data: dict)` — plain dicts, no typed domain objects.
- `DomainEventDispatcher.emit()` remains the sole place core services publish events. Its call sites are unchanged.
- Plugins never call `DomainEventDispatcher.emit()` directly (unless they need typed handler results). They call `event_bus.publish()` for plugin-to-plugin events.
- Module-level singleton imported as `from src.events import event_bus`.

---

## 3. EventBus API

**Location:** `src/events/bus.py`

**Import:**
```python
from src.events import event_bus
```

### Methods

#### `subscribe(event_name, callback)`

Register a callback to be called when `event_name` is published.

```python
event_bus.subscribe("subscription.activated", my_handler)
```

- `event_name` — dot-separated string, e.g. `"subscription.activated"`
- `callback` — `Callable[[str, dict], None]`; receives `(event_name, data)`
- Duplicate registrations are silently ignored (same callback object, same event)

#### `unsubscribe(event_name, callback)`

Remove a previously registered callback. No-op if not found.

```python
event_bus.unsubscribe("subscription.activated", my_handler)
```

#### `publish(event_name, data)`

Call all subscribers registered for `event_name` with the given `data` dict.

```python
event_bus.publish("my_plugin.thing_happened", {"item_id": str(item.id)})
```

- Subscriber exceptions are caught and logged at `WARNING` level; remaining subscribers still execute.
- No-op (debug log only) if there are no subscribers.

#### `has_subscribers(event_name)`

Return `True` if at least one subscriber is registered for `event_name`.

```python
if event_bus.has_subscribers("subscription.activated"):
    ...
```

---

## 4. Domain Event Bridge

`DomainEventDispatcher.emit()` in `src/events/domain.py` now has a two-phase execution:

1. **Phase 1 (unchanged):** Run every registered `IEventHandler` object that returns `True` from `can_handle(event)`. Collect `EventResult` objects.
2. **Phase 2 (new):** Call `event_bus.publish(event.name, event.data or {})`.

This means every domain event that passes through `DomainEventDispatcher` is automatically forwarded to plugin subscribers — **no changes to the emit call sites are required**.

The bridge import is lazy (inside `emit()`) to avoid circular imports:

```python
# src/events/domain.py — simplified
def emit(self, event: DomainEvent) -> EventResult:
    # Phase 1 — typed handlers
    results = [...]

    # Phase 2 — forward to EventBus
    bus = self._event_bus  # injected, or...
    if bus is None:
        from src.events.bus import event_bus as _bus
        bus = _bus
    if bus is not None:
        bus.publish(event.name, event.data or {})

    return EventResult.combine(results)
```

**Testing:** Pass `event_bus=None` to `DomainEventDispatcher()` in unit tests to disable the bridge and test handlers in isolation without side-effects on the singleton bus.

---

## 5. BasePlugin.register_event_handlers

**Location:** `src/plugins/base.py`

```python
def register_event_handlers(self, bus: Any) -> None:
    """Subscribe to EventBus events.

    Called by PluginManager.enable_plugin() after on_enable().
    Override this method to subscribe to domain or plugin events using
    bus.subscribe(event_name, callback).

    Args:
        bus: The EventBus singleton.
    """
    pass
```

### Lifecycle order

```
PluginManager.enable_plugin(name)
    │
    ├── plugin.on_enable()                    # set up non-event resources
    │
    └── plugin.register_event_handlers(bus)   # subscribe to EventBus
```

**Rule:** Subscribe to `event_bus` here, not in `on_enable()`. Using `on_enable()` for event subscriptions was the source of the broken import pattern.

### Override pattern

```python
class MyPlugin(BasePlugin):

    def register_event_handlers(self, bus) -> None:
        bus.subscribe("subscription.activated", self._on_activated)
        bus.subscribe("subscription.cancelled", self._on_cancelled)

    def _on_activated(self, event_name: str, data: dict) -> None:
        user_id = data.get("user_id")
        plan_id = data.get("plan_id")
        # grant access, etc.

    def _on_cancelled(self, event_name: str, data: dict) -> None:
        user_id = data.get("user_id")
        # begin grace period, etc.
```

---

## 6. EventContextRegistry

**Location:** `plugins/email/src/services/event_context_registry.py`

The `EventContextRegistry` is an open-schema registry. Any plugin can register the template variables it will include in a given event's payload. The email admin panel reads from this registry to populate the variable-hint UI when a template author is editing a template for that event type.

### Module-level functions

```python
from plugins.email.src.services.event_context_registry import EventContextRegistry
```

#### `register(event_type, schema)`

Register (or update) the variable schema for `event_type`.

```python
EventContextRegistry.register("my_plugin.order_shipped", {
    "description": "Fired when a digital order is dispatched",
    "variables": {
        "user_email": {
            "type": "string",
            "description": "Recipient address",
            "example": "alice@example.com",
        },
        "order_id": {
            "type": "string",
            "description": "Order UUID",
            "example": "a1b2c3d4-...",
        },
        "download_url": {
            "type": "string",
            "description": "Secure download link",
            "example": "https://app.example.com/downloads/token",
        },
    },
})
```

- Calling `register()` a second time for the same `event_type` replaces the entry (last-write wins). This lets plugins override core defaults.
- Call `register()` in `on_enable()` (not `register_event_handlers`) because it has no dependency on the bus instance.

#### `get_all()`

Return all registered schemas as a list of dicts sorted by event name. Used by `GET /api/v1/admin/email/event-types`.

#### `get(event_type)`

Return the schema for a single event type, or `None`.

### Relationship to core email contexts

`plugins/email/src/services/event_contexts.py` defines the 8 built-in transactional email events and auto-registers them into the registry at import time. Plugins add to this set — they do not modify `event_contexts.py`.

### Summary: who calls what

| Task | Where to call | Method |
|---|---|---|
| Subscribe to a bus event | `register_event_handlers(bus)` | `bus.subscribe()` |
| Publish a custom bus event | anywhere in plugin code | `event_bus.publish()` |
| Register email template schema | `on_enable()` | `EventContextRegistry.register()` |

---

## 7. Code Examples

### Publishing an event from a plugin

```python
# plugins/my_plugin/src/services/my_service.py
from src.events import event_bus

class MyService:
    def complete_order(self, order_id: str, user_email: str) -> None:
        # ... business logic ...
        event_bus.publish("my_plugin.order_completed", {
            "order_id": order_id,
            "user_email": user_email,
        })
```

### Subscribing in register_event_handlers

```python
# plugins/my_plugin/__init__.py
from src.plugins.base import BasePlugin, PluginMetadata

class MyPlugin(BasePlugin):

    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="my-plugin",
            version="1.0.0",
            author="Your Name",
            description="Example plugin",
        )

    def get_blueprint(self):
        from plugins.my_plugin.src.routes import my_bp
        return my_bp

    def get_url_prefix(self) -> str:
        return ""

    def on_enable(self) -> None:
        # Register email template schemas here (no bus needed)
        from plugins.email.src.services.event_context_registry import EventContextRegistry
        EventContextRegistry.register("my_plugin.order_completed", {
            "description": "Sent when an order completes",
            "variables": {
                "user_email": {"type": "string", "example": "alice@example.com",
                               "description": "Recipient"},
                "order_id":   {"type": "string", "example": "a1b2c3d4",
                               "description": "Order UUID"},
            },
        })

    def register_event_handlers(self, bus) -> None:
        # Subscribe to core domain events forwarded by the bridge
        bus.subscribe("subscription.activated", self._on_activated)
        bus.subscribe("subscription.cancelled", self._on_cancelled)
        # Subscribe to events published by other plugins
        bus.subscribe("my_plugin.order_completed", self._on_order_completed)

    # ------------------------------------------------------------------

    def _on_activated(self, event_name: str, data: dict) -> None:
        user_id = data.get("user_id")
        plan_id = data.get("plan_id")
        # grant access ...

    def _on_cancelled(self, event_name: str, data: dict) -> None:
        user_id = data.get("user_id")
        # start grace period ...

    def _on_order_completed(self, event_name: str, data: dict) -> None:
        order_id = data.get("order_id")
        # post-processing ...
```

### Registering an email template schema

```python
# plugins/ghrm/__init__.py  (in on_enable)
def on_enable(self) -> None:
    from plugins.email.src.services.event_context_registry import EventContextRegistry
    EventContextRegistry.register("ghrm.access_granted", {
        "description": "Sent when GitHub repo access is granted",
        "variables": {
            "user_email":    {"type": "string", "example": "alice@example.com",
                              "description": "Recipient address"},
            "package_name":  {"type": "string", "example": "vbwd-backend",
                              "description": "Software package name"},
            "github_invite": {"type": "string", "example": "https://github.com/...",
                              "description": "GitHub collaborator invitation URL"},
        },
    })
```

After this call, `GET /api/v1/admin/email/event-types` will include `ghrm.access_granted` in its response, and the email template editor will show the variable hints.

---

## 8. What Stays the Same

The following things were **not changed** by Sprint 09 and continue to work exactly as before:

- **`IEventHandler` objects** — still registered with `DomainEventDispatcher.register(event_name, handler)` and still receive typed `DomainEvent` instances via `handle(event)`.
- **`DomainEventDispatcher.emit()` call sites** — no service files were modified. The bridge is purely additive inside `emit()`.
- **Typed event classes** (`SubscriptionActivatedEvent`, `PaymentCompletedEvent`, etc.) — unchanged.
- **`EventDispatcher`** (`src/events/dispatcher.py`) — the old plugin bus is still present for backwards compatibility. New plugins should use `EventBus` instead.
- **Plugin status lifecycle** — `DISCOVERED → REGISTERED → INITIALIZED → ENABLED` — unchanged. `register_event_handlers()` is called at the end of the `ENABLED` transition.
