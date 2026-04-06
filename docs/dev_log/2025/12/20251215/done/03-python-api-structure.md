# Task 03: Python API Structure

**Priority:** High
**Status:** Pending
**Estimated Effort:** Large

---

## Objective

Create the Flask API base structure with routes, models, and services following TDD-first, SOLID, and DI principles.

---

## Tasks

### 3.1 Create python/api/requirements.txt

```txt
# Core
Flask==3.0.0
gunicorn==21.2.0

# Database
Flask-SQLAlchemy==3.1.1
PyMySQL==1.1.0
cryptography==41.0.7

# Async & Background Tasks
concurrent-futures==3.1.1

# WebSocket
flask-socketio==5.3.6
python-socketio==5.10.0

# HTTP Client
requests==2.31.0

# Validation
marshmallow==3.20.1
email-validator==2.1.0

# Security
python-dotenv==1.0.0

# Testing
pytest==7.4.3
pytest-flask==1.3.0
pytest-cov==4.1.0
factory-boy==3.3.0

# Development
black==23.12.1
flake8==6.1.0
mypy==1.7.1
```

### 3.2 Create python/api/src/__init__.py (App Factory)

```python
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_socketio import SocketIO
from concurrent.futures import ThreadPoolExecutor
import os

db = SQLAlchemy()
socketio = SocketIO()
executor = ThreadPoolExecutor(max_workers=10)


def create_app(config_name=None):
    app = Flask(__name__)

    # Configuration
    app.config['SECRET_KEY'] = os.getenv('FLASK_SECRET_KEY', 'dev-secret-key')
    app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv(
        'DATABASE_URL',
        'mysql+pymysql://vbwd:vbwd@mysql:3306/vbwd'
    )
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # Initialize extensions
    db.init_app(app)
    socketio.init_app(app, async_mode='threading', cors_allowed_origins='*')

    # Register blueprints
    from src.routes.user import user_bp
    from src.routes.admin import admin_bp
    from src.routes.health import health_bp

    app.register_blueprint(health_bp)
    app.register_blueprint(user_bp, url_prefix='/api/user')
    app.register_blueprint(admin_bp, url_prefix='/api/admin')

    return app
```

### 3.3 Create python/api/src/routes/user.py

```python
from flask import Blueprint, request, jsonify, current_app
from src.services.submission_service import SubmissionService
from src.services.validator_service import ValidatorService
from src import db, executor

user_bp = Blueprint('user', __name__)


@user_bp.route('/submit', methods=['POST'])
def submit_diagnostic():
    """
    Fire-and-Forget submission endpoint.
    Returns 202 immediately, processes in background.
    """
    data = request.get_json()

    # 1. Validate (sync, fast)
    validator = ValidatorService()
    errors = validator.validate_submission(data)
    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    # 2. Create submission record (sync, fast)
    service = SubmissionService(db.session)
    submission = service.create_submission(data)

    # 3. Submit to background thread (non-blocking)
    app = current_app._get_current_object()
    executor.submit(
        service.process_submission_background,
        app,
        submission.id,
        data
    )

    # 4. Return immediately
    return jsonify({
        "success": True,
        "message": "Your data is submitted. You will receive results via email.",
        "submission_id": submission.id
    }), 202


@user_bp.route('/status/<int:submission_id>', methods=['GET'])
def get_status(submission_id):
    """Get submission status (for polling if WebSocket not available)."""
    service = SubmissionService(db.session)
    submission = service.get_submission(submission_id)

    if not submission:
        return jsonify({"success": False, "message": "Not found"}), 404

    return jsonify({
        "success": True,
        "submission_id": submission.id,
        "status": submission.status,
        "created_at": submission.created_at.isoformat()
    }), 200
```

### 3.4 Create python/api/src/routes/admin.py

```python
from flask import Blueprint, request, jsonify
from functools import wraps
from src.services.submission_service import SubmissionService
from src.services.auth_service import AuthService
from src import db

admin_bp = Blueprint('admin', __name__)


def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = AuthService()
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        if not auth.verify_admin_token(token):
            return jsonify({"success": False, "message": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated


@admin_bp.route('/submissions', methods=['GET'])
@admin_required
def list_submissions():
    """List all submissions with pagination."""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    status = request.args.get('status')

    service = SubmissionService(db.session)
    result = service.list_submissions(page, per_page, status)

    return jsonify({
        "success": True,
        "data": result['items'],
        "pagination": {
            "page": result['page'],
            "per_page": result['per_page'],
            "total": result['total']
        }
    }), 200


@admin_bp.route('/submissions/<int:submission_id>', methods=['GET'])
@admin_required
def get_submission(submission_id):
    """Get single submission details."""
    service = SubmissionService(db.session)
    submission = service.get_submission(submission_id)

    if not submission:
        return jsonify({"success": False, "message": "Not found"}), 404

    return jsonify({
        "success": True,
        "data": submission.to_dict()
    }), 200
```

### 3.5 Create python/api/src/routes/health.py

```python
from flask import Blueprint, jsonify
from src import db

health_bp = Blueprint('health', __name__)


@health_bp.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for Docker/k8s."""
    try:
        db.session.execute('SELECT 1')
        db_status = 'healthy'
    except Exception as e:
        db_status = f'unhealthy: {str(e)}'

    return jsonify({
        "status": "healthy" if db_status == 'healthy' else "unhealthy",
        "database": db_status
    }), 200 if db_status == 'healthy' else 503
```

### 3.6 Create python/api/src/models/submission.py

```python
from src import db
from datetime import datetime


class Submission(db.Model):
    __tablename__ = 'submissions'

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), nullable=False, index=True)
    status = db.Column(
        db.Enum('pending', 'processing', 'completed', 'failed'),
        default='pending',
        index=True
    )
    images_data = db.Column(db.JSON)
    comments = db.Column(db.Text)
    consent_given = db.Column(db.Boolean, default=False)
    consent_timestamp = db.Column(db.DateTime)
    result = db.Column(db.JSON)
    error = db.Column(db.Text)
    loopai_execution_id = db.Column(db.String(255))
    created_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'email': self.email,
            'status': self.status,
            'comments': self.comments,
            'consent_given': self.consent_given,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
```

### 3.7 Create python/api/src/services/submission_service.py

```python
from src.models.submission import Submission
from src.services.loopai_client import LoopAIClient
from src.services.email_service import EmailService
from src import socketio
from datetime import datetime


class SubmissionService:
    """
    Service for handling diagnostic submissions.
    Follows Single Responsibility Principle - only handles submission logic.
    Dependencies injected via constructor (DI).
    """

    def __init__(self, db_session, loopai_client=None, email_service=None):
        self._db = db_session
        self._loopai = loopai_client or LoopAIClient()
        self._email = email_service or EmailService()

    def create_submission(self, data: dict) -> Submission:
        """Create new submission record."""
        submission = Submission(
            email=data['email'],
            images_data=data.get('images'),
            comments=data.get('comments'),
            consent_given=data.get('consent', False),
            consent_timestamp=datetime.utcnow() if data.get('consent') else None,
            status='pending'
        )
        self._db.add(submission)
        self._db.commit()
        return submission

    def get_submission(self, submission_id: int) -> Submission:
        """Get submission by ID."""
        return Submission.query.get(submission_id)

    def list_submissions(self, page: int, per_page: int, status: str = None) -> dict:
        """List submissions with pagination and optional status filter."""
        query = Submission.query
        if status:
            query = query.filter_by(status=status)

        query = query.order_by(Submission.created_at.desc())
        pagination = query.paginate(page=page, per_page=per_page)

        return {
            'items': [s.to_dict() for s in pagination.items],
            'page': pagination.page,
            'per_page': pagination.per_page,
            'total': pagination.total
        }

    def process_submission_background(self, app, submission_id: int, data: dict):
        """
        Background processing - runs in ThreadPoolExecutor.
        Does NOT block HTTP requests.
        """
        with app.app_context():
            try:
                submission = Submission.query.get(submission_id)
                submission.status = 'processing'
                self._db.commit()

                # Notify frontend (if connected)
                self._emit_status(submission, 'Processing your submission...')

                # Call LoopAI API
                response = self._loopai.run_diagnostic(data)
                submission.loopai_execution_id = response.get('execution_id')
                self._db.commit()

                # Poll for results
                result = self._loopai.poll_for_result(response['execution_id'])

                # Update submission
                submission.status = 'completed'
                submission.result = result
                self._db.commit()

                # Send email
                self._email.send_result(submission.email, result)

                # Notify frontend
                self._emit_status(submission, 'Your results are ready! Check your email.')

            except Exception as e:
                submission = Submission.query.get(submission_id)
                submission.status = 'failed'
                submission.error = str(e)
                self._db.commit()
                self._emit_status(submission, f'Error: {str(e)}')

    def _emit_status(self, submission: Submission, message: str):
        """Emit WebSocket status update."""
        socketio.emit('status_update', {
            'submission_id': submission.id,
            'status': submission.status,
            'message': message
        }, room=f'user_{submission.email}')
```

### 3.8 Create python/api/src/services/loopai_client.py

```python
import requests
import time
import os


class LoopAIClient:
    """Client for LoopAI API integration."""

    def __init__(self, base_url=None, api_key=None):
        self._base_url = base_url or os.getenv('LOOPAI_API_URL', 'http://loopai-web:5000')
        self._api_key = api_key or os.getenv('LOOPAI_API_KEY')

    def run_diagnostic(self, data: dict) -> dict:
        """Submit diagnostic request to LoopAI."""
        response = requests.post(
            f'{self._base_url}/api/public/agent/{self._get_agent_id()}/action/diagnose/',
            json=data,
            headers=self._headers(),
            timeout=30
        )
        response.raise_for_status()
        return response.json()

    def poll_for_result(self, execution_id: str, timeout: int = 3600, interval: int = 60) -> dict:
        """Poll for execution result with timeout."""
        start_time = time.time()

        while time.time() - start_time < timeout:
            response = requests.get(
                f'{self._base_url}/api/execution/{execution_id}/status/',
                headers=self._headers(),
                timeout=30
            )
            response.raise_for_status()
            data = response.json()

            if data.get('status') == 'COMPLETED':
                return data.get('result', {})
            elif data.get('status') == 'FAILED':
                raise Exception(f"LoopAI execution failed: {data.get('error')}")

            time.sleep(interval)

        raise Exception(f"Timeout waiting for result after {timeout} seconds")

    def _headers(self) -> dict:
        headers = {'Content-Type': 'application/json'}
        if self._api_key:
            headers['Authorization'] = f'Bearer {self._api_key}'
        return headers

    def _get_agent_id(self) -> int:
        return int(os.getenv('LOOPAI_AGENT_ID', '1'))
```

### 3.9 Create python/api/src/services/validator_service.py

```python
import re
from typing import List, Optional


class ValidatorService:
    """Validation service for submissions."""

    ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']
    MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB
    EMAIL_REGEX = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    def validate_submission(self, data: dict) -> List[str]:
        """Validate submission data. Returns list of errors."""
        errors = []

        # Email validation
        email_error = self._validate_email(data.get('email'))
        if email_error:
            errors.append(email_error)

        # Consent validation
        if not data.get('consent'):
            errors.append('Consent is required')

        # Images validation
        images_errors = self._validate_images(data.get('images', []))
        errors.extend(images_errors)

        return errors

    def _validate_email(self, email: Optional[str]) -> Optional[str]:
        if not email:
            return 'Email is required'
        if not re.match(self.EMAIL_REGEX, email):
            return 'Invalid email format'
        return None

    def _validate_images(self, images: list) -> List[str]:
        errors = []
        if not images:
            errors.append('At least one image is required')
            return errors

        for i, img in enumerate(images):
            if img.get('type') not in self.ALLOWED_IMAGE_TYPES:
                errors.append(f'Image {i+1}: Invalid format. Allowed: JPEG, PNG, WebP')
            if img.get('size', 0) > self.MAX_IMAGE_SIZE:
                errors.append(f'Image {i+1}: Exceeds 10MB limit')

        return errors
```

---

## Directory Structure After Completion

```
python/api/
├── requirements.txt
├── gunicorn.conf.py
├── src/
│   ├── __init__.py
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── admin.py
│   │   └── health.py
│   ├── models/
│   │   ├── __init__.py
│   │   └── submission.py
│   └── services/
│       ├── __init__.py
│       ├── submission_service.py
│       ├── loopai_client.py
│       ├── validator_service.py
│       ├── email_service.py
│       └── auth_service.py
└── tests/
    ├── __init__.py
    ├── conftest.py
    ├── unit/
    │   ├── test_validator_service.py
    │   └── test_submission_service.py
    ├── integration/
    │   └── test_user_routes.py
    └── fixtures/
        └── submission_fixtures.py
```

---

## Acceptance Criteria

- [ ] All routes respond correctly
- [ ] `/api/user/submit` returns 202 and processes in background
- [ ] WebSocket emits status updates
- [ ] Services follow DI pattern
- [ ] Unit tests pass for all services

---

## Dependencies

- Task 01 (docker-compose.yaml)
- Task 02 (container configs)

---

## Next Task

- `04-frontend-structure.md`
