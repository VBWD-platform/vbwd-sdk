# Task 7: Docker & Secrets Management

**Priority:** MEDIUM
**Focus:** Production-ready Docker configuration
**Estimated Time:** 1-2 hours

---

## Problem Statement

Current State:
- Secrets hardcoded in docker-compose.yaml
- No separate production configuration
- Same compose file for dev and prod

Target State:
- Secrets via environment files (not in VCS)
- Separate dev/prod configurations
- Docker secrets for sensitive data

---

## Core Requirements

- No Over-Engineering: Simple .env files, not Vault/AWS Secrets
- Clean Code: Clear separation of concerns
- Security: No secrets in version control

---

## 7.1 Environment Files Structure

### Create .env.example (already exists, verify)

**File:** `vbwd-backend/.env.example`
```env
# Database
POSTGRES_USER=vbwd
POSTGRES_PASSWORD=CHANGE_ME_IN_PRODUCTION
POSTGRES_DB=vbwd
DATABASE_URL=postgresql://vbwd:CHANGE_ME@postgres:5432/vbwd

# Flask
FLASK_ENV=development
SECRET_KEY=CHANGE_ME_IN_PRODUCTION
JWT_SECRET_KEY=CHANGE_ME_IN_PRODUCTION

# Redis
REDIS_URL=redis://redis:6379/0

# Email (optional in dev)
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=noreply@example.com
SMTP_FROM_NAME=VBWD

# API Keys (optional)
LOOPAI_API_URL=
LOOPAI_API_KEY=
```

### Create .env.production.example

**File:** `vbwd-backend/.env.production.example`
```env
# PRODUCTION CONFIGURATION
# Copy to .env.production and fill in real values
# NEVER commit .env.production to version control

# Database (use strong password)
POSTGRES_USER=vbwd
POSTGRES_PASSWORD=<GENERATE_STRONG_PASSWORD>
POSTGRES_DB=vbwd_production
DATABASE_URL=postgresql://vbwd:<PASSWORD>@postgres:5432/vbwd_production

# Flask (generate with: python -c "import secrets; print(secrets.token_hex(32))")
FLASK_ENV=production
SECRET_KEY=<GENERATE_64_CHAR_HEX>
JWT_SECRET_KEY=<GENERATE_64_CHAR_HEX>

# Redis
REDIS_URL=redis://redis:6379/0

# Email (required in production)
SMTP_HOST=smtp.mailgun.org
SMTP_PORT=587
SMTP_USER=postmaster@mg.yourdomain.com
SMTP_PASSWORD=<MAILGUN_PASSWORD>
SMTP_FROM_EMAIL=noreply@yourdomain.com
SMTP_FROM_NAME=VBWD

# Logging
LOG_LEVEL=WARNING
```

---

## 7.2 Update docker-compose.yaml

### Remove Hardcoded Secrets

**Before:**
```yaml
services:
  postgres:
    environment:
      POSTGRES_USER: vbwd
      POSTGRES_PASSWORD: vbwd  # BAD: hardcoded
```

**After:**
```yaml
services:
  postgres:
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
```

### Full Updated docker-compose.yaml

```yaml
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: container/python/Dockerfile
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=${FLASK_ENV:-development}
      - SECRET_KEY=${SECRET_KEY}
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - DATABASE_URL=${DATABASE_URL:-postgresql://vbwd:vbwd@postgres:5432/vbwd}
      - REDIS_URL=${REDIS_URL:-redis://redis:6379/0}
      - SMTP_HOST=${SMTP_HOST:-}
      - SMTP_PORT=${SMTP_PORT:-587}
      - SMTP_USER=${SMTP_USER:-}
      - SMTP_PASSWORD=${SMTP_PASSWORD:-}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - ./src:/app/src:ro
      - ./tests:/app/tests:ro

  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-vbwd}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-vbwd}
      POSTGRES_DB: ${POSTGRES_DB:-vbwd}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-vbwd}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  python-test:
    build:
      context: .
      dockerfile: container/python/Dockerfile.test
    environment:
      - FLASK_ENV=testing
      - DATABASE_URL=sqlite:///:memory:
      - REDIS_URL=redis://redis:6379/1
    depends_on:
      - redis
    profiles:
      - test

volumes:
  postgres_data:
```

---

## 7.3 Create Production Compose Override

**File:** `docker-compose.production.yaml`
```yaml
version: '3.8'

# Production overrides
# Usage: docker-compose -f docker-compose.yaml -f docker-compose.production.yaml up -d

services:
  api:
    restart: always
    volumes: []  # No volume mounts in production
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M

  postgres:
    restart: always
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  redis:
    restart: always
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data

volumes:
  redis_data:
```

---

## 7.4 Update .gitignore

Ensure secrets are not committed:

```gitignore
# Environment files
.env
.env.local
.env.production
.env.*.local

# Keep examples
!.env.example
!.env.production.example

# Docker volumes (local dev)
postgres_data/
redis_data/
```

---

## 7.5 Add Startup Validation

**File:** `src/utils/startup_check.py`
```python
import os
import sys
import logging

logger = logging.getLogger(__name__)

REQUIRED_ENV_VARS = [
    'DATABASE_URL',
    'REDIS_URL',
]

REQUIRED_IN_PRODUCTION = [
    'SECRET_KEY',
    'JWT_SECRET_KEY',
]

def validate_environment():
    """Validate required environment variables are set."""
    missing = []

    for var in REQUIRED_ENV_VARS:
        if not os.environ.get(var):
            missing.append(var)

    if os.environ.get('FLASK_ENV') == 'production':
        for var in REQUIRED_IN_PRODUCTION:
            value = os.environ.get(var)
            if not value:
                missing.append(var)
            elif value in ('dev-secret-key', 'dev-secret-key-change-in-production'):
                logger.error(f"SECURITY: {var} is using default dev value in production!")
                missing.append(f"{var} (using insecure default)")

    if missing:
        logger.error(f"Missing required environment variables: {missing}")
        if os.environ.get('FLASK_ENV') == 'production':
            sys.exit(1)  # Exit in production
        else:
            logger.warning("Continuing in development mode with missing variables")

    return len(missing) == 0
```

**Update app.py:**
```python
from src.utils.startup_check import validate_environment

def create_app():
    validate_environment()
    # ... rest of app creation
```

---

## 7.6 Documentation

**File:** `docs/deployment.md`
```markdown
# Deployment Guide

## Environment Setup

1. Copy example environment file:
   ```bash
   cp .env.example .env
   ```

2. Generate secure secrets:
   ```bash
   # Generate SECRET_KEY
   python -c "import secrets; print(secrets.token_hex(32))"

   # Generate JWT_SECRET_KEY
   python -c "import secrets; print(secrets.token_hex(32))"

   # Generate POSTGRES_PASSWORD
   python -c "import secrets; print(secrets.token_urlsafe(24))"
   ```

3. Update .env with generated values

## Development

```bash
docker-compose up -d
```

## Production

```bash
# Use production overrides
docker-compose -f docker-compose.yaml -f docker-compose.production.yaml up -d
```

## Required Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| DATABASE_URL | Yes | PostgreSQL connection string |
| REDIS_URL | Yes | Redis connection string |
| SECRET_KEY | Production | Flask session encryption |
| JWT_SECRET_KEY | Production | JWT signing key |
| SMTP_* | Production | Email configuration |
```

---

## Checklist

### Environment Files
- [ ] .env.example updated
- [ ] .env.production.example created
- [ ] .gitignore updated

### Docker Configuration
- [ ] docker-compose.yaml uses env vars
- [ ] docker-compose.production.yaml created
- [ ] No hardcoded secrets

### Validation
- [ ] startup_check.py created
- [ ] App validates env on startup
- [ ] Production exits on missing secrets

### Documentation
- [ ] deployment.md created
- [ ] Secret generation instructions

---

## Verification

```bash
# Test with env file
cp .env.example .env
docker-compose up -d

# Verify no hardcoded secrets
grep -r "password" docker-compose.yaml | grep -v "\${"
# Should return nothing

# Test production validation
FLASK_ENV=production SECRET_KEY="" docker-compose run --rm api python -c "from src.utils.startup_check import validate_environment; validate_environment()"
# Should show error about missing SECRET_KEY
```
