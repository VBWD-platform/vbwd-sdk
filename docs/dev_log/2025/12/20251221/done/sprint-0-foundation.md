# Sprint 0: Foundation

**Goal:** Establish project structure, Docker configuration, CI pipeline, and base abstractions.

---

## Objectives

- [x] Docker configuration for Python API
- [ ] Flask application factory pattern
- [ ] Base interfaces (ISP compliance)
- [ ] DI container setup
- [ ] Test infrastructure
- [ ] Database connection and migrations
- [ ] CI pipeline configuration

---

## Tasks

### 0.1 Docker Configuration

**File:** `container/python/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY api/ .

# Set Python path
ENV PYTHONPATH=/app/src

# Default command
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "src.app:create_app()"]
```

**File:** `docker-compose.yml` (python service)

```yaml
services:
  python:
    build:
      context: ./python
      dockerfile: ../container/python/Dockerfile
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=development
      - DATABASE_URL=postgresql://user:password@postgres:5432/vbwd
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - ./python/api:/app
      - ./data/python/logs:/app/logs
    depends_on:
      - postgres
    command: ["flask", "run", "--host=0.0.0.0", "--reload"]
```

---

### 0.2 Requirements

**File:** `python/api/requirements.txt`

```txt
# Core
Flask==3.0.0
gunicorn==21.2.0

# Database
SQLAlchemy==2.0.23
Flask-SQLAlchemy==3.1.1
psycopg2-binary==2.9.9
cryptography==41.0.7
alembic==1.13.0

# Authentication
PyJWT==2.8.0
bcrypt==4.1.1

# Validation
marshmallow==3.20.1
email-validator==2.1.0

# DI Container
dependency-injector==4.41.0

# Testing
pytest==7.4.3
pytest-cov==4.1.0
pytest-mock==3.12.0
factory-boy==3.3.0
faker==21.0.0

# Code Quality
flake8==6.1.0
mypy==1.7.1
black==23.12.0

# HTTP Client (for payment gateways)
httpx==0.25.2

# Environment
python-dotenv==1.0.0
```

---

### 0.3 Flask Application Factory

**TDD Steps:**

#### Step 1: Write failing test

**File:** `python/api/tests/unit/test_app.py`

```python
"""Tests for Flask application factory."""
import pytest


class TestAppFactory:
    """Test cases for create_app factory function."""

    def test_create_app_returns_flask_instance(self):
        """create_app should return a Flask application instance."""
        from src.app import create_app

        app = create_app()

        assert app is not None
        assert app.name == "src.app"

    def test_create_app_with_test_config(self):
        """create_app should accept test configuration."""
        from src.app import create_app

        app = create_app({"TESTING": True})

        assert app.config["TESTING"] is True

    def test_create_app_registers_blueprints(self):
        """create_app should register API blueprints."""
        from src.app import create_app

        app = create_app()

        # Check that blueprints are registered
        assert "api" in app.blueprints

    def test_health_endpoint_returns_ok(self):
        """Health endpoint should return 200 OK."""
        from src.app import create_app

        app = create_app({"TESTING": True})
        client = app.test_client()

        response = client.get("/api/v1/health")

        assert response.status_code == 200
        assert response.json["status"] == "ok"
```

#### Step 2: Implement to pass

**File:** `python/api/src/app.py`

```python
"""Flask application factory."""
from flask import Flask, Blueprint, jsonify
from typing import Optional, Dict, Any


def create_app(config: Optional[Dict[str, Any]] = None) -> Flask:
    """
    Create and configure Flask application.

    Args:
        config: Optional configuration dictionary to override defaults.

    Returns:
        Configured Flask application instance.
    """
    app = Flask(__name__)

    # Load default configuration
    app.config.from_object("src.config.Config")

    # Override with provided config
    if config:
        app.config.update(config)

    # Initialize extensions
    _init_extensions(app)

    # Register blueprints
    _register_blueprints(app)

    return app


def _init_extensions(app: Flask) -> None:
    """Initialize Flask extensions."""
    from src.extensions import db

    db.init_app(app)


def _register_blueprints(app: Flask) -> None:
    """Register API blueprints."""
    api = Blueprint("api", __name__, url_prefix="/api/v1")

    @api.route("/health")
    def health():
        return jsonify({"status": "ok"})

    app.register_blueprint(api)
```

**File:** `python/api/src/config.py`

```python
"""Application configuration."""
import os
from typing import Optional


class Config:
    """Base configuration."""

    SECRET_KEY: str = os.environ.get("SECRET_KEY", "dev-secret-key")
    SQLALCHEMY_DATABASE_URI: str = os.environ.get(
        "DATABASE_URL",
        "postgresql://user:password@localhost:5432/vbwd"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS: bool = False
    SQLALCHEMY_ECHO: bool = False


class TestConfig(Config):
    """Test configuration."""

    TESTING: bool = True
    SQLALCHEMY_DATABASE_URI: str = "sqlite:///:memory:"


class DevelopmentConfig(Config):
    """Development configuration."""

    DEBUG: bool = True
    SQLALCHEMY_ECHO: bool = True


class ProductionConfig(Config):
    """Production configuration."""

    DEBUG: bool = False

    def __init__(self):
        if not os.environ.get("SECRET_KEY"):
            raise ValueError("SECRET_KEY must be set in production")
```

**File:** `python/api/src/extensions.py`

```python
"""Flask extensions initialization."""
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
```

---

### 0.4 Base Interfaces (Interface Segregation)

**TDD Steps:**

#### Step 1: Write interface contracts

**File:** `python/api/src/interfaces/__init__.py`

```python
"""Interface definitions following Interface Segregation Principle."""
from .repositories import (
    IReadRepository,
    IWriteRepository,
    IRepository,
    IUserRepository,
    ITarifPlanRepository,
    ISubscriptionRepository,
    IInvoiceRepository,
)
from .services import (
    IAuthService,
    IUserService,
    ISubscriptionService,
    IPaymentService,
    IInvoiceService,
)
from .gateways import (
    IPaymentGateway,
    IEmailGateway,
)

__all__ = [
    # Repositories
    "IReadRepository",
    "IWriteRepository",
    "IRepository",
    "IUserRepository",
    "ITarifPlanRepository",
    "ISubscriptionRepository",
    "IInvoiceRepository",
    # Services
    "IAuthService",
    "IUserService",
    "ISubscriptionService",
    "IPaymentService",
    "IInvoiceService",
    # Gateways
    "IPaymentGateway",
    "IEmailGateway",
]
```

**File:** `python/api/src/interfaces/repositories.py`

```python
"""Repository interfaces following Interface Segregation Principle."""
from abc import ABC, abstractmethod
from typing import Generic, TypeVar, Optional, List

T = TypeVar("T")
ID = TypeVar("ID")


class IReadRepository(ABC, Generic[T, ID]):
    """Interface for read-only repository operations."""

    @abstractmethod
    def find_by_id(self, id: ID) -> Optional[T]:
        """Find entity by ID."""
        pass

    @abstractmethod
    def find_all(self, limit: int = 100, offset: int = 0) -> List[T]:
        """Find all entities with pagination."""
        pass

    @abstractmethod
    def count(self) -> int:
        """Count total entities."""
        pass


class IWriteRepository(ABC, Generic[T, ID]):
    """Interface for write repository operations."""

    @abstractmethod
    def save(self, entity: T) -> T:
        """Save (create or update) entity."""
        pass

    @abstractmethod
    def delete(self, id: ID) -> bool:
        """Delete entity by ID. Returns True if deleted."""
        pass


class IRepository(IReadRepository[T, ID], IWriteRepository[T, ID]):
    """Combined read/write repository interface."""

    pass


class IUserRepository(IRepository["User", int]):
    """User-specific repository interface."""

    @abstractmethod
    def find_by_email(self, email: str) -> Optional["User"]:
        """Find user by email address."""
        pass

    @abstractmethod
    def find_by_status(self, status: str) -> List["User"]:
        """Find users by status."""
        pass

    @abstractmethod
    def email_exists(self, email: str) -> bool:
        """Check if email is already registered."""
        pass


class ITarifPlanRepository(IRepository["TarifPlan", int]):
    """Tariff plan repository interface."""

    @abstractmethod
    def find_by_slug(self, slug: str) -> Optional["TarifPlan"]:
        """Find tariff plan by URL slug."""
        pass

    @abstractmethod
    def find_active(self) -> List["TarifPlan"]:
        """Find all active tariff plans."""
        pass


class ISubscriptionRepository(IRepository["Subscription", int]):
    """Subscription repository interface."""

    @abstractmethod
    def find_by_user_id(self, user_id: int) -> List["Subscription"]:
        """Find all subscriptions for a user."""
        pass

    @abstractmethod
    def find_active_by_user_id(self, user_id: int) -> Optional["Subscription"]:
        """Find active subscription for a user."""
        pass

    @abstractmethod
    def find_expiring_before(self, date: "datetime") -> List["Subscription"]:
        """Find subscriptions expiring before date."""
        pass


class IInvoiceRepository(IRepository["UserInvoice", int]):
    """Invoice repository interface."""

    @abstractmethod
    def find_by_user_id(self, user_id: int) -> List["UserInvoice"]:
        """Find all invoices for a user."""
        pass

    @abstractmethod
    def find_by_invoice_number(self, number: str) -> Optional["UserInvoice"]:
        """Find invoice by invoice number."""
        pass

    @abstractmethod
    def find_by_status(self, status: str) -> List["UserInvoice"]:
        """Find invoices by status."""
        pass

    @abstractmethod
    def find_pending_expired(self) -> List["UserInvoice"]:
        """Find invoices that are pending but past expiry."""
        pass
```

**File:** `python/api/src/interfaces/services.py`

```python
"""Service interfaces following Interface Segregation Principle."""
from abc import ABC, abstractmethod
from typing import Optional, List, Tuple
from dataclasses import dataclass
from decimal import Decimal


@dataclass
class AuthResult:
    """Authentication result."""

    success: bool
    user_id: Optional[int] = None
    token: Optional[str] = None
    error: Optional[str] = None


@dataclass
class CheckoutSession:
    """Payment checkout session."""

    session_id: str
    checkout_url: str
    invoice_id: int


class IAuthService(ABC):
    """Authentication service interface."""

    @abstractmethod
    def register(self, email: str, password: str) -> AuthResult:
        """Register new user."""
        pass

    @abstractmethod
    def login(self, email: str, password: str) -> AuthResult:
        """Authenticate user and return JWT token."""
        pass

    @abstractmethod
    def verify_token(self, token: str) -> Optional[int]:
        """Verify JWT token and return user_id if valid."""
        pass

    @abstractmethod
    def hash_password(self, password: str) -> str:
        """Hash password using bcrypt."""
        pass

    @abstractmethod
    def verify_password(self, password: str, hashed: str) -> bool:
        """Verify password against hash."""
        pass


class IUserService(ABC):
    """User management service interface."""

    @abstractmethod
    def get_user(self, user_id: int) -> Optional["User"]:
        """Get user by ID."""
        pass

    @abstractmethod
    def get_user_details(self, user_id: int) -> Optional["UserDetails"]:
        """Get user details."""
        pass

    @abstractmethod
    def update_user_details(
        self, user_id: int, details: dict
    ) -> "UserDetails":
        """Update user details."""
        pass

    @abstractmethod
    def update_user_status(self, user_id: int, status: str) -> "User":
        """Update user status."""
        pass


class ISubscriptionService(ABC):
    """Subscription management service interface."""

    @abstractmethod
    def get_active_subscription(self, user_id: int) -> Optional["Subscription"]:
        """Get user's active subscription."""
        pass

    @abstractmethod
    def get_user_subscriptions(self, user_id: int) -> List["Subscription"]:
        """Get all user subscriptions."""
        pass

    @abstractmethod
    def create_subscription(
        self, user_id: int, tarif_plan_id: int
    ) -> "Subscription":
        """Create new subscription (inactive until payment)."""
        pass

    @abstractmethod
    def activate_subscription(self, subscription_id: int) -> "Subscription":
        """Activate subscription after payment."""
        pass

    @abstractmethod
    def cancel_subscription(self, subscription_id: int) -> "Subscription":
        """Cancel subscription."""
        pass

    @abstractmethod
    def expire_subscription(self, subscription_id: int) -> "Subscription":
        """Mark subscription as expired."""
        pass


class IPaymentService(ABC):
    """Payment processing service interface."""

    @abstractmethod
    def create_checkout(
        self,
        user_id: int,
        tarif_plan_id: int,
        payment_method: str,
    ) -> CheckoutSession:
        """Create payment checkout session."""
        pass

    @abstractmethod
    def process_webhook(
        self, provider: str, payload: dict, signature: str
    ) -> bool:
        """Process payment webhook notification."""
        pass

    @abstractmethod
    def verify_payment(self, invoice_id: int) -> bool:
        """Verify if payment was successful."""
        pass


class IInvoiceService(ABC):
    """Invoice management service interface."""

    @abstractmethod
    def create_invoice(
        self,
        user_id: int,
        tarif_plan_id: int,
        subscription_id: Optional[int] = None,
    ) -> "UserInvoice":
        """Create new invoice."""
        pass

    @abstractmethod
    def mark_paid(
        self, invoice_id: int, payment_ref: str, payment_method: str
    ) -> "UserInvoice":
        """Mark invoice as paid."""
        pass

    @abstractmethod
    def mark_expired(self, invoice_id: int) -> "UserInvoice":
        """Mark invoice as expired."""
        pass

    @abstractmethod
    def mark_cancelled(self, invoice_id: int) -> "UserInvoice":
        """Mark invoice as cancelled."""
        pass

    @abstractmethod
    def get_user_invoices(self, user_id: int) -> List["UserInvoice"]:
        """Get all invoices for user."""
        pass
```

**File:** `python/api/src/interfaces/gateways.py`

```python
"""External gateway interfaces following Interface Segregation Principle."""
from abc import ABC, abstractmethod
from typing import Optional
from dataclasses import dataclass
from decimal import Decimal


@dataclass
class PaymentSession:
    """Payment provider session details."""

    session_id: str
    checkout_url: str
    provider: str


@dataclass
class PaymentResult:
    """Payment verification result."""

    success: bool
    payment_ref: Optional[str] = None
    error: Optional[str] = None


@dataclass
class WebhookEvent:
    """Parsed webhook event."""

    event_type: str  # payment.completed, payment.failed, etc.
    payment_ref: str
    invoice_id: Optional[int] = None
    metadata: Optional[dict] = None


class IPaymentGateway(ABC):
    """
    Payment gateway interface.

    Liskov Substitution: Any implementation (PayPal, Stripe)
    must honor this contract and be substitutable.
    """

    @abstractmethod
    def create_checkout_session(
        self,
        amount: Decimal,
        currency: str,
        invoice_id: int,
        success_url: str,
        cancel_url: str,
    ) -> PaymentSession:
        """
        Create payment checkout session.

        Args:
            amount: Payment amount
            currency: ISO 4217 currency code
            invoice_id: Internal invoice ID for reference
            success_url: Redirect URL on success
            cancel_url: Redirect URL on cancellation

        Returns:
            PaymentSession with checkout URL

        Raises:
            PaymentGatewayError: If session creation fails
        """
        pass

    @abstractmethod
    def verify_webhook_signature(
        self, payload: bytes, signature: str
    ) -> bool:
        """
        Verify webhook signature authenticity.

        Args:
            payload: Raw webhook payload bytes
            signature: Signature header from provider

        Returns:
            True if signature is valid
        """
        pass

    @abstractmethod
    def parse_webhook_event(self, payload: dict) -> WebhookEvent:
        """
        Parse webhook payload into standardized event.

        Args:
            payload: Webhook JSON payload

        Returns:
            Parsed WebhookEvent
        """
        pass

    @abstractmethod
    def verify_payment(self, session_id: str) -> PaymentResult:
        """
        Verify payment status by session ID.

        Args:
            session_id: Payment session ID

        Returns:
            PaymentResult with success status
        """
        pass


class IEmailGateway(ABC):
    """Email sending gateway interface."""

    @abstractmethod
    def send_welcome_email(self, to_email: str, user_name: str) -> bool:
        """Send welcome email to new user."""
        pass

    @abstractmethod
    def send_payment_confirmation(
        self,
        to_email: str,
        invoice_number: str,
        amount: Decimal,
        currency: str,
    ) -> bool:
        """Send payment confirmation email."""
        pass

    @abstractmethod
    def send_subscription_activated(
        self,
        to_email: str,
        plan_name: str,
        expires_at: "datetime",
    ) -> bool:
        """Send subscription activation email."""
        pass

    @abstractmethod
    def send_subscription_expiring(
        self,
        to_email: str,
        plan_name: str,
        expires_at: "datetime",
    ) -> bool:
        """Send subscription expiring reminder."""
        pass
```

---

### 0.5 Dependency Injection Container

**File:** `python/api/src/container.py`

```python
"""Dependency Injection container using dependency-injector."""
from dependency_injector import containers, providers
from dependency_injector.wiring import Provide, inject

from src.extensions import db


class Container(containers.DeclarativeContainer):
    """
    DI Container following Dependency Inversion Principle.

    All dependencies are wired through this container,
    allowing easy substitution for testing.
    """

    wiring_config = containers.WiringConfiguration(
        modules=[
            "src.routes.auth",
            "src.routes.user",
            "src.routes.tarif_plans",
            "src.routes.checkout",
            "src.routes.admin",
            "src.routes.webhooks",
        ]
    )

    # Configuration
    config = providers.Configuration()

    # Database session
    db_session = providers.Singleton(lambda: db.session)

    # Repositories
    user_repository = providers.Factory(
        "src.repositories.UserRepository",
        session=db_session,
    )

    tarif_plan_repository = providers.Factory(
        "src.repositories.TarifPlanRepository",
        session=db_session,
    )

    subscription_repository = providers.Factory(
        "src.repositories.SubscriptionRepository",
        session=db_session,
    )

    invoice_repository = providers.Factory(
        "src.repositories.InvoiceRepository",
        session=db_session,
    )

    # Gateways
    paypal_gateway = providers.Singleton(
        "src.gateways.PayPalGateway",
        client_id=config.paypal.client_id,
        client_secret=config.paypal.client_secret,
        sandbox=config.paypal.sandbox,
    )

    stripe_gateway = providers.Singleton(
        "src.gateways.StripeGateway",
        api_key=config.stripe.api_key,
        webhook_secret=config.stripe.webhook_secret,
    )

    email_gateway = providers.Singleton(
        "src.gateways.EmailGateway",
        smtp_host=config.email.smtp_host,
        smtp_port=config.email.smtp_port,
        username=config.email.username,
        password=config.email.password,
    )

    # Services
    auth_service = providers.Factory(
        "src.services.AuthService",
        user_repo=user_repository,
        secret_key=config.secret_key,
    )

    user_service = providers.Factory(
        "src.services.UserService",
        user_repo=user_repository,
    )

    subscription_service = providers.Factory(
        "src.services.SubscriptionService",
        subscription_repo=subscription_repository,
        tarif_plan_repo=tarif_plan_repository,
    )

    invoice_service = providers.Factory(
        "src.services.InvoiceService",
        invoice_repo=invoice_repository,
        tarif_plan_repo=tarif_plan_repository,
    )

    payment_service = providers.Factory(
        "src.services.PaymentService",
        invoice_service=invoice_service,
        subscription_service=subscription_service,
        paypal_gateway=paypal_gateway,
        stripe_gateway=stripe_gateway,
    )
```

---

### 0.6 Test Configuration

**File:** `python/api/pytest.ini`

```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -v --tb=short
filterwarnings =
    ignore::DeprecationWarning
```

**File:** `python/api/tests/conftest.py`

```python
"""Pytest configuration and fixtures."""
import pytest
from flask import Flask
from src.app import create_app
from src.extensions import db as _db


@pytest.fixture(scope="session")
def app() -> Flask:
    """Create application for testing."""
    app = create_app({
        "TESTING": True,
        "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
    })
    return app


@pytest.fixture(scope="session")
def db(app: Flask):
    """Create database for testing."""
    with app.app_context():
        _db.create_all()
        yield _db
        _db.drop_all()


@pytest.fixture(scope="function")
def session(db, app: Flask):
    """Create database session for a test."""
    with app.app_context():
        connection = db.engine.connect()
        transaction = connection.begin()

        # Bind session to connection
        db.session.configure(bind=connection)

        yield db.session

        # Rollback transaction after test
        db.session.remove()
        transaction.rollback()
        connection.close()


@pytest.fixture
def client(app: Flask):
    """Create test client."""
    return app.test_client()


@pytest.fixture
def auth_headers(app: Flask) -> dict:
    """Create authenticated headers with valid JWT."""
    from src.services import AuthService
    from unittest.mock import Mock

    # Create mock user repo
    mock_repo = Mock()
    mock_repo.find_by_email.return_value = None

    # Create auth service and generate token
    auth_service = AuthService(
        user_repo=mock_repo,
        secret_key=app.config["SECRET_KEY"],
    )
    token = auth_service._generate_token(user_id=1)

    return {"Authorization": f"Bearer {token}"}
```

---

### 0.7 Database Migrations Setup

**File:** `python/api/migrations/env.py`

```python
"""Alembic migration environment configuration."""
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
import os
import sys

# Add src to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from src.extensions import db
from src.models import *  # noqa: Import all models

config = context.config
fileConfig(config.config_file_name)

target_metadata = db.metadata


def run_migrations_offline():
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

---

## Verification Checklist

```bash
# Run from project root

# 1. Build Python container
docker-compose build python

# 2. Run all tests
docker-compose run --rm python pytest

# 3. Run with coverage
docker-compose run --rm python pytest --cov=src --cov-report=term-missing

# 4. Lint check
docker-compose run --rm python flake8 src/ tests/

# 5. Type check
docker-compose run --rm python mypy src/

# 6. Health endpoint
docker-compose up -d python
curl http://localhost:5000/api/v1/health
# Expected: {"status": "ok"}
```

---

## Deliverables

| Item | Status | Notes |
|------|--------|-------|
| Dockerfile | [ ] | Python 3.11, all deps |
| docker-compose.yml | [ ] | Python service config |
| requirements.txt | [ ] | All dependencies |
| Flask app factory | [ ] | With tests |
| Base interfaces | [ ] | ISP compliant |
| DI container | [ ] | dependency-injector |
| Test fixtures | [ ] | conftest.py |
| Migrations setup | [ ] | Alembic |
| CI pipeline | [ ] | GitHub Actions |

---

## Next Sprint

[Sprint 1: Data Layer](./sprint-1-data-layer.md) - Implement models and repositories.
