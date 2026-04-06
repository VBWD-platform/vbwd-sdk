# Task 05: Testing Infrastructure

**Priority:** High
**Status:** Pending
**Estimated Effort:** Medium

---

## Objective

Set up TDD-first testing infrastructure. All tests run in Docker containers.

---

## Tasks

### 5.1 Create python/api/tests/conftest.py

```python
import pytest
from src import create_app, db


@pytest.fixture(scope='session')
def app():
    """Create application for testing."""
    app = create_app('testing')
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    app.config['TESTING'] = True

    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()


@pytest.fixture
def client(app):
    """Test client for making requests."""
    return app.test_client()


@pytest.fixture
def db_session(app):
    """Database session for tests."""
    with app.app_context():
        yield db.session
        db.session.rollback()
```

### 5.2 Create python/api/tests/unit/test_validator_service.py

```python
import pytest
from src.services.validator_service import ValidatorService


class TestValidatorService:
    """Unit tests for ValidatorService - TDD first."""

    def setup_method(self):
        self.validator = ValidatorService()

    def test_valid_submission_passes(self):
        data = {
            'email': 'test@example.com',
            'consent': True,
            'images': [{'type': 'image/jpeg', 'size': 1000}]
        }
        errors = self.validator.validate_submission(data)
        assert errors == []

    def test_missing_email_fails(self):
        data = {'consent': True, 'images': [{'type': 'image/jpeg', 'size': 1000}]}
        errors = self.validator.validate_submission(data)
        assert 'Email is required' in errors

    def test_invalid_email_fails(self):
        data = {
            'email': 'not-an-email',
            'consent': True,
            'images': [{'type': 'image/jpeg', 'size': 1000}]
        }
        errors = self.validator.validate_submission(data)
        assert 'Invalid email format' in errors

    def test_missing_consent_fails(self):
        data = {
            'email': 'test@example.com',
            'consent': False,
            'images': [{'type': 'image/jpeg', 'size': 1000}]
        }
        errors = self.validator.validate_submission(data)
        assert 'Consent is required' in errors

    def test_no_images_fails(self):
        data = {'email': 'test@example.com', 'consent': True, 'images': []}
        errors = self.validator.validate_submission(data)
        assert 'At least one image is required' in errors

    def test_invalid_image_type_fails(self):
        data = {
            'email': 'test@example.com',
            'consent': True,
            'images': [{'type': 'image/gif', 'size': 1000}]
        }
        errors = self.validator.validate_submission(data)
        assert any('Invalid format' in e for e in errors)

    def test_image_too_large_fails(self):
        data = {
            'email': 'test@example.com',
            'consent': True,
            'images': [{'type': 'image/jpeg', 'size': 20 * 1024 * 1024}]  # 20MB
        }
        errors = self.validator.validate_submission(data)
        assert any('Exceeds 10MB' in e for e in errors)
```

### 5.3 Create python/api/tests/integration/test_user_routes.py

```python
import pytest


class TestUserRoutes:
    """Integration tests for user API routes."""

    def test_health_check(self, client):
        response = client.get('/health')
        assert response.status_code == 200
        data = response.get_json()
        assert data['status'] == 'healthy'

    def test_submit_returns_202(self, client):
        """Submission should return 202 Accepted (fire-and-forget)."""
        data = {
            'email': 'test@example.com',
            'consent': True,
            'images': [{'type': 'image/jpeg', 'size': 1000, 'data': 'base64...'}],
            'comments': 'Test submission'
        }
        response = client.post('/api/user/submit', json=data)
        assert response.status_code == 202
        result = response.get_json()
        assert result['success'] is True
        assert 'submission_id' in result

    def test_submit_invalid_data_returns_400(self, client):
        """Invalid submission should return 400."""
        data = {'email': 'invalid'}  # Missing required fields
        response = client.post('/api/user/submit', json=data)
        assert response.status_code == 400
        result = response.get_json()
        assert result['success'] is False
        assert 'errors' in result

    def test_get_status_not_found(self, client):
        response = client.get('/api/user/status/99999')
        assert response.status_code == 404
```

### 5.4 Create container/python/Dockerfile.test

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    default-libmysqlclient-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/ .

# Run tests
CMD ["pytest", "-v", "--cov=src", "--cov-report=term-missing"]
```

### 5.5 Add test commands to docker-compose.yaml

```yaml
  python-test:
    build:
      context: ./python
      dockerfile: ../container/python/Dockerfile.test
    volumes:
      - ./python/api:/app
    environment:
      - TESTING=true
    networks:
      - vbwd-network

  frontend-test:
    build:
      context: ./frontend/user/vue
      dockerfile: ../../../container/frontend/Dockerfile.test
    volumes:
      - ./frontend/user/vue:/app
    command: npm test
    networks:
      - vbwd-network
```

### 5.6 Create Makefile for test commands

```makefile
.PHONY: test test-python test-frontend test-unit test-integration

# Run all tests
test: test-python test-frontend

# Python tests
test-python:
	docker-compose run --rm python-test

# Frontend tests
test-frontend:
	docker-compose run --rm frontend-test

# Unit tests only
test-unit:
	docker-compose run --rm python-test pytest tests/unit -v

# Integration tests only
test-integration:
	docker-compose run --rm python-test pytest tests/integration -v

# Run with coverage
test-coverage:
	docker-compose run --rm python-test pytest --cov=src --cov-report=html
```

---

## Acceptance Criteria

- [ ] `make test` runs all tests in Docker
- [ ] Unit tests run without database
- [ ] Integration tests use test database
- [ ] Coverage report generated
- [ ] Tests follow TDD pattern (write test first)

---

## Dependencies

- Task 01-04 (all infrastructure)

---

## Sprint Complete

After Task 05, the basic infrastructure is complete and ready for development.
