# Sprint 15: Webhook System Core

**Priority:** HIGH
**Estimated Tests:** 25-30
**Dependencies:** Sprint 13, Sprint 14

---

## Objective

Implement the webhook system core: database model with Alembic migration, webhook repository, service layer, and base handler interface. This provides the foundation for provider-specific webhook handlers.

---

## Core Requirements Checklist

- [ ] **TDD**: Write tests FIRST, then implement
- [ ] **SOLID**: Repository pattern, handler interface segregation
- [ ] **Liskov Interface**: All webhook handlers implement IWebhookHandler
- [ ] **Clean Code**: Clear separation of concerns
- [ ] **No Over-Engineering**: Only core system, provider handlers in next sprint
- [ ] **Dockerized Tests**: All tests run via `make test`

---

## Deliverables

### 1. Webhook Model (TDD)

**Test First:**
```python
# tests/unit/models/test_webhook_model.py
def test_webhook_has_required_fields():
    """Webhook has provider, event_id, event_type, payload."""

def test_webhook_has_status_enum():
    """Webhook status uses WebhookStatus enum."""

def test_webhook_has_timestamps():
    """Webhook has created_at, processed_at."""

def test_webhook_has_foreign_keys():
    """Webhook can link to invoice, subscription, user."""

def test_webhook_inherits_base_model():
    """Webhook inherits UUID, version from BaseModel."""
```

**Implementation:**
```python
# src/models/webhook.py
from src.models.base import BaseModel
from src.models.enums import WebhookStatus

class Webhook(BaseModel):
    """Webhook event record."""
    __tablename__ = 'webhooks'

    provider = db.Column(db.String(50), nullable=False, index=True)
    event_id = db.Column(db.String(255), nullable=False)
    event_type = db.Column(db.String(100), nullable=False, index=True)
    payload = db.Column(JSONB, nullable=False, default={})
    headers = db.Column(JSONB, nullable=False, default={})
    status = db.Column(
        SQLEnum(WebhookStatus),
        nullable=False,
        default=WebhookStatus.RECEIVED,
        index=True
    )
    error_message = db.Column(db.Text)
    processed_at = db.Column(db.DateTime)
    retry_count = db.Column(db.Integer, default=0)

    # Optional foreign keys (set after processing)
    invoice_id = db.Column(UUID(as_uuid=True), db.ForeignKey('user_invoice.id'))
    subscription_id = db.Column(UUID(as_uuid=True), db.ForeignKey('subscription.id'))
    user_id = db.Column(UUID(as_uuid=True), db.ForeignKey('user.id'))

    # Unique constraint: prevent duplicate processing
    __table_args__ = (
        db.UniqueConstraint('provider', 'event_id', name='uq_webhook_provider_event'),
    )
```

**File:** `src/models/webhook.py`
**Tests:** `tests/unit/models/test_webhook_model.py` (6 tests)

---

### 2. WebhookStatus Enum (TDD)

**Test First:**
```python
# tests/unit/models/test_webhook_enums.py
def test_webhook_status_has_received():
    assert WebhookStatus.RECEIVED.value == 'received'

def test_webhook_status_has_processing():
    assert WebhookStatus.PROCESSING.value == 'processing'

def test_webhook_status_has_processed():
    assert WebhookStatus.PROCESSED.value == 'processed'

def test_webhook_status_has_failed():
    assert WebhookStatus.FAILED.value == 'failed'
```

**Implementation:**
```python
# src/models/enums.py (add to existing)
class WebhookStatus(enum.Enum):
    """Webhook processing status."""
    RECEIVED = 'received'
    PROCESSING = 'processing'
    PROCESSED = 'processed'
    FAILED = 'failed'
    SKIPPED = 'skipped'  # Duplicate or irrelevant
```

**File:** `src/models/enums.py`
**Tests:** `tests/unit/models/test_webhook_enums.py` (5 tests)

---

### 3. Alembic Migration (TDD)

**Test First:**
```python
# tests/integration/test_webhook_migration.py
def test_webhook_table_exists():
    """Webhook table created by migration."""

def test_webhook_has_correct_columns():
    """All columns exist with correct types."""

def test_webhook_unique_constraint():
    """Unique constraint on provider + event_id."""

def test_webhook_foreign_keys():
    """Foreign keys to invoice, subscription, user."""
```

**Implementation:**
```python
# alembic/versions/YYYYMMDD_HHMM_add_webhook_table.py
def upgrade():
    op.create_table(
        'webhooks',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('version', sa.Integer, nullable=False, default=1),
        sa.Column('provider', sa.String(50), nullable=False),
        sa.Column('event_id', sa.String(255), nullable=False),
        sa.Column('event_type', sa.String(100), nullable=False),
        sa.Column('payload', JSONB, nullable=False, server_default='{}'),
        sa.Column('headers', JSONB, nullable=False, server_default='{}'),
        sa.Column('status', sa.Enum(WebhookStatus), nullable=False),
        sa.Column('error_message', sa.Text),
        sa.Column('processed_at', sa.DateTime),
        sa.Column('retry_count', sa.Integer, default=0),
        sa.Column('invoice_id', UUID(as_uuid=True), sa.ForeignKey('user_invoice.id')),
        sa.Column('subscription_id', UUID(as_uuid=True), sa.ForeignKey('subscription.id')),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('user.id')),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, onupdate=sa.func.now()),
    )
    op.create_unique_constraint('uq_webhook_provider_event', 'webhooks', ['provider', 'event_id'])
    op.create_index('ix_webhooks_provider', 'webhooks', ['provider'])
    op.create_index('ix_webhooks_event_type', 'webhooks', ['event_type'])
    op.create_index('ix_webhooks_status', 'webhooks', ['status'])
```

**File:** `alembic/versions/YYYYMMDD_HHMM_add_webhook_table.py`
**Tests:** `tests/integration/test_webhook_migration.py` (4 tests)

---

### 4. WebhookRepository (TDD)

**Test First:**
```python
# tests/unit/repositories/test_webhook_repository.py
def test_create_webhook():
    """Create new webhook record."""

def test_find_by_provider_event_id():
    """Find webhook by provider and event_id."""

def test_find_by_status():
    """Find webhooks by status."""

def test_update_status():
    """Update webhook status and processed_at."""

def test_find_failed_for_retry():
    """Find failed webhooks eligible for retry."""

def test_mark_as_processed():
    """Mark webhook as processed."""
```

**Implementation:**
```python
# src/repositories/webhook_repository.py
class WebhookRepository(BaseRepository[Webhook]):
    """Repository for webhook operations."""

    def __init__(self, session: Session):
        super().__init__(Webhook, session)

    def find_by_provider_event_id(self, provider: str, event_id: str) -> Optional[Webhook]:
        """Find webhook by provider and external event ID."""
        return self._session.query(Webhook).filter(
            Webhook.provider == provider,
            Webhook.event_id == event_id
        ).first()

    def find_by_status(self, status: WebhookStatus, limit: int = 100) -> List[Webhook]:
        """Find webhooks by status."""
        return self._session.query(Webhook).filter(
            Webhook.status == status
        ).limit(limit).all()

    def find_failed_for_retry(self, max_retries: int = 3) -> List[Webhook]:
        """Find failed webhooks eligible for retry."""
        return self._session.query(Webhook).filter(
            Webhook.status == WebhookStatus.FAILED,
            Webhook.retry_count < max_retries
        ).all()

    def mark_as_processed(self, webhook_id: UUID) -> None:
        """Mark webhook as successfully processed."""
        webhook = self.find_by_id(webhook_id)
        if webhook:
            webhook.status = WebhookStatus.PROCESSED
            webhook.processed_at = datetime.utcnow()
```

**File:** `src/repositories/webhook_repository.py`
**Tests:** `tests/unit/repositories/test_webhook_repository.py` (8 tests)

---

### 5. NormalizedWebhookEvent DTO (TDD)

**Test First:**
```python
# tests/unit/webhooks/test_webhook_dto.py
def test_normalized_event_has_type():
    """NormalizedWebhookEvent has event_type."""

def test_normalized_event_has_provider():
    """NormalizedWebhookEvent has provider."""

def test_normalized_event_has_data():
    """NormalizedWebhookEvent has normalized data."""

def test_from_stripe_event():
    """Create from Stripe webhook payload."""
```

**Implementation:**
```python
# src/webhooks/dto.py
@dataclass
class NormalizedWebhookEvent:
    """Provider-agnostic webhook event."""
    provider: str
    event_id: str
    event_type: WebhookEventType
    payment_intent_id: Optional[str] = None
    subscription_id: Optional[UUID] = None
    user_id: Optional[UUID] = None
    amount: Optional[Decimal] = None
    currency: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    raw_payload: Dict[str, Any] = field(default_factory=dict)

class WebhookEventType(enum.Enum):
    """Normalized webhook event types."""
    PAYMENT_SUCCEEDED = 'payment.succeeded'
    PAYMENT_FAILED = 'payment.failed'
    SUBSCRIPTION_CREATED = 'subscription.created'
    SUBSCRIPTION_UPDATED = 'subscription.updated'
    SUBSCRIPTION_CANCELLED = 'subscription.cancelled'
    REFUND_CREATED = 'refund.created'
    DISPUTE_CREATED = 'dispute.created'
    UNKNOWN = 'unknown'
```

**File:** `src/webhooks/dto.py`
**Tests:** `tests/unit/webhooks/test_webhook_dto.py` (5 tests)

---

### 6. IWebhookHandler Interface (TDD)

**Test First:**
```python
# tests/unit/webhooks/test_webhook_handler_interface.py
def test_handler_has_provider():
    """Handler declares which provider it handles."""

def test_handler_has_verify_signature():
    """Handler can verify webhook signature."""

def test_handler_has_parse_event():
    """Handler parses raw payload to NormalizedWebhookEvent."""

def test_handler_has_handle():
    """Handler processes normalized event."""
```

**Implementation:**
```python
# src/webhooks/handlers/base.py
class IWebhookHandler(ABC):
    """Interface for webhook handlers (Liskov-compliant)."""

    @property
    @abstractmethod
    def provider(self) -> str:
        """Provider name this handler supports."""
        pass

    @abstractmethod
    def verify_signature(self, payload: bytes, signature: str, secret: str) -> bool:
        """Verify webhook signature."""
        pass

    @abstractmethod
    def parse_event(self, payload: Dict[str, Any]) -> NormalizedWebhookEvent:
        """Parse raw payload to normalized event."""
        pass

    @abstractmethod
    def handle(self, event: NormalizedWebhookEvent) -> WebhookResult:
        """Process the normalized event."""
        pass

@dataclass
class WebhookResult:
    """Result of webhook processing."""
    success: bool
    message: Optional[str] = None
    error: Optional[str] = None
```

**Liskov:** Any handler implementing IWebhookHandler is substitutable
**File:** `src/webhooks/handlers/base.py`
**Tests:** `tests/unit/webhooks/test_webhook_handler_interface.py` (5 tests)

---

### 7. WebhookService (TDD)

**Test First:**
```python
# tests/unit/services/test_webhook_service.py
def test_process_webhook_verifies_signature():
    """Signature verified before processing."""

def test_process_webhook_checks_duplicate():
    """Duplicate events are skipped."""

def test_process_webhook_stores_record():
    """Webhook stored in database."""

def test_process_webhook_dispatches_event():
    """Domain event dispatched after processing."""

def test_process_webhook_handles_failure():
    """Failures are logged and recorded."""
```

**Implementation:**
```python
# src/webhooks/service.py
class WebhookService:
    """Core webhook processing service."""

    def __init__(
        self,
        repository: WebhookRepository,
        event_dispatcher: EventDispatcher,
        handlers: Dict[str, IWebhookHandler]
    ):
        self._repository = repository
        self._dispatcher = event_dispatcher
        self._handlers = handlers

    def process(
        self,
        provider: str,
        payload: bytes,
        signature: str,
        headers: Dict[str, str]
    ) -> WebhookResult:
        """Process incoming webhook."""
        handler = self._handlers.get(provider)
        if not handler:
            return WebhookResult(success=False, error=f"Unknown provider: {provider}")

        # Verify signature
        secret = self._get_webhook_secret(provider)
        if not handler.verify_signature(payload, signature, secret):
            return WebhookResult(success=False, error="Invalid signature")

        # Parse payload
        data = json.loads(payload)
        event = handler.parse_event(data)

        # Check duplicate
        existing = self._repository.find_by_provider_event_id(provider, event.event_id)
        if existing:
            return WebhookResult(success=True, message="Duplicate event, skipped")

        # Store webhook record
        webhook = Webhook(
            provider=provider,
            event_id=event.event_id,
            event_type=event.event_type.value,
            payload=data,
            headers=headers,
            status=WebhookStatus.PROCESSING
        )
        self._repository.create(webhook)

        # Process via handler
        result = handler.handle(event)

        # Update status
        webhook.status = WebhookStatus.PROCESSED if result.success else WebhookStatus.FAILED
        if not result.success:
            webhook.error_message = result.error

        return result
```

**File:** `src/webhooks/service.py`
**Tests:** `tests/unit/services/test_webhook_service.py` (8 tests)

---

## File Structure

```
src/
├── models/
│   ├── enums.py           # Add WebhookStatus
│   └── webhook.py         # Webhook model
├── repositories/
│   └── webhook_repository.py
├── webhooks/
│   ├── __init__.py
│   ├── dto.py             # NormalizedWebhookEvent, WebhookEventType
│   ├── service.py         # WebhookService
│   └── handlers/
│       ├── __init__.py
│       └── base.py        # IWebhookHandler, WebhookResult
└── alembic/versions/
    └── YYYYMMDD_HHMM_add_webhook_table.py

tests/unit/
├── models/
│   ├── test_webhook_model.py
│   └── test_webhook_enums.py
├── repositories/
│   └── test_webhook_repository.py
├── webhooks/
│   ├── test_webhook_dto.py
│   └── test_webhook_handler_interface.py
└── services/
    └── test_webhook_service.py
```

---

## TDD Workflow

```bash
# Run model tests
docker-compose run --rm python-test pytest tests/unit/models/test_webhook_model.py -v

# Run repository tests
docker-compose run --rm python-test pytest tests/unit/repositories/test_webhook_repository.py -v

# Run service tests
docker-compose run --rm python-test pytest tests/unit/services/test_webhook_service.py -v

# Run all webhook tests
docker-compose run --rm python-test pytest tests/unit/webhooks/ tests/unit/services/test_webhook_service.py -v
```

---

## Acceptance Criteria

- [ ] All tests pass: `make test`
- [ ] Webhook model with UUID primary key
- [ ] Migration applies cleanly
- [ ] Repository handles CRUD operations
- [ ] Service verifies signatures
- [ ] Duplicate detection works
- [ ] All handlers implement IWebhookHandler (Liskov)
- [ ] Test coverage > 90%

---

**Estimated Duration:** 3-4 hours
**Test Count Target:** 25-30 tests
