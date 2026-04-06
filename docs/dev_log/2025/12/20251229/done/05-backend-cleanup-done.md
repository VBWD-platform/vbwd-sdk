# Task 5: Backend Code Cleanup & Security

**Priority:** CRITICAL
**Focus:** Fix security vulnerabilities, enable DI, clean code issues
**Estimated Time:** 2-3 hours

---

## Core Requirements

- TDD-First: Tests before implementation
- SOLID: Dependency Injection is key here
- Clean Code: Remove magic numbers, use enums properly
- No Over-Engineering: Simple fixes only

---

## 5.1 Security Fixes (CRITICAL)

### Fix Default SECRET_KEY

**File:** `src/config.py`

**Test First:** `tests/unit/test_config.py`
```python
def test_production_config_requires_secret_key():
    """ProductionConfig raises error if SECRET_KEY not set."""
    import os
    os.environ.pop('SECRET_KEY', None)
    os.environ.pop('JWT_SECRET_KEY', None)

    with pytest.raises(ValueError, match="SECRET_KEY must be set"):
        ProductionConfig()

def test_production_config_requires_jwt_secret():
    """ProductionConfig raises error if JWT_SECRET_KEY not set."""
    import os
    os.environ['SECRET_KEY'] = 'test'
    os.environ.pop('JWT_SECRET_KEY', None)

    with pytest.raises(ValueError, match="JWT_SECRET_KEY must be set"):
        ProductionConfig()
```

**Implementation:**
```python
class ProductionConfig(Config):
    DEBUG = False
    TESTING = False

    def __init__(self):
        super().__init__()
        if not os.environ.get('SECRET_KEY'):
            raise ValueError("SECRET_KEY must be set in production")
        if not os.environ.get('JWT_SECRET_KEY'):
            raise ValueError("JWT_SECRET_KEY must be set in production")

        self.SECRET_KEY = os.environ['SECRET_KEY']
        self.JWT_SECRET_KEY = os.environ['JWT_SECRET_KEY']
```

### Add Rate Limiting

**Install:** Add `Flask-Limiter` to requirements.txt

**Test First:** `tests/unit/routes/test_rate_limiting.py`
```python
def test_login_rate_limited(client):
    """Login endpoint is rate limited after 5 attempts."""
    for i in range(5):
        client.post('/api/v1/auth/login', json={'email': 'test@test.com', 'password': 'wrong'})

    response = client.post('/api/v1/auth/login', json={'email': 'test@test.com', 'password': 'wrong'})
    assert response.status_code == 429

def test_register_rate_limited(client):
    """Register endpoint is rate limited after 3 attempts."""
    pass
```

**Implementation:** `src/extensions.py`
```python
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(key_func=get_remote_address, default_limits=["200 per day", "50 per hour"])
```

**Update routes:** `src/routes/auth.py`
```python
from src.extensions import limiter

@auth_bp.route('/login', methods=['POST'])
@limiter.limit("5 per minute")
def login():
    pass

@auth_bp.route('/register', methods=['POST'])
@limiter.limit("3 per minute")
def register():
    pass
```

---

## 5.2 Enable DI Container

**File:** `src/container.py`

**Test First:** `tests/unit/test_container.py`
```python
def test_container_provides_user_repository():
    """Container provides UserRepository instance."""
    container = Container()
    repo = container.user_repository()
    assert isinstance(repo, UserRepository)

def test_container_provides_auth_service():
    """Container provides AuthService with injected dependencies."""
    container = Container()
    service = container.auth_service()
    assert isinstance(service, AuthService)

def test_services_are_singletons():
    """Services are singletons within request scope."""
    container = Container()
    service1 = container.auth_service()
    service2 = container.auth_service()
    assert service1 is service2
```

**Implementation:**
```python
from dependency_injector import containers, providers
from src.extensions import db
from src.repositories.user_repository import UserRepository
from src.repositories.subscription_repository import SubscriptionRepository
from src.repositories.invoice_repository import InvoiceRepository
from src.services.auth_service import AuthService
from src.services.user_service import UserService
from src.services.subscription_service import SubscriptionService

class Container(containers.DeclarativeContainer):
    """Dependency injection container."""

    config = providers.Configuration()

    # Database session
    db_session = providers.Singleton(lambda: db.session)

    # Repositories
    user_repository = providers.Factory(
        UserRepository,
        session=db_session
    )

    subscription_repository = providers.Factory(
        SubscriptionRepository,
        session=db_session
    )

    invoice_repository = providers.Factory(
        InvoiceRepository,
        session=db_session
    )

    tarif_plan_repository = providers.Factory(
        TarifPlanRepository,
        session=db_session
    )

    # Services
    auth_service = providers.Factory(
        AuthService,
        user_repository=user_repository
    )

    user_service = providers.Factory(
        UserService,
        user_repository=user_repository
    )

    subscription_service = providers.Factory(
        SubscriptionService,
        subscription_repository=subscription_repository,
        tarif_plan_repository=tarif_plan_repository
    )
```

**Wire to Flask:** `src/app.py`
```python
from src.container import Container

def create_app():
    app = Flask(__name__)
    # ...

    container = Container()
    container.config.from_dict(app.config)
    app.container = container

    # Wire container to routes
    container.wire(modules=[
        'src.routes.auth',
        'src.routes.user',
        'src.routes.subscriptions'
    ])

    return app
```

**Update routes to use DI:** `src/routes/auth.py`
```python
from dependency_injector.wiring import inject, Provide
from src.container import Container

@auth_bp.route('/register', methods=['POST'])
@inject
def register(auth_service: AuthService = Provide[Container.auth_service]):
    """Register new user."""
    data = request.get_json()
    result = auth_service.register(
        email=data.get('email'),
        password=data.get('password')
    )
    # ...
```

---

## 5.3 Clean Code Fixes

### Fix Magic Numbers

**File:** `src/services/auth_service.py`

**Before:**
```python
token = jwt.encode({
    'user_id': str(user.id),
    'email': user.email,
    'exp': datetime.utcnow() + timedelta(hours=24)  # Magic number
}, self._secret_key, algorithm='HS256')
```

**After:**
```python
# Add to Config
class Config:
    JWT_EXPIRATION_HOURS = int(os.environ.get('JWT_EXPIRATION_HOURS', 24))

# Use in service
token = jwt.encode({
    'user_id': str(user.id),
    'email': user.email,
    'exp': datetime.utcnow() + timedelta(hours=current_app.config['JWT_EXPIRATION_HOURS'])
}, self._secret_key, algorithm='HS256')
```

### Fix Enum Comparisons

**Before:**
```python
if user.status.value != 'active':
    return AuthResult(success=False, error="User is not active")
```

**After:**
```python
if user.status != UserStatus.ACTIVE:
    return AuthResult(success=False, error="User is not active")
```

**Files to update:**
- [ ] `src/services/auth_service.py`
- [ ] `src/services/subscription_service.py`
- [ ] `src/routes/auth.py`

---

## 5.4 Add Transaction Management

**File:** `src/utils/transaction.py`

**Test First:**
```python
def test_transaction_commits_on_success():
    """Transaction commits when no exception raised."""
    pass

def test_transaction_rollbacks_on_exception():
    """Transaction rolls back when exception raised."""
    pass
```

**Implementation:**
```python
from contextlib import contextmanager
from src.extensions import db

@contextmanager
def transaction():
    """Context manager for database transactions."""
    try:
        yield db.session
        db.session.commit()
    except Exception:
        db.session.rollback()
        raise
```

**Usage:**
```python
from src.utils.transaction import transaction

def create_subscription_with_invoice(self, user_id, plan_id):
    with transaction() as session:
        subscription = Subscription(user_id=user_id, tarif_plan_id=plan_id)
        session.add(subscription)

        invoice = UserInvoice(user_id=user_id, subscription_id=subscription.id)
        session.add(invoice)
    # Commits automatically on success
```

---

## Checklist

### Security
- [ ] ProductionConfig validates SECRET_KEY
- [ ] ProductionConfig validates JWT_SECRET_KEY
- [ ] Flask-Limiter added and configured
- [ ] Rate limits on /login (5/min)
- [ ] Rate limits on /register (3/min)

### DI Container
- [ ] Container properly configured
- [ ] All repositories in container
- [ ] All services in container
- [ ] Routes wired to container
- [ ] Tests for container

### Clean Code
- [ ] JWT expiration from config
- [ ] All enum comparisons use enum values
- [ ] Transaction context manager added
- [ ] No magic numbers remaining

---

## Verification

```bash
# Run security tests
docker-compose run --rm python-test pytest tests/unit/test_config.py tests/unit/routes/test_rate_limiting.py -v

# Run DI tests
docker-compose run --rm python-test pytest tests/unit/test_container.py -v

# Run all tests
docker-compose run --rm python-test pytest tests/ -v
```
