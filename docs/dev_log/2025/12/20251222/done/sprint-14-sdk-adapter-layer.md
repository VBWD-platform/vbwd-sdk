# Sprint 14: SDK Adapter Layer

**Priority:** HIGH
**Estimated Tests:** 30-35
**Dependencies:** Sprint 13

---

## Objective

Implement the SDK Adapter Layer abstraction for payment providers. This layer wraps provider APIs with idempotency checking, retry logic, and consistent error handling.

---

## Core Requirements Checklist

- [ ] **TDD**: Write tests FIRST, then implement
- [ ] **SOLID**: Interfaces for adapters, single responsibility per class
- [ ] **Liskov Interface**: All adapters implement ISDKAdapter, fully substitutable
- [ ] **Clean Code**: Clear naming, small methods, self-documenting
- [ ] **No Over-Engineering**: Implement Stripe adapter only, PayPal as interface stub
- [ ] **Dockerized Tests**: All tests run via `make test`

---

## Deliverables

### 1. IdempotencyService (TDD)

**Test First:**
```python
# tests/unit/services/test_idempotency_service.py
def test_check_key_returns_none_for_new():
    """New key returns None."""

def test_check_key_returns_cached_response():
    """Existing key returns cached response."""

def test_store_saves_response():
    """store() caches response with TTL."""

def test_generate_key_creates_unique():
    """generate_key() creates deterministic key from inputs."""

def test_key_expires_after_ttl():
    """Keys expire after configured TTL."""

def test_concurrent_requests_handled():
    """First request wins, others get cached response."""
```

**Implementation:**
```python
# src/services/idempotency_service.py
class IdempotencyService:
    """Manages idempotency keys for SDK requests."""

    DEFAULT_TTL = 86400  # 24 hours

    def __init__(self, redis_client: Redis):
        self._redis = redis_client

    def generate_key(self, provider: str, operation: str, *args) -> str:
        """Generate deterministic idempotency key."""
        data = f"{provider}:{operation}:{':'.join(str(a) for a in args)}"
        return hashlib.sha256(data.encode()).hexdigest()[:32]

    def check(self, key: str) -> Optional[Dict[str, Any]]:
        """Check if response exists for key."""
        cached = self._redis.get(f"idempotency:{key}")
        return json.loads(cached) if cached else None

    def store(self, key: str, response: Dict[str, Any], ttl: int = None) -> None:
        """Store response with TTL."""
        self._redis.setex(
            f"idempotency:{key}",
            ttl or self.DEFAULT_TTL,
            json.dumps(response)
        )
```

**SOLID:** Single Responsibility - only handles idempotency
**File:** `src/services/idempotency_service.py`
**Tests:** `tests/unit/services/test_idempotency_service.py` (10 tests)

---

### 2. ISDKAdapter Interface (TDD)

**Test First:**
```python
# tests/unit/sdk/test_sdk_adapter_interface.py
def test_adapter_has_create_payment_intent():
    """Adapter must implement create_payment_intent."""

def test_adapter_has_capture_payment():
    """Adapter must implement capture_payment."""

def test_adapter_has_refund_payment():
    """Adapter must implement refund_payment."""

def test_adapter_has_get_payment_status():
    """Adapter must implement get_payment_status."""
```

**Implementation:**
```python
# src/sdk/interface.py
@dataclass
class SDKConfig:
    """SDK configuration."""
    api_key: str
    api_secret: Optional[str] = None
    sandbox: bool = True
    timeout: int = 30
    max_retries: int = 3

@dataclass
class SDKResponse:
    """Standardized SDK response."""
    success: bool
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    error_code: Optional[str] = None
    provider_response: Optional[Dict[str, Any]] = None

class ISDKAdapter(ABC):
    """Interface for payment provider SDK adapters (Liskov-compliant)."""

    @abstractmethod
    def create_payment_intent(
        self,
        amount: Decimal,
        currency: str,
        metadata: Dict[str, Any],
        idempotency_key: Optional[str] = None
    ) -> SDKResponse: ...

    @abstractmethod
    def capture_payment(
        self,
        payment_intent_id: str,
        idempotency_key: Optional[str] = None
    ) -> SDKResponse: ...

    @abstractmethod
    def refund_payment(
        self,
        payment_intent_id: str,
        amount: Optional[Decimal] = None,
        idempotency_key: Optional[str] = None
    ) -> SDKResponse: ...

    @abstractmethod
    def get_payment_status(self, payment_intent_id: str) -> SDKResponse: ...
```

**Liskov:** Any adapter implementing ISDKAdapter is substitutable
**File:** `src/sdk/interface.py`
**Tests:** `tests/unit/sdk/test_sdk_adapter_interface.py` (5 tests)

---

### 3. BaseSDKAdapter (TDD)

**Test First:**
```python
# tests/unit/sdk/test_base_adapter.py
def test_base_adapter_checks_idempotency():
    """Base adapter checks idempotency before calling provider."""

def test_base_adapter_retries_on_failure():
    """Base adapter retries transient failures."""

def test_base_adapter_stores_successful_response():
    """Successful responses are cached for idempotency."""

def test_base_adapter_handles_timeout():
    """Timeouts are handled gracefully."""

def test_base_adapter_logs_requests():
    """All requests are logged for debugging."""
```

**Implementation:**
```python
# src/sdk/base.py
class BaseSDKAdapter(ISDKAdapter):
    """Base adapter with common functionality."""

    def __init__(
        self,
        config: SDKConfig,
        idempotency_service: IdempotencyService,
        logger: Optional[Logger] = None
    ):
        self._config = config
        self._idempotency = idempotency_service
        self._logger = logger or logging.getLogger(__name__)

    def _with_idempotency(
        self,
        key: Optional[str],
        operation: Callable[[], SDKResponse]
    ) -> SDKResponse:
        """Execute operation with idempotency check."""
        if key:
            cached = self._idempotency.check(key)
            if cached:
                return SDKResponse(**cached)

        response = self._with_retry(operation)

        if key and response.success:
            self._idempotency.store(key, asdict(response))

        return response

    def _with_retry(
        self,
        operation: Callable[[], SDKResponse],
        max_retries: Optional[int] = None
    ) -> SDKResponse:
        """Execute with exponential backoff retry."""
        retries = max_retries or self._config.max_retries
        for attempt in range(retries):
            try:
                return operation()
            except TransientError:
                if attempt == retries - 1:
                    raise
                time.sleep(2 ** attempt)  # Exponential backoff
```

**SOLID:** Open/Closed - extend without modifying base
**File:** `src/sdk/base.py`
**Tests:** `tests/unit/sdk/test_base_adapter.py` (8 tests)

---

### 4. StripeSDKAdapter (TDD)

**Test First:**
```python
# tests/unit/sdk/test_stripe_adapter.py
def test_create_payment_intent_calls_stripe():
    """create_payment_intent calls Stripe API."""

def test_create_payment_intent_with_idempotency():
    """Idempotency key passed to Stripe."""

def test_capture_payment_success():
    """Successful capture returns payment data."""

def test_refund_payment_partial():
    """Partial refund works correctly."""

def test_handles_stripe_errors():
    """Stripe errors mapped to SDKResponse."""

def test_sandbox_uses_test_api():
    """Sandbox mode uses Stripe test API."""
```

**Implementation:**
```python
# src/sdk/stripe_adapter.py
class StripeSDKAdapter(BaseSDKAdapter):
    """Stripe SDK adapter."""

    PROVIDER_NAME = "stripe"

    def __init__(
        self,
        config: SDKConfig,
        idempotency_service: IdempotencyService
    ):
        super().__init__(config, idempotency_service)
        import stripe
        stripe.api_key = config.api_key

    def create_payment_intent(
        self,
        amount: Decimal,
        currency: str,
        metadata: Dict[str, Any],
        idempotency_key: Optional[str] = None
    ) -> SDKResponse:
        def _create():
            intent = stripe.PaymentIntent.create(
                amount=int(amount * 100),  # Stripe uses cents
                currency=currency.lower(),
                metadata=metadata,
                idempotency_key=idempotency_key
            )
            return SDKResponse(
                success=True,
                data={"payment_intent_id": intent.id, "client_secret": intent.client_secret}
            )

        return self._with_idempotency(idempotency_key, _create)
```

**File:** `src/sdk/stripe_adapter.py`
**Tests:** `tests/unit/sdk/test_stripe_adapter.py` (10 tests)

---

### 5. SDKAdapterRegistry (TDD)

**Test First:**
```python
# tests/unit/sdk/test_adapter_registry.py
def test_register_adapter():
    """Register adapter by provider name."""

def test_get_adapter_returns_registered():
    """Get returns registered adapter."""

def test_get_adapter_raises_for_unknown():
    """Unknown provider raises ValueError."""

def test_list_providers():
    """list_providers returns all registered names."""
```

**Implementation:**
```python
# src/sdk/registry.py
class SDKAdapterRegistry:
    """Registry for SDK adapters."""

    def __init__(self):
        self._adapters: Dict[str, ISDKAdapter] = {}

    def register(self, provider: str, adapter: ISDKAdapter) -> None:
        """Register adapter for provider."""
        self._adapters[provider] = adapter

    def get(self, provider: str) -> ISDKAdapter:
        """Get adapter by provider name."""
        if provider not in self._adapters:
            raise ValueError(f"Unknown provider: {provider}")
        return self._adapters[provider]

    def list_providers(self) -> List[str]:
        """List registered providers."""
        return list(self._adapters.keys())
```

**File:** `src/sdk/registry.py`
**Tests:** `tests/unit/sdk/test_adapter_registry.py` (5 tests)

---

### 6. MockSDKAdapter for Testing (TDD)

**Test First:**
```python
# tests/unit/sdk/test_mock_adapter.py
def test_mock_adapter_succeeds_by_default():
    """Mock adapter returns success by default."""

def test_mock_adapter_can_fail():
    """Mock adapter can be configured to fail."""

def test_mock_adapter_tracks_calls():
    """Mock adapter tracks all method calls."""
```

**Implementation:**
```python
# src/sdk/mock_adapter.py
class MockSDKAdapter(ISDKAdapter):
    """Mock adapter for testing."""

    def __init__(self, should_fail: bool = False):
        self._should_fail = should_fail
        self._calls: List[Dict] = []

    def create_payment_intent(self, amount, currency, metadata, idempotency_key=None):
        self._calls.append({"method": "create_payment_intent", "amount": amount})
        if self._should_fail:
            return SDKResponse(success=False, error="Mock failure")
        return SDKResponse(
            success=True,
            data={"payment_intent_id": f"pi_mock_{uuid4().hex[:8]}"}
        )
```

**File:** `src/sdk/mock_adapter.py`
**Tests:** `tests/unit/sdk/test_mock_adapter.py` (5 tests)

---

## File Structure

```
src/
├── services/
│   └── idempotency_service.py
└── sdk/
    ├── __init__.py
    ├── interface.py       # ISDKAdapter, SDKConfig, SDKResponse
    ├── base.py            # BaseSDKAdapter
    ├── registry.py        # SDKAdapterRegistry
    ├── stripe_adapter.py  # StripeSDKAdapter
    └── mock_adapter.py    # MockSDKAdapter (testing)

tests/unit/
├── services/
│   └── test_idempotency_service.py
└── sdk/
    ├── test_sdk_adapter_interface.py
    ├── test_base_adapter.py
    ├── test_stripe_adapter.py
    ├── test_adapter_registry.py
    └── test_mock_adapter.py
```

---

## TDD Workflow

```bash
# Run idempotency tests
docker-compose run --rm python-test pytest tests/unit/services/test_idempotency_service.py -v

# Run SDK adapter tests
docker-compose run --rm python-test pytest tests/unit/sdk/ -v

# Run with coverage
docker-compose run --rm python-test pytest tests/unit/sdk/ --cov=src/sdk --cov-report=term-missing
```

---

## Acceptance Criteria

- [ ] All tests pass: `make test`
- [ ] IdempotencyService prevents duplicate API calls
- [ ] All adapters implement ISDKAdapter (Liskov)
- [ ] Stripe adapter works in sandbox mode
- [ ] Retry logic handles transient failures
- [ ] Registry manages adapter instances
- [ ] Test coverage > 90%

---

## Notes

**No Over-Engineering:**
- Only implement StripeSDKAdapter fully
- PayPalSDKAdapter is a stub (interface only) for future sprint
- KlarnaSDKAdapter not needed yet

**Dependencies:**
- `stripe` Python package for StripeSDKAdapter
- Redis for IdempotencyService

---

**Estimated Duration:** 3-4 hours
**Test Count Target:** 30-35 tests
