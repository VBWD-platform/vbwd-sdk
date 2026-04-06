# Sprint 13: Event System Core Enhancement

**Priority:** HIGH
**Estimated Tests:** 25-30
**Dependencies:** Sprint 4, Sprint 11-12

---

## Objective

Enhance the existing event system with advanced features from the payment architecture specification: EventContext for request-scoped data, priority-based handler execution, and lazy handler initialization.

---

## Core Requirements Checklist

- [ ] **TDD**: Write tests FIRST, then implement
- [ ] **SOLID**: Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion
- [ ] **Liskov Interface**: All handlers implement IEventHandler, substitutable
- [ ] **Clean Code**: Meaningful names, small functions, no comments explaining bad code
- [ ] **No Over-Engineering**: Only implement what's needed NOW
- [ ] **Dockerized Tests**: All tests run via `make test` or `docker-compose run --rm python-test`

---

## Deliverables

### 1. EventInterface Protocol (TDD)

**Test First:**
```python
# tests/unit/events/test_event_interface.py
def test_event_interface_has_name():
    """EventInterface requires name property."""

def test_event_interface_has_data():
    """EventInterface requires data property."""

def test_event_interface_has_stop_propagation():
    """EventInterface requires stop_propagation method."""
```

**Implementation:**
```python
# src/events/core/interfaces.py
class EventInterface(Protocol):
    """Protocol for all events (Liskov-compliant)."""
    name: str
    data: Dict[str, Any]

    def stop_propagation(self) -> None: ...
    def is_propagation_stopped(self) -> bool: ...
```

**File:** `src/events/core/interfaces.py`
**Tests:** `tests/unit/events/test_event_interface.py`

---

### 2. EventContext (TDD)

**Test First:**
```python
# tests/unit/events/test_event_context.py
def test_context_stores_request_scoped_data():
    """Context stores data for current request."""

def test_context_get_or_compute_caches():
    """get_or_compute only calls factory once."""

def test_context_clear_removes_all():
    """clear() removes all cached data."""

def test_context_isolation_between_requests():
    """Different requests have isolated contexts."""
```

**Implementation:**
```python
# src/events/core/context.py
class EventContext:
    """Request-scoped cache for event processing."""

    def __init__(self):
        self._cache: Dict[str, Any] = {}

    def get(self, key: str) -> Optional[Any]: ...
    def set(self, key: str, value: Any) -> None: ...
    def get_or_compute(self, key: str, factory: Callable) -> Any: ...
    def clear(self) -> None: ...
```

**SOLID:** Single Responsibility - only handles request-scoped caching
**File:** `src/events/core/context.py`
**Tests:** `tests/unit/events/test_event_context.py` (8-10 tests)

---

### 3. HandlerPriority Constants (TDD)

**Test First:**
```python
# tests/unit/events/test_handler_priority.py
def test_highest_is_100():
    assert HandlerPriority.HIGHEST == 100

def test_priority_ordering():
    """HIGHEST > HIGH > NORMAL > LOW > LOWEST."""
    assert HandlerPriority.HIGHEST > HandlerPriority.HIGH
```

**Implementation:**
```python
# src/events/core/handler.py
class HandlerPriority:
    """Handler priority constants (higher = executes first)."""
    HIGHEST = 100
    HIGH = 75
    NORMAL = 50
    LOW = 25
    LOWEST = 0
```

**File:** `src/events/core/handler.py`
**Tests:** `tests/unit/events/test_handler_priority.py` (5 tests)

---

### 4. IEventHandler Interface Enhancement (TDD)

**Test First:**
```python
# tests/unit/events/test_event_handler_interface.py
def test_handler_has_get_handled_event_class():
    """Handler must declare which event class it handles."""

def test_handler_has_get_priority():
    """Handler returns priority (default NORMAL)."""

def test_handler_has_can_handle():
    """Handler checks if it can handle specific event."""

def test_handler_has_handle():
    """Handler processes event and returns result."""
```

**Implementation:**
```python
# src/events/core/handler.py
class IEventHandler(ABC):
    """Interface for event handlers (Liskov-compliant)."""

    @staticmethod
    @abstractmethod
    def get_handled_event_class() -> str:
        """Return event class name this handler handles."""
        pass

    @staticmethod
    def get_priority() -> int:
        """Return handler priority (default NORMAL)."""
        return HandlerPriority.NORMAL

    @abstractmethod
    def can_handle(self, event: EventInterface) -> bool:
        """Check if handler can process this event."""
        pass

    @abstractmethod
    def handle(self, event: EventInterface) -> EventResult:
        """Process event and return result."""
        pass
```

**Liskov:** Any handler implementing IEventHandler is substitutable
**File:** `src/events/core/handler.py`
**Tests:** `tests/unit/events/test_event_handler_interface.py` (6 tests)

---

### 5. AbstractHandler Base Class (TDD)

**Test First:**
```python
# tests/unit/events/test_abstract_handler.py
def test_abstract_handler_provides_emit():
    """AbstractHandler provides emit() for event chaining."""

def test_abstract_handler_emit_uses_dispatcher():
    """emit() delegates to injected dispatcher."""

def test_abstract_handler_default_priority():
    """Default priority is NORMAL."""
```

**Implementation:**
```python
# src/events/core/base_handler.py
class AbstractHandler(IEventHandler):
    """Base handler with common functionality."""

    def __init__(self, dispatcher: Optional['EventDispatcher'] = None):
        self._dispatcher = dispatcher

    def emit(self, event: EventInterface) -> EventResult:
        """Emit event via dispatcher (for event chaining)."""
        if self._dispatcher:
            return self._dispatcher.dispatch(event)
        return EventResult.no_handler_result()

    @staticmethod
    def get_priority() -> int:
        return HandlerPriority.NORMAL
```

**SOLID:** Open/Closed - extend without modifying
**File:** `src/events/core/base_handler.py`
**Tests:** `tests/unit/events/test_abstract_handler.py` (5 tests)

---

### 6. EventDispatcher Enhancement (TDD)

**Test First:**
```python
# tests/unit/events/test_enhanced_dispatcher.py
def test_dispatch_sorts_by_priority():
    """Handlers execute in priority order (highest first)."""

def test_dispatch_stops_on_propagation_stopped():
    """Stops calling handlers after stop_propagation()."""

def test_dispatch_with_context():
    """Dispatcher passes context to handlers."""

def test_register_lazy_handler():
    """Lazy handlers initialized on first dispatch."""
```

**Implementation:**
```python
# src/events/core/dispatcher.py
class EventDispatcher:
    """Priority-based event dispatcher."""

    def __init__(self, context: Optional[EventContext] = None):
        self._handlers: Dict[str, List[Tuple[int, IEventHandler]]] = {}
        self._context = context or EventContext()

    def register(self, handler: IEventHandler) -> None:
        """Register handler (sorted by priority)."""
        event_class = handler.get_handled_event_class()
        priority = handler.get_priority()
        # Insert sorted by priority (descending)

    def dispatch(self, event: EventInterface) -> EventResult:
        """Dispatch event to registered handlers."""
        results = []
        for priority, handler in self._handlers.get(event.name, []):
            if event.is_propagation_stopped():
                break
            if handler.can_handle(event):
                results.append(handler.handle(event))
        return EventResult.combine(results)
```

**File:** `src/events/core/dispatcher.py`
**Tests:** `tests/unit/events/test_enhanced_dispatcher.py` (10 tests)

---

## File Structure

```
src/events/core/
├── __init__.py
├── interfaces.py      # EventInterface protocol
├── context.py         # EventContext
├── handler.py         # IEventHandler, HandlerPriority
├── base_handler.py    # AbstractHandler
└── dispatcher.py      # EventDispatcher

tests/unit/events/
├── test_event_interface.py
├── test_event_context.py
├── test_handler_priority.py
├── test_event_handler_interface.py
├── test_abstract_handler.py
└── test_enhanced_dispatcher.py
```

---

## TDD Workflow

1. **RED**: Write failing test
2. **GREEN**: Write minimal code to pass
3. **REFACTOR**: Clean up, maintain SOLID

```bash
# Run single test file during development
docker-compose run --rm python-test pytest tests/unit/events/test_event_context.py -v

# Run all event tests
docker-compose run --rm python-test pytest tests/unit/events/ -v

# Run with coverage
docker-compose run --rm python-test pytest tests/unit/events/ --cov=src/events/core --cov-report=term-missing
```

---

## Acceptance Criteria

- [ ] All tests pass: `make test`
- [ ] EventContext caches request-scoped data
- [ ] Handlers sorted by priority (HIGHEST first)
- [ ] Propagation stops when requested
- [ ] All handlers implement IEventHandler (Liskov)
- [ ] No circular dependencies
- [ ] Test coverage > 90%

---

## Definition of Done

1. All tests written FIRST (TDD)
2. All tests pass in Docker
3. Code follows SOLID principles
4. Interfaces are Liskov-compliant
5. No over-engineering (only what's needed)
6. Clean, readable code
7. Sprint report generated

---

**Estimated Duration:** 2-3 hours
**Test Count Target:** 25-30 tests
