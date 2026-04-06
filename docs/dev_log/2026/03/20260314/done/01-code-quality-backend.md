# Sprint: Code Quality — vbwd-backend

**Date:** 2026-03-14
**Ref:** `docs/dev_log/20260314/reports/01-code-quality-audit.md`

## Context

The code quality audit identified 9 categories of issues in the backend. This sprint addresses all of them in priority order. No new features — only internal quality, correctness, and consistency improvements.

## Core Requirements

TDD, SOLID, DI, DRY, LSP, DevOps First, clean code, no overengineering.

---

## Steps

### Step 1: Fix `datetime.utcnow()` Deprecation (DRY, Clean Code)

**Scope:** All files using `datetime.utcnow()` — models, services, migrations
**Count:** 15+ occurrences

Replace every occurrence with timezone-aware alternative:

```python
# Before (deprecated in Python 3.12)
from datetime import datetime
datetime.utcnow()

# After
from datetime import datetime, timezone
datetime.now(timezone.utc)
```

**Files to scan:**
```bash
grep -rn "datetime.utcnow()" src/ plugins/
```

Update any model `default=` and `onupdate=` kwargs that use lambdas:
```python
# Before
created_at = db.Column(db.DateTime, default=datetime.utcnow)
# After
created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
```

**Tests:** Existing tests must still pass. No new tests needed — this is a pure substitution.

---

### Step 2: Extract UUID Validation Utility (DRY, SOLID — Single Responsibility)

**Scope:** `src/routes/`, all plugin `src/routes.py` files

**Create:** `src/utils/validation.py`

```python
import uuid
from flask import jsonify

def parse_uuid_or_400(value: str, field_name: str = "id"):
    """Parse a UUID string; raises ValueError if invalid (caller returns 400)."""
    try:
        return uuid.UUID(str(value))
    except (ValueError, AttributeError):
        return None  # caller checks and returns 400

def require_uuid(value: str, field_name: str = "id"):
    """Parse UUID or abort with 400."""
    from flask import abort
    parsed = parse_uuid_or_400(value, field_name)
    if parsed is None:
        abort(400, description=f"Invalid {field_name} format")
    return parsed
```

**Replace** all inline UUID validation blocks with `require_uuid()`:
```python
# Before (repeated 5+ times)
try:
    uuid.UUID(str(some_id))
except ValueError:
    return jsonify({"error": "Invalid ID format"}), 400

# After
from src.utils.validation import require_uuid
some_id = require_uuid(raw_id)
```

**Tests:** `tests/unit/utils/test_validation.py`
- valid UUID string → returns UUID object
- invalid string → returns None / aborts 400
- None input → handled gracefully

---

### Step 3: Fix Bare Exception Suppression in GHRM Sync (Clean Code, DevOps First)

**Scope:** `plugins/ghrm/src/services/github_sync_service.py`

```python
# Before — silently swallows all failures
try:
    changelog = self.github_client.fetch_changelog(owner, repo)
except Exception:
    pass

# After — log and continue gracefully
import logging
logger = logging.getLogger(__name__)

try:
    changelog = self.github_client.fetch_changelog(owner, repo)
except Exception as exc:
    logger.warning(
        "fetch_changelog failed for %s/%s: %s",
        owner, repo, exc, exc_info=True
    )
    changelog = None
```

Apply same pattern for `fetch_readme` if similarly guarded.

**Tests:** `plugins/ghrm/tests/unit/services/test_github_sync_tabs.py`
Add case: when `fetch_changelog` raises, `sync.cached_changelog` is `None` and no exception propagates.

---

### Step 4: Hash Sync API Keys Before Storage (Security, SOLID — LSP on IGithubAppClient)

**Scope:** `plugins/ghrm/src/models/ghrm_software_sync.py`, `plugins/ghrm/src/services/`

The `sync_api_key` is currently stored and compared as plaintext.

**Create:** `src/utils/security.py`

```python
import hashlib, secrets

def generate_api_key() -> tuple[str, str]:
    """Returns (raw_key, hashed_key). Store hash, return raw to caller once."""
    raw = secrets.token_urlsafe(32)
    hashed = hashlib.sha256(raw.encode()).hexdigest()
    return raw, hashed

def verify_api_key(raw: str, stored_hash: str) -> bool:
    return hashlib.sha256(raw.encode()).hexdigest() == stored_hash
```

**Migration:** `alembic/versions/<timestamp>_hash_ghrm_sync_api_keys.py`
- Add `sync_api_key_hash VARCHAR(64)` column
- Populate from existing keys (re-hash current plaintext values)
- Drop `sync_api_key` column, rename `sync_api_key_hash` → `sync_api_key`

**Service changes:**
- `create_package()`: call `generate_api_key()`, store hash, return raw key once in response
- `verify_sync_key(package_slug, raw_key)`: load hash from DB, call `verify_api_key()`

**Tests:** `tests/unit/utils/test_security.py`
- `generate_api_key()` returns different raw keys on each call
- `verify_api_key(raw, hash)` → True
- `verify_api_key(wrong, hash)` → False
- Integration: POST `/ghrm/sync` with correct raw key → 200; wrong key → 401

---

### Step 5: Consolidate Dead Code — `deactivate_plan` / `archive_plan` (DRY, SOLID — SRP)

**Scope:** `src/services/plan_service.py` (or equivalent)

Both methods set `is_active = False`. If no semantic difference is intended:
- Delete `archive_plan`
- Rename all callers to use `deactivate_plan`

If semantic distinction is needed in future, introduce a `status` enum now:
```python
class PlanStatus(str, enum.Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    ARCHIVED = "archived"
```

Do NOT add this enum unless there is a real current use case — no overengineering.

**Tests:** Existing service tests must pass. Remove any tests for the deleted method.

---

### Step 6: Fix Direct `Model.query` Access in Admin Routes (SOLID — DI, LSP)

**Scope:** `src/routes/admin.py` — `UserTokenBalance.query` calls

All data access must go through a repository. Direct model queries bypass DI and are untestable.

**Create:** `src/repositories/user_token_balance_repository.py`

```python
from src.repositories.base import BaseRepository
from src.models.user_token_balance import UserTokenBalance

class UserTokenBalanceRepository(BaseRepository[UserTokenBalance]):
    def find_by_user_id(self, user_id) -> UserTokenBalance | None:
        return self.session.query(UserTokenBalance).filter_by(user_id=user_id).first()
```

**Wire in** `src/container.py` following existing repository pattern.

**Replace** in admin routes:
```python
# Before
balance = UserTokenBalance.query.filter_by(user_id=user_id).first()

# After (injected via factory function)
balance = token_balance_repo.find_by_user_id(user_id)
```

**Tests:** `tests/unit/repositories/test_user_token_balance_repository.py`
- `find_by_user_id` with known ID → returns model
- `find_by_user_id` with unknown ID → returns None

---

### Step 7: Fix Module-Level Import Inside Function Body (Clean Code, PEP 8)

**Scope:** Wherever `import re` (or any stdlib import) appears inside a function body in `plugins/`

```bash
grep -rn "^\s\+import " plugins/ src/
```

Move all imports to module top level. No logic changes.

**Tests:** None needed — linter (`flake8` via `make lint`) will catch regressions.

---

### Step 8: Enforce Service Factory Pattern in Routes (SOLID — DI, DevOps First)

**Scope:** `plugins/*/src/routes.py` files where services are instantiated at module level

Services must be instantiated inside request-scoped factory functions to avoid detached session errors:

```python
# Before — module level (wrong: session captured at import time)
_service = GhrmService(GhrmSoftwareRepository(db.session))

# After — factory function (correct: session resolved per-request)
def _get_service() -> GhrmService:
    return GhrmService(GhrmSoftwareRepository(db.session))
```

Apply to all plugin routes that have module-level service instantiation.

**Tests:** Integration tests (`make test-integration`) verify no `DetachedInstanceError` after this change.

---

### Step 9: Add README.md to All Backend Plugins

**Scope:** All 6+ backend plugins missing `README.md`

Each `plugins/<name>/README.md` must include:

```markdown
# Plugin Name

## Purpose
One paragraph: what problem this plugin solves.

## Configuration
| Key | Type | Default | Description |
|-----|------|---------|-------------|

## API Routes
| Method | Path | Auth | Description |
|--------|------|------|-------------|

## Events
Emits / consumes (platform event bus).

## Database
Tables owned. Migration file reference.

## Frontend Bundle
Links to fe-admin and fe-user plugin counterparts.

## Testing
```bash
docker compose run --rm test python -m pytest plugins/<name>/tests/ -v
```
```

Plugins requiring READMEs: `cms`, `ghrm`, `taro`, `stripe`, `github-oauth`, `webhooks`.

---

## Verification

```bash
# In vbwd-backend/
./bin/pre-commit-check.sh          # lint only (fast)
./bin/pre-commit-check.sh --quick  # lint + unit
./bin/pre-commit-check.sh          # full: lint + unit + integration
```

All checks must be green before merging. Specifically:
1. `make lint` — no flake8 warnings, mypy passes, black format clean
2. `make test-unit` — all unit tests pass including new ones from Steps 2, 3, 4, 6
3. `make test-integration` — no `DetachedInstanceError`, sync API key verification works
4. Manual: `POST /api/v1/ghrm/sync?package=<slug>&key=<raw_key>` → 200 (hashed key verification)
5. Manual: same with wrong key → 401
